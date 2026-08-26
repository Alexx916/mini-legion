extends VBoxContainer
class_name UnitPortrait

## A small HUD widget: a square portrait (tinted by race, no real art yet)
## with a green health bar and a white special-ability cooldown bar beneath
## it. Greys out entirely once the unit dies.

const SIZE := 48.0

const RACE_TINTS := {
	MiniPart.Race.NONE: Color("caa24a"),
	MiniPart.Race.IRONCLAD: Color("6f8fae"),
	MiniPart.Race.SKARRGOR: Color("a5533f"),
	MiniPart.Race.WHISPERWOOD: Color("5f9e6e"),
}

var _portrait: ColorRect
var _health_bar: ProgressBar
var _ability_bar: ProgressBar

func setup(unit: MiniUnit) -> void:
	add_theme_constant_override("separation", 2)

	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(SIZE, SIZE)
	_portrait.color = RACE_TINTS.get(unit.get_race(), Color.GRAY)
	add_child(_portrait)

	var initial := Label.new()
	initial.text = unit.get_unit_type_name().substr(0, 1).to_upper() if unit.get_unit_type_name() != "" else "?"
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.add_child(initial)

	_health_bar = _make_bar(Color(0.25, 0.85, 0.3))
	add_child(_health_bar)

	_ability_bar = _make_bar(Color.WHITE)
	add_child(_ability_bar)

func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(SIZE, 5)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("background", bg)
	return bar

func update_state(hp: float, max_hp: float, ability_cooldown: float, ability_cooldown_max: float) -> void:
	_health_bar.max_value = max(max_hp, 1.0)
	_health_bar.value = hp

	if ability_cooldown_max > 0.0:
		_ability_bar.max_value = ability_cooldown_max
		_ability_bar.value = ability_cooldown_max - ability_cooldown
		_ability_bar.visible = true
	else:
		_ability_bar.visible = false

	modulate = Color(0.35, 0.35, 0.35, 1.0) if hp <= 0.0 else Color.WHITE
