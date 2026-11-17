// BTCodecSB.x — SpringBoard Client Component
#import <Foundation/Foundation.h>
#import <notify.h>
#import "BTCodecCommon.h"

// Forward declare your UI manager or notification handler
@interface BTCodecManager : NSObject
+ (instancetype)sharedManager;
- (void)updateCodecDisplayWithID:(BTCodecID)codecID bitrate:(uint32_t)bitrate;
@end

static int sClientNotifyToken = NOTIFY_TOKEN_INVALID;

static void BTCodec_FetchAndUpdateCurrentState(void) {
    uint64_t state = 0;
    
    if (sClientNotifyToken == NOTIFY_TOKEN_INVALID) {
        notify_register_check(kBTCodecNotifName, &sClientNotifyToken);
    }
    
    if (sClientNotifyToken != NOTIFY_TOKEN_INVALID) {
        notify_get_state(sClientNotifyToken, &state);
        BTCodecID codecID = BTCodecGetID(state);
        uint32_t bitrate = BTCodecGetBitrate(state);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[BTCodecManager sharedManager] updateCodecDisplayWithID:codecID bitrate:bitrate];
        });
    }
}

%ctor {
    // Ensure this component only runs inside SpringBoard
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;

    // 1. Fetch current state immediately upon SpringBoard load
    BTCodec_FetchAndUpdateCurrentState();
    
    // 2. Register dispatch queue listener for live updates when daemon posts changes
    notify_register_dispatch(kBTCodecNotifName, &sClientNotifyToken, dispatch_get_main_queue(), ^(int token) {
        uint64_t state = 0;
        notify_get_state(token, &state);
        
        BTCodecID codecID = BTCodecGetID(state);
        uint32_t bitrate = BTCodecGetBitrate(state);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[BTCodecManager sharedManager] updateCodecDisplayWithID:codecID bitrate:bitrate];
        });
    });
}

%dtor {
    if (sClientNotifyToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sClientNotifyToken);
        sClientNotifyToken = NOTIFY_TOKEN_INVALID;
    }
}
