extends NavigationRegion2D


func InitNavRegion():
	pass
	var nav_polygon = NavigationPolygon.new()
	
	var polygon = PackedVector2Array([
		Vector2(0,0),
		Vector2(1368,0),
		Vector2(1360,768),
		Vector2(0,768)
	])
	
	nav_polygon.clear_outlines()
	nav_polygon.add_outline(polygon)
	nav_polygon.make_polygons_from_outlines()
	
	navigation_polygon = nav_polygon
	
	bake_navigation_polygon()


func _on_nav_timer_timeout() -> void:
	InitNavRegion()
