extends Control

@onready var card_row: HBoxContainer = $MarginContainer/VBoxContainer/CardRow

const RACE_GLOW := {
	MiniPart.Race.IRONCLAD: Color.DODGER_BLUE,
	MiniPart.Race.SKARRGOR: Color.CRIMSON,
	MiniPart.Race.WHISPERWOOD: Color.LIME_GREEN,
}

const RACE_BLURB := {
	MiniPart.Race.IRONCLAD: "Disciplined and defensive. Tanky units, healing, and formation buffs.",
	MiniPart.Race.SKARRGOR: "Aggressive and brutal. High Might, armor-piercing, and battle fury.",
	MiniPart.Race.WHISPERWOOD: "Agile and arcane. Ranged casters, dodging, and nature magic.",
}

func _ready() -> void:
	for race in GachaSystem.get_playable_races():
		card_row.add_child(_build_card(race))

func _build_card(race: MiniPart.Race) -> PanelContainer:
	var glow: Color = RACE_GLOW.get(race, Color.WHITE)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 360)

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

	var blurb := Label.new()
	blurb.text = RACE_BLURB.get(race, "")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(blurb)

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var choose_button := Button.new()
	choose_button.text = "Choose %s" % MiniPart.race_name(race)
	choose_button.pressed.connect(func(): _on_choose(race))
	vbox.add_child(choose_button)

	return panel

func _on_choose(race: MiniPart.Race) -> void:
	GameState.draft_race = race
	get_tree().change_scene_to_file("res://scenes/main/draft.tscn")
