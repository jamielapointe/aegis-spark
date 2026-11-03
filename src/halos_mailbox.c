#include "halos_mailbox.h"

#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

// Static Host SIL simulation channel instance (64-byte cache line aligned)
// NOLINTBEGIN(cppcoreguidelines-avoid-non-const-global-variables)
alignas(64) struct aegis_mailbox_channel aegis_sim_mailbox = {};
// NOLINTEND(cppcoreguidelines-avoid-non-const-global-variables)

uint32_t aegis_mailbox_crc32(const struct halos_trajectory_payload* payload) {
  if (payload == nullptr) {
    return 0U;
  }

  const uint8_t* bytes = (const uint8_t*)payload;
  uint32_t crc = 0xFFFFFFFFU;

  for (size_t i = 0U; i < sizeof(struct halos_trajectory_payload); ++i) {
    crc ^= (uint32_t)bytes[i];
    for (size_t bit = 0U; bit < 8U; ++bit) {
      if ((crc & 1U) != 0U) {
        crc = (crc >> 1U) ^ 0xEDB88320U;
      } else {
        crc >>= 1U;
      }
    }
  }

  return crc ^ 0xFFFFFFFFU;
}

enum halos_mailbox_status aegis_mailbox_init(struct aegis_mailbox_channel* chan,
                                             uint32_t channel_id) {
  if (chan == nullptr) {
    return HALOS_MBX_ERR_NULL_PTR;
  }

  if (((uintptr_t)chan % 64U) != 0U) {
    return HALOS_MBX_ERR_UNALIGNED;
  }

  memset(chan, 0, sizeof(struct aegis_mailbox_channel));

  chan->config.magic = AEGIS_MAILBOX_MAGIC;
  chan->config.version = AEGIS_MAILBOX_VERSION;
  chan->config.capacity = AEGIS_MAILBOX_CAPACITY;
  chan->config.slot_size = AEGIS_MAILBOX_SLOT_SIZE;
  chan->config.channel_id = channel_id;

  atomic_init(&chan->producer.tail, 0U);
  atomic_init(&chan->consumer.head, 0U);

  return HALOS_MBX_OK;
}

// NOLINTBEGIN(bugprone-easily-swappable-parameters)
enum halos_mailbox_status aegis_mailbox_try_push(
    struct aegis_mailbox_channel* chan, enum halos_msg_type msg_type,
    uint32_t flags, uint64_t now_ns,
    const struct halos_trajectory_payload* payload) {
  // NOLINTEND(bugprone-easily-swappable-parameters)
  if (chan == nullptr || payload == nullptr) {
    return HALOS_MBX_ERR_NULL_PTR;
  }

  if (chan->config.magic != AEGIS_MAILBOX_MAGIC) {
    return HALOS_MBX_ERR_CORRUPT_MAGIC;
  }

  if (chan->config.version != AEGIS_MAILBOX_VERSION) {
    return HALOS_MBX_ERR_VERSION_MISMATCH;
  }

  if (msg_type == HALOS_MSG_NONE || msg_type > HALOS_MSG_EMERGENCY_STOP) {
    return HALOS_MBX_ERR_INVALID_MSG_TYPE;
  }

  uint64_t tail =
      atomic_load_explicit(&chan->producer.tail, memory_order_relaxed);
  uint64_t cached_head = chan->producer.cached_head;

  if ((tail - cached_head) >= AEGIS_MAILBOX_CAPACITY) {
    cached_head =
        atomic_load_explicit(&chan->consumer.head, memory_order_acquire);
    chan->producer.cached_head = cached_head;
    if ((tail - cached_head) >= AEGIS_MAILBOX_CAPACITY) {
      chan->producer.full_drops++;
      return HALOS_MBX_ERR_FULL;
    }
  }

  uint32_t slot_idx = (uint32_t)(tail & (AEGIS_MAILBOX_CAPACITY - 1U));
  struct halos_mailbox_msg* slot = &chan->slots[slot_idx];

  slot->payload = *payload;
  slot->header.sequence_id = tail;
  slot->header.timestamp_ns = now_ns;
  slot->header.msg_type = msg_type;
  slot->header.flags = flags | (uint32_t)HALOS_MBX_FLAG_VALID;
  slot->header.crc32 = aegis_mailbox_crc32(payload);
  slot->header.reserved = 0U;

  atomic_store_explicit(&chan->producer.tail, tail + 1U, memory_order_release);
  chan->producer.push_count++;

  return HALOS_MBX_OK;
}

enum halos_mailbox_status aegis_mailbox_try_pop(
    struct aegis_mailbox_channel* chan, uint64_t now_ns,
    struct halos_mailbox_msg* msg_out) {
  if (chan == nullptr || msg_out == nullptr) {
    return HALOS_MBX_ERR_NULL_PTR;
  }

  if (chan->config.magic != AEGIS_MAILBOX_MAGIC) {
    return HALOS_MBX_ERR_CORRUPT_MAGIC;
  }

  if (chan->config.version != AEGIS_MAILBOX_VERSION) {
    return HALOS_MBX_ERR_VERSION_MISMATCH;
  }

  uint64_t head =
      atomic_load_explicit(&chan->consumer.head, memory_order_relaxed);
  uint64_t cached_tail = chan->consumer.cached_tail;

  if (head == cached_tail) {
    cached_tail =
        atomic_load_explicit(&chan->producer.tail, memory_order_acquire);
    chan->consumer.cached_tail = cached_tail;
    if (head == cached_tail) {
      return HALOS_MBX_ERR_EMPTY;
    }
  }

  uint32_t slot_idx = (uint32_t)(head & (AEGIS_MAILBOX_CAPACITY - 1U));
  const struct halos_mailbox_msg* slot = &chan->slots[slot_idx];
  *msg_out = *slot;

  if (msg_out->header.sequence_id != head) {
    chan->consumer.seq_gaps++;
    return HALOS_MBX_ERR_SEQ_GAP;
  }

  if ((msg_out->header.flags & (uint32_t)HALOS_MBX_FLAG_VALID) == 0U) {
    return HALOS_MBX_ERR_INVALID_PAYLOAD;
  }

  uint32_t expected_crc = aegis_mailbox_crc32(&msg_out->payload);
  if (msg_out->header.crc32 != expected_crc) {
    chan->consumer.crc_errors++;
    return HALOS_MBX_ERR_CRC_MISMATCH;
  }

  if (now_ns < msg_out->header.timestamp_ns ||
      (now_ns - msg_out->header.timestamp_ns) > 5000000ULL) {
    return HALOS_MBX_ERR_STALE_TIMESTAMP;
  }

  atomic_store_explicit(&chan->consumer.head, head + 1U, memory_order_release);
  chan->consumer.pop_count++;

  return HALOS_MBX_OK;
}
