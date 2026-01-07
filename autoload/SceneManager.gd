# SceneManager.gd -- Autoload singleton
# Put this script as Autoload with name "SceneManager"
extends Node

var _cache: Dictionary = {}   # path -> PackedScene

func load_packed_scene(path: String) -> PackedScene:
	if path == "":
		push_error("SceneManager.load_packed_scene: empty path")
		return null
	if _cache.has(path):
		return _cache[path]
	var packed := ResourceLoader.load(path)
	if packed == null:
		push_error("SceneManager: Failed to load path: %s" % path)
		return null
	_cache[path] = packed
	return packed

func instantiate_scene(path: String) -> Node:
	var packed := load_packed_scene(path)
	if packed == null:
		return null
	return packed.instantiate()

func unload_packed_scene(path: String) -> void:
	if _cache.has(path):
		_cache.erase(path)
