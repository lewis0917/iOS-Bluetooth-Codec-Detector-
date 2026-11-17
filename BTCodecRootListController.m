// BTCodecRootListController.m

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#include <notify.h>

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

#import "BTCodecCommon.h"

static NSString *const kDomain       = @"com.btcodectweak";
static NSString *const kPrefsChanged = @"com.btcodectweak.prefschanged";

@interface BTCodecRootListController : PSListController {
    int _codecNotifyToken;
}
@property (nonatomic, strong) PSSpecifier *codecStatusSpecifier;
@property (nonatomic, strong) PSSpecifier *bitrateStatusSpecifier;
@end

@implementation BTCodecRootListController

// ── Specifiers ─────────────────────────────────────────────────────────────────

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *specs = [NSMutableArray array];

    // ── Group 1: Live status ───────────────────────────────────────────────────
    PSSpecifier *statusGroup = [PSSpecifier groupSpecifierWithName:@"Live Status"];
    [statusGroup setProperty:
        @"Reflects the most recently detected A2DP codec."
        forKey:@"footerText"];
    [specs addObject:statusGroup];

    PSSpecifier *codecSpec = [PSSpecifier
        preferenceSpecifierNamed:@"Active Codec"
                          target:self
                             set:NULL
                             get:@selector(currentCodecDisplayString)
                          detail:nil
                            cell:PSStaticTextCell
                            edit:nil];
    [specs addObject:codecSpec];
    self.codecStatusSpecifier = codecSpec;

    PSSpecifier *bitrateSpec = [PSSpecifier
        preferenceSpecifierNamed:@"Est. Bitrate"
                          target:self
                             set:NULL
                             get:@selector(currentBitrateDisplayString)
                          detail:nil
                            cell:PSStaticTextCell
                            edit:nil];
    [specs addObject:bitrateSpec];
    self.bitrateStatusSpecifier = bitrateSpec;

    // ── Group 2: Display options ───────────────────────────────────────────────
    PSSpecifier *displayGroup = [PSSpecifier groupSpecifierWithName:@"Display"];
    [displayGroup setProperty:
        @"Badge appears below the Dynamic Island for 3 seconds on codec change."
        forKey:@"footerText"];
    [specs addObject:displayGroup];

    PSSpecifier *enableSpec = [PSSpecifier
        preferenceSpecifierNamed:@"Show Codec Badge"
                          target:self
                             set:@selector(setPreferenceValue:specifier:)
                             get:@selector(readPreferenceValue:)
                          detail:nil
                            cell:PSSwitchCell
                            edit:nil];
    [enableSpec setProperty:kDomain    forKey:@"defaults"];
    [enableSpec setProperty:@"enabled" forKey:@"key"];
    [enableSpec setProperty:@YES       forKey:@"default"];
    [specs addObject:enableSpec];

    PSSpecifier *sbcSpec = [PSSpecifier
        preferenceSpecifierNamed:@"Orange Alert on SBC Fallback"
                          target:self
                             set:@selector(setPreferenceValue:specifier:)
                             get:@selector(readPreferenceValue:)
                          detail:nil
                            cell:PSSwitchCell
                            edit:nil];
    [sbcSpec setProperty:kDomain       forKey:@"defaults"];
    [sbcSpec setProperty:@"alertOnSBC" forKey:@"key"];
    [sbcSpec setProperty:@YES          forKey:@"default"];
    [specs addObject:sbcSpec];

    // ── Group 3: About ─────────────────────────────────────────────────────────
    PSSpecifier *aboutGroup = [PSSpecifier groupSpecifierWithName:@""];
    [aboutGroup setProperty:@"BTCodecTweak 1.0.0 — github.com/lewis0917"
                     forKey:@"footerText"];
    [specs addObject:aboutGroup];

    PSSpecifier *versionSpec = [PSSpecifier
        preferenceSpecifierNamed:@"Version"
                          target:self
                             set:NULL
                             get:@selector(versionString)
                          detail:nil
                            cell:PSStaticTextCell
                            edit:nil];
    [specs addObject:versionSpec];

    _specifiers = specs;
    return _specifiers;
}

// ── Lifecycle ──────────────────────────────────────────────────────────────────

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title        = @"Bluetooth Codec";
    _codecNotifyToken = NOTIFY_TOKEN_INVALID;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (_codecNotifyToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(_codecNotifyToken);
        _codecNotifyToken = NOTIFY_TOKEN_INVALID;
    }

    notify_register_dispatch(kBTCodecNotifName,
                             &_codecNotifyToken,
                             dispatch_get_main_queue(),
                             ^(int __unused t) {
        // Smooth cross-dissolve animation when daemon posts a notification update
        [UIView transitionWithView:self.table
                          duration:0.25
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
            if (self.codecStatusSpecifier) {
                [self reloadSpecifier:self.codecStatusSpecifier];
            }
            if (self.bitrateStatusSpecifier) {
                [self reloadSpecifier:self.bitrateStatusSpecifier];
            }
        } completion:nil];
    });

    // Refresh immediately upon opening the pane
    if (self.codecStatusSpecifier) {
        [self reloadSpecifier:self.codecStatusSpecifier];
    }
    if (self.bitrateStatusSpecifier) {
        [self reloadSpecifier:self.bitrateStatusSpecifier];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_codecNotifyToken != NOTIFY_TOKEN_INVALID) {
        notify_cancel(_codecNotifyToken);
        _codecNotifyToken = NOTIFY_TOKEN_INVALID;
    }
}

// ── Display getters ────────────────────────────────────────────────────────────

- (NSString *)currentCodecDisplayString {
    uint64_t state = [self _readLiveState];
    if (!BTCodecStateIsValid(state)) return @"No BT Audio Active";
    switch (BTCodecStateGetID(state)) {
        case BTCodecID_AAC:       return @"AAC-LC";
        case BTCodecID_SBC:       return @"SBC";
        case BTCodecID_MPEG12:    return @"MPEG-1/2 Audio";
        case BTCodecID_VendorExt: return @"Vendor (aptX / LDAC)";
        default:                  return @"No BT Audio Active";
    }
}

- (NSString *)currentBitrateDisplayString {
    uint64_t state = [self _readLiveState];
    if (!BTCodecStateIsValid(state)) return @"—";
    uint32_t bitrate = BTCodecStateGetBitrate(state);
    if (bitrate == 0) {
        return BTCodecStateGetID(state) == BTCodecID_AAC
             ? @"~256 kbps (est.)" : @"—";
    }
    // Scale raw bits-per-second (e.g. 327000) down to kbps (327)
    uint32_t kbps = (bitrate > 1000) ? (bitrate / 1000) : bitrate;
    return [NSString stringWithFormat:@"%u kbps", kbps];
}

- (NSString *)versionString { return @"1.0.0"; }

// ── Darwin notify state read ───────────────────────────────────────────────────

- (uint64_t)_readLiveState {
    int token = NOTIFY_TOKEN_INVALID;
    if (notify_register_check(kBTCodecNotifName, &token) != NOTIFY_STATUS_OK) {
        return 0;
    }
    uint64_t state = 0;
    notify_get_state(token, &state);
    notify_cancel(token);
    return state;
}

// ── Preference read / write ────────────────────────────────────────────────────

- (id)readPreferenceValue:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"];
    if (!key) return [spec propertyForKey:@"default"];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kDomain
    );
    return value ?: [spec propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"];
    if (!key || !value) return;
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        (__bridge CFStringRef)kDomain
    );
    CFPreferencesSynchronize(
        (__bridge CFStringRef)kDomain,
        kCFPreferencesAnyUser,
        kCFPreferencesCurrentHost
    );
    notify_post([kPrefsChanged UTF8String]);
}

@end
