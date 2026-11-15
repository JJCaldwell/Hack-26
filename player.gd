extends CharacterBody2D

@export var move_speed: float = 280.0
@export var horizontal_acceleration: float = 1700.0
@export var horizontal_friction: float = 2200.0
@export var jump_velocity: float = -470.0
@export var held_jump_gravity_scale: float = 0.78
@export var jump_release_cut: float = 0.55
@export var max_jumps: int = 2

var gravity: float = 1450.0
var fall_gravity_scale: float = 1.55
var released_jump_gravity_scale: float = 1.15
var jumps_used := 0
var launch_horizontal_speed := 0.0
var launch_horizontal_time := 0.0


func launch_from_needle(horizontal_speed: float, horizontal_time: float, vertical_speed: float) -> void:
	launch_horizontal_speed = horizontal_speed
	launch_horizontal_time = horizontal_time
	velocity = Vector2(horizontal_speed, vertical_speed)


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	if is_on_floor():
		jumps_used = 0
		launch_horizontal_time = 0.0

	if launch_horizontal_time > 0.0:
		velocity.x = launch_horizontal_speed
		launch_horizontal_time = maxf(0.0, launch_horizontal_time - delta)
	else:
		var target_speed := direction * move_speed
		var horizontal_rate := horizontal_acceleration if absf(direction) > 0.01 else horizontal_friction
		velocity.x = move_toward(velocity.x, target_speed, horizontal_rate * delta)

	if Input.is_action_just_pressed("jump") and jumps_used < max_jumps:
		velocity.y = jump_velocity
		jumps_used += 1
	elif Input.is_action_just_released("jump") and velocity.y < 0.0:
		# Releasing early makes either jump a short hop.
		velocity.y *= jump_release_cut

	if not is_on_floor():
		var gravity_scale := 1.0
		if velocity.y > 0.0:
			gravity_scale = fall_gravity_scale
		elif velocity.y < 0.0:
			gravity_scale = held_jump_gravity_scale if Input.is_action_pressed("jump") else released_jump_gravity_scale
		velocity.y += gravity * gravity_scale * delta

	move_and_slide()
