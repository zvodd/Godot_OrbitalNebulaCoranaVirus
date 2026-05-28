class_name TrackballCamera
extends Camera3D

@export_group("Motion")
@export var mouse_sens := 0.0012
@export var friction := 5.0
@export var max_speed := 0.5
@export var inertia_gain := 1.5 # Multiplier for opposing movement

@export_group("Distance")
@export var distance := 5.0
@export var min_dist := 2.8
@export var max_dist := 8.0

var yaw := 0.0
var pitch := 0.0
var velocity := Vector2.ZERO
var mouse_buffer := Vector2.ZERO

@onready var pivot_transform := Transform3D.IDENTITY

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pivot_transform.origin = get_parent().global_position

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Accumulate raw motion into buffer to handle high-polling rates
		mouse_buffer.x -= event.relative.x * mouse_sens
		mouse_buffer.y -= event.relative.y * mouse_sens
		
	if event is InputEventMouseButton and event.is_pressed():
		var scroll := 0.0
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: scroll = -0.2
			MOUSE_BUTTON_WHEEL_DOWN: scroll = 0.2
		distance = clampf(distance + scroll, min_dist, max_dist)

func _process(delta: float) -> void:
	_apply_buffered_input()
	
	# Apply velocity
	yaw += velocity.x
	pitch = clamp(pitch + velocity.y, -PI * 0.49, PI * 0.49)

	# Inertia: Exponential decay for frame-rate independence
	velocity = velocity.lerp(Vector2.ZERO, friction * delta)

	# Transform Update
	var q := Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
	pivot_transform.basis = Basis(q)
	global_transform = pivot_transform.translated_local(Vector3.BACK * distance)

func _apply_buffered_input() -> void:
	if mouse_buffer.length() < 0.0001:
		return

	if velocity.length() > 0.0001:
		# Directional Gain: How much does input align with current velocity?
		# Dot ~ 1.0 (Same direction) -> reduce gain
		# Dot ~ -1.0 (Opposite) -> increase gain to reverse spin
		var dot_val := mouse_buffer.normalized().dot(velocity.normalized())
		var gain := remap(dot_val, 1.0, -1.0, 0.5, inertia_gain)
		velocity += mouse_buffer * gain
	else:
		velocity += mouse_buffer

	# Clamp rotation speed
	velocity = velocity.limit_length(max_speed)
	
	# Clear buffer
	mouse_buffer = Vector2.ZERO
