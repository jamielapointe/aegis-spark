#include <gtest/gtest.h>

#include <cmath>
#include <cstdint>
#include <limits>

#include "aegis_spark.h"

class HalosFaultInjectionTest : public ::testing::Test {
 protected:
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

    // Zero out safe torque array
    for (size_t i = 0; i < HALOS_DOF_COUNT; ++i) {
      safe_torque_out_[i] = 0.0F;
    }
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
