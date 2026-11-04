extends PanelContainer

# Painel para testar: cada barra mexe numa variável da Player na hora, com o jogo rodando.
# O que for mudado fica salvo em user://ajustes.json; "Restaurar padrão" volta aos valores do Inspector.

const ShipParts = preload("res://ship/ship_parts.gd")

const SAVE_PATH := "user://ajustes.json"

# propriedade da Player, nome, mínimo, máximo, passo, unidade
const SETTINGS := [
	["max_turn_speed", "Giro máximo", 30.0, 400.0, 5.0, "graus/s"],
	["gyro_torque", "Força de giro própria", 0.0, 600000.0, 5000.0, ""],
	["rotation_drag", "Resistência do ar no giro", 0.0, 6.0, 0.1, ""],
	["base_thrust", "Força básica (sem motor)", 0.0, 50000.0, 500.0, ""],
	["engine_power", "Força dos motores", 0.0, 3.0, 0.05, "x"],
	["max_speed", "Velocidade máxima", 100.0, 1200.0, 10.0, "px/s"],
	["stop_time", "Tempo para parar", 0.1, 5.0, 0.1, "s"],
	["brake_curve", "Curva do freio", 1.0, 6.0, 0.1, ""],
	["aim_speed", "Velocidade da mira", 100.0, 3000.0, 50.0, "px/s"],
	["cursor_turn_speed", "Giro do anel na borda", 90.0, 3600.0, 30.0, "graus/s"],
	["aim_dead_zone", "Círculo da mira (mínimo)", 20.0, 200.0, 5.0, "px"],
	["fire_rate", "Tiros por segundo", 1.0, 30.0, 1.0, ""],
]

var defaults := {}
var sliders := {}
var labels := {}
var info_label: Label
var refresh_timer := 0.0

func _ready() -> void:
	hide()
	for setting in SETTINGS:
		defaults[setting[0]] = _player().get(setting[0])
	_load()
	_build_ui()

func toggle() -> void:
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_HIDDEN
	_refresh_info()

func _player() -> Node:
	return get_tree().get_first_node_in_group("player")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		toggle()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	# Fechar o editor de nave esconde o mouse; com os ajustes abertos ele tem que aparecer
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_timer -= delta
	if refresh_timer <= 0.0:
		refresh_timer = 0.25
		_refresh_info()

func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)

	var title := Label.new()
	title.text = "Ajustes (F1)"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.modulate = Color(0.7, 0.9, 1)
	box.add_child(info_label)

	for setting in SETTINGS:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		box.add_child(label)
		labels[setting[0]] = label

		var slider := HSlider.new()
		slider.min_value = setting[2]
		slider.max_value = setting[3]
		slider.step = setting[4]
		slider.value = _player().get(setting[0])
		slider.focus_mode = Control.FOCUS_NONE # para W/A/S/D e setas continuarem mexendo a nave
		slider.custom_minimum_size.x = 280
		slider.value_changed.connect(func(value: float) -> void: _change_setting(setting, value))
		box.add_child(slider)
		sliders[setting[0]] = slider
		_update_label(setting)

	var reset := Button.new()
	reset.text = "Restaurar padrão"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_reset)
	box.add_child(reset)

func _change_setting(setting: Array, value: float) -> void:
	_player().set(setting[0], value)
	_update_label(setting)
	_save()
	_refresh_info()

func _update_label(setting: Array) -> void:
	var value: float = _player().get(setting[0])
	var text := "%d" % value if setting[4] >= 1.0 else "%.2f" % value
	labels[setting[0]].text = "%s: %s %s" % [setting[1], text, setting[5]]

# O resultado na nave atual, para ver o efeito do ajuste
func _refresh_info() -> void:
	if info_label == null:
		return
	var player := _player()
	var report := ShipParts.push_report(player.design, player.base_thrust, player.engine_power, player.gyro_torque)
	var turn := ShipParts.half_turn_time(player.design, player.engine_power, player.gyro_torque, player.max_turn_speed, player.rotation_drag, 1.0)
	var turn_text := "%.2f s" % turn if turn < 10.0 else "não consegue"
	info_label.text = "Nave atual: meia-volta %s\nacelera %d para frente, %d para trás" % [turn_text, report[0].accel, report[2].accel]

func _reset() -> void:
	for setting in SETTINGS:
		sliders[setting[0]].value = defaults[setting[0]]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# Só salva o que é diferente do padrão, para mudanças futuras no Inspector valerem no resto
func _save() -> void:
	var changed := {}
	for setting in SETTINGS:
		var value = _player().get(setting[0])
		if not is_equal_approx(value, defaults[setting[0]]):
			changed[setting[0]] = value
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(changed))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (saved is Dictionary):
		return
	for setting in SETTINGS:
		if saved.has(setting[0]):
			_player().set(setting[0], float(saved[setting[0]]))
