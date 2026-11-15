class_name GyroRig
extends Node3D
## The player's gyro satellite: orbits the (stationary) planet with trackball controls and
## inertia, carries the emitters and the third-person camera (ROADMAP §6.1).
##
## This node IS the satellite: it sits at `orbit_radius` with -Z pointing at the planet
## centre. The laser fires straight down that axis. Scroll only moves the camera.
##
## Merged from script/orbit_cam.gd and demo-experiment-sufrnorm/orbit.gd; the clamped
## yaw/pitch is replaced by quaternion accumulation so the poles are reachable.

@export_group("Loadout")
@export var laser_types: Array[LaserTypeDef] = []
@export var lenses: Array[LensDef] = []

@export_group("Orbit")
## orbit_radius = surface_radius × orbit_factors[collapses]. Must shrink per collapse so
## the planet looks bigger each time (GDD §3.5).
@export var orbit_factors: Array[float] = [1.8, 1.65, 1.5, 1.4, 1.32, 1.26, 1.2, 1.16]
## Seconds-ish for the descent after a collapse.
@export var descent_time: float = 3.0

@export_group("Motion")
@export var mouse_sens: float = 0.00022
@export var friction: float = 6.0
## Radians per 1/60 s.
@export var max_speed: float = 0.07
## Multiplier when the input opposes the current spin (snappier reversals).
@export var inertia_gain: float = 1.5

@export_group("Camera")
@export var cam_distance: float = 14.0
@export var cam_min: float = 5.0
@export var cam_max: float = 45.0
## Camera height above the beam axis as a fraction of its distance.
@export var cam_height: float = 0.3
@export var fov: float = 60.0

var planet: Planet
var orbit_radius: float = 56.0
var camera: Camera3D
var laser: Laser
var tractor: TractorBeam
var laser_index: int = 0
var lens_index: int = 0
## When false the rig stops reading the mouse buttons, so tests / cutscenes can drive
## `laser.active` and `tractor.active` directly.
var manual_control: bool = true

var _orientation := Quaternion.IDENTITY
var _velocity := Vector2.ZERO
var _mouse_buffer := Vector2.ZERO
var _aim_dist: float = 25.0


func setup(p_planet: Planet, collector: Collector) -> void:
	planet = p_planet
	orbit_radius = _target_orbit_radius()
	_aim_dist = orbit_radius - planet.grid.surface_radius()

	laser = Laser.new()
	laser.name = "Laser"
	laser.planet = planet
	add_child(laser)
	tractor = TractorBeam.new()
	tractor.name = "TractorBeam"
	tractor.collector = collector
	add_child(tractor)
	_select(0, 0)

	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.2
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()

	_build_placeholder_model()
	_build_light()
	_apply_transform()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Park the satellite directly above a point / direction on the planet and stop spinning.
func aim_at(dir: Vector3) -> void:
	var z := dir.normalized()
	var x := (Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).cross(z).normalized()
	_orientation = Basis(x, z.cross(x), z).get_rotation_quaternion()
	_velocity = Vector2.ZERO
	_mouse_buffer = Vector2.ZERO
	_apply_transform()


func current_laser() -> LaserTypeDef:
	return laser_types[laser_index] if not laser_types.is_empty() else null


func current_lens() -> LensDef:
	return lenses[lens_index] if not lenses.is_empty() else null


func cycle_lens(step: int) -> void:
	if not lenses.is_empty():
		_select(laser_index, posmod(lens_index + step, lenses.size()))


func select_laser(index: int) -> void:
	if index >= 0 and index < laser_types.size():
		_select(index, lens_index)


func _select(p_laser: int, p_lens: int) -> void:
	laser_index = p_laser
	lens_index = p_lens
	laser.laser_type = current_laser()
	laser.lens = current_lens()


func _target_orbit_radius() -> float:
	var grid := planet.grid
	var collapses := clampi(grid.outermost_intact_shell, 0, orbit_factors.size() - 1)
	return grid.surface_radius() * orbit_factors[collapses]


func _unhandled_input(event: InputEvent) -> void:
	if planet == null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		# Accumulate raw motion; applied once per frame (handles high polling rates).
		_mouse_buffer -= event.relative * mouse_sens
	elif event is InputEventMouseButton and event.pressed:
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				cam_distance = clampf(cam_distance * 0.9, cam_min, cam_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_distance = clampf(cam_distance * 1.1, cam_min, cam_max)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_1: select_laser(0)
			KEY_2: select_laser(1)
			KEY_3: select_laser(2)
			KEY_Q: cycle_lens(-1)
			KEY_E: cycle_lens(1)


func _process(delta: float) -> void:
	if planet == null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if manual_control:
		laser.active = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		tractor.active = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	_apply_buffered_input()
	# Trackball: rotate about the satellite's own up/right axes — no pole lock.
	var step := _velocity * (delta * 60.0)
	_orientation = (_orientation * Quaternion(Vector3.UP, step.x) * Quaternion(Vector3.RIGHT, step.y)).normalized()
	# Inertia: exponential decay, frame-rate independent.
	_velocity = _velocity.lerp(Vector2.ZERO, minf(friction * delta, 1.0))

	# Ease toward the orbit for the current outermost shell (drops after a collapse).
	var target := _target_orbit_radius()
	orbit_radius = lerpf(orbit_radius, target, 1.0 - exp(-delta * 3.0 / maxf(descent_time, 0.01)))
	_apply_transform()

	# Keep the camera looking at where the beam lands so the pit stays centred.
	var want := orbit_radius - planet.grid.surface_radius()
	if laser.has_hit:
		want = laser.hit_point.distance_to(global_position)
	_aim_dist = lerpf(_aim_dist, want, 1.0 - exp(-delta * 4.0))
	var cam_pos := Vector3(0.0, cam_distance * cam_height, cam_distance)
	var look := Vector3(0.0, 0.0, -_aim_dist)
	camera.transform = Transform3D(Basis.looking_at(look - cam_pos, Vector3.UP), cam_pos)


func _apply_buffered_input() -> void:
	if _mouse_buffer.length_squared() < 1e-12:
		return
	if _velocity.length() > 0.00001:
		# Same direction as the spin → less gain; opposing → more, to reverse quickly.
		var d := _mouse_buffer.normalized().dot(_velocity.normalized())
		_velocity += _mouse_buffer * remap(d, 1.0, -1.0, 0.5, inertia_gain)
	else:
		_velocity += _mouse_buffer
	_velocity = _velocity.limit_length(max_speed)
	_mouse_buffer = Vector2.ZERO


func _apply_transform() -> void:
	var b := Basis(_orientation)
	global_transform = Transform3D(b, planet.global_position + b.z * orbit_radius)


func _build_placeholder_model() -> void:
	# Stand-in for the designer's gyro armature: two rings and a hub. The camera looks
	# past it, so keep the beam axis clear.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.62, 0.3)
	mat.metallic = 0.8
	mat.roughness = 0.35
	var ring := TorusMesh.new()
	ring.inner_radius = 1.5
	ring.outer_radius = 1.8
	ring.material = mat
	var r1 := MeshInstance3D.new()
	r1.mesh = ring
	r1.rotation = Vector3(PI / 2.0, 0, 0)
	add_child(r1)
	var ring2 := TorusMesh.new()
	ring2.inner_radius = 1.05
	ring2.outer_radius = 1.25
	ring2.material = mat
	var r2 := MeshInstance3D.new()
	r2.mesh = ring2
	r2.rotation = Vector3(0, 0, PI / 2.0)
	add_child(r2)
	var hub_mesh := SphereMesh.new()
	hub_mesh.radius = 0.45
	hub_mesh.height = 0.9
	hub_mesh.material = mat
	var hub := MeshInstance3D.new()
	hub.mesh = hub_mesh
	add_child(hub)


func _build_light() -> void:
	# The key light rides with the satellite, off-axis, so the working area is always lit
	# and pits pick up shading.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, 32.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
