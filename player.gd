extends CharacterBody2D

const ShipParts = preload("res://ship_parts.gd")
const ShipArt = preload("res://ship_art.gd")

@export var base_thrust := 13000.0 # força básica em todas as direções, mesmo sem motor
@export var engine_power := 1.0 # multiplica a força de todos os motores (a força de cada um está em ship_parts.gd)
@export var max_speed := 450.0
@export var stop_time := 1.5 # tempo máximo para parar depois de soltar as teclas (s)
@export var brake_curve := 2.0 # 1 = freio constante; maior = começa mais fraco e aperta mais no final
@export var aim_speed := 600.0 # velocidade com que a mira real anda até o mouse (px/s)
@export var aim_dead_zone := 50.0 # raio mínimo do círculo em volta da nave onde a mira não entra (px)
@export var cursor_turn_speed := 900.0 # quão rápido o anel da mira dá a volta pela borda do círculo (graus/s)
@export var max_turn_speed := 150.0 # velocidade máxima de giro (graus por segundo)
@export var gyro_torque := 170000.0 # força de giro própria da nave, sem motores; nave pesada gira mais devagar
@export var rotation_drag := 1.0 # resistência do ar no giro: quanto maior, mais rápido o giro morre sem força (por segundo)
@export var bullet_scene: PackedScene
@export var fire_rate := 8.0 # tiros por segundo segurando o botão

# A nave montada no editor: lista de peças (ver ship_parts.gd)
var design := []
var mass := 1.0
var inertia := 1.0
var center := Vector2.ZERO # centro de massa, em quadradinhos; a nave gira em volta dele
var ship_radius := 0.0 # distância do centro de massa até a ponta mais longe da nave (px)
var cursor_offset := Vector2.RIGHT * 100.0 # onde o anel da mira está, em relação à nave
var ship_front := 0.0 # distância do centro de massa até a frente da nave (px), onde o laser começa
var laser_length := 100.0 # até onde vai o laser do bico, a partir do centro de massa (px)
var angular_velocity := 0.0
var engine_throttle := {} # índice da peça -> quanto o motor está ligado agora (0 a 1), para desenhar o fogo

# Para onde a nave está tentando virar (vai caminhando até o anel da mira)
var aim_point := Vector2.ZERO

# Por eixo (x e y): há quanto tempo está sem empuxo e a velocidade quando o empuxo parou
var coast_time := Vector2.ZERO
var coast_speed := Vector2.ZERO

var shoot_cooldown := 0.0
var firing := false

# Camadas de desenho: o casco só é redesenhado quando a nave muda; fogo, laser e anel a cada quadro
var hull_layer := Node2D.new()
var effects_layer := Node2D.new()

func _ready() -> void:
	aim_point = global_position + global_transform.x * 100.0
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hull_layer.draw.connect(_draw_hull_layer)
	effects_layer.draw.connect(_draw_effects_layer)
	add_child(hull_layer)
	add_child(effects_layer)
	apply_design(ShipParts.load_design())

# Monta a nave (peso, giro e colisão) a partir do desenho do editor
func apply_design(new_design: Array) -> void:
	design = new_design
	mass = ShipParts.total_mass(design)
	center = ShipParts.center_of_mass(design)
	inertia = ShipParts.inertia(design, center) * ShipParts.CELL * ShipParts.CELL
	engine_throttle.clear()
	firing = false

	for child in get_children():
		if child is CollisionShape2D:
			remove_child(child)
			child.queue_free()
	ship_radius = 0.0
	ship_front = 0.0
	for part in design:
		var box := ShipParts.bounds(part)
		var rect := RectangleShape2D.new()
		rect.size = box.size * ShipParts.CELL
		var shape := CollisionShape2D.new()
		shape.shape = rect
		shape.position = _local(box.get_center())
		add_child(shape)
		for corner in [box.position, box.end, Vector2(box.position.x, box.end.y), Vector2(box.end.x, box.position.y)]:
			ship_radius = maxf(ship_radius, _local(corner).length() + ShipParts.CELL)
		ship_front = maxf(ship_front, _local(box.end).x)
	hull_layer.queue_redraw()

# Ponto do grid (em quadradinhos) em relação ao centro de massa, em px
func _local(grid_pos: Vector2) -> Vector2:
	return (grid_pos - center) * ShipParts.CELL

func _unhandled_input(event: InputEvent) -> void:
	# Aqui (e não no Input direto) para clicar em botões não disparar tiro
	if event.is_action("shoot"):
		firing = event.is_pressed()

func _physics_process(delta: float) -> void:
	_move_cursor(delta)
	_move_aim(delta)

	# WASD é fixo na tela. A força básica empurra pelo centro de massa (não gira a nave);
	# cada motor que aponta para o lado pedido liga e empurra do lugar onde está
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var engines := []
	for i in design.size():
		var part: Dictionary = design[i]
		if ShipParts.kind(part) != ShipParts.ENGINE:
			continue
		var push := ShipParts.dir_vector(part.dir).rotated(global_rotation)
		var thrust := ShipParts.thrust(part) * engine_power
		engines.append({
			"index": i,
			"push": push,
			"thrust": thrust,
			"torque": _local(ShipParts.center_of(part)).rotated(global_rotation).cross(push * thrust), # torção com o motor no máximo
			"throttle": clampf(push.dot(input), 0.0, 1.0),
		})

	_turn(engines, delta)
	_move_laser(delta)

	var force := input * base_thrust
	for e in engines:
		force += e.push * e.thrust * e.throttle
		engine_throttle[e.index] = e.throttle

	velocity += force / mass * delta
	velocity = velocity.limit_length(max_speed)
	velocity.x = _brake(0, input.x, delta)
	velocity.y = _brake(1, input.y, delta)
	move_and_slide()

	shoot_cooldown -= delta
	if firing and shoot_cooldown <= 0.0:
		shoot_cooldown = 1.0 / fire_rate
		_shoot()

# Redesenha no máximo uma vez por quadro (pedir isso dentro da física redesenharia a cada passo dela)
func _process(_delta: float) -> void:
	queue_redraw()
	effects_layer.queue_redraw()

# Raio do círculo em volta da nave onde a mira não entra (cresce com o tamanho da nave)
func _aim_radius() -> float:
	return maxf(aim_dead_zone, ship_radius)

# O anel da mira segue o mouse, mas não entra no círculo: com o mouse lá dentro ele desliza
# pela borda até o lado do mouse (sem pular para o outro lado quando o mouse cruza a nave)
func _move_cursor(delta: float) -> void:
	var mouse := get_global_mouse_position() - global_position
	var angle := cursor_offset.angle()
	if not mouse.is_zero_approx():
		var step := deg_to_rad(cursor_turn_speed) * delta
		angle += clampf(angle_difference(angle, mouse.angle()), -step, step)
	cursor_offset = Vector2.from_angle(angle) * maxf(mouse.length(), _aim_radius())

# O ponto para onde a nave tenta virar viaja até o anel dando a volta em torno da nave, então
# nunca passa por cima dela nem entra no círculo. Girar em volta e afastar/aproximar têm velocidade.
func _move_aim(delta: float) -> void:
	var target := cursor_offset
	var offset := aim_point - global_position
	if offset.is_zero_approx():
		offset = global_transform.x
	var dist := maxf(offset.length(), _aim_radius())
	var step := aim_speed * delta
	var turn := clampf(angle_difference(offset.angle(), target.angle()), -step / dist, step / dist)
	dist = move_toward(dist, target.length(), step)
	aim_point = global_position + Vector2.from_angle(offset.angle() + turn) * dist

# Laser do bico: vai até a distância em que o anel da mira está à frente da nave.
# Com o anel de lado ou atrás, ele vai só até a borda do círculo (não espelha o mouse do outro lado).
# O comprimento muda com velocidade de viagem, então ele nunca pula.
func _move_laser(delta: float) -> void:
	var ahead := cursor_offset.dot(Vector2.from_angle(global_rotation))
	laser_length = move_toward(laser_length, maxf(ahead, _aim_radius()), aim_speed * delta)
	laser_length = maxf(laser_length, _aim_radius())

# Vira o bico para a mira. O giroscópio da nave faz o que consegue; o que faltar, os motores
# que torcem a nave para o lado certo ligam para ajudar. Motor fora do centro de massa
# (ligado para andar) torce a nave e puxa o bico para um lado. A resistência do ar freia o giro,
# então para continuar girando é preciso continuar fazendo força.
func _turn(engines: Array, delta: float) -> void:
	var max_spin := deg_to_rad(max_turn_speed)
	var error := angle_difference(global_rotation, (aim_point - global_position).angle())
	# Gira o mais rápido possível, mas só o tanto que dá para frear e parar na mira
	# (mais força de giro = freia mais rápido = pode girar rápido por mais tempo)
	var brake_torque := gyro_torque
	for e in engines:
		if _helps_turn(e, -error):
			brake_torque += absf(e.torque) * (1.0 - e.throttle)
	var stoppable := sqrt(2.0 * brake_torque / inertia * ShipParts.TURN_BRAKE_MARGIN * absf(error))
	var wanted_spin := signf(error) * minf(minf(stoppable, absf(error) * ShipParts.TURN_AIM_GAIN), max_spin)
	# Força para chegar na velocidade de giro desejada + a que o ar está tirando
	var wanted := ((wanted_spin - angular_velocity) * ShipParts.TURN_RESPONSE + rotation_drag * angular_velocity) * inertia

	var gyro := clampf(wanted, -gyro_torque, gyro_torque)
	var missing := wanted - gyro
	var available := 0.0
	for e in engines:
		if _helps_turn(e, missing):
			available += absf(e.torque) * (1.0 - e.throttle)
	if available > 0.0:
		var extra := minf(absf(missing) / available, 1.0)
		for e in engines:
			if _helps_turn(e, missing):
				e.throttle += (1.0 - e.throttle) * extra

	var torque := gyro
	for e in engines:
		torque += e.torque * e.throttle
	angular_velocity += (torque / inertia - rotation_drag * angular_velocity) * delta
	angular_velocity = clampf(angular_velocity, -max_spin, max_spin)
	global_rotation += angular_velocity * delta

func _helps_turn(engine: Dictionary, missing: float) -> bool:
	return engine.torque * missing > 0.0 and ShipParts.can_turn(engine.torque, engine.thrust)

# Freio de um eixo: quase nada logo que solta, vai apertando com o tempo
# e a nave para em no máximo stop_time segundos
func _brake(axis: int, thrust: float, delta: float) -> float:
	var v := velocity[axis]
	if thrust != 0.0:
		coast_time[axis] = 0.0
		coast_speed[axis] = absf(v)
		return v

	coast_time[axis] += delta
	var t := minf(coast_time[axis] / stop_time, 1.0)
	var limit := coast_speed[axis] * (1.0 - pow(t, brake_curve))
	if limit < 1.0: # abaixo de 1 px/s já conta como parada (evita sobrar 0.0001 por erro de conta)
		return 0.0
	return clampf(v, -limit, limit)

# Cada arma atira para onde aponta na nave
func _shoot() -> void:
	for part in design:
		if ShipParts.kind(part) != ShipParts.WEAPON:
			continue
		var bullet: Node2D = bullet_scene.instantiate()
		get_parent().add_child(bullet)
		bullet.global_position = to_global(_local(ShipParts.muzzle(part)))
		bullet.global_rotation = global_rotation + ShipParts.dir_vector(part.dir).angle()

# Embaixo da nave: círculo onde a mira não entra
func _draw() -> void:
	draw_circle(Vector2.ZERO, _aim_radius(), Color(1, 1, 1, 0.05))
	draw_arc(Vector2.ZERO, _aim_radius(), 0.0, TAU, 64, Color(1, 1, 1, 0.15), 1.5)

func _draw_hull_layer() -> void:
	ShipArt.draw_static(hull_layer, design, Vector2.ZERO, center, ShipParts.CELL)

# Em cima da nave: fogo dos motores, anel da mira e laser
func _draw_effects_layer() -> void:
	ShipArt.draw_effects(effects_layer, design, Vector2.ZERO, center, ShipParts.CELL, engine_throttle, Time.get_ticks_msec() / 1000.0)
	# Onde eu estou mirando (mouse, empurrado para fora do círculo)
	effects_layer.draw_arc(to_local(global_position + cursor_offset), 10.0, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	# Laser vermelho bem transparente: para onde o bico da nave aponta de verdade
	var laser_start := Vector2.RIGHT * ship_front
	var laser_end := Vector2.RIGHT * laser_length
	effects_layer.draw_line(laser_start, laser_end, Color(1, 0.15, 0.1, 0.07), 5.0, true)
	effects_layer.draw_line(laser_start, laser_end, Color(1, 0.15, 0.1, 0.28), 1.5, true)
