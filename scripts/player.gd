extends CharacterBody2D

# =====================================================================================
#  PLATFORMER PLAYER
#
#  A full movement kit layered onto one CharacterBody2D velocity:
#
#    * RUNNING with acceleration and friction (a touch less control in the air)
#    * FORGIVENESS: coyote time and a jump buffer, so near-misses still jump
#    * JUMP FEEL: variable height, a heavier fall, and a floaty apex
#    * DOUBLE JUMP: an extra mid-air jump, refilled on the floor
#    * AIR DASH: a short fixed-speed burst, gated by a cooldown and one per airtime
#    * WALL SLIDE: hug a wall in the air to slow your fall
#    * WALL JUMP: kick off the wall (up and away), briefly locking steering so the
#                 push reads as deliberate, and refreshing the dash and air jump so
#                 the moves chain into each other
#
#  Each move is a little state machine of timers and flags on the same velocity.
#  Every tuning number is exported, so you can tune it in the Inspector, even
#  while the game is running.
# =====================================================================================

# --- Horizontal movement ---
@export_group("Run")
@export var speed: float = 130.0
@export var acceleration: float = 1300.0
@export var friction: float = 1600.0

# --- Jumping ---
@export_group("Jump")
@export var jump_velocity: float = -300.0
@export var double_jump_velocity: float = -260.0  # the second (air) jump, a touch weaker
@export var jump_cut: float = 0.45
@export var max_air_jumps: int = 1       # extra jumps after leaving the ground

# --- Dash ---  a fixed-speed burst with a cooldown; you get one per airtime.
@export_group("Dash")
@export var dash_speed: float = 340.0
@export var dash_duration: float = 0.14
@export var dash_cooldown: float = 0.35

# --- Wall slide & wall jump ---
@export_group("Wall")
@export var wall_slide_speed: float = 55.0    # capped fall speed while hugging a wall
@export var wall_jump_velocity: float = -300.0  # upward kick of a wall jump
@export var wall_jump_push: float = 170.0   # sideways shove away from the wall
@export var wall_jump_lock: float = 0.12    # brief input lock so the kick reads as deliberate

# --- Forgiveness windows (seconds) ---
@export_group("Forgiveness")
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10

# --- Gravity feel ---
var base_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
@export_group("Gravity")
@export var rise_gravity_mult: float = 0.9
@export var fall_gravity_mult: float = 1.5
@export var max_fall_speed: float = 400.0
@export var apex_speed_threshold: float = 45.0
@export var apex_gravity_mult: float = 0.55

@export_group("")

# --- Runtime state ---
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var air_jumps_left = 0

# Dash + wall state
var is_dashing = false
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var can_dash = true
var dash_dir = 1.0
var wall_jump_lock_timer = 0.0
var is_wall_sliding = false
var double_jump_timer = 0.0   # >0 while the double-jump flip animation should show

@onready var animated_sprite = $AnimatedSprite2D


func _physics_process(delta):
	# Dash is an override: while it's active we ignore gravity/steering and just fly.
	_tick_dash(delta)
	if double_jump_timer > 0.0:
		double_jump_timer -= delta
	if is_dashing:
		_update_animation()
		move_and_slide()
		return

	_apply_gravity(delta)
	_handle_wall_slide(delta)
	_handle_jump(delta)
	_handle_horizontal(delta)
	_try_start_dash()
	_update_animation()
	move_and_slide()


func _apply_gravity(delta):
	if not is_on_floor():
		var mult = rise_gravity_mult if velocity.y < 0.0 else fall_gravity_mult
		if absf(velocity.y) < apex_speed_threshold:
			mult *= apex_gravity_mult
		velocity.y += base_gravity * mult * delta
		velocity.y = min(velocity.y, max_fall_speed)


# The jump chain, in priority order: WALL jump > ground jump > air (double) jump.
func _handle_jump(delta):
	# On the floor, refill both the coyote grace and the air-jump counter.
	if is_on_floor():
		coyote_timer = coyote_time
		air_jumps_left = max_air_jumps
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	# A buffered press while hugging a wall in mid-air = a wall jump (highest priority).
	if jump_buffer_timer > 0.0 and is_on_wall_only() and not is_on_floor():
		_do_wall_jump()
		jump_buffer_timer = 0.0
	# A buffered press + coyote grace = a normal ground jump.
	elif jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
	# Otherwise spend an air jump (the double jump).
	elif jump_buffer_timer > 0.0 and air_jumps_left > 0:
		velocity.y = double_jump_velocity
		air_jumps_left -= 1
		double_jump_timer = 0.45   # show the double-jump flip animation
		jump_buffer_timer = 0.0

	# Variable jump height: let go early for a shorter hop.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut


# Kick off a wall: shove away + up, refresh the air jump AND the dash so wall play
# chains, and lock steering briefly so the kick reads as committed.
func _do_wall_jump():
	var wall_normal = get_wall_normal()
	velocity.x = wall_normal.x * wall_jump_push
	velocity.y = wall_jump_velocity
	wall_jump_lock_timer = wall_jump_lock
	air_jumps_left = max_air_jumps   # give the double jump back after a wall jump
	can_dash = true                  # ...and the dash, so wall play stays expressive
	animated_sprite.flip_h = wall_normal.x > 0.0


# Hug a wall in the air while pressing into it to slide down slowly instead of
# free-falling. That is the setup that makes a wall jump feel intentional.
func _handle_wall_slide(delta):
	is_wall_sliding = false
	if is_on_floor() or not is_on_wall_only() or velocity.y <= 0.0:
		return
	var direction = Input.get_axis("move_left", "move_right")
	var wall_normal = get_wall_normal()
	# Only slide if you're actively pushing TOWARD the wall.
	if direction != 0.0 and signf(direction) == -signf(wall_normal.x):
		velocity.y = minf(velocity.y, wall_slide_speed)
		is_wall_sliding = true
		animated_sprite.flip_h = wall_normal.x < 0.0


# Counts the dash + cooldown timers, drives the dash velocity while it's active,
# and refreshes the dash whenever you're on the ground (one dash per airtime).
func _tick_dash(delta):
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_dir * dash_speed
		velocity.y = 0.0   # a flat, floaty dash reads cleaner than an arced one
		if dash_timer <= 0.0:
			is_dashing = false
			velocity.x = dash_dir * speed   # ease out into a normal run
	if is_on_floor():
		can_dash = true


# Fire a dash on input if one's available. Dashes in the held direction, or the
# way you're facing if you're not steering.
func _try_start_dash():
	if not Input.is_action_just_pressed("dash"):
		return
	if is_dashing or not can_dash or dash_cooldown_timer > 0.0:
		return
	var input_dir = Input.get_axis("move_left", "move_right")
	dash_dir = signf(input_dir) if input_dir != 0.0 else (1.0 if animated_sprite.flip_h else -1.0)
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	can_dash = false
	animated_sprite.flip_h = dash_dir > 0.0


func _handle_horizontal(delta):
	# Just after a wall jump, ignore steering for a beat so the kick is committed.
	if wall_jump_lock_timer > 0.0:
		wall_jump_lock_timer -= delta
		animated_sprite.flip_h = velocity.x > 0.0
		return

	var direction = Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		var accel = acceleration if is_on_floor() else acceleration * 0.7
		velocity.x = move_toward(velocity.x, direction * speed, accel * delta)
		animated_sprite.flip_h = direction > 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _update_animation():
	# Clinging to a wall takes priority - show the wall-cling pose.
	if is_wall_sliding:
		animated_sprite.play("wall_jump")
	elif not is_on_floor():
		if double_jump_timer > 0.0:
			animated_sprite.play("double_jump")
		elif velocity.y < 0.0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif abs(velocity.x) > 10.0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")
