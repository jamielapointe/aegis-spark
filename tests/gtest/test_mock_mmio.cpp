#include <gtest/gtest.h>

#include <cstdint>

#include "aegis_spark.h"

class HalosMockMmioTest : public ::testing::Test {
 protected:
  void SetUp() override {
    // Reset registers to known state
    aegis_mock_uart0_dr = 0U;
    aegis_mock_uart0_sr = 1U;  // TX empty = 1
    aegis_mock_uart0_cr = 0U;
    aegis_mock_uart0_baud = 0U;
  }
};

TEST_F(HalosMockMmioTest, MemoryAddressesAccessibleWithoutSigsegv) {
  // Reading and writing to all 4 volatile mock registers must never SIGSEGV in
  // host simulation
  EXPECT_NO_FATAL_FAILURE({
    aegis_mock_uart0_dr = 0xAAU;
    aegis_mock_uart0_sr = 0x01U;
    aegis_mock_uart0_cr = 0x03U;
    aegis_mock_uart0_baud = 115200U;

    EXPECT_EQ(aegis_mock_uart0_dr, 0xAAU);
    EXPECT_EQ(aegis_mock_uart0_sr, 0x01U);
    EXPECT_EQ(aegis_mock_uart0_cr, 0x03U);
    EXPECT_EQ(aegis_mock_uart0_baud, 115200U);
  });
}

TEST_F(HalosMockMmioTest, ControlRegisterBitfields) {
  auto* cr = reinterpret_cast<volatile struct aegis_uart_ctrl_reg*>(
      const_cast<uint32_t*>(&aegis_mock_uart0_cr));

  cr->enable = 1U;
  cr->tx_en = 1U;
  cr->rx_en = 0U;
  cr->loopback = 1U;

  EXPECT_EQ(static_cast<uint32_t>(cr->enable), 1U);
  EXPECT_EQ(static_cast<uint32_t>(cr->tx_en), 1U);
  EXPECT_EQ(static_cast<uint32_t>(cr->rx_en), 0U);
  EXPECT_EQ(static_cast<uint32_t>(cr->loopback), 1U);

  // Bit 0 = enable (1), Bit 1 = tx_en (2), Bit 7 = loopback (128) -> 131 (0x83)
  EXPECT_EQ(aegis_mock_uart0_cr & 0xFFU, 0x83U);
}

TEST_F(HalosMockMmioTest, StatusRegisterBitfields) {
  auto* sr = reinterpret_cast<volatile struct aegis_uart_status_reg*>(
      const_cast<uint32_t*>(&aegis_mock_uart0_sr));

  sr->tx_empty = 1U;
  sr->rx_full = 0U;
  sr->busy = 1U;
  sr->err_ovr = 0U;

  EXPECT_EQ(static_cast<uint32_t>(sr->tx_empty), 1U);
  EXPECT_EQ(static_cast<uint32_t>(sr->rx_full), 0U);
  EXPECT_EQ(static_cast<uint32_t>(sr->busy), 1U);
  EXPECT_EQ(static_cast<uint32_t>(sr->err_ovr), 0U);

  // Bit 0 = tx_empty (1), Bit 2 = busy (4) -> 5
  EXPECT_EQ(aegis_mock_uart0_sr & 0x0FU, 0x05U);
}

TEST_F(HalosMockMmioTest, DataRegisterByteTransfer) {
  auto* dr = reinterpret_cast<volatile struct aegis_uart_data_reg*>(
      const_cast<uint32_t*>(&aegis_mock_uart0_dr));

  dr->data = 'X';
  dr->reserved = 0U;

  EXPECT_EQ(static_cast<uint32_t>(dr->data), static_cast<uint32_t>('X'));
  EXPECT_EQ(aegis_mock_uart0_dr & 0xFFU, static_cast<uint32_t>('X'));
}

TEST_F(HalosMockMmioTest, BaudRateDivisorConfiguration) {
  // 115200 baud divisor configuration
  constexpr uint32_t kBaud115200 = 24'000'000U / (16U * 115200U);
  aegis_mock_uart0_baud = kBaud115200;

  EXPECT_EQ(aegis_mock_uart0_baud, kBaud115200);
}
