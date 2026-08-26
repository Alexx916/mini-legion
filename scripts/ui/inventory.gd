extends Control

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var currency_label: Label = $MarginContainer/VBoxContainer/TopBar/CurrencyLabel
@onready var unit_grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/UnitGrid

const SLOT_ORDER := [MiniPart.Slot.HEAD, MiniPart.Slot.TORSO, MiniPart.Slot.LEGS, MiniPart.Slot.WEAPON]

func _ready() -> void:
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	GameState.inventory_changed.connect(_refresh)
	GameState.currency_changed.connect(func(_v): _update_currency())
	_update_currency()
	_refresh()

func _update_currency() -> void:
	currency_label.text = "Gold: %d" % GameState.currency

func _refresh() -> void:
	for child in unit_grid.get_children():
		child.queue_free()

	var groups := GameState.get_buildable_sets()
	if groups.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No parts yet -- pull the Gacha Machine to collect some."
		empty_label.modulate = Color(1, 1, 1, 0.5)
		unit_grid.add_child(empty_label)
		return

	for group in groups:
		unit_grid.add_child(_build_card(group))

func _build_card(group: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var buildable: int = group["buildable_count"]
	var is_buildable := buildable > 0
	var parts: Dictionary = group["parts"]

	var preview := MiniUnit.new()
	preview.head = parts.get(MiniPart.Slot.HEAD)
	preview.torso = parts.get(MiniPart.Slot.TORSO)
	preview.legs = parts.get(MiniPart.Slot.LEGS)
	preview.weapon = parts.get(MiniPart.Slot.WEAPON)

	var title := Label.new()
	title.text = "%s\n%s" % [group["unit_type_name"], MiniPart.race_name(group["race"])]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", MiniPart.rarity_color(group["rarity"]))
	box.add_child(title)

	if is_buildable:
		var dmg := "PHY" if preview.get_damage_type() == MiniPart.DamageType.PHYSICAL else "MAG"
		var stats_row := HBoxContainer.new()
		stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
		stats_row.add_theme_constant_override("separation", 14)
		box.add_child(stats_row)

		var col_a := VBoxContainer.new()
		for line in ["Might %d" % preview.get_might(), "Armor %d" % preview.get_armor(), "Speed %.0f" % preview.get_speed()]:
			var l := Label.new()
			l.text = line
			l.add_theme_font_size_override("font_size", 13)
			col_a.add_child(l)
		stats_row.add_child(col_a)

		var col_b := VBoxContainer.new()
		for line in ["Prowess %d" % preview.get_prowess(), "Resist %d" % preview.get_resistance(), "Dodge %.0f%%" % preview.get_dodge_chance()]:
			var l := Label.new()
			l.text = line
			l.add_theme_font_size_override("font_size", 13)
			col_b.add_child(l)
		stats_row.add_child(col_b)

		var power_label := Label.new()
		power_label.text = "[%s] Power %d" % [dmg, preview.get_power_score()]
		power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		power_label.add_theme_font_size_override("font_size", 12)
		box.add_child(power_label)
	else:
		var missing: Array = []
		for slot in SLOT_ORDER:
			if not parts.has(slot):
				missing.append(MiniPart.slot_name(slot))
		var missing_label := Label.new()
		missing_label.text = "Missing: %s" % ", ".join(missing)
		missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing_label.add_theme_font_size_override("font_size", 12)
		missing_label.modulate = Color(1, 0.6, 0.5)
		box.add_child(missing_label)

	var pieces_label := Label.new()
	var piece_bits: Array = []
	for slot in SLOT_ORDER:
		var count: int = group["counts"].get(slot, 0)
		piece_bits.append("%s x%d" % [MiniPart.slot_name(slot).substr(0, 1), count])
	pieces_label.text = ", ".join(piece_bits)
	pieces_label.add_theme_font_size_override("font_size", 12)
	pieces_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pieces_label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(pieces_label)

	if group["passive_name"] != "":
		var passive_label := Label.new()
		passive_label.text = "★ %s" % group["passive_name"]
		passive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		passive_label.add_theme_font_size_override("font_size", 12)
		passive_label.modulate = Color(0.8, 0.9, 1.0)
		box.add_child(passive_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(footer)

	var count_label := Label.new()
	count_label.text = "Buildable: %d" % buildable
	footer.add_child(count_label)

	var assemble_button := Button.new()
	assemble_button.text = "Assemble"
	assemble_button.disabled = not is_buildable
	assemble_button.pressed.connect(func(): _on_assemble(group))
	box.add_child(assemble_button)

	return panel

func _on_assemble(group: Dictionary) -> void:
	GameState.assemble_from_group(group)
