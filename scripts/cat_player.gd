extends CharacterBody2D

## A 2D platformer character controller for a cat character.
## Supports movement, jumping, wall sliding, dashing, and attacking
## with a simple state machine driving animation selection.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum State {
	IDLE,
	RUN,
	JUMP,
	FALL,
	WALL_SLIDE,
	DASH,
	ATTACK,
	HIT,
}

# ---------------------------------------------------------------------------
# Exported parameters
# ---------------------------------------------------------------------------

@export_group("Movement")
@export var move_speed: float = 200.0
@export var gravity: float = 980.0
@export var jump_velocity: float = -350.0
@export var max_jumps: int = 2

@export_group("Wall Slide")
@export var wall_slide_gravity: float = 100.0

@export_group("Dash")
@export var dash_speed: float = 400.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.8

@export_group("Attack")
@export var attack_duration: float = 0.4

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_collision: CollisionShape2D = $CollisionShape2D
@onready var attack_area: Area2D = $AttackArea
@onready var attack_collision: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var hurt_box: Area2D = $HurtBox

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var current_state: State = State.IDLE
var facing_direction: float = 1.0  # 1.0 = right, -1.0 = left

# Dash bookkeeping
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var can_dash: bool = true
var dash_direction: float = 1.0

# Attack bookkeeping
var attack_timer: float = 0.0
var attack_in_air: bool = false

# Jump bookkeeping
var jump_count: int = 0

# ---------------------------------------------------------------------------
# Built-in callbacks
# ---------------------------------------------------------------------------

func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)


func _physics_process(delta: float) -> void:
	# Tick cooldown timers regardless of state.
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
		if dash_cooldown_timer <= 0.0:
			can_dash = true

	# Gather input once per frame.
	var input_direction: float = Input.get_axis("ui_left", "ui_right")
	var jump_pressed: bool = Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_accept")
	var dash_pressed: bool = Input.is_action_just_pressed("dash")
	var attack_pressed: bool = Input.is_action_just_pressed("attack")

	# Process current state.
	match current_state:
		State.IDLE:
			_state_idle(delta, input_direction, jump_pressed, dash_pressed, attack_pressed)
		State.RUN:
			_state_run(delta, input_direction, jump_pressed, dash_pressed, attack_pressed)
		State.JUMP:
			_state_jump(delta, input_direction, jump_pressed, dash_pressed, attack_pressed)
		State.FALL:
			_state_fall(delta, input_direction, jump_pressed, dash_pressed, attack_pressed)
		State.WALL_SLIDE:
			_state_wall_slide(delta, input_direction, jump_pressed, dash_pressed)
		State.DASH:
			_state_dash(delta)
		State.ATTACK:
			_state_attack(delta)
		State.HIT:
			_state_hit(delta)

	move_and_slide()
	global_position = global_position.round()
	_update_animation()

# ---------------------------------------------------------------------------
# Input map helpers -- ensure custom actions exist at runtime
# ---------------------------------------------------------------------------

## We map "dash" to Shift and "attack" to X / J.  If the actions are not
## already defined in the project InputMap we add them here so the script
## works out of the box.
func _enter_tree() -> void:
	_ensure_action("dash", [KEY_SHIFT])
	_ensure_action("attack", [KEY_X, KEY_J])


func _ensure_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		for key in keys:
			var event := InputEventKey.new()
			event.keycode = key
			InputMap.action_add_event(action_name, event)

# ---------------------------------------------------------------------------
# State implementations
# ---------------------------------------------------------------------------

func _state_idle(delta: float, input_dir: float, jump: bool, dash: bool, attack: bool) -> void:
	# Apply gravity while on ground (keeps the body snapped to the floor).
	_apply_gravity(delta)

	velocity.x = move_toward(velocity.x, 0.0, move_speed)

	if attack:
		_enter_attack()
		return

	if dash and can_dash:
		_enter_dash()
		return

	if jump and is_on_floor():
		_enter_jump()
		return

	if input_dir != 0.0:
		_change_state(State.RUN)
		return

	if not is_on_floor():
		_change_state(State.FALL)
		return


func _state_run(delta: float, input_dir: float, jump: bool, dash: bool, attack: bool) -> void:
	_apply_gravity(delta)
	velocity.x = input_dir * move_speed

	if input_dir != 0.0:
		facing_direction = signf(input_dir)

	if attack:
		_enter_attack()
		return

	if dash and can_dash:
		_enter_dash()
		return

	if jump and is_on_floor():
		_enter_jump()
		return

	if not is_on_floor():
		_change_state(State.FALL)
		return

	if input_dir == 0.0:
		_change_state(State.IDLE)
		return


func _state_jump(delta: float, input_dir: float, jump: bool, dash: bool, attack: bool) -> void:
	_apply_gravity(delta)
	velocity.x = input_dir * move_speed

	if input_dir != 0.0:
		facing_direction = signf(input_dir)

	if attack:
		_enter_attack()
		return

	if dash and can_dash:
		_enter_dash()
		return

	if jump and jump_count < max_jumps:
		_enter_jump()
		return

	if velocity.y >= 0.0:
		_change_state(State.FALL)
		return

	if is_on_floor():
		_change_state(State.IDLE)
		return


func _state_fall(delta: float, input_dir: float, jump: bool, dash: bool, attack: bool) -> void:
	_apply_gravity(delta)
	velocity.x = input_dir * move_speed

	if input_dir != 0.0:
		facing_direction = signf(input_dir)

	if attack:
		_enter_attack()
		return

	if dash and can_dash:
		_enter_dash()
		return

	if jump and jump_count < max_jumps:
		_enter_jump()
		return

	# Transition to wall slide when pressing into a wall while airborne.
	if is_on_wall() and input_dir != 0.0:
		_change_state(State.WALL_SLIDE)
		return

	if is_on_floor():
		if input_dir != 0.0:
			_change_state(State.RUN)
		else:
			_change_state(State.IDLE)
		return


func _state_wall_slide(delta: float, input_dir: float, jump: bool, dash: bool) -> void:
	# Reduced gravity so the cat slides down slowly.
	velocity.y = move_toward(velocity.y, wall_slide_gravity, wall_slide_gravity * delta)
	velocity.x = input_dir * move_speed

	# Face away from the wall (back against the wall)
	if input_dir != 0.0:
		facing_direction = -signf(input_dir)

	if dash and can_dash:
		_enter_dash()
		return

	if jump:
		_enter_jump()
		return

	if is_on_floor():
		_change_state(State.IDLE)
		return

	# Leave wall slide if no longer on a wall or not pressing toward it.
	if not is_on_wall() or input_dir == 0.0:
		_change_state(State.FALL)
		return


func _state_dash(delta: float) -> void:
	dash_timer -= delta
	velocity.y = 0.0
	velocity.x = dash_direction * dash_speed

	if dash_timer <= 0.0:
		velocity.x = 0.0
		if is_on_floor():
			_change_state(State.IDLE)
		else:
			_change_state(State.FALL)


func _state_hit(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 5.0)


func _state_attack(delta: float) -> void:
	_apply_gravity(delta)
	# Slow horizontal movement to near zero during attack.
	velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 5.0)

	attack_timer -= delta
	if attack_timer <= 0.0:
		_end_attack()

# ---------------------------------------------------------------------------
# State transition helpers
# ---------------------------------------------------------------------------

func _change_state(new_state: State) -> void:
	if new_state == State.IDLE or new_state == State.RUN:
		jump_count = 0
	current_state = new_state


func _enter_jump() -> void:
	velocity.y = jump_velocity
	jump_count += 1
	_change_state(State.JUMP)


func _enter_dash() -> void:
	can_dash = false
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_direction = facing_direction
	_change_state(State.DASH)


func _end_attack() -> void:
	attack_collision.disabled = true
	attack_area.collision_layer = 0
	if is_on_floor():
		_change_state(State.IDLE)
	else:
		_change_state(State.FALL)


func _enter_attack() -> void:
	attack_timer = attack_duration
	attack_in_air = not is_on_floor()
	# Enable attack hitbox and position it in front of the cat.
	attack_collision.position.x = abs(attack_collision.position.x) * facing_direction
	attack_collision.disabled = false
	attack_area.collision_layer = 2
	_change_state(State.ATTACK)

# ---------------------------------------------------------------------------
# Physics helpers
# ---------------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _update_animation() -> void:
	# Flip sprite based on facing direction.
	animated_sprite.flip_h = facing_direction < 0.0

	# Offset sprite toward wall during wall slide so it appears flush
	if current_state == State.WALL_SLIDE:
		animated_sprite.position.x = -facing_direction * 10.0
	else:
		animated_sprite.position.x = 0.0

	var anim_name: String = _animation_for_state()
	if animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)


func _animation_for_state() -> String:
	match current_state:
		State.IDLE:
			return "idle"
		State.RUN:
			return "run"
		State.JUMP:
			return "double_jump" if jump_count >= 2 else "jump"
		State.FALL:
			return "fall"
		State.WALL_SLIDE:
			return "wall_slide"
		State.DASH:
			return "dash"
		State.ATTACK:
			return "jump_attack" if attack_in_air else "attack"
		State.HIT:
			return "take_damage"
	return "idle"

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_hurt_box_area_entered(_area: Area2D) -> void:
	if current_state == State.HIT or current_state == State.DASH:
		return
	# Disable attack hitbox if we get hit during attack
	if current_state == State.ATTACK:
		attack_collision.disabled = true
		attack_area.collision_layer = 0
	_change_state(State.HIT)


func _on_animation_finished() -> void:
	# When a one-shot animation finishes, return to the appropriate state.
	match current_state:
		State.ATTACK:
			_end_attack()
		State.DASH:
			if is_on_floor():
				_change_state(State.IDLE)
			else:
				_change_state(State.FALL)
		State.HIT:
			if is_on_floor():
				_change_state(State.IDLE)
			else:
				_change_state(State.FALL)
