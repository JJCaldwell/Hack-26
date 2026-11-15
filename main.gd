extends Node2D

const PLAYER_SCRIPT = preload("res://player.gd")
const QUESTIONS: Array[Dictionary] = [
	{
		"prompt": "What does the medical prefix cardio- refer to?",
		"answers": ["The heart", "The skin", "The bones"],
		"correct": 0,
		"explain": "Correct! Cardio- refers to the heart."
	},
	{
		"prompt": "What does dyspnea mean?",
		"answers": ["Joint pain", "Difficulty breathing", "A fast heartbeat"],
		"correct": 1,
		"explain": "Correct! Dyspnea means difficult or labored breathing."
	}
]

var player: CharacterBody2D
var ui_layer: CanvasLayer
var hud_label: Label
var popup: PanelContainer
var prompt_label: Label
var feedback_label: Label
var answers_box: VBoxContainer
var quiz_open := false
var current_question := 0
var questions_answered := 0


func _ready() -> void:
	_register_controls()
	queue_redraw()
	_create_room()
	_create_hud()
	_create_question_popup()
	_create_checkpoint(340.0, 0)
	_create_checkpoint(880.0, 1)
	_create_exit(1450.0)


func _draw() -> void:
	# Side-view hospital room backdrop, drawn behind the playable platforms.
	var outline := Color("303954")
	draw_rect(Rect2(-1400, -900, 4200, 1800), Color("e5eafa"))
	# Ceiling and tiled clinical walls.
	draw_rect(Rect2(-1400, -360, 4200, 205), Color("c4cee3"))
	draw_rect(Rect2(-1400, -360, 4200, 22), Color("f6f8ff"))
	draw_line(Vector2(-1400, -155), Vector2(2800, -155), outline, 5.0)
	for x in range(-1300, 2700, 180):
		draw_rect(Rect2(x, -315, 150, 120), Color("e8edf8"))
		draw_rect(Rect2(x + 8, -307, 134, 104), Color("d9e1f1"))
		draw_line(Vector2(x + 8, -203), Vector2(x + 142, -203), Color("aab6d0"), 3.0)
	# Wall panels and lower protective wall rail.
	draw_rect(Rect2(-1400, -150, 4200, 600), Color("e2e8f5"))
	for x in range(-1300, 2700, 260):
		draw_rect(Rect2(x, -135, 244, 470), Color("e8edf7"))
		draw_line(Vector2(x + 244, -135), Vector2(x + 244, 334), Color("b8c4da"), 3.0)
	draw_rect(Rect2(-1400, 405, 4200, 24), Color("aebbd2"))
	draw_rect(Rect2(-1400, 429, 4200, 210), Color("cbd5e8"))
	draw_line(Vector2(-1400, 429), Vector2(2800, 429), Color("f7f9ff"), 6.0)
	for x in range(-1300, 2700, 120):
		draw_line(Vector2(x, 430), Vector2(x, 638), Color("b6c2d8"), 2.0)
	# Ceiling surgical lamps and wall fixtures spaced along the scrolling room.
	for x in [-760, -80, 620, 1320, 2020]:
		_draw_surgical_light(float(x), outline)
	_draw_window(-1080, 26, 245, 195, outline)
	_draw_cabinet(-790, 215, 200, 183, outline)
	_draw_monitor(-525, 85, 174, 125, outline)
	_draw_bed(-205, 328, outline)
	_draw_monitor(240, 95, 196, 145, outline)
	_draw_iv_pole(492, 88, outline)
	_draw_cabinet(740, 215, 235, 183, outline)
	_draw_monitor(1010, 100, 200, 138, outline)
	_draw_window(1395, 26, 245, 195, outline)
	_draw_iv_pole(1720, 82, outline)
	_draw_cabinet(1855, 215, 220, 183, outline)
	# A few wall signs and floor reflections keep the space readable in motion.
	_draw_medical_cross(-405, -55, 23, Color("42aeca"), outline)
	_draw_medical_cross(1280, -55, 23, Color("42aeca"), outline)
	for x in range(-1250, 2600, 170):
		draw_rect(Rect2(x, 617, 72, 5), Color(0.40, 0.50, 0.67, 0.22))


func _draw_surgical_light(x: float, outline: Color) -> void:
	draw_line(Vector2(x, -155), Vector2(x, -32), outline, 6.0)
	draw_rect(Rect2(x - 8, -40, 16, 22), Color("8794af"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 88, -18), Vector2(x + 88, -18),
		Vector2(x + 64, 34), Vector2(x - 64, 34)
	]), Color("77849f"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 78, -13), Vector2(x + 78, -13),
		Vector2(x + 56, 25), Vector2(x - 56, 25)
	]), Color("f6f8ff"))
	draw_line(Vector2(x - 62, 11), Vector2(x + 62, 11), Color("aab6ce"), 5.0)
	for lamp_x in range(-45, 46, 30):
		draw_circle(Vector2(x + lamp_x, 17), 7, Color("bdeef5"))
	draw_line(Vector2(x - 88, -18), Vector2(x + 88, -18), outline, 5.0)


func _draw_window(x: float, y: float, w: float, h: float, outline: Color) -> void:
	draw_rect(Rect2(x - 8, y - 8, w + 16, h + 16), outline)
	draw_rect(Rect2(x, y, w, h), Color("8a9ab8"))
	draw_rect(Rect2(x + 7, y + 7, w - 14, h - 14), Color("c9eaf3"))
	draw_rect(Rect2(x + 12, y + 12, w - 24, h / 2 - 12), Color("e9f8ff"))
	draw_line(Vector2(x + w / 2, y + 4), Vector2(x + w / 2, y + h - 4), outline, 5.0)
	draw_line(Vector2(x + 4, y + h / 2), Vector2(x + w - 4, y + h / 2), outline, 5.0)
	# Simple privacy curtain folds at the side of the window.
	for fold in range(0, 36, 9):
		draw_line(Vector2(x - 22 + fold, y - 2), Vector2(x - 22 + fold, y + h + 4), Color("aebbd0"), 4.0)


func _draw_cabinet(x: float, y: float, w: float, h: float, outline: Color) -> void:
	draw_rect(Rect2(x - 6, y - 6, w + 12, h + 12), outline)
	draw_rect(Rect2(x, y, w, h), Color("f5f7fd"))
	draw_rect(Rect2(x, y, w, 18), Color("9ba8c1"))
	var drawer_h := (h - 24) / 3.0
	for i in range(3):
		var drawer_y := y + 22 + i * drawer_h
		draw_rect(Rect2(x + 8, drawer_y, w - 16, drawer_h - 5), Color("d8e0ef"))
		draw_line(Vector2(x + 18, drawer_y + 8), Vector2(x + w - 18, drawer_y + 8), Color("b4bfd3"), 2.0)
		draw_rect(Rect2(x + w / 2 - 12, drawer_y + 17, 24, 5), outline)
	draw_rect(Rect2(x - 10, y - 12, w + 20, 8), Color("7f8ca7"))
	for leg_x in [x + 18, x + w - 24]:
		draw_rect(Rect2(leg_x, y + h, 7, 24), outline)


func _draw_monitor(x: float, y: float, w: float, h: float, outline: Color) -> void:
	draw_rect(Rect2(x - 7, y - 7, w + 14, h + 14), outline)
	draw_rect(Rect2(x, y, w, h), Color("252e47"))
	draw_rect(Rect2(x + 8, y + 8, w - 16, h - 24), Color("102b43"))
	var screen_color := Color("35d8e7")
	draw_line(Vector2(x + 18, y + h * 0.55), Vector2(x + w * 0.30, y + h * 0.55), screen_color, 3.0)
	draw_line(Vector2(x + w * 0.30, y + h * 0.55), Vector2(x + w * 0.38, y + h * 0.35), screen_color, 3.0)
	draw_line(Vector2(x + w * 0.38, y + h * 0.35), Vector2(x + w * 0.46, y + h * 0.72), screen_color, 3.0)
	draw_line(Vector2(x + w * 0.46, y + h * 0.72), Vector2(x + w * 0.55, y + h * 0.52), screen_color, 3.0)
	draw_line(Vector2(x + w * 0.55, y + h * 0.52), Vector2(x + w - 18, y + h * 0.52), screen_color, 3.0)
	draw_rect(Rect2(x + 15, y + h - 12, 11, 4), Color("63e9d7"))
	draw_rect(Rect2(x + 34, y + h - 12, 11, 4), Color("63e9d7"))
	draw_line(Vector2(x + w / 2, y + h + 7), Vector2(x + w / 2, y + h + 44), outline, 7.0)
	draw_line(Vector2(x + w / 2 - 28, y + h + 44), Vector2(x + w / 2 + 28, y + h + 44), outline, 7.0)


func _draw_bed(x: float, y: float, outline: Color) -> void:
	draw_rect(Rect2(x, y, 285, 18), outline)
	draw_rect(Rect2(x + 8, y + 5, 269, 10), Color("f9fbff"))
	draw_rect(Rect2(x + 12, y - 24, 58, 25), outline)
	draw_rect(Rect2(x + 17, y - 19, 48, 16), Color("f8faff"))
	draw_rect(Rect2(x + 72, y + 18, 200, 20), Color("91a0ba"))
	draw_rect(Rect2(x + 84, y + 38, 10, 54), outline)
	draw_rect(Rect2(x + 252, y + 38, 10, 54), outline)
	draw_rect(Rect2(x - 12, y - 35, 10, 128), outline)
	draw_rect(Rect2(x - 25, y - 38, 28, 7), Color("707e99"))
	draw_rect(Rect2(x - 32, y + 90, 320, 10), outline)
	# Folded blanket in the same cool blue-gray range as the reference.
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 115, y + 3), Vector2(x + 268, y + 3),
		Vector2(x + 250, y + 20), Vector2(x + 112, y + 20)
	]), Color("7f91b1"))


func _draw_iv_pole(x: float, y: float, outline: Color) -> void:
	draw_line(Vector2(x, y), Vector2(x, 428), outline, 6.0)
	draw_line(Vector2(x - 38, y + 2), Vector2(x + 38, y + 2), outline, 6.0)
	draw_line(Vector2(x - 32, y + 2), Vector2(x - 32, y + 16), outline, 4.0)
	draw_line(Vector2(x + 32, y + 2), Vector2(x + 32, y + 16), outline, 4.0)
	draw_rect(Rect2(x - 24, y + 16, 48, 64), outline)
	draw_rect(Rect2(x - 18, y + 22, 36, 48), Color("c9f0f5"))
	draw_rect(Rect2(x - 18, y + 50, 36, 20), Color("7bc7d8"))
	draw_line(Vector2(x, y + 80), Vector2(x, y + 154), Color("55b8cc"), 3.0)
	draw_line(Vector2(x, 428), Vector2(x - 33, 439), outline, 5.0)
	draw_line(Vector2(x, 428), Vector2(x + 33, 439), outline, 5.0)
	draw_line(Vector2(x, 428), Vector2(x, 444), outline, 5.0)
	draw_circle(Vector2(x - 33, 440), 6, outline)
	draw_circle(Vector2(x + 33, 440), 6, outline)
	draw_circle(Vector2(x, 446), 6, outline)


func _draw_medical_cross(x: float, y: float, size: float, color: Color, outline: Color) -> void:
	draw_rect(Rect2(x - size - 4, y - size - 4, size * 2 + 8, size * 2 + 8), outline)
	draw_rect(Rect2(x - size, y - size, size * 2, size * 2), color)
	draw_rect(Rect2(x - 5, y - size + 5, 10, size * 2 - 10), Color.WHITE)
	draw_rect(Rect2(x - size + 5, y - 5, size * 2 - 10, 10), Color.WHITE)


func _register_controls() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_left", KEY_LEFT)
	_add_key_action("move_right", KEY_D)
	_add_key_action("move_right", KEY_RIGHT)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("jump", KEY_UP)


func _add_key_action(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _create_room() -> void:
	# Three floor sections leave small gaps for the player to jump across.
	_create_platform(Vector2(-90, 570), Vector2(940, 48))
	_create_platform(Vector2(760, 570), Vector2(520, 48))
	_create_platform(Vector2(1540, 570), Vector2(750, 48))
	# A couple of low platforms add a little vertical movement to the room.
	_create_platform(Vector2(585, 480), Vector2(150, 24), Color("268f98"))
	_create_platform(Vector2(1115, 480), Vector2(170, 24), Color("268f98"))
	_create_player()
	_add_world_label("PATIENT ROOM / LEVEL 1", Vector2(-380, 115), Color("89f4e5"), 25)
	_add_world_label("EMERGENCY CARE • OXYGEN DELIVERY", Vector2(-378, 150), Color("b6c9e3"), 15)


func _create_platform(center: Vector2, size: Vector2, color := Color("263d61")) -> void:
	var body := StaticBody2D.new()
	body.position = center
	add_child(body)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-size.x / 2, -size.y / 2), Vector2(size.x / 2, -size.y / 2),
		Vector2(size.x / 2, size.y / 2), Vector2(-size.x / 2, size.y / 2)
	])
	visual.color = color
	body.add_child(visual)
	var top_glow := Polygon2D.new()
	top_glow.polygon = PackedVector2Array([
		Vector2(-size.x / 2, -size.y / 2), Vector2(size.x / 2, -size.y / 2),
		Vector2(size.x / 2, -size.y / 2 + 5), Vector2(-size.x / 2, -size.y / 2 + 5)
	])
	top_glow.color = Color("48e1c6")
	body.add_child(top_glow)


func _create_player() -> void:
	player = CharacterBody2D.new()
	player.name = "Player"
	player.position = Vector2(-350, 520)
	player.set_script(PLAYER_SCRIPT)
	add_child(player)
	var collision := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 15.0
	shape.height = 48.0
	collision.shape = shape
	player.add_child(collision)
	# Simple doctor/scientist character with a plus badge.
	_add_circle(player, Vector2(0, -27), 13, Color("ffd8ba"))
	_add_poly(player, [Vector2(-14, -14), Vector2(14, -14), Vector2(17, 17), Vector2(-17, 17)], Color("f3f7ff"))
	_add_poly(player, [Vector2(-17, 17), Vector2(17, 17), Vector2(13, 24), Vector2(-13, 24)], Color("58d8c1"))
	_add_poly(player, [Vector2(-7, -8), Vector2(7, -8), Vector2(7, 8), Vector2(-7, 8)], Color("36c9b7"))
	_add_poly(player, [Vector2(-2, -6), Vector2(2, -6), Vector2(2, 6), Vector2(-2, 6)], Color.WHITE)
	_add_poly(player, [Vector2(-6, -2), Vector2(6, -2), Vector2(6, 2), Vector2(-6, 2)], Color.WHITE)
	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	player.add_child(camera)
	camera.make_current()


func _add_circle(parent: Node2D, at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		points.append(at + Vector2(cos(angle), sin(angle)) * radius)
	_add_poly(parent, points, color)


func _add_poly(parent: Node2D, points: Variant, color: Color) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array(points)
	polygon.color = color
	parent.add_child(polygon)


func _add_world_label(text: String, at: Vector2, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)


func _create_checkpoint(x: float, question_index: int) -> void:
	var area := Area2D.new()
	area.position = Vector2(x, 492)
	area.name = "QuestionCheckpoint%d" % (question_index + 1)
	add_child(area)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70, 150)
	collision.shape = shape
	area.add_child(collision)
	_add_poly(area, [Vector2(-25, -58), Vector2(25, -58), Vector2(25, 45), Vector2(-25, 45)], Color("316a91"))
	_add_poly(area, [Vector2(-25, -58), Vector2(25, -58), Vector2(25, -51), Vector2(-25, -51)], Color("59f0d3"))
	_add_poly(area, [Vector2(-5, -42), Vector2(5, -42), Vector2(5, -22), Vector2(-5, -22)], Color.WHITE)
	_add_poly(area, [Vector2(-15, -36), Vector2(15, -36), Vector2(15, -28), Vector2(-15, -28)], Color.WHITE)
	_add_world_label("QUIZ %d" % (question_index + 1), Vector2(x - 34, 416), Color("b8fff2"), 16)
	area.body_entered.connect(_on_checkpoint_entered.bind(area, question_index))


func _create_exit(x: float) -> void:
	var area := Area2D.new()
	area.position = Vector2(x, 490)
	add_child(area)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(80, 170)
	collision.shape = shape
	area.add_child(collision)
	_add_poly(area, [Vector2(-32, -70), Vector2(32, -70), Vector2(32, 48), Vector2(-32, 48)], Color("1d8e81"))
	_add_poly(area, [Vector2(-24, -60), Vector2(24, -60), Vector2(24, 40), Vector2(-24, 40)], Color("163b59"))
	_add_world_label("EXIT", Vector2(x - 22, 395), Color("94ffe7"), 19)
	area.body_entered.connect(_on_exit_entered)


func _create_hud() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	var bar := PanelContainer.new()
	bar.position = Vector2(22, 18)
	bar.custom_minimum_size = Vector2(450, 72)
	bar.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.09, 0.17, 0.88), Color("35d8c2")))
	ui_layer.add_child(bar)
	hud_label = Label.new()
	hud_label.text = "MEDICAL MISSION     A/D or arrows: move     SPACE: jump"
	hud_label.add_theme_color_override("font_color", Color("e6f5ff"))
	hud_label.add_theme_font_size_override("font_size", 17)
	bar.add_child(hud_label)


func _create_question_popup() -> void:
	popup = PanelContainer.new()
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.offset_left = -270
	popup.offset_top = -175
	popup.offset_right = 270
	popup.offset_bottom = 175
	popup.add_theme_stylebox_override("panel", _panel_style(Color("101d33"), Color("4ce2cb")))
	ui_layer.add_child(popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	popup.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_color_override("font_color", Color("f4f8ff"))
	prompt_label.add_theme_font_size_override("font_size", 23)
	column.add_child(prompt_label)
	feedback_label = Label.new()
	feedback_label.add_theme_color_override("font_color", Color("91f3df"))
	feedback_label.add_theme_font_size_override("font_size", 16)
	column.add_child(feedback_label)
	answers_box = VBoxContainer.new()
	answers_box.add_theme_constant_override("separation", 8)
	column.add_child(answers_box)
	popup.hide()


func _panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _on_checkpoint_entered(body: Node2D, area: Area2D, question_index: int) -> void:
	if body != player or quiz_open:
		return
	area.set_deferred("monitoring", false)
	current_question = question_index
	_show_question()


func _show_question() -> void:
	quiz_open = true
	player.set_physics_process(false)
	feedback_label.text = "Choose the best answer to continue."
	prompt_label.text = QUESTIONS[current_question]["prompt"]
	for child in answers_box.get_children():
		child.queue_free()
	for i in range(QUESTIONS[current_question]["answers"].size()):
		var button := Button.new()
		button.text = QUESTIONS[current_question]["answers"][i]
		button.custom_minimum_size = Vector2(440, 42)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_answer_selected.bind(i))
		answers_box.add_child(button)
	popup.show()


func _answer_selected(answer_index: int) -> void:
	if answer_index != int(QUESTIONS[current_question]["correct"]):
		feedback_label.text = "Not quite—try another answer."
		return
	questions_answered += 1
	hud_label.text = "QUESTIONS ANSWERED: %d/2     Keep moving to the exit!" % questions_answered
	if questions_answered < QUESTIONS.size():
		current_question += 1
		feedback_label.text = QUESTIONS[current_question - 1]["explain"] + " Next checkpoint ahead!"
		prompt_label.text = "Ready for the next question?"
		for child in answers_box.get_children():
			child.queue_free()
		var next_button := Button.new()
		next_button.text = "Continue"
		next_button.custom_minimum_size = Vector2(440, 42)
		next_button.pressed.connect(_resume_after_quiz)
		answers_box.add_child(next_button)
	else:
		feedback_label.text = QUESTIONS[current_question]["explain"] + " Reach the exit!"
		prompt_label.text = "Checkpoint complete!"
		for child in answers_box.get_children():
			child.queue_free()
		var continue_button := Button.new()
		continue_button.text = "Continue to the exit"
		continue_button.custom_minimum_size = Vector2(440, 42)
		continue_button.pressed.connect(_resume_after_quiz)
		answers_box.add_child(continue_button)


func _resume_after_quiz() -> void:
	popup.hide()
	quiz_open = false
	player.set_physics_process(true)


func _on_exit_entered(body: Node2D) -> void:
	if body != player:
		return
	player.set_physics_process(false)
	quiz_open = true
	prompt_label.text = "Patient discharged!"
	feedback_label.text = "You reached the end and completed %d medical questions." % questions_answered
	for child in answers_box.get_children():
		child.queue_free()
	var finish_button := Button.new()
	finish_button.text = "Play again"
	finish_button.custom_minimum_size = Vector2(440, 42)
	finish_button.pressed.connect(_restart_game)
	answers_box.add_child(finish_button)
	popup.show()


func _restart_game() -> void:
	get_tree().reload_current_scene()
