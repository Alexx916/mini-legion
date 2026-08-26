extends Control

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var summary_label: Label = $MarginContainer/VBoxContainer/TopBar/SummaryLabel
@onready var ironclad_column: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/RaceColumns/IroncladColumn
@onready var skarrgor_column: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/RaceColumns/SkarrgorColumn
@onready var whisperwood_column: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/RaceColumns/WhisperwoodColumn
@onready var neutral_column: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/RaceColumns/NeutralColumn

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	GameState.collection_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	_clear_column(ironclad_column)
	_clear_column(skarrgor_column)
	_clear_column(whisperwood_column)
	_clear_column(neutral_column)

	var discovered := 0
	var total := 0

	for race in GachaSystem.RACE_UNIT_TYPES.keys():
		var column := _column_for_race(race)
		for unit_type in GachaSystem.RACE_UNIT_TYPES[race]:
			total += 1
			var key := "%d|%s" % [race, unit_type["name"]]
			var count: int = GameState.assembled_log[key]["count"] if GameState.assembled_log.has(key) else 0
			if count > 0:
				discovered += 1
			_add_entry(column, unit_type["name"], unit_type["rarity"], unit_type.get("passive", ""), count)

	for figure in GachaSystem.LEGENDARY_FIGURE_DEFS:
		total += 1
		var key := "%d|%s" % [MiniPart.Race.NONE, figure["name"]]
		var count: int = GameState.assembled_log[key]["count"] if GameState.assembled_log.has(key) else 0
		if count > 0:
			discovered += 1
		_add_entry(neutral_column, figure["name"], MiniPart.Rarity.LEGENDARY, figure["passive"], count)

	summary_label.text = "%d / %d unit types discovered" % [discovered, total]

func _column_for_race(race: MiniPart.Race) -> VBoxContainer:
	match race:
		MiniPart.Race.IRONCLAD: return ironclad_column
		MiniPart.Race.SKARRGOR: return skarrgor_column
		MiniPart.Race.WHISPERWOOD: return whisperwood_column
	return neutral_column

## Column index 0 is always the race header label; everything after it is
## a per-unit-type entry we rebuild on refresh.
func _clear_column(column: VBoxContainer) -> void:
	for i in range(column.get_child_count() - 1, 0, -1):
		column.get_child(i).queue_free()

func _add_entry(column: VBoxContainer, unit_type_name: String, rarity: MiniPart.Rarity, passive_id: String, count: int) -> void:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var discovered := count > 0

	var name_label := Label.new()
	name_label.text = "%s (%s)" % [unit_type_name, MiniPart.rarity_name(rarity)]
	name_label.add_theme_color_override("font_color", MiniPart.rarity_color(rarity) if discovered else Color(0.5, 0.5, 0.5))
	vbox.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "Assembled: %d" % count if discovered else "Not yet assembled"
	count_label.modulate = Color(1, 1, 1, 0.9 if discovered else 0.5)
	vbox.add_child(count_label)

	if passive_id != "" and discovered:
		var passive_label := Label.new()
		passive_label.text = "★ %s: %s" % [GachaSystem.PASSIVES[passive_id]["name"], GachaSystem.PASSIVES[passive_id]["description"]]
		passive_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		passive_label.modulate = Color(0.8, 0.9, 1.0)
		vbox.add_child(passive_label)
	elif passive_id != "":
		var passive_label := Label.new()
		passive_label.text = "★ ??? (assemble one to reveal its passive)"
		passive_label.modulate = Color(0.5, 0.5, 0.5)
		vbox.add_child(passive_label)

	column.add_child(panel)
