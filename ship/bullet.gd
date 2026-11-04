extends Area2D

@export var speed := 900.0
@export var lifetime := 1.2 # segundos até sumir sozinho

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free) # false = para enquanto o jogo está pausado

func _physics_process(delta: float) -> void:
	position += transform.x * speed * delta

func _on_area_entered(area: Area2D) -> void:
	if area.has_method("hit"):
		area.hit()
		queue_free()
