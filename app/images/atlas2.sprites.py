image('atlas2.xcf')
grid(8, 8)
scale(10)

sprites(
    gear=floodfill((2, 2)),
    edging=floodfill((6, 2)),
    button=floodfill((4, 5)),
    colorblind=[
        floodfill((1, 7)),
        floodfill((3, 7)),
    ],
    red_dot=floodfill((5, 7)),
)
