#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <notify.h>
#include <os/log.h>

#import "BTCodecCommon.h"

@interface BTCodecPillWindow : UIWindow
+ (instancetype)shared;
- (void)presentWithCodecID:(BTCodecID)codecID bitrate:(uint32_t)bitrate;
- (void)dismiss;
@end

static os_log_t sLog = NULL;
static int sListenToken = NOTIFY_TOKEN_INVALID;

@implementation BTCodecPillWindow {
    UIView *_pill;
    UIVisualEffectView *_blurView;
    UIImageView *_iconView;
    UILabel *_codeLabel;
    UILabel *_detailLabel;
    CALayer *_accentStrip;
    dispatch_source_t _dismissTimer;
}

+ (instancetype)shared {
    static BTCodecPillWindow *sInstance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIWindowScene *targetScene = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                targetScene = (UIWindowScene *)s;
                break;
            }
        }
        if (targetScene) {
            sInstance = [[BTCodecPillWindow alloc] initWithWindowScene:targetScene];
        } else {
            sInstance = [[BTCodecPillWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        }
        sInstance.windowLevel = UIWindowLevelStatusBar + 100.0;
        sInstance.backgroundColor = UIColor.clearColor;
        sInstance.userInteractionEnabled = NO;
        sInstance.hidden = YES;
        [sInstance buildHierarchy];
    });
    return sInstance;
}

- (void)buildHierarchy {
    _pill = [[UIView alloc] initWithFrame:CGRectZero];
    _pill.layer.cornerRadius = 20.0;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    _pill.clipsToBounds = YES;
    _pill.alpha = 0.0;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _accentStrip = [CALayer layer];
    _accentStrip.cornerRadius = 1.5;
    [_blurView.contentView.layer addSublayer:_accentStrip];

    UIImageConfiguration *imgCfg = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightMedium];
    UIImage *icon = [UIImage systemImageNamed:@"headphones" withConfiguration:imgCfg];
    _iconView = [[UIImageView alloc] initWithImage:icon];
    _iconView.tintColor = UIColor.whiteColor;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;

    _codeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _codeLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    _codeLabel.textColor = UIColor.whiteColor;

    _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _detailLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    _detailLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];

    [_blurView.contentView addSubview:_iconView];
    [_blurView.contentView addSubview:_codeLabel];
    [_blurView.contentView addSubview:_detailLabel];
    [_pill addSubview:_blurView];
    [self addSubview:_pill];
}

- (void)presentWithCodecID:(BTCodecID)codecID bitrate:(uint32_t)bitrate {
    NSString *codeName, *detail;
    UIColor *accent;

    switch (codecID) {
        case BTCodecID_AAC:
            codeName = @"AAC";
            detail = (bitrate > 0) ? [NSString stringWithFormat:@"%u kbps", bitrate] : @"High Quality";
            accent = [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
            break;
        case BTCodecID_SBC:
            codeName = @"SBC";
            detail = @"Fallback";
            accent = [UIColor colorWithRed:1.00 green:0.62 blue:0.04 alpha:1.0];
            break;
        default:
            codeName = @"BT Audio";
            detail = @"Unknown Codec";
            accent = [UIColor systemGrayColor];
            break;
    }

    _codeLabel.text = codeName;
    _detailLabel.text = detail;
    _accentStrip.backgroundColor = accent.CGColor;

    const CGFloat hPad = 12.0, vPad = 8.0, iconSize = 18.0, iconGap = 6.0, interLabelGap = 2.0, pillH = 40.0;
    [_codeLabel sizeToFit];
    [_detailLabel sizeToFit];
    CGFloat textW = MAX(_codeLabel.frame.size.width, _detailLabel.frame.size.width);
    textW = MAX(textW, 50.0);
    CGFloat pillW = hPad + 4.0 + iconGap + iconSize + iconGap + textW + hPad;
    pillW = MAX(pillW, 140.0);

    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (keyWin) safeInsets = keyWin.safeAreaInsets;

    CGFloat pillY = MAX(safeInsets.top + 6.0, 10.0);
    CGRect pillFrame = CGRectMake((screenW - pillW) / 2.0, pillY, pillW, pillH);

    self.frame = UIScreen.mainScreen.bounds;
    _pill.frame = CGRectMake(pillFrame.origin.x, pillFrame.origin.y - 28.0, pillW, pillH);
    _blurView.frame = _pill.bounds;

    _accentStrip.frame = CGRectMake(0, vPad, 3.0, pillH - vPad * 2.0);
    _iconView.frame = CGRectMake(4.0 + iconGap, (pillH - iconSize) / 2.0, iconSize, iconSize);

    CGFloat codeH = _codeLabel.font.lineHeight;
    CGFloat detailH = _detailLabel.font.lineHeight;
    CGFloat blockH = codeH + interLabelGap + detailH;
    CGFloat blockY = (pillH - blockH) / 2.0;
    _codeLabel.frame = CGRectMake(4.0 + iconGap + iconSize + iconGap * 2, blockY, textW, codeH);
    _detailLabel.frame = CGRectMake(_codeLabel.frame.origin.x, blockY + codeH + interLabelGap, textW, detailH);

    [self cancelDismissTimer];
    self.hidden = NO;

    [UIView animateWithDuration:0.38 delay:0.0 usingSpringWithDamping:0.70 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_pill.alpha = 1.0;
        self->_pill.frame = pillFrame;
    } completion:nil];

    [self scheduleDismissAfterDelay:3.0];
}

- (void)dismiss {
    [self cancelDismissTimer];
    CGRect f = _pill.frame;
    [UIView animateWithDuration:0.22 animations:^{
        self->_pill.alpha = 0.0;
        self->_pill.frame = CGRectMake(f.origin.x, f.origin.y - 20.0, f.size.width, f.size.height);
    } completion:^(BOOL done) {
        self.hidden = YES;
    }];
}

- (void)scheduleDismissAfterDelay:(NSTimeInterval)delay {
    [self cancelDismissTimer];
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, (int64_t)(0.1 * NSEC_PER_SEC));
    __weak BTCodecPillWindow *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf dismiss];
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

static void BTCodec_HandleNotification(int token) {
    uint64_t state = 0;
    if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return;
    BTCodecID codecID = BTCodecStateGetID(state);
    uint32_t bitrate = BTCodecStateGetBitrate(state);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[BTCodecPillWindow shared] presentWithCodecID:codecID bitrate:bitrate];
    });
}

%ctor {
    if (![[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"]) return;
    sLog = os_log_create("com.btcodectweak", "ui");

    notify_register_dispatch(kBTCodecNotifName, &sListenToken, dispatch_get_main_queue(), ^(int token) {
        BTCodec_HandleNotification(token);
    });
}

%dtor {
    if (sListenToken != NOTIFY_TOKEN_INVALID) notify_cancel(sListenToken);
}
