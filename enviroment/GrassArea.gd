extends Area2D
class_name GrassArea
@export var is_grass_area: bool = true

func _ready():
	add_to_group("grass") # ไม่บังคับแต่ช่วยให้จัดการง่ายขึ้น
