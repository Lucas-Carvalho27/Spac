extends Node2D

# Espalha meteoros em volta da nave no começo; depois cada um se vira sozinho (ver meteor.gd)

@export var meteor_scene: PackedScene
@export var count := 10

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	for i in count:
		var meteor: Node2D = meteor_scene.instantiate()
		add_child(meteor)
		meteor.global_position = player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(250.0, 900.0)
