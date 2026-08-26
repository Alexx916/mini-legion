extends Control

## Army selection for a specific battle, shown AFTER the player has already
## picked an opponent on Encounter Select (per game design: "army select
## should happen after the battle select"). The squad size is fixed to
## whatever the encounter was generated for; only which units fill it can
## change here. This is a one-time choice for this fight -- it never
## touches the saved default army (use Barracks > Manage Army for that).

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var currency_label: Label = $MarginContainer/VBoxContainer/TopBar/CurrencyLabel
@onready var selection_summary: Label = $MarginContainer/VBoxContainer/SelectionSummary
@onready var roster_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/RosterGrid
@onready var watch_button: Button = $MarginContainer/VBoxContainer/ActionBar/WatchButton
@onready var sim_button: Button = $MarginContainer/VBoxContainer/ActionBar/SimButton

var army_size: int = 3
var selected_ids: Array[String] = []

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/battle/encounter_select.tscn"))
	watch_button.pressed.connect(_on_watch)
	sim_button.pressed.connect(_on_sim)
	GameState.currency_changed.connect(func(_v): _update_currency())

	army_size = BattleSim.pending_enemy_units.size()
	_seed_from_default_army()
	_update_currency()
	_refresh_roster()

## Seeds from a pending one-time override (Manage Army's "Use Once"), if
## any, otherwise the saved default army. Either way this is just a
## starting point -- the player can still freely adjust before fighting.
func _seed_from_default_army() -> void:
	for u in GameState.consume_battle_army():
		if selected_ids.size() < army_size:
			selected_ids.append(u.unit_id)

func _update_currency() -> void:
	currency_label.text = "Gold: %d" % GameState.currency

func _locked_race() -> int:
	for id in selected_ids:
		var unit := _find_unit(id)
		if unit and unit.get_race() != MiniPart.Race.NONE:
			return unit.get_race()
	return -1

func _find_unit(id: String) -> MiniUnit:
	for u in GameState.roster:
		if u.unit_id == id:
			return u
	return null

func _refresh_roster() -> void:
	for child in roster_grid.get_children():
		child.queue_free()

	var lock := _locked_race()
	for unit in GameState.roster:
		var eligible := lock == -1 or unit.get_race() == lock or unit.get_race() == MiniPart.Race.NONE
		var selected := selected_ids.has(unit.unit_id)
		roster_grid.add_child(_build_unit_card(unit, eligible, selected))

	selection_summary.text = "Selected: %d/%d%s" % [
		selected_ids.size(), army_size,
		"  (%s)" % MiniPart.race_name(lock) if lock != -1 else ""
	]
	var ready := selected_ids.size() == army_size
	watch_button.disabled = not ready
	sim_button.disabled = not ready

func _build_unit_card(unit: MiniUnit, eligible: bool, selected: bool) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = selected
	btn.custom_minimum_size = Vector2(200, 90)
	btn.text = "%s\n%s (%s)\nPower %d" % [
		unit.unit_name, MiniPart.race_name(unit.get_race()), MiniPart.rarity_name(unit.get_rarity()), unit.get_power_score()
	]
	btn.add_theme_color_override("font_color", MiniPart.rarity_color(unit.get_rarity()))
	if not eligible and not selected:
		btn.disabled = true
		btn.modulate = Color(1, 1, 1, 0.4)
	btn.pressed.connect(func(): _on_toggle_unit(unit))
	return btn

func _on_toggle_unit(unit: MiniUnit) -> void:
	if selected_ids.has(unit.unit_id):
		selected_ids.erase(unit.unit_id)
	elif selected_ids.size() < army_size:
		selected_ids.append(unit.unit_id)
	_refresh_roster()

func _selected_units() -> Array[MiniUnit]:
	var units: Array[MiniUnit] = []
	for id in selected_ids:
		var u := _find_unit(id)
		if u:
			units.append(u)
	return units

func _on_watch() -> void:
	BattleSim.pending_player_units = _selected_units()
	get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")

func _on_sim() -> void:
	var result := BattleSim.simulate(_selected_units(), BattleSim.pending_enemy_units)
	var reward := BattleSim.compute_reward(result, BattleSim.squad_power(BattleSim.pending_enemy_units))
	GameState.add_currency(reward)
	var outcome := "VICTORY" if result["winning_team"] == 0 else "DEFEAT"
	_show_sim_result(outcome, result, reward)

func _show_sim_result(outcome: String, result: Dictionary, reward: int) -> void:
	var popup := AcceptDialog.new()
	popup.title = outcome
	popup.dialog_text = "%s! Survivors: %d vs %d\n+%d Gold" % [outcome, result["player_survivors"], result["enemy_survivors"], reward]
	add_child(popup)
	popup.confirmed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	popup.canceled.connect(popup.queue_free)
	popup.popup_centered()
