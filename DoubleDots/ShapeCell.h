//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "ShapeMatches.h"

#import <UIKit/UIKit.h>

#include <memory>

@interface ShapeCell : UITableViewCell

- (void)setShapeMatches:(const std::shared_ptr<ShapeMatches>&)shapeMatches;
- (void)updateScores;

@end
