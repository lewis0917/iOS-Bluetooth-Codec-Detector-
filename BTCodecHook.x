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
