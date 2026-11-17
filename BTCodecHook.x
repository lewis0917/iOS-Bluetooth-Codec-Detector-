// BTCodecHook.x
// Injected into bluetoothd via BTCodecDaemon.plist

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <dlfcn.h>
#include <notify.h>
#include <os/log.h>
#include <unistd.h>

#import "BTCodecCommon.h"

static os_log_t       sLog            = NULL;
static int            sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID      sCurrentCodecID = BTCodecID_Unknown;

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

// ── Private BluetoothManager.framework stubs ──────────────────────────────────

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

    os_log(sLog, "[BTCodecDaemon] setA2dpCodecType fired: %lu", (unsigned long)codecType);

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

// ── Diagnostic: runtime class + selector dump to /tmp/ ────────────────────────

static void BTCodec_DumpClasses(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSMutableString *out = [NSMutableString string];

        int numClasses = objc_getClassList(NULL, 0);
        Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
        objc_getClassList(classes, numClasses);

        for (int i = 0; i < numClasses; i++) {
            NSString *name = NSStringFromClass(classes[i]);
            NSString *lower = name.lowercaseString;

            BOOL btRelated = [lower hasPrefix:@"bt"]             ||
                             [lower containsString:@"bluetooth"]  ||
                             [lower containsString:@"a2dp"]       ||
                             [lower containsString:@"avdtp"];
            if (!btRelated) continue;

            NSMutableString *section = [NSMutableString string];
            unsigned int count = 0;
            Method *methods = class_copyMethodList(classes[i], &count);
            for (unsigned int j = 0; j < count; j++) {
                NSString *sel = NSStringFromSelector(method_getName(methods[j]));
                NSString *selLower = sel.lowercaseString;
                if ([selLower containsString:@"codec"]   ||
                    [selLower containsString:@"a2dp"]    ||
                    [selLower containsString:@"bitrate"] ||
                    [selLower containsString:@"format"]  ||
                    [selLower containsString:@"stream"]  ||
                    [selLower containsString:@"audio"]) {
                    [section appendFormat:@"  %@\n", sel];
                }
            }
            if (count > 0) free(methods);

            if (section.length > 0) {
                [out appendFormat:@"\n=== %@ ===\n%@", name, section];
            }
        }
        free(classes);

        if (out.length == 0) {
            [out appendString:@"No BT/codec methods found in bluetoothd process\n"];
        }

        NSString *path = @"/tmp/btd_classes.txt";
        NSError *err = nil;
        BOOL ok = [out writeToFile:path
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:&err];
        
        if (sLog) {
            os_log(sLog, "[BTCodecDaemon] class dump written to /tmp/: %d (%@)", ok, err);
        }
    });
}

// ── Constructor ────────────────────────────────────────────────────────────────

%ctor {
    NSString *procName = [NSProcessInfo processInfo].processName;
    if (![procName isEqualToString:@"bluetoothd"]) return;

    sLog = os_log_create("com.btcodectweak", "daemon");
    os_log(sLog, "[BTCodecDaemon] Loading — pid %d", getpid());

    BTCodec_DumpClasses();

    os_log(sLog, "[BTCodecDaemon] Setup complete");
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
