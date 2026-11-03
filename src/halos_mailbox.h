#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
#include <atomic>
using aegis_atomic_u64 = std::atomic<uint64_t>;
extern "C" {
#else
#include <stdatomic.h>
typedef _Atomic uint64_t aegis_atomic_u64;
#endif

static constexpr uint64_t AEGIS_MAILBOX_MAGIC =
    0x41454749534D4258ULL;  // "AEGISMBX"
static constexpr uint32_t AEGIS_MAILBOX_VERSION = 1U;
static constexpr uint32_t AEGIS_MAILBOX_CAPACITY = 16U;
static constexpr uint32_t AEGIS_MAILBOX_SLOT_SIZE = 128U;
#ifndef HALOS_DOF_COUNT_DEFINED
#define HALOS_DOF_COUNT_DEFINED
static constexpr size_t HALOS_DOF_COUNT = 6U;
#endif

enum halos_msg_type : uint32_t {
  HALOS_MSG_NONE = 0U,
  HALOS_MSG_TORQUE_CMD = 1U,
  HALOS_MSG_KINEMATIC_CMD = 2U,
  HALOS_MSG_HEARTBEAT_PET = 3U,
  HALOS_MSG_RESET_FAULT = 4U,
  HALOS_MSG_EMERGENCY_STOP = 5U,
};

enum halos_mailbox_flags : uint32_t {
  HALOS_MBX_FLAG_NONE = 0U,
  HALOS_MBX_FLAG_VALID = (1U << 0),
  HALOS_MBX_FLAG_ACK_REQ = (1U << 1),
  HALOS_MBX_FLAG_DEGRADED = (1U << 2),
  HALOS_MBX_FLAG_ESTOP = (1U << 3),
};

enum halos_mailbox_status : int32_t {
  HALOS_MBX_OK = 0,
  HALOS_MBX_ERR_EMPTY = 1,
  HALOS_MBX_ERR_FULL = 2,
  HALOS_MBX_ERR_NULL_PTR = 3,
  HALOS_MBX_ERR_UNALIGNED = 4,
  HALOS_MBX_ERR_CORRUPT_MAGIC = 5,
  HALOS_MBX_ERR_VERSION_MISMATCH = 6,
  HALOS_MBX_ERR_SEQ_GAP = 7,
  HALOS_MBX_ERR_OVERRUN = 8,
  HALOS_MBX_ERR_CRC_MISMATCH = 9,
  HALOS_MBX_ERR_INVALID_PAYLOAD = 10,
  HALOS_MBX_ERR_STALE_TIMESTAMP = 11,
  HALOS_MBX_ERR_INVALID_MSG_TYPE = 12,
};

struct halos_mailbox_header {
  uint64_t sequence_id;
  uint64_t timestamp_ns;
  enum halos_msg_type msg_type;
  uint32_t flags;
  uint32_t crc32;
  uint32_t reserved;
};

struct halos_trajectory_payload {
  float position_rad[HALOS_DOF_COUNT];
  float velocity_rad_s[HALOS_DOF_COUNT];
  float torque_nm[HALOS_DOF_COUNT];
  float acceleration_rad_s2[HALOS_DOF_COUNT];
};

struct halos_mailbox_msg {
  struct halos_mailbox_header header;
  struct halos_trajectory_payload payload;
};

struct aegis_mailbox_config {
  alignas(64) uint64_t magic;
  uint32_t version;
  uint32_t capacity;
  uint32_t slot_size;
  uint32_t channel_id;
  uint8_t reserved[40];
};

struct aegis_mailbox_producer {
  alignas(64) aegis_atomic_u64 tail;
  uint64_t cached_head;
  uint64_t push_count;
  uint64_t full_drops;
  uint8_t reserved[32];
};

struct aegis_mailbox_consumer {
  alignas(64) aegis_atomic_u64 head;
  uint64_t cached_tail;
  uint64_t pop_count;
  uint64_t crc_errors;
  uint64_t seq_gaps;
  uint8_t reserved[24];
};

struct aegis_mailbox_channel {
  struct aegis_mailbox_config config;
  struct aegis_mailbox_producer producer;
  struct aegis_mailbox_consumer consumer;
  alignas(64) uint8_t reserved_line[64];
  alignas(64) struct halos_mailbox_msg slots[AEGIS_MAILBOX_CAPACITY];
};

// C23 Static Assertions for Layout and Alignment Parity
static_assert(sizeof(struct halos_mailbox_header) == 32U,
              "Header size mismatch");
static_assert(alignof(struct halos_mailbox_header) == 8U,
              "Header alignment mismatch");
static_assert(sizeof(struct halos_trajectory_payload) == 96U,
              "Payload size mismatch");
static_assert(alignof(struct halos_trajectory_payload) == 4U,
              "Payload alignment mismatch");
static_assert(sizeof(struct halos_mailbox_msg) == 128U,
              "Message size mismatch");
static_assert(alignof(struct halos_mailbox_msg) == 8U,
              "Message alignment mismatch");
static_assert(sizeof(struct aegis_mailbox_config) == 64U,
              "Config size mismatch");
static_assert(alignof(struct aegis_mailbox_config) == 64U,
              "Config alignment mismatch");
static_assert(sizeof(struct aegis_mailbox_producer) == 64U,
              "Producer size mismatch");
static_assert(alignof(struct aegis_mailbox_producer) == 64U,
              "Producer alignment mismatch");
static_assert(sizeof(struct aegis_mailbox_consumer) == 64U,
              "Consumer size mismatch");
static_assert(alignof(struct aegis_mailbox_consumer) == 64U,
              "Consumer alignment mismatch");
static_assert(sizeof(struct aegis_mailbox_channel) == 2304U,
              "Channel size mismatch");
static_assert(alignof(struct aegis_mailbox_channel) == 64U,
              "Channel alignment mismatch");

// Exported Host SIL simulation channel instance
// NOLINTBEGIN(cppcoreguidelines-avoid-non-const-global-variables)
extern struct aegis_mailbox_channel aegis_sim_mailbox;
// NOLINTEND(cppcoreguidelines-avoid-non-const-global-variables)

// Producer & Channel APIs (C23)
[[nodiscard]] enum halos_mailbox_status aegis_mailbox_init(
    struct aegis_mailbox_channel* chan, uint32_t channel_id);

// NOLINTBEGIN(bugprone-easily-swappable-parameters)
[[nodiscard]] enum halos_mailbox_status aegis_mailbox_try_push(
    struct aegis_mailbox_channel* chan, enum halos_msg_type msg_type,
    uint32_t flags, uint64_t now_ns,
    const struct halos_trajectory_payload* payload);
// NOLINTEND(bugprone-easily-swappable-parameters)

[[nodiscard]] enum halos_mailbox_status aegis_mailbox_try_pop(
    struct aegis_mailbox_channel* chan, uint64_t now_ns,
    struct halos_mailbox_msg* msg_out);

[[nodiscard]] uint32_t aegis_mailbox_crc32(
    const struct halos_trajectory_payload* payload);

#ifdef __cplusplus
}
#endif
