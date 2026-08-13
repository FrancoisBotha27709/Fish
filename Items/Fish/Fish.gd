extends Item
class_name Fish

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

@export var species : FishSpecies

@export_group("Fish")
@export var weight : float = 1.0
@export var age : Age = Age.ADULT

#region Size
func get_size() -> Size:
	var ratio := weight / species.normal_weight

	if ratio < 0.5:
		return Size.TINY
	elif ratio < 0.8:
		return Size.SMALL
	elif ratio < 1.2:
		return Size.NORMAL
	elif ratio < 2.0:
		return Size.LARGE
	elif ratio < 5.0:
		return Size.HUGE
	else:
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

#endregion

#region Value

func get_value() -> float:
	var price := species.base_price_per_kg * weight

	price *= get_size_multiplier()
	price *= get_age_multiplier()
	price *= species.rarity_multiplier

	return snapped(price, 0.01)

#endregion

func get_description() -> String:
	return """%s\nWeight: %.2f kg\n
Age: %.1f cm\n
Price/kg: %d/kg""" % [
		description,
		weight,
		age,
		species.base_price_per_kg
	]
