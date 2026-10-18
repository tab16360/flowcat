#ifndef FLOWCAT_HARDWARE_BRIDGE_H
#define FLOWCAT_HARDWARE_BRIDGE_H
#include <stdint.h>
typedef struct {
    uint32_t error;
    uint8_t warning, spare, used;
    int32_t temperature;
    uint64_t read_units, written_units, hours, errors;
    uint8_t valid_read, valid_written, valid_hours, valid_errors;
} FCNVMeHealth;
// 0: read, 1: unsupported, 2: permission denied, 3: read failed.
int fc_read_nvme(const char *bsd_name, FCNVMeHealth *out);
#endif
