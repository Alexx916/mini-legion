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
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	reroll_button.pressed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	for child in card_row.get_children():
		child.queue_free()

	## Army selection now happens AFTER picking a battle, so the encounter
	## size is drawn from the default army rather than an already-built one.
	var army_size: int = GameState.get_default_army().get("size", 3)
	options = BattleSim.generate_encounter_options(army_size)
	for option in options:
		card_row.add_child(_build_card(option))

## The whole card is a Button so clicking anywhere on it selects that battle.
func _build_card(option: Dictionary) -> Button:
	var race: MiniPart.Race = option["race"]
	var glow: Color = RACE_GLOW.get(race, Color.WHITE)

	var card := Button.new()
	card.custom_minimum_size = Vector2(240, 190)
	card.pressed.connect(func(): _on_select(option))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.17)
	style.border_color = glow
	style.set_border_width_all(4)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(glow.r, glow.g, glow.b, 0.6)
	style.shadow_size = 12
	card.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.19, 0.19, 0.23)
	card.add_theme_stylebox_override("hover", hover_style)
	card.add_theme_stylebox_override("pressed", hover_style)
	card.add_theme_stylebox_override("focus", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	card.add_child(vbox)

	var logo := ColorRect.new()
	logo.custom_minimum_size = Vector2(52, 52)
	logo.size_flags_horizontal = SIZE_SHRINK_CENTER
	logo.color = glow
	vbox.add_child(logo)

	var initial := Label.new()
	initial.text = MiniPart.race_name(race).substr(0, 1)
	initial.add_theme_font_size_override("font_size", 28)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.add_child(initial)

	var name_label := Label.new()
	name_label.text = MiniPart.race_name(race)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", glow)
	vbox.add_child(name_label)

	var tier_label := Label.new()
	tier_label.text = "Threat: %s" % MiniPart.rarity_name(option["max_rarity"])
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tier_label)

	var power_label := Label.new()
	power_label.text = "Enemy Power: %d" % option["enemy_power"]
	power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(power_label)

	var reward_label := Label.new()
	reward_label.text = "Est. Reward: %d Gold" % option["reward_estimate"]
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_label.add_theme_font_size_override("font_size", 12)
	reward_label.modulate = Color(1.0, 0.85, 0.4)
	vbox.add_child(reward_label)

	return card

func _on_select(option: Dictionary) -> void:
	BattleSim.pending_enemy_units = option["enemy_units"]
	get_tree().change_scene_to_file("res://scenes/battle/battle_army_select.tscn")
