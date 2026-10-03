@tool
extends Node2D
## Draws a block of Kenney Pixel Platformer ground tiles, centred on this node:
## a grass top row with dirt below. Visual only; the parent StaticBody2D's
## collision shape is what you stand on, so size them to match.

const ATLAS := preload("res://assets/kenney_pixel-platformer/Tilemap/tilemap_packed.png")
const TILE := 18

## Width and height of the block, in tiles.
@export var size_in_tiles := Vector2i(4, 2):
	set(value):
		size_in_tiles = value
		queue_redraw()


func _draw() -> void:
	var w := size_in_tiles.x
	var h := size_in_tiles.y
	var origin := -Vector2(w, h) * TILE / 2.0
	for y in h:
		for x in w:
			# Atlas columns 1, 2 and 3 are the left edge, middle and right edge.
			# Column 0 is a block one tile wide, with both edges.
			var col := 2
			if w == 1:
				col = 0
			elif x == 0:
				col = 1
			elif x == w - 1:
				col = 3
			# Row 0 is a grass top that joins the dirt below it, row 1 is a thin
			# grass platform with a closed bottom, row 6 is dirt fill and row 7 is
			# dirt with a closed bottom.
			var row := 6
			if y == 0:
				row = 1 if h == 1 else 0
			elif y == h - 1:
				row = 7
			var dest := Rect2(origin + Vector2(x, y) * TILE, Vector2(TILE, TILE))
			var src := Rect2(Vector2(col, row) * TILE, Vector2(TILE, TILE))
			draw_texture_rect_region(ATLAS, dest, src)
