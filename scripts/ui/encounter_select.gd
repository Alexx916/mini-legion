extends Control

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var reroll_button: Button = $MarginContainer/VBoxContainer/TopBar/RerollButton
@onready var card_row: HBoxContainer = $MarginContainer/VBoxContainer/CardRow

const RACE_GLOW := {
	MiniPart.Race.IRONCLAD: Color.DODGER_BLUE,
	MiniPart.Race.SKARRGOR: Color.CRIMSON,
	MiniPart.Race.WHISPERWOOD: Color.LIME_GREEN,
}

var options: Array = []

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/battle/army_builder.tscn"))
	reroll_button.pressed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	for child in card_row.get_children():
		child.queue_free()

	var army_size := BattleSim.pending_player_units.size()
	options = BattleSim.generate_encounter_options(army_size)
	for option in options:
		card_row.add_child(_build_card(option))

func _build_card(option: Dictionary) -> PanelContainer:
	var race: MiniPart.Race = option["race"]
	var glow: Color = RACE_GLOW.get(race, Color.WHITE)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 340)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.17)
	style.border_color = glow
	style.set_border_width_all(4)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(glow.r, glow.g, glow.b, 0.6)
	style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var logo := ColorRect.new()
	logo.custom_minimum_size = Vector2(96, 96)
	logo.size_flags_horizontal = SIZE_SHRINK_CENTER
	logo.color = glow
	vbox.add_child(logo)

	var initial := Label.new()
	initial.text = MiniPart.race_name(race).substr(0, 1)
	initial.add_theme_font_size_override("font_size", 48)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.add_child(initial)

	var name_label := Label.new()
	name_label.text = MiniPart.race_name(race)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", glow)
	vbox.add_child(name_label)

	var tier_label := Label.new()
	tier_label.text = "Threat: %s" % MiniPart.rarity_name(option["max_rarity"])
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tier_label)

	var power_label := Label.new()
	power_label.text = "Enemy Power: %d" % option["enemy_power"]
	power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(power_label)

	var reward_label := Label.new()
	reward_label.text = "Est. Reward: %d Gold" % option["reward_estimate"]
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_label.modulate = Color(1.0, 0.85, 0.4)
	vbox.add_child(reward_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var watch_button := Button.new()
	watch_button.text = "Watch Battle"
	watch_button.pressed.connect(func(): _on_watch(option))
	vbox.add_child(watch_button)

	var sim_button := Button.new()
	sim_button.text = "Instant Sim"
	sim_button.pressed.connect(func(): _on_sim(option))
	vbox.add_child(sim_button)

	return panel

func _on_watch(option: Dictionary) -> void:
	BattleSim.pending_enemy_units = option["enemy_units"]
	get_tree().change_scene_to_file("res://scenes/battle/battle_arena.tscn")

func _on_sim(option: Dictionary) -> void:
	var result := BattleSim.simulate(BattleSim.pending_player_units, option["enemy_units"])
	var reward := BattleSim.compute_reward(result, option["enemy_power"])
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
