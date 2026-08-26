extends Control

@onready var slot_list: VBoxContainer = $CenterContainer/VBoxContainer/SlotList

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	for child in slot_list.get_children():
		child.queue_free()
	for i in range(GameState.SLOT_COUNT):
		slot_list.add_child(_build_slot_row(i))

func _build_slot_row(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var summary := GameState.get_slot_summary(index)
	var info := Label.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	if summary.is_empty():
		info.text = "Slot %d -- Empty" % (index + 1)
		info.modulate = Color(1, 1, 1, 0.6)
	else:
		info.text = "Slot %d -- %s, %d units, %d Gold" % [index + 1, summary["race_name"], summary["unit_count"], summary["currency"]]
	row.add_child(info)

	if summary.is_empty():
		var new_game_button := Button.new()
		new_game_button.text = "New Game"
		new_game_button.pressed.connect(func(): _on_new_game(index))
		row.add_child(new_game_button)
	else:
		var continue_button := Button.new()
		continue_button.text = "Continue"
		continue_button.pressed.connect(func(): _on_continue(index))
		row.add_child(continue_button)

		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(func(): _on_delete(index))
		row.add_child(delete_button)

	return panel

func _on_continue(index: int) -> void:
	GameState.load_slot(index)
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _on_new_game(index: int) -> void:
	GameState.start_new_game(index)
	get_tree().change_scene_to_file("res://scenes/main/faction_select.tscn")

func _on_delete(index: int) -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Delete Slot %d? This cannot be undone." % (index + 1)
	add_child(confirm)
	confirm.confirmed.connect(func():
		GameState.delete_slot(index)
		_refresh()
	)
	confirm.canceled.connect(confirm.queue_free)
	confirm.confirmed.connect(confirm.queue_free)
	confirm.popup_centered()
