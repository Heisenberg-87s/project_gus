extends Node

# AutoLoad singleton to track and save the current scene path (Godot 4)
# Add this file as an AutoLoad (Project -> Project Settings -> AutoLoad) with the name "SaveManager".

const SAVE_PATH: String = "user://save_game.save"
var last_scene_path: String = ""  # เก็บ path ของ scene ปัจจุบัน เช่น "res://scenes/level1.tscn"

func set_current_scene_path(path: String) -> void:
	last_scene_path = path

# เปลี่ยน scene ผ่าน SaveManager เพื่อให้มัน track path ให้อัตโนมัติ
func change_scene_and_track(path: String) -> int:
	var err := get_tree().change_scene_to_file(path)
	if err == OK:
		last_scene_path = path
	return err

# บันทึก path ที่เก็บไว้ลง disk (user://)
func save_current_scene_to_disk() -> bool:
	if last_scene_path == "":
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_line(last_scene_path)
	f.close()
	return true

# อ่าน path จากไฟล์ save หากมี
func load_saved_scene_path() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return ""
	var p := f.get_line().strip_edges()
	f.close()
	return p

# โหลด scene ที่บันทึกไว้ (คืนค่า error code จาก change_scene_to_file หรือ -1 ถ้าไม่มี save)
func load_saved_scene() -> int:
	var p := load_saved_scene_path()
	if p == "":
		return -1
	return change_scene_and_track(p)
