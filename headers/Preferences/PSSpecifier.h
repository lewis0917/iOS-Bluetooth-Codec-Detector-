// headers/Preferences/PSSpecifier.h
// Class-dump derived declarations for PSSpecifier from Preferences.framework.
// Covers all cell types and property accessors used by BTCodecRootListController.

#pragma once
#import <Foundation/Foundation.h>

// ── Cell type enum ─────────────────────────────────────────────────────────────
// Integer values map 1:1 to Preferences.framework internals — do not reorder.
typedef NS_ENUM(NSInteger, PSCellType) {
    PSGroupCell          =  0,
    PSLinkCell           =  1,
    PSLinkListCell       =  2,
    PSListItemCell       =  3,
    PSTitleValueCell     =  4,
    PSSliderCell         =  5,
    PSSwitchCell         =  6,
    PSStaticTextCell     =  7,
    PSEditTextCell       =  8,
    PSSegmentCell        =  9,
    PSGiantIconCell      = 10,
    PSGiantCell          = 11,
    PSSecureEditTextCell = 12,
    PSButtonCell         = 13,
    PSEditTextViewCell   = 14,
};

// ── PSSpecifier ────────────────────────────────────────────────────────────────

@interface PSSpecifier : NSObject

@property (nonatomic, assign) id       target;
@property (nonatomic, assign) SEL      setter;
@property (nonatomic, assign) SEL      getter;
@property (nonatomic, assign) SEL      action;          // used by PSButtonCell
@property (nonatomic, copy)   NSString *identifier;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, assign) PSCellType cellType;
@property (nonatomic, strong) Class    detailControllerClass;
@property (nonatomic, strong) Class    editPaneClass;

// Internal property dictionary — accessed via setProperty:forKey: /
// propertyForKey:.  Keys include "key", "default", "defaults", "footerText",
// "enabled", "min", "max", etc.
@property (nonatomic, strong) NSMutableDictionary *properties;

// For PSSegmentCell, PSLinkListCell: parallel ordered arrays.
@property (nonatomic, strong) NSArray *values;
@property (nonatomic, strong) NSArray *titleDictionary;  // parallel titles

// ── Constructors ───────────────────────────────────────────────────────────────

// PSGroupCell convenience — name appears as the section header string.
+ (instancetype)groupSpecifierWithName:(NSString *)name;

// PSGroupCell with no header string.
+ (instancetype)emptyGroupSpecifier;

// General constructor used for all non-group cell types.
+ (instancetype)preferenceSpecifierNamed:(NSString *)name
                                  target:(id)target
                                     set:(SEL)set
                                     get:(SEL)get
                                  detail:(Class)detail
                                    cell:(PSCellType)cell
                                    edit:(Class)edit;

// ── Property bag ───────────────────────────────────────────────────────────────

- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)property forKey:(NSString *)key;
- (void)removePropertyForKey:(NSString *)key;

// ── Value/title pairs (PSSegmentCell, PSLinkListCell) ─────────────────────────

- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
- (void)setValues:(NSArray *)values
           titles:(NSArray *)titles
      shortTitles:(NSArray *)shortTitles;

@end
