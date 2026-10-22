#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

static constexpr size_t HALOS_DOF_COUNT = 6U;

enum halos_status : int32_t {
  HALOS_OK = 0,
  HALOS_ERR_NOT_ACTIVE = 1,
  HALOS_ERR_STALE_HEARTBEAT = 2,
  HALOS_ERR_NON_FINITE_INPUT = 3,
  HALOS_ERR_TORQUE_LIMIT_EXCEEDED = 4,
};

enum halos_safety_state : uint8_t {
  HALOS_STATE_INIT = 0U,
  HALOS_STATE_ACTIVE = 1U,
  HALOS_STATE_FAULT_ESTOP = 2U,
};

enum halos_log_status : int32_t {
  HALOS_LOG_OK = 0,
  HALOS_LOG_ERR_NULL_PTR = -1,
  HALOS_LOG_ERR_IO = -2,
};

struct halos_joint_cmd {
  uint64_t timestamp_ns;
  float desired_torque_nm[HALOS_DOF_COUNT];
};

struct halos_safety_envelope {
  float max_abs_torque_nm[HALOS_DOF_COUNT];
  enum halos_safety_state state;
};

static_assert(sizeof(enum halos_status) == 4U,
              "ABI requires 32-bit Halos_Status enum");
static_assert(sizeof(enum halos_safety_state) == 1U,
              "ABI requires 8-bit Halos_Safety_State enum");
static_assert(sizeof(enum halos_log_status) == 4U,
              "ABI requires 32-bit Halos_Log_Status enum");

[[nodiscard]] enum halos_log_status halos_log_suite_header(void);

[[nodiscard]] enum halos_log_status halos_log_intercept_step(
    uint32_t step_id, uint64_t now_ns,
    const struct halos_joint_cmd* restrict cmd_in,
    const struct halos_safety_envelope* restrict env,
    const float safe_out[restrict static HALOS_DOF_COUNT],
    enum halos_status status);

[[nodiscard]] enum halos_log_status halos_log_suite_footer(void);

// Thin void wrappers for SPARK Ada FFI boundary (Halos_Logger package body)
void halos_c_log_suite_header(void);

void halos_c_log_intercept_step(
    uint32_t step_id, uint64_t now_ns,
    const struct halos_joint_cmd* restrict cmd_in,
    const struct halos_safety_envelope* restrict env,
    const float safe_out[restrict static HALOS_DOF_COUNT],
    enum halos_status status);

void halos_c_log_suite_footer(void);

#ifdef __cplusplus
}  // extern "C"
#endif
