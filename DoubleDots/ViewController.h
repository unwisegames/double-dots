//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "RenderController.h"

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController<UITableViewDataSource, UITableViewDelegate, UIPopoverControllerDelegate>

@property (nonatomic, strong) IBOutlet UITableView      * tableView;
@property (nonatomic, strong) IBOutlet UIButton         * seed;
@property (nonatomic, strong) IBOutlet UIButton         * gear;

- (IBAction)tappedMatch;
- (IBAction)tappedSeed;

@end
