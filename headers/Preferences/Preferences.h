#import <UIKit/UIKit.h>

@interface PSListController : UIViewController {
    NSMutableArray *_specifiers;
}
- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@property (nonatomic, readonly) NSMutableArray *specifiers;
@end
