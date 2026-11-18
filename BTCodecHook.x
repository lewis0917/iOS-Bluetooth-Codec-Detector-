// BTCodecHook.x — iOS 18 bluetoothd, Dopamine rootless
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <notify.h>
#include <stdio.h>
#include <time.h>

#import "BTCodecCommon.h"

#define LOG_PATH "/var/tmp/btcodec_daemon.txt"

static int       sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID sCurrentCodecID = BTCodecID_Unknown;
static uint32_t  sCurrentBitrate = 0;

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
    fflush(f);
    fclose(f);
}

// Normalize raw bitrate — CBAudioLinkQualityInfo.bitRate appears to be bps.
// Values > 1000 are assumed bps and converted; values <= 1000 are already kbps.
// No A2DP codec exceeds 1000 kbps, so this heuristic is reliable.
static uint32_t BTCodec_NormalizeBitrate(NSInteger raw, BTCodecID codecID) {
    if (raw > 1000) return (uint32_t)(raw / 1000);
    if (raw > 0)    return (uint32_t)raw;
    return (codecID == BTCodecID_AAC) ? 256 : 328;
}

static void BTCodec_PostIfChanged(BTCodecID codecID, uint32_t bitrate) {
    if (codecID == sCurrentCodecID && sCurrentBitrate == bitrate) return;
    sCurrentCodecID = codecID;
    sCurrentBitrate = bitrate;

    if (sStateToken == NOTIFY_TOKEN_INVALID) {
        notify_register_check(kBTCodecNotifName, &sStateToken);
    }
    notify_set_state(sStateToken, BTCodecMakeState(codecID, bitrate));
    notify_post(kBTCodecNotifName);
    BTCodec_FileLog("Posted codec=%d bitrate=%u kbps", (int)codecID, bitrate);
}

@interface CBAudioLinkQualityInfo : NSObject
@property (nonatomic, assign) NSInteger codecType;
@property (nonatomic, assign) NSInteger bitRate;
@end

%hook CBAudioLinkQualityInfo

// Setter-only hooks — no getter hook.
// The getter fires on every property read and causes constant spurious posts.
// Setters fire exactly when the codec is negotiated.

- (void)setCodecType:(NSInteger)newCodecType {
    %orig;
    BTCodec_FileLog("setCodecType: %ld  bitRate: %ld",
                    (long)newCodecType,
                    (long)([self respondsToSelector:@selector(bitRate)] ? [self bitRate] : -1));

    BTCodecID codecID;
    switch (newCodecType) {
        case 0:  codecID = BTCodecID_SBC; break;
        case 2:
        case 10: codecID = BTCodecID_AAC; break;
        default:
            BTCodec_FileLog("  → unknown codecType %ld", (long)newCodecType);
            return;
    }

    NSInteger raw = [self respondsToSelector:@selector(bitRate)] ? [self bitRate] : 0;
    BTCodec_PostIfChanged(codecID, BTCodec_NormalizeBitrate(raw, codecID));
}

- (void)setBitRate:(NSInteger)newBitRate {
    %orig;
    BTCodec_FileLog("setBitRate: %ld", (long)newBitRate);

    if (newBitRate <= 0) return;

    // Read codecType directly — no getter hook, safe to call.
    NSInteger rawCodec = [self respondsToSelector:@selector(codecType)] ? [self codecType] : -1;
    BTCodecID codecID;
    switch (rawCodec) {
        case 0:  codecID = BTCodecID_SBC; break;
        case 2:
        case 10: codecID = BTCodecID_AAC; break;
        default: return;  // unknown codec, don't post
    }

    BTCodec_PostIfChanged(codecID, BTCodec_NormalizeBitrate(newBitRate, codecID));
}

%end

%ctor {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"bluetoothd"]) return;
    BTCodec_FileLog("BTCodecDaemon loaded (pid %d)", getpid());
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
