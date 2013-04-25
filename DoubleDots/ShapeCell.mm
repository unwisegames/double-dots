//  Copyright © 2013 Marcelo Cantos <me@marcelocantos.com>

#import "ShapeCell.h"
#import "Board.h"

#include <sstream>

@interface ShapeCell () {
    bool _scoresUpdated;
}
@property (nonatomic, strong) IBOutlet UILabel      * quantity;
@property (nonatomic, strong) IBOutlet UILabel      * scores;
@end

@implementation ShapeCell

@synthesize quantity = _quantity, shape = _shape;

- (void)setShapeMatches:(ShapeMatches const &)sm image:(UIImage *)shape {
    _quantity.hidden        = sm.matches.size() < 2;
    if (!_quantity.hidden)
        _quantity.text      = [NSString stringWithFormat:@"%ld ×", sm.matches.size()];
    _shape.image            = shape;
    //_scores.numberOfLines   = sm.matches.size();
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
