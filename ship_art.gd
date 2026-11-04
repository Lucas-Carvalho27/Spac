# Arte da nave, desenhada por código para as peças se encaixarem em qualquer formato montado no editor:
# o casco é uma peça só (contorno só nas bordas de fora, cantos chanfrados, emendas entre placas)
# e armas e motores ficam montados em cima dele.

const ShipParts = preload("res://ship_parts.gd")

const HULL := Color(0.42, 0.47, 0.55)
const HULL_ALT := Color(0.47, 0.52, 0.6)
const RIM := Color(0.09, 0.11, 0.15)
const HIGHLIGHT := Color(0.8, 0.86, 0.92, 0.5)
const SEAM := Color(0.24, 0.28, 0.34, 0.8)
const RIVET := Color(0.3, 0.34, 0.4)
const ACCENT := Color(0.98, 0.58, 0.16)
const DARK_METAL := Color(0.2, 0.22, 0.26)
const METAL := Color(0.6, 0.63, 0.68)
const GLOW := Color(1.0, 0.55, 0.2)
const FLAME_OUTER := Color(1.0, 0.42, 0.1, 0.8)
const FLAME_INNER := Color(1.0, 0.9, 0.6, 0.95)

const QUADRANTS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

# Desenha a nave inteira: "origin" é onde fica o ponto "offset" do grid, "s" o tamanho do quadradinho;
# "throttles" diz quanto cada motor (pelo índice da peça) está ligado; "alpha" deixa tudo transparente
static func draw_ship(ci: CanvasItem, design: Array, origin: Vector2, offset: Vector2, s: float, throttles := {}, time := 0.0, alpha := 1.0) -> void:
	draw_static(ci, design, origin, offset, s, alpha)
	draw_effects(ci, design, origin, offset, s, throttles, time, alpha)

# A parte que não muda enquanto a nave voa (casco, carcaças, armas): dá para desenhar uma vez só
static func draw_static(ci: CanvasItem, design: Array, origin: Vector2, offset: Vector2, s: float, alpha := 1.0) -> void:
	_draw_hull(ci, ShipParts.occupancy(design), origin, offset, s, alpha)
	for kind in [ShipParts.ENGINE, ShipParts.WEAPON]:
		for part in design:
			if ShipParts.kind(part) != kind:
				continue
			var center: Vector2 = origin + (ShipParts.center_of(part) - offset) * s
			if kind == ShipParts.ENGINE:
				_draw_engine(ci, part, center, s, alpha)
			else:
				_draw_weapon(ci, part, center, s, alpha)

# A parte que muda a cada quadro: brilho dos bocais e fogo dos motores
static func draw_effects(ci: CanvasItem, design: Array, origin: Vector2, offset: Vector2, s: float, throttles := {}, time := 0.0, alpha := 1.0) -> void:
	for i in design.size():
		var part: Dictionary = design[i]
		if ShipParts.kind(part) == ShipParts.ENGINE:
			var center: Vector2 = origin + (ShipParts.center_of(part) - offset) * s
			_draw_engine_fire(ci, part, center, s, throttles.get(i, 0.0), time, alpha)

# Casco: cada quadradinho é dividido em 4 cantos; cada canto olha os vizinhos para saber se é
# meio do casco, borda ou quina (quina de fora é chanfrada). Assim qualquer formato fica fechado.
static func _draw_hull(ci: CanvasItem, occupied: Dictionary, origin: Vector2, offset: Vector2, s: float, alpha: float) -> void:
	var hs := s * 0.5
	var bevel := s * 0.32
	var rims := [] # [de, até, para dentro]
	for cell in occupied:
		var p: Vector2 = origin + (Vector2(cell) - offset) * s
		var shade := HULL_ALT if hash(cell) % 3 == 0 else HULL
		for q in QUADRANTS:
			var ax := Vector2(q.x, 0)
			var ay := Vector2(0, q.y)
			var open_x: bool = not occupied.has(cell + Vector2i(q.x, 0))
			var open_y: bool = not occupied.has(cell + Vector2i(0, q.y))
			if open_x and open_y:
				var b := p + ax * hs + ay * (hs - bevel)
				var c := p + ax * (hs - bevel) + ay * hs
				ci.draw_colored_polygon(PackedVector2Array([p, p + ax * hs, b, c, p + ay * hs]), _a(shade, alpha))
				rims.append([p + ax * hs, b, -ax])
				rims.append([b, c, -(ax + ay).normalized()])
				rims.append([c, p + ay * hs, -ay])
			else:
				ci.draw_colored_polygon(PackedVector2Array([p, p + ax * hs, p + (ax + ay) * hs, p + ay * hs]), _a(shade, alpha))
				if open_x:
					rims.append([p + ax * hs, p + (ax + ay) * hs, -ax])
				if open_y:
					rims.append([p + ay * hs, p + (ax + ay) * hs, -ay])

	# Emendas entre placas (só algumas, para parecer placas de tamanhos variados) e rebites
	for cell in occupied:
		var p: Vector2 = origin + (Vector2(cell) - offset) * s
		for side in [Vector2i.RIGHT, Vector2i.DOWN]:
			if occupied.has(cell + side) and hash(Vector3i(cell.x, cell.y, side.x)) % 2 == 0:
				var along := Vector2(side.y, side.x) * (hs - s * 0.08)
				var at := p + Vector2(side) * hs
				ci.draw_line(at - along, at + along, _a(SEAM, alpha), maxf(s * 0.05, 1.0))
		if hash(cell) % 4 == 1:
			for corner in [Vector2(-1, -1), Vector2(1, 1)]:
				ci.draw_circle(p + corner * s * 0.3, s * 0.05, _a(RIVET, alpha))

	# Contorno de fora: borda escura grossa com um fio claro por dentro
	for rim in rims:
		ci.draw_line(rim[0], rim[1], _a(RIM, alpha), s * 0.16)
		ci.draw_circle(rim[0], s * 0.08, _a(RIM, alpha))
	for rim in rims:
		var inward: Vector2 = rim[2] * s * 0.14
		ci.draw_line(rim[0] + inward, rim[1] + inward, _a(HIGHLIGHT, alpha), maxf(s * 0.05, 1.0))

# Arma: torre redonda no quadradinho de trás e cano comprido passando um pouco da nave
static func _draw_weapon(ci: CanvasItem, part: Dictionary, center: Vector2, s: float, alpha: float) -> void:
	var d := ShipParts.dir_vector(part.dir)
	var side := d.orthogonal()
	var base := center - d * s * 0.5
	var tip := center + d * s * 1.25
	ci.draw_colored_polygon(_bar(base, tip, s * 0.17), _a(RIM, alpha))
	ci.draw_colored_polygon(_bar(base, tip - d * s * 0.04, s * 0.1), _a(METAL, alpha))
	ci.draw_colored_polygon(_bar(tip - d * s * 0.28, tip, s * 0.2), _a(DARK_METAL, alpha))
	ci.draw_line(tip - d * s * 0.16 + side * s * 0.2, tip - d * s * 0.16 - side * s * 0.2, _a(ACCENT, alpha), s * 0.07)
	ci.draw_circle(base, s * 0.44, _a(RIM, alpha))
	ci.draw_circle(base, s * 0.37, _a(DARK_METAL, alpha))
	ci.draw_circle(base, s * 0.28, _a(METAL, alpha))
	ci.draw_circle(base - (d + side) * s * 0.08, s * 0.1, _a(HIGHLIGHT, alpha))
	ci.draw_circle(base, s * 0.09, _a(ACCENT, alpha))

# Motor: carcaça com grade, faixa colorida e bocal atrás (o brilho e o fogo ficam em _draw_engine_fire)
static func _draw_engine(ci: CanvasItem, part: Dictionary, center: Vector2, s: float, alpha: float) -> void:
	var n: int = ShipParts.PARTS[part.type].size.x
	var d := ShipParts.dir_vector(part.dir)
	var side := d.orthogonal()
	var half := n * s * 0.5

	ci.draw_colored_polygon(_box(center, d * (half - s * 0.1), side * (half - s * 0.1)), _a(RIM, alpha))
	ci.draw_colored_polygon(_box(center, d * (half - s * 0.18), side * (half - s * 0.18)), _a(DARK_METAL, alpha))
	var slots := n * 2 + 1
	for k in range(1, slots):
		var across := side * (-half + s * 0.3 + (2.0 * half - s * 0.6) * k / slots)
		ci.draw_line(center + across - d * half * 0.15, center + across + d * (half - s * 0.4), _a(RIM, alpha * 0.8), maxf(s * 0.06, 1.0))
	ci.draw_line(center + d * (half - s * 0.3) + side * (half - s * 0.3), center + d * (half - s * 0.3) - side * (half - s * 0.3), _a(ACCENT, alpha), s * 0.09)

	var back := center - d * half
	var inner_w := half * 0.55
	var outer_w := half * 0.8
	var mouth := back - d * s * 0.45
	ci.draw_colored_polygon(PackedVector2Array([
		back + d * s * 0.35 + side * inner_w, back + d * s * 0.35 - side * inner_w,
		mouth - side * outer_w, mouth + side * outer_w,
	]), _a(RIM, alpha))
	ci.draw_colored_polygon(PackedVector2Array([
		back + d * s * 0.28 + side * inner_w * 0.8, back + d * s * 0.28 - side * inner_w * 0.8,
		mouth + d * s * 0.06 - side * outer_w * 0.85, mouth + d * s * 0.06 + side * outer_w * 0.85,
	]), _a(METAL, alpha))

# Brilho no fundo do bocal e fogo que tremula, do tamanho do motor e da força
static func _draw_engine_fire(ci: CanvasItem, part: Dictionary, center: Vector2, s: float, throttle: float, time: float, alpha: float) -> void:
	var n: int = ShipParts.PARTS[part.type].size.x
	var d := ShipParts.dir_vector(part.dir)
	var side := d.orthogonal()
	var half := n * s * 0.5
	var outer_w := half * 0.8
	var mouth := center - d * (half + s * 0.45)
	ci.draw_line(mouth + side * outer_w * 0.75, mouth - side * outer_w * 0.75, _a(GLOW, alpha * (0.35 + 0.65 * throttle)), s * 0.14)

	if throttle > 0.01:
		var flicker := 0.85 + 0.15 * sin(time * 40.0 + center.x * 0.1 + center.y * 0.07)
		var length := (s * 0.8 + n * s * 1.6) * throttle * flicker
		ci.draw_colored_polygon(PackedVector2Array([
			mouth + side * outer_w * 0.85, mouth - side * outer_w * 0.85, mouth - d * length,
		]), _a(FLAME_OUTER, alpha))
		ci.draw_colored_polygon(PackedVector2Array([
			mouth + side * outer_w * 0.45, mouth - side * outer_w * 0.45, mouth - d * length * 0.6,
		]), _a(FLAME_INNER, alpha))

static func _a(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)

static func _box(center: Vector2, along: Vector2, across: Vector2) -> PackedVector2Array:
	return PackedVector2Array([center + along + across, center + along - across, center - along - across, center - along + across])

# Retângulo de "from" até "to" com meia-largura "half_width"
static func _bar(from: Vector2, to: Vector2, half_width: float) -> PackedVector2Array:
	var across := (to - from).normalized().orthogonal() * half_width
	return PackedVector2Array([from + across, to + across, to - across, from - across])
