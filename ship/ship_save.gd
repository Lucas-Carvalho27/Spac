# Salva e carrega a nave: as peças do chassi e o interior (paredes e componentes).

const ShipParts = preload("res://ship/ship_parts.gd")
const ShipInterior = preload("res://ship/ship_interior.gd")

const SAVE_PATH := "user://nave_v2.json" # v2: peças de tamanhos diferentes

static func save_ship(parts: Array, interior: Dictionary) -> void:
	var data := {"parts": ShipParts.to_json(parts), "interior": ShipInterior.to_json(interior)}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

# {"parts": Array, "interior": Dictionary}. Arquivos antigos (só a lista de peças) continuam valendo.
static func load_ship() -> Dictionary:
	var data = null
	if FileAccess.file_exists(SAVE_PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Array:
		data = {"parts": data}
	if not (data is Dictionary):
		data = {}
	var parts := ShipParts.from_json(data.get("parts"))
	return {"parts": parts, "interior": ShipInterior.cleaned(parts, ShipInterior.from_json(data.get("interior")))}
