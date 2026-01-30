/*
 * smc.h - SMC key definitions for battery control
 * Based on smcFanControl and battery CLI research
 */

#ifndef SMC_H
#define SMC_H

#include <IOKit/IOKitLib.h>

#define SMC_KEY_SIZE 4
#define SMC_VAL_SIZE 32

// SMC data types
typedef struct {
    char key[SMC_KEY_SIZE + 1];
    UInt32 dataSize;
    char dataType[SMC_KEY_SIZE + 1];
    UInt8 bytes[SMC_VAL_SIZE];
} SMCVal_t;

typedef struct {
    UInt32 key;
    SMCVal_t val;
    UInt32 keyInfo;
    UInt8 result;
    UInt8 status;
    UInt8 data8;
    UInt32 data32;
} SMCParamStruct;

// SMC commands
enum {
    kSMCReadKey  = 5,
    kSMCWriteKey = 6,
    kSMCGetKeyInfo = 9,
};

// SMC key codes (FourCC)
#define SMC_KEY(s) ((UInt32)(s[0]) << 24 | (UInt32)(s[1]) << 16 | (UInt32)(s[2]) << 8 | (UInt32)(s[3]))

// Charging control keys
// Tahoe (M1/M2/M3/M4 Apple Silicon)
#define KEY_CHTE "CHTE"  // Charging enable/disable (4 bytes: 00000000=on, 01000000=off)

// Legacy (Intel)
#define KEY_CH0B "CH0B"  // Charging control B (1 byte: 00=on, 02=off)
#define KEY_CH0C "CH0C"  // Charging control C (1 byte: 00=on, 02=off)

// Adapter/discharge control
#define KEY_CHIE "CHIE"  // Adapter control (newer, 1 byte: 00=on, 08=off/discharge)
#define KEY_CH0I "CH0I"  // Adapter control (legacy, 1 byte: 00=on, 01=off/discharge)
#define KEY_CH0J "CH0J"  // Adapter control (alt, 1 byte: 00=on, 01=off/discharge)

// MagSafe LED control
#define KEY_ACLC "ACLC"  // LED color (00=reset, 01=off, 03=green, 04=orange)

#endif /* SMC_H */
