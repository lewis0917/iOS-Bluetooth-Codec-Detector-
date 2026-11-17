// BTCodecHook.x
// Injected into bluetoothd via BTCodecDaemon.plist

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

// ── Interface Definition ──────────────────────────────────────────────────────

@interface BTDevice : NSObject
@property (nonatomic, readonly, copy) NSString *address;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, assign) NSUInteger a2dpCodecType;
@property (nonatomic, assign) NSUInteger a2dpNegotiatedBitrate;
@end

// ── Layer 1: ObjC hook — BTDevice ─────────────────────────────────────────────

%hook BTDevice

- (void)setA2dpCodecType:(NSUInteger)codecType {
    %orig;

    BTCodec_Log(@"=== setA2dpCodecType: %lu ===", (unsigned long)codecType);
    BTCodec_Log(@"  self     = %p", self);
    BTCodec_Log(@"  address  = %@", [self respondsToSelector:@selector(address)] ? [self address] : @"n/a");
    BTCodec_Log(@"  name     = %@", [self respondsToSelector:@selector(name)]    ? [self name]    : @"n/a");

    // ── Diagnostic: probe common bitrate-related selectors ───────────────────
    NSArray *bitrateSelectors = @[
        @"a2dpNegotiatedBitrate",
        @"negotiatedBitrate",
        @"bitrate",
        @"a2dpBitrate",
        @"codecBitrate",
        @"maxBitrate",
        @"vbrMaxBitrate",
        @"a2dpCodecBitrate",
        @"negotiatedA2DPBitrate"
    ];

    for (NSString *selName in bitrateSelectors) {
        SEL sel = NSSelectorFromString(selName);
        if ([self respondsToSelector:sel]) {
            BTCodec_Log(@"  selector '%@' exists", selName);
            @try {
                NSUInteger val = ((NSUInteger (*)(id, SEL))objc_msgSend)(self, sel);
                BTCodec_Log(@"    → value: %lu", (unsigned long)val);
            } @catch (NSException *e) {
                BTCodec_Log(@"    → call failed: %@", e.reason ?: @"unknown");
            }
        }
    }

    // ── Map incoming codecType to our BTCodecID ──────────────────────────────
    BTCodecID codecID = BTCodecID_Unknown;
    switch (codecType) {
        case 0:
        case 1:
            codecID = BTCodecID_SBC;
            break;
        case 2:
        case 4:
            codecID = BTCodecID_AAC;
            break;
        case 8:
            codecID = BTCodecID_ATRAC;
            break;
        case 255:
            codecID = BTCodecID_VendorExt;
            break;
        default:
            codecID = BTCodecID_Unknown;
            BTCodec_Log(@"  Unknown codecType raw value: %lu", (unsigned long)codecType);
            break;
    }

    // ── Bitrate extraction ───────────────────────────────────────────────────
    uint32_t bitrate = 0;
    if ([self respondsToSelector:@selector(a2dpNegotiatedBitrate)]) {
        bitrate = (uint32_t)[self a2dpNegotiatedBitrate];
    }

    if (codecID == BTCodecID_AAC && bitrate == 0) {
        bitrate = 256;
        BTCodec_Log(@"  Using AAC fallback bitrate 256 kbps");
    }

    BTCodec_PostIfChanged(codecID, bitrate);
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
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
