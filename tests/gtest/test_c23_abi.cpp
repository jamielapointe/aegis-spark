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
static_assert(sizeof(struct aegis_uart_status_reg) == 4U,
              "ABI requires 4-byte aegis_uart_status_reg");
static_assert(sizeof(struct aegis_uart_ctrl_reg) == 4U,
              "ABI requires 4-byte aegis_uart_ctrl_reg");

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
}

TEST(C23AbiTest, StructConstants) { EXPECT_EQ(HALOS_DOF_COUNT, 6U); }
