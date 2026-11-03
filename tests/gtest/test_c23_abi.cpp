#include <gtest/gtest.h>

#include <cstddef>
#include <cstdint>

#include "aegis_spark.h"

// =============================================================================
// Compile-Time Layout & ABI Parity Assertions (ISO C23 / C++23)
// =============================================================================

// Halos_Status enum ABI parity
static_assert(sizeof(enum halos_status) == 4U,
              "ABI requires 32-bit Halos_Status enum");
static_assert(alignof(enum halos_status) == 4U,
              "ABI requires 4-byte aligned Halos_Status enum");

// Halos_Safety_State enum ABI parity
static_assert(sizeof(enum halos_safety_state) == 1U,
              "ABI requires 8-bit Halos_Safety_State enum");
static_assert(alignof(enum halos_safety_state) == 1U,
              "ABI requires 1-byte aligned Halos_Safety_State enum");

// Halos_Log_Status enum ABI parity
static_assert(sizeof(enum halos_log_status) == 4U,
              "ABI requires 32-bit Halos_Log_Status enum");
static_assert(alignof(enum halos_log_status) == 4U,
              "ABI requires 4-byte aligned Halos_Log_Status enum");

// Halos_Joint_Cmd struct ABI parity
static_assert(sizeof(struct halos_joint_cmd) == 32U,
              "ABI requires 32-byte halos_joint_cmd struct");
static_assert(alignof(struct halos_joint_cmd) == 8U,
              "ABI requires 8-byte aligned halos_joint_cmd struct");
static_assert(offsetof(struct halos_joint_cmd, timestamp_ns) == 0U,
              "timestamp_ns offset mismatch");
static_assert(offsetof(struct halos_joint_cmd, desired_torque_nm) == 8U,
              "desired_torque_nm offset mismatch");

// Halos_Safety_Envelope struct ABI parity
static_assert(sizeof(struct halos_safety_envelope) == 28U,
              "ABI requires 28-byte halos_safety_envelope struct");
static_assert(alignof(struct halos_safety_envelope) == 4U,
              "ABI requires 4-byte aligned halos_safety_envelope struct");
static_assert(offsetof(struct halos_safety_envelope, max_abs_torque_nm) == 0U,
              "max_abs_torque_nm offset mismatch");
static_assert(offsetof(struct halos_safety_envelope, state) == 24U,
              "state offset mismatch");

// Mock MMIO Register Struct ABI parity
static_assert(sizeof(struct aegis_uart_data_reg) == 4U,
              "ABI requires 4-byte aegis_uart_data_reg");
static_assert(alignof(struct aegis_uart_data_reg) == 4U,
              "ABI requires 4-byte aligned aegis_uart_data_reg");
static_assert(sizeof(struct aegis_uart_status_reg) == 4U,
              "ABI requires 4-byte aegis_uart_status_reg");
static_assert(alignof(struct aegis_uart_status_reg) == 4U,
              "ABI requires 4-byte aligned aegis_uart_status_reg");
static_assert(sizeof(struct aegis_uart_ctrl_reg) == 4U,
              "ABI requires 4-byte aegis_uart_ctrl_reg");
static_assert(alignof(struct aegis_uart_ctrl_reg) == 4U,
              "ABI requires 4-byte aligned aegis_uart_ctrl_reg");

// =============================================================================
// Phase 4: Watchdog, HSM, Kinematics, Mailbox ABI Parity
// =============================================================================

// Watchdog
static_assert(sizeof(enum halos_watchdog_status) == 4U,
              "ABI requires 32-bit halos_watchdog_status");
static_assert(sizeof(struct halos_watchdog_config) == 16U,
              "ABI requires 16-byte halos_watchdog_config");
static_assert(alignof(struct halos_watchdog_config) == 8U,
              "ABI requires 8-byte aligned halos_watchdog_config");
static_assert(sizeof(struct halos_watchdog_device) == 40U,
              "ABI requires 40-byte halos_watchdog_device");
static_assert(alignof(struct halos_watchdog_device) == 8U,
              "ABI requires 8-byte aligned halos_watchdog_device");

// HSM
static_assert(sizeof(enum halos_hsm_state) == 4U,
              "ABI requires 32-bit halos_hsm_state");
static_assert(alignof(enum halos_hsm_state) == 4U,
              "ABI requires 4-byte aligned halos_hsm_state");
static_assert(sizeof(enum halos_hsm_event) == 4U,
              "ABI requires 32-bit halos_hsm_event");
static_assert(alignof(enum halos_hsm_event) == 4U,
              "ABI requires 4-byte aligned halos_hsm_event");
static_assert(sizeof(enum halos_fault_code) == 4U,
              "ABI requires 32-bit halos_fault_code");
static_assert(alignof(enum halos_fault_code) == 4U,
              "ABI requires 4-byte aligned halos_fault_code");
static_assert(sizeof(enum halos_hsm_status) == 4U,
              "ABI requires 32-bit halos_hsm_status");
static_assert(alignof(enum halos_hsm_status) == 4U,
              "ABI requires 4-byte aligned halos_hsm_status");
static_assert(sizeof(struct halos_hsm_instance) == 16U,
              "ABI requires 16-byte halos_hsm_instance");
static_assert(alignof(struct halos_hsm_instance) == 8U,
              "ABI requires 8-byte aligned halos_hsm_instance");

// Kinematics
static_assert(sizeof(struct halos_kinematic_limits) == 96U,
              "ABI requires 96-byte halos_kinematic_limits");
static_assert(alignof(struct halos_kinematic_limits) == 4U,
              "ABI requires 4-byte aligned halos_kinematic_limits");
static_assert(sizeof(struct halos_kinematic_cmd) == 80U,
              "ABI requires 80-byte halos_kinematic_cmd");
static_assert(alignof(struct halos_kinematic_cmd) == 8U,
              "ABI requires 8-byte aligned halos_kinematic_cmd");
static_assert(sizeof(struct halos_kinematic_state) == 192U,
              "ABI requires 192-byte halos_kinematic_state");
static_assert(alignof(struct halos_kinematic_state) == 8U,
              "ABI requires 8-byte aligned halos_kinematic_state");

// Composed Gate
static_assert(sizeof(struct halos_composed_gate) == 248U,
              "ABI requires 248-byte halos_composed_gate");
static_assert(alignof(struct halos_composed_gate) == 8U,
              "ABI requires 8-byte aligned halos_composed_gate");

// SPSC Mailbox
static_assert(sizeof(struct halos_mailbox_header) == 32U,
              "ABI requires 32-byte halos_mailbox_header");
static_assert(alignof(struct halos_mailbox_header) == 8U,
              "ABI requires 8-byte aligned halos_mailbox_header");
static_assert(sizeof(struct halos_trajectory_payload) == 96U,
              "ABI requires 96-byte halos_trajectory_payload");
static_assert(alignof(struct halos_trajectory_payload) == 4U,
              "ABI requires 4-byte aligned halos_trajectory_payload");
static_assert(sizeof(struct halos_mailbox_msg) == 128U,
              "ABI requires 128-byte halos_mailbox_msg");
static_assert(alignof(struct halos_mailbox_msg) == 8U,
              "ABI requires 8-byte aligned halos_mailbox_msg");
static_assert(sizeof(struct aegis_mailbox_config) == 64U,
              "ABI requires 64-byte aegis_mailbox_config");
static_assert(alignof(struct aegis_mailbox_config) == 64U,
              "ABI requires 64-byte aligned aegis_mailbox_config");
static_assert(sizeof(struct aegis_mailbox_producer) == 64U,
              "ABI requires 64-byte aegis_mailbox_producer");
static_assert(alignof(struct aegis_mailbox_producer) == 64U,
              "ABI requires 64-byte aligned aegis_mailbox_producer");
static_assert(sizeof(struct aegis_mailbox_consumer) == 64U,
              "ABI requires 64-byte aegis_mailbox_consumer");
static_assert(alignof(struct aegis_mailbox_consumer) == 64U,
              "ABI requires 64-byte aligned aegis_mailbox_consumer");
static_assert(sizeof(struct aegis_mailbox_channel) == 2304U,
              "ABI requires 2304-byte aegis_mailbox_channel");
static_assert(alignof(struct aegis_mailbox_channel) == 64U,
              "ABI requires 64-byte aligned aegis_mailbox_channel");

TEST(C23AbiTest, EnumValueParity) {
  EXPECT_EQ(HALOS_OK, 0);
  EXPECT_EQ(HALOS_ERR_NOT_ACTIVE, 1);
  EXPECT_EQ(HALOS_ERR_STALE_HEARTBEAT, 2);
  EXPECT_EQ(HALOS_ERR_NON_FINITE_INPUT, 3);
  EXPECT_EQ(HALOS_ERR_TORQUE_LIMIT_EXCEEDED, 4);

  EXPECT_EQ(HALOS_STATE_INIT, 0);
  EXPECT_EQ(HALOS_STATE_ACTIVE, 1);
  EXPECT_EQ(HALOS_STATE_FAULT_ESTOP, 2);

  EXPECT_EQ(HALOS_LOG_OK, 0);
  EXPECT_EQ(HALOS_LOG_ERR_NULL_PTR, -1);
  EXPECT_EQ(HALOS_LOG_ERR_IO, -2);

  // Watchdog Enums
  EXPECT_EQ(WD_OK, 0);
  EXPECT_EQ(WD_ERR_NOT_ARMED, 1);
  EXPECT_EQ(WD_ERR_TOO_EARLY, 2);
  EXPECT_EQ(WD_ERR_TOO_LATE, 3);
  EXPECT_EQ(WD_ERR_TIME_REWIND, 4);
  EXPECT_EQ(WD_ERR_INVALID_CONFIG, 5);
  EXPECT_EQ(WD_ERR_INVALID_KEY, 6);

  // HSM Enums
  EXPECT_EQ(HALOS_HSM_BOOT, 0);
  EXPECT_EQ(HALOS_HSM_ACTIVE, 1);
  EXPECT_EQ(HALOS_HSM_DEGRADED, 2);
  EXPECT_EQ(HALOS_HSM_FAULT_ESTOP, 3);

  EXPECT_EQ(HALOS_EVENT_NONE, 0);
  EXPECT_EQ(HALOS_EVENT_SELF_TEST_PASSED, 1);
  EXPECT_EQ(HALOS_EVENT_SELF_TEST_FAILED, 2);
  EXPECT_EQ(HALOS_EVENT_DEGRADE_REQUESTED, 3);
  EXPECT_EQ(HALOS_EVENT_RECOVER_NOMINAL, 4);
  EXPECT_EQ(HALOS_EVENT_FAULT_DETECTED, 5);
  EXPECT_EQ(HALOS_EVENT_RESET_REQUESTED, 6);

  EXPECT_EQ(HALOS_FAULT_NONE, 0);
  EXPECT_EQ(HALOS_FAULT_WATCHDOG_TIMEOUT, 1);
  EXPECT_EQ(HALOS_FAULT_WATCHDOG_EARLY_PET, 2);
  EXPECT_EQ(HALOS_FAULT_WATCHDOG_CLOCK_REWIND, 3);
  EXPECT_EQ(HALOS_FAULT_KINEMATIC_POSITION, 4);
  EXPECT_EQ(HALOS_FAULT_KINEMATIC_VELOCITY, 5);
  EXPECT_EQ(HALOS_FAULT_KINEMATIC_TORQUE, 6);
  EXPECT_EQ(HALOS_FAULT_KINEMATIC_JERK, 7);
  EXPECT_EQ(HALOS_FAULT_NON_FINITE_INPUT, 8);
  EXPECT_EQ(HALOS_FAULT_HARDWARE_BIST, 9);

  EXPECT_EQ(HALOS_HSM_OK, 0);
  EXPECT_EQ(HALOS_HSM_ERR_INVALID_TRANSITION, 1);
  EXPECT_EQ(HALOS_HSM_ERR_INVALID_KEY, 2);
  EXPECT_EQ(HALOS_HSM_ERR_ALREADY_IN_STATE, 3);

  // Mailbox Enums
  EXPECT_EQ(HALOS_MBX_OK, 0);
  EXPECT_EQ(HALOS_MBX_ERR_EMPTY, 1);
  EXPECT_EQ(HALOS_MBX_ERR_FULL, 2);
  EXPECT_EQ(HALOS_MBX_ERR_NULL_PTR, 3);
  EXPECT_EQ(HALOS_MBX_ERR_UNALIGNED, 4);
  EXPECT_EQ(HALOS_MBX_ERR_CORRUPT_MAGIC, 5);
  EXPECT_EQ(HALOS_MBX_ERR_VERSION_MISMATCH, 6);
  EXPECT_EQ(HALOS_MBX_ERR_SEQ_GAP, 7);
  EXPECT_EQ(HALOS_MBX_ERR_OVERRUN, 8);
  EXPECT_EQ(HALOS_MBX_ERR_CRC_MISMATCH, 9);
}

TEST(C23AbiTest, StructConstants) {
  EXPECT_EQ(HALOS_DOF_COUNT, 6U);
  EXPECT_EQ(HALOS_WD_RESET_MAGIC, 0x57444752U);
  EXPECT_EQ(HALOS_HSM_RESET_MAGIC, 0x48534D52U);
  EXPECT_EQ(AEGIS_MAILBOX_MAGIC, 0x41454749534D4258ULL);
  EXPECT_EQ(AEGIS_MAILBOX_VERSION, 1U);
  EXPECT_EQ(AEGIS_MAILBOX_CAPACITY, 16U);
  EXPECT_EQ(AEGIS_MAILBOX_SLOT_SIZE, 128U);
}
