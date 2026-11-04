extends Control

const ShipParts = preload("res://ship/ship_parts.gd")
const ShipArt = preload("res://ship/ship_art.gd")

const RADIUS := 10 # o grid vai de -10 a 10 (21x21 quadradinhos)
const EDIT_CELL := 24.0 # tamanho do quadradinho no editor, em px
const ERASE := "erase"
const SIDE_NAMES := ["frente", "direita", "trás", "esquerda"]

var design := []
var selected := "floor" # tipo de peça (ver ShipParts.PARTS) ou ERASE
var brush_dir := 0 # direção da próxima arma/motor colocado
var hover_pos := Vector2.ZERO # posição do mouse no grid, em quadradinhos (com fração)
var hovered := Vector2i.ZERO
var hovering := false

var stats_label: Label
var message_label: Label

func _ready() -> void:
	_build_ui()

func open() -> void:
	if visible:
		return
	design = _player().design.duplicate(true)
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	message_label.text = ""
	_refresh()

func close() -> void:
	if not visible:
		return
	_player().apply_design(design)
	ShipParts.save_design(design)
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _player() -> Node:
	return get_tree().get_first_node_in_group("player")

func _build_ui() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(24, 20)
	panel.custom_minimum_size.x = 260
	panel.add_theme_constant_override("separation", 6)
	add_child(panel)

	var title := Label.new()
	title.text = "Editor da nave"
	title.add_theme_font_size_override("font_size", 22)
	panel.add_child(title)

	var tools := GridContainer.new()
	tools.columns = 2
	panel.add_child(tools)
	var group := ButtonGroup.new()
	var entries := []
	for type in ShipParts.PARTS:
		var size: Vector2i = ShipParts.PARTS[type].size
		entries.append([type, "%s %dx%d" % [ShipParts.PARTS[type].name, size.y, size.x]])
	entries.append([ERASE, "Apagar"])
	for entry in entries:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = entry[0] == selected
		button.pressed.connect(func() -> void:
			selected = entry[0]
			queue_redraw())
		tools.add_child(button)

	var turn_button := Button.new()
	turn_button.text = "Girar peça (R)"
	turn_button.focus_mode = Control.FOCUS_NONE
	turn_button.pressed.connect(_rotate_brush)
	panel.add_child(turn_button)

	var help := Label.new()
	help.text = "Clique: coloca (arraste para pintar)\nPeça em cima de chão troca o chão\nClique de novo numa arma ou motor: gira\nBotão direito: apaga"
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.7)
	panel.add_child(help)

	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 14)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(stats_label)

	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(message_label)

	var done := Button.new()
	done.text = "Voltar ao jogo (Tab)"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	panel.add_child(done)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_TAB:
			if visible:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE when visible:
			close()
			get_viewport().set_input_as_handled()
		KEY_R when visible:
			_rotate_brush()
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var before := hovered
		_hover(event.position)
		# Arrastando com o botão apertado pinta (ou apaga) vários quadradinhos
		if hovered != before:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_use(selected == ERASE, false)
			elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_use(true, false)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		_hover(event.position)
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_use(selected == ERASE, true)
			MOUSE_BUTTON_RIGHT:
				_use(true, true)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				_rotate_brush()

func _hover(pos: Vector2) -> void:
	hover_pos = (pos - _grid_center()) / EDIT_CELL
	hovered = Vector2i(hover_pos.round())
	hovering = absi(hovered.x) <= RADIUS and absi(hovered.y) <= RADIUS

func _rotate_brush() -> void:
	brush_dir = (brush_dir + 1) % 4
	queue_redraw()

# A peça que seria colocada agora: peça grande fica centrada no mouse; a arma tem a base no mouse
func _brush_part() -> Dictionary:
	var size: Vector2i = ShipParts.PARTS[selected].size
	var cell := hovered
	if size.x == size.y:
		cell = Vector2i((hover_pos - Vector2.ONE * (size.x - 1) * 0.5).round())
	return {"type": selected, "cell": cell, "dir": brush_dir}

func _use(erase: bool, click: bool) -> void:
	if not hovering:
		return
	if click:
		message_label.text = ""
	if erase:
		_erase(click)
	else:
		_place(click)
	_refresh()

func _place(click: bool) -> void:
	var at = ShipParts.occupancy(design).get(hovered)
	# Clicar numa peça do mesmo tipo gira ela
	if at != null and design[at].type == selected:
		if click and ShipParts.kind(design[at]) != ShipParts.FLOOR:
			_rotate_part(at)
		return
	var result := _with_part(design, _brush_part(), click)
	if not result.is_empty():
		design = result

func _rotate_part(index: int) -> void:
	var others := design.duplicate()
	others.remove_at(index)
	var turned: Dictionary = design[index].duplicate()
	turned.dir = (turned.dir + 1) % 4
	var result := _with_part(others, turned, true)
	if not result.is_empty():
		design = result

# A nave com a peça colocada (o chão embaixo dela sai), ou [] se não dá (e explica na mensagem)
func _with_part(base: Array, part: Dictionary, report: bool) -> Array:
	var occupied := ShipParts.occupancy(base)
	var covered := ShipParts.cells(part)
	var touches := false
	for c in covered:
		if absi(c.x) > RADIUS or absi(c.y) > RADIUS:
			return _fail("Não cabe no grid.", report)
		if occupied.has(c):
			if ShipParts.kind(base[occupied[c]]) != ShipParts.FLOOR:
				return _fail("Tem outra peça no caminho.", report)
			touches = true
		for n in ShipParts.NEIGHBORS:
			if occupied.has(c + n):
				touches = true
	if not touches:
		return _fail("A peça tem que encostar na nave.", report)
	var result := base.filter(func(p): return not (ShipParts.kind(p) == ShipParts.FLOOR and covered.has(p.cell)))
	result.append(part)
	if not ShipParts.is_in_one_piece(result):
		return _fail("Não dá: a nave ia se partir em duas.", report)
	return result

func _fail(text: String, report: bool) -> Array:
	if report:
		message_label.text = text
	return []

func _erase(click: bool) -> void:
	var at = ShipParts.occupancy(design).get(hovered)
	if at == null:
		return
	if design.size() == 1:
		message_label.text = "A nave precisa de pelo menos uma peça."
		return
	var result := design.duplicate()
	result.remove_at(at)
	if not ShipParts.is_in_one_piece(result):
		if click:
			message_label.text = "Não dá: a nave ia se partir em duas."
		return
	design = result

func _refresh() -> void:
	var player := _player()
	var text := "Peso: %.1f\nAceleração para cada lado:\n" % ShipParts.total_mass(design)
	var warnings := ""
	var report := ShipParts.push_report(design, player.base_thrust, player.engine_power, player.gyro_torque)
	for side in 4:
		text += "   %s: %d\n" % [SIDE_NAMES[side], report[side].accel]
		var torque: float = report[side].torque
		if absf(torque) > 1.0:
			warnings += "\nAcelerando para %s, o bico vira para a %s" % [SIDE_NAMES[side], "direita" if torque > 0.0 else "esquerda"]
			if not report[side].holdable:
				warnings += " (forte demais: a nave vai rodar sem controle)"

	# Meia-volta: motores longe do centro de massa ajudam a girar
	var right := ShipParts.half_turn_time(design, player.engine_power, player.gyro_torque, player.max_turn_speed, player.rotation_drag, 1.0)
	var left := ShipParts.half_turn_time(design, player.engine_power, player.gyro_torque, player.max_turn_speed, player.rotation_drag, -1.0)
	if absf(right - left) < 0.05:
		text += "Meia-volta: %s\n" % _seconds(right)
	else:
		text += "Meia-volta: %s pela direita, %s pela esquerda\n" % [_seconds(right), _seconds(left)]
	if not design.any(func(p): return ShipParts.kind(p) == ShipParts.WEAPON):
		warnings += "\nSem arma: a nave não atira."
	stats_label.text = text + warnings
	queue_redraw()

func _seconds(time: float) -> String:
	return "%.2f s" % time if time < 10.0 else "não consegue girar"

func _grid_center() -> Vector2:
	return Vector2(size.x * 0.5 + 130.0, size.y * 0.5)

func _cell_pos(cell: Vector2) -> Vector2:
	return _grid_center() + cell * EDIT_CELL

func _grid_rect(box: Rect2) -> Rect2:
	return Rect2(_cell_pos(box.position), box.size * EDIT_CELL)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.09, 0.95))

	var half := Vector2.ONE * EDIT_CELL * 0.5
	for x in range(-RADIUS, RADIUS + 1):
		for y in range(-RADIUS, RADIUS + 1):
			draw_rect(Rect2(_cell_pos(Vector2(x, y)) - half, half * 2.0), Color(1, 1, 1, 0.07), false, 1.0)

	# Indicador da frente da nave
	var edge := _cell_pos(Vector2(RADIUS + 0.5, 0))
	draw_string(get_theme_default_font(), edge + Vector2(10, -14), "frente", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
	draw_colored_polygon(PackedVector2Array([edge + Vector2(12, -6), edge + Vector2(12, 6), edge + Vector2(24, 0)]), Color(1, 1, 1, 0.6))

	ShipArt.draw_ship(self, design, _grid_center(), Vector2.ZERO, EDIT_CELL)

	# Linha de força de cada motor: se passa pelo centro de massa a nave vai reto (verde),
	# senão ela torce a nave (laranja)
	var com := ShipParts.center_of_mass(design)
	for part in design:
		if ShipParts.kind(part) != ShipParts.ENGINE:
			continue
		var from := ShipParts.center_of(part)
		var d := ShipParts.dir_vector(part.dir)
		var straight := absf((com - from).cross(d)) < 0.05
		var reach := RADIUS + 0.5 - from.dot(d)
		var color := Color(0.4, 1, 0.5, 0.7) if straight else Color(1, 0.6, 0.2, 0.8)
		draw_dashed_line(_cell_pos(from), _cell_pos(from + d * reach), color, 2.0, 6.0)

	# Centro de massa
	var com_pos := _cell_pos(com)
	draw_circle(com_pos, 8.0, Color.WHITE)
	draw_circle(com_pos, 5.0, Color(0.1, 0.1, 0.1))
	draw_circle(com_pos, 2.0, Color.WHITE)
	draw_string(get_theme_default_font(), com_pos + Vector2(12, -10), "centro de massa", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))

	# Prévia embaixo do mouse
	if not hovering:
		return
	var at = ShipParts.occupancy(design).get(hovered)
	if selected == ERASE:
		if at != null:
			draw_rect(_grid_rect(ShipParts.bounds(design[at])), Color(1, 0.3, 0.3, 0.9), false, 2.0)
	elif at != null and design[at].type == selected:
		draw_rect(_grid_rect(ShipParts.bounds(design[at])), Color(1, 1, 1, 0.8), false, 2.0)
	else:
		var part := _brush_part()
		ShipArt.draw_ship(self, [part], _grid_center(), Vector2.ZERO, EDIT_CELL, {}, 0.0, 0.5)
		if _with_part(design, part, false).is_empty():
			draw_rect(_grid_rect(ShipParts.bounds(part)), Color(1, 0.3, 0.3, 0.9), false, 2.0)
