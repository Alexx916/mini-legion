extends Node2D

@onready var arena_container: Node2D = $ArenaContainer
@onready var speed_button: Button = $HUD/TopBar/SpeedButton
@onready var skip_button: Button = $HUD/TopBar/SkipButton
@onready var player_portrait_row: HBoxContainer = $HUD/PlayerPortraits
@onready var enemy_portrait_row: HBoxContainer = $HUD/EnemyPortraits
@onready var result_overlay: PanelContainer = $HUD/ResultOverlay
@onready var result_label: Label = $HUD/ResultOverlay/ResultVBox/ResultLabel
@onready var reward_label: Label = $HUD/ResultOverlay/ResultVBox/RewardLabel
@onready var continue_button: Button = $HUD/ResultOverlay/ResultVBox/ContinueButton

var battle_result: Dictionary
var visuals: Array[UnitVisual] = []
var portraits: Array[UnitPortrait] = []
var frame_index: int = 0
var frame_timer: float = 0.0
var speed_multiplier: float = 1.0
const SPEED_STEPS := [1.0, 2.0, 4.0]
var speed_step_index := 0

func _ready() -> void:
	continue_button.pressed.connect(_on_continue)
	speed_button.pressed.connect(_on_speed_toggle)
	skip_button.pressed.connect(_show_result_now)

	var player_units := BattleSim.pending_player_units
	var enemy_units := BattleSim.pending_enemy_units
	battle_result = BattleSim.simulate(player_units, enemy_units)

	_spawn_visuals(player_units, enemy_units)

func _spawn_visuals(player_units: Array[MiniUnit], enemy_units: Array[MiniUnit]) -> void:
	for i in range(player_units.size() + enemy_units.size()):
		var v := UnitVisual.new()
		v.team = 0 if i < player_units.size() else 1
		arena_container.add_child(v)
		visuals.append(v)

	for unit in player_units:
		var p := UnitPortrait.new()
		player_portrait_row.add_child(p)
		p.setup(unit)
		portraits.append(p)
	for unit in enemy_units:
		var p := UnitPortrait.new()
		enemy_portrait_row.add_child(p)
		p.setup(unit)
		portraits.append(p)

	_apply_frame(0)

func _process(delta: float) -> void:
	if result_overlay.visible:
		return
	if battle_result["frames"].is_empty():
		_show_result_now()
		return

	frame_timer += delta * speed_multiplier
	var frame_dt: float = 0.1
	while frame_timer >= frame_dt and frame_index < battle_result["frames"].size() - 1:
		frame_timer -= frame_dt
		frame_index += 1
		_apply_frame(frame_index)

	if frame_index >= battle_result["frames"].size() - 1:
		_show_result_now()

func _apply_frame(index: int) -> void:
	var frame: Dictionary = battle_result["frames"][index]
	var units: Dictionary = frame["units"]
	for i in units.keys():
		if i >= visuals.size():
			continue
		var data: Dictionary = units[i]
		visuals[i].position = data["pos"]
		if visuals[i].max_health <= 1.0:
			visuals[i].max_health = max(data["hp"], 1.0)
		visuals[i].set_health(data["hp"])

		if i < portraits.size():
			portraits[i].update_state(data["hp"], data["max_hp"], data["ability_cooldown"], data["ability_cooldown_max"])

func _on_speed_toggle() -> void:
	speed_step_index = (speed_step_index + 1) % SPEED_STEPS.size()
	speed_multiplier = SPEED_STEPS[speed_step_index]
	speed_button.text = "Speed: %dx" % int(speed_multiplier)

func _show_result_now() -> void:
	if result_overlay.visible:
		return
	if not battle_result["frames"].is_empty():
		_apply_frame(battle_result["frames"].size() - 1)

	var enemy_power := BattleSim.squad_power(BattleSim.pending_enemy_units)
	var reward := BattleSim.compute_reward(battle_result, enemy_power)
	GameState.add_currency(reward)

	result_label.text = "VICTORY" if battle_result["winning_team"] == 0 else "DEFEAT"
	reward_label.text = "+%d Gold" % reward
	result_overlay.visible = true

func _on_continue() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
