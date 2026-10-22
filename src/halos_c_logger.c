#include "halos_c_logger.h"

#include <stdint.h>
#include <stdio.h>

[[nodiscard]] static const char* status_to_str(enum halos_status status) {
  switch (status) {
    case HALOS_OK:
      return "HALOS_OK";
    case HALOS_ERR_NOT_ACTIVE:
      return "HALOS_ERR_NOT_ACTIVE";
    case HALOS_ERR_STALE_HEARTBEAT:
      return "HALOS_ERR_STALE_HEARTBEAT";
    case HALOS_ERR_NON_FINITE_INPUT:
      return "HALOS_ERR_NON_FINITE_INPUT";
    case HALOS_ERR_TORQUE_LIMIT_EXCEEDED:
      return "HALOS_ERR_TORQUE_LIMIT_EXCEEDED";
    default:
      return "HALOS_ERR_UNKNOWN";
  }
}

[[nodiscard]] static const char* state_to_str(enum halos_safety_state state) {
  switch (state) {
    case HALOS_STATE_INIT:
      return "STATE_INIT";
    case HALOS_STATE_ACTIVE:
      return "STATE_ACTIVE";
    case HALOS_STATE_FAULT_ESTOP:
      return "STATE_FAULT_ESTOP";
    default:
      return "STATE_UNKNOWN";
  }
}

[[nodiscard]] static const char* severity_to_str(enum halos_status status) {
  return (status == HALOS_OK) ? "INFO" : "WARN";
}

enum halos_log_status halos_log_suite_header(void) {
  if (fputs("=================================================================="
            "==============\n"
            "[INFO] [AEGIS-SPARK] Starting Aegis-SPARK (Halos) Safety Gate "
            "Verification\n"
            "=================================================================="
            "==============\n",
            stdout) == EOF) {
    return HALOS_LOG_ERR_IO;
  }
  if (fflush(stdout) == EOF) {
    return HALOS_LOG_ERR_IO;
  }
  return HALOS_LOG_OK;
}

enum halos_log_status halos_log_intercept_step(
    uint32_t step_id, uint64_t now_ns,
    const struct halos_joint_cmd* restrict cmd_in,
    const struct halos_safety_envelope* restrict env,
    const float safe_out[restrict static HALOS_DOF_COUNT],
    enum halos_status status) {
  if (cmd_in == nullptr || env == nullptr) {
    return HALOS_LOG_ERR_NULL_PTR;
  }

  const char* const sev = severity_to_str(status);
  const char* const status_str = status_to_str(status);
  const char* const state_str = state_to_str(env->state);

  if (printf("[%s] [Step %u] now_ns=%llu cmd_ts_ns=%llu | status=%s | "
             "env_state=%s\n",
             sev, (unsigned int)step_id, (unsigned long long)now_ns,
             (unsigned long long)cmd_in->timestamp_ns, status_str,
             state_str) < 0) {
    return HALOS_LOG_ERR_IO;
  }

  if (printf("       req_torque_nm  = [%.1f, %.1f, %.1f, %.1f, %.1f, %.1f]\n",
             (double)cmd_in->desired_torque_nm[0],
             (double)cmd_in->desired_torque_nm[1],
             (double)cmd_in->desired_torque_nm[2],
             (double)cmd_in->desired_torque_nm[3],
             (double)cmd_in->desired_torque_nm[4],
             (double)cmd_in->desired_torque_nm[5]) < 0) {
    return HALOS_LOG_ERR_IO;
  }

  if (printf("       safe_torque_nm = [%.1f, %.1f, %.1f, %.1f, %.1f, %.1f]\n",
             (double)safe_out[0], (double)safe_out[1], (double)safe_out[2],
             (double)safe_out[3], (double)safe_out[4],
             (double)safe_out[5]) < 0) {
    return HALOS_LOG_ERR_IO;
  }

  if (fflush(stdout) == EOF) {
    return HALOS_LOG_ERR_IO;
  }
  return HALOS_LOG_OK;
}

enum halos_log_status halos_log_suite_footer(void) {
  if (fputs("------------------------------------------------------------------"
            "--------------\n"
            "[INFO] [AEGIS-SPARK] All Gold-proved safety assertions and checks "
            "succeeded.\n"
            "=================================================================="
            "==============\n",
            stdout) == EOF) {
    return HALOS_LOG_ERR_IO;
  }
  if (fflush(stdout) == EOF) {
    return HALOS_LOG_ERR_IO;
  }
  return HALOS_LOG_OK;
}

void halos_c_log_suite_header(void) {
  const enum halos_log_status rc = halos_log_suite_header();
  (void)rc;
}

void halos_c_log_intercept_step(
    uint32_t step_id, uint64_t now_ns,
    const struct halos_joint_cmd* restrict cmd_in,
    const struct halos_safety_envelope* restrict env,
    const float safe_out[restrict static HALOS_DOF_COUNT],
    enum halos_status status) {
  const enum halos_log_status rc =
      halos_log_intercept_step(step_id, now_ns, cmd_in, env, safe_out, status);
  (void)rc;
}

void halos_c_log_suite_footer(void) {
  const enum halos_log_status rc = halos_log_suite_footer();
  (void)rc;
}
