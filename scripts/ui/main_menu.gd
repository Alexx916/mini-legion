extends Control

@onready var currency_label: Label = $CenterContainer/VBoxContainer/CurrencyLabel
@onready var battle_button: Button = $CenterContainer/VBoxContainer/BattleButton
@onready var gacha_button: Button = $CenterContainer/VBoxContainer/GachaButton
@onready var inventory_button: Button = $CenterContainer/VBoxContainer/InventoryButton
@onready var barracks_button: Button = $CenterContainer/VBoxContainer/BarracksButton
@onready var collection_button: Button = $CenterContainer/VBoxContainer/CollectionButton
@onready var switch_save_button: Button = $CenterContainer/VBoxContainer/SwitchSaveButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

func _ready() -> void:
	_update_currency()
	GameState.currency_changed.connect(func(_v): _update_currency())
	battle_button.pressed.connect(_on_battle_pressed)
	gacha_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/gacha/gacha_screen.tscn"))
	inventory_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/inventory/inventory.tscn"))
	barracks_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/barracks/barracks.tscn"))
	collection_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/collection/collection.tscn"))
	switch_save_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/slot_select.tscn"))
	quit_button.pressed.connect(func(): get_tree().quit())

func _update_currency() -> void:
	currency_label.text = "Gold: %d" % GameState.currency

## Skips straight to picking a battle if a one-time override or a default
## army is set, so the player doesn't have to rebuild a squad every time;
## falls back to the Army Builder if neither is available.
func _on_battle_pressed() -> void:
	var units := GameState.consume_battle_army()
	if units.is_empty():
		get_tree().change_scene_to_file("res://scenes/battle/army_builder.tscn")
	else:
		BattleSim.pending_player_units = units
		get_tree().change_scene_to_file("res://scenes/battle/encounter_select.tscn")
