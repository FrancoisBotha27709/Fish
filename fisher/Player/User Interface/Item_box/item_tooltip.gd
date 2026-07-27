extends Control
class_name ItemTooltip

@export var panel : Panel
@export var label : RichTextLabel

func config(data : Item, for_text):
	if not label:
		await self.ready
		
	panel.self_modulate = data.rarity.accent_color
	label.text = for_text
