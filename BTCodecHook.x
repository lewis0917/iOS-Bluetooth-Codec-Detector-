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
    fclose(f);
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
    BTCodec_FileLog("Posted codec=%d bitrate=%u", (int)codecID, bitrate);
}

// CBAudioLinkQualityInfo interface stubs
@interface CBAudioLinkQualityInfo : NSObject
@property (nonatomic, assign) NSInteger codecType;
@property (nonatomic, assign) NSInteger bitRate;
@end

%hook CBAudioLinkQualityInfo

- (id)init {
    id orig = %orig;
    BTCodec_FileLog("CBAudioLinkQualityInfo init called");
    return orig;
}

- (NSInteger)codecType {
    NSInteger origCodec = %orig;
    BTCodecID codecID;
    switch (origCodec) {
        case 0:  codecID = BTCodecID_SBC; break;
        case 2:  
        case 10: codecID = BTCodecID_AAC; break;
        default: codecID = BTCodecID_Unknown; break;
    }

    if (codecID != BTCodecID_Unknown) {
        NSInteger rawBitrate = [self respondsToSelector:@selector(bitRate)] ? [self bitRate] : 0;
        uint32_t bitrate = (rawBitrate > 0) ? (uint32_t)rawBitrate : 327000;
        BTCodec_PostIfChanged(codecID, bitrate);
    }
    
    return origCodec;
}

- (void)setCodecType:(NSInteger)newCodecType {
    BTCodec_FileLog("CBAudioLinkQualityInfo setCodecType fired with: %ld  bitRate: %ld",
                    (long)newCodecType,
                    (long)([self respondsToSelector:@selector(bitRate)] ? [self bitRate] : -1));
    %orig;

    BTCodecID codecID;
    switch (newCodecType) {
        case 0:  codecID = BTCodecID_SBC; break;
        case 2:  
        case 10: codecID = BTCodecID_AAC; break;
        default: return;
    }

    NSInteger rawBitrate = [self respondsToSelector:@selector(bitRate)] ? [self bitRate] : 0;
    uint32_t bitrate = (rawBitrate > 0) ? (uint32_t)rawBitrate : (codecID == BTCodecID_AAC ? 327000 : 212000);

    BTCodec_PostIfChanged(codecID, bitrate);
}

- (void)setBitRate:(NSInteger)newBitRate {
    BTCodec_FileLog("CBAudioLinkQualityInfo setBitRate fired with: %ld", (long)newBitRate);
    %orig;

    if (newBitRate > 0) {
        NSInteger currentCodec = [self respondsToSelector:@selector(codecType)] ? [self codecType] : 10;
        BTCodecID codecID;
        switch (currentCodec) {
            case 0:  codecID = BTCodecID_SBC; break;
            case 2:  
            case 10: codecID = BTCodecID_AAC; break;
            default: codecID = BTCodecID_AAC; break;
        }
        BTCodec_PostIfChanged(codecID, (uint32_t)newBitRate);
    }
}

%end

// BTAudioSession hooks to track stream routing lifecycle
%hook BTAudioSession

- (void)activateWithCompletion:(id)completion {
    BTCodec_FileLog("BTAudioSession activateWithCompletion called");
    %orig;
}

- (void)setCategory:(NSString *)category {
    BTCodec_FileLog("BTAudioSession setCategory: %@", category);
    %orig;
}

- (void)setMode:(NSString *)mode {
    BTCodec_FileLog("BTAudioSession setMode: %@", mode);
    %orig;
}

%end

%ctor {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"bluetoothd"]) return;
    BTCodec_FileLog("BTCodecDaemon loaded in bluetoothd (pid %d)", getpid());
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
