#import <Foundation/Foundation.h>
#include <substrate.h>
#include <dlfcn.h>
#include <notify.h>
#include <os/log.h>
#include <pthread.h>
#include <unistd.h>

#import "BTCodecCommon.h"

@interface BTDevice : NSObject
@property (nonatomic, readonly, copy) NSString *address;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, assign) NSUInteger a2dpCodecType;
@property (nonatomic, assign) NSUInteger a2dpNegotiatedBitrate;
@end

static os_log_t       sLog            = NULL;
static int            sStateToken     = NOTIFY_TOKEN_INVALID;
static BTCodecID      sCurrentCodecID = BTCodecID_Unknown;

static pthread_t      sLogThread;
static _Atomic(bool)  sLogThreadRunning = false;

static void BTCodec_PostIfChanged(BTCodecID codecID, uint32_t bitrate_kbps) {
    if (codecID == sCurrentCodecID) return;
    sCurrentCodecID = codecID;

    if (sStateToken == NOTIFY_TOKEN_INVALID) {
        uint32_t status = notify_register_check(kBTCodecNotifName, &sStateToken);
        if (status != NOTIFY_STATUS_OK) return;
    }

    uint64_t state = BTCodecMakeState(codecID, bitrate_kbps);
    notify_set_state(sStateToken, state);
    notify_post(kBTCodecNotifName);
}

%hook BTDevice
- (void)setA2dpCodecType:(NSUInteger)codecType {
    %orig;
    BTCodecID codecID = (codecType <= BTCodecID_VendorExt)
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

typedef void (*AVDTP_SetCfm_t)(void *session, uint8_t codec_type, const uint8_t *codec_ie, size_t ie_len);
static AVDTP_SetCfm_t sOrigAVDTP_SetCfm = NULL;

static void Hooked_AVDTP_SetCfm(void *session, uint8_t codec_type, const uint8_t *codec_ie, size_t ie_len) {
    if (sOrigAVDTP_SetCfm) sOrigAVDTP_SetCfm(session, codec_type, codec_ie, ie_len);

    BTCodecID codecID = BTCodecID_Unknown;
    if (codec_type == BTCodecID_SBC || codec_type == BTCodecID_MPEG12 || codec_type == BTCodecID_AAC || codec_type == BTCodecID_ATRAC) {
        codecID = (BTCodecID)codec_type;
    }

    uint32_t bitrate = 0;
    if (codecID == BTCodecID_AAC && codec_ie != NULL && ie_len >= 5) {
        uint32_t bps = ((uint32_t)(codec_ie[2] & 0x07) << 16) | ((uint32_t)codec_ie[3] << 8) | ((uint32_t)codec_ie[4]);
        bitrate = (bps > 0) ? (bps / 1000) : 256;
    } else if (codecID == BTCodecID_AAC) {
        bitrate = 256;
    }

    BTCodec_PostIfChanged(codecID, bitrate);
}

static void BTCodec_ParseOSLogEntry(NSString *message) {
    if (!message || message.length == 0) return;
    NSString *lower = message.lowercaseString;
    BTCodecID detected = BTCodecID_Unknown;
    uint32_t bitrate = 0;

    if ([lower containsString:@"codec type 2"] || [lower containsString:@"codec=0x02"] || [lower containsString:@"aac-lc"]) {
        detected = BTCodecID_AAC;
        bitrate = 256;
    } else if ([lower containsString:@"codec type 0"] || [lower containsString:@"codec=0x00"] || [lower containsString:@"sbc"]) {
        detected = BTCodecID_SBC;
    }

    if (detected != BTCodecID_Unknown) {
        BTCodec_PostIfChanged(detected, bitrate);
    }
}

static void *BTCodec_LogStreamThread(void *__unused arg) {
    @autoreleasepool {
        Class OSLogStoreClass = NSClassFromString(@"OSLogStore");
        if (!OSLogStoreClass) return NULL;

        NSError *storeErr = nil;
        id store = [OSLogStoreClass performSelector:@selector(localStoreAndReturnError:) 
                                         withObject:(__bridge id)(void *)&storeErr];
        if (!store) return NULL;

        NSPredicate *pred = [NSPredicate predicateWithFormat:@"subsystem == 'com.apple.bluetooth' AND category == 'A2DP'"];
        SEL enumSel = NSSelectorFromString(@"entriesEnumeratorWithOptions:position:predicate:error:");
        NSMethodSignature *sig = [store methodSignatureForSelector:enumSel];
        if (!sig) return NULL;

        while (sLogThreadRunning) {
            @autoreleasepool {
                NSError *enumErr = nil;
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:store];
                [inv setSelector:enumSel];
                NSUInteger options = 0;
                [inv setArgument:&options atIndex:2];
                id nullPos = nil;
                [inv setArgument:&nullPos atIndex:3];
                [inv setArgument:&pred atIndex:4];
                [inv setArgument:&enumErr atIndex:5];
                [inv invoke];

                id __unsafe_unretained enumerator = nil;
                [inv getReturnValue:&enumerator];

                if (enumerator) {
                    SEL msgSel = NSSelectorFromString(@"composedMessage");
                    for (id entry in enumerator) {
                        if (!sLogThreadRunning) break;
                        if ([entry respondsToSelector:msgSel]) {
                            #pragma clang diagnostic push
                            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                            NSString *msg = [entry performSelector:msgSel];
                            #pragma clang diagnostic pop

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

%ctor {
    if (![[NSProcessInfo processInfo].processName isEqualToString:@"bluetoothd"]) return;
    sLog = os_log_create("com.btcodectweak", "daemon");

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
            MSHookFunction(sym, (void *)Hooked_AVDTP_SetCfm, (void **)&sOrigAVDTP_SetCfm);
            break;
        }
    }

    sLogThreadRunning = true;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&sLogThread, &attr, BTCodec_LogStreamThread, NULL);
    pthread_attr_destroy(&attr);
}

%dtor {
    sLogThreadRunning = false;
    if (sStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sStateToken);
        sStateToken = NOTIFY_TOKEN_INVALID;
    }
}
