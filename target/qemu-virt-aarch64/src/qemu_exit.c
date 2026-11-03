#include "qemu_exit.h"

[[noreturn]] void qemu_exit(int status) {
  // ARM Semihosting SYS_EXIT (0x18)
  // Reason 0x20026 = ADP_Stopped_ApplicationExit
  struct {
    uint64_t reason;
    uint64_t exit_code;
  } param_block = {
      .reason = 0x20026ULL,
      .exit_code = (uint64_t)(uint32_t)status,
  };

  register uint64_t x0 __asm__("x0") = 0x18ULL;
  register uint64_t x1 __asm__("x1") = (uint64_t)&param_block;

  __asm__ volatile("hlt #0xf000" : "+r"(x0), "+r"(x1) : : "memory");

  // Fallback: ARM PSCI SYSTEM_OFF (0x84000008) via HVC call
  register uint64_t psci_fn __asm__("x0") = 0x84000008ULL;
  __asm__ volatile("hvc #0" : "+r"(psci_fn) : : "memory");

  // Final fallback: sleep forever
  for (;;) {
    __asm__ volatile("wfe");
  }
}
