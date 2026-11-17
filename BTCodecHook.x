// BTCodecHook.x
// Discovery version – injected into bluetoothd

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <dlfcn.h>
#include <notify.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>

#import "BTCodecCommon.h"

static int            sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID      sCurrentCodecID = BTCodecID_Unknown;

#define BTCODEC_LOG_PATH "/var/tmp/btcodec_debug.txt"

static void BTCodec_LogToFile(const char *fmt, ...) {
    FILE *f = fopen(BTCODEC_LOG_PATH, "a");
    if (!f) return;

    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    char ts[32];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm);

    fprintf(f, "[%s] ", ts);

    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);

    fputc('\n', f);
    fclose(f);
}

static void BTCodec_Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    BTCodec_LogToFile("%s", msg.UTF8String);
}

static const char *BTCodecIDDescription(BTCodecID codecID) {
    switch (codecID) {
        case BTCodecID_SBC:       return "SBC";
        case BTCodecID_MPEG12:    return "MPEG-1/2";
        case BTCodecID_AAC:       return "AAC";
        case BTCodecID_ATRAC:     return "ATRAC";
        case BTCodecID_VendorExt: return "Vendor";
        default:                  return "Unknown";
    }
}

static void BTCodec_PostIfChanged(BTCodecID codecID, uint32_t bitrate_kbps) {
    if (codecID == sCurrentCodecID) return;
    sCurrentCodecID = codecID;

    if (sStateToken == NOTIFY_TOKEN_INVALID) {
        notify_register_check(kBTCodecNotifName, &sStateToken);
    }

    uint64_t state = BTCodecMakeState(codecID, bitrate_kbps);
    notify_set_state(sStateToken, state);
    notify_post(kBTCodecNotifName);

    BTCodec_Log(@"Posted state → codec=%s (%u), bitrate=%u kbps",
                BTCodecIDDescription(codecID), codecID, bitrate_kbps);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

static BOOL BTCodec_SelectorLooksInteresting(const char *name) {
    if (!name) return NO;

    // Convert to lowercase for matching
    char lower[256];
    size_t len = strlen(name);
    if (len >= sizeof(lower)) len = sizeof(lower) - 1;
    for (size_t i = 0; i < len; i++) {
        lower[i] = (char)tolower((unsigned char)name[i]);
    }
    lower[len] = '\0';

    const char *keywords[] = {
        "codec", "a2dp", "avdtp", "bitrate", "bit rate", "audio",
        "stream", "sbc", "aac", "mpeg", "atrac", "negotiate",
        "configured", "configuration", "vendor", NULL
    };

    for (int i = 0; keywords[i]; i++) {
        if (strstr(lower, keywords[i])) return YES;
    }
    return NO;
}

static void BTCodec_DumpInterestingMethods(Class cls) {
    if (!cls) {
        BTCodec_LogToFile("BTDevice class not found");
        return;
    }

    BTCodec_LogToFile("--- Dumping interesting methods on %s ---", class_getName(cls));

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);

    int found = 0;
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *name = sel_getName(sel);
        if (BTCodec_SelectorLooksInteresting(name)) {
            BTCodec_LogToFile("  %s", name);
            found++;
        }
    }

    free(methods);
    BTCodec_LogToFile("--- Found %d interesting methods ---", found);
}

// ── Interface ─────────────────────────────────────────────────────────────────

@interface BTDevice : NSObject
@property (nonatomic, readonly, copy) NSString *address;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, assign) NSUInteger a2dpCodecType;
@property (nonatomic, assign) NSUInteger a2dpNegotiatedBitrate;
@end

// ── Hooks ─────────────────────────────────────────────────────────────────────

%hook BTDevice

// Original target
- (void)setA2dpCodecType:(NSUInteger)codecType {
    %orig;
    BTCodec_Log(@"!!! setA2dpCodecType: fired → %lu", (unsigned long)codecType);
}

// Common alternative names
- (void)setCodecType:(NSUInteger)type {
    %orig;
    BTCodec_Log(@"setCodecType: %lu", (unsigned long)type);
}

- (void)setA2DPCodec:(NSUInteger)type {
    %orig;
    BTCodec_Log(@"setA2DPCodec: %lu", (unsigned long)type);
}

- (void)setA2dpCodec:(NSUInteger)type {
    %orig;
    BTCodec_Log(@"setA2dpCodec: %lu", (unsigned long)type);
}

- (void)setNegotiatedCodec:(NSUInteger)type {
    %orig;
    BTCodec_Log(@"setNegotiatedCodec: %lu", (unsigned long)type);
}

- (void)setNegotiatedCodecType:(NSUInteger)type {
    %orig;
    BTCodec_Log(@"setNegotiatedCodecType: %lu", (unsigned long)type);
}

- (void)setCodec:(NSUInteger)type {
    %orig;
    BTCodec_Log(@"setCodec: %lu", (unsigned long)type);
}

%end

// ── Constructor ───────────────────────────────────────────────────────────────

%ctor {
    BTCodec_LogToFile("Constructor entered (pid %d)", getpid());

    NSString *procName = nil;
    @try {
        procName = [NSProcessInfo processInfo].processName;
    } @catch (NSException *e) {
        BTCodec_LogToFile("Failed to get processName: %s", e.reason.UTF8String ?: "unknown");
        return;
    }

    BTCodec_Log(@"Constructor fired for process: %@", procName);

    if (![procName isEqualToString:@"bluetoothd"]) {
        BTCodec_LogToFile("Not bluetoothd — exiting constructor");
        return;
    }

    BTCodec_LogToFile("bluetoothd matched — dylib loaded successfully");

    // Discovery: dump interesting methods on BTDevice
    Class btDeviceClass = objc_getClass("BTDevice");
    BTCodec_DumpInterestingMethods(btDeviceClass);

    // Also try a couple of other classes that sometimes appear
    BTCodec_DumpInterestingMethods(objc_getClass("BluetoothDevice"));
    BTCodec_DumpInterestingMethods(objc_getClass("BTAudioDevice"));
    BTCodec_DumpInterestingMethods(objc_getClass("BTClassicDevice"));
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
