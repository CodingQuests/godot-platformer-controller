extends Node2D
## The test level: a platform you need the double jump for, a gap to dash or
## double jump across, and a shaft to wall jump up. A Camera2D follows the
## player. Demo only; the controller is scripts/player.gd.

@onready var player = $Player

## Fall below this (into the gap) and you are put back at the start.
const FALL_LIMIT := 300.0

## The camera looks a little above the player's feet.
const CAMERA_OFFSET := Vector2(0, -30)

var _spawn := Vector2.ZERO


func _ready():
	_spawn = player.global_position


func _process(_delta):
	if is_instance_valid(player) and player.global_position.y > FALL_LIMIT:
		_respawn()
	# A simple follow camera so the player never runs off-screen.
	if is_instance_valid(player):
		$Camera2D.global_position = $Camera2D.global_position.lerp(player.global_position + CAMERA_OFFSET, 0.15)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_respawn()


func _respawn():
	player.global_position = _spawn
	player.velocity = Vector2.ZERO
	$Camera2D.global_position = _spawn + CAMERA_OFFSET
