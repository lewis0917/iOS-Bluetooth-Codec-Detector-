// BTCodecHook.x
// Injected into bluetoothd via BTCodecDaemon.plist

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <dlfcn.h>
#include <notify.h>
#include <unistd.h>

#import "BTCodecCommon.h"

static int            sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID      sCurrentCodecID = BTCodecID_Unknown;

static void BTCodec_LogToFile(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSString *path = @"/var/mobile/btcodec_debug.txt";
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
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

    BTCodec_LogToFile(@"setA2dpCodecType fired: %lu", (unsigned long)codecType);

    BTCodecID codecID = (codecType == BTCodecID_SBC    ||
                         codecType == BTCodecID_MPEG12  ||
                         codecType == BTCodecID_AAC    ||
                         codecType == BTCodecID_ATRAC  ||
                         codecType == BTCodecID_VendorExt)
                      ? (BTCodecID)(uint8_t)codecType
                      : BTCodecID_Unknown;

    uint32_t bitrate = 0;
    if ([self respondsToSelector:@selector(a2dpNegotiatedBitrate)]) {
        bitrate = (uint32_t)[self a2dpNegotiatedBitrate];
    }
    if (codecID == BTCodecID_AAC && bitrate == 0) bitrate = 256;

    BTCodec_PostIfChanged(codecID, bitrate);
}

%end

// ── Constructor ────────────────────────────────────────────────────────────────

%ctor {
    NSString *procName = [NSProcessInfo processInfo].processName;
    if (![procName isEqualToString:@"bluetoothd"]) return;

    BTCodec_LogToFile(@"Loading — pid %d", getpid());
    BTCodec_LogToFile(@"Setup complete");
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
