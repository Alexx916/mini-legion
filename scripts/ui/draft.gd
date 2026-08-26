extends Control

@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var sub_label: Label = $MarginContainer/VBoxContainer/SubLabel
@onready var drafted_row: HBoxContainer = $MarginContainer/VBoxContainer/DraftedRow
@onready var card_row: HBoxContainer = $MarginContainer/VBoxContainer/CardRow

const TOTAL_ROUNDS := 5
## Rounds 1-4 offer Common units; the final round offers an Uncommon pick,
## giving every new army exactly one unit with a passive ability.
const ROUND_RARITY := [
	MiniPart.Rarity.COMMON, MiniPart.Rarity.COMMON, MiniPart.Rarity.COMMON, MiniPart.Rarity.COMMON,
	MiniPart.Rarity.UNCOMMON,
]

var round_index: int = 0
var drafted_units: Array[MiniUnit] = []

func _ready() -> void:
	_start_round()

func _start_round() -> void:
	title_label.text = "DRAFT YOUR ARMY -- Round %d/%d" % [round_index + 1, TOTAL_ROUNDS]
	var rarity: MiniPart.Rarity = ROUND_RARITY[round_index]
	sub_label.text = "Pick one %s unit to join your starting army." % MiniPart.rarity_name(rarity)

	for child in card_row.get_children():
		child.queue_free()

	var candidates: Array = GachaSystem.get_unit_types_for_race(GameState.draft_race, rarity).duplicate()
	candidates.shuffle()
	for i in range(min(3, candidates.size())):
		card_row.add_child(_build_card(candidates[i]))

func _build_card(unit_type: Dictionary) -> PanelContainer:
	var unit := GachaSystem.build_unit_from_type(GameState.draft_race, unit_type["name"])

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 300)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var name_label := Label.new()
	name_label.text = unit_type["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", MiniPart.rarity_color(unit_type["rarity"]))
	vbox.add_child(name_label)

	var dmg := "Physical" if unit.get_damage_type() == MiniPart.DamageType.PHYSICAL else "Magical"
	var range_text := "Ranged" if unit.is_ranged() else "Melee"
	var stats_label := Label.new()
	stats_label.text = "Might %d  Prowess %d\nArmor %d  Resist %d\nHP %d  Speed %.0f  Dodge %.0f%%\n[%s, %s]" % [
		unit.get_might(), unit.get_prowess(), unit.get_armor(), unit.get_resistance(),
		unit.get_max_health(), unit.get_speed(), unit.get_dodge_chance(), dmg, range_text
	]
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(stats_label)

	if unit.get_passive_name() != "":
		var passive_label := Label.new()
		passive_label.text = "★ %s\n%s" % [unit.get_passive_name(), unit.get_passive_description()]
		passive_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		passive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		passive_label.modulate = Color(0.8, 0.9, 1.0)
		vbox.add_child(passive_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var pick_button := Button.new()
	pick_button.text = "Pick"
	pick_button.pressed.connect(func(): _on_pick(unit))
	vbox.add_child(pick_button)

	return panel

func _on_pick(unit: MiniUnit) -> void:
	drafted_units.append(unit)

	var chip := Label.new()
	chip.text = unit.unit_name
	chip.add_theme_color_override("font_color", MiniPart.rarity_color(unit.get_rarity()))
	drafted_row.add_child(chip)

	round_index += 1
	if round_index >= TOTAL_ROUNDS:
		_finish()
	else:
		_start_round()

func _finish() -> void:
	GameState.finish_draft(drafted_units)
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
