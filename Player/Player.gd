extends CharacterBody3D

@onready var body = $Body
@onready var head = $Body/Head
@onready var camera = $Body/Head/CameraMarker3D/Camera3D
@onready var camera_target = $Body/Head/CameraMarker3D
@onready var head_position: Vector3 = head.position

var mouse_sensitivity: float = 0.1

const ACCELERATION_DEFAULT: float = 7.0
const ACCELERATION_AIR: float = 1.0
const SPEED_DEFAULT: float = 7.0
const SPEED_ON_STAIRS: float = 5.0

var acceleration: float = ACCELERATION_DEFAULT
var speed: float = SPEED_DEFAULT

var gravity: float = 9.8
var jump: float = 5.0
var direction: Vector3 = Vector3.ZERO
var main_velocity: Vector3 = Vector3.ZERO
var gravity_direction: Vector3 = Vector3.ZERO
var movement: Vector3 = Vector3.ZERO

const STAIRS_FEELING_COEFFICIENT: float = 2.5
const WALL_MARGIN: float = 0.001
const STEP_DOWN_MARGIN: float = 0.01
const STEP_HEIGHT_DEFAULT: Vector3 = Vector3(0, 0.6, 0)
const STEP_HEIGHT_IN_AIR_DEFAULT: Vector3 = Vector3(0, 0.6, 0)
const STEP_MAX_SLOPE_DEGREE: float = 40.0
const STEP_CHECK_COUNT: int = 2
const SPEED_CLAMP_AFTER_JUMP_COEFFICIENT = 0.4
const SPEED_CLAMP_SLOPE_STEP_UP_COEFFICIENT = 0.4

var step_height_main: Vector3
var step_incremental_check_height: Vector3
var is_enabled_stair_stepping_in_air: bool = true
var is_jumping: bool = false
var is_in_air: bool = false

var head_offset: Vector3 = Vector3.ZERO
var camera_target_position : Vector3 = Vector3.ZERO
var camera_lerp_coefficient: float = 1.0
var time_in_air: float = 0.0
var update_camera = false
var camera_gt_previous : Transform3D
var camera_gt_current : Transform3D

func _ready():
	#floor_snap_length = 0.0;
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	camera_target_position = camera.global_transform.origin
	camera.set_as_top_level(true)
	camera.global_transform = camera_target.global_transform
	
	camera_gt_previous = camera_target.global_transform
	camera_gt_current = camera_target.global_transform

func update_camera_transform():
	camera_gt_previous = camera_gt_current
	camera_gt_current = camera_target.global_transform

# Function: Handle mouse mode toggling
func _toggle_mouse_mode():
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
func _process(delta: float) -> void:
	if update_camera:
		update_camera_transform()
		update_camera = false

	var interpolation_fraction = clamp(Engine.get_physics_interpolation_fraction(), 0, 1)

	var camera_xform = camera_gt_previous.interpolate_with(camera_gt_current, interpolation_fraction)
	camera.global_transform = camera_xform

	var head_xform : Transform3D = head.get_global_transform()
	
	camera_target_position = lerp(camera_target_position, head_xform.origin, delta * speed * STAIRS_FEELING_COEFFICIENT * camera_lerp_coefficient)

	if is_on_floor():
		time_in_air = 0.0
		camera_lerp_coefficient = 1.0
		camera.position.y = camera_target_position.y
	else:
		time_in_air += delta
		if time_in_air > 1.0:
			camera_lerp_coefficient += delta
			camera_lerp_coefficient = clamp(camera_lerp_coefficient, 2.0, 4.0)
		else: 
			camera_lerp_coefficient = 2.0

		camera.position.y = camera_target_position.y

func _input(event):
	# Handle ESC input
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_mode()
		
	if event is InputEventMouseMotion:
		body.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta):
	update_camera = true
	var is_step: bool = false
	
	var input = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	direction = (body.global_transform.basis * Vector3(input.x, 0, input.y)).normalized()

	if is_on_floor():
		is_jumping = false
		is_in_air = false
		acceleration = ACCELERATION_DEFAULT
		gravity_direction = Vector3.ZERO
	else:
		is_in_air = true
		acceleration = ACCELERATION_AIR
		gravity_direction += Vector3.DOWN * gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		is_jumping = true
		is_in_air = false
		gravity_direction = Vector3.UP * jump

	direction *= input.length();
	main_velocity = main_velocity.lerp(direction * speed, acceleration * delta)

	var step_result : StepResult = StepResult.new()
	
	is_step = step_check(main_velocity * delta, is_jumping, step_result)
	
	if is_step:
		var is_enabled_stair_stepping: bool = true
		if step_result.is_step_up and is_in_air and not is_enabled_stair_stepping_in_air:
			is_enabled_stair_stepping = false

		if is_enabled_stair_stepping:
			global_transform.origin += step_result.diff_position
			head_offset = step_result.diff_position
			speed = SPEED_ON_STAIRS
	else:
		head_offset = head_offset.lerp(Vector3.ZERO, delta * speed * STAIRS_FEELING_COEFFICIENT)
		
		if abs(head_offset.y) <= 0.01:
			speed = SPEED_DEFAULT

	movement = main_velocity + gravity_direction

	set_velocity(movement)
	set_max_slides(6)
	move_and_slide()
	
	if is_step and step_result.is_step_up and is_enabled_stair_stepping_in_air:
		if is_in_air or direction.dot(step_result.normal) > 0:
			main_velocity *= SPEED_CLAMP_AFTER_JUMP_COEFFICIENT
			gravity_direction *= SPEED_CLAMP_AFTER_JUMP_COEFFICIENT

	if is_jumping:
		is_jumping = false
		is_in_air = true

class StepResult:
	var diff_position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	var is_step_up: bool = false

func test_motion(transform3d: Transform3D, motion: Vector3, recovery_as_collision: bool = false) -> PhysicsTestMotionResult3D:
	var test_params = PhysicsTestMotionParameters3D.new()
	test_params.from = transform3d
	test_params.motion = motion
	test_params.recovery_as_collision = recovery_as_collision;
	
	var result = PhysicsTestMotionResult3D.new()
	var collided = PhysicsServer3D.body_test_motion(self.get_rid(), test_params, result)
	if collided:
		return result
	return null

func step_up(move: Vector3, step_result: StepResult) -> bool:
	#if gravity is pulling is down we must be fallinga and should not stair step.
	if gravity_direction.y < 0:
		return false;
		
	for i in range(STEP_CHECK_COUNT):	
		var step_height: Vector3 = step_height_main - i * step_incremental_check_height;
		var transform3d: Transform3D = global_transform;
		
		#Tests if moving up by step_height collides with anything.
		#If there’s a collision from above, skip this step height and try the next because we hit a ceiling.	
		var up_result = test_motion(transform3d, step_height);
		if(up_result && up_result.get_collision_normal().y < 0):
			continue;
		
		#We are allowed to move up with because there is no ceiling.
		transform3d.origin += step_height;
		#After moving up by step_height, test if moving forward will collide.
		var forward_result = test_motion(transform3d, move);
		if (forward_result == null):
			#We are allowed to move forward because there is no wall.
			transform3d.origin += move;
			#After moving forward, test if moving down will collide.
			var down_result = test_motion(transform3d, -step_height);	
			if (down_result != null):
				if down_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
					step_result.is_step_up = true;
					step_result.diff_position = -down_result.get_remainder();
					step_result.normal = down_result.get_collision_normal();
					return true;
		else:
			#We must have collided with a wall.
			#We add the distance we traveled against the wall.
			transform3d.origin += forward_result.get_travel();
			#Then move slightly away from the wall. 
			var wall_collision_normal: Vector3 = forward_result.get_collision_normal();
			transform3d.origin += wall_collision_normal * WALL_MARGIN
			#Then test our remaining movement sliding along the wall
			var slide_movement = forward_result.get_remainder().slide(wall_collision_normal);
			var slide_result = test_motion(transform3d, slide_movement);
			
			if (slide_result  == null):
				#If we hit nothing add or sliding movement
				transform3d.origin += slide_movement
				#After sliding, test if moving down will collide.
				var down_result = test_motion(transform3d, -step_height);
				if (down_result != null):
					if down_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
						step_result.is_step_up = true
						step_result.diff_position = -down_result.get_remainder();
						step_result.normal = down_result.get_collision_normal();
						return true;
	return false;
	
func step_down(move: Vector3, step_result: StepResult):
	step_result.is_step_up = false
	var transform3d: Transform3D = global_transform

	var forward_result = test_motion(transform3d, move, true);
	if (!forward_result):
		#We are allowed to move forward because there is no wall.
		transform3d.origin += move
		#After moving forward, test if moving down will collide.
		var down_result = test_motion(transform3d, -step_height_main, true);	
		if (down_result != null):
			if down_result.get_travel().y < -STEP_DOWN_MARGIN:
				if down_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
					step_result.diff_position = down_result.get_travel()
					step_result.normal = down_result.get_collision_normal()
					return true

	elif is_zero_approx(forward_result.get_collision_normal().y):
		#We must have collided with a wall.
		#We add the distance we traveled against the wall.
		transform3d.origin += forward_result.get_travel();
		#Then move slightly away from the wall. 
		var wall_collision_normal: Vector3 = forward_result.get_collision_normal()
		transform3d.origin += wall_collision_normal * WALL_MARGIN
		#Then test our remaining movement sliding along the wall
		var slide_movement = forward_result.get_remainder().slide(wall_collision_normal);	
		var slide_result = test_motion(transform3d, slide_movement, true);
		if (!slide_result):
			#If we hit nothing add or sliding movement
			transform3d.origin += slide_movement

			#After sliding, test if moving down will collide.
			var down_result = test_motion(transform3d, -step_height_main, true);	
			if (down_result != null):
				if down_result.get_travel().y < -STEP_DOWN_MARGIN:
					if down_result.get_collision_normal().angle_to(Vector3.UP) <= deg_to_rad(STEP_MAX_SLOPE_DEGREE):
						step_result.diff_position = down_result.get_travel()
						step_result.normal = down_result.get_collision_normal()
						return true
	return false;

	
func step_check(move: Vector3, is_jumping_: bool, step_result: StepResult):
	step_height_main = STEP_HEIGHT_DEFAULT
	step_incremental_check_height = STEP_HEIGHT_DEFAULT / STEP_CHECK_COUNT
	
	if is_in_air and is_enabled_stair_stepping_in_air:
		step_height_main = STEP_HEIGHT_IN_AIR_DEFAULT
		step_incremental_check_height = STEP_HEIGHT_IN_AIR_DEFAULT / STEP_CHECK_COUNT
		
	var is_step: bool = step_up(move, step_result);
	if (!is_jumping_ && !is_step && is_on_floor()):
		is_step = step_down(move, step_result)
		
	return is_step
