# Regras das peças da nave: tamanhos, peso, força, centro de massa e salvamento (o desenho fica em ship_art.gd).
# A nave é uma lista de peças: {"type": nome em PARTS, "cell": Vector2i, "dir": 0..3}
# "dir" é para onde a peça aponta na nave: 0 = frente, 1 = direita, 2 = trás, 3 = esquerda.
# A arma atira para "dir"; o motor empurra para "dir" (o fogo sai do lado oposto).
# Peça quadrada ocupa um quadrado a partir de "cell" (canto de cima-esquerda);
# peça comprida (a arma) tem a base em "cell" e se estende para onde aponta.

const CELL := 10.0 # tamanho de um quadradinho na nave, em px

const FLOOR := "floor"
const WEAPON := "weapon"
const ENGINE := "engine"

# size = comprimento (na direção para onde a peça aponta) x largura, em quadradinhos
const PARTS := {
	"floor": {"kind": FLOOR, "name": "Chão", "size": Vector2i(1, 1), "mass": 1.0},
	"weapon": {"kind": WEAPON, "name": "Arma", "size": Vector2i(2, 1), "mass": 3.0},
	"engine_small": {"kind": ENGINE, "name": "Motor pequeno", "size": Vector2i(1, 1), "mass": 2.0, "thrust": 5000.0},
	"engine_medium": {"kind": ENGINE, "name": "Motor médio", "size": Vector2i(2, 2), "mass": 6.0, "thrust": 14000.0},
	"engine_large": {"kind": ENGINE, "name": "Motor grande", "size": Vector2i(3, 3), "mass": 12.0, "thrust": 28000.0},
}

const NEIGHBORS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

# Motor só ajuda a girar se a linha de força dele passa pelo menos isso longe do centro de massa
# (em quadradinhos); mais perto que isso ele mais empurra do que gira
const MIN_LEVER := 0.5

# Controle do giro (usado pela nave e pela estimativa de meia-volta): quanto o erro da mira vira
# velocidade de giro perto da mira, quão rápido essa velocidade é buscada, e quanto da força de
# giro é reservada para frear em cima da mira
const TURN_AIM_GAIN := 6.0
const TURN_RESPONSE := 20.0
const TURN_BRAKE_MARGIN := 0.7

const SAVE_PATH := "user://nave_v2.json" # v2: peças de tamanhos diferentes

static func dir_vector(dir: int) -> Vector2:
	return Vector2.RIGHT.rotated(dir * PI / 2.0)

static func kind(part: Dictionary) -> String:
	return PARTS[part.type].kind

static func thrust(part: Dictionary) -> float:
	return PARTS[part.type].get("thrust", 0.0)

# Quadradinhos que a peça ocupa
static func cells(part: Dictionary) -> Array:
	var size: Vector2i = PARTS[part.type].size
	var list := []
	if size.x == size.y:
		for x in size.x:
			for y in size.y:
				list.append(part.cell + Vector2i(x, y))
	else:
		var d := Vector2i(dir_vector(part.dir).round())
		var side := Vector2i(d.y, -d.x)
		for i in size.x:
			for j in size.y:
				list.append(part.cell + d * i + side * j)
	return list

# Centro da peça, em quadradinhos (pode cair entre dois)
static func center_of(part: Dictionary) -> Vector2:
	var sum := Vector2.ZERO
	var list := cells(part)
	for c in list:
		sum += Vector2(c)
	return sum / list.size()

# Retângulo que a peça ocupa, em quadradinhos (bordas nos meios-quadradinhos)
static func bounds(part: Dictionary) -> Rect2:
	var list := cells(part)
	var box := Rect2(Vector2(list[0]), Vector2.ZERO)
	for c in list:
		box = box.expand(Vector2(c))
	return box.grow(0.5)

# Ponta do cano da arma, em quadradinhos
static func muzzle(part: Dictionary) -> Vector2:
	var box := bounds(part)
	var d := dir_vector(part.dir)
	return box.get_center() + d * (absf(box.size.dot(d)) * 0.5 + 0.3)

# Quadradinho -> índice da peça que está nele
static func occupancy(design: Array) -> Dictionary:
	var occupied := {}
	for i in design.size():
		for c in cells(design[i]):
			occupied[c] = i
	return occupied

# Uma nave em forma de seta: motor grande atrás, duas armas nas asas
# e dois motores pequenos no bico, de lado, para ajudar a girar
static func default_design() -> Array:
	var design := []
	var half_width := {-2: 3, -1: 3, 0: 2, 1: 2, 2: 1, 3: 1, 4: 0}
	for x in half_width:
		for y in range(-half_width[x], half_width[x] + 1):
			design.append({"type": "floor", "cell": Vector2i(x, y), "dir": 0})
	design.append({"type": "engine_large", "cell": Vector2i(-5, -1), "dir": 0})
	design.append({"type": "weapon", "cell": Vector2i(2, -2), "dir": 0})
	design.append({"type": "weapon", "cell": Vector2i(2, 2), "dir": 0})
	design.append({"type": "engine_small", "cell": Vector2i(4, -1), "dir": 1})
	design.append({"type": "engine_small", "cell": Vector2i(4, 1), "dir": 3})
	return design

static func total_mass(design: Array) -> float:
	var mass := 0.0
	for part in design:
		mass += PARTS[part.type].mass
	return mass

# Em quadradinhos do grid (pode cair entre dois quadradinhos)
static func center_of_mass(design: Array) -> Vector2:
	var sum := Vector2.ZERO
	for part in design:
		sum += center_of(part) * PARTS[part.type].mass
	return sum / total_mass(design)

# Peso de giro, em quadradinhos²: peças longe do centro de massa deixam a nave mais difícil de girar
static func inertia(design: Array, com: Vector2) -> float:
	var total := 0.0
	for part in design:
		var size := bounds(part).size
		total += PARTS[part.type].mass * ((center_of(part) - com).length_squared() + size.length_squared() / 12.0)
	return total

# A nave não pode ter pedaços soltos: todo quadradinho tem que encostar nos outros
static func is_in_one_piece(design: Array) -> bool:
	var occupied := occupancy(design)
	if occupied.is_empty():
		return false
	var start: Vector2i = occupied.keys()[0]
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for n in NEIGHBORS:
			var next: Vector2i = cell + n
			if occupied.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == occupied.size()

static func can_turn(engine_torque: float, engine_thrust: float) -> bool:
	return absf(engine_torque) >= engine_thrust * CELL * MIN_LEVER

# Os motores da nave: para onde empurram, com quanta força e quanto torcem a nave no máximo
# (torque > 0 vira o bico para a direita)
static func engines(design: Array, power: float) -> Array:
	var com := center_of_mass(design)
	var list := []
	for part in design:
		if kind(part) == ENGINE:
			var push := dir_vector(part.dir)
			var force := thrust(part) * power
			list.append({"push": push, "thrust": force, "torque": ((center_of(part) - com) * CELL).cross(push * force)})
	return list

# Para cada lado da nave (frente, direita, trás, esquerda): quanto ela acelera (px/s²), quanto
# os motores torcem a nave e se o giroscópio + motores que torcem para o outro lado aguentam segurar
static func push_report(design: Array, base_thrust: float, power: float, gyro_torque: float) -> Array:
	var mass := total_mass(design)
	var list := engines(design, power)
	var report := []
	for side in 4:
		var wanted := dir_vector(side)
		var force := wanted * base_thrust
		var torque := 0.0
		var throttles := []
		for e in list:
			var throttle := maxf(e.push.dot(wanted), 0.0)
			throttles.append(throttle)
			force += e.push * e.thrust * throttle
			torque += e.torque * throttle
		var counter := gyro_torque
		for i in list.size():
			if list[i].torque * torque < 0.0 and can_turn(list[i].torque, list[i].thrust):
				counter += absf(list[i].torque) * (1.0 - throttles[i])
		report.append({"accel": force.dot(wanted) / mass, "torque": torque, "holdable": absf(torque) <= counter})
	return report

# Tempo aproximado (s) para dar meia-volta girando para a direita (dir = 1) ou esquerda (dir = -1).
# Simula o mesmo controle de giro da nave: giroscópio + motores que torcem para esse lado aceleram,
# os do outro lado freiam, com velocidade máxima e resistência do ar no giro. 10 = não consegue.
static func half_turn_time(design: Array, power: float, gyro_torque: float, max_turn_speed: float, drag: float, dir: float) -> float:
	var spin_inertia := inertia(design, center_of_mass(design)) * CELL * CELL
	var push := gyro_torque
	var brake := gyro_torque
	for e in engines(design, power):
		if can_turn(e.torque, e.thrust):
			if e.torque * dir > 0.0:
				push += absf(e.torque)
			else:
				brake += absf(e.torque)
	var top := deg_to_rad(max_turn_speed)
	var left := PI
	var spin := 0.0
	var time := 0.0
	var dt := 1.0 / 60.0
	while left > deg_to_rad(3.0) and time < 10.0:
		var stoppable := sqrt(2.0 * brake / spin_inertia * TURN_BRAKE_MARGIN * left)
		var wanted := minf(minf(stoppable, left * TURN_AIM_GAIN), top)
		var accel := clampf((wanted - spin) * TURN_RESPONSE + drag * spin, -brake / spin_inertia, push / spin_inertia)
		spin = clampf(spin + (accel - drag * spin) * dt, -top, top)
		left -= spin * dt
		time += dt
	return time

static func save_design(design: Array) -> void:
	var parts := []
	for part in design:
		parts.append({"type": part.type, "x": part.cell.x, "y": part.cell.y, "dir": part.dir})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(parts))

static func load_design() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return default_design()
	var parts = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parts is Array):
		return default_design()
	var design := []
	for p in parts:
		if p is Dictionary and PARTS.has(p.get("type")):
			design.append({"type": p.type, "cell": Vector2i(int(p.x), int(p.y)), "dir": int(p.dir)})
	if design.is_empty() or not is_in_one_piece(design):
		return default_design()
	return design
