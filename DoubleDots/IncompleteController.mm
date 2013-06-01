//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "IncompleteController.h"

@interface IncompleteController ()

@end

@implementation IncompleteController

@synthesize shapeImage = _shapeImage, shape = _shape;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _shape.image = _shapeImage;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
