#include <stdint.h>

#include "qemu_exit.h"

// Last chance handler called by bare-metal GNAT runtime on unhandled
// exception/assertion failure
[[noreturn]] void __gnat_last_chance_handler(const char* msg, int line) {
  (void)msg;
  (void)line;
  volatile uint32_t* const uart0_dr = (volatile uint32_t*)0x09000000ULL;
  const char panic_msg[] =
      "\n[FATAL] GNAT Last Chance Handler invoked! Halting.\n";
  for (const char* p = panic_msg; *p != '\0'; ++p) {
    *uart0_dr = (uint32_t)(uint8_t)(*p);
  }
  qemu_exit(1);
}
