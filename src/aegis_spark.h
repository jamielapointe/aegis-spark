#pragma once

#include <stdint.h>

#include "halos_c_logger.h"

#ifdef __cplusplus
extern "C" {
#endif

// Gold-proved safety command interceptor exported from Halos_Safety_Gate
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
