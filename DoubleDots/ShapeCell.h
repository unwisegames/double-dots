//
//  ShapeCell.h
//  DoubleDots
//
//  Created by Marcelo Cantos on 11/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#import "ShapeMatches.h"

#import <UIKit/UIKit.h>

#include <memory>

@interface ShapeCell : UITableViewCell

- (void)setShapeMatches:(const std::shared_ptr<ShapeMatches>&)shapeMatches;
- (void)updateScores;

@end
