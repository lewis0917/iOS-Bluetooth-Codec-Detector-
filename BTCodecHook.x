// BTCodecHook.x
// Injected into bluetoothd via BTCodecDaemon.plist
//
// Detection strategy — three layers, each degrades gracefully:
//
//   Layer 1 — Logos ObjC hook on BTDevice.setA2dpCodecType:
//             Fires when bluetoothd updates the negotiated A2DP codec.
//             Class/property names are iOS 15–17 derived; may be renamed
//             in iOS 18 — the runtime dump block below identifies the
//             actual current names.
//
//   Layer 2 — MSHookFunction via dlsym against AVDTP C symbol candidates.
//             Skipped cleanly if no symbol resolves (stripped binaries).
//
//   Layer 3 — Background polling thread against OSLogStore,
//             filtered to com.apple.bluetooth / A2DP category.
//
//   Diagnostic — enumerates all ObjC classes and BT/codec-related
//                selectors in the bluetoothd process, writes to
//                /var/mobile/Library/BTCodecTweak/btd_classes.txt
//                for inspection when hook targets are unknown.

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

// ── Private BluetoothManager.framework stubs ──────────────────────────────────

@interface BTDevice : NSObject
@property (nonatomic, readonly, copy) NSString *address;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, assign) NSUInteger a2dpCodecType;
@property (nonatomic, assign) NSUInteger a2dpNegotiatedBitrate;
@end

// ── File-scope globals ─────────────────────────────────────────────────────────

static os_log_t       sLog            = NULL;
static int            sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID      sCurrentCodecID = BTCodecID_Unknown;

static pthread_t      sLogThread;
static _Atomic(bool)  sLogThreadRunning = false;

// ── Core notification dispatch ─────────────────────────────────────────────────

static void BTCodec_PostIfChanged(BTCodecID codecID, uint32_t bitrate_kbps) {
    if (codecID == sCurrentCodecID) return;
    sCurrentCodecID = codecID;

    if (sStateToken == NOTIFY_TOKEN_INVALID) {
        uint32_t status = notify_register_check(kBTCodecNotifName, &sStateToken);
        if (status != NOTIFY_STATUS_OK) {
            os_log_error(sLog, "[BTCodecDaemon] notify_register_check failed: %u", status);
            return;
        }
    }

    uint64_t state = BTCodecMakeState(codecID, bitrate_kbps);
    notify_set_state(sStateToken, state);
    notify_post(kBTCodecNotifName);

    os_log(sLog, "[BTCodecDaemon] codec → %u (%u kbps) posted",
           (unsigned)codecID, (unsigned)bitrate_kbps);
}

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

// ── Layer 2: C-level hook — AVDTP SET_CONFIGURATION ───────────────────────────

typedef void (*AVDTP_SetCfm_t)(void *session,
                                uint8_t codec_type,
                                const uint8_t *codec_ie,
                                size_t ie_len);

static AVDTP_SetCfm_t sOrigAVDTP_SetCfm = NULL;

static void Hooked_AVDTP_SetCfm(void *session,
                                 uint8_t codec_type,
                                 const uint8_t *codec_ie,
                                 size_t ie_len) {
    if (sOrigAVDTP_SetCfm) sOrigAVDTP_SetCfm(session, codec_type, codec_ie, ie_len);

    BTCodecID codecID = BTCodecID_Unknown;
    if (codec_type == BTCodecID_SBC   ||
        codec_type == BTCodecID_MPEG12 ||
        codec_type == BTCodecID_AAC   ||
        codec_type == BTCodecID_ATRAC) {
        codecID = (BTCodecID)codec_type;
    }

    uint32_t bitrate = 0;
    if (codecID == BTCodecID_AAC && codec_ie != NULL && ie_len >= 5) {
        uint32_t bps = ((uint32_t)(codec_ie[2] & 0x07) << 16)
                     | ((uint32_t)codec_ie[3]           <<  8)
                     | ((uint32_t)codec_ie[4]);
        bitrate = (bps > 0) ? (bps / 1000) : 256;
    } else if (codecID == BTCodecID_AAC) {
        bitrate = 256;
    }

    BTCodec_PostIfChanged(codecID, bitrate);
}

// ── Layer 3: os_log stream thread ─────────────────────────────────────────────

static void BTCodec_ParseOSLogEntry(NSString *message) {
    if (!message || message.length == 0) return;

    NSString *lower = message.lowercaseString;
    BTCodecID detected = BTCodecID_Unknown;
    uint32_t bitrate = 0;

    if ([lower containsString:@"codec type 2"]  ||
        [lower containsString:@"codec=0x02"]    ||
        [lower containsString:@"codec: aac"]    ||
        [lower containsString:@"aac-lc"]        ||
        [lower containsString:@"mpeg-2 aac"]    ||
        ([lower containsString:@"codec"] && [lower containsString:@"aac"])) {
        detected = BTCodecID_AAC;
        bitrate  = 256;
    } else if ([lower containsString:@"codec type 0"] ||
               [lower containsString:@"codec=0x00"]   ||
               [lower containsString:@"codec: sbc"]   ||
               ([lower containsString:@"codec"] && [lower containsString:@"sbc"])) {
        detected = BTCodecID_SBC;
    }

    if (detected != BTCodecID_Unknown) {
        BTCodec_PostIfChanged(detected, bitrate);
    }
}

static void *BTCodec_LogStreamThread(void *__unused arg) {
    @autoreleasepool {
        Class OSLogStoreClass = NSClassFromString(@"OSLogStore");
        if (!OSLogStoreClass) {
            os_log_error(sLog, "[BTCodecDaemon] OSLogStore unavailable");
            return NULL;
        }

        NSError *storeErr = nil;
        NSError * __autoreleasing *errPtr = &storeErr;
        id store = [OSLogStoreClass performSelector:@selector(localStoreAndReturnError:)
                                        withObject:(__bridge id)(void *)errPtr];
        if (!store) {
            os_log_error(sLog, "[BTCodecDaemon] OSLogStore open failed: %@", storeErr);
            return NULL;
        }

        NSPredicate *pred = [NSPredicate predicateWithFormat:
            @"subsystem == 'com.apple.bluetooth' AND category == 'A2DP'"];

        SEL enumSel = NSSelectorFromString(
            @"entriesEnumeratorWithOptions:position:predicate:error:");
        NSMethodSignature *sig = [store methodSignatureForSelector:enumSel];
        if (!sig) {
            os_log_error(sLog, "[BTCodecDaemon] entriesEnumerator unavailable");
            return NULL;
        }

        while (sLogThreadRunning) {
            @autoreleasepool {
                NSError *enumErr = nil;
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:store];
                [inv setSelector:enumSel];
                NSUInteger options = 0;
                [inv setArgument:&options atIndex:2];
                id nullPos = nil;
                [inv setArgument:&nullPos  atIndex:3];
                [inv setArgument:&pred     atIndex:4];
                [inv setArgument:&enumErr  atIndex:5];
                [inv invoke];

                id __unsafe_unretained enumerator = nil;
                [inv getReturnValue:&enumerator];

                if (enumerator) {
                    SEL msgSel = NSSelectorFromString(@"composedMessage");
                    for (id entry in enumerator) {
                        if (!sLogThreadRunning) break;
                        if ([entry respondsToSelector:msgSel]) {
                            NSString *msg = ((NSString *(*)(id, SEL))objc_msgSend)(entry, msgSel);
                            BTCodec_ParseOSLogEntry(msg);
                        }
                    }
                }
            }
            usleep(500000);
        }
    }
    return NULL;
}

// ── Diagnostic: runtime class + selector dump ──────────────────────────────────

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

        NSString *dir = @"/var/mobile/Library/BTCodecTweak";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSError *err = nil;
        BOOL ok = [out writeToFile:[dir stringByAppendingPathComponent:@"btd_classes.txt"]
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:&err];
        os_log(sLog, "[BTCodecDaemon] class dump written: %d (%@)", ok, err);
    });
}

// ── Constructor ────────────────────────────────────────────────────────────────

%ctor {
    NSString *procName = [NSProcessInfo processInfo].processName;
    if (![procName isEqualToString:@"bluetoothd"]) return;

    sLog = os_log_create("com.btcodectweak", "daemon");
    os_log(sLog, "[BTCodecDaemon] Loading — pid %d", getpid());

    // Layer 2: attempt C-symbol hook
    static const char * const kCandidates[] = {
        "_bt_avdtp_set_configuration_cfm",
        "_BTAVDTPSetConfigurationResponse",
        "_a2dp_avdtp_set_configuration_ind",
        "_a2dp_set_configuration_cfm",
        "_BTAVDTPHandleSetConfigurationConfirmation",
        NULL
    };
    for (int i = 0; kCandidates[i] != NULL; i++) {
        void *sym = dlsym(RTLD_DEFAULT, kCandidates[i]);
        if (sym) {
            MSHookFunction(sym,
                           (void *)Hooked_AVDTP_SetCfm,
                           (void **)&sOrigAVDTP_SetCfm);
            os_log(sLog, "[BTCodecDaemon] Layer 2 hooked: %s", kCandidates[i]);
            break;
        }
    }
    if (!sOrigAVDTP_SetCfm) {
        os_log(sLog, "[BTCodecDaemon] Layer 2: no symbol matched");
    }

    // Layer 3: log-stream background thread
    sLogThreadRunning = true;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&sLogThread, &attr, BTCodec_LogStreamThread, NULL);
    pthread_attr_destroy(&attr);

    // Diagnostic dump
    BTCodec_DumpClasses();

    os_log(sLog, "[BTCodecDaemon] Setup complete");
}

%dtor {
    sLogThreadRunning = false;
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
