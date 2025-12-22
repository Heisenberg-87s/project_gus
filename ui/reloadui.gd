extends Control



func _on_playground_pressed() -> void:
	get_tree().change_scene_to_file("res://playground.tscn")


func _on_crawl_test_pressed() -> void:
	get_tree().change_scene_to_file("res://crawl_test.tscn")
