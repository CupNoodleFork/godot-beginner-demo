extends CharacterBody2D

## A rat enemy with patrol, chase, and attack behaviors.
## Patrols using edge detection, chases the player when in range,
## and performs a leaping attack.

enum State {
	PATROL,
	CHASE,
	PAUSE,
	CHARGE,
	ATTACK,
	HIT,
}

@export_group("Movement")
@export var patrol_speed: float = 60.0
@export var chase_speed: float = 100.0
@export var gravity: float = 980.0

@export_group("Combat")
@export var detect_range: float = 120.0
@export var attack_range: float = 100.0
@export var attack_leap_speed: float = 250.0
@export var attack_leap_height: float = -50.0
@export var attack_cooldown: float = 3.0
@export var chase_duration: float = 1.5
@export var pause_duration: float = 0.8

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_fx: AnimatedSprite2D = $AttackFX
@onready var ray_left: RayCast2D = $RayLeft
@onready var ray_right: RayCast2D = $RayRight
@onready var hurt_box: Area2D = $HurtBox

var facing_direction: float = -1.0
var current_state: State = State.PATROL
var _attack_cooldown_timer: float = 0.0
var _chase_timer: float = 0.0
var _pause_timer: float = 0.0
var _player: CharacterBody2D = null


func _ready() -> void:
	animated_sprite.play("run")
	animated_sprite.animation_finished.connect(_on_animation_finished)
	attack_fx.animation_finished.connect(_on_attack_fx_finished)
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)


func _on_attack_fx_finished() -> void:
	attack_fx.visible = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

	# Find player if we don't have a reference yet
	if _player == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]

	match current_state:
		State.PATROL:
			_state_patrol()
		State.CHASE:
			_state_chase(delta)
		State.PAUSE:
			_state_pause(delta)
		State.CHARGE:
			velocity.x = 0.0
		State.ATTACK:
			_state_attack()
		State.HIT:
			velocity.x = move_toward(velocity.x, 0.0, patrol_speed * delta * 5.0)

	move_and_slide()
	global_position = global_position.round()

	animated_sprite.flip_h = facing_direction < 0.0


func _can_walk_forward() -> bool:
	if not is_on_floor():
		return true
	var front_ray := ray_left if facing_direction < 0.0 else ray_right
	return front_ray.is_colliding()


func _state_patrol() -> void:
	_play_anim("run")

	if is_on_wall():
		facing_direction *= -1.0
	elif is_on_floor():
		if not _can_walk_forward():
			# Try the other direction
			facing_direction *= -1.0
			if not _can_walk_forward():
				# Both sides are edges — stand still
				velocity.x = 0.0
				_play_anim("idle")
				# Still check for player
				if _player and _distance_to_player() < detect_range:
					_chase_timer = chase_duration
					current_state = State.CHASE
				return

	velocity.x = facing_direction * patrol_speed

	# Check if player is in detection range
	if _player and _distance_to_player() < detect_range:
		_chase_timer = chase_duration
		current_state = State.CHASE


func _state_chase(delta: float) -> void:
	if _player == null:
		current_state = State.PATROL
		return

	var dist := _distance_to_player()

	# Lost the player — go back to patrolling
	if dist > detect_range * 1.5:
		current_state = State.PATROL
		return

	# Chase timer — pause after chasing for a while
	_chase_timer -= delta
	if _chase_timer <= 0.0:
		_enter_pause()
		return

	# Face toward player
	facing_direction = signf(_player.global_position.x - global_position.x)
	velocity.x = facing_direction * chase_speed
	_play_anim("run")

	# Edge detection — don't run off platforms even when chasing
	if is_on_floor():
		var front_ray := ray_left if facing_direction < 0.0 else ray_right
		if not front_ray.is_colliding():
			velocity.x = 0.0

	# Close enough to attack — charge up first
	if dist < attack_range and _attack_cooldown_timer <= 0.0 and is_on_floor():
		_enter_charge()


func _enter_pause() -> void:
	current_state = State.PAUSE
	_pause_timer = pause_duration
	velocity.x = 0.0


func _state_pause(delta: float) -> void:
	velocity.x = 0.0
	_play_anim("idle")

	_pause_timer -= delta
	if _pause_timer <= 0.0:
		if _player and _distance_to_player() < detect_range:
			_chase_timer = chase_duration
			current_state = State.CHASE
		else:
			current_state = State.PATROL


func _state_attack() -> void:
	# Once landed, stop vertical movement and slide on ground
	if is_on_floor():
		velocity.y = 0.0
		velocity.x = move_toward(velocity.x, 0.0, attack_leap_speed * 0.02)


func _enter_charge() -> void:
	current_state = State.CHARGE
	velocity.x = 0.0
	animated_sprite.play("ability")


func _enter_attack() -> void:
	current_state = State.ATTACK
	velocity.x = facing_direction * attack_leap_speed
	velocity.y = attack_leap_height
	animated_sprite.play("attack")
	# Show attack FX overlay
	attack_fx.flip_h = facing_direction < 0.0
	attack_fx.visible = true
	attack_fx.play("attack_fx")


func _distance_to_player() -> float:
	if _player == null:
		return INF
	return abs(_player.global_position.x - global_position.x)


func _play_anim(anim_name: String) -> void:
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)


func _on_hurt_box_area_entered(area: Area2D) -> void:
	if current_state == State.HIT:
		return
	# Face toward the attacker
	var attacker_x := area.global_position.x
	if attacker_x < global_position.x:
		facing_direction = -1.0
	else:
		facing_direction = 1.0
	take_hit()


func take_hit() -> void:
	if current_state == State.HIT:
		return
	current_state = State.HIT
	attack_fx.visible = false
	animated_sprite.play("hit")


func _on_animation_finished() -> void:
	match current_state:
		State.HIT:
			current_state = State.PATROL
			animated_sprite.play("run")
		State.CHARGE:
			_enter_attack()
		State.ATTACK:
			_attack_cooldown_timer = attack_cooldown
			_enter_pause()
