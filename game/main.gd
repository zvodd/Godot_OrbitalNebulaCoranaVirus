extends Node3D
## MVP main scene: wires planet, satellite rig, ore field, collector and HUD together and
## owns the debug keys. No round loop / fuel / upgrades yet (M5).

const SKY_SHADER := preload("res://materials/shader_sky.gdshader")
const SKY_TEXTURE := preload("res://assets/rainbow_nebula.webp")

@onready var planet: Planet = $Planet
@onready var ore_field: OreField = $OreField
@onready var rig: GyroRig = $GyroRig
@onready var collector: Collector = $GyroRig/Collector
@onready var hud: Hud = $HUD


func _ready() -> void:
	_build_environment()
	ore_field.setup(planet)
	rig.setup(planet, collector)
	hud.setup(planet, rig, collector, ore_field)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F3:
				hud.toggle_debug()
			KEY_F7:
				# Debug: blast a crater where the beam lands (ore is vaporized).
				if rig.laser.has_hit:
					planet.carve_sphere(rig.laser.hit_point, 5.0)
			KEY_F9:
				collector.clear()
				planet.build(randi())


func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("sky_tex", SKY_TEXTURE)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
