extends Node2D
class_name UnitVisual

var team: int = 0
var max_health: float = 1.0
var current_health: float = 1.0

const RADIUS := 14.0

func _draw() -> void:
	var color := Color(0.3, 0.55, 1.0) if team == 0 else Color(1.0, 0.35, 0.3)
	if current_health <= 0.0:
		color = color.darkened(0.7)
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 24, Color.BLACK, 1.5)

	# Health bar
	var bar_width := 32.0
	var bar_height := 5.0
	var bar_pos := Vector2(-bar_width / 2.0, -RADIUS - 12.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0, 0, 0, 0.6))
	var pct: float = clamp(current_health / max_health, 0.0, 1.0)
	var fill_color := Color(0.3, 0.9, 0.3) if pct > 0.3 else Color(0.9, 0.3, 0.2)
	draw_rect(Rect2(bar_pos, Vector2(bar_width * pct, bar_height)), fill_color)

func set_health(hp: float) -> void:
	current_health = hp
	queue_redraw()
