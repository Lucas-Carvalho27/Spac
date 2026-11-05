# Regras do interior da nave. Cada quadradinho de chassi vira 2x2 quadradinhos internos (de 1/4).
#   - Livres: o chão inteiro por dentro, onde vão paredes e componentes.
#   - Casco: uma camada de 1/4 por fora, contornando o chão (quinas também), que já vem como parede.
#     Dá para trocar por parede reforçada ou blindagem; apagando, volta a ser casco normal.
#   - Trancados: os de arma e motor (ali está a máquina; o casco não passa em volta deles).
# Paredes, parede reforçada e blindagem são blocos sólidos: separam as salas. Os outros componentes não.
#
# O interior é um Dictionary: "blocks": Vector2i (quadradinho interno) -> tipo do bloco.
# Por enquanto nada disso muda o jogo.

const ShipParts = preload("res://ship/ship_parts.gd")

const FREE := "free"
const HULL := "hull"
const LOCKED := "locked"

# Vizinhos de um quadradinho interno, contando as diagonais (para o casco fechar nas quinas)
const AROUND := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

# group: para que sistema o bloco vai servir; short: nome curto para o botão do editor;
# solid: separa salas
const BLOCKS := {
	"wall": {"name": "Parede", "short": "Parede", "group": "Estrutura", "solid": true},
	"wall_reinforced": {"name": "Parede reforçada", "short": "Parede reforçada", "group": "Estrutura", "solid": true},
	"armor": {"name": "Blindagem", "short": "Blindagem", "group": "Blindagem", "solid": true},
	"autoloader": {"name": "Autoloader", "short": "Autoloader", "group": "Arma", "solid": false},
	"magazine": {"name": "Pente", "short": "Pente", "group": "Arma", "solid": false},
	"ammo": {"name": "Munição", "short": "Munição", "group": "Arma", "solid": false},
	"fuel_tank": {"name": "Tanque de combustível", "short": "Combustível", "group": "Motor", "solid": false},
	"fuel_pump": {"name": "Bomba de combustível", "short": "Bomba", "group": "Motor", "solid": false},
}
# O que pode substituir o casco
const HULL_UPGRADES := ["wall_reinforced", "armor"]

static func empty() -> Dictionary:
	return {"blocks": {}}

# Quadradinho de chassi onde fica um quadradinho interno
static func cell_of(sub: Vector2i) -> Vector2i:
	return Vector2i(floori(sub.x / 2.0), floori(sub.y / 2.0))

# Todos os quadradinhos internos da nave: quadradinho -> FREE, HULL ou LOCKED
static func sub_cells(design: Array) -> Dictionary:
	var subs := {}
	var occupied := ShipParts.occupancy(design)
	for cell in occupied:
		var state := FREE if ShipParts.kind(design[occupied[cell]]) == ShipParts.FLOOR else LOCKED
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			subs[cell * 2 + corner] = state
	var ring := {}
	for sub in subs:
		if subs[sub] == FREE:
			for n in AROUND:
				if not subs.has(sub + n):
					ring[sub + n] = true
	for sub in ring:
		subs[sub] = HULL
	return subs

# O que tem de sólido num quadradinho interno (casco conta), ou "" se nada sólido
static func solid_at(subs: Dictionary, interior: Dictionary, sub: Vector2i) -> String:
	var block: String = interior.blocks.get(sub, "")
	if block != "" and BLOCKS[block].solid:
		return block
	return HULL if subs.get(sub) == HULL else ""

# Por que não dá para pôr esse bloco nesse quadradinho ("" = dá)
static func block_problem(subs: Dictionary, sub: Vector2i, type: String) -> String:
	match subs.get(sub):
		null:
			return "Fora da nave."
		LOCKED:
			return "Aqui fica a arma ou o motor; o resto vai no chão em volta."
		HULL:
			if type == "wall":
				return "O casco já é parede."
			if not HULL_UPGRADES.has(type):
				return "Isso é o casco: aqui só dá parede reforçada ou blindagem."
	return ""

# O interior sem o que ficou fora do lugar depois de mudar o chassi (chão apagado,
# arma ou motor colocado por cima, bloco que virou borda do casco...)
static func cleaned(design: Array, interior: Dictionary) -> Dictionary:
	var subs := sub_cells(design)
	var result := empty()
	var blocks: Dictionary = interior.get("blocks", {})
	for sub in blocks:
		if block_problem(subs, sub, blocks[sub]) == "":
			result.blocks[sub] = blocks[sub]
	return result

# Salas: quadradinhos livres sem bloco sólido, ligados entre si. Devolve quadradinho -> número da sala
static func rooms(subs: Dictionary, interior: Dictionary) -> Dictionary:
	var room_of := {}
	var count := 0
	for start in subs:
		if not _walkable(subs, interior, start) or room_of.has(start):
			continue
		room_of[start] = count
		var queue := [start]
		while not queue.is_empty():
			var sub: Vector2i = queue.pop_back()
			for n in ShipParts.NEIGHBORS:
				var next: Vector2i = sub + n
				if _walkable(subs, interior, next) and not room_of.has(next):
					room_of[next] = count
					queue.append(next)
		count += 1
	return room_of

static func _walkable(subs: Dictionary, interior: Dictionary, sub: Vector2i) -> bool:
	return subs.get(sub) == FREE and solid_at(subs, interior, sub) == ""

static func to_json(interior: Dictionary) -> Dictionary:
	var blocks := []
	for sub in interior.blocks:
		blocks.append({"x": sub.x, "y": sub.y, "type": interior.blocks[sub]})
	return {"blocks": blocks}

# Também lê o formato anterior ("components"); as paredes antigas em linha não existem mais
static func from_json(data) -> Dictionary:
	var interior := empty()
	if not (data is Dictionary):
		return interior
	for b in data.get("blocks", []) + data.get("components", []):
		if b is Dictionary and BLOCKS.has(b.get("type")):
			interior.blocks[Vector2i(int(b.x), int(b.y))] = b.type
	return interior
