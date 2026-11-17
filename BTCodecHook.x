// BTCodecHook.x
// Hooking BluetoothDevice & probing AAC capabilities on iOS 18

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <dlfcn.h>
#include <notify.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <ctype.h>
#include <string.h>

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

// ── Interface Definition for BluetoothDevice ──────────────────────────────────

@interface BluetoothDevice : NSObject
- (NSString *)address;
- (NSString *)name;
- (BOOL)isAppleAudioDevice;
- (NSInteger)getAACCapabilityInteger:(NSInteger)arg;
- (NSUInteger)getAACCapabilityBits;
@end

// ── Hooks ─────────────────────────────────────────────────────────────────────

%hook BluetoothDevice

- (void)setA2dpCodecType:(NSUInteger)codecType {
    %orig;
    BTCodec_Log(@"[BluetoothDevice] setA2dpCodecType: %lu", (unsigned long)codecType);

    BTCodec_Log(@"  isAppleAudioDevice: %d", [self respondsToSelector:@selector(isAppleAudioDevice)] ? [self isAppleAudioDevice] : -1);

    // Probe getAACCapabilityInteger with common index arguments (0, 1, 2, etc.)
    if ([self respondsToSelector:@selector(getAACCapabilityInteger:)]) {
        for (NSInteger i = 0; i < 5; i++) {
            @try {
                NSInteger capVal = [self getAACCapabilityInteger:i];
                BTCodec_Log(@"  getAACCapabilityInteger(%ld) -> %ld", (long)i, (long)capVal);
            } @catch (NSException *e) {
                BTCodec_Log(@"  getAACCapabilityInteger(%ld) threw: %@", (long)i, e.reason);
            }
        }
    }

    if ([self respondsToSelector:@selector(getAACCapabilityBits)]) {
        @try {
            NSUInteger bits = [self getAACCapabilityBits];
            BTCodec_Log(@"  getAACCapabilityBits -> %lu", (unsigned long)bits);
        } @catch (NSException *e) {
            BTCodec_Log(@"  getAACCapabilityBits threw: %@", e.reason);
        }
    }
}

// Also hook general connection or stream init if they fire
- (void)connect {
    %orig;
    BTCodec_Log(@"[BluetoothDevice] connect fired for name: %@ (%@)", 
                [self respondsToSelector:@selector(name)] ? [self name] : @"nil",
                [self respondsToSelector:@selector(address)] ? [self address] : @"nil");
}

%end

// ── Constructor ────────────────────────────────________________───────────────

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

    BTCodec_LogToFile("bluetoothd matched — BluetoothDevice hook loaded successfully");
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
