#include <gtest/gtest.h>

#include <chrono>
#include <cstdint>
#include <thread>
#include <vector>

#include "aegis_spark.h"

class HalosMailboxSpscTest : public ::testing::Test {
 protected:
  void SetUp() override {
    enum halos_mailbox_status const rc = aegis_mailbox_init(&channel_, 1U);
    ASSERT_EQ(rc, HALOS_MBX_OK);
  }

  alignas(64) struct aegis_mailbox_channel channel_{};
};

TEST_F(HalosMailboxSpscTest, InitChannelValidation) {
  EXPECT_EQ(channel_.config.magic, AEGIS_MAILBOX_MAGIC);
  EXPECT_EQ(channel_.config.version, AEGIS_MAILBOX_VERSION);
  EXPECT_EQ(channel_.config.capacity, AEGIS_MAILBOX_CAPACITY);
  EXPECT_EQ(channel_.config.channel_id, 1U);
  EXPECT_EQ(channel_.producer.push_count, 0U);
  EXPECT_EQ(channel_.consumer.pop_count, 0U);
  EXPECT_EQ(channel_.producer.full_drops, 0U);
  EXPECT_EQ(channel_.consumer.crc_errors, 0U);
}

TEST_F(HalosMailboxSpscTest, EmptyChannelReturnsEmpty) {
  struct halos_mailbox_msg popped_msg{};
  enum halos_mailbox_status const rc =
      aegis_mailbox_try_pop(&channel_, 1'000'000ULL, &popped_msg);
  EXPECT_EQ(rc, HALOS_MBX_ERR_EMPTY);
}

TEST_F(HalosMailboxSpscTest, SingleMessagePushAndPop) {
  struct halos_trajectory_payload payload{};
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    payload.position_rad[i] = static_cast<float>(i) * 0.1F;
    payload.velocity_rad_s[i] = 1.0F;
    payload.torque_nm[i] = 5.0F;
    payload.acceleration_rad_s2[i] = 0.5F;
  }

  uint64_t const send_ts = 1'000'000ULL;
  enum halos_mailbox_status rc = aegis_mailbox_try_push(
      &channel_, HALOS_MSG_KINEMATIC_CMD, 0U, send_ts, &payload);
  EXPECT_EQ(rc, HALOS_MBX_OK);

  struct halos_mailbox_msg pop_msg{};
  uint64_t const pop_ts = send_ts + 100'000ULL;  // +0.1 ms (well within 5 ms)
  rc = aegis_mailbox_try_pop(&channel_, pop_ts, &pop_msg);
  EXPECT_EQ(rc, HALOS_MBX_OK);

  EXPECT_EQ(pop_msg.header.sequence_id, 0ULL);
  EXPECT_EQ(pop_msg.header.timestamp_ns, send_ts);
  EXPECT_EQ(pop_msg.header.msg_type, HALOS_MSG_KINEMATIC_CMD);
  EXPECT_EQ(pop_msg.header.crc32, aegis_mailbox_crc32(&payload));

  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(pop_msg.payload.position_rad[i],
                    static_cast<float>(i) * 0.1F);
    EXPECT_FLOAT_EQ(pop_msg.payload.velocity_rad_s[i], 1.0F);
    EXPECT_FLOAT_EQ(pop_msg.payload.torque_nm[i], 5.0F);
    EXPECT_FLOAT_EQ(pop_msg.payload.acceleration_rad_s2[i], 0.5F);
  }

  // Queue is empty again
  rc = aegis_mailbox_try_pop(&channel_, pop_ts, &pop_msg);
  EXPECT_EQ(rc, HALOS_MBX_ERR_EMPTY);
}

TEST_F(HalosMailboxSpscTest, QueueCapacityAndFullHandling) {
  struct halos_trajectory_payload payload{};

  // Capacity is 16 slots. Push until full.
  uint32_t pushed_count = 0;
  for (uint64_t i = 0; i < AEGIS_MAILBOX_CAPACITY + 4; ++i) {
    uint64_t const now_ns = 1'000'000ULL + i * 10'000ULL;
    enum halos_mailbox_status const rc = aegis_mailbox_try_push(
        &channel_, HALOS_MSG_TORQUE_CMD, 0U, now_ns, &payload);
    if (rc == HALOS_MBX_OK) {
      ++pushed_count;
    } else {
      EXPECT_EQ(rc, HALOS_MBX_ERR_FULL);
    }
  }

  EXPECT_EQ(pushed_count, AEGIS_MAILBOX_CAPACITY);
  EXPECT_EQ(channel_.producer.full_drops, 4U);

  // Pop all 16 messages
  for (uint64_t i = 0; i < pushed_count; ++i) {
    struct halos_mailbox_msg popped{};
    uint64_t const now_ns = 1'000'000ULL + i * 10'000ULL + 50'000ULL;
    enum halos_mailbox_status const rc =
        aegis_mailbox_try_pop(&channel_, now_ns, &popped);
    EXPECT_EQ(rc, HALOS_MBX_OK);
    EXPECT_EQ(popped.header.sequence_id, i);
  }

  // Now empty
  struct halos_mailbox_msg empty_msg{};
  EXPECT_EQ(aegis_mailbox_try_pop(&channel_, 2'000'000ULL, &empty_msg),
            HALOS_MBX_ERR_EMPTY);
}

TEST_F(HalosMailboxSpscTest, RejectsCorruptChannelMagic) {
  channel_.config.magic = 0xDEADBEEFULL;

  struct halos_trajectory_payload payload{};
  struct halos_mailbox_msg msg{};
  EXPECT_EQ(aegis_mailbox_try_push(&channel_, HALOS_MSG_TORQUE_CMD, 0U,
                                   1'000'000ULL, &payload),
            HALOS_MBX_ERR_CORRUPT_MAGIC);
  EXPECT_EQ(aegis_mailbox_try_pop(&channel_, 1'000'000ULL, &msg),
            HALOS_MBX_ERR_CORRUPT_MAGIC);
}

TEST_F(HalosMailboxSpscTest, ConcurrentHighThroughputStreaming) {
  // Concurrent SPSC test using C++20/C++23 std::jthread
  // Stream 10,000 commands between untrusted producer and trusted FSI consumer
  constexpr uint64_t kMessageCount = 10'000ULL;
  std::vector<uint64_t> received_sequences;
  received_sequences.reserve(kMessageCount);

  // Consumer thread
  std::jthread consumer([this, &received_sequences]() {
    uint64_t count = 0;
    while (count < kMessageCount) {
      struct halos_mailbox_msg msg{};
      // Timestamp simulated to always be fresh relative to message timestamp
      uint64_t const now_ns = (count + 1ULL) * 1'000ULL + 100ULL;
      enum halos_mailbox_status const rc =
          aegis_mailbox_try_pop(&channel_, now_ns, &msg);
      if (rc == HALOS_MBX_OK) {
        // Verify CRC integrity
        uint32_t const expected_crc = aegis_mailbox_crc32(&msg.payload);
        EXPECT_EQ(msg.header.crc32, expected_crc);

        received_sequences.push_back(msg.header.sequence_id);
        ++count;
      } else {
        std::this_thread::yield();
      }
    }
  });

  // Producer thread
  std::jthread producer([this]() {
    struct halos_trajectory_payload payload{};

    for (uint64_t seq = 0; seq < kMessageCount; ++seq) {
      uint64_t const now_ns = (seq + 1ULL) * 1'000ULL;
      for (size_t j = 0; j < HALOS_DOF_COUNT; ++j) {
        payload.position_rad[j] = static_cast<float>(seq) * 0.001F;
        payload.velocity_rad_s[j] = 1.0F;
        payload.torque_nm[j] = 2.0F;
        payload.acceleration_rad_s2[j] = 0.1F;
      }

      // Push with spin-retry if buffer is temporarily full
      while (aegis_mailbox_try_push(&channel_, HALOS_MSG_KINEMATIC_CMD, 0U,
                                    now_ns, &payload) == HALOS_MBX_ERR_FULL) {
        std::this_thread::yield();
      }
    }
  });

  // jthreads automatically join on destruction at scope exit
  producer.join();
  consumer.join();

  // Verify all 10,000 messages were received strictly in order with zero loss
  ASSERT_EQ(received_sequences.size(), kMessageCount);
  for (uint64_t i = 0; i < kMessageCount; ++i) {
    EXPECT_EQ(received_sequences[i], i);
  }
}
