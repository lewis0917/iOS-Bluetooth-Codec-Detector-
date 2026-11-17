// BTCodecHook.x — iOS 18 bluetoothd, Dopamine rootless

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <notify.h>
#include <os/log.h>
#include <stdio.h>
#include <time.h>

#import "BTCodecCommon.h"

#define LOG_PATH "/var/tmp/btcodec_daemon.txt"

static int       sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID sCurrentCodecID = BTCodecID_Unknown;
static os_log_t  sLog            = NULL;

static void BTCodec_FileLog(const char *fmt, ...) {
    FILE *f = fopen(LOG_PATH, "a");
    if (!f) return;
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    char ts[32];
    strftime(ts, sizeof(ts), "%H:%M:%S", &tm);
    fprintf(f, "[%s] ", ts);
    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);
    fputc('\n', f);
    fclose(f);
}

static void BTCodec_PostIfChanged(BTCodecID codecID, uint32_t bitrate) {
    if (codecID == sCurrentCodecID) return;
    sCurrentCodecID = codecID;

    if (sStateToken == NOTIFY_TOKEN_INVALID) {
        notify_register_check(kBTCodecNotifName, &sStateToken);
    }
    notify_set_state(sStateToken, BTCodecMakeState(codecID, bitrate));
    notify_post(kBTCodecNotifName);
    BTCodec_FileLog("Posted codec=%d bitrate=%u", (int)codecID, bitrate);
}

// ── CBAudioLinkQualityInfo stubs ───────────────────────────────────────────────
// Present in bluetoothd on iOS 18 (confirmed via runtime class dump).
// codec values logged raw so we can map them on first connection.

@interface CBAudioLinkQualityInfo : NSObject
@property (nonatomic, assign) NSInteger codecType;
@property (nonatomic, assign) NSInteger bitRate;
@end

%hook CBAudioLinkQualityInfo

- (void)setCodecType:(NSInteger)newCodecType {
    %orig;

    // Log the raw value every time so we can confirm the mapping
    BTCodec_FileLog("CBAudioLinkQualityInfo setCodecType: %ld  bitRate: %ld",
                    (long)newCodecType,
                    (long)([self respondsToSelector:@selector(bitRate)] ? [self bitRate] : -1));

    BTCodecID codecID;
    switch (newCodecType) {
        case 0:  codecID = BTCodecID_SBC; break;
        case 2:  codecID = BTCodecID_AAC; break;
        // Log unknown values so we can extend the map later
        default:
            BTCodec_FileLog("  → unknown codecType %ld — skipping post", (long)newCodecType);
            return;
    }

    NSInteger rawBitrate = [self respondsToSelector:@selector(bitRate)] ? [self bitRate] : 0;
    uint32_t bitrate = (rawBitrate > 0)
                     ? (uint32_t)rawBitrate
                     : (codecID == BTCodecID_AAC ? 256 : 0);

    BTCodec_PostIfChanged(codecID, bitrate);
}

%end

// ── Targeted method dump for verification ─────────────────────────────────────
// Dumps ALL selectors on the classes most likely to carry codec state,
// so we can spot any renamed or additional hook targets.

static void BTCodec_DumpTargetedMethods(void) {
    NSArray *targets = @[
        @"CBAudioLinkQualityInfo",
        @"AudioAccessoryDeviceInfo",
        @"AudioAccessoryDeviceConfig",
        @"AudioAccessoryDevice",
        @"AudioDeviceManager",
        @"BluetoothDevice",
        @"BTAudioSession",
        @"BTAudioRoutingRequest",
    ];

    NSMutableString *out = [NSMutableString string];
    for (NSString *name in targets) {
        Class cls = NSClassFromString(name);
        [out appendFormat:@"\n=== %@ %@ ===\n", name, cls ? @"(found)" : @"(not found)"];
        if (!cls) continue;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            [out appendFormat:@"  %@\n", NSStringFromSelector(method_getName(methods[i]))];
        }
        if (count > 0) free(methods);
    }

    BTCodec_FileLog("--- targeted method dump ---\n%s", out.UTF8String);
}

// ── Constructor ────────────────────────────────────────────────────────────────

%ctor {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"bluetoothd"]) return;

    sLog = os_log_create("com.btcodectweak", "daemon");
    BTCodec_FileLog("BTCodecDaemon loaded in bluetoothd (pid %d)", getpid());
    BTCodec_DumpTargetedMethods();
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
