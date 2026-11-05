class_name HeroArt
extends Control
## Animated pixel-art hero, rendered from authored sprite frames.
##
## The hero sprite sheet is authored in PixelLab and shipped as per-frame PNGs
## under `res://assets/sprites/hero`. This control plays the frame sequence that
## matches the player's active quest, so the character visibly *does* what the
## quest describes:
##
##   * IDLE    — breathing in place
##   * EXPLORE — striding forward
##   * BATTLE  — throwing a punch / swinging at the enemy
##   * GATHER  — crouching to pick something up
##
## Playback is time driven so frame timing stays smooth and independent of the
## display refresh rate. Being a `Control` it drops straight into any container.

enum Pose { IDLE, EXPLORE, BATTLE, GATHER }

const DESIGN_SIZE: float = 140.0
const SPRITE_DIR: String = "res://assets/sprites/hero/"

## Frame file stem for each pose, indexed by `Pose`.
const POSE_FILES: Array[String] = ["idle", "explore", "battle", "gather"]
## Number of shipped frames for each pose, indexed by `Pose`.
const POSE_FRAME_COUNTS: Array[int] = [4, 6, 6, 5]
## Playback rate for each pose, indexed by `Pose` (frames per second).
const POSE_FPS: Array[float] = [6.0, 8.0, 10.0, 8.0]

var _pose: Pose = Pose.IDLE
var _frame_time: float = 0.0
var _frames: Dictionary = {}
var _display: TextureRect
var _current_index: int = -1


func _ready() -> void:
	custom_minimum_size = Vector2(DESIGN_SIZE, DESIGN_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_display = TextureRect.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_display)

	_load_frames()
	set_process(true)

	SignalBus.quest_started.connect(_on_quest_started)
	SignalBus.quest_claimed.connect(_on_quest_claimed)
	SignalBus.quests_refreshed.connect(_on_quests_refreshed)

	_apply_frame()


func _process(delta: float) -> void:
	_frame_time += delta
	_apply_frame()


## Switches the animation. Changing pose restarts the clip so each action starts
## from a clean, recognisable key frame rather than mid-swing.
func set_pose(pose: Pose) -> void:
	if _pose == pose:
		return
	_pose = pose
	_frame_time = 0.0
	_current_index = -1
	_apply_frame()


func get_pose() -> Pose:
	return _pose


## Number of loaded frames for the current pose (0 when the art is missing).
func get_frame_count() -> int:
	return (_frames.get(int(_pose), []) as Array).size()


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


# --- Playback --------------------------------------------------------------

## Loads every shipped frame per pose. A pose whose art is absent simply plays
## nothing rather than falling back to a drawn placeholder.
func _load_frames() -> void:
	for pose_index: int in POSE_FILES.size():
		var frames: Array[Texture2D] = []
		for frame_index: int in POSE_FRAME_COUNTS[pose_index]:
			var path: String = "%s%s_%d.png" % [SPRITE_DIR, POSE_FILES[pose_index], frame_index]
			if not ResourceLoader.exists(path):
				continue
			var texture: Texture2D = load(path) as Texture2D
			if texture != null:
				frames.append(texture)
		_frames[pose_index] = frames


func _apply_frame() -> void:
	if _display == null:
		return
	var frames: Array = _frames.get(int(_pose), [])
	if frames.is_empty():
		_display.texture = null
		_current_index = -1
		return
	var count: int = frames.size()
	var index: int = int(_frame_time * POSE_FPS[int(_pose)]) % count
	if index == _current_index:
		return
	_current_index = index
	_display.texture = frames[index]
