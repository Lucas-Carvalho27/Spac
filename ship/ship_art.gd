# Arte da nave, desenhada por código para as peças se encaixarem em qualquer formato montado no editor.
# Chassi: uma estrutura escura com o contorno de fora (quinas chanfradas) e, por cima, uma placa com
# relevo para cada bloco de chão (1x1, 1x2 e 4x4 têm detalhes diferentes); armas e motores montados
# em cima. Interior: piso de grade, blocos sólidos que se emendam (casco, paredes, blindagem) e
# componentes. A luz vem de cima-esquerda da nave.

const ShipParts = preload("res://ship/ship_parts.gd")
const ShipInterior = preload("res://ship/ship_interior.gd")

const LIGHT_DIR := Vector2(-0.7071, -0.7071) # de onde vem a luz

const FRAME := Color(0.11, 0.13, 0.17) # estrutura embaixo das placas (aparece nas emendas)
const PLATE := Color(0.45, 0.5, 0.57)
const PLATE_ALT := Color(0.5, 0.55, 0.62)
const PLATE_LIGHT := Color(0.76, 0.81, 0.88)
const PLATE_SHADOW := Color(0.25, 0.28, 0.34)
const PLATE_RECESS := Color(0.33, 0.37, 0.44)
const RIM := Color(0.06, 0.07, 0.1)
const HIGHLIGHT := Color(0.85, 0.9, 0.96, 0.5)
const RIVET := Color(0.2, 0.23, 0.28)
const ACCENT := Color(0.98, 0.58, 0.16)
const DARK_METAL := Color(0.19, 0.21, 0.25)
const METAL := Color(0.6, 0.64, 0.7)
const METAL_LIGHT := Color(0.88, 0.91, 0.95)
const GLOW := Color(1.0, 0.55, 0.2)
const FLAME_OUTER := Color(1.0, 0.42, 0.1, 0.8)
const FLAME_INNER := Color(1.0, 0.9, 0.6, 0.95)

const QUADRANTS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]

# Interior
const GROUP_COLORS := {"Estrutura": Color(0.82, 0.86, 0.92), "Arma": Color(1.0, 0.78, 0.3), "Blindagem": Color(0.55, 0.72, 1.0), "Motor": Color(1.0, 0.52, 0.25)}
const ICON_DARK := Color(0.07, 0.08, 0.1)
const GRATE := Color(0.12, 0.14, 0.18)
const GRATE_SLAT := Color(0.22, 0.25, 0.3)
# Blocos sólidos: preenchimento, luz, sombra
const BLOCK_LOOKS := {
	"hull": [Color(0.45, 0.5, 0.57), Color(0.72, 0.77, 0.84), Color(0.26, 0.29, 0.35)],
	"wall": [Color(0.6, 0.64, 0.71), Color(0.85, 0.88, 0.93), Color(0.36, 0.4, 0.47)],
	"wall_reinforced": [Color(0.34, 0.38, 0.45), Color(0.6, 0.65, 0.73), Color(0.17, 0.2, 0.25)],
	"armor": [Color(0.29, 0.42, 0.63), Color(0.58, 0.72, 0.93), Color(0.15, 0.22, 0.36)],
}

# Desenha a nave inteira: "origin" é onde fica o ponto "offset" do grid, "s" o tamanho do quadradinho;
# "throttles" diz quanto cada motor (pelo índice da peça) está ligado; "alpha" deixa tudo transparente
static func draw_ship(ci: CanvasItem, design: Array, origin: Vector2, offset: Vector2, s: float, throttles := {}, time := 0.0, alpha := 1.0) -> void:
	draw_static(ci, design, origin, offset, s, alpha)
	draw_effects(ci, design, origin, offset, s, throttles, time, alpha)

# A parte que não muda enquanto a nave voa (casco, carcaças, armas): dá para desenhar uma vez só
static func draw_static(ci: CanvasItem, design: Array, origin: Vector2, offset: Vector2, s: float, alpha := 1.0) -> void:
	_draw_hull(ci, design, origin, offset, s, alpha)
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

# ---------- Chassi ----------

# 1) estrutura escura com a silhueta da nave: cada quadradinho é dividido em 4 cantos e cada canto
#    olha os vizinhos para saber se é meio, borda ou quina (quina de fora é chanfrada);
# 2) uma placa com relevo para cada bloco de chão; 3) contorno de fora por cima de tudo
static func _draw_hull(ci: CanvasItem, design: Array, origin: Vector2, offset: Vector2, s: float, alpha: float) -> void:
	var occupied := ShipParts.occupancy(design)
	var hs := s * 0.5
	var bevel := s * 0.32
	var rims := [] # [de, até, para dentro]
	for cell in occupied:
		var p: Vector2 = origin + (Vector2(cell) - offset) * s
		for q in QUADRANTS:
			var ax := Vector2(q.x, 0)
			var ay := Vector2(0, q.y)
			var open_x: bool = not occupied.has(cell + Vector2i(q.x, 0))
			var open_y: bool = not occupied.has(cell + Vector2i(0, q.y))
			if open_x and open_y:
				var b := p + ax * hs + ay * (hs - bevel)
				var c := p + ax * (hs - bevel) + ay * hs
				ci.draw_colored_polygon(PackedVector2Array([p, p + ax * hs, b, c, p + ay * hs]), _a(FRAME, alpha))
				rims.append([p + ax * hs, b, -ax])
				rims.append([b, c, -(ax + ay).normalized()])
				rims.append([c, p + ay * hs, -ay])
			else:
				ci.draw_colored_polygon(PackedVector2Array([p, p + ax * hs, p + (ax + ay) * hs, p + ay * hs]), _a(FRAME, alpha))
				if open_x:
					rims.append([p + ax * hs, p + (ax + ay) * hs, -ax])
				if open_y:
					rims.append([p + ay * hs, p + (ax + ay) * hs, -ay])

	for part in design:
		if ShipParts.kind(part) == ShipParts.FLOOR:
			_draw_plate(ci, part, occupied, origin, offset, s, alpha)

	for rim in rims:
		ci.draw_line(rim[0], rim[1], _a(RIM, alpha), s * 0.16)
		ci.draw_circle(rim[0], s * 0.08, _a(RIM, alpha))
	for rim in rims:
		var inward: Vector2 = rim[2] * s * 0.14
		ci.draw_line(rim[0] + inward, rim[1] + inward, _a(HIGHLIGHT, alpha), maxf(s * 0.05, 1.0))

# Placa de um bloco de chão: relevo nas bordas, cantos de fora chanfrados junto com o casco
# e detalhes conforme o tamanho (1x1 rebites, 1x2 canaleta, 3x3 escotilha grande,
# 4x4 painel com ventilação, escotilha e faixa de aviso)
static func _draw_plate(ci: CanvasItem, part: Dictionary, occupied: Dictionary, origin: Vector2, offset: Vector2, s: float, alpha: float) -> void:
	var box := ShipParts.bounds(part)
	var rect := Rect2(origin + (box.position - offset) * s, box.size * s).grow(-s * 0.07)
	var low := Vector2i((box.position + Vector2(0.5, 0.5)).round())
	var high := Vector2i((box.end - Vector2(0.5, 0.5)).round())
	var corner_cells := [low, Vector2i(high.x, low.y), high, Vector2i(low.x, high.y)]
	var chamfers := []
	for i in 4:
		var q: Vector2i = QUADRANTS[i]
		var cell: Vector2i = corner_cells[i]
		var outer: bool = not occupied.has(cell + Vector2i(q.x, 0)) and not occupied.has(cell + Vector2i(0, q.y))
		chamfers.append(s * (0.27 if outer else 0.05))
	var shade := PLATE_ALT if hash(part.cell) % 3 == 0 else PLATE
	_draw_bevel(ci, _chamfered_rect(rect, chamfers), shade, PLATE_LIGHT, PLATE_SHADOW, s * 0.07, alpha)

	var center := rect.get_center()
	var cell_count := ShipParts.cells(part).size()
	if cell_count == 1:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			_rivet(ci, center + corner * (rect.size.x * 0.5 - s * 0.17), s * 0.05, alpha)
	elif cell_count == 2:
		var long := Vector2.RIGHT if rect.size.x > rect.size.y else Vector2.DOWN
		var across := Vector2(long.y, long.x)
		var half_long := maxf(rect.size.x, rect.size.y) * 0.5
		var half_short := minf(rect.size.x, rect.size.y) * 0.5
		var groove := long * (half_long - s * 0.3)
		ci.draw_line(center - groove, center + groove, _a(PLATE_SHADOW, alpha), maxf(s * 0.06, 1.0))
		ci.draw_line(center - groove + across * s * 0.05, center + groove + across * s * 0.05, _a(PLATE_LIGHT, alpha * 0.6), maxf(s * 0.03, 1.0))
		for end in [-1.0, 1.0]:
			for side in [-1.0, 1.0]:
				_rivet(ci, center + long * end * (half_long - s * 0.17) + across * side * (half_short - s * 0.17), s * 0.05, alpha)
	elif cell_count == 9:
		# Escotilha grande e redonda no meio, num sulco, com volante e parafusos nos cantos
		var r := rect.size.x * 0.3
		ci.draw_arc(center, r + s * 0.12, 0.0, TAU, 40, _a(PLATE_SHADOW, alpha), s * 0.1)
		ci.draw_arc(center, r + s * 0.16, -PI * 0.25 - PI * 0.5, -PI * 0.25 + PI * 0.5, 20, _a(PLATE_LIGHT, alpha * 0.7), maxf(s * 0.04, 1.0))
		ci.draw_circle(center, r, _a(RIM, alpha))
		ci.draw_circle(center + LIGHT_DIR * r * 0.05, r * 0.9, _a(PLATE_LIGHT, alpha))
		ci.draw_circle(center - LIGHT_DIR * r * 0.03, r * 0.87, _a(shade, alpha))
		ci.draw_arc(center, r * 0.93, 0.2, 1.0, 8, _a(ACCENT, alpha), maxf(s * 0.06, 1.0))
		ci.draw_arc(center, r * 0.45, 0.0, TAU, 28, _a(RIM, alpha), maxf(s * 0.07, 1.0))
		for k in 3:
			var spoke := Vector2.from_angle(k * TAU / 3.0 + 0.3) * r * 0.45
			ci.draw_line(center, center + spoke, _a(RIM, alpha), maxf(s * 0.06, 1.0))
		ci.draw_circle(center, r * 0.12, _a(RIM, alpha))
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			_rivet(ci, center + corner * (rect.size.x * 0.5 - s * 0.25), s * 0.07, alpha)
	else:
		# Painel rebaixado no meio (luz invertida = parece afundado)
		var recess := rect.grow(-s * 0.45)
		_draw_bevel(ci, _chamfered_rect(recess, [s * 0.12, s * 0.12, s * 0.12, s * 0.12]), PLATE_RECESS, PLATE_SHADOW, PLATE_LIGHT, s * 0.06, alpha)
		# Grade de ventilação em cima à esquerda
		for k in 5:
			var y := recess.position.y + recess.size.y * (0.14 + 0.075 * k)
			ci.draw_line(Vector2(recess.position.x + recess.size.x * 0.12, y), Vector2(recess.position.x + recess.size.x * 0.5, y), _a(RIM, alpha * 0.85), maxf(s * 0.07, 1.0))
		# Escotilha redonda embaixo à direita
		var hatch := recess.position + recess.size * Vector2(0.7, 0.68)
		var r := minf(recess.size.x, recess.size.y) * 0.2
		ci.draw_circle(hatch, r, _a(RIM, alpha))
		ci.draw_circle(hatch, r * 0.84, _a(PLATE_SHADOW, alpha))
		ci.draw_circle(hatch + LIGHT_DIR * r * 0.06, r * 0.7, _a(PLATE_LIGHT, alpha))
		ci.draw_circle(hatch - LIGHT_DIR * r * 0.04, r * 0.66, _a(shade, alpha))
		ci.draw_line(hatch - Vector2(r * 0.4, 0), hatch + Vector2(r * 0.4, 0), _a(RIM, alpha), maxf(s * 0.06, 1.0))
		# Faixa de aviso no alto à direita do painel
		var stripe_y := recess.position.y + recess.size.y * 0.16
		for k in 4:
			var x := recess.position.x + recess.size.x * (0.6 + k * 0.08)
			var step := recess.size.x * 0.05
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x, stripe_y + step), Vector2(x + step, stripe_y - step),
				Vector2(x + step * 1.8, stripe_y - step), Vector2(x + step * 0.8, stripe_y + step),
			]), _a(ACCENT if k % 2 == 0 else RIM, alpha))
		# Rebites em volta da placa
		var per_side := int(round(rect.size.x / s))
		for k in range(1, per_side):
			var t := float(k) / per_side
			for edge_point in [
				Vector2(rect.position.x + rect.size.x * t, rect.position.y + s * 0.2),
				Vector2(rect.position.x + rect.size.x * t, rect.end.y - s * 0.2),
				Vector2(rect.position.x + s * 0.2, rect.position.y + rect.size.y * t),
				Vector2(rect.end.x - s * 0.2, rect.position.y + rect.size.y * t),
			]:
				_rivet(ci, edge_point, s * 0.05, alpha)

# Arma: berço, cano com brilho num lado, freio de boca com fendas e torre redonda com reflexo
static func _draw_weapon(ci: CanvasItem, part: Dictionary, center: Vector2, s: float, alpha: float) -> void:
	var d := ShipParts.dir_vector(part.dir)
	var side := d.orthogonal()
	var lit_side := side if side.dot(LIGHT_DIR) > 0.0 else -side
	var base := center - d * s * 0.5
	var tip := center + d * s * 1.3
	ci.draw_colored_polygon(_bar(base, center + d * s * 0.42, s * 0.3), _a(RIM, alpha))
	ci.draw_colored_polygon(_bar(base, center + d * s * 0.36, s * 0.23), _a(DARK_METAL, alpha))
	ci.draw_colored_polygon(_bar(base, tip, s * 0.15), _a(RIM, alpha))
	ci.draw_colored_polygon(_bar(base, tip - d * s * 0.03, s * 0.09), _a(METAL, alpha))
	ci.draw_line(base + lit_side * s * 0.045, tip - d * s * 0.05 + lit_side * s * 0.045, _a(METAL_LIGHT, alpha), maxf(s * 0.035, 1.0))
	ci.draw_colored_polygon(_bar(tip - d * s * 0.34, tip, s * 0.19), _a(RIM, alpha))
	ci.draw_colored_polygon(_bar(tip - d * s * 0.3, tip - d * s * 0.03, s * 0.14), _a(DARK_METAL, alpha))
	for k in [0.1, 0.2]:
		ci.draw_line(tip - d * s * k + side * s * 0.11, tip - d * s * k - side * s * 0.11, _a(RIM, alpha), maxf(s * 0.04, 1.0))
	ci.draw_line(tip - d * s * 0.34 + side * s * 0.19, tip - d * s * 0.34 - side * s * 0.19, _a(ACCENT, alpha), s * 0.06)
	ci.draw_circle(base, s * 0.46, _a(RIM, alpha))
	ci.draw_circle(base, s * 0.4, _a(DARK_METAL, alpha))
	ci.draw_circle(base + LIGHT_DIR * s * 0.04, s * 0.31, _a(METAL_LIGHT, alpha))
	ci.draw_circle(base - LIGHT_DIR * s * 0.02, s * 0.29, _a(METAL, alpha))
	ci.draw_circle(base, s * 0.12, _a(RIM, alpha))
	ci.draw_circle(base, s * 0.08, _a(ACCENT, alpha))

# Motor: carcaça com relevo, grade, faixa laranja e parafusos; bocal com anéis
# (o brilho e o fogo ficam em _draw_engine_fire)
static func _draw_engine(ci: CanvasItem, part: Dictionary, center: Vector2, s: float, alpha: float) -> void:
	var n: int = ShipParts.PARTS[part.type].size.x
	var d := ShipParts.dir_vector(part.dir)
	var side := d.orthogonal()
	var half := n * s * 0.5

	ci.draw_colored_polygon(_box(center, d * (half - s * 0.08), side * (half - s * 0.08)), _a(RIM, alpha))
	_draw_bevel(ci, _box(center, d * (half - s * 0.16), side * (half - s * 0.16)), DARK_METAL, Color(0.44, 0.48, 0.55), Color(0.09, 0.1, 0.13), s * 0.07, alpha)
	var slots := n * 2 + 1
	for k in range(1, slots):
		var across := side * (-half + s * 0.32 + (2.0 * half - s * 0.64) * k / slots)
		ci.draw_line(center + across - d * half * 0.2, center + across + d * (half - s * 0.45), _a(RIM, alpha * 0.85), maxf(s * 0.07, 1.0))
	ci.draw_line(center + d * (half - s * 0.32) + side * (half - s * 0.32), center + d * (half - s * 0.32) - side * (half - s * 0.32), _a(ACCENT, alpha), s * 0.09)
	for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_rivet(ci, center + d * corner.x * (half - s * 0.3) + side * corner.y * (half - s * 0.3), s * 0.06, alpha)

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
	var lit_side := side if side.dot(LIGHT_DIR) > 0.0 else -side
	ci.draw_line(back + d * s * 0.26 + lit_side * inner_w * 0.7, mouth + d * s * 0.08 + lit_side * outer_w * 0.75, _a(METAL_LIGHT, alpha), maxf(s * 0.05, 1.0))
	for t in [0.35, 0.7]:
		var ring_center := (back + d * s * 0.28).lerp(mouth + d * s * 0.06, t)
		var ring_w := lerpf(inner_w * 0.8, outer_w * 0.85, t)
		ci.draw_line(ring_center + side * ring_w, ring_center - side * ring_w, _a(RIM, alpha * 0.6), maxf(s * 0.04, 1.0))

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

# ---------- Interior ----------

# Interior visto de cima. "s" é o tamanho do quadradinho de chassi na tela (o interno tem s/2);
# "room_colors" pinta de leve cada sala
static func draw_interior(ci: CanvasItem, design: Array, interior: Dictionary, subs: Dictionary, room_of: Dictionary, origin: Vector2, offset: Vector2, s: float, room_colors: Array) -> void:
	for sub in subs:
		if subs[sub] != ShipInterior.LOCKED and ShipInterior.solid_at(subs, interior, sub) == "":
			_draw_grate(ci, sub_rect(sub, origin, offset, s), room_colors[room_of.get(sub, 0) % room_colors.size()])
	draw_static(ci, design.filter(func(p): return ShipParts.kind(p) != ShipParts.FLOOR), origin, offset, s)
	for sub in subs:
		var solid := ShipInterior.solid_at(subs, interior, sub)
		if subs[sub] != ShipInterior.LOCKED and solid != "":
			_draw_solid(ci, solid, sub, subs, interior, origin, offset, s)
	for sub in interior.blocks:
		var type: String = interior.blocks[sub]
		if not ShipInterior.BLOCKS[type].solid:
			draw_component(ci, type, sub_rect(sub, origin, offset, s).get_center(), s * 0.5)
	# Contorno de fora da nave
	for sub in subs:
		for n in ShipParts.NEIGHBORS:
			if not subs.has(sub + n):
				var pts := _side(sub_rect(sub, origin, offset, s), n)
				ci.draw_line(pts[0], pts[1], RIM, s * 0.1)

# Um bloco do interior sozinho (prévia do editor)
static func draw_block_preview(ci: CanvasItem, type: String, rect: Rect2, alpha: float) -> void:
	if ShipInterior.BLOCKS[type].solid:
		_draw_block_face(ci, type, rect, [true, true, true, true], alpha)
	else:
		draw_component(ci, type, rect.get_center(), rect.size.x, alpha)

static func sub_rect(sub: Vector2i, origin: Vector2, offset: Vector2, s: float) -> Rect2:
	return Rect2(origin + (Vector2(sub) * 0.5 - Vector2(0.5, 0.5) - offset) * s, Vector2.ONE * s * 0.5)

static func _draw_grate(ci: CanvasItem, rect: Rect2, tint: Color) -> void:
	ci.draw_rect(rect, GRATE)
	ci.draw_rect(rect, Color(tint, 0.16))
	var inner := rect.grow(-rect.size.x * 0.14)
	for k in 3:
		var y := inner.position.y + inner.size.y * (k + 0.5) / 3.0
		ci.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), GRATE_SLAT, maxf(rect.size.x * 0.1, 1.0))
	ci.draw_rect(rect, Color(0, 0, 0, 0.3), false, 1.0)

# Bloco sólido que se emenda com os vizinhos sólidos: só as bordas soltas ganham contorno e relevo;
# encostado em outro material aparece só uma emenda fina
static func _draw_solid(ci: CanvasItem, type: String, sub: Vector2i, subs: Dictionary, interior: Dictionary, origin: Vector2, offset: Vector2, s: float) -> void:
	var rect := sub_rect(sub, origin, offset, s)
	var open := []
	for n in ShipParts.NEIGHBORS:
		var other := ShipInterior.solid_at(subs, interior, sub + n) if subs.get(sub + n) != ShipInterior.LOCKED else ""
		open.append(other == "")
		if other != "" and other != type:
			var pts := _side(rect, n)
			ci.draw_line(pts[0], pts[1], Color(RIM, 0.6), 1.0)
	_draw_block_face(ci, type, rect, open, 1.0)
	# redesenha as emendas por cima do preenchimento
	for i in 4:
		var n: Vector2i = ShipParts.NEIGHBORS[i]
		var other := ShipInterior.solid_at(subs, interior, sub + n) if subs.get(sub + n) != ShipInterior.LOCKED else ""
		if other != "" and other != type:
			var pts := _side(rect, n)
			ci.draw_line(pts[0], pts[1], Color(RIM, 0.7), maxf(rect.size.x * 0.05, 1.0))

# Cara de um bloco sólido; "open" diz quais lados (direita, baixo, esquerda, cima) estão soltos
static func _draw_block_face(ci: CanvasItem, type: String, rect: Rect2, open: Array, alpha: float) -> void:
	var look: Array = BLOCK_LOOKS[type]
	var u := rect.size.x
	var w := maxf(u * 0.12, 1.0)
	ci.draw_rect(rect, _a(look[0], alpha))
	match type:
		"hull":
			_rivet(ci, rect.get_center(), u * 0.08, alpha)
		"wall_reinforced":
			var inner := rect.grow(-u * 0.2)
			ci.draw_line(inner.position, inner.end, _a(RIM, alpha * 0.55), maxf(u * 0.07, 1.0))
			ci.draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), _a(RIM, alpha * 0.55), maxf(u * 0.07, 1.0))
			for corner in [inner.position, inner.end, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y)]:
				_rivet(ci, corner, u * 0.06, alpha)
		"armor":
			for k in [0.3, 0.6, 0.9]:
				ci.draw_line(rect.position + Vector2(u * k, 0), rect.position + Vector2(0, u * k), _a(look[1], alpha * 0.45), maxf(u * 0.06, 1.0))
	for i in 4:
		if not open[i]:
			continue
		var n: Vector2i = ShipParts.NEIGHBORS[i]
		var pts := _side(rect, n)
		var inward := -Vector2(n)
		var lit := Vector2(n).dot(LIGHT_DIR) > 0.0
		ci.draw_line(pts[0] + inward * w * 1.1, pts[1] + inward * w * 1.1, _a(look[1] if lit else look[2], alpha), w)
		ci.draw_line(pts[0], pts[1], _a(RIM, alpha), w)

# Componente num quadradinho de lado "s" centrado em "center": caixa com relevo, luzinha e o desenho
# do componente na cor do sistema (amarelo = arma, azul = blindagem, laranja = motor)
static func draw_component(ci: CanvasItem, type: String, center: Vector2, s: float, alpha := 1.0) -> void:
	var color: Color = GROUP_COLORS[ShipInterior.BLOCKS[type].group]
	var u := s * 0.5
	var box := Rect2(center - Vector2.ONE * u * 0.86, Vector2.ONE * u * 1.72)
	ci.draw_rect(Rect2(box.position + Vector2(u * 0.1, u * 0.12), box.size), _a(Color(0, 0, 0, 0.4), alpha))
	var chamfer := u * 0.22
	_draw_bevel(ci, _chamfered_rect(box, [chamfer, chamfer, chamfer, chamfer]), Color(0.2, 0.22, 0.27), Color(0.45, 0.49, 0.56), Color(0.08, 0.09, 0.11), maxf(u * 0.1, 1.0), alpha)
	ci.draw_circle(box.position + Vector2(box.size.x - u * 0.32, u * 0.32), u * 0.1, _a(color.lightened(0.2), alpha))
	var c := _a(color, alpha)
	var dark := _a(ICON_DARK, alpha)
	var light := _a(color.lightened(0.45), alpha)
	var icon := center + Vector2(0, u * 0.06)
	var k := 0.8 # tamanho do desenho dentro da caixa
	match type:
		"autoloader": # engrenagem
			for t in 8:
				var dir := Vector2.from_angle(t * TAU / 8.0)
				ci.draw_colored_polygon(_bar(icon + dir * u * 0.3 * k, icon + dir * u * 0.62 * k, u * 0.11 * k), c)
			ci.draw_circle(icon, u * 0.44 * k, c)
			ci.draw_circle(icon + LIGHT_DIR * u * 0.05, u * 0.3 * k, light)
			ci.draw_circle(icon - LIGHT_DIR * u * 0.03, u * 0.29 * k, c)
			ci.draw_circle(icon, u * 0.15 * k, dark)
		"magazine": # pente: caixa comprida com as balas aparecendo
			var body := Rect2(icon - Vector2(u * 0.3, u * 0.6) * k, Vector2(u * 0.6, u * 1.2) * k)
			ci.draw_rect(body, c)
			ci.draw_rect(Rect2(body.position, Vector2(body.size.x * 0.25, body.size.y)), light)
			for t in 4:
				var y := body.position.y + body.size.y * (0.2 + t * 0.2)
				ci.draw_line(Vector2(body.position.x + body.size.x * 0.3, y), Vector2(body.end.x - body.size.x * 0.15, y), dark, maxf(u * 0.07, 1.0))
		"ammo": # três balas
			for t in [-1.0, 0.0, 1.0]:
				var x: float = icon.x + t * u * 0.36 * k
				ci.draw_rect(Rect2(x - u * 0.12 * k, icon.y - u * 0.12 * k, u * 0.24 * k, u * 0.62 * k), c)
				ci.draw_circle(Vector2(x, icon.y - u * 0.12 * k), u * 0.12 * k, light)
				ci.draw_line(Vector2(x - u * 0.12 * k, icon.y + u * 0.32 * k), Vector2(x + u * 0.12 * k, icon.y + u * 0.32 * k), dark, maxf(u * 0.05, 1.0))
		"fuel_tank": # tanque em pé com faixa e reflexo
			var tank := Rect2(icon - Vector2(u * 0.34, u * 0.36) * k, Vector2(u * 0.68, u * 0.72) * k)
			ci.draw_rect(tank, c)
			ci.draw_circle(icon + Vector2(0, -u * 0.36 * k), u * 0.34 * k, c)
			ci.draw_circle(icon + Vector2(0, u * 0.36 * k), u * 0.34 * k, c)
			ci.draw_line(icon + Vector2(-u * 0.2 * k, -u * 0.5 * k), icon + Vector2(-u * 0.2 * k, u * 0.4 * k), light, maxf(u * 0.08, 1.0))
			ci.draw_line(icon + Vector2(-u * 0.34 * k, 0), icon + Vector2(u * 0.34 * k, 0), dark, maxf(u * 0.08, 1.0))
		"fuel_pump": # roda com seta de fluxo
			ci.draw_circle(icon, u * 0.6 * k, c)
			ci.draw_arc(icon, u * 0.5 * k, PI, PI * 1.5, 8, light, maxf(u * 0.08, 1.0))
			ci.draw_colored_polygon(PackedVector2Array([
				icon + Vector2(-u * 0.26, -u * 0.32) * k, icon + Vector2(u * 0.36, 0) * k, icon + Vector2(-u * 0.26, u * 0.32) * k,
			]), dark)
		"armor", "wall", "wall_reinforced": # sólidos usam a cara de bloco, mas desenha algo se pedirem
			_draw_block_face(ci, type, box, [true, true, true, true], alpha)

# ---------- Ajudantes ----------

# Polígono preenchido com relevo: lados virados para a luz ficam claros, os do outro lado escuros
static func _draw_bevel(ci: CanvasItem, poly: PackedVector2Array, fill: Color, light: Color, shadow: Color, width: float, alpha: float) -> void:
	ci.draw_colored_polygon(poly, _a(fill, alpha))
	var middle := Vector2.ZERO
	for p in poly:
		middle += p
	middle /= poly.size()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var out := (b - a).orthogonal().normalized()
		if out.dot((a + b) * 0.5 - middle) < 0.0:
			out = -out
		var facing := out.dot(LIGHT_DIR)
		if absf(facing) < 0.3:
			continue
		ci.draw_line(a - out * width * 0.5, b - out * width * 0.5, _a(light if facing > 0.0 else shadow, alpha), width)

static func _rivet(ci: CanvasItem, pos: Vector2, r: float, alpha: float) -> void:
	ci.draw_circle(pos, r, _a(RIVET, alpha))
	ci.draw_circle(pos + LIGHT_DIR * r * 0.35, r * 0.45, _a(PLATE_LIGHT, alpha * 0.8))

# Retângulo com cantos cortados (cima-esq., cima-dir., baixo-dir., baixo-esq.); cortes maiores que zero
static func _chamfered_rect(rect: Rect2, chamfers: Array) -> PackedVector2Array:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	return PackedVector2Array([
		Vector2(x0 + chamfers[0], y0), Vector2(x1 - chamfers[1], y0), Vector2(x1, y0 + chamfers[1]),
		Vector2(x1, y1 - chamfers[2]), Vector2(x1 - chamfers[2], y1), Vector2(x0 + chamfers[3], y1),
		Vector2(x0, y1 - chamfers[3]), Vector2(x0, y0 + chamfers[0]),
	])

# As duas pontas do lado "n" (direita, baixo, esquerda ou cima) de um retângulo
static func _side(rect: Rect2, n: Vector2i) -> Array:
	if n == Vector2i.RIGHT:
		return [Vector2(rect.end.x, rect.position.y), rect.end]
	if n == Vector2i.DOWN:
		return [Vector2(rect.position.x, rect.end.y), rect.end]
	if n == Vector2i.LEFT:
		return [rect.position, Vector2(rect.position.x, rect.end.y)]
	return [rect.position, Vector2(rect.end.x, rect.position.y)]

static func _a(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)

static func _box(center: Vector2, along: Vector2, across: Vector2) -> PackedVector2Array:
	return PackedVector2Array([center + along + across, center + along - across, center - along - across, center - along + across])

# Retângulo de "from" até "to" com meia-largura "half_width"
static func _bar(from: Vector2, to: Vector2, half_width: float) -> PackedVector2Array:
	var across := (to - from).normalized().orthogonal() * half_width
	return PackedVector2Array([from + across, to + across, to - across, from - across])
