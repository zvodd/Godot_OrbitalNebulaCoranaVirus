class_name Hud
extends CanvasLayer
## Plain placeholder HUD: crosshair on the beam's landing point, loadout, what the beam is
## doing, ore counts, shell progress, plus the F3 debug overlay (ROADMAP §7, §10).

const CROSSHAIR_SHADER := preload("res://materials/canvas_crosshair.gdshader")
const BLOCK_TEXT := {
	LaserCarve.Block.TOO_HARD: "TOO HARD",
	LaserCarve.Block.OUT_OF_REACH: "OUT OF REACH",
	LaserCarve.Block.CORRUPTED: "CORRUPTED",
	LaserCarve.Block.CORE: "CORE - indestructible",
}

var planet: Planet
var rig: GyroRig
var collector: Collector
var ore_field: OreField

var _crosshair: ColorRect
var _info: Label
var _ore: Label
var _help: Label
var _debug: Label
var _fps_smooth: float = 60.0


func setup(p_planet: Planet, p_rig: GyroRig, p_collector: Collector, p_ore_field: OreField) -> void:
	planet = p_planet
	rig = p_rig
	collector = p_collector
	ore_field = p_ore_field

	var mat := ShaderMaterial.new()
	mat.shader = CROSSHAIR_SHADER
	mat.set_shader_parameter("crosshair_color", Color(1, 1, 1, 0.9))
	_crosshair = ColorRect.new()
	_crosshair.size = Vector2(100, 100)
	_crosshair.material = mat
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_info = _label(Vector2(16, 12))
	_ore = _label(Vector2(16, 0))
	_ore.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_ore.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ore.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ore.position += Vector2(-16, 12)
	_help = _label(Vector2.ZERO)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.position += Vector2(16, -12)
	_help.modulate = Color(1, 1, 1, 0.7)
	_help.text = "\n".join([
		"Mouse: orbit    Wheel: camera    LMB: laser    RMB: tractor beam",
		"1/2/3: laser type    Q/E: lens    Esc: free mouse",
		"F3: debug    F7: blast crater at aim    F9: new planet",
	])
	_debug = _label(Vector2.ZERO)
	_debug.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_debug.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_debug.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug.position += Vector2(-16, -12)
	_debug.visible = false


func toggle_debug() -> void:
	_debug.visible = not _debug.visible


func _label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(delta: float) -> void:
	if planet == null or planet.grid == null:
		return
	var grid := planet.grid
	var laser := rig.laser
	var view := get_viewport().get_visible_rect().size

	# Crosshair sits where the beam actually lands.
	var screen := view * 0.5
	if laser.has_hit and not rig.camera.is_position_behind(laser.hit_point):
		screen = rig.camera.unproject_position(laser.hit_point)
	_crosshair.position = screen - _crosshair.size * 0.5

	var lt := rig.current_laser()
	var lens := rig.current_lens()
	var lines: Array[String] = []
	if lt != null and lens != null:
		lines.append("Laser: %s    Lens: %s" % [lt.name, lens.name])
		lines.append("Power per cell: %.1f    Reach: down to r=%.1f" % [
			LaserCarve.cell_power(lt, lens, laser.power_mult),
			LaserCarve.min_cut_radius(lt, rig.orbit_radius, laser.reach_bonus)])
	lines.append(_target_line(grid, laser))
	var shell := mini(grid.outermost_intact_shell, grid.def.shells.size() - 1)
	lines.append("Shell %d  %s:  %.1f%% cleared" % [
		shell + 1, grid.def.shells[shell].name, grid.cleared_fraction(shell) * 100.0])
	_info.text = "\n".join(lines)

	var ore_lines: Array[String] = ["ORE COLLECTED"]
	for m in grid.materials:
		if m.is_ore():
			ore_lines.append("%s: %d" % [m.name, int(collector.totals.get(m.ore_id, 0.0))])
	ore_lines.append("")
	ore_lines.append("loose chunks: %d" % ore_field.live_count())
	_ore.text = "\n".join(ore_lines)

	if _debug.visible:
		_fps_smooth = lerpf(_fps_smooth, 1.0 / maxf(delta, 0.0001), 0.05)
		_debug.text = "\n".join([
			"FPS %d" % roundi(_fps_smooth),
			"chunk rebuild %.2f ms (%d chunks), worst %.2f ms" % [
				planet.last_rebuild_ms, planet.last_rebuild_count, planet.worst_chunk_ms],
			"dirty queue %d" % planet.dirty_count(),
			"planet tris %d    build %d ms    seed %d" % [
				planet.triangle_count(), roundi(planet.initial_build_ms), planet.planet_seed],
			"orbit r=%.1f    tractor pulling %d" % [rig.orbit_radius, rig.tractor.pulling],
		])


func _target_line(grid: PlanetGrid, laser: Laser) -> String:
	if not laser.has_hit:
		return "Target: -"
	var mat_name := grid.materials[laser.aimed_material].name if laser.aimed_material >= 0 else "?"
	var depth := grid.shell_top_radius(0) - planet.to_local(laser.hit_point).length()
	var line := "Target: %s    depth %.1f" % [mat_name, maxf(depth, 0.0)]
	var res := laser.last_result
	if res == null:
		return line
	if res.removed > 0.0:
		return line + "    CUTTING"
	if res.blocked != LaserCarve.Block.NONE:
		var why: String = BLOCK_TEXT[res.blocked]
		if res.blocked == LaserCarve.Block.TOO_HARD and res.blocked_material >= 0:
			var m := grid.materials[res.blocked_material]
			why += " (%s needs %.1f, have %.1f)" % [m.name, m.min_power, res.cell_power]
		return line + "    " + why
	return line
