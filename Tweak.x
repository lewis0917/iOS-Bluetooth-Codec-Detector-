// Tweak.x — injected into SpringBoard via BTCodecSB.plist

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#include <notify.h>
#include <os/log.h>

#import "BTCodecCommon.h"

// ── Preference helpers ─────────────────────────────────────────────────────────

static BOOL BTCodec_IsEnabled(void) {
    CFPreferencesAppSynchronize(CFSTR("com.btcodectweak"));
    CFTypeRef v = CFPreferencesCopyAppValue(CFSTR("enabled"),
                                            CFSTR("com.btcodectweak"));
    BOOL r = v ? CFBooleanGetValue((CFBooleanRef)v) : YES;
    if (v) CFRelease(v);
    return r;
}

static BOOL BTCodec_AlertOnSBC(void) {
    CFPreferencesAppSynchronize(CFSTR("com.btcodectweak"));
    CFTypeRef v = CFPreferencesCopyAppValue(CFSTR("alertOnSBC"),
                                            CFSTR("com.btcodectweak"));
    BOOL r = v ? CFBooleanGetValue((CFBooleanRef)v) : YES;
    if (v) CFRelease(v);
    return r;
}

// ── iOS 18 framework class declarations ─────────────────────────────────────

@interface MRContentItemMetadataAudioFormat : NSObject
@property (nonatomic, assign) NSInteger codec;
@property (nonatomic, assign) NSInteger bitrate;
@end

@interface CBAudioLinkQualityInfo : NSObject
@property (nonatomic, assign) NSInteger codecType;
@property (nonatomic, assign) NSInteger bitRate;
@end

// ── Forward declaration ────────────────────────────────────────────────────────

@interface BTCodecPillWindow : UIWindow
+ (instancetype)shared;
- (void)presentWithCodecID:(BTCodecID)codecID bitrate:(uint32_t)bitrate;
- (void)dismiss;
@end

// ── File-scope globals ─────────────────────────────────────────────────────────

static os_log_t sLog          = NULL;
static int      sListenToken  = NOTIFY_TOKEN_INVALID;  // dispatch listener
static int      sPrefsToken   = NOTIFY_TOKEN_INVALID;  // prefs change listener
static int      sSBStateToken = NOTIFY_TOKEN_INVALID;  // check token for set_state

// ── iOS 18 Hook Targets ─────────────────────────────────────────────────────

%hook MRContentItemMetadataAudioFormat

- (void)setCodec:(NSInteger)newCodec {
    os_log_info(sLog, "[BTCodecSB] MRContentItemMetadataAudioFormat setCodec fired with raw codec: %ld", (long)newCodec);
    %orig;

    BTCodecID codecID;
    switch (newCodec) {
        case 0:  codecID = BTCodecID_SBC; break;
        case 2:  codecID = BTCodecID_AAC; break;
        default: return;
    }

    NSInteger rawBitrate = [self respondsToSelector:@selector(bitrate)]
                         ? [self bitrate] : 0;
    uint32_t bitrate = (rawBitrate > 0)
                     ? (uint32_t)rawBitrate
                     : (codecID == BTCodecID_AAC ? 256 : 0);

    os_log_info(sLog, "[BTCodecSB] Processed codecID: %d, bitrate: %u", (int)codecID, bitrate);

    if (sSBStateToken != NOTIFY_TOKEN_INVALID) {
        notify_set_state(sSBStateToken, BTCodecMakeState(codecID, bitrate));
    }
    notify_post(kBTCodecNotifName);
}

%end

%hook CBAudioLinkQualityInfo

- (void)setCodecType:(NSInteger)newCodecType {
    os_log_info(sLog, "[BTCodecSB] CBAudioLinkQualityInfo setCodecType fired with raw type: %ld", (long)newCodecType);
    %orig;

    BTCodecID codecID;
    switch (newCodecType) {
        case 0:  codecID = BTCodecID_SBC; break;
        case 2:  codecID = BTCodecID_AAC; break;
        default: return;
    }

    NSInteger rawBitrate = [self respondsToSelector:@selector(bitRate)]
                         ? [self bitRate] : 0;
    uint32_t bitrate = (rawBitrate > 0)
                     ? (uint32_t)rawBitrate
                     : (codecID == BTCodecID_AAC ? 256 : 0);

    os_log_info(sLog, "[BTCodecSB] Processed codecID: %d, bitrate: %u", (int)codecID, bitrate);

    if (sSBStateToken != NOTIFY_TOKEN_INVALID) {
        notify_set_state(sSBStateToken, BTCodecMakeState(codecID, bitrate));
    }
    notify_post(kBTCodecNotifName);
}

%end

// ── Pill window implementation ────────────────────────────────────────────────

@implementation BTCodecPillWindow {
    UIView              *_pill;
    UIVisualEffectView  *_blurView;
    UILabel             *_codeLabel;
    UILabel             *_detailLabel;
    CALayer             *_accentStrip;
    dispatch_source_t    _dismissTimer;
}

+ (instancetype)shared {
    static BTCodecPillWindow *sInstance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIWindowScene *scene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
        sInstance = scene
            ? [[BTCodecPillWindow alloc] initWithWindowScene:scene]
            : [[BTCodecPillWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        sInstance.windowLevel            = UIWindowLevelStatusBar + 100.0;
        sInstance.backgroundColor        = UIColor.clearColor;
        sInstance.userInteractionEnabled = NO;
        sInstance.hidden                 = YES;
        [sInstance buildHierarchy];
    });
    return sInstance;
}

- (void)buildHierarchy {
    _pill = [[UIView alloc] initWithFrame:CGRectZero];
    _pill.layer.cornerRadius = 20.0;
    _pill.layer.cornerCurve  = kCACornerCurveContinuous;
    _pill.clipsToBounds      = YES;
    _pill.alpha              = 0.0;

    UIBlurEffect *blur = [UIBlurEffect
        effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _accentStrip = [CALayer layer];
    _accentStrip.cornerRadius = 1.5;
    [_blurView.contentView.layer addSublayer:_accentStrip];

    _codeLabel = [[UILabel alloc] init];
    _codeLabel.font      = [UIFont systemFontOfSize:13.0
                                             weight:UIFontWeightBold];
    _codeLabel.textColor = UIColor.whiteColor;

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.font      = [UIFont systemFontOfSize:11.0
                                               weight:UIFontWeightRegular];
    _detailLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];

    [_blurView.contentView addSubview:_codeLabel];
    [_blurView.contentView addSubview:_detailLabel];
    [_pill addSubview:_blurView];
    [self addSubview:_pill];
}

- (void)presentWithCodecID:(BTCodecID)codecID bitrate:(uint32_t)bitrate {
    NSAssert(NSThread.isMainThread, @"main thread only");

    NSString *codeName, *detail;
    UIColor  *accent;

    switch (codecID) {
        case BTCodecID_AAC:
            codeName = @"AAC";
            detail   = bitrate > 0
                     ? [NSString stringWithFormat:@"%u kbps", bitrate]
                     : @"High Quality";
            accent = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            break;
        case BTCodecID_SBC:
            codeName = @"SBC";
            detail   = @"Fallback";
            accent = [UIColor colorWithRed:1.00 green:0.62 blue:0.04 alpha:1.0];
            break;
        case BTCodecID_MPEG12:
            codeName = @"MP3";
            detail   = @"";
            accent = UIColor.systemBlueColor;
            break;
        default:
            codeName = @"BT Audio";
            detail   = @"Unknown Codec";
            accent = UIColor.systemGrayColor;
            break;
    }

    _codeLabel.text   = codeName;
    _detailLabel.text = detail;
    _accentStrip.backgroundColor = accent.CGColor;

    const CGFloat hPad    = 12.0;
    const CGFloat iconGap =  8.0;
    const CGFloat pillH   = 40.0;

    [_codeLabel sizeToFit];
    [_detailLabel sizeToFit];
    CGFloat textW = MAX(_codeLabel.frame.size.width,
                        _detailLabel.frame.size.width);
    textW = MAX(textW, 50.0);
    CGFloat pillW = hPad + 4.0 + iconGap + textW + hPad;
    pillW = MAX(pillW, 120.0);

    CGFloat screenW  = UIScreen.mainScreen.bounds.size.width;
    CGFloat topInset = self.safeAreaInsets.top;
    if (topInset < 10.0) topInset = 10.0;
    CGFloat pillY = topInset + 6.0;

    CGRect pillFrame  = CGRectMake((screenW - pillW) / 2.0, pillY, pillW, pillH);
    CGRect entryFrame = CGRectOffset(pillFrame, 0, -28.0);

    self.frame      = UIScreen.mainScreen.bounds;
    _pill.frame     = entryFrame;
    _blurView.frame = _pill.bounds;

    _accentStrip.frame = CGRectMake(0, 8.0, 3.0, pillH - 16.0);

    CGFloat xCursor   = 4.0 + iconGap;
    CGFloat codeH     = _codeLabel.font.lineHeight;
    CGFloat detailH   = _detailLabel.font.lineHeight;
    BOOL    hasDetail = detail.length > 0;
    CGFloat blockH    = hasDetail ? (codeH + 2.0 + detailH) : codeH;
    CGFloat blockY    = (pillH - blockH) / 2.0;

    _codeLabel.frame    = CGRectMake(xCursor, blockY, textW, codeH);
    _detailLabel.frame  = CGRectMake(xCursor, blockY + codeH + 2.0, textW, detailH);
    _detailLabel.hidden = !hasDetail;

    [self cancelDismissTimer];
    self.hidden = NO;

    [UIView animateWithDuration:0.38
                          delay:0.0
         usingSpringWithDamping:0.70
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_pill.alpha = 1.0;
        self->_pill.frame = pillFrame;
    } completion:nil];

    [self scheduleDismissAfterDelay:3.0];
}

- (void)dismiss {
    NSAssert(NSThread.isMainThread, @"main thread only");
    [self cancelDismissTimer];
    CGRect f = _pill.frame;
    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_pill.alpha = 0.0;
        self->_pill.frame = CGRectOffset(f, 0, -20.0);
    } completion:^(BOOL __unused done) {
        self.hidden = YES;
    }];
}

- (void)scheduleDismissAfterDelay:(NSTimeInterval)delay {
    dispatch_source_t timer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
        0,
        (int64_t)(0.1 * NSEC_PER_SEC));
    __weak BTCodecPillWindow *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf dismiss];
        dispatch_source_cancel(timer);
    });
    dispatch_resume(timer);
    _dismissTimer = timer;
}

- (void)cancelDismissTimer {
    if (_dismissTimer) {
        dispatch_source_cancel(_dismissTimer);
        _dismissTimer = nil;
    }
}

@end

// ── Notification handler ───────────────────────────────────────────────────────

static void BTCodec_HandleNotification(int token) {
    uint64_t state = 0;
    if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return;
    if (!BTCodecStateIsValid(state)) return;
    if (!BTCodec_IsEnabled()) return;

    BTCodecID codecID = BTCodecStateGetID(state);
    uint32_t  bitrate = BTCodecStateGetBitrate(state);

    if (codecID == BTCodecID_SBC && !BTCodec_AlertOnSBC()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[BTCodecPillWindow shared] presentWithCodecID:codecID bitrate:bitrate];
    });
}

// ── Constructor ────────────────────────────────────────────────────────────────

%ctor {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;

    sLog = os_log_create("com.btcodectweak", "ui");

    uint32_t checkStatus = notify_register_check(kBTCodecNotifName, &sSBStateToken);
    if (checkStatus != NOTIFY_STATUS_OK) {
        os_log_error(sLog, "[BTCodecUI] notify_register_check failed: %u", checkStatus);
    }

    uint32_t status = notify_register_dispatch(
        kBTCodecNotifName,
        &sListenToken,
        dispatch_get_main_queue(),
        ^(int token) { BTCodec_HandleNotification(token); }
    );
    if (status != NOTIFY_STATUS_OK) {
        os_log_error(sLog, "[BTCodecUI] notify_register_dispatch failed: %u", status);
    }

    notify_register_dispatch(kBTCodecPrefsChanged,
                             &sPrefsToken,
                             dispatch_get_main_queue(),
                             ^(int __unused t) {});

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{ (void)[BTCodecPillWindow shared]; });
}

// ── Destructor ─────────────────────────────────────────────────────────────────

%dtor {
    if (sSBStateToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sSBStateToken);
        sSBStateToken = NOTIFY_TOKEN_INVALID;
    }
    if (sListenToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sListenToken);
        sListenToken = NOTIFY_TOKEN_INVALID;
    }
    if (sPrefsToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(sPrefsToken);
        sPrefsToken = NOTIFY_TOKEN_INVALID;
    }
}
