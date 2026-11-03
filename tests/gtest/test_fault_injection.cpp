#include <gtest/gtest.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iterator>
#include <limits>

#include "aegis_spark.h"

class HalosFaultInjectionTest : public ::testing::Test {
 protected:
  static constexpr float kSentinelTorque = 99.0F;

  void ResetSafeTorquesToSentinel() {
    std::fill(std::begin(safe_torque_out_), std::end(safe_torque_out_),
              kSentinelTorque);
  }

  void SetUp() override {
    // Initialize envelope to active with 100.0 Nm limit per joint
    for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
      env_.max_abs_torque_nm[i] = 100.0F;
    }
    env_.state = HALOS_STATE_ACTIVE;

    // Nominal command
    cmd_.timestamp_ns = 1'000'000ULL;
    for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
      cmd_.desired_torque_nm[i] = 10.0F;
    }

    // Pre-populate safe torque array with non-zero sentinel values so tests
    // genuinely verify that halos_spark_intercept_joint_cmd actively drives
    // safe torques to 0.0F on error.
    ResetSafeTorquesToSentinel();
    status_ = static_cast<enum halos_status>(-1);
  }

  struct halos_safety_envelope env_{};
  struct halos_joint_cmd cmd_{};
  float safe_torque_out_[HALOS_DOF_COUNT] = {};
  enum halos_status status_ = HALOS_OK;
};

TEST_F(HalosFaultInjectionTest, NominalCommandPassesThrough) {
  uint64_t const now_ns =
      2'000'000ULL;  // 1 ms latency (well under 5 ms watchdog)

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_OK);
  EXPECT_EQ(env_.state, HALOS_STATE_ACTIVE);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], cmd_.desired_torque_nm[i]);
  }
}

TEST_F(HalosFaultInjectionTest, RejectsWhenSafetyGateNotActive) {
  env_.state = HALOS_STATE_INIT;
  uint64_t const now_ns = 2'000'000ULL;

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_NOT_ACTIVE);
  EXPECT_EQ(env_.state, HALOS_STATE_INIT);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest, RejectsStaleHeartbeatAndLatchesFaultEstop) {
  uint64_t const now_ns =
      7'000'001ULL;  // > 5 ms watchdog limit (cmd at 1'000'000)

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_STALE_HEARTBEAT);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest, RejectsClockRewindAndLatchesFaultEstop) {
  uint64_t const now_ns =
      500'000ULL;  // now_ns < cmd.timestamp_ns (time travel)

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_STALE_HEARTBEAT);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest, RejectsNanTorqueAndLatchesFaultEstop) {
  float const nan_val = std::numeric_limits<float>::quiet_NaN();
  uint64_t const now_ns = 2'000'000ULL;

  for (size_t joint = 0; joint < HALOS_DOF_COUNT; ++joint) {
    SetUp();  // reset nominal state
    cmd_.desired_torque_nm[joint] = nan_val;

    halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                    &status_);

    EXPECT_EQ(status_, HALOS_ERR_NON_FINITE_INPUT)
        << "Failed on joint " << joint;
    EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP)
        << "Failed on joint " << joint;
    for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
      EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
    }
  }
}

TEST_F(HalosFaultInjectionTest,
       RejectsPositiveInfinityTorqueAndLatchesFaultEstop) {
  float const inf_val = std::numeric_limits<float>::infinity();
  uint64_t const now_ns = 2'000'000ULL;

  cmd_.desired_torque_nm[0] = inf_val;

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_NON_FINITE_INPUT);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest,
       RejectsNegativeInfinityTorqueAndLatchesFaultEstop) {
  float const neg_inf_val = -std::numeric_limits<float>::infinity();
  uint64_t const now_ns = 2'000'000ULL;

  cmd_.desired_torque_nm[3] = neg_inf_val;

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_NON_FINITE_INPUT);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest, RejectsTorqueExceedingEnvelopeLimit) {
  uint64_t const now_ns = 2'000'000ULL;
  cmd_.desired_torque_nm[2] = 120.0F;  // envelope limit is 100.0 Nm

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_TORQUE_LIMIT_EXCEEDED);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest, RejectsNegativeTorqueExceedingEnvelopeLimit) {
  uint64_t const now_ns = 2'000'000ULL;
  cmd_.desired_torque_nm[5] = -105.0F;  // envelope limit is 100.0 Nm

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_TORQUE_LIMIT_EXCEEDED);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest, RejectsTorqueExceedingHardwareAbsoluteLimit) {
  uint64_t const now_ns = 2'000'000ULL;
  env_.max_abs_torque_nm[1] = 500.0F;
  cmd_.desired_torque_nm[1] = 500.1F;  // hardware limit is 500.0 Nm

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_NON_FINITE_INPUT);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

TEST_F(HalosFaultInjectionTest, FaultEstopStateIsImmutableAndLatched) {
  uint64_t now_ns = 2'000'000ULL;

  // Step 1: Trigger fault via stale heartbeat
  cmd_.timestamp_ns = 1'000'000ULL;
  now_ns = 10'000'000ULL;  // 9 ms latency -> stale

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  EXPECT_EQ(status_, HALOS_ERR_STALE_HEARTBEAT);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);

  // Step 2: Send completely valid, nominal, fresh command
  // Re-populate output buffer with sentinel values to verify Step 2 actively
  // zeroes outputs
  ResetSafeTorquesToSentinel();
  cmd_.timestamp_ns = 10'500'000ULL;
  now_ns = 11'000'000ULL;  // 0.5 ms latency
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    cmd_.desired_torque_nm[i] = 5.0F;  // well within limits
  }

  halos_spark_intercept_joint_cmd(&env_, &cmd_, now_ns, safe_torque_out_,
                                  &status_);

  // Must be rejected with HALOS_ERR_NOT_ACTIVE and latch maintained
  EXPECT_EQ(status_, HALOS_ERR_NOT_ACTIVE);
  EXPECT_EQ(env_.state, HALOS_STATE_FAULT_ESTOP);
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque_out_[i], 0.0F);
  }
}

// =============================================================================
// Phase 4: Watchdog Windowed Supervision Fault Injection Tests
// =============================================================================

TEST(HalosWatchdogFaultTest, EarlyPetTriggersFault) {
  struct halos_watchdog_device wd{};
  struct halos_watchdog_config config{
      .min_interval_ns = 500'000ULL,   // 0.5 ms
      .max_interval_ns = 5'000'000ULL  // 5.0 ms
  };
  enum halos_watchdog_status status = WD_OK;

  halos_watchdog_init(&wd);
  halos_watchdog_arm(&wd, &config, 1'000'000ULL, &status);
  EXPECT_EQ(status, WD_OK);
  EXPECT_EQ(wd.state, WD_ARMED);

  // Early pet: only 0.2 ms elapsed (< 0.5 ms min)
  halos_watchdog_pet(&wd, 1'200'000ULL, &status);
  EXPECT_EQ(status, WD_ERR_TOO_EARLY);
  EXPECT_EQ(wd.state, WD_FAULT_EARLY);
}

TEST(HalosWatchdogFaultTest, LatePetTriggersFault) {
  struct halos_watchdog_device wd{};
  struct halos_watchdog_config config{.min_interval_ns = 500'000ULL,
                                      .max_interval_ns = 5'000'000ULL};
  enum halos_watchdog_status status = WD_OK;

  halos_watchdog_init(&wd);
  halos_watchdog_arm(&wd, &config, 1'000'000ULL, &status);
  EXPECT_EQ(status, WD_OK);

  // Late pet: 6.0 ms elapsed (> 5.0 ms max)
  halos_watchdog_pet(&wd, 7'000'000ULL, &status);
  EXPECT_EQ(status, WD_ERR_TOO_LATE);
  EXPECT_EQ(wd.state, WD_FAULT_LATE);
}

TEST(HalosWatchdogFaultTest, ClockRewindTriggersFault) {
  struct halos_watchdog_device wd{};
  struct halos_watchdog_config config{.min_interval_ns = 500'000ULL,
                                      .max_interval_ns = 5'000'000ULL};
  enum halos_watchdog_status status = WD_OK;

  halos_watchdog_init(&wd);
  halos_watchdog_arm(&wd, &config, 5'000'000ULL, &status);
  EXPECT_EQ(status, WD_OK);

  // Monotonic rewind: now_ns < last_pet_ns
  halos_watchdog_pet(&wd, 4'000'000ULL, &status);
  EXPECT_EQ(status, WD_ERR_TIME_REWIND);
  EXPECT_EQ(wd.state, WD_FAULT_CLOCK);
}

TEST(HalosWatchdogFaultTest, CheckDeadlineDetectsExpiration) {
  struct halos_watchdog_device wd{};
  struct halos_watchdog_config config{.min_interval_ns = 500'000ULL,
                                      .max_interval_ns = 5'000'000ULL};
  enum halos_watchdog_status status = WD_OK;

  halos_watchdog_init(&wd);
  halos_watchdog_arm(&wd, &config, 1'000'000ULL, &status);
  EXPECT_EQ(status, WD_OK);

  // Check deadline at 7.0 ms (6.0 ms since pet -> expired)
  halos_watchdog_check_deadline(&wd, 7'000'000ULL, &status);
  EXPECT_EQ(status, WD_ERR_TOO_LATE);
  EXPECT_EQ(wd.state, WD_FAULT_LATE);
}

TEST(HalosWatchdogFaultTest, ResetRequiresValidToken) {
  struct halos_watchdog_device wd{};
  struct halos_watchdog_config config{.min_interval_ns = 500'000ULL,
                                      .max_interval_ns = 5'000'000ULL};
  enum halos_watchdog_status status = WD_OK;

  halos_watchdog_init(&wd);
  halos_watchdog_arm(&wd, &config, 1'000'000ULL, &status);
  halos_watchdog_pet(&wd, 7'000'000ULL, &status);
  EXPECT_EQ(wd.state, WD_FAULT_LATE);

  // Invalid reset token: rejected
  halos_watchdog_reset(&wd, 0xDEADBEEFU, 8'000'000ULL, &status);
  EXPECT_EQ(status, WD_ERR_INVALID_KEY);
  EXPECT_EQ(wd.state, WD_FAULT_LATE);

  // Valid reset token 0x57444752: clears fault back to armed
  halos_watchdog_reset(&wd, HALOS_WD_RESET_MAGIC, 8'000'000ULL, &status);
  EXPECT_EQ(status, WD_OK);
  EXPECT_EQ(wd.state, WD_ARMED);
}

// =============================================================================
// Phase 4: HSM Lifecycle & Fault Estop Latching Tests
// =============================================================================

TEST(HalosHsmFaultTest, IllegalTransitionsRejected) {
  struct halos_hsm_instance hsm{};
  enum halos_hsm_status status = HALOS_HSM_OK;

  halos_hsm_init(&hsm);
  EXPECT_EQ(hsm.state, HALOS_HSM_BOOT);

  // Direct transition to Degraded without self-test passed: illegal
  halos_hsm_process_event(&hsm, HALOS_EVENT_DEGRADE_REQUESTED, HALOS_FAULT_NONE,
                          &status);
  EXPECT_EQ(status, HALOS_HSM_ERR_INVALID_TRANSITION);
  EXPECT_EQ(hsm.state, HALOS_HSM_BOOT);

  // Self-test pass transitions to Active
  halos_hsm_process_event(&hsm, HALOS_EVENT_SELF_TEST_PASSED, HALOS_FAULT_NONE,
                          &status);
  EXPECT_EQ(status, HALOS_HSM_OK);
  EXPECT_EQ(hsm.state, HALOS_HSM_ACTIVE);

  // Trigger Fault Estop
  halos_hsm_process_event(&hsm, HALOS_EVENT_FAULT_DETECTED,
                          HALOS_FAULT_KINEMATIC_TORQUE, &status);
  EXPECT_EQ(status, HALOS_HSM_OK);
  EXPECT_EQ(hsm.state, HALOS_HSM_FAULT_ESTOP);

  // Illegal bypass without key
  halos_hsm_process_event(&hsm, HALOS_EVENT_SELF_TEST_PASSED, HALOS_FAULT_NONE,
                          &status);
  EXPECT_EQ(status, HALOS_HSM_ERR_INVALID_TRANSITION);
  EXPECT_EQ(hsm.state, HALOS_HSM_FAULT_ESTOP);
}

TEST(HalosHsmFaultTest, AuthenticatedResetKeyClearsFault) {
  struct halos_hsm_instance hsm{};
  enum halos_hsm_status status = HALOS_HSM_OK;

  halos_hsm_init(&hsm);
  halos_hsm_process_event(&hsm, HALOS_EVENT_SELF_TEST_PASSED, HALOS_FAULT_NONE,
                          &status);
  halos_hsm_process_event(&hsm, HALOS_EVENT_FAULT_DETECTED,
                          HALOS_FAULT_WATCHDOG_TIMEOUT, &status);
  EXPECT_EQ(hsm.state, HALOS_HSM_FAULT_ESTOP);

  // Invalid key: fails
  halos_hsm_trigger_reset(&hsm, 0x12345678U, &status);
  EXPECT_EQ(status, HALOS_HSM_ERR_INVALID_KEY);
  EXPECT_EQ(hsm.state, HALOS_HSM_FAULT_ESTOP);

  // Valid key: returns to Boot
  halos_hsm_trigger_reset(&hsm, HALOS_HSM_RESET_MAGIC, &status);
  EXPECT_EQ(status, HALOS_HSM_OK);
  EXPECT_EQ(hsm.state, HALOS_HSM_BOOT);
  EXPECT_EQ(hsm.last_fault_code, HALOS_FAULT_NONE);
}

// =============================================================================
// Phase 4: 6-DOF Kinematic Envelope Clamping & Fail-Safe Tests
// =============================================================================

TEST(HalosKinematicsFaultTest, PositionExceedanceTriggersEstop) {
  struct halos_kinematic_state state{};
  halos_kinematics_init(&state);
  state.hsm.state = HALOS_HSM_ACTIVE;

  // Set limits
  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    state.limits.max_abs_position_rad[i] = 3.14F;
    state.limits.max_abs_velocity_rad[i] = 10.0F;
    state.limits.max_abs_torque_nm[i] = 50.0F;
    state.limits.max_delta_torque_step[i] = 20.0F;
  }

  // Violate position on joint 1 (4.0 > 3.14)
  struct halos_kinematic_cmd cmd{
      .timestamp_ns = 1'000'000ULL,
      .position_rad = {0.0F, 4.0F, 0.0F, 0.0F, 0.0F, 0.0F},
      .velocity_rad = {1.0F, 1.0F, 1.0F, 1.0F, 1.0F, 1.0F},
      .torque_nm = {5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F}};
  float safe_torque[HALOS_DOF_COUNT] = {99.0F, 99.0F, 99.0F,
                                        99.0F, 99.0F, 99.0F};
  float safe_vel[HALOS_DOF_COUNT] = {99.0F, 99.0F, 99.0F, 99.0F, 99.0F, 99.0F};
  enum halos_hsm_status status = HALOS_HSM_OK;

  halos_kinematics_intercept_cmd(&state, &cmd, safe_torque, safe_vel, &status);
  EXPECT_NE(status, HALOS_HSM_OK);
  EXPECT_EQ(state.hsm.state, HALOS_HSM_FAULT_ESTOP);
  EXPECT_EQ(state.hsm.last_fault_code, HALOS_FAULT_KINEMATIC_POSITION);

  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque[i], 0.0F);
    EXPECT_FLOAT_EQ(safe_vel[i], 0.0F);
  }
}

TEST(HalosKinematicsFaultTest, VelocityExceedanceTriggersEstop) {
  struct halos_kinematic_state state{};
  halos_kinematics_init(&state);
  state.hsm.state = HALOS_HSM_ACTIVE;

  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    state.limits.max_abs_position_rad[i] = 3.14F;
    state.limits.max_abs_velocity_rad[i] = 5.0F;
    state.limits.max_abs_torque_nm[i] = 50.0F;
    state.limits.max_delta_torque_step[i] = 20.0F;
  }

  // Violate velocity on joint 4 (8.0 > 5.0)
  struct halos_kinematic_cmd cmd{
      .timestamp_ns = 1'000'000ULL,
      .position_rad = {0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F},
      .velocity_rad = {0.0F, 0.0F, 0.0F, 0.0F, 8.0F, 0.0F},
      .torque_nm = {5.0F, 5.0F, 5.0F, 5.0F, 5.0F, 5.0F}};
  float safe_torque[HALOS_DOF_COUNT] = {};
  float safe_vel[HALOS_DOF_COUNT] = {};
  enum halos_hsm_status status = HALOS_HSM_OK;

  halos_kinematics_intercept_cmd(&state, &cmd, safe_torque, safe_vel, &status);
  EXPECT_NE(status, HALOS_HSM_OK);
  EXPECT_EQ(state.hsm.state, HALOS_HSM_FAULT_ESTOP);
  EXPECT_EQ(state.hsm.last_fault_code, HALOS_FAULT_KINEMATIC_VELOCITY);

  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque[i], 0.0F);
    EXPECT_FLOAT_EQ(safe_vel[i], 0.0F);
  }
}

TEST(HalosKinematicsFaultTest, StepJerkExceedanceTriggersEstop) {
  struct halos_kinematic_state state{};
  halos_kinematics_init(&state);
  state.hsm.state = HALOS_HSM_ACTIVE;

  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    state.limits.max_abs_position_rad[i] = 3.14F;
    state.limits.max_abs_velocity_rad[i] = 5.0F;
    state.limits.max_abs_torque_nm[i] = 50.0F;
    state.limits.max_delta_torque_step[i] = 5.0F;  // max 5.0 Nm delta
    state.last_cmd.torque_nm[i] = 0.0F;
  }

  // Delta is 12.0 Nm > 5.0 Nm max jerk
  struct halos_kinematic_cmd cmd{
      .timestamp_ns = 1'000'000ULL,
      .position_rad = {0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F},
      .velocity_rad = {0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F},
      .torque_nm = {12.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F}};
  float safe_torque[HALOS_DOF_COUNT] = {};
  float safe_vel[HALOS_DOF_COUNT] = {};
  enum halos_hsm_status status = HALOS_HSM_OK;

  halos_kinematics_intercept_cmd(&state, &cmd, safe_torque, safe_vel, &status);
  EXPECT_NE(status, HALOS_HSM_OK);
  EXPECT_EQ(state.hsm.state, HALOS_HSM_FAULT_ESTOP);
  EXPECT_EQ(state.hsm.last_fault_code, HALOS_FAULT_KINEMATIC_JERK);

  for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
    EXPECT_FLOAT_EQ(safe_torque[i], 0.0F);
    EXPECT_FLOAT_EQ(safe_vel[i], 0.0F);
  }
}
