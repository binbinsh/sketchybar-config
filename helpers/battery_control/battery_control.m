/*
 * battery_control.m - Native SMC-based battery charging control for macOS
 * Supports Apple Silicon (Tahoe) and Intel (Legacy) Macs
 *
 * Usage:
 *   battery_control status       - JSON status output
 *   battery_control enable       - Enable charging
 *   battery_control disable      - Disable charging
 *   battery_control adapter on   - Enable adapter (normal power)
 *   battery_control adapter off  - Disable adapter (force discharge)
 *   battery_control caps         - Show SMC capabilities
 */

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

// SMC constants
#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
    UInt32 key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static io_connect_t conn = 0;

static UInt32 _strtoul(const char *str, int size, int base) {
    (void)base; // unused, always treat as ASCII FourCC
    UInt32 total = 0;
    for (int i = 0; i < size; i++) {
        total = (total << 8) | (UInt8)str[i];
    }
    return total;
}

static void _ultostr(char *str, UInt32 val) {
    str[0] = (char)(val >> 24);
    str[1] = (char)(val >> 16);
    str[2] = (char)(val >> 8);
    str[3] = (char)val;
    str[4] = '\0';
}

static kern_return_t SMCOpen(void) {
    mach_port_t masterPort;
    kern_return_t result = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if (result != kIOReturnSuccess) return result;

    CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
    io_iterator_t iterator;
    result = IOServiceGetMatchingServices(masterPort, matchingDictionary, &iterator);
    if (result != kIOReturnSuccess) return result;

    io_object_t device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == 0) return kIOReturnNoDevice;

    result = IOServiceOpen(device, mach_task_self(), 0, &conn);
    IOObjectRelease(device);
    return result;
}

static kern_return_t SMCClose(void) {
    return IOServiceClose(conn);
}

static kern_return_t SMCCall(int index, SMCKeyData_t *inputStructure, SMCKeyData_t *outputStructure) {
    size_t structureInputSize = sizeof(SMCKeyData_t);
    size_t structureOutputSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, index, inputStructure, structureInputSize,
                                     outputStructure, &structureOutputSize);
}

static kern_return_t SMCReadKey(const char *key, SMCKeyData_t *val) {
    SMCKeyData_t inputStructure = {0};
    SMCKeyData_t outputStructure = {0};

    inputStructure.key = _strtoul(key, 4, 0);
    inputStructure.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (result != kIOReturnSuccess) return result;

    inputStructure.keyInfo.dataSize = outputStructure.keyInfo.dataSize;
    inputStructure.data8 = SMC_CMD_READ_BYTES;

    result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (result != kIOReturnSuccess) return result;

    memcpy(val, &outputStructure, sizeof(SMCKeyData_t));
    return kIOReturnSuccess;
}

static kern_return_t SMCWriteKey(const char *key, const UInt8 *bytes, UInt32 dataSize) {
    SMCKeyData_t inputStructure = {0};
    SMCKeyData_t outputStructure = {0};

    inputStructure.key = _strtoul(key, 4, 0);
    inputStructure.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (result != kIOReturnSuccess) return result;

    inputStructure.keyInfo.dataSize = outputStructure.keyInfo.dataSize;
    inputStructure.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(inputStructure.bytes, bytes, dataSize);

    result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    return result;
}

static BOOL SMCKeyExists(const char *key) {
    SMCKeyData_t inputStructure = {0};
    SMCKeyData_t outputStructure = {0};

    inputStructure.key = _strtoul(key, 4, 0);
    inputStructure.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);

    // Key exists if call succeeds and dataSize > 0
    return result == kIOReturnSuccess && outputStructure.keyInfo.dataSize > 0;
}

static NSString *SMCReadHex(const char *key) {
    SMCKeyData_t inputStructure = {0};
    SMCKeyData_t outputStructure = {0};

    inputStructure.key = _strtoul(key, 4, 0);
    inputStructure.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (result != kIOReturnSuccess) return nil;

    UInt32 dataSize = outputStructure.keyInfo.dataSize;
    if (dataSize == 0) return nil;

    inputStructure.keyInfo.dataSize = dataSize;
    inputStructure.data8 = SMC_CMD_READ_BYTES;

    result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
    if (result != kIOReturnSuccess) return nil;

    NSMutableString *hex = [NSMutableString string];
    for (UInt32 i = 0; i < dataSize; i++) {
        [hex appendFormat:@"%02x", (unsigned char)outputStructure.bytes[i]];
    }
    return hex;
}

// Capability detection
static BOOL supports_tahoe = NO;
static BOOL supports_legacy = NO;
static BOOL supports_chie = NO;
static BOOL supports_ch0i = NO;
static BOOL supports_ch0j = NO;

static void detectCapabilities(void) {
    supports_tahoe = SMCKeyExists("CHTE");
    supports_legacy = SMCKeyExists("CH0B");
    supports_chie = SMCKeyExists("CHIE");
    supports_ch0i = SMCKeyExists("CH0I");
    supports_ch0j = SMCKeyExists("CH0J");
}

static NSString *getSmcType(void) {
    if (supports_tahoe) return @"tahoe";
    if (supports_legacy) return @"legacy";
    return @"unknown";
}

// Charging status
static BOOL isChargingEnabled(void) {
    if (supports_tahoe) {
        NSString *hex = SMCReadHex("CHTE");
        return [hex isEqualToString:@"00000000"];
    } else if (supports_legacy) {
        NSString *hex = SMCReadHex("CH0B");
        return [hex isEqualToString:@"00"];
    }
    return YES; // Assume enabled if unknown
}

// Adapter status
static BOOL isAdapterEnabled(void) {
    NSString *hex = nil;
    if (supports_chie) {
        hex = SMCReadHex("CHIE");
        return [hex isEqualToString:@"00"];
    } else if (supports_ch0j) {
        hex = SMCReadHex("CH0J");
        return [hex isEqualToString:@"00"];
    } else if (supports_ch0i) {
        hex = SMCReadHex("CH0I");
        return [hex isEqualToString:@"00"];
    }
    return YES; // Assume enabled if unknown
}

// Enable adapter (normal power from charger)
static BOOL enableAdapter(void) {
    kern_return_t result = kIOReturnError;
    UInt8 byte = 0x00;
    if (supports_chie) {
        result = SMCWriteKey("CHIE", &byte, 1);
    } else if (supports_ch0j) {
        result = SMCWriteKey("CH0J", &byte, 1);
    } else if (supports_ch0i) {
        result = SMCWriteKey("CH0I", &byte, 1);
    }
    return result == kIOReturnSuccess;
}

// Disable adapter (force discharge even when plugged in)
static BOOL disableAdapter(void) {
    kern_return_t result = kIOReturnError;
    if (supports_chie) {
        UInt8 byte = 0x08;
        result = SMCWriteKey("CHIE", &byte, 1);
    } else if (supports_ch0j) {
        UInt8 byte = 0x01;
        result = SMCWriteKey("CH0J", &byte, 1);
    } else if (supports_ch0i) {
        UInt8 byte = 0x01;
        result = SMCWriteKey("CH0I", &byte, 1);
    }
    return result == kIOReturnSuccess;
}

// Enable charging (also disables forced discharge, following battery.sh logic)
static BOOL enableCharging(void) {
    kern_return_t result;

    // First, disable forced discharge (enable adapter)
    enableAdapter();

    // Then enable charging
    if (supports_tahoe) {
        UInt8 bytes[] = {0x00, 0x00, 0x00, 0x00};
        result = SMCWriteKey("CHTE", bytes, 4);
    } else if (supports_legacy) {
        UInt8 byte = 0x00;
        result = SMCWriteKey("CH0B", &byte, 1);
        if (result == kIOReturnSuccess) {
            result = SMCWriteKey("CH0C", &byte, 1);
        }
    } else {
        return NO;
    }
    return result == kIOReturnSuccess;
}

// Disable charging
static BOOL disableCharging(void) {
    kern_return_t result;
    if (supports_tahoe) {
        UInt8 bytes[] = {0x01, 0x00, 0x00, 0x00};
        result = SMCWriteKey("CHTE", bytes, 4);
    } else if (supports_legacy) {
        UInt8 byte = 0x02;
        result = SMCWriteKey("CH0B", &byte, 1);
        if (result == kIOReturnSuccess) {
            result = SMCWriteKey("CH0C", &byte, 1);
        }
    } else {
        return NO;
    }
    return result == kIOReturnSuccess;
}

static void printUsage(void) {
    fprintf(stderr, "Usage: battery_control <command> [args]\n");
    fprintf(stderr, "Commands:\n");
    fprintf(stderr, "  status       - Show current charging status (JSON)\n");
    fprintf(stderr, "  enable       - Enable charging\n");
    fprintf(stderr, "  disable      - Disable charging\n");
    fprintf(stderr, "  adapter on   - Enable adapter (normal power)\n");
    fprintf(stderr, "  adapter off  - Disable adapter (force discharge)\n");
    fprintf(stderr, "  caps         - Show SMC capabilities\n");
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printUsage();
            return 1;
        }

        kern_return_t result = SMCOpen();
        if (result != kIOReturnSuccess) {
            fprintf(stderr, "Failed to open SMC connection: 0x%x\n", result);
            fprintf(stderr, "Make sure to run with sudo\n");
            return 1;
        }

        detectCapabilities();

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        int exitCode = 0;

        if ([command isEqualToString:@"status"]) {
            NSDictionary *status = @{
                @"charging_enabled": @(isChargingEnabled()),
                @"adapter_enabled": @(isAdapterEnabled()),
                @"smc_type": getSmcType(),
                @"supports_tahoe": @(supports_tahoe),
                @"supports_legacy": @(supports_legacy),
                @"supports_adapter_control": @(supports_chie || supports_ch0i || supports_ch0j),
            };
            NSError *error = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:&error];
            if (json) {
                fwrite(json.bytes, 1, json.length, stdout);
                printf("\n");
            } else {
                fprintf(stderr, "JSON error: %s\n", error.localizedDescription.UTF8String);
                exitCode = 1;
            }
        } else if ([command isEqualToString:@"enable"]) {
            if (enableCharging()) {
                printf("{\"success\":true,\"action\":\"enable_charging\"}\n");
            } else {
                fprintf(stderr, "Failed to enable charging\n");
                exitCode = 1;
            }
        } else if ([command isEqualToString:@"disable"]) {
            if (disableCharging()) {
                printf("{\"success\":true,\"action\":\"disable_charging\"}\n");
            } else {
                fprintf(stderr, "Failed to disable charging\n");
                exitCode = 1;
            }
        } else if ([command isEqualToString:@"adapter"]) {
            if (argc < 3) {
                fprintf(stderr, "Usage: battery_control adapter <on|off>\n");
                exitCode = 1;
            } else {
                NSString *setting = [NSString stringWithUTF8String:argv[2]];
                // Match battery.sh semantics:
                // adapter on  = enable_discharging (force battery use)
                // adapter off = disable_discharging (normal adapter power)
                if ([setting isEqualToString:@"on"]) {
                    if (disableAdapter()) {
                        printf("{\"success\":true,\"action\":\"force_discharge\"}\n");
                    } else {
                        fprintf(stderr, "Failed to force discharge\n");
                        exitCode = 1;
                    }
                } else if ([setting isEqualToString:@"off"]) {
                    if (enableAdapter()) {
                        printf("{\"success\":true,\"action\":\"normal_power\"}\n");
                    } else {
                        fprintf(stderr, "Failed to enable normal power\n");
                        exitCode = 1;
                    }
                } else {
                    fprintf(stderr, "Invalid adapter setting: %s\n", argv[2]);
                    exitCode = 1;
                }
            }
        } else if ([command isEqualToString:@"caps"]) {
            NSDictionary *caps = @{
                @"tahoe": @(supports_tahoe),
                @"legacy": @(supports_legacy),
                @"chie": @(supports_chie),
                @"ch0i": @(supports_ch0i),
                @"ch0j": @(supports_ch0j),
                @"smc_type": getSmcType(),
            };
            NSError *error = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:caps options:NSJSONWritingPrettyPrinted error:&error];
            if (json) {
                fwrite(json.bytes, 1, json.length, stdout);
                printf("\n");
            }
        } else if ([command isEqualToString:@"debug"]) {
            // Debug: try to read a known key and show raw result
            printf("Testing SMC key reads...\n");
            const char *keys[] = {"CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J", "BCLM", "CHWA", "CH0K", "CHLC", "BFCL"};
            int numKeys = sizeof(keys) / sizeof(keys[0]);
            for (int i = 0; i < numKeys; i++) {
                SMCKeyData_t inputStructure = {0};
                SMCKeyData_t outputStructure = {0};
                inputStructure.key = _strtoul(keys[i], 4, 0);
                inputStructure.data8 = SMC_CMD_READ_KEYINFO;
                kern_return_t result = SMCCall(KERNEL_INDEX_SMC, &inputStructure, &outputStructure);
                if (result == kIOReturnSuccess && outputStructure.keyInfo.dataSize > 0) {
                    NSString *hex = SMCReadHex(keys[i]);
                    printf("  %s: dataSize=%u, value=%s\n", keys[i], outputStructure.keyInfo.dataSize, hex ? [hex UTF8String] : "?");
                } else {
                    printf("  %s: not found (result=0x%x)\n", keys[i], result);
                }
            }
        } else {
            fprintf(stderr, "Unknown command: %s\n", argv[1]);
            printUsage();
            exitCode = 1;
        }

        SMCClose();
        return exitCode;
    }
}
