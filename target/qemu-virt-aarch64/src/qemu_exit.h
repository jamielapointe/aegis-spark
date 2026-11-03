#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Semihosting and PSCI clean shutdown interface for QEMU bare metal
[[noreturn]] void qemu_exit(int status);

#ifdef __cplusplus
}
#endif
