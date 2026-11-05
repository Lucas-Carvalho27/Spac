extends Control

# Editor da nave, com duas abas:
# - Chassi: chão, armas e motores num grid; é o que mexe na física da nave
# - Interior: cada quadradinho de chassi vira 2x2 quadradinhos de 1/4; paredes, paredes reforçadas,
#   blindagem e componentes vão neles (por enquanto o interior ainda não muda nada no jogo)

const ShipParts = preload("res://ship/ship_parts.gd")
const ShipArt = preload("res://ship/ship_art.gd")
const ShipInterior = preload("res://ship/ship_interior.gd")
const ShipSave = preload("res://ship/ship_save.gd")

const RADIUS := 10 # o grid vai de -10 a 10 (21x21 quadradinhos de chassi)
const EDIT_CELL := 24.0 # tamanho do quadradinho de chassi na aba Chassi, em px
const ERASE := "erase"
const SIDE_NAMES := ["frente", "direita", "trás", "esquerda"]
const CHASSIS := "chassis"
const INTERIOR := "interior"
const ROOM_COLORS := [Color(0.3, 0.6, 0.95), Color(0.4, 0.85, 0.5), Color(0.95, 0.75, 0.3), Color(0.85, 0.45, 0.7), Color(0.55, 0.5, 0.95), Color(0.3, 0.85, 0.85)]

var design := []
var interior := {}
var mode := CHASSIS
var selected := "floor" # peça do chassi (ver ShipParts.PARTS) ou ERASE
var selected_inside := "wall" # bloco do interior (ver ShipInterior.BLOCKS) ou ERASE
var brush_dir := 0 # direção da próxima arma/motor colocado
var hover_pos := Vector2.ZERO # posição do mouse no grid, em quadradinhos de chassi (com fração)
var hovered := Vector2i.ZERO
var hovering := false
var hover_sub := Vector2i.ZERO # quadradinho interno embaixo do mouse

# Visão: quantos px tem um quadradinho de chassi e qual ponto do grid fica no meio da área do grid
var view_cell := EDIT_CELL
var view_center := Vector2.ZERO

# Só na aba Interior (o chassi não muda enquanto ela está aberta)
var subs := {} # quadradinho interno -> livre, casco ou trancado
var room_of := {} # quadradinho interno -> número da sala

var stats_label: Label
var message_label: Label
var chassis_box: VBoxContainer
var interior_box: VBoxContainer
var tab_buttons := {}

func _ready() -> void:
	_build_ui()

func open() -> void:
	if visible:
		return
	design = _player().design.duplicate(true)
	interior = _player().interior.duplicate(true)
	show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_mode(mode)

func close() -> void:
	if not visible:
		return
	_player().apply_design(design, interior)
	ShipSave.save_ship(design, interior)
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

	# Título com o botão de voltar do lado, para ele nunca sumir embaixo do painel
	var title_row := HBoxContainer.new()
	panel.add_child(title_row)
	var title := Label.new()
	title.text = "Editor da nave"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var done := Button.new()
	done.text = "Voltar (Tab)"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(close)
	title_row.add_child(done)

	var tabs := HBoxContainer.new()
	panel.add_child(tabs)
	var tab_group := ButtonGroup.new()
	for entry in [[CHASSIS, "Chassi"], [INTERIOR, "Interior"]]:
		var tab := Button.new()
		tab.text = entry[1]
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.button_pressed = entry[0] == mode
		tab.pressed.connect(func() -> void: _set_mode(entry[0]))
		tabs.add_child(tab)
		tab_buttons[entry[0]] = tab

	# Aba Chassi
	chassis_box = VBoxContainer.new()
	panel.add_child(chassis_box)
	var parts := []
	for type in ShipParts.PARTS:
		var size: Vector2i = ShipParts.PARTS[type].size
		parts.append([type, "%s %dx%d" % [ShipParts.PARTS[type].name, size.y, size.x], ""])
	parts.append([ERASE, "Apagar", ""])
	chassis_box.add_child(_tool_grid(parts, selected, func(type: String) -> void: selected = type))
	var turn_button := Button.new()
	turn_button.text = "Girar peça (R)"
	turn_button.focus_mode = Control.FOCUS_NONE
	turn_button.pressed.connect(_rotate_brush)
	chassis_box.add_child(turn_button)
	chassis_box.add_child(_help("Clique: coloca (arraste para pintar)\nPeça em cima de chão troca o chão\nClique de novo numa arma ou motor: gira\nBotão direito: apaga"))

	# Aba Interior
	interior_box = VBoxContainer.new()
	interior_box.visible = false
	panel.add_child(interior_box)
	var inside := []
	for type in ShipInterior.BLOCKS:
		inside.append([type, ShipInterior.BLOCKS[type].short, ShipInterior.BLOCKS[type].group])
	inside.append([ERASE, "Apagar", ""])
	interior_box.add_child(_tool_grid(inside, selected_inside, func(type: String) -> void: selected_inside = type))
	interior_box.add_child(_help("Clique: coloca no quadradinho (arraste para pintar)\nO casco é a camada de fora: dá para trocar por parede reforçada ou blindagem\nBotão direito: apaga"))

	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 14)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(stats_label)

	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(message_label)

# Botões de ferramenta em 2 colunas; cada entrada é [tipo, texto, sistema (pinta o texto na cor dele)]
func _tool_grid(entries: Array, current: String, pick: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	var group := ButtonGroup.new()
	for entry in entries:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = entry[0] == current
		if entry[2] != "":
			button.add_theme_color_override("font_color", ShipArt.GROUP_COLORS[entry[2]])
			button.tooltip_text = ShipInterior.BLOCKS[entry[0]].name
		button.pressed.connect(func() -> void:
			pick.call(entry[0])
			queue_redraw())
		grid.add_child(button)
	return grid

func _help(text: String) -> Label:
	var help := Label.new()
	help.text = text
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.7)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 260
	return help

func _set_mode(new_mode: String) -> void:
	mode = new_mode
	for key in tab_buttons:
		tab_buttons[key].set_pressed_no_signal(key == mode)
		tab_buttons[key].modulate = Color.WHITE if key == mode else Color(1, 1, 1, 0.5)
	chassis_box.visible = mode == CHASSIS
	interior_box.visible = mode == INTERIOR
	message_label.text = ""
	if mode == INTERIOR:
		subs = ShipInterior.sub_cells(design)
		_fit_view()
	else:
		view_cell = EDIT_CELL
		view_center = Vector2.ZERO
	_refresh()

# No interior, aproxima a visão para a nave encher o grid (quadradinhos internos maiores para clicar)
func _fit_view() -> void:
	var low := Vector2(INF, INF)
	var high := -low
	for cell in ShipParts.occupancy(design):
		low = low.min(Vector2(cell))
		high = high.max(Vector2(cell))
	var span := high - low + Vector2.ONE * 3.0
	view_cell = clampf((RADIUS * 2 + 1) * EDIT_CELL / maxf(span.x, span.y), EDIT_CELL, EDIT_CELL * 2.0)
	view_center = (low + high) * 0.5

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
		KEY_R when visible and mode == CHASSIS:
			_rotate_brush()
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var before = _target()
		_hover(event.position)
		# Arrastando com o botão apertado pinta (ou apaga) vários de uma vez
		if _target() != before:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_use(_erasing(), false)
			elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_use(true, false)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		_hover(event.position)
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_use(_erasing(), true)
			MOUSE_BUTTON_RIGHT:
				_use(true, true)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mode == CHASSIS:
					_rotate_brush()

# O que está embaixo do mouse na aba atual (para saber quando o arrasto chegou numa coisa nova)
func _target():
	return hovered if mode == CHASSIS else hover_sub

func _erasing() -> bool:
	return (selected if mode == CHASSIS else selected_inside) == ERASE

func _hover(pos: Vector2) -> void:
	hover_pos = (pos - _grid_center()) / view_cell + view_center
	hovered = Vector2i(hover_pos.round())
	hovering = absi(hovered.x) <= RADIUS and absi(hovered.y) <= RADIUS
	hover_sub = Vector2i(((hover_pos + Vector2(0.5, 0.5)) * 2.0).floor())

func _rotate_brush() -> void:
	brush_dir = (brush_dir + 1) % 4
	queue_redraw()

func _use(erase: bool, click: bool) -> void:
	if not hovering:
		return
	if click:
		message_label.text = ""
	if mode == INTERIOR:
		_use_inside(erase, click)
	else:
		if erase:
			_erase(click)
		else:
			_place(click)
		# Mudou o chassi: some o que estava dentro de chão apagado ou embaixo de arma/motor novo
		interior = ShipInterior.cleaned(design, interior)
	_refresh()

# ---------- Aba Chassi ----------

# A peça que seria colocada agora: peça grande fica centrada no mouse; a arma tem a base no mouse
func _brush_part() -> Dictionary:
	var size: Vector2i = ShipParts.PARTS[selected].size
	var cell := hovered
	if size.x == size.y:
		cell = Vector2i((hover_pos - Vector2.ONE * (size.x - 1) * 0.5).round())
	return {"type": selected, "cell": cell, "dir": brush_dir}

func _place(click: bool) -> void:
	var at = ShipParts.occupancy(design).get(hovered)
	# Clicar numa peça do mesmo tipo gira ela (chão quadrado não tem o que girar)
	if at != null and design[at].type == selected:
		var size: Vector2i = ShipParts.PARTS[selected].size
		if click and (ShipParts.kind(design[at]) != ShipParts.FLOOR or size.x != size.y):
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

# A nave com a peça colocada, ou [] se não dá (e explica na mensagem). O chão embaixo da peça sai;
# se a peça cobre só parte de uma placa grande de chão, o resto da placa vira chão 1x1.
func _with_part(base: Array, part: Dictionary, report: bool) -> Array:
	var occupied := ShipParts.occupancy(base)
	var covered := ShipParts.cells(part)
	var touches := false
	var under := {} # índices das peças de chão embaixo da nova
	for c in covered:
		if absi(c.x) > RADIUS or absi(c.y) > RADIUS:
			return _fail("Não cabe no grid.", report)
		if occupied.has(c):
			if ShipParts.kind(base[occupied[c]]) != ShipParts.FLOOR:
				return _fail("Tem outra peça no caminho.", report)
			under[occupied[c]] = true
			touches = true
		for n in ShipParts.NEIGHBORS:
			if occupied.has(c + n):
				touches = true
	if not touches:
		return _fail("A peça tem que encostar na nave.", report)
	# Chão em cima de chão só troca placas que ficam inteiras embaixo (não corta placa grande)
	if ShipParts.kind(part) == ShipParts.FLOOR and not under.is_empty():
		var all_floor := covered.all(func(c): return occupied.has(c))
		var cuts := under.keys().any(func(i): return ShipParts.cells(base[i]).any(func(c): return not covered.has(c)))
		if all_floor and cuts:
			return _fail("Já tem chão aqui.", report)
	var result := []
	for i in base.size():
		if not under.has(i):
			result.append(base[i])
			continue
		for c in ShipParts.cells(base[i]):
			if not covered.has(c):
				result.append({"type": "floor", "cell": c, "dir": 0})
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

# ---------- Aba Interior ----------

# Apagar no casco reforçado volta a ser casco normal (o casco em si não sai)
func _use_inside(erase: bool, click: bool) -> void:
	if erase:
		interior.blocks.erase(hover_sub)
		return
	var problem := ShipInterior.block_problem(subs, hover_sub, selected_inside)
	if problem == "":
		interior.blocks[hover_sub] = selected_inside
	elif click:
		message_label.text = problem

# ---------- Painel e desenho ----------

func _refresh() -> void:
	if mode == INTERIOR:
		room_of = ShipInterior.rooms(subs, interior)
		stats_label.text = _interior_stats()
	else:
		stats_label.text = _chassis_stats()
	queue_redraw()

func _chassis_stats() -> String:
	var player := _player()
	var warnings := ""
	var report := ShipParts.push_report(design, player.base_thrust, player.engine_power, player.gyro_torque)
	var accels := []
	for side in 4:
		accels.append("%s %d" % [SIDE_NAMES[side], report[side].accel])
		var torque: float = report[side].torque
		if absf(torque) > 1.0:
			warnings += "\nPara %s, o bico puxa p/ %s" % [SIDE_NAMES[side], "direita" if torque > 0.0 else "esquerda"]
			if not report[side].holdable:
				warnings += " (forte demais: roda sem controle)"
	var text := "Peso: %.1f\nAceleração: %s\n" % [ShipParts.total_mass(design), ", ".join(accels)]

	# Meia-volta: motores longe do centro de massa ajudam a girar
	var right := ShipParts.half_turn_time(design, player.engine_power, player.gyro_torque, player.max_turn_speed, player.rotation_drag, 1.0)
	var left := ShipParts.half_turn_time(design, player.engine_power, player.gyro_torque, player.max_turn_speed, player.rotation_drag, -1.0)
	if absf(right - left) < 0.05:
		text += "Meia-volta: %s\n" % _seconds(right)
	else:
		text += "Meia-volta: %s pela direita, %s pela esquerda\n" % [_seconds(right), _seconds(left)]
	if not design.any(func(p): return ShipParts.kind(p) == ShipParts.WEAPON):
		warnings += "\nSem arma: a nave não atira."
	return text + warnings

func _interior_stats() -> String:
	var rooms := {}
	for sub in room_of:
		rooms[room_of[sub]] = true
	var counts := {}
	var hull_upgrades := 0
	for sub in interior.blocks:
		var type: String = interior.blocks[sub]
		counts[type] = counts.get(type, 0) + 1
		if subs.get(sub) == ShipInterior.HULL:
			hull_upgrades += 1
	var hull := subs.values().count(ShipInterior.HULL)
	var text := "(o interior ainda não muda nada no jogo)\nSalas: %d\nCasco: %d quadradinhos (%d reforçados)\n" % [rooms.size(), hull, hull_upgrades]
	var listed := []
	for type in ShipInterior.BLOCKS:
		if counts.has(type):
			listed.append("%s %d" % [ShipInterior.BLOCKS[type].short, counts[type]])
	return text + ("Blocos: " + ", ".join(listed) if not listed.is_empty() else "Nenhum bloco colocado ainda")

func _seconds(time: float) -> String:
	return "%.2f s" % time if time < 10.0 else "não consegue girar"

func _grid_center() -> Vector2:
	return Vector2(size.x * 0.5 + 130.0, size.y * 0.5)

# Ponto do grid (em quadradinhos de chassi) na tela
func _cell_pos(cell: Vector2) -> Vector2:
	return _grid_center() + (cell - view_center) * view_cell

func _grid_rect(box: Rect2) -> Rect2:
	return Rect2(_cell_pos(box.position), box.size * view_cell)

# Quadradinho interno na tela
func _sub_rect(sub: Vector2i) -> Rect2:
	return ShipArt.sub_rect(sub, _grid_center(), view_center, view_cell)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.09, 0.95))
	if mode == INTERIOR:
		_draw_interior()
	else:
		_draw_chassis()

	# Indicador da frente da nave
	var edge := _grid_center() + Vector2((RADIUS + 0.5) * EDIT_CELL, 0)
	draw_string(get_theme_default_font(), edge + Vector2(10, -14), "frente", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
	draw_colored_polygon(PackedVector2Array([edge + Vector2(12, -6), edge + Vector2(12, 6), edge + Vector2(24, 0)]), Color(1, 1, 1, 0.6))

func _draw_chassis() -> void:
	var half := Vector2.ONE * view_cell * 0.5
	for x in range(-RADIUS, RADIUS + 1):
		for y in range(-RADIUS, RADIUS + 1):
			draw_rect(Rect2(_cell_pos(Vector2(x, y)) - half, half * 2.0), Color(1, 1, 1, 0.07), false, 1.0)

	ShipArt.draw_ship(self, design, _grid_center(), view_center, view_cell)

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
		ShipArt.draw_ship(self, [part], _grid_center(), view_center, view_cell, {}, 0.0, 0.5)
		if _with_part(design, part, false).is_empty():
			draw_rect(_grid_rect(ShipParts.bounds(part)), Color(1, 0.3, 0.3, 0.9), false, 2.0)

func _draw_interior() -> void:
	ShipArt.draw_interior(self, design, interior, subs, room_of, _grid_center(), view_center, view_cell, ROOM_COLORS)

	# Prévia embaixo do mouse
	if not hovering or not subs.has(hover_sub):
		return
	var rect := _sub_rect(hover_sub)
	if selected_inside == ERASE:
		if interior.blocks.has(hover_sub):
			draw_rect(rect, Color(1, 0.3, 0.3, 0.9), false, 2.0)
		return
	var allowed := ShipInterior.block_problem(subs, hover_sub, selected_inside) == ""
	if allowed:
		ShipArt.draw_block_preview(self, selected_inside, rect, 0.6)
	draw_rect(rect, Color(1, 1, 1, 0.8) if allowed else Color(1, 0.3, 0.3, 0.9), false, 2.0)
