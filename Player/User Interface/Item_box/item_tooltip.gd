extends Control
class_name ItemTooltip

@export var panel : Panel
@export var title_label : RichTextLabel
@export var body_label : RichTextLabel


func config(data : Item) -> void:
	if not title_label or not body_label:
		await self.ready

	if data.rarity:
		panel.self_modulate = data.rarity.accent_color
		title_label.text = "[color=#%s][b]%s[/b][/color]  [i](%s)[/i]" % [
			data.rarity.color.to_html(),
			data.display_name,
			data.rarity.display_name,
		]
	else:
		title_label.text = "[b]%s[/b]" % data.display_name

	body_label.text = data.get_description()