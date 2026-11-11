#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface BTCodecRootListController : PSListController
@end

@implementation BTCodecRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end
