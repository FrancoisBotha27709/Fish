@tool
extends Node3D
## Loads a preset JSON from PRESET_DIR and applies every value onto a
## GPUParticles3D node's two shader materials:
##   - process_material  -> particle_process_3d.gdshader
##   - draw_pass_1's material override -> particle_draw_3d.gdshader
##
## "Chosen Preset" in the Inspector is a plain dropdown built from the
## PRESET_NAMES list below. Add a new preset .json to PRESET_DIR, then
## add its name to PRESET_NAMES AND the @export_enum(...) line so it
## shows up here too.
##
## Works as a @tool script: changing the dropdown re-applies the preset
## immediately in the editor so you can preview it on the particle node.
## Press "Reload Preset" in the Inspector to force a fresh reload from
## disk (useful after editing a preset .json file's contents without
## changing which one is selected).

const PRESET_DIR := "res://Particles/base_particle/Presets/"

const PRESET_NAMES := [
	"magic_sparkle",
	"dust",
	"bubbles",
	"snow",
	"explosion",
	"water_splash",
	"catch_sparkle",
	"coin_burst",
	"money_rain",
	"treasure_glow",
	"storm_rain",
	"bubble_trail",
	"sun_glint",
	"seaspray_mist",
	"levelup_burst",
	"drizzle",
	"dock_dust",
	"lure_glow",
	"fish_shimmer",
	"net_splash",
	"hook_sink_trail",
	"quest_marker_glow",
	"achievement_confetti",
	"rare_fish_aura",
	"toxic_algae_bloom",
	"oil_slick_shimmer",
	"fog_mist",
	"lantern_flicker",
	"feed_scatter",
	"current_swirl",
	"lightning_flash",
	"ripple_ring",
	"boat_smoke",
	"deep_glow",
	"counter_glimmer",
]

@export_enum(
	"magic_sparkle",
	"dust",
	"bubbles",
	"snow",
	"explosion",
	"water_splash",
	"catch_sparkle",
	"coin_burst",
	"money_rain",
	"treasure_glow",
	"storm_rain",
	"bubble_trail",
	"sun_glint",
	"seaspray_mist",
	"levelup_burst",
	"drizzle",
	"dock_dust",
	"lure_glow",
	"fish_shimmer",
	"net_splash",
	"hook_sink_trail",
	"quest_marker_glow",
	"achievement_confetti",
	"rare_fish_aura",
	"toxic_algae_bloom",
	"oil_slick_shimmer",
	"fog_mist",
	"lantern_flicker",
	"feed_scatter",
	"current_swirl",
	"lightning_flash",
	"ripple_ring",
	"boat_smoke",
	"deep_glow",
	"counter_glimmer"
)
var chosen_preset : String = "magic_sparkle":
	set(value):
		chosen_preset = value
		_reload()

@export var particle : GPUParticles3D
@export_tool_button("Reload Preset") var reload_preset_btn: Callable = _reload

func _ready() -> void:
	apply(chosen_preset, particle)

func _reload() -> void:
	# Guard so the chosen_preset setter above doesn't fire during scene
	# load before `particle` has been assigned yet.
	if not is_inside_tree():
		return
	apply(chosen_preset, particle)

static func apply(preset_name: String, particles: GPUParticles3D) -> void:
	if particles == null:
		push_warning("ParticlePreset: no GPUParticles3D assigned")
		return

	var preset_path := PRESET_DIR + preset_name + ".json"
	var data := _load_json(preset_path)
	if data.is_empty():
		push_error("ParticlePreset: could not load or parse '%s'" % preset_path)
		return

	var draw_values: Dictionary = data.get("draw", {})
	var process_values: Dictionary = data.get("process", {})

	var draw_mat := _get_draw_material(particles)
	if draw_mat:
		_apply_to_material(draw_mat, draw_values)
	else:
		push_warning("ParticlePreset: no draw_pass_1 ShaderMaterial found on '%s'" % particles.name)

	var process_mat := particles.process_material as ShaderMaterial
	if process_mat:
		_apply_to_material(process_mat, process_values)
	else:
		push_warning("ParticlePreset: no process_material ShaderMaterial found on '%s'" % particles.name)

static func _get_draw_material(particles: GPUParticles3D) -> ShaderMaterial:
	if particles.draw_pass_1 and particles.draw_pass_1.surface_get_material(0):
		var mat := particles.draw_pass_1.surface_get_material(0)
		if mat is ShaderMaterial:
			return mat
	return null


static func _apply_to_material(mat: ShaderMaterial, values: Dictionary) -> void:
	for key in values.keys():
		var value = values[key]
		if value is Array and value.size() == 3:
			mat.set_shader_parameter(key, Vector3(value[0], value[1], value[2]))
		elif value is Array and value.size() == 2:
			mat.set_shader_parameter(key, Vector2(value[0], value[1]))
		else:
			mat.set_shader_parameter(key, value)


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed