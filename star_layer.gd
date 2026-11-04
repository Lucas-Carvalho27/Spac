extends Node2D

# Uma camada de estrelas, desenhada uma vez só. O Parallax2D pai repete a camada sem fim
# e move ela mais devagar que a câmera (quanto menor o scroll_scale dele, mais longe parece).

@export var area := Vector2(1024, 1024) # tem que ser igual ao repeat_size do Parallax2D pai
@export var count := 160
@export var min_size := 0.5
@export var max_size := 1.1
@export var min_brightness := 0.25
@export var max_brightness := 0.55
@export var sky_seed := 1

const TINTS := [Color(1, 1, 1), Color(0.75, 0.85, 1), Color(1, 0.92, 0.75)]

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sky_seed
	for i in count:
		var pos := Vector2(rng.randf(), rng.randf()) * area
		var radius := rng.randf_range(min_size, max_size)
		var tint: Color = TINTS[rng.randi() % TINTS.size()]
		draw_circle(pos, radius, Color(tint, rng.randf_range(min_brightness, max_brightness)))
