//
//  ShapeCell.m
//  DoubleDots
//
//  Created by Marcelo Cantos on 11/03/13.
//  Copyright (c) 2013 Marcelo Cantos. All rights reserved.
//

#import "ShapeCell.h"

@implementation ShapeCell

@synthesize quantity = _quantity, shape = _shape;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
