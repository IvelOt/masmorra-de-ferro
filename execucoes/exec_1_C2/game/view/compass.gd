class_name Compass
extends Control
## Bússola de faixa estilo Daggerfall (80x32). A faixa tem 320 px para 4096 BAM;
## a direção d aparece em x = 40 + (((angle - d + 2048) & 4095) - 2048) * 320 / 4096.
## Norte = +Z da simulação (1024), Leste = +X (0).

const BG: Color = Color(0.12, 0.11, 0.10)
const EDGE: Color = Color(0.45, 0.40, 0.33)
const TEXT: Color = Color(0.92, 0.86, 0.70)
const MARK: Color = Color(0.70, 0.64, 0.52)
const POINTER: Color = Color(0.85, 0.10, 0.10)
const LETTERS: Array[String] = ["L", "N", "O", "S"]

var angle: int = 0


func _ready() -> void:
	size = Vector2(80, 32)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_angle(a: int) -> void:
	if a != angle:
		angle = a
		queue_redraw()


static func strip_x(a: int, d: int) -> int:
	return 40 + ((((a - d + 2048) & 4095) - 2048) * 320) / 4096


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var font: Font = get_theme_default_font()
	for k in range(8):
		var d: int = k * 512
		var x: int = strip_x(angle, d)
		if x < -8 or x > 88:
			continue
		if k % 2 == 0:
			var s: String = LETTERS[k / 2]
			var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string_outline(font, Vector2(x - w * 0.5, 26), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 1, Color(0, 0, 0))
			draw_string(font, Vector2(x - w * 0.5, 26), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT)
			draw_line(Vector2(x, 6), Vector2(x, 10), MARK, 1.0)
		else:
			draw_line(Vector2(x, 6), Vector2(x, 10), MARK, 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(36, 1), Vector2(44, 1), Vector2(40, 6)]), POINTER)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1, 1)), EDGE, false, 1.0)
