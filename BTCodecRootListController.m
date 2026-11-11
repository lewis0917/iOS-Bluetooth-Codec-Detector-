// BTCodecRootListController.m
// PreferenceLoader root pane for BTCodecTweak.
//
// Preference domain: com.btcodectweak
// Keys:
//   enabled       BOOL  (default YES) — master toggle for the pill badge
//   alertOnSBC    BOOL  (default YES) — orange accent when codec degrades to SBC
//
// IPC: posts "com.btcodectweak.prefschanged" via Darwin notify on every write
// so BTCodecSB (Tweak.x) can re-read without polling.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>

// Pre-built class stubs from headers/Preferences/ — resolved at runtime
// by PreferenceLoader; no -framework Preferences link needed.
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

#import "BTCodecCommon.h"

// ── Constants ──────────────────────────────────────────────────────────────────

static NSString *const kDomain           = @"com.btcodectweak";
static NSString *const kPrefsChangedPost = @"com.btcodectweak.prefschanged";

// ── Controller ─────────────────────────────────────────────────────────────────

@interface BTCodecRootListController : PSListController
@property (nonatomic, strong) PSSpecifier *codecStatusSpecifier;
@end

@implementation BTCodecRootListController

// ── Specifier construction ─────────────────────────────────────────────────────

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *specs = [NSMutableArray array];

    // ── Group 1: Live status ───────────────────────────────────────────────────
    PSSpecifier *statusGroup = [PSSpecifier groupSpecifierWithName:@"Live Status"];
    [statusGroup setProperty:
        @"Reflects the most recently detected A2DP codec. "
        @"Connect a Bluetooth audio device to trigger detection."
        forKey:@"footerText"];
    [specs addObject:statusGroup];

    // PSStaticTextCell with a custom getter shows label on left, value on right.
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

    // ── Group 2: Display options ───────────────────────────────────────────────
    PSSpecifier *displayGroup = [PSSpecifier groupSpecifierWithName:@"Display"];
    [displayGroup setProperty:
        @"The badge appears below the Dynamic Island or status bar "
        @"for 3 seconds whenever the active codec changes."
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

    PSSpecifier *sbcAlertSpec = [PSSpecifier
        preferenceSpecifierNamed:@"Orange Alert on SBC Fallback"
                          target:self
                             set:@selector(setPreferenceValue:specifier:)
                             get:@selector(readPreferenceValue:)
                          detail:nil
                            cell:PSSwitchCell
                            edit:nil];
    [sbcAlertSpec setProperty:kDomain       forKey:@"defaults"];
    [sbcAlertSpec setProperty:@"alertOnSBC" forKey:@"key"];
    [sbcAlertSpec setProperty:@YES          forKey:@"default"];
    [specs addObject:sbcAlertSpec];

    // ── Group 3: About (no header; version in footer) ─────────────────────────
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

// ── View lifecycle ─────────────────────────────────────────────────────────────

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Bluetooth Codec";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Refresh the live-status cells each time the pane becomes visible —
    // the codec state may have changed since last open.
    if (self.codecStatusSpecifier) {
        [self reloadSpecifier:self.codecStatusSpecifier];
    }
}

// ── Getter methods for display-only cells ─────────────────────────────────────

- (NSString *)currentCodecDisplayString {
    BTCodecID codecID = [self _readLiveCodecID];
    switch (codecID) {
        case BTCodecID_AAC:       return @"AAC-LC";
        case BTCodecID_SBC:       return @"SBC";
        case BTCodecID_MPEG12:    return @"MPEG-1/2 Audio";
        case BTCodecID_VendorExt: return @"Vendor (aptX / LDAC)";
        default:                  return @"No BT Audio Active";
    }
}

- (NSString *)currentBitrateDisplayString {
    BTCodecID codecID = [self _readLiveCodecID];
    if (codecID == BTCodecID_Unknown) return @"—";

    uint32_t bitrate = [self _readLiveBitrate];
    if (bitrate == 0) {
        return (codecID == BTCodecID_AAC) ? @"~256 kbps (est.)" : @"~328 kbps (est.)";
    }
    return [NSString stringWithFormat:@"%u kbps", bitrate];
}

- (NSString *)versionString {
    return @"1.0.0";
}

// ── Darwin notify state helpers ───────────────────────────────────────────────

- (uint64_t)_readRawNotifyState {
    int token = NOTIFY_TOKEN_INVALID;
    uint32_t status = notify_register_check(kBTCodecNotifName, &token);
    if (status != NOTIFY_STATUS_OK) return 0;
    uint64_t state = 0;
    notify_get_state(token, &state);
    notify_cancel(token);
    return state;
}

- (BTCodecID)_readLiveCodecID {
    return BTCodecStateGetID([self _readRawNotifyState]);
}

- (uint32_t)_readLiveBitrate {
    return BTCodecStateGetBitrate([self _readRawNotifyState]);
}

// ── Preference read/write ─────────────────────────────────────────────────────

- (id)readPreferenceValue:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"];
    if (!key) return [spec propertyForKey:@"default"];

    // Synchronize before read to pick up writes from other processes.
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

    // Notify the SpringBoard dylib so it re-reads without a respring.
    notify_post([kPrefsChangedPost UTF8String]);
}

@end
