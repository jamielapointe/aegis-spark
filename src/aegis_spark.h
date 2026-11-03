#pragma once

#include <stddef.h>
#include <stdint.h>

#include "halos_c_logger.h"
#include "halos_mailbox.h"

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Halos Watchdog Subsystem C23 ABI
// ============================================================================
static constexpr uint32_t HALOS_WD_RESET_MAGIC = 0x57444752U;  // "WDGR"

enum halos_watchdog_state : uint32_t {
  WD_DISABLED = 0U,
  WD_ARMED = 1U,
  WD_FAULT_EARLY = 2U,
  WD_FAULT_LATE = 3U,
  WD_FAULT_CLOCK = 4U,
};

enum halos_watchdog_status : int32_t {
  WD_OK = 0,
  WD_ERR_NOT_ARMED = 1,
  WD_ERR_TOO_EARLY = 2,
  WD_ERR_TOO_LATE = 3,
  WD_ERR_TIME_REWIND = 4,
  WD_ERR_INVALID_CONFIG = 5,
  WD_ERR_INVALID_KEY = 6,
};

struct halos_watchdog_config {
  uint64_t min_interval_ns;
  uint64_t max_interval_ns;
};

struct halos_watchdog_device {
  struct halos_watchdog_config config;
  uint64_t last_pet_ns;
  uint64_t pet_count;
  enum halos_watchdog_state state;
  uint32_t reserved_pad;
};

static_assert(sizeof(struct halos_watchdog_config) == 16U,
              "Watchdog config size mismatch");
static_assert(alignof(struct halos_watchdog_config) == 8U,
              "Watchdog config align mismatch");
static_assert(sizeof(struct halos_watchdog_device) == 40U,
              "Watchdog device size mismatch");
static_assert(alignof(struct halos_watchdog_device) == 8U,
              "Watchdog device align mismatch");
static_assert(offsetof(struct halos_watchdog_device, last_pet_ns) == 16U,
              "last_pet_ns offset mismatch");
static_assert(offsetof(struct halos_watchdog_device, state) == 32U,
              "state offset mismatch");

void halos_watchdog_init(struct halos_watchdog_device* wd);

void halos_watchdog_arm(struct halos_watchdog_device* wd,
                        const struct halos_watchdog_config* config,
                        uint64_t start_ns, enum halos_watchdog_status* status);

void halos_watchdog_pet(struct halos_watchdog_device* wd, uint64_t now_ns,
                        enum halos_watchdog_status* status);

void halos_watchdog_check_deadline(struct halos_watchdog_device* wd,
                                   uint64_t now_ns,
                                   enum halos_watchdog_status* status);

void halos_watchdog_reset(struct halos_watchdog_device* wd, uint32_t reset_key,
                          uint64_t now_ns, enum halos_watchdog_status* status);

// ============================================================================
// Halos Safety HSM Subsystem C23 ABI
// ============================================================================
static constexpr uint32_t HALOS_HSM_RESET_MAGIC = 0x48534D52U;  // "HSMR"

enum halos_hsm_state : uint32_t {
  HALOS_HSM_BOOT = 0U,
  HALOS_HSM_ACTIVE = 1U,
  HALOS_HSM_DEGRADED = 2U,
  HALOS_HSM_FAULT_ESTOP = 3U,
};

enum halos_hsm_event : uint32_t {
  HALOS_EVENT_NONE = 0U,
  HALOS_EVENT_SELF_TEST_PASSED = 1U,
  HALOS_EVENT_SELF_TEST_FAILED = 2U,
  HALOS_EVENT_DEGRADE_REQUESTED = 3U,
  HALOS_EVENT_RECOVER_NOMINAL = 4U,
  HALOS_EVENT_FAULT_DETECTED = 5U,
  HALOS_EVENT_RESET_REQUESTED = 6U,
};

enum halos_fault_code : uint32_t {
  HALOS_FAULT_NONE = 0U,
  HALOS_FAULT_WATCHDOG_TIMEOUT = 1U,
  HALOS_FAULT_WATCHDOG_EARLY_PET = 2U,
  HALOS_FAULT_WATCHDOG_CLOCK_REWIND = 3U,
  HALOS_FAULT_KINEMATIC_POSITION = 4U,
  HALOS_FAULT_KINEMATIC_VELOCITY = 5U,
  HALOS_FAULT_KINEMATIC_TORQUE = 6U,
  HALOS_FAULT_KINEMATIC_JERK = 7U,
  HALOS_FAULT_NON_FINITE_INPUT = 8U,
  HALOS_FAULT_HARDWARE_BIST = 9U,
};

enum halos_hsm_status : int32_t {
  HALOS_HSM_OK = 0,
  HALOS_HSM_ERR_INVALID_TRANSITION = 1,
  HALOS_HSM_ERR_INVALID_KEY = 2,
  HALOS_HSM_ERR_ALREADY_IN_STATE = 3,
};

struct halos_hsm_instance {
  enum halos_hsm_state state;
  enum halos_fault_code last_fault_code;
  uint64_t transition_count;
};

static_assert(sizeof(struct halos_hsm_instance) == 16U,
              "HSM instance size mismatch");
static_assert(alignof(struct halos_hsm_instance) == 8U,
              "HSM instance align mismatch");
static_assert(offsetof(struct halos_hsm_instance, last_fault_code) == 4U,
              "last_fault_code offset mismatch");
static_assert(offsetof(struct halos_hsm_instance, transition_count) == 8U,
              "transition_count offset mismatch");

void halos_hsm_init(struct halos_hsm_instance* hsm);

void halos_hsm_process_event(struct halos_hsm_instance* hsm,
                             enum halos_hsm_event event,
                             enum halos_fault_code fault_code,
                             enum halos_hsm_status* status);

void halos_hsm_trigger_reset(struct halos_hsm_instance* hsm, uint32_t reset_key,
                             enum halos_hsm_status* status);

// ============================================================================
// Halos 6-DOF Kinematic Envelope Subsystem C23 ABI
// ============================================================================
struct halos_kinematic_limits {
  float max_abs_position_rad[HALOS_DOF_COUNT];
  float max_abs_velocity_rad[HALOS_DOF_COUNT];
  float max_abs_torque_nm[HALOS_DOF_COUNT];
  float max_delta_torque_step[HALOS_DOF_COUNT];
};

struct halos_kinematic_cmd {
  uint64_t timestamp_ns;
  float position_rad[HALOS_DOF_COUNT];
  float velocity_rad[HALOS_DOF_COUNT];
  float torque_nm[HALOS_DOF_COUNT];
};

struct halos_kinematic_state {
  struct halos_kinematic_cmd last_cmd;
  struct halos_kinematic_limits limits;
  struct halos_hsm_instance hsm;
};

static_assert(sizeof(struct halos_kinematic_limits) == 96U,
              "Kinematic limits size mismatch");
static_assert(alignof(struct halos_kinematic_limits) == 4U,
              "Kinematic limits align mismatch");
static_assert(sizeof(struct halos_kinematic_cmd) == 80U,
              "Kinematic cmd size mismatch");
static_assert(alignof(struct halos_kinematic_cmd) == 8U,
              "Kinematic cmd align mismatch");
static_assert(sizeof(struct halos_kinematic_state) == 192U,
              "Kinematic state size mismatch");
static_assert(alignof(struct halos_kinematic_state) == 8U,
              "Kinematic state align mismatch");
static_assert(offsetof(struct halos_kinematic_state, limits) == 80U,
              "limits offset mismatch");
static_assert(offsetof(struct halos_kinematic_state, hsm) == 176U,
              "hsm offset mismatch");

void halos_kinematics_init(struct halos_kinematic_state* state);

void halos_kinematics_intercept_cmd(struct halos_kinematic_state* state,
                                    const struct halos_kinematic_cmd* cmd_in,
                                    float safe_torque_out[HALOS_DOF_COUNT],
                                    float safe_vel_out[HALOS_DOF_COUNT],
                                    enum halos_hsm_status* status);

// ============================================================================
// Halos Composed Safety Gate C23 ABI
// ============================================================================
struct halos_composed_gate {
  struct halos_watchdog_device watchdog;
  struct halos_hsm_instance hsm;
  struct halos_kinematic_state kinematics;
};

static_assert(sizeof(struct halos_composed_gate) == 248U,
              "Composed gate size mismatch");
static_assert(alignof(struct halos_composed_gate) == 8U,
              "Composed gate align mismatch");
static_assert(offsetof(struct halos_composed_gate, hsm) == 40U,
              "hsm offset mismatch");
static_assert(offsetof(struct halos_composed_gate, kinematics) == 56U,
              "kinematics offset mismatch");

void halos_composed_gate_init(struct halos_composed_gate* gate,
                              uint64_t start_ns);

void halos_composed_gate_intercept_cmd(struct halos_composed_gate* gate,
                                       const struct halos_kinematic_cmd* cmd_in,
                                       uint64_t now_ns,
                                       float safe_torque_out[HALOS_DOF_COUNT],
                                       float safe_vel_out[HALOS_DOF_COUNT],
                                       enum halos_hsm_status* status);

// ============================================================================
// Legacy Gold-proved safety command interceptor (Halos_Safety_Gate)
// ============================================================================
void halos_spark_intercept_joint_cmd(struct halos_safety_envelope* env,
                                     const struct halos_joint_cmd* cmd_in,
                                     uint64_t now_ns,
                                     float safe_torque_out[HALOS_DOF_COUNT],
                                     enum halos_status* status);

// Standalone SPARK Ada library lifecycle functions
void aegis_sparkinit(void);
void aegis_sparkfinal(void);
[[nodiscard]] const char* aegis_spark_version_string(void);

// Host Simulation Mock MMIO Register Bitfield Structs (Aegis.HAL.Registers)
struct aegis_uart_data_reg {
  uint32_t data : 8;
  uint32_t reserved : 24;
};

struct aegis_uart_status_reg {
  uint32_t tx_empty : 1;
  uint32_t rx_full : 1;
  uint32_t busy : 1;
  uint32_t err_ovr : 1;
  uint32_t reserved : 28;
};

struct aegis_uart_ctrl_reg {
  uint32_t enable : 1;
  uint32_t tx_en : 1;
  uint32_t rx_en : 1;
  uint32_t reserved_1 : 4;
  uint32_t loopback : 1;
  uint32_t reserved_2 : 24;
};

// In-RAM mock MMIO registers exported from Aegis.HAL.Registers (Host SIL)
// NOLINTBEGIN(cppcoreguidelines-avoid-non-const-global-variables)
extern volatile uint32_t aegis_mock_uart0_dr;
extern volatile uint32_t aegis_mock_uart0_sr;
extern volatile uint32_t aegis_mock_uart0_cr;
extern volatile uint32_t aegis_mock_uart0_baud;
// NOLINTEND(cppcoreguidelines-avoid-non-const-global-variables)

#ifdef __cplusplus
}  // extern "C"
#endif
