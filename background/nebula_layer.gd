extends Node2D

# Manchas de nebulosa, desenhadas uma vez só (o Parallax2D pai repete e move a camada).
# Cada mancha são várias bolas bem transparentes umas sobre as outras, que ficam com borda suave.

@export var area := Vector2(2048, 2048) # tem que ser igual ao repeat_size do Parallax2D pai
@export var count := 5
@export var sky_seed := 99

const COLORS := [Color(0.45, 0.2, 0.7), Color(0.15, 0.35, 0.8), Color(0.1, 0.55, 0.6), Color(0.7, 0.22, 0.4)]

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sky_seed
	for n in count:
		var pos := Vector2(rng.randf(), rng.randf()) * area
		var radius := rng.randf_range(260.0, 520.0)
		var color: Color = COLORS[rng.randi() % COLORS.size()]
		for blob in 3:
			var blob_pos := pos + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.5
			var blob_radius := radius * rng.randf_range(0.5, 0.9)
			for ring in 12:
				draw_circle(blob_pos, blob_radius * (1.0 - ring * 0.075), Color(color, 0.011))
