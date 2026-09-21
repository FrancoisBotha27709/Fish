extends Item
class_name Fish

@export_group("Symbols")
@export var age_symbol_dict : Dictionary[Age, Texture2D] = {}
@export var size_symbol_dict : Dictionary[Size, Texture2D] = {}
@export var freshness_symbol_dict : Dictionary[Freshness, Texture2D] = {}

enum Age {
	BABY,
	ADULT,
	OLD,
	ANCIENT
}

enum Size {
	TINY,
	SMALL,
	NORMAL,
	LARGE,
	HUGE,
	COLOSSAL
}

enum Freshness {
	FRESH,
	ROTTEN,
	STEAK
}

@export var species : FishSpecies

@export_group("Icons")
@export var dead_scene : Texture2D
@export var steak_scene : Texture2D

@export_group("Fish")
@export var weight : float = 1.0
@export var age : Age = Age.ADULT
@export var freshness_level : Freshness = Freshness.FRESH

#region Size
func get_size() -> Size:
	var ratio := weight / species.normal_weight

	if ratio < 0.5:
		return Size.TINY
	if ratio < 0.8:
		return Size.SMALL
	if ratio < 1.2:
		return Size.NORMAL
	if ratio < 2.0:
		return Size.LARGE
	if ratio < 5.0:
		return Size.HUGE
	return Size.COLOSSAL

func get_size_multiplier() -> float:
	match get_size():
		Size.TINY: return 0.7
		Size.SMALL: return 0.9
		Size.NORMAL: return 1.0
		Size.LARGE: return 1.3
		Size.HUGE: return 1.7
		Size.COLOSSAL: return 2.5
	return 1.0

#endregion

#region Age

func get_age_multiplier() -> float:
	match age:
		Age.BABY: return 0.7
		Age.ADULT: return 1.0
		Age.OLD: return 1.3
		Age.ANCIENT: return 2.0
	return 1.0

func get_freshness_level() -> Texture2D:
	match freshness_level:
		Freshness.FRESH: return icon
		Freshness.ROTTEN: return dead_scene
		Freshness.STEAK: return steak_scene
	return null

#endregion

#region Value

func get_value() -> float:
	var price := species.base_price_per_kg * weight

	price *= get_size_multiplier()
	price *= get_age_multiplier()
	price *= species.rarity_multiplier

	return snapped(price, 0.01)

#endregion

func get_size_name() -> String:
	match get_size():
		Size.TINY: return "Tiny"
		Size.SMALL: return "Small"
		Size.NORMAL: return "Normal"
		Size.LARGE: return "Large"
		Size.HUGE: return "Huge"
		Size.COLOSSAL: return "Colossal"
		_: return "Unknown"


func get_age_name() -> String:
	match age:
		Age.BABY: return "Baby"
		Age.ADULT: return "Adult"
		Age.OLD: return "Old"
		Age.ANCIENT: return "Ancient"
		_: return "Unknown"


func get_description() -> String:
	var lines := [
		description,
		"",
		"%s, %s %s" % [get_size_name(), get_age_name(), species.display_name if species else display_name],
		"Weight: %.2f kg" % weight,
		"Value: %d" % get_value(),
	]
	if rarity:
		lines.append("Rarity: %s" % rarity.display_name)
	return "\n".join(lines)

## Rolls fresh weight/age/rarity for this fish instance. Call once per catch.
func randomize_data() -> void:
	_randomize_weight()
	_randomize_age()
	_randomize_rarity()
	_randomize_fresh()

func _randomize_weight() -> void:
	if not species:
		return
	# Sum of two uniforms gives a rough bell curve (more catches near "normal",
	# fewer extreme outliers) instead of a flat random spread.
	var spread := (randf() + randf() - 1.0)  # roughly -1..1, biased toward 0
	var variance := 0.4  # how far a catch can stray from species.normal_weight
	weight = species.normal_weight * (1.0 + spread * variance)
	weight = max(weight, species.normal_weight * 0.1)  # floor so nothing catches at ~0kg


func _randomize_age() -> void:
	var roll := randf()
	if roll < 0.15:
		age = Age.BABY
	elif roll < 0.75:
		age = Age.ADULT
	elif roll < 0.95:
		age = Age.OLD
	else:
		age = Age.ANCIENT


func _randomize_rarity() -> void:
	var extremity := _get_size_extremity()  # 0.0 (normal) .. 1.0 (colossal/tiny)

	var t := randf()
	t = pow(t, 1.0 + extremity * 3.0)  # push roll toward 1.0 when extremity is high
	rarity = UtilityStates.pick_rarity_by_roll(t)


func _randomize_fresh() -> void:
	var roll := randf()
	if roll < 0.33:
		freshness_level = Freshness.FRESH
	elif roll < 0.70:
		freshness_level = Freshness.ROTTEN
	elif roll < 0.90:
		freshness_level = Freshness.STEAK

## Returns 0.0 for Size.NORMAL, up to 1.0 for Size.TINY/COLOSSAL.
func _get_size_extremity() -> float:
	match get_size():
		Size.NORMAL:
			return 0.0
		Size.SMALL, Size.LARGE:
			return 0.35
		Size.TINY, Size.HUGE:
			return 0.7
		Size.COLOSSAL:
			return 1.0
		_:
			return 0.0

#region Symbols

func get_symbols() -> Array[Texture2D]:
	var symbols := super.get_symbols()

	var size_symbol := _get_size_symbol()
	if size_symbol:
		symbols.append(size_symbol)

	var rarity_symbol := _get_rarity_symbol()
	if rarity_symbol:
		symbols.append(rarity_symbol)

	var age_symbol := _get_age_symbol()
	if age_symbol:
		symbols.append(age_symbol)

	var freshness_symbol := _get_freshness_symbol()
	if freshness_symbol:
		symbols.append(freshness_symbol)

	return symbols

func _get_size_symbol() -> Texture2D:
	return size_symbol_dict.get(get_size())


func _get_rarity_symbol() -> Texture2D:
	return rarity.icon

func _get_age_symbol() -> Texture2D:
	return age_symbol_dict.get(age)


func _get_freshness_symbol() -> Texture2D:
	return freshness_symbol_dict.get(freshness_level)

#endregion
