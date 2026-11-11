// headers/Preferences/PSListController.h
// Class-dump derived declarations for PSListController from Preferences.framework.

#pragma once
#import <UIKit/UIKit.h>
#import "PSSpecifier.h"

@interface PSListController : UIViewController {
    // Direct ivar — Logos/Logos-generated code accesses _specifiers directly
    // when you assign to the synthesised property in overriding -specifiers.
    NSMutableArray *_specifiers;
}

// The specifiers array.  Override -specifiers to build programmatically;
// PSListController lazily calls it and caches the result.
@property (nonatomic, retain) NSMutableArray *specifiers;

// ── Specifier management ───────────────────────────────────────────────────────

// Load from a .plist in the bundle's Resources directory.
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;

// Full reload — rebuilds the table from -specifiers.
- (void)reloadSpecifiers;

// Targeted reload — only refreshes the row for one specifier without
// rebuilding the entire table.  Call this after a getter's return value changes.
- (void)reloadSpecifier:(PSSpecifier *)specifier;
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;

// ── Preference I/O ─────────────────────────────────────────────────────────────
// Override both methods to implement custom storage (CFPreferences, NSUserDefaults,
// flat plist, etc.).  PSListController calls them automatically for switch cells,
// slider cells, and any other cell with a getter/setter selector pair.

- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;

@end
