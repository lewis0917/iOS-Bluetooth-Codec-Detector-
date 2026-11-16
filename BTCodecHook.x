// BTCodecHook.x — injected into bluetoothd via BTCodecDaemon.plist

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#include <notify.h>
#include <os/log.h>

#import "BTCodecCommon.h"

static os_log_t sLog = NULL;

// ── Constructor ────────────────────────────────────────────────────────────────

%ctor {
    sLog = os_log_create("com.btcodectweak", "daemon");
    os_log_info(sLog, "[BTCodecDaemon] BTCodecHook loaded into bluetoothd process.");

    // Runtime class & method enumeration dump for bluetoothd (runs on background queue)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
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

            [out appendFormat:@"\n=== %@ ===\n", name];
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
                    [out appendFormat:@"  %@\n", sel];
                }
            }
            if (count > 0) free(methods);
        }
        free(classes);

        if (out.length == 0) {
            [out appendString:@"No BT classes found in bluetoothd process\n"];
        }

        NSString *dir = @"/var/mobile/Library/BTCodecTweak";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        [out writeToFile:[dir stringByAppendingPathComponent:@"btd_classes.txt"]
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
    });
}
