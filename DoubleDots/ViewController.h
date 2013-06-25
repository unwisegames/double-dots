//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "RenderController.h"

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController<UITableViewDataSource, UITableViewDelegate, UIPopoverControllerDelegate>

@property (strong, nonatomic) IBOutlet UITableView      * tableView;
@property (strong, nonatomic) IBOutlet UIButton         * seed;
@property (strong, nonatomic) IBOutlet UIButton         * gear;
@property (strong, nonatomic) IBOutlet UILabel          * score;

- (IBAction)tappedMatch;
- (IBAction)tappedSeed;

@end
