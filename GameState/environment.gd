extends Node3D

## Applies TimeStates' clock to the sun light and sky shader.
## This script owns no time state of its own — it only reacts to
## TimeStates.time_changed and writes the result to the light/shader.

@export var sun_light: DirectionalLight3D
@export var sky_material: ShaderMaterial

## Sun light fades between these as it rises/sets — purely cosmetic (light
## quality, not sky color, which the shader already handles via sunset_range).
@export var sun_energy_day: float = 1.4
@export var sun_energy_night: float = 0.35

## Kept close to white at midday. The previous version lerped straight from
## night-blue to a saturated rust-yellow across the whole day, which meant
## every lit surface in the level (not just the sky) sat under a strong
## orange-brown light for most of the day/night cycle — that's the "world
## turns brown" symptom. The rust tint now only shows up near the horizon.
@export var sun_color_day: Color = Color(0.97, 0.94, 0.86)
@export var sun_color_horizon: Color = Color(0.9, 0.55, 0.25) # matches sun_color_a in the sky shader
@export var sun_color_night: Color = Color(0.1, 0.15, 0.25)

## Mirrors the sky shader's own sunset_range uniform so the ground lighting's
## color transition lines up with the sky's transition instead of drifting
## out of sync with it.
@export var sunset_range: Vector2 = Vector2(-0.1, 0.3)


func _ready() -> void:
	TimeStates.time_changed.connect(_on_time_changed)
	# Sync immediately on scene load instead of waiting for the next tick.
	_on_time_changed(TimeStates.time_of_day, TimeStates.day_number)


func _on_time_changed(_time_of_day: float, _day_number: int) -> void:
	var angle: float = TimeStates.get_sun_angle()

	if sun_light:
		# Set in GLOBAL space on purpose: if this node is ever instanced
		# under something with its own rotation (a level root, a spawn
		# point, anything), setting local rotation would let that parent
		# transform leak into the light's real-world direction and make
		# the sun's position inconsistent from run to run. Global rotation
		# pins the light — and therefore LIGHT0_DIRECTION in the sky
		# shader — to time_of_day and nothing else.
		sun_light.global_rotation.x = -angle

		var sun_elevation: float = sin(angle)
		var elevation: float = clamp(sun_elevation, 0.0, 1.0)
		sun_light.light_energy = lerp(sun_energy_night, sun_energy_day, elevation)

		# Blend horizon -> day using the same curve the sky shader uses for
		# its own sunset_range, so the ground color and sky color settle
		# into "neutral daylight" together instead of the ground staying
		# tinted long after the sky above it has gone pale.
		var horizon_t: float = smoothstep(sunset_range.x, sunset_range.y, sun_elevation)
		var lit_color: Color = sun_color_horizon.lerp(sun_color_day, horizon_t)
		sun_light.light_color = sun_color_night.lerp(lit_color, elevation)

	# sky_material is intentionally left untouched here: the sky shader
	# animates its clouds off TIME on its own and its color uniforms are
	# static, so there's nothing time-of-day-driven to push into it. Left as
	# an export in case a future pass wants to drive shader uniforms from here.