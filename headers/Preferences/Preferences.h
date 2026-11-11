#import <UIKit/UIKit.h>

@interface PSListController : UIViewController
- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@property (nonatomic, readonly) NSMutableArray *specifiers;
@end
