extends Area2D

# Meteoro: pedra com formato sorteado que gira e anda à deriva. Leva alguns tiros, se parte
# em pedaços e nasce de novo fora da tela, perto da nave. Não ataca.

@export var max_health := 4
@export var respawn_delay := 1.0 # segundos até nascer de novo
@export var min_radius := 16.0
@export var max_radius := 42.0
@export var max_drift := 40.0 # velocidade máxima à deriva (px/s)
@export var max_distance := 1600.0 # se ficar mais longe que isso da nave, reaparece perto dela

const ROCK := Color(0.44, 0.39, 0.35)
const ROCK_LIGHT := Color(0.58, 0.52, 0.46)
const ROCK_DARK := Color(0.16, 0.14, 0.13)
const CRATER := Color(0.3, 0.26, 0.24)

var health := max_health
var radius := 20.0
var drift := Vector2.ZERO
var spin := 0.0
var outline := PackedVector2Array()
var craters := [] # [posição, raio]
var dead := false

@onready var collision: CollisionPolygon2D = $CollisionPolygon2D

func _ready() -> void:
	_new_rock()

# Sorteia um formato novo de pedra
func _new_rock() -> void:
	radius = randf_range(min_radius, max_radius)
	var count := randi_range(9, 13)
	outline = PackedVector2Array()
	for i in count:
		var angle := TAU * (i + randf_range(-0.3, 0.3)) / count
		outline.append(Vector2.from_angle(angle) * radius * randf_range(0.72, 1.08))
	collision.polygon = outline
	craters.clear()
	for i in randi_range(2, 4):
		craters.append([Vector2.from_angle(randf() * TAU) * radius * randf_range(0.0, 0.5), radius * randf_range(0.12, 0.24)])
	drift = Vector2.from_angle(randf() * TAU) * randf_range(5.0, max_drift)
	spin = randf_range(-0.8, 0.8)
	health = max_health
	modulate = Color.WHITE
	queue_redraw() # desenhada uma vez só por pedra nova; depois só gira e anda

func _physics_process(delta: float) -> void:
	position += drift * delta
	rotation += spin * delta
	var player := _player()
	if not dead and player != null and global_position.distance_to(player.global_position) > max_distance:
		global_position = _spawn_point()

func hit() -> void:
	if dead:
		return
	health -= 1
	if health > 0:
		# Pisca branco quando leva tiro
		modulate = Color(3, 3, 3)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.12)
	else:
		_die()

func _die() -> void:
	dead = true
	collision.set_deferred("disabled", true)
	_burst()
	hide()
	await get_tree().create_timer(respawn_delay, false).timeout # false = para enquanto o jogo está pausado
	global_position = _spawn_point()
	_new_rock()
	collision.disabled = false
	dead = false
	show()

# Pedacinhos de pedra voando para todo lado
func _burst() -> void:
	var fade := Gradient.new()
	fade.colors = PackedColorArray([ROCK_LIGHT, Color(ROCK, 0.0)])
	var debris := CPUParticles2D.new()
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = int(radius * 0.6)
	debris.lifetime = 0.9
	debris.spread = 180.0
	debris.gravity = Vector2.ZERO
	debris.initial_velocity_min = 40.0
	debris.initial_velocity_max = 150.0
	debris.damping_min = 30.0
	debris.damping_max = 60.0
	debris.scale_amount_min = 2.0
	debris.scale_amount_max = radius * 0.15
	debris.angular_velocity_min = -300.0
	debris.angular_velocity_max = 300.0
	debris.color_ramp = fade
	get_parent().add_child(debris)
	debris.global_position = global_position
	debris.emitting = true
	debris.finished.connect(debris.queue_free)

# Fora da tela, perto da nave, para o meteoro aparecer vindo de longe
func _spawn_point() -> Vector2:
	var player := _player()
	var center := player.global_position if player != null else global_position
	var away := get_viewport_rect().size.length() * 0.5 + radius + randf_range(50.0, 400.0)
	return center + Vector2.from_angle(randf() * TAU) * away

func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _draw() -> void:
	# Lado iluminado da pedra (gira junto com ela)
	var light := Vector2(-1, -1).normalized() * radius * 0.12
	draw_colored_polygon(outline, ROCK)
	var lit := PackedVector2Array()
	for p in outline:
		lit.append(p * 0.72 + light)
	draw_colored_polygon(lit, ROCK_LIGHT)
	for crater in craters:
		draw_circle(crater[0], crater[1], CRATER)
		draw_arc(crater[0], crater[1], 0.0, TAU, 16, ROCK_DARK, 1.5)
		draw_circle(crater[0] - light * 0.4, crater[1] * 0.55, Color(CRATER, 0.6).darkened(0.25))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, ROCK_DARK, 2.5, true)
