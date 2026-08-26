extends Control

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var currency_label: Label = $MarginContainer/VBoxContainer/TopBar/CurrencyLabel
@onready var summary_label: Label = $MarginContainer/VBoxContainer/SummaryLabel
@onready var default_army_label: Label = $MarginContainer/VBoxContainer/DefaultArmyPanel/DefaultArmyBox/DefaultArmyLabel
@onready var manage_army_button: Button = $MarginContainer/VBoxContainer/DefaultArmyPanel/DefaultArmyBox/ManageArmyButton
@onready var roster_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/RosterGrid

const RACE_TINTS := {
	MiniPart.Race.NONE: Color("caa24a"),
	MiniPart.Race.IRONCLAD: Color("6f8fae"),
	MiniPart.Race.SKARRGOR: Color("a5533f"),
	MiniPart.Race.WHISPERWOOD: Color("5f9e6e"),
}

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	manage_army_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/barracks/manage_army.tscn"))
	GameState.roster_changed.connect(_refresh)
	GameState.armies_changed.connect(_refresh_default_army)
	GameState.currency_changed.connect(func(_v): _update_currency())
	_update_currency()
	_refresh()

func _update_currency() -> void:
	currency_label.text = "Gold: %d" % GameState.currency

func _refresh() -> void:
	for child in roster_grid.get_children():
		child.queue_free()

	var total_power := 0
	for unit in GameState.roster:
		total_power += unit.get_power_score()
		roster_grid.add_child(_build_unit_card(unit))

	summary_label.text = "Roster: %d units | Total power: %d" % [GameState.roster.size(), total_power]
	_refresh_default_army()

func _refresh_default_army() -> void:
	var army := GameState.get_default_army()
	if army.is_empty():
		default_army_label.text = "No default army set. Use Manage Army to pick one."
		return

	var units := GameState.resolve_army_units(army)
	var names: Array = []
	for u in units:
		names.append(u.unit_name)
	default_army_label.text = "Default Army (%s, %d/%d units): %s" % [
		MiniPart.race_name(army["race"]), units.size(), army["size"], ", ".join(names)
	]

func _build_unit_card(unit: MiniUnit) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var portrait := ColorRect.new()
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.size_flags_horizontal = SIZE_SHRINK_CENTER
	portrait.color = RACE_TINTS.get(unit.get_race(), Color.GRAY)
	box.add_child(portrait)

	var initial := Label.new()
	initial.text = unit.get_unit_type_name().substr(0, 1).to_upper() if unit.get_unit_type_name() != "" else "?"
	initial.add_theme_font_size_override("font_size", 28)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(initial)

	var name_label := Label.new()
	name_label.text = unit.unit_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", MiniPart.rarity_color(unit.get_rarity()))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(name_label)

	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 14)
	box.add_child(stats_row)

	var col_a := VBoxContainer.new()
	for line in ["Might %d" % unit.get_might(), "Armor %d" % unit.get_armor(), "Speed %.0f" % unit.get_speed()]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 13)
		col_a.add_child(l)
	stats_row.add_child(col_a)

	var col_b := VBoxContainer.new()
	for line in ["Prowess %d" % unit.get_prowess(), "Resist %d" % unit.get_resistance(), "Dodge %.0f%%" % unit.get_dodge_chance()]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 13)
		col_b.add_child(l)
	stats_row.add_child(col_b)

	if unit.get_passive_name() != "":
		var ability_label := Label.new()
		ability_label.text = "★ %s" % unit.get_passive_name()
		ability_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(ability_label)

		var desc_label := Label.new()
		desc_label.text = unit.get_passive_description()
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.modulate = Color(1, 1, 1, 0.75)
		box.add_child(desc_label)
	else:
		var none_label := Label.new()
		none_label.text = "No Ability"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_label.modulate = Color(1, 1, 1, 0.4)
		box.add_child(none_label)

	var sell_button := Button.new()
	sell_button.text = "Sell (+%d)" % unit.get_sell_value()
	sell_button.pressed.connect(func(): GameState.sell_unit(unit))
	box.add_child(sell_button)

	return panel
