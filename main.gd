extends Node2D

const PLAYER_SCRIPT = preload("res://player.gd")
const NEEDLE_TEXTURE = preload("res://needle.png")
const APPLE_TEXTURE = preload("res://apple.png")
const SCALPEL_TEXTURE = preload("res://scalpel.png")
const SEED_TEXTURE = preload("res://seed.png")
const MEDICAL_STUDENT_TEXTURE = preload("res://medical_student.png")
const KAREN_TEXTURE = preload("res://karen.png")
const ADRENALINE_TEXTURE = preload("res://adrenaline.png")
const PHD_TEXTURE = preload("res://phd.png")
const PLAYER_MAX_HEALTH := 100
const BOSS_MAX_HEALTH := 200
const SCALPEL_DAMAGE := 20
const APPLE_DAMAGE := 5
const SCALPEL_SWING_TIME := 0.42
const BOSS_ARENA_MIN_X := -640.0
const BOSS_ARENA_MAX_X := 640.0
const PHD_DOOR_RESPAWN_POSITION := Vector2(1905, 289)
const PHD_TERM_STRINGS: Array[String] = [
	"CARDIOLOGY • HEMATOLOGY • NEUROLOGY",
	"DYSPNEA • TACHYCARDIA • HEMOSTASIS",
	"ERYTHROCYTE • LEUKOCYTE • PLATELET",
	"PATHOLOGY • ANATOMY • PHYSIOLOGY"
]
var questions: Array[Dictionary] = []

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
var last_grounded_position := Vector2(-350, 520)
var level_start_position := Vector2(-350, 520)
var boss_room := false
var next_level := false
var boss_defeated := false
var door_nearby := false
var door_target: StringName = &"apple_boss"
var boss_kind: StringName = &"apple"
var karen_defeated := false
var phd_defeated := false
var has_adrenaline := false
var adrenaline_pickup: Area2D
var player_sprite: Sprite2D
var moving_arm_overlay: Node2D
var moving_arm_cover: Polygon2D
var moving_arm_outline: Line2D
var moving_arm_sleeve: Line2D
var moving_arm_hand: Polygon2D
var player_move_clock := 0.0
var virus_hazards: Array[Area2D] = []
var virus_spawn_timer := 0.0
var phd_term_index := 0
var player_health := PLAYER_MAX_HEALTH
var boss_health := BOSS_MAX_HEALTH
var boss_jump_timer := 2.5
var seed_shot_timer := 1.2
var seed_projectiles: Array[Area2D] = []
var boss_attack_state: StringName = &"approach"
var attack_cooldown := 0.0
var swing_timer := 0.0
var swing_hit_registered := false
var player_facing := 1.0
var boss: CharacterBody2D
var boss_collision_shape: CollisionShape2D
var player_health_label: Label
var boss_health_label: Label
var player_health_bar: ProgressBar
var boss_health_bar: ProgressBar
var scalpel_sprite: Sprite2D
var slash_arc: Line2D
var slash_arc_highlight: Line2D
var player_camera: Camera2D


func _ready() -> void:
	_load_questions()
	_register_controls()
	queue_redraw()
	_create_room()
	_create_hud()
	_create_question_popup()


func _load_questions() -> void:
	var file := FileAccess.open("res://medical_questions.json", FileAccess.READ)
	if file == null:
		push_error("Question bank could not be opened.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		questions.assign(parsed)
	if questions.is_empty():
		push_error("Question bank is empty.")

func _input(event: InputEvent) -> void:
	if not quiz_open and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_scalpel_swing()


func _process(delta: float) -> void:
	if player == null or quiz_open:
		return
	if player.is_on_floor():
		last_grounded_position = player.global_position
	var movement := Input.get_axis("move_left", "move_right")
	if absf(movement) > 0.1:
		player_move_clock += delta
		player_facing = signf(movement)
		if is_instance_valid(player_sprite):
			player_sprite.flip_h = player_facing < 0.0
	if is_instance_valid(moving_arm_overlay):
		var is_moving := absf(movement) > 0.1
		moving_arm_overlay.visible = is_moving
		moving_arm_overlay.scale.x = player_facing
		if is_moving:
			var arm_swing := sin(player_move_clock * 12.0) * 3.2
			var elbow := Vector2(-16.0, -13.0 + arm_swing)
			var wrist := Vector2(-17.0, -6.0 + arm_swing)
			var arm_points := PackedVector2Array([Vector2(-8.0, -24.0), elbow, wrist])
			moving_arm_outline.points = arm_points
			moving_arm_sleeve.points = arm_points
			var hand_center := wrist + Vector2(-1.0, 2.0)
			moving_arm_hand.polygon = PackedVector2Array([
				hand_center + Vector2(-3.0, -3.0), hand_center + Vector2(1.0, -4.0),
				hand_center + Vector2(4.0, -1.0), hand_center + Vector2(3.0, 3.0),
				hand_center + Vector2(-1.0, 4.0), hand_center + Vector2(-4.0, 1.0)
			])
	if player.global_position.y > 900.0:
		_handle_fall()
		return
	if door_nearby and Input.is_action_just_pressed("interact"):
		match door_target:
			&"apple_boss":
				_enter_boss_room(&"apple")
			&"karen_boss":
				_enter_boss_room(&"karen")
			&"level2":
				_enter_next_level()
			&"level2_return":
				_return_to_level_two()
			&"level2_finish":
				_enter_boss_room(&"phd")
	_update_player_scalpel(delta)
	if boss_room:
		_update_boss_fight(delta)


func _handle_fall() -> void:
	_hide_scalpel()
	# Return to the last safe platform before asking the medical question.
	player.global_position = last_grounded_position
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(false)
	current_question = randi_range(0, questions.size() - 1)
	quiz_open = true
	prompt_label.text = "You fell! You're back on the platform you were standing on."
	feedback_label.add_theme_color_override("font_color", Color("91f3df"))
	feedback_label.text = "Answer the medical question correctly to continue."
	_show_answer_buttons()
	popup.show()


func _draw() -> void:
	if boss_room:
		_draw_inside_body_background()
		return
	if next_level:
		_draw_research_room_background()
		return
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
	draw_rect(Rect2(-1400, -150, 4200, 672), Color("e2e8f5"))
	for x in range(-1300, 2700, 260):
		draw_rect(Rect2(x, -135, 244, 470), Color("e8edf7"))
		draw_line(Vector2(x + 244, -135), Vector2(x + 244, 334), Color("b8c4da"), 3.0)
	draw_rect(Rect2(-1400, 522, 4200, 24), Color("aebbd2"))
	draw_rect(Rect2(-1400, 546, 4200, 210), Color("cbd5e8"))
	draw_line(Vector2(-1400, 546), Vector2(2800, 546), Color("f7f9ff"), 6.0)
	for x in range(-1300, 2700, 120):
		draw_line(Vector2(x, 547), Vector2(x, 638), Color("b6c2d8"), 2.0)
	# Ceiling surgical lamps and wall fixtures spaced along the scrolling room.
	for x in [-760, -80, 620, 1320, 2020]:
		_set_art_scale(Vector2(float(x), 20), 0.74)
		_draw_surgical_light(float(x), outline)
		_reset_art_scale()
	_set_art_scale(Vector2(-957.5, 123.5), 0.78)
	_draw_window(-1080, 26, 245, 195, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(-690, 546), 0.70)
	_draw_cabinet(-790, 339, 200, 183, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(-438, 147.5), 0.72)
	_draw_monitor(-525, 85, 174, 125, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(-62.5, 546), 0.70)
	_draw_bed(-205, 430, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(338, 167.5), 0.72)
	_draw_monitor(240, 95, 196, 145, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(492, 546), 0.72)
	_draw_iv_pole(492, 88, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(857.5, 546), 0.70)
	_draw_cabinet(740, 339, 235, 183, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(1110, 169), 0.72)
	_draw_monitor(1010, 100, 200, 138, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(1517.5, 123.5), 0.78)
	_draw_window(1395, 26, 245, 195, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(1720, 546), 0.72)
	_draw_iv_pole(1720, 82, outline)
	_reset_art_scale()
	_set_art_scale(Vector2(1965, 546), 0.70)
	_draw_cabinet(1855, 339, 220, 183, outline)
	_reset_art_scale()
	# A few wall signs and floor reflections keep the space readable in motion.
	_set_art_scale(Vector2(-405, -55), 0.82)
	_draw_medical_cross(-405, -55, 23, Color("42aeca"), outline)
	_reset_art_scale()
	_set_art_scale(Vector2(1280, -55), 0.82)
	_draw_medical_cross(1280, -55, 23, Color("42aeca"), outline)
	_reset_art_scale()
	for x in range(-1250, 2600, 170):
		draw_rect(Rect2(x, 617, 72, 5), Color(0.40, 0.50, 0.67, 0.22))


func _draw_inside_body_background() -> void:
	# A stylized bloodstream chamber keeps the boss arena medically themed.
	draw_rect(Rect2(-1900, -1000, 3800, 2000), Color("241126"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1900, -280), Vector2(-1200, -360), Vector2(-450, -275),
		Vector2(250, -360), Vector2(980, -285), Vector2(1900, -360),
		Vector2(1900, 230), Vector2(1050, 285), Vector2(240, 215),
		Vector2(-600, 300), Vector2(-1300, 220), Vector2(-1900, 280)
	]), Color("4c1d38"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1900, -180), Vector2(-1050, -255), Vector2(-300, -180),
		Vector2(450, -260), Vector2(1250, -170), Vector2(1900, -245),
		Vector2(1900, 170), Vector2(1150, 215), Vector2(350, 155),
		Vector2(-500, 235), Vector2(-1300, 155), Vector2(-1900, 210)
	]), Color("692446"))
	# Vessel walls and glowing capillaries.
	for x in range(-1800, 1801, 260):
		draw_line(Vector2(x, -240), Vector2(x + 150, 220), Color("a73b5c"), 7.0)
		draw_line(Vector2(x + 4, -240), Vector2(x + 154, 220), Color("f27483"), 2.0)
	# Floating red blood cells in the distance.
	for cell in [Vector2(-1300, -100), Vector2(-900, 70), Vector2(-450, -65), Vector2(60, -105), Vector2(520, 65), Vector2(1080, -85), Vector2(1500, 90)]:
		_draw_blood_cell(cell, 34.0)
	draw_rect(Rect2(-1900, 548, 3800, 240), Color("361529"))
	draw_line(Vector2(-1900, 548), Vector2(1900, 548), Color("f27483"), 8.0)
	for x in range(-1850, 1900, 100):
		draw_line(Vector2(x, 550), Vector2(x + 45, 670), Color("77304b"), 3.0)


func _draw_blood_cell(center: Vector2, radius: float) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		outer.append(center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.62))
		inner.append(center + Vector2(cos(angle) * radius * 0.48, sin(angle) * radius * 0.28))
	draw_colored_polygon(outer, Color("d45c73"))
	draw_colored_polygon(inner, Color("a83958"))


func _draw_research_room_background() -> void:
	draw_rect(Rect2(-1800, -1000, 3600, 2000), Color("e5eff4"))
	draw_rect(Rect2(-1800, -420, 3600, 330), Color("bfdae4"))
	draw_rect(Rect2(-1800, -90, 3600, 640), Color("e8f1f3"))
	draw_rect(Rect2(-1800, 540, 3600, 250), Color("c2d3dc"))
	for x in range(-1700, 1800, 260):
		draw_rect(Rect2(x, -350, 220, 190), Color("d4e7ed"))
		draw_rect(Rect2(x + 12, -338, 196, 166), Color("9ed3df"))
		draw_line(Vector2(x + 12, -255), Vector2(x + 208, -255), Color("f2fbff"), 5.0)
		draw_rect(Rect2(x, 555, 170, 8), Color(0.34, 0.62, 0.70, 0.22))
	draw_line(Vector2(-1800, 540), Vector2(1800, 540), Color("ffffff"), 7.0)


func _set_art_scale(anchor: Vector2, amount: float) -> void:
	# Shrink a prop toward its center or floor contact point without moving that point.
	draw_set_transform(anchor * (1.0 - amount), 0.0, Vector2.ONE * amount)


func _reset_art_scale() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	draw_line(Vector2(x, y), Vector2(x, 528), outline, 6.0)
	draw_line(Vector2(x - 38, y + 2), Vector2(x + 38, y + 2), outline, 6.0)
	draw_line(Vector2(x - 32, y + 2), Vector2(x - 32, y + 16), outline, 4.0)
	draw_line(Vector2(x + 32, y + 2), Vector2(x + 32, y + 16), outline, 4.0)
	draw_rect(Rect2(x - 24, y + 16, 48, 64), outline)
	draw_rect(Rect2(x - 18, y + 22, 36, 48), Color("c9f0f5"))
	draw_rect(Rect2(x - 18, y + 50, 36, 20), Color("7bc7d8"))
	draw_line(Vector2(x, y + 80), Vector2(x, y + 154), Color("55b8cc"), 3.0)
	draw_line(Vector2(x, 528), Vector2(x - 33, 539), outline, 5.0)
	draw_line(Vector2(x, 528), Vector2(x + 33, 539), outline, 5.0)
	draw_line(Vector2(x, 528), Vector2(x, 544), outline, 5.0)
	draw_circle(Vector2(x - 33, 540), 6, outline)
	draw_circle(Vector2(x + 33, 540), 6, outline)
	draw_circle(Vector2(x, 546), 6, outline)


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
	_add_key_action("jump", KEY_W)
	_add_key_action("jump", KEY_UP)
	_add_key_action("interact", KEY_E)


func _add_key_action(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _create_room() -> void:
	# A shorter parkour route: the low ledge leads to the needle launcher,
	# which can boost the player up to the distant landing platform.
	_create_platform(Vector2(-350, 570), Vector2(220, 48), Color("31527a"))
	_create_platform(Vector2(-50, 490), Vector2(100, 24))
	_create_platform(Vector2(230, 420), Vector2(90, 24), Color("34758a"))
	_create_platform(Vector2(440, 640), Vector2(110, 24), Color("31527a"))
	# The intermediate second-half ledges are removed; this is the far landing.
	_create_platform(Vector2(1860, 320), Vector2(160, 24), Color("34758a"))
	_create_player()
	_create_needle_launcher(Vector2(530, 715))
	_create_exit_door(Vector2(1920, 242), "BOSS ROOM  •  E")
	_add_world_label("PATIENT ROOM / LEVEL 1", Vector2(-380, 115), Color("89f4e5"), 25)
	_add_world_label("EMERGENCY CARE • OXYGEN DELIVERY", Vector2(-378, 150), Color("b6c9e3"), 15)
	_add_world_label("NEEDLE BOOST →", Vector2(405, 565), Color("89f4e5"), 18)
	_add_world_label("FAR LANDING", Vector2(1785, 255), Color("89f4e5"), 20)
	_add_world_label("FIRST BOSS TIP: LEFT CLICK TO SWING YOUR SCALPEL", Vector2(1640, 165), Color("25839a"), 16)


func _create_exit_door(at: Vector2, label_text: String, target: StringName = &"apple_boss") -> void:
	var door := Area2D.new()
	door.name = "BossRoomDoor"
	door.position = at
	door.set_meta("door_target", target)
	door.add_to_group("room_content")
	door.collision_layer = 0
	door.collision_mask = 1
	var trigger := CollisionShape2D.new()
	var trigger_shape := RectangleShape2D.new()
	trigger_shape.size = Vector2(100, 130)
	trigger.shape = trigger_shape
	door.add_child(trigger)
	var frame := Polygon2D.new()
	frame.polygon = PackedVector2Array([
		Vector2(-48, 66), Vector2(-48, -66), Vector2(48, -66), Vector2(48, 66)
	])
	frame.color = Color("263d61")
	door.add_child(frame)
	var leaf := Polygon2D.new()
	leaf.polygon = PackedVector2Array([
		Vector2(-38, 66), Vector2(-38, -56), Vector2(38, -56), Vector2(38, 66)
	])
	leaf.color = Color("5d7898")
	door.add_child(leaf)
	var window := Polygon2D.new()
	window.polygon = PackedVector2Array([
		Vector2(-23, -38), Vector2(-23, -5), Vector2(23, -5), Vector2(23, -38)
	])
	window.color = Color("9eeaf0")
	door.add_child(window)
	_add_circle(door, Vector2(25, 20), 5.0, Color("ffd16c"))
	door.body_entered.connect(_on_door_entered.bind(target))
	door.body_exited.connect(_on_door_exited.bind(target))
	add_child(door)
	_add_world_label(label_text, at + Vector2(-85, -94), Color("89f4e5"), 15)


func _on_door_entered(body: Node2D, target: StringName) -> void:
	if body == player:
		door_nearby = true
		door_target = target
		match target:
			&"apple_boss":
				hud_label.text = "Press E to challenge the apple pathogen"
			&"karen_boss":
				hud_label.text = "Press E to enter Karen's room"
			&"level2":
				hud_label.text = "Press E to enter the next level"
			&"level2_return":
				hud_label.text = "Press E to return to the research wing"
			&"level2_finish":
				hud_label.text = "Press E to challenge the PhD"


func _on_door_exited(body: Node2D, _target: StringName) -> void:
	if body == player:
		door_nearby = false
		hud_label.text = "MEDICAL MISSION     A/D or arrows: move     SPACE: jump"


func _create_needle_launcher(at: Vector2) -> void:
	var launcher := Area2D.new()
	launcher.name = "NeedleLauncher"
	launcher.position = at
	launcher.add_to_group("room_content")
	launcher.collision_layer = 0
	launcher.collision_mask = 1
	var trigger := CollisionShape2D.new()
	var trigger_shape := CapsuleShape2D.new()
	trigger_shape.radius = 18.0
	trigger_shape.height = 132.0
	trigger.shape = trigger_shape
	trigger.rotation = -PI / 4.0
	launcher.add_child(trigger)
	var sprite := Sprite2D.new()
	sprite.texture = NEEDLE_TEXTURE
	sprite.scale = Vector2(0.32, 0.32)
	# The source image's point faces down-left; turn it around to point up-right.
	sprite.rotation = PI
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	launcher.add_child(sprite)
	launcher.body_entered.connect(_on_needle_contact.bind(launcher))
	add_child(launcher)


func _on_needle_contact(body: Node2D, launcher: Area2D) -> void:
	if body != player or quiz_open:
		return
	# Launch diagonally up and right so the distant platform is reachable.
	player.launch_from_needle(1000.0, 1.2, -1350.0)
	launcher.set_deferred("monitoring", false)
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(launcher):
			launcher.monitoring = true
	)


func _create_platform(center: Vector2, size: Vector2, color := Color("263d61")) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.add_to_group("room_content")
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
	player.add_to_group("room_content")
	player.position = Vector2(-350, 520)
	player.set_script(PLAYER_SCRIPT)
	add_child(player)
	var collision := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 13.0
	shape.height = 62.0
	collision.shape = shape
	player.add_child(collision)
	player_sprite = Sprite2D.new()
	player_sprite.name = "MedicalStudentVisual"
	player_sprite.texture = MEDICAL_STUDENT_TEXTURE
	player_sprite.position = Vector2(0, -9)
	player_sprite.scale = Vector2(0.06, 0.06)
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player.add_child(player_sprite)
	moving_arm_overlay = Node2D.new()
	moving_arm_overlay.name = "MovingArm"
	moving_arm_overlay.visible = false
	player.add_child(moving_arm_overlay)
	moving_arm_cover = Polygon2D.new()
	moving_arm_cover.polygon = PackedVector2Array([
		Vector2(-18, -12), Vector2(-8, -10), Vector2(-6, -3),
		Vector2(-12, 2), Vector2(-18, -2)
	])
	moving_arm_cover.color = Color("f6f8fc")
	moving_arm_overlay.add_child(moving_arm_cover)
	moving_arm_outline = Line2D.new()
	moving_arm_outline.width = 8.0
	moving_arm_outline.default_color = Color("415872")
	moving_arm_overlay.add_child(moving_arm_outline)
	moving_arm_sleeve = Line2D.new()
	moving_arm_sleeve.width = 5.5
	moving_arm_sleeve.default_color = Color("f6f8fc")
	moving_arm_overlay.add_child(moving_arm_sleeve)
	moving_arm_hand = Polygon2D.new()
	moving_arm_hand.color = Color("ffd8ba")
	moving_arm_overlay.add_child(moving_arm_hand)
	scalpel_sprite = Sprite2D.new()
	scalpel_sprite.name = "Scalpel"
	scalpel_sprite.texture = SCALPEL_TEXTURE
	scalpel_sprite.scale = Vector2(0.075, 0.075)
	scalpel_sprite.position = Vector2(24, -2)
	scalpel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scalpel_sprite.visible = false
	player.add_child(scalpel_sprite)
	var arc_points := PackedVector2Array([
		Vector2(18, -39), Vector2(39, -34), Vector2(56, -20),
		Vector2(65, 0), Vector2(56, 20), Vector2(39, 34), Vector2(18, 39)
	])
	slash_arc = Line2D.new()
	slash_arc.name = "ScalpelSlashArc"
	slash_arc.points = arc_points
	slash_arc.width = 7.0
	slash_arc.default_color = Color("4ce2cb")
	slash_arc.z_index = 3
	slash_arc.visible = false
	player.add_child(slash_arc)
	slash_arc_highlight = Line2D.new()
	slash_arc_highlight.name = "ScalpelSlashHighlight"
	slash_arc_highlight.points = arc_points
	slash_arc_highlight.width = 2.5
	slash_arc_highlight.default_color = Color("e8fffc")
	slash_arc_highlight.z_index = 4
	slash_arc_highlight.visible = false
	player.add_child(slash_arc_highlight)
	var camera := Camera2D.new()
	camera.name = "PlayerCamera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	player.add_child(camera)
	player_camera = camera
	camera.make_current()
	level_start_position = player.global_position
	last_grounded_position = player.global_position

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
	label.add_to_group("room_content")
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)


func _enter_boss_room(kind: StringName) -> void:
	boss_room = true
	boss_kind = kind
	boss_defeated = false
	door_nearby = false
	_clear_viruses()
	virus_spawn_timer = 0.0
	phd_term_index = 0
	player_health = PLAYER_MAX_HEALTH
	boss_health = BOSS_MAX_HEALTH
	seed_projectiles.clear()
	for node in get_tree().get_nodes_in_group("room_content"):
		if node != player:
			node.queue_free()
	player.global_position = Vector2(-300, 505)
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(true)
	if is_instance_valid(player_camera):
		player_camera.reset_smoothing()
	last_grounded_position = player.global_position
	_create_platform(Vector2(0, 560), Vector2(1400, 48), Color("45243c"))
	_create_boss(kind)
	_add_world_label("INSIDE THE BLOODSTREAM", Vector2(-540, 390), Color("ffd3dc"), 25)
	var boss_title := "APPLE PATHOGEN" if kind == &"apple" else "KAREN'S OFFICE • PURSE ATTACKS"
	if kind == &"phd":
		boss_title = "FINAL BOSS • THE PHD"
	_add_world_label(boss_title + "  •  LEFT CLICK TO SWING", Vector2(-540, 426), Color("a8f6ee"), 17)
	if kind == &"phd":
		_add_world_label("DODGE THE MEDICAL TERMS AND FLOATING VIRUSES", Vector2(-540, 455), Color("ffd66d"), 15)
	hud_label.text = "BOSS FIGHT     LEFT CLICK: swing scalpel     A/D: move"
	boss_health_bar.show()
	boss_health_label.show()
	_update_health_ui()
	queue_redraw()


func _create_boss(kind: StringName) -> void:
	boss = CharacterBody2D.new()
	if kind == &"apple":
		boss.name = "AppleBoss"
		boss.position = Vector2(300, 489)
	elif kind == &"karen":
		boss.name = "KarenBoss"
		boss.position = Vector2(300, 474)
	else:
		boss.name = "PhDBoss"
		boss.position = Vector2(300, 478)
	boss.add_to_group("room_content")
	boss_collision_shape = CollisionShape2D.new()
	boss_collision_shape.name = "BossHitbox"
	var shape := CircleShape2D.new()
	shape.radius = 58.0
	if kind == &"apple":
		shape.radius = 47.0
	elif kind == &"karen":
		shape.radius = 62.0
	boss_collision_shape.shape = shape
	boss.add_child(boss_collision_shape)
	var sprite := Sprite2D.new()
	if kind == &"apple":
		sprite.texture = APPLE_TEXTURE
		sprite.scale = Vector2(0.075, 0.075)
	elif kind == &"karen":
		sprite.texture = KAREN_TEXTURE
		sprite.scale = Vector2(0.195, 0.195)
		sprite.position.y = -55.0
	else:
		sprite.texture = PHD_TEXTURE
		sprite.scale = Vector2(0.12, 0.12)
		sprite.position.y = 11.0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	boss.add_child(sprite)
	add_child(boss)
	boss_jump_timer = 2.5
	seed_shot_timer = 1.2
	boss_attack_state = &"approach"


func _update_boss_fight(delta: float) -> void:
	if boss_defeated or boss == null or not is_instance_valid(boss):
		return
	boss_jump_timer -= delta
	seed_shot_timer -= delta
	var toward_player := signf(player.global_position.x - boss.global_position.x)
	var horizontal_distance := absf(player.global_position.x - boss.global_position.x)
	if boss.is_on_floor():
		if boss_attack_state != &"approach":
			boss_attack_state = &"approach"
			boss_jump_timer = 1.35
		if boss_kind == &"apple":
			if horizontal_distance > 135.0:
				boss.velocity.x = toward_player * 85.0
			else:
				boss.velocity.x = 0.0
			if boss_jump_timer <= 0.0:
				boss_attack_state = &"leap"
				boss.velocity.x = clampf((player.global_position.x - boss.global_position.x) * 1.15, -440.0, 440.0)
				boss.velocity.y = -620.0
				boss_jump_timer = 4.2
		elif boss_kind == &"karen":
			# Karen hops toward the player, then backs off while continuing to throw purse items.
			if horizontal_distance > 280.0:
				boss.velocity.x = toward_player * 80.0
			elif horizontal_distance < 190.0:
				boss.velocity.x = -toward_player * 80.0
			else:
				boss.velocity.x = 0.0
			if boss_jump_timer <= 0.0:
				boss_attack_state = &"leap"
				boss.velocity.x = clampf((player.global_position.x - boss.global_position.x) * 1.25, -500.0, 500.0)
				boss.velocity.y = -600.0
				boss_jump_timer = 2.4
		else:
			boss.velocity.x = 0.0
	elif boss_attack_state == &"bounce":
		boss.velocity.x = move_toward(boss.velocity.x, 0.0, 230.0 * delta)
	boss.velocity.y += 1150.0 * delta
	boss.move_and_slide()
	_keep_boss_inside_arena()
	var contact_range := 92.0 if boss_kind == &"apple" else 120.0
	if boss_attack_state == &"leap" and boss.global_position.distance_to(player.global_position) < contact_range:
		var boss_before_hit := boss
		_damage_player(APPLE_DAMAGE)
		if boss != boss_before_hit:
			return
		boss_attack_state = &"bounce"
		var bounce_direction := signf(boss.global_position.x - player.global_position.x)
		if is_zero_approx(bounce_direction):
			bounce_direction = -toward_player
		boss.velocity = Vector2(bounce_direction * 390.0, -450.0)
	if seed_shot_timer <= 0.0:
		_shoot_apple_seed()
		seed_shot_timer = 1.8 if boss_kind == &"phd" else 2.2
	_update_seed_projectiles(delta)
	if boss_kind == &"phd":
		_update_virus_hazards(delta)


func _update_player_scalpel(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if swing_timer <= 0.0:
		scalpel_sprite.visible = false
		scalpel_sprite.flip_h = player_facing < 0.0
		scalpel_sprite.position = Vector2(24.0 * player_facing, -2.0)
		scalpel_sprite.rotation = 0.22 * player_facing
		scalpel_sprite.scale = Vector2(0.075, 0.075)
		slash_arc.visible = false
		slash_arc_highlight.visible = false
		return

	swing_timer = maxf(0.0, swing_timer - delta)
	var progress := 1.0 - swing_timer / SCALPEL_SWING_TIME
	scalpel_sprite.visible = true
	scalpel_sprite.flip_h = player_facing < 0.0
	var swing_angle: float
	if progress < 0.22:
		var windup := progress / 0.22
		swing_angle = lerpf(-0.35, -1.15, windup)
	elif progress < 0.72:
		var strike := (progress - 0.22) / 0.50
		var eased_strike := strike * strike * (3.0 - 2.0 * strike)
		swing_angle = lerpf(-1.15, 1.0, eased_strike)
	else:
		var follow_through := (progress - 0.72) / 0.28
		swing_angle = lerpf(1.0, 0.55, follow_through)
	scalpel_sprite.position = Vector2(27.0 * player_facing, -4.0 + sin(progress * PI) * -5.0)
	scalpel_sprite.rotation = swing_angle * player_facing
	var scale_pulse := 1.0 + sin(progress * PI) * 0.12
	scalpel_sprite.scale = Vector2(0.075, 0.075) * scale_pulse
	var arc_visible := boss_room and progress >= 0.16 and progress <= 0.84
	slash_arc.visible = arc_visible
	slash_arc_highlight.visible = arc_visible
	slash_arc.scale.x = player_facing
	slash_arc_highlight.scale.x = player_facing
	var arc_alpha := 0.85 * sin(clampf((progress - 0.16) / 0.68, 0.0, 1.0) * PI)
	slash_arc.modulate.a = arc_alpha
	slash_arc_highlight.modulate.a = arc_alpha
	if not swing_hit_registered and boss_room and not boss_defeated and is_instance_valid(boss) and progress >= 0.18 and progress <= 0.88:
		var to_boss := boss.global_position - player.global_position
		var hit_range := 112.0 if boss_kind == &"apple" else 155.0
		if to_boss.length() < hit_range and to_boss.x * player_facing > 0.0 and absf(to_boss.y) < 120.0:
			_damage_boss(SCALPEL_DAMAGE)
			swing_hit_registered = true


func _keep_boss_inside_arena() -> void:
	if boss.global_position.x < BOSS_ARENA_MIN_X:
		boss.global_position.x = BOSS_ARENA_MIN_X
		boss.velocity.x = absf(boss.velocity.x) * 0.7
		if boss_attack_state == &"leap":
			boss_attack_state = &"bounce"
			boss.velocity.y = -380.0
	elif boss.global_position.x > BOSS_ARENA_MAX_X:
		boss.global_position.x = BOSS_ARENA_MAX_X
		boss.velocity.x = -absf(boss.velocity.x) * 0.7
		if boss_attack_state == &"leap":
			boss_attack_state = &"bounce"
			boss.velocity.y = -380.0


func _shoot_apple_seed() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var projectile := Area2D.new()
	projectile.name = "BossProjectile"
	projectile.add_to_group("room_content")
	projectile.collision_layer = 0
	projectile.collision_mask = 0
	if boss_kind == &"apple":
		var sprite := Sprite2D.new()
		sprite.texture = SEED_TEXTURE
		sprite.scale = Vector2(0.7, 0.7)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		projectile.add_child(sprite)
	elif boss_kind == &"karen":
		var bag := Polygon2D.new()
		bag.polygon = PackedVector2Array([Vector2(-14, -8), Vector2(13, -8), Vector2(17, 8), Vector2(10, 13), Vector2(-11, 13), Vector2(-17, 7)])
		bag.color = Color("9c537d")
		projectile.add_child(bag)
		var bag_trim := Polygon2D.new()
		bag_trim.polygon = PackedVector2Array([Vector2(-9, -5), Vector2(9, -5), Vector2(11, 2), Vector2(-11, 2)])
		bag_trim.color = Color("f0c96e")
		projectile.add_child(bag_trim)
		var handle := Line2D.new()
		handle.points = PackedVector2Array([Vector2(-7, -8), Vector2(-5, -15), Vector2(5, -15), Vector2(7, -8)])
		handle.width = 3.0
		handle.default_color = Color("e8bb62")
		projectile.add_child(handle)
	else:
		var bubble := Polygon2D.new()
		bubble.polygon = PackedVector2Array([
			Vector2(-178, -20), Vector2(178, -20), Vector2(178, 20), Vector2(-178, 20)
		])
		bubble.color = Color("172a50")
		projectile.add_child(bubble)
		var terms := Label.new()
		terms.position = Vector2(-174, -18)
		terms.size = Vector2(348, 36)
		terms.text = PHD_TERM_STRINGS[phd_term_index % PHD_TERM_STRINGS.size()]
		phd_term_index += 1
		terms.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		terms.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		terms.add_theme_color_override("font_color", Color("fff1a6"))
		terms.add_theme_color_override("font_outline_color", Color("10192d"))
		terms.add_theme_constant_override("outline_size", 3)
		terms.add_theme_font_size_override("font_size", 16)
		projectile.add_child(terms)
	var start_offset := Vector2(-8.0, -8.0)
	if boss_kind == &"phd":
		start_offset = Vector2(signf(player.global_position.x - boss.global_position.x) * 90.0, 0.0)
	var start := boss.global_position + start_offset
	var aim := (player.global_position - start).normalized()
	projectile.global_position = start
	if boss_kind != &"phd":
		projectile.rotation = aim.angle() + PI / 2.0
	var projectile_speed := 540.0
	if boss_kind == &"apple":
		projectile_speed = 430.0
	elif boss_kind == &"karen":
		projectile_speed = 860.0
	projectile.set_meta("seed_velocity", aim * projectile_speed)
	add_child(projectile)
	seed_projectiles.append(projectile)


func _update_seed_projectiles(delta: float) -> void:
	for projectile in seed_projectiles.duplicate():
		if not is_instance_valid(projectile):
			seed_projectiles.erase(projectile)
			continue
		var seed_velocity: Vector2 = projectile.get_meta("seed_velocity", Vector2.ZERO)
		projectile.global_position += seed_velocity * delta
		if projectile.global_position.distance_to(player.global_position) < 32.0:
			var boss_before_hit := boss
			_damage_player(APPLE_DAMAGE)
			projectile.queue_free()
			seed_projectiles.erase(projectile)
			if boss != boss_before_hit:
				return
			if quiz_open:
				return
		elif projectile.global_position.distance_to(boss.global_position) > 950.0:
			projectile.queue_free()
			seed_projectiles.erase(projectile)


func _update_virus_hazards(delta: float) -> void:
	if not boss_room or boss_defeated or boss_kind != &"phd":
		return
	virus_spawn_timer -= delta
	if virus_spawn_timer <= 0.0 and virus_hazards.size() < 6:
		_create_virus_hazard()
		virus_spawn_timer = 0.9
	for virus in virus_hazards.duplicate():
		if not is_instance_valid(virus):
			virus_hazards.erase(virus)
			continue
		var velocity: Vector2 = virus.get_meta("virus_velocity", Vector2.ZERO)
		var wander_timer: float = virus.get_meta("wander_timer", 0.0) - delta
		if wander_timer <= 0.0:
			velocity = Vector2(randf_range(-105.0, 105.0), randf_range(-70.0, 70.0))
			if velocity.length() < 40.0:
				velocity = Vector2(65.0, -45.0)
			wander_timer = randf_range(0.65, 1.5)
			virus.set_meta("virus_velocity", velocity)
			virus.set_meta("wander_timer", wander_timer)
		virus.global_position += velocity * delta
		var relative_position: Vector2 = virus.global_position - player.global_position
		if relative_position.x < -420.0:
			virus.global_position.x = player.global_position.x - 420.0
			velocity.x = absf(velocity.x)
		elif relative_position.x > 420.0:
			virus.global_position.x = player.global_position.x + 420.0
			velocity.x = -absf(velocity.x)
		if relative_position.y < -245.0:
			virus.global_position.y = player.global_position.y - 245.0
			velocity.y = absf(velocity.y)
		elif relative_position.y > 155.0:
			virus.global_position.y = player.global_position.y + 155.0
			velocity.y = -absf(velocity.y)
		virus.set_meta("virus_velocity", velocity)
		if virus.global_position.distance_to(player.global_position) < 34.0:
			_damage_player(10)
			virus.queue_free()
			virus_hazards.erase(virus)
			if not boss_room or boss_kind != &"phd":
				return


func _create_virus_hazard() -> void:
	var virus := Area2D.new()
	virus.name = "FloatingVirus"
	virus.add_to_group("room_content")
	virus.collision_layer = 0
	virus.collision_mask = 0
	var hitbox := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	hitbox.shape = circle
	virus.add_child(hitbox)
	var spikes := Polygon2D.new()
	var vertices := PackedVector2Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		var radius := 25.0 if i % 2 == 0 else 17.0
		vertices.append(Vector2(cos(angle), sin(angle)) * radius)
	spikes.polygon = vertices
	spikes.color = Color("69e47d")
	virus.add_child(spikes)
	_add_circle(virus, Vector2.ZERO, 15.0, Color("9e3cbd"))
	_add_circle(virus, Vector2(-4, -4), 2.5, Color("eaffbd"))
	_add_circle(virus, Vector2(5, 3), 2.5, Color("eaffbd"))
	virus.global_position = player.global_position + Vector2(randf_range(-390.0, 390.0), randf_range(-220.0, 125.0))
	virus.set_meta("virus_velocity", Vector2(randf_range(-100.0, 100.0), randf_range(-65.0, 65.0)))
	virus.set_meta("wander_timer", randf_range(0.5, 1.2))
	add_child(virus)
	virus_hazards.append(virus)


func _clear_viruses() -> void:
	for virus in virus_hazards:
		if is_instance_valid(virus):
			virus.queue_free()
	virus_hazards.clear()


func _clear_seed_projectiles() -> void:
	for projectile in seed_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	seed_projectiles.clear()


func _hide_scalpel() -> void:
	swing_timer = 0.0
	if is_instance_valid(scalpel_sprite):
		scalpel_sprite.visible = false
		scalpel_sprite.scale = Vector2(0.075, 0.075)
		scalpel_sprite.position = Vector2(24.0 * player_facing, -2.0)
		scalpel_sprite.rotation = 0.22 * player_facing
		scalpel_sprite.flip_h = player_facing < 0.0
	if is_instance_valid(slash_arc):
		slash_arc.visible = false
	if is_instance_valid(slash_arc_highlight):
		slash_arc_highlight.visible = false


func _start_scalpel_swing() -> void:
	if attack_cooldown > 0.0:
		return
	attack_cooldown = 0.5
	swing_timer = SCALPEL_SWING_TIME
	swing_hit_registered = false
	scalpel_sprite.visible = true
	slash_arc.visible = false
	slash_arc_highlight.visible = false


func _damage_boss(amount: int) -> void:
	boss_health = maxi(0, boss_health - amount)
	_update_health_ui()
	if boss_health == 0:
		boss_defeated = true
		_hide_scalpel()
		_clear_seed_projectiles()
		boss.velocity = Vector2.ZERO
		boss.visible = false
		if is_instance_valid(boss_collision_shape):
			boss_collision_shape.set_deferred("disabled", true)
		player.velocity = Vector2.ZERO
		player.set_physics_process(false)
		quiz_open = true
		if boss_kind == &"apple":
			prompt_label.text = "The apple pathogen is defeated!"
			feedback_label.text = "Patient stabilized. The door to Level 2 is open."
			_create_exit_door(Vector2(560, 470), "NEXT LEVEL  •  E", &"level2")
		elif boss_kind == &"karen":
			karen_defeated = true
			prompt_label.text = "Karen dropped an adrenaline shot!"
			feedback_label.text = "Continue, then collect the glowing shot to unlock the way back."
			_create_adrenaline_pickup(Vector2(40, 490))
		else:
			phd_defeated = true
			prompt_label.text = "The PhD has been defeated!"
			feedback_label.text = "You survived the final exam and completed the game."
			_create_exit_door(Vector2(560, 470), "RETURN TO LEVEL 2  •  E", &"level2_return")
			_clear_viruses()
		for child in answers_box.get_children():
			child.queue_free()
		var button := Button.new()
		button.text = "Continue exploring"
		button.custom_minimum_size = Vector2(440, 42)
		button.pressed.connect(_continue_after_victory)
		answers_box.add_child(button)
		popup.show()


func _continue_after_victory() -> void:
	_hide_scalpel()
	popup.hide()
	quiz_open = false
	player.set_physics_process(true)
	if boss_kind == &"apple":
		hud_label.text = "PATIENT STABILIZED     GO TO THE NEXT LEVEL DOOR"
	elif boss_kind == &"karen":
		hud_label.text = "KAREN DEFEATED     COLLECT THE ADRENALINE SHOT"
	else:
		hud_label.text = "FINAL BOSS DEFEATED     LEVEL 2 COMPLETE"


func _create_adrenaline_pickup(at: Vector2) -> void:
	var pickup := Area2D.new()
	pickup.name = "AdrenalineShot"
	pickup.position = at
	pickup.add_to_group("room_content")
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 34.0
	collision.shape = circle
	pickup.add_child(collision)
	var sprite := Sprite2D.new()
	sprite.texture = ADRENALINE_TEXTURE
	sprite.scale = Vector2(0.11, 0.11)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pickup.add_child(sprite)
	pickup.body_entered.connect(_on_adrenaline_pickup)
	add_child(pickup)
	adrenaline_pickup = pickup
	_add_world_label("ADRENALINE SHOT", at + Vector2(-73, -52), Color("a8f6ee"), 15)


func _on_adrenaline_pickup(body: Node2D) -> void:
	if body != player or has_adrenaline or quiz_open:
		return
	has_adrenaline = true
	player.set("jump_velocity", -700.0)
	if is_instance_valid(adrenaline_pickup):
		adrenaline_pickup.queue_free()
	adrenaline_pickup = null
	hud_label.text = "ADRENALINE SHOT ACTIVE"
	_create_exit_door(Vector2(560, 470), "RETURN TO LEVEL 2  •  E", &"level2_return")


func _damage_player(amount: int) -> void:
	player_health = maxi(0, player_health - amount)
	_update_health_ui()
	if player_health == 0:
		player_health = PLAYER_MAX_HEALTH
		_update_health_ui()
		_handle_fall()


func _restart_boss_fight() -> void:
	_clear_seed_projectiles()
	_clear_viruses()
	if is_instance_valid(boss):
		boss.queue_free()
	player_health = PLAYER_MAX_HEALTH
	boss_health = BOSS_MAX_HEALTH
	boss_defeated = false
	quiz_open = false
	player.global_position = level_start_position
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(true)
	_create_boss(boss_kind)
	popup.hide()
	_update_health_ui()


func _respawn_before_phd() -> void:
	_clear_seed_projectiles()
	_clear_viruses()
	boss_room = false
	boss_defeated = false
	door_nearby = false
	player_health = PLAYER_MAX_HEALTH
	player.global_position = PHD_DOOR_RESPAWN_POSITION
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(true)
	quiz_open = false
	popup.hide()
	if is_instance_valid(player_camera):
		player_camera.reset_smoothing()
	_build_level_two(PHD_DOOR_RESPAWN_POSITION)
	door_nearby = true
	door_target = &"level2_finish"
	_update_health_ui()
	hud_label.text = "YOU DIED     BACK AT THE PHD DOOR — PRESS E TO RETRY"


func _restore_at_checkpoint() -> void:
	_hide_scalpel()
	player_health = PLAYER_MAX_HEALTH
	player.global_position = level_start_position
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(true)
	quiz_open = false
	popup.hide()
	_update_health_ui()


func _enter_next_level() -> void:
	_hide_scalpel()
	_clear_seed_projectiles()
	_clear_viruses()
	next_level = true
	boss_room = false
	boss_defeated = false
	door_nearby = false
	player.global_position = Vector2(-350, 510)
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(true)
	if is_instance_valid(player_camera):
		player_camera.reset_smoothing()
	level_start_position = player.global_position
	_build_level_two(player.global_position)


func _return_to_level_two() -> void:
	_hide_scalpel()
	_clear_seed_projectiles()
	_clear_viruses()
	boss_room = false
	boss_defeated = false
	door_nearby = false
	player.global_position = Vector2(700, 310)
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(true)
	if is_instance_valid(player_camera):
		player_camera.reset_smoothing()
	_build_level_two(player.global_position)


func _build_level_two(spawn_at: Vector2) -> void:
	for node in get_tree().get_nodes_in_group("room_content"):
		if node != player:
			node.queue_free()
	boss = null
	boss_collision_shape = null
	if has_adrenaline:
		player.set("jump_velocity", -700.0)
	else:
		player.set("jump_velocity", -470.0)
	player.global_position = spawn_at
	last_grounded_position = spawn_at
	if not next_level:
		level_start_position = spawn_at
	next_level = true
	boss_room = false
	_create_platform(Vector2(-350, 570), Vector2(170, 40), Color("31527a"))
	_create_platform(Vector2(-60, 475), Vector2(82, 20), Color("34758a"))
	_create_platform(Vector2(220, 390), Vector2(68, 20))
	_create_platform(Vector2(475, 480), Vector2(72, 20), Color("34758a"))
	_create_platform(Vector2(740, 345), Vector2(92, 20))
	# This ledge is deliberately out of reach until Karen's adrenaline power-up boosts jumps.
	_create_platform(Vector2(1035, 65), Vector2(90, 20), Color("34758a"))
	_create_platform(Vector2(1310, 225), Vector2(72, 20))
	# End-of-level ledges follow the alternating low-left / high-left / middle-right sketch.
	_create_platform(Vector2(1480, 520), Vector2(120, 20), Color("34758a"))
	_create_platform(Vector2(1620, 165), Vector2(120, 20))
	_create_platform(Vector2(1940, 330), Vector2(180, 20), Color("34758a"))
	if not phd_defeated:
		_create_exit_door(Vector2(1940, 254), "PHD FINAL BOSS  •  E", &"level2_finish")
	if not karen_defeated:
		_create_exit_door(Vector2(740, 269), "KAREN'S OFFICE  •  E", &"karen_boss")
	_add_world_label("LEVEL 2  •  RESEARCH WING", Vector2(-520, 390), Color("25839a"), 25)
	var mission_text := "CELL CULTURE LAB  •  BEAT KAREN FOR THE ADRENALINE SHOT" if not karen_defeated else "CELL CULTURE LAB  •  ADRENALINE SHOT ACQUIRED"
	if phd_defeated:
		mission_text = "RESEARCH WING CLEARED  •  FINAL EXAM PASSED"
	_add_world_label(mission_text, Vector2(-520, 426), Color("357080"), 17)
	if not has_adrenaline:
		var shot_marker := Sprite2D.new()
		shot_marker.name = "AdrenalineShotMarker"
		shot_marker.texture = ADRENALINE_TEXTURE
		shot_marker.position = Vector2(1035, 5)
		shot_marker.scale = Vector2(0.09, 0.09)
		shot_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shot_marker.add_to_group("room_content")
		add_child(shot_marker)
	hud_label.text = "LEVEL 2     A/D OR ARROWS: MOVE     SPACE: DOUBLE JUMP"
	boss_health_bar.hide()
	boss_health_label.hide()
	queue_redraw()


func _create_hud() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	var bar := PanelContainer.new()
	bar.position = Vector2(22, 18)
	bar.custom_minimum_size = Vector2(450, 148)
	bar.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.09, 0.17, 0.88), Color("35d8c2")))
	ui_layer.add_child(bar)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	bar.add_child(column)
	hud_label = Label.new()
	hud_label.text = "MEDICAL MISSION     A/D or arrows: move     SPACE: jump"
	hud_label.add_theme_color_override("font_color", Color("e6f5ff"))
	hud_label.add_theme_font_size_override("font_size", 17)
	column.add_child(hud_label)
	player_health_label = Label.new()
	player_health_label.add_theme_color_override("font_color", Color("baf7ec"))
	player_health_label.add_theme_font_size_override("font_size", 14)
	column.add_child(player_health_label)
	player_health_bar = _make_health_bar(PLAYER_MAX_HEALTH, Color("42d6a4"))
	column.add_child(player_health_bar)
	boss_health_label = Label.new()
	boss_health_label.add_theme_color_override("font_color", Color("ffd1d8"))
	boss_health_label.add_theme_font_size_override("font_size", 14)
	column.add_child(boss_health_label)
	boss_health_bar = _make_health_bar(BOSS_MAX_HEALTH, Color("ed5261"))
	column.add_child(boss_health_bar)
	boss_health_label.hide()
	boss_health_bar.hide()
	_update_health_ui()


func _make_health_bar(max_health: int, fill_color: Color) -> ProgressBar:
	var health_bar := ProgressBar.new()
	health_bar.min_value = 0
	health_bar.max_value = max_health
	health_bar.value = max_health
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(400, 15)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("26364e")
	background.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("background", background)
	return health_bar


func _update_health_ui() -> void:
	if player_health_bar != null:
		player_health_bar.value = player_health
		player_health_label.text = "PLAYER HEALTH  %d / %d" % [player_health, PLAYER_MAX_HEALTH]
	if boss_health_bar != null:
		boss_health_bar.value = boss_health
		var boss_label := "PHD FINAL BOSS"
		if boss_kind == &"apple":
			boss_label = "APPLE BOSS"
		elif boss_kind == &"karen":
			boss_label = "KAREN"
		boss_health_label.text = "%s  %d / %d" % [boss_label, boss_health, BOSS_MAX_HEALTH]


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
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


func _show_answer_buttons() -> void:
	prompt_label.text += "\n\n[%s] %s" % [questions[current_question]["subject"], questions[current_question]["prompt"]]
	for child in answers_box.get_children():
		child.queue_free()
	if questions[current_question].get("type", "mcq") == "free_response":
		var reveal_button := Button.new()
		reveal_button.text = "Reveal answer"
		reveal_button.custom_minimum_size = Vector2(440, 42)
		reveal_button.pressed.connect(_reveal_free_response)
		answers_box.add_child(reveal_button)
		popup.show()
		return
	for i in range(questions[current_question]["answers"].size()):
		var button := Button.new()
		button.text = questions[current_question]["answers"][i]
		button.custom_minimum_size = Vector2(440, 42)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_answer_selected.bind(i))
		answers_box.add_child(button)
	popup.show()


func _reveal_free_response() -> void:
	feedback_label.text = "Answer: " + str(questions[current_question]["answer"])
	_show_quiz_continue()


func _answer_selected(answer_index: int) -> void:
	var correct_index := int(questions[current_question]["correct"])
	var correct_answer: String = questions[current_question]["answers"][correct_index]
	if answer_index == correct_index:
		questions_answered += 1
		hud_label.text = "MEDICAL MISSION     QUESTIONS ANSWERED: %d" % questions_answered
		feedback_label.add_theme_color_override("font_color", Color("91f3df"))
		feedback_label.text = "Correct! " + str(questions[current_question]["explain"])
	else:
		_damage_player(3)
		if player_health == PLAYER_MAX_HEALTH and quiz_open:
			return
		feedback_label.add_theme_color_override("font_color", Color("ff5d68"))
		feedback_label.text = "You're incorrect. The correct answer is: " + correct_answer
	_show_quiz_continue()


func _show_quiz_continue() -> void:
	for child in answers_box.get_children():
		child.queue_free()
	var continue_button := Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(440, 42)
	continue_button.pressed.connect(_resume_after_quiz)
	answers_box.add_child(continue_button)


func _resume_after_quiz() -> void:
	popup.hide()
	quiz_open = false
	player.global_position = last_grounded_position
	player.velocity = Vector2.ZERO
	player.launch_horizontal_time = 0.0
	player.set_physics_process(true)


