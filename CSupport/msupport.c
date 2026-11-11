#include "msupport.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

// ---------------------------------------------------------------- temperature (IOHIDEventSystem)
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kIOHIDEventTypeTemperature 15
#define IOHIDEventFieldBase(type) ((type) << 16)

static IOHIDEventSystemClientRef hidClient = NULL;

CFArrayRef ms_copy_temperatures(void) {
    if (!hidClient) {
        hidClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!hidClient) return NULL;
        // Usage page 0xff00, usage 5 = sensori di temperatura Apple
        int page = 0xff00, usage = 5;
        CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *vals[] = { p, u };
        CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDEventSystemClientSetMatching(hidClient, match);
        CFRelease(match); CFRelease(p); CFRelease(u);
    }
    CFArrayRef services = IOHIDEventSystemClientCopyServices(hidClient);
    if (!services) return NULL;
    CFMutableArrayRef out = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
        IOHIDServiceClientRef s = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        CFTypeRef name = IOHIDServiceClientCopyProperty(s, CFSTR("Product"));
        IOHIDEventRef ev = IOHIDServiceClientCopyEvent(s, kIOHIDEventTypeTemperature, 0, 0);
        if (name && ev && CFGetTypeID(name) == CFStringGetTypeID()) {
            double v = IOHIDEventGetFloatValue(ev, IOHIDEventFieldBase(kIOHIDEventTypeTemperature));
            if (v > -40 && v < 150) {
                CFNumberRef n = CFNumberCreate(NULL, kCFNumberDoubleType, &v);
                const void *k[] = { CFSTR("name"), CFSTR("value") };
                const void *vv[] = { name, n };
                CFDictionaryRef d = CFDictionaryCreate(NULL, k, vv, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                CFArrayAppendValue(out, d);
                CFRelease(d); CFRelease(n);
            }
        }
        if (ev) CFRelease(ev);
        if (name) CFRelease(name);
    }
    CFRelease(services);
    return out;
}

// ---------------------------------------------------------------- SMC
typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize; uint32_t dataType; char dataAttributes; } SMCKeyInfoData;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    char result, status, data8;
    uint32_t data32;
    unsigned char bytes[32];
} SMCKeyData;

enum { kSMCUserClient = 2, kSMCReadKey = 5, kSMCGetKeyInfo = 9 };

static io_connect_t smcConn = 0;

int ms_smc_open(void) {
    if (smcConn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &smcConn);
    IOObjectRelease(svc);
    return kr == KERN_SUCCESS ? 0 : -1;
}

void ms_smc_close(void) {
    if (smcConn) { IOServiceClose(smcConn); smcConn = 0; }
}

static uint32_t fourcc(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3];
}

static int smc_call(SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(smcConn, kSMCUserClient, in, sizeof(SMCKeyData), out, &outSize) == KERN_SUCCESS ? 0 : -1;
}

int ms_smc_read_number(const char *key, double *out) {
    if (!smcConn && ms_smc_open() != 0) return -1;
    if (strlen(key) != 4) return -1;
    SMCKeyData in, info, val;
    memset(&in, 0, sizeof in); memset(&info, 0, sizeof info); memset(&val, 0, sizeof val);
    in.key = fourcc(key);
    in.data8 = kSMCGetKeyInfo;
    if (smc_call(&in, &info) != 0 || info.result != 0) return -1;
    in.keyInfo.dataSize = info.keyInfo.dataSize;
    in.data8 = kSMCReadKey;
    if (smc_call(&in, &val) != 0 || val.result != 0) return -1;

    uint32_t type = info.keyInfo.dataType, size = info.keyInfo.dataSize;
    const unsigned char *b = val.bytes;
    if (type == fourcc("flt ") && size == 4) { float f; memcpy(&f, b, 4); *out = f; return 0; }
    if (type == fourcc("ui8 ")) { *out = b[0]; return 0; }
    if (type == fourcc("ui16")) { *out = (b[0] << 8) | b[1]; return 0; }
    if (type == fourcc("ui32")) { *out = ((uint32_t)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]; return 0; }
    if (type == fourcc("fpe2")) { *out = ((b[0] << 8) | b[1]) / 4.0; return 0; }
    if (type == fourcc("sp78")) { *out = (int16_t)((b[0] << 8) | b[1]) / 256.0; return 0; }
    return -1;
}
