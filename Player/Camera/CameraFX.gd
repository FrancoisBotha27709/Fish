extends CanvasLayer

@export_group("CameraFX")
@export var cam_fx_enabled : bool = false : set = set_cam_fx_enabled
@export var cam_timer : Label
@export var ui_container : MarginContainer
@export var rec_orb : Sprite2D
@export_subgroup("Start Time")
@export_range(0, 99) var start_hours : int = 0
@export_range(0, 59) var start_minutes : int = 0
@export_range(0, 59) var start_seconds : int = 0

@export_group("VHS")
@export var vhs_enabled: bool = true : set = set_vhs_enabled
@export_range(0.0, 1.0) var vhs_scanline_intensity: float = 0.15 : set = set_vhs_scanline_intensity
@export_range(50.0, 1000.0) var vhs_scanline_count: float = 240.0 : set = set_vhs_scanline_count
@export_range(0.0, 1.0) var vhs_noise_intensity: float = 0.05 : set = set_vhs_noise_intensity
@export_range(0.0, 0.05) var vhs_tracking_distortion: float = 0.0015 : set = set_vhs_tracking_distortion
@export_range(0.0, 10.0) var vhs_wobble_speed: float = 1.0 : set = set_vhs_wobble_speed
@export_range(0.0, 0.02) var vhs_color_bleed: float = 0.003 : set = set_vhs_color_bleed
@export_range(0.0, 1.0) var vhs_vignette: float = 0.2 : set = set_vhs_vignette

@export_group("Chromatic Aberration")
@export var ca_enabled: bool = true : set = set_ca_enabled
@export_range(2, 12) var ca_samples: int = 3 : set = set_ca_samples
@export_range(0.0, 0.05) var ca_strength: float = 0.004 : set = set_ca_strength
@export var ca_radial: bool = true : set = set_ca_radial

@export_group("Lens Scuffs")
@export var scuff_enabled: bool = true : set = set_scuff_enabled
@export var scuff_texture: Texture2D : set = set_scuff_texture
@export_range(0.0, 1.0) var scuff_opacity: float = 0.35 : set = set_scuff_opacity
@export var scuff_scale: float = 1.0 : set = set_scuff_scale
@export var scuff_offset: Vector2 = Vector2.ZERO : set = set_scuff_offset
@export_range(0.0, 1.0) var scuff_smudge: float = 0.0 : set = set_scuff_smudge

@export_group("Color Correction")
@export_range(-2.0, 2.0) var cc_exposure: float = 0.0 : set = set_cc_exposure
@export_range(0.0, 2.0) var cc_contrast: float = 1.0 : set = set_cc_contrast
@export_range(0.0, 2.0) var cc_saturation: float = 1.0 : set = set_cc_saturation
@export_range(0.1, 3.0) var cc_gamma: float = 1.0 : set = set_cc_gamma
@export var cc_color_filter: Color = Color.WHITE : set = set_cc_color_filter
@export var cc_shadows_tint: Color = Color.WHITE : set = set_cc_shadows_tint
@export var cc_highlights_tint: Color = Color.WHITE : set = set_cc_highlights_tint

@export_group("Lens Distortion")
@export var lens_distortion_enabled: bool = false : set = set_lens_distortion_enabled
@export_range(-1.0, 1.0) var lens_barrel_amount: float = 0.0 : set = set_lens_barrel_amount

@export_group("Cinematic")
@export var grain_enabled: bool = true : set = set_grain_enabled
@export_range(0.0, 1.0) var grain_intensity: float = 0.05 : set = set_grain_intensity
@export var vignette_enabled: bool = true : set = set_vignette_enabled
@export_range(0.0, 1.0) var vignette_strength: float = 0.3 : set = set_vignette_strength
@export_range(0.1, 2.0) var vignette_softness: float = 0.8 : set = set_vignette_softness
@export var letterbox_enabled: bool = false : set = set_letterbox_enabled
@export_range(0.0, 0.5) var letterbox_size: float = 0.1 : set = set_letterbox_size

@export var rect_path: NodePath = ^"Rect"

const TWEEN_DUR := 0.6

var _mat: ShaderMaterial
var _blackout_active: bool = false
var _vhs_baseline: Dictionary = {}
var _time_passed : float

func _ready() -> void:
	var rect := get_node_or_null(rect_path) as ColorRect
	if rect == null:
		push_error("CameraFX: no ColorRect found at rect_path '%s'." % rect_path)
		return
	_mat = rect.material as ShaderMaterial
	if _mat == null:
		push_error("CameraFX: the ColorRect's material is not a ShaderMaterial using camera_fx.gdshader.")
		return
	if ui_container:
		ui_container.visible = cam_fx_enabled
	SignalBus.connect("blackout", _on_blackout)
	SignalBus.connect("loaded", _on_loaded)
	SignalBus.connect("loading_started", _on_loading_started)

	_push_all_params()

func _process(delta: float) -> void:
	if cam_fx_enabled:
		_update_time(delta)
		_blip_rec_orb()

func _blip_rec_orb() -> void:
	if rec_orb == null:
		return
	rec_orb.visible = int(_time_passed) % 2 == 0

func _get_start_offset() -> int:
	return start_hours * 3600 + start_minutes * 60 + start_seconds

func _update_time(delta: float) -> void:
	_time_passed += delta
	_refresh_timer_label()

func _refresh_timer_label() -> void:
	if cam_timer == null:
		return
	var total_seconds : int = int(_time_passed) + _get_start_offset()
	var hours := total_seconds / 3600
	var mins := (total_seconds / 60) % 60
	var sec := total_seconds % 60
	cam_timer.text = "%02d : %02d : %02d" % [hours, mins, sec]

func get_fx_material() -> ShaderMaterial:
	return _mat

func _p(name: StringName, value) -> void:
	if _mat:
		_mat.set_shader_parameter(name, value)

func _push_all_params() -> void:
	set_vhs_enabled(vhs_enabled)
	set_vhs_scanline_intensity(vhs_scanline_intensity)
	set_vhs_scanline_count(vhs_scanline_count)
	set_vhs_noise_intensity(vhs_noise_intensity)
	set_vhs_tracking_distortion(vhs_tracking_distortion)
	set_vhs_wobble_speed(vhs_wobble_speed)
	set_vhs_color_bleed(vhs_color_bleed)
	set_vhs_vignette(vhs_vignette)
	set_ca_enabled(ca_enabled)
	set_ca_samples(ca_samples)
	set_ca_strength(ca_strength)
	set_ca_radial(ca_radial)
	set_scuff_enabled(scuff_enabled)
	set_scuff_texture(scuff_texture)
	set_scuff_opacity(scuff_opacity)
	set_scuff_scale(scuff_scale)
	set_scuff_offset(scuff_offset)
	set_scuff_smudge(scuff_smudge)
	set_lens_distortion_enabled(lens_distortion_enabled)
	set_lens_barrel_amount(lens_barrel_amount)
	set_cc_exposure(cc_exposure)
	set_cc_contrast(cc_contrast)
	set_cc_saturation(cc_saturation)
	set_cc_gamma(cc_gamma)
	set_cc_color_filter(cc_color_filter)
	set_cc_shadows_tint(cc_shadows_tint)
	set_cc_highlights_tint(cc_highlights_tint)
	set_grain_enabled(grain_enabled)
	set_grain_intensity(grain_intensity)
	set_vignette_enabled(vignette_enabled)
	set_vignette_strength(vignette_strength)
	set_vignette_softness(vignette_softness)
	set_letterbox_enabled(letterbox_enabled)
	set_letterbox_size(letterbox_size)

func set_vhs_enabled(v: bool) -> void: vhs_enabled = v; _p(&"vhs_enabled", v)
func set_cam_fx_enabled(v: bool) -> void:
	cam_fx_enabled = v
	if ui_container:
		ui_container.visible = v
func set_vhs_scanline_intensity(v: float) -> void: vhs_scanline_intensity = v; _p(&"vhs_scanline_intensity", v)
func set_vhs_scanline_count(v: float) -> void: vhs_scanline_count = v; _p(&"vhs_scanline_count", v)
func set_vhs_noise_intensity(v: float) -> void: vhs_noise_intensity = v; _p(&"vhs_noise_intensity", v)
func set_vhs_tracking_distortion(v: float) -> void: vhs_tracking_distortion = v; _p(&"vhs_tracking_distortion", v)
func set_vhs_wobble_speed(v: float) -> void: vhs_wobble_speed = v; _p(&"vhs_wobble_speed", v)
func set_vhs_color_bleed(v: float) -> void: vhs_color_bleed = v; _p(&"vhs_color_bleed", v)
func set_vhs_vignette(v: float) -> void: vhs_vignette = v; _p(&"vhs_vignette", v)

func set_ca_enabled(v: bool) -> void: ca_enabled = v; _p(&"ca_enabled", v)
func set_ca_samples(v: int) -> void: ca_samples = v; _p(&"ca_samples", v)
func set_ca_strength(v: float) -> void: ca_strength = v; _p(&"ca_strength", v)
func set_ca_radial(v: bool) -> void: ca_radial = v; _p(&"ca_radial", v)

func set_scuff_enabled(v: bool) -> void: scuff_enabled = v; _p(&"scuff_enabled", v)
func set_scuff_texture(v: Texture2D) -> void: scuff_texture = v; _p(&"scuff_texture", v)
func set_scuff_opacity(v: float) -> void: scuff_opacity = v; _p(&"scuff_opacity", v)
func set_scuff_scale(v: float) -> void: scuff_scale = v; _p(&"scuff_scale", v)
func set_scuff_offset(v: Vector2) -> void: scuff_offset = v; _p(&"scuff_offset", v)
func set_scuff_smudge(v: float) -> void: scuff_smudge = v; _p(&"scuff_smudge", v)

func set_lens_distortion_enabled(v: bool) -> void: lens_distortion_enabled = v; _p(&"lens_distortion_enabled", v)
func set_lens_barrel_amount(v: float) -> void: lens_barrel_amount = v; _p(&"lens_barrel_amount", v)

func set_cc_exposure(v: float) -> void: cc_exposure = v; _p(&"cc_exposure", v)
func set_cc_contrast(v: float) -> void: cc_contrast = v; _p(&"cc_contrast", v)
func set_cc_saturation(v: float) -> void: cc_saturation = v; _p(&"cc_saturation", v)
func set_cc_gamma(v: float) -> void: cc_gamma = v; _p(&"cc_gamma", v)
func set_cc_color_filter(v: Color) -> void: cc_color_filter = v; _p(&"cc_color_filter", Vector3(v.r, v.g, v.b))
func set_cc_shadows_tint(v: Color) -> void: cc_shadows_tint = v; _p(&"cc_shadows_tint", Vector3(v.r, v.g, v.b))
func set_cc_highlights_tint(v: Color) -> void: cc_highlights_tint = v; _p(&"cc_highlights_tint", Vector3(v.r, v.g, v.b))

func set_grain_enabled(v: bool) -> void: grain_enabled = v; _p(&"grain_enabled", v)
func set_grain_intensity(v: float) -> void: grain_intensity = v; _p(&"grain_intensity", v)
func set_vignette_enabled(v: bool) -> void: vignette_enabled = v; _p(&"vignette_enabled", v)
func set_vignette_strength(v: float) -> void: vignette_strength = v; _p(&"vignette_strength", v)
func set_vignette_softness(v: float) -> void: vignette_softness = v; _p(&"vignette_softness", v)
func set_letterbox_enabled(v: bool) -> void: letterbox_enabled = v; _p(&"letterbox_enabled", v)
func set_letterbox_size(v: float) -> void: letterbox_size = v; _p(&"letterbox_size", v)

func _on_blackout() -> void:
	_blackout_active = not _blackout_active
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _blackout_active:
		_vhs_baseline = {
			"enabled": vhs_enabled,
			"scanline": vhs_scanline_intensity,
			"noise": vhs_noise_intensity,
			"tracking": vhs_tracking_distortion,
			"bleed": vhs_color_bleed,
			"vignette": vhs_vignette,
		}
		set_vhs_enabled(true)
		tw.tween_property(self, "vhs_scanline_intensity", 0.15, TWEEN_DUR)
		tw.tween_property(self, "vhs_noise_intensity", 0.2, TWEEN_DUR)
		tw.tween_property(self, "vhs_tracking_distortion", 0.02, TWEEN_DUR)
		tw.tween_property(self, "vhs_color_bleed", 0.02, TWEEN_DUR)
		tw.tween_property(self, "vhs_vignette", 1.0, TWEEN_DUR)
	else:
		tw.tween_property(self, "vhs_scanline_intensity", _vhs_baseline.get("scanline", 0.15), TWEEN_DUR)
		tw.tween_property(self, "vhs_noise_intensity", _vhs_baseline.get("noise", 0.05), TWEEN_DUR)
		tw.tween_property(self, "vhs_tracking_distortion", _vhs_baseline.get("tracking", 0.0015), TWEEN_DUR)
		tw.tween_property(self, "vhs_color_bleed", _vhs_baseline.get("bleed", 0.003), TWEEN_DUR)
		tw.tween_property(self, "vhs_vignette", _vhs_baseline.get("vignette", 0.2), TWEEN_DUR)
		await tw.finished
		set_vhs_enabled(_vhs_baseline.get("enabled", true))

func _on_loaded(value: bool) -> void:
	if not value:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "letterbox_size", 0.0, TWEEN_DUR)

func _on_loading_started() -> void:
	set_letterbox_enabled(true)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "letterbox_size", 0.5, TWEEN_DUR)
	await tw.finished
	SignalBus.prepared_load.emit()   # was: prepared_load.emit()

func apply_preset(preset_name: String) -> void:
	match preset_name:
		"clean_photo_mode":
			set_vhs_enabled(false)
			set_lens_distortion_enabled(false)
			set_ca_enabled(true); set_ca_samples(3); set_ca_strength(0.0015)
			set_grain_intensity(0.02)
			set_vignette_strength(0.2)
		"found_footage_vhs":
			set_vhs_enabled(true)
			set_vhs_scanline_intensity(0.25); set_vhs_noise_intensity(0.12)
			set_vhs_tracking_distortion(0.003); set_vhs_color_bleed(0.006)
			set_ca_samples(3); set_ca_strength(0.006)
			set_letterbox_enabled(true)
		"cinematic_wide_lens":
			set_vhs_enabled(false)
			set_lens_distortion_enabled(true); set_lens_barrel_amount(0.15)
			set_ca_samples(5); set_ca_strength(0.006)
			set_cc_contrast(1.1); set_cc_saturation(0.9)
			set_letterbox_enabled(true); set_vignette_strength(0.4)
