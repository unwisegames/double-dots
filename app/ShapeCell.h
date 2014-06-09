//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "ShapeMatches.h"

#import <UIKit/UIKit.h>

#include <memory>

@interface ShapeCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UIImageView  * shape;

- (void)setShapeMatches:(ShapeMatches const &)sm image:(UIImage *)shape;

@end
