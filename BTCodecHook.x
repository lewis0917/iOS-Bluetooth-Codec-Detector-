// BTCodecHook.x
// Injected into bluetoothd via BTCodecDaemon.plist

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#include <dlfcn.h>
#include <notify.h>
#include <os/log.h>
#include <pthread.h>
#include <unistd.h>

#import "BTCodecCommon.h"

static os_log_t       sLog            = NULL;
static int            sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID      sCurrentCodecID = BTCodecID_Unknown;

static pthread_t      sLogThread;
static _Atomic(bool)  sLogThreadRunning = false;

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

        // Write directly to /tmp/ where bluetoothd has sandbox write access
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

%ctor {
    NSString *procName = [NSProcessInfo processInfo].processName;
    if (![procName isEqualToString:@"bluetoothd"]) return;

    sLog = os_log_create("com.btcodectweak", "daemon");
    os_log(sLog, "[BTCodecDaemon] Loading — pid %d", getpid());

    // Trigger diagnostic dump
    BTCodec_DumpClasses();

    os_log(sLog, "[BTCodecDaemon] Setup complete");
}
