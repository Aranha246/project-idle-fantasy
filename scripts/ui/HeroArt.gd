class_name HeroArt
extends Control
## Procedurally drawn, smoothly animated hero.
##
## The project ships no raster art, so the hero is rendered entirely in code —
## the same approach already used for the rarity-tinted item gems in `GameTheme`.
## It runs a small animation state machine whose pose follows the player's active
## quest, so the character visibly *does* what the quest describes:
##
##   * IDLE    — breathing in place, weapon sheathed
##   * EXPLORE — striding forward with a raised torch
##   * BATTLE  — lunging with a swinging sword
##   * GATHER  — crouched, swinging a pickaxe at the ground
##
## Every pose is driven by a continuous time value, so transitions are smooth
## rather than frame-snapped. Being a `Control` it drops into any container.

enum Pose { IDLE, EXPLORE, BATTLE, GATHER }

const DESIGN_SIZE: float = 140.0

const SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.30)
const CAPE_COLOR: Color = Color(0.352941, 0.243137, 0.541176, 1.0)
const TUNIC_COLOR: Color = Color(0.415686, 0.360784, 0.639216, 1.0)
const TUNIC_LIGHT: Color = Color(0.545098, 0.490196, 0.788235, 1.0)
const ARMOR_COLOR: Color = Color(0.588235, 0.639216, 0.760784, 1.0)
const SKIN_COLOR: Color = Color(0.933333, 0.784314, 0.615686, 1.0)
const LEG_COLOR: Color = Color(0.239216, 0.243137, 0.341176, 1.0)
const WEAPON_COLOR: Color = Color(0.827451, 0.850980, 0.901961, 1.0)
const WEAPON_GRIP: Color = Color(0.435294, 0.294118, 0.156863, 1.0)
const TORCH_FLAME: Color = Color(1.0, 0.717647, 0.290196, 1.0)
const ACCENT: Color = Color(0.623529, 0.482353, 0.921569, 1.0)

var _pose: Pose = Pose.IDLE
var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(DESIGN_SIZE, DESIGN_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

	SignalBus.quest_started.connect(_on_quest_started)
	SignalBus.quest_claimed.connect(_on_quest_claimed)
	SignalBus.quests_refreshed.connect(_on_quests_refreshed)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Switches the animation. Changing pose restarts the clock so each action starts
## from a clean, recognisable key frame rather than mid-swing.
func set_pose(pose: Pose) -> void:
	if _pose == pose:
		return
	_pose = pose
	_time = 0.0
	queue_redraw()


func get_pose() -> Pose:
	return _pose


# --- Animation state -------------------------------------------------------

func _on_quest_started(quest: Resource, _duration: float) -> void:
	set_pose(_pose_for_quest(quest))


func _on_quest_claimed(_rewards: Dictionary) -> void:
	set_pose(Pose.IDLE)


func _on_quests_refreshed() -> void:
	if QuestManager.is_quest_running():
		set_pose(_pose_for_quest(QuestManager.get_active_quest()))
	else:
		set_pose(Pose.IDLE)


func _pose_for_quest(quest: Resource) -> Pose:
	var quest_data: QuestData = quest as QuestData
	if quest_data == null:
		return Pose.IDLE
	match quest_data.quest_type:
		QuestData.QuestType.BATTLE:
			return Pose.BATTLE
		QuestData.QuestType.EXPLORE:
			return Pose.EXPLORE
		QuestData.QuestType.GATHER:
			return Pose.GATHER
	return Pose.IDLE


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var shortest: float = minf(size.x, size.y)
	if shortest <= 4.0:
		return
	var k: float = shortest / DESIGN_SIZE
	var feet: Vector2 = Vector2(size.x * 0.5, size.y * 0.94)

	# --- per-pose animation channels ---
	var bob: float = 0.0        # vertical bounce
	var lean: float = 0.0       # forward lean
	var crouch: float = 0.0     # knee bend
	var stride: float = 0.0     # leg swing amount (-1..1)
	var swing: float = 0.0      # weapon swing amount (-1..1)
	match _pose:
		Pose.EXPLORE:
			bob = absf(sin(_time * 6.0)) * 3.0
			lean = sin(_time * 6.0) * 0.10
			stride = sin(_time * 6.0)
		Pose.BATTLE:
			bob = absf(sin(_time * 5.0)) * 2.0
			lean = 0.16
			stride = sin(_time * 5.0) * 0.4
			swing = sin(_time * 9.0)
		Pose.GATHER:
			bob = absf(sin(_time * 7.0)) * 1.5
			lean = 0.14
			crouch = 7.0
			swing = sin(_time * 7.0)
		_:
			bob = sin(_time * 2.0) * 1.6
			swing = sin(_time * 2.0) * 0.2

	var hip: Vector2 = Vector2(feet.x + lean * 16.0 * k, feet.y - (40.0 - crouch + bob) * k)
	var shoulder: Vector2 = Vector2(hip.x + lean * 8.0 * k, hip.y - 30.0 * k)
	var head: Vector2 = Vector2(shoulder.x + lean * 4.0 * k, shoulder.y - 15.0 * k)

	# Soft ground shadow that shrinks as the hero rises.
	draw_circle(Vector2(feet.x, feet.y), (17.0 - bob * 0.4) * k, SHADOW_COLOR)

	_draw_cape(feet, shoulder, k, swing)
	_draw_legs(feet, hip, k, stride)
	_draw_torso(hip, shoulder, k, lean)
	_draw_arms(shoulder, k, lean, swing)
	_draw_head(head, k)
	_draw_weapon(shoulder, k, lean, swing)
	if _pose == Pose.GATHER:
		_draw_sparkles(feet, k)


func _draw_cape(feet: Vector2, shoulder: Vector2, k: float, swing: float) -> void:
	var sway: float = sin(_time * 3.0) * 4.0 * k + swing * 3.0 * k
	var top: Vector2 = shoulder + Vector2(-6.0 * k, -2.0 * k)
	var cape: PackedVector2Array = PackedVector2Array([
		top,
		top + Vector2(-4.0 * k, 18.0 * k),
		Vector2(feet.x - 14.0 * k + sway, feet.y - 6.0 * k),
		Vector2(feet.x - 2.0 * k + sway, feet.y - 4.0 * k),
	])
	draw_colored_polygon(cape, CAPE_COLOR)


func _draw_legs(feet: Vector2, hip: Vector2, k: float, stride: float) -> void:
	var leg_len: float = (feet.y - 4.0 * k) - hip.y
	var foot_l: Vector2 = Vector2(feet.x - 7.0 * k, hip.y + leg_len - absf(stride) * 3.0 * k)
	var foot_r: Vector2 = Vector2(feet.x + 7.0 * k, hip.y + leg_len - absf(-stride) * 3.0 * k)
	draw_line(hip + Vector2(-3.0 * k, 0.0), foot_l, LEG_COLOR, 7.0 * k, true)
	draw_line(hip + Vector2(3.0 * k, 0.0), foot_r, LEG_COLOR, 7.0 * k, true)
	# Boots.
	draw_circle(foot_l, 4.0 * k, LEG_COLOR.darkened(0.25))
	draw_circle(foot_r, 4.0 * k, LEG_COLOR.darkened(0.25))


func _draw_torso(hip: Vector2, shoulder: Vector2, k: float, lean: float) -> void:
	var body: PackedVector2Array = PackedVector2Array([
		hip + Vector2(-9.0 * k, 2.0 * k),
		hip + Vector2(9.0 * k, 2.0 * k),
		shoulder + Vector2(8.0 * k, 2.0 * k),
		shoulder + Vector2(-8.0 * k, 2.0 * k),
	])
	draw_colored_polygon(body, TUNIC_COLOR)
	# Lit front face for a sense of volume.
	var front: PackedVector2Array = PackedVector2Array([
		hip + Vector2(1.0 * k, 2.0 * k),
		hip + Vector2(9.0 * k, 2.0 * k),
		shoulder + Vector2(8.0 * k, 2.0 * k),
		shoulder + Vector2(1.0 * k + lean * 3.0 * k, 2.0 * k),
	])
	draw_colored_polygon(front, TUNIC_LIGHT)
	# Belt.
	draw_line(hip + Vector2(-9.0 * k, 0.0), hip + Vector2(9.0 * k, 0.0), WEAPON_GRIP, 3.0 * k, true)


func _draw_arms(shoulder: Vector2, k: float, lean: float, swing: float) -> void:
	var arm_len: float = 20.0 * k
	# Rear arm.
	var rear: Vector2 = shoulder + Vector2(-7.0 * k, 3.0 * k)
	draw_line(rear, rear + Vector2(-3.0 * k, arm_len * 0.7), ARMOR_COLOR, 5.0 * k, true)
	# Front arm reaches toward the weapon / torch.
	var front_angle: float = -0.6 + swing * 0.5 + lean
	var front: Vector2 = shoulder + Vector2(6.0 * k, 2.0 * k)
	var hand: Vector2 = front + Vector2(cos(front_angle), sin(front_angle)) * arm_len
	draw_line(front, hand, ARMOR_COLOR, 5.0 * k, true)
	draw_circle(hand, 3.0 * k, SKIN_COLOR)


func _draw_head(head: Vector2, k: float) -> void:
	draw_circle(head, 10.0 * k, SKIN_COLOR)
	# Helm: a dome plus a nose guard.
	draw_circle(head + Vector2(0.0, -2.0 * k), 10.5 * k, ARMOR_COLOR)
	draw_rect(Rect2(head + Vector2(-10.5 * k, -4.0 * k), Vector2(21.0 * k, 6.0 * k)), ARMOR_COLOR, true)
	draw_line(head + Vector2(0.0, -12.0 * k), head + Vector2(0.0, 8.0 * k), ARMOR_COLOR.darkened(0.2), 2.0 * k, true)
	# Crest accent.
	draw_line(head + Vector2(-2.0 * k, -11.0 * k), head + Vector2(6.0 * k, -16.0 * k), ACCENT, 2.5 * k, true)


func _draw_weapon(shoulder: Vector2, k: float, lean: float, swing: float) -> void:
	var grip: Vector2 = shoulder + Vector2(11.0 * k, 18.0 * k)
	if _pose == Pose.EXPLORE:
		# Raised torch with a flickering flame.
		var flame: Vector2 = grip + Vector2(6.0 * k, -24.0 * k)
		draw_line(grip, flame, WEAPON_GRIP, 3.0 * k, true)
		var flicker: float = 1.0 + sin(_time * 18.0) * 0.18
		draw_circle(flame, 6.0 * k * flicker, TORCH_FLAME)
		draw_circle(flame, 3.0 * k * flicker, Color(1.0, 0.945098, 0.729412, 1.0))
		return

	if _pose == Pose.GATHER:
		# Pickaxe head that swings with `swing`.
		var angle: float = -1.1 + (swing * 0.5 + 0.5) * 1.6
		var tip: Vector2 = grip + Vector2(cos(angle), sin(angle)) * 26.0 * k
		draw_line(grip, tip, WEAPON_GRIP, 3.0 * k, true)
		var head_dir: Vector2 = Vector2(cos(angle + PI * 0.5), sin(angle + PI * 0.5))
		draw_line(tip - head_dir * 7.0 * k, tip + head_dir * 7.0 * k, WEAPON_COLOR, 3.0 * k, true)
		return

	# Battle / idle: a sword whose blade angle follows `swing`.
	var blade_angle: float = -1.2 + swing * 1.1 + lean
	var blade_tip: Vector2 = grip + Vector2(cos(blade_angle), sin(blade_angle)) * (30.0 * k)
	draw_line(grip, blade_tip, WEAPON_COLOR, 3.5 * k, true)
	draw_line(grip + Vector2(-4.0 * k, 0.0), grip + Vector2(4.0 * k, 0.0), WEAPON_GRIP, 3.0 * k, true)
	if _pose == Pose.BATTLE:
		# Motion arc trailing the blade tip.
		draw_arc(grip, 30.0 * k, blade_angle - 0.5, blade_angle, 12, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45), 2.0 * k, true)


func _draw_sparkles(feet: Vector2, k: float) -> void:
	for i: int in 4:
		var phase: float = _time * 5.0 + float(i) * 1.7
		var rise: float = fposmod(phase, 1.0)
		var offset_x: float = sin(phase * 3.0) * 10.0 * k
		var position: Vector2 = Vector2(feet.x + offset_x, feet.y - rise * 26.0 * k)
		var alpha: float = 1.0 - rise
		draw_circle(position, 2.0 * k * (1.0 - rise * 0.5), Color(TORCH_FLAME.r, TORCH_FLAME.g, TORCH_FLAME.b, alpha))
