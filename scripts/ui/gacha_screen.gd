extends Control

@onready var currency_label: Label = $MarginContainer/VBoxContainer/TopBar/CurrencyLabel
@onready var line_bar: HBoxContainer = $MarginContainer/VBoxContainer/LineBar
@onready var pack_bar: HBoxContainer = $MarginContainer/VBoxContainer/PackBar
@onready var result_label: RichTextLabel = $MarginContainer/VBoxContainer/ResultScroll/ResultLabel
@onready var pity_label: Label = $MarginContainer/VBoxContainer/PityLabel
@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton

var current_line: String = "neutral"
var _line_group: ButtonGroup

func _ready() -> void:
	_update_currency()
	_update_pity()
	GameState.currency_changed.connect(func(_v): _update_currency())
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))

	_build_line_tabs()
	_build_pack_buttons()

func _update_currency() -> void:
	currency_label.text = "Gold: %d" % GameState.currency

func _update_pity() -> void:
	pity_label.text = "Pity: %d / %d" % [GachaSystem.pull_count_since_epic, GachaSystem.PITY_LIMIT]

func _build_line_tabs() -> void:
	for child in line_bar.get_children():
		child.queue_free()

	_line_group = ButtonGroup.new()
	for line in GachaSystem.get_pack_lines():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = _line_group
		btn.text = GachaSystem.get_pack_line_display_name(line)
		btn.button_pressed = line == current_line
		btn.pressed.connect(func(): _on_select_line(line))
		line_bar.add_child(btn)

func _on_select_line(line: String) -> void:
	current_line = line
	_build_pack_buttons()

func _build_pack_buttons() -> void:
	for child in pack_bar.get_children():
		child.queue_free()

	for pack in GachaSystem.get_packs_for_line(current_line):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(200, 64)
		btn.text = "%s\n%d Gold" % [pack["name"], pack["cost"]]
		btn.pressed.connect(func(): _on_pull(pack["id"]))
		pack_bar.add_child(btn)

func _on_pull(pack_id: String) -> void:
	if not GachaSystem.can_afford_pack(pack_id):
		result_label.text = "Not enough gold for that pack!"
		return
	var results := GachaSystem.pull(pack_id)
	_show_result(pack_id, results)

func _show_result(pack_id: String, results: Array) -> void:
	_update_pity()
	var pack := GachaSystem.get_pack_by_id(pack_id)
	var lines := []
	lines.append("[b]%s results:[/b]" % pack["name"])
	for result in results:
		var part: MiniPart = result["part"]
		var color := MiniPart.rarity_color(part.rarity)
		lines.append("[color=#%s]%s (%s %s)[/color]" % [
			color.to_html(false), part.display_name, MiniPart.race_name(part.race), MiniPart.rarity_name(part.rarity)
		])
	result_label.text = "\n".join(lines)
