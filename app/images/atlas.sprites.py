image('atlas.xcf')
grid(8, 8)
scale(8)

sprites(
    screen=floodfill((3, 1)),
    match=floodfill((7, 1)),
    hand=floodfill((0.6, 4.4), scale=16),
    marbles=[
        floodfill((1, 3)),
        floodfill((3, 3)),
        floodfill((5, 3)),
        floodfill((7, 3)),
        floodfill((5, 5)),
        floodfill((7, 5)),
        floodfill((5, 7)),
        floodfill((7, 7)),
    ],
)
