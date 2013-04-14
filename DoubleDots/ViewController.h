//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "RenderController.h"

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController<UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet RenderController *renderer;

- (IBAction)tappedMatch;
@end
