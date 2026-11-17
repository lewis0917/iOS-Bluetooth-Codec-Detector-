That explains it. Remember the log output from earlier? When we looked for BTDevice, it logged "Class not found". That means BTDevice isn't a registered Objective-C class name in iOS 18's bluetoothd, so our hook for setA2dpCodecType: was never actually attaching to anything. When we switched the hook to BluetoothDevice, BluetoothDevice loaded successfully, but it doesn't have a setA2dpCodecType: method, so playing audio didn't trigger it.
To find the exact class names Apple is using for audio and codecs in iOS 18, we can write a quick Class Discovery pass into the constructor. This will scan all runtime classes and log any class name containing keywords like Audio, Codec, Stream, A2DP, or Device.
Here is the updated discovery hook code:
// BTCodecHook.x
// Class & Method Discovery for iOS 18 bluetoothd

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

__attribute__((unused)) static int            sStateToken     = NOTIFY_TOKEN_INVALID;
__attribute__((unused)) static BTCodecID      sCurrentCodecID = BTCodecID_Unknown;

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

// Dump all runtime classes matching keywords
static void BTCodec_DumpMatchingClasses(void) {
    BTCodec_LogToFile("=== Dumping Matching Runtime Classes ===");
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) return;

    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    const char *keywords[] = { "audio", "codec", "a2dp", "avdtp", "stream", "device", "bluetooth", NULL };

    for (int i = 0; i < numClasses; i++) {
        const char *className = class_getName(classes[i]);
        char lower[256];
        size_t len = strlen(className);
        if (len >= sizeof(lower)) len = sizeof(lower) - 1;
        for (size_t j = 0; j < len; j++) lower[j] = (char)tolower((unsigned char)className[j]);
        lower[len] = '\0';

        for (int k = 0; keywords[k]; k++) {
            if (strstr(lower, keywords[k])) {
                BTCodec_LogToFile("  Found class: %s", className);
                break;
            }
        }
    }
    free(classes);
    BTCodec_LogToFile("=== End Class Dump ===");
}

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

    if (![procName isEqualToString:@"bluetoothd"]) {
        return;
    }

    BTCodec_LogToFile("bluetoothd matched — running class discovery");
    BTCodec_DumpMatchingClasses();
}

%dtor {
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}

Next Steps
 * Build and install this discovery version.
 * Cycle the daemon (Airplane Mode toggle or restart).
 * Check the log file:
   cat /var/tmp/btcodec_debug.txt

This will output every single class name in bluetoothd related to audio, codecs, A2DP, and devices on iOS 18 so we can target the exact right class.
