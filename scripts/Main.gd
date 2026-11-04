extends Node2D
## Root scene controller.
##
## Mounts every UI scene on its own CanvasLayer so the interface renders above
## the game world, stays fixed on screen and is unaffected by any Camera2D.
## Scenes are loaded defensively: a missing or broken file logs an error and is
## skipped instead of crashing the game.

## UI scenes to mount, in draw order (later entries render on top).
const UI_SCENES: Array[String] = [
	"res://scenes/ui/HUD.tscn",
	"res://scenes/ui/InventoryUI.tscn",
]

## CanvasLayer level used to host UI scenes that are not one already.
const UI_LAYER: int = 1


func _ready() -> void:
	for scene_path: String in UI_SCENES:
		_mount_ui_scene(scene_path)


## Loads `scene_path` and mounts it under a screen-fixed CanvasLayer.
func _mount_ui_scene(scene_path: String) -> void:
	var instance: Node = _instantiate_scene(scene_path)
	if instance == null:
		return

	# Scenes that are already a CanvasLayer host themselves.
	if instance is CanvasLayer:
		add_child(instance)
		return

	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.name = "%sLayer" % instance.name
	ui_layer.layer = UI_LAYER
	add_child(ui_layer)
	ui_layer.add_child(instance)


## Validates and instantiates `scene_path`, returning null (with an error
## logged) when the resource is missing or cannot be turned into a node.
func _instantiate_scene(scene_path: String) -> Node:
	if not ResourceLoader.exists(scene_path):
		push_error("Main: UI scene not found at '%s'." % scene_path)
		return null
	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Main: '%s' is not a valid PackedScene." % scene_path)
		return null
	var instance: Node = packed_scene.instantiate()
	if instance == null:
		push_error("Main: failed to instantiate '%s'." % scene_path)
		return null
	return instance
