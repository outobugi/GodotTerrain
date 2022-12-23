@tool
extends EditorPlugin

const FILE_TOOLBAR: PackedScene = preload("res://addons/terrain_3d/ui/tools.tscn")

var current_terrain: Terrain
var is_active: bool = false

var mouse_is_pressed: bool = false
var toolbar: Control

var color_channels: Array[Color] = [
	Color(1,0,0,0),
	Color(0,1,0,0),
	Color(0,0,1,0),
	Color(0,0,0,1),
]

func _enter_tree():
	if !toolbar:
		toolbar = FILE_TOOLBAR.instantiate()
	toolbar.hide()
	toolbar.connect("texture_changed", on_texture_changed)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, toolbar)

func _exit_tree():
	
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, toolbar)
	toolbar.queue_free()
	toolbar = null

func _handles(obj):
	if obj is Terrain:
		set_edited_terrain(obj)
		return true
	set_edited_terrain(null)
	return false
	
func _make_visible(visible: bool):
	is_active = visible
	toolbar.visible = visible
	
	
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent):
	
	if is_active:
		if is_terrain_valid():
			
			if event is InputEventMouse:
				var mouse_pos: Vector2 = event.get_position()
			
				var ray_param: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
				ray_param.set_from(camera.global_transform.origin)
				
				ray_param.set_to(camera.project_position(mouse_pos, 1024.0))
				var space = current_terrain.get_world_3d().get_space()
				var ray_data: Dictionary = PhysicsServer3D.space_get_direct_state(space).intersect_ray(ray_param)
				
				if event is InputEventMouseButton and event.get_button_index() == 1:
#					if mouse_is_pressed and !event.is_pressed():
#						current_terrain.update_normalmap(true)
					mouse_is_pressed = event.is_pressed()
						
				if event is InputEventMouseMotion and mouse_is_pressed:
					
					if !ray_data.is_empty():
						
						var uv: Vector2 = get_uv_from(ray_data.position)
						
						if toolbar.tool_mode == toolbar.ToolMode.HEIGHT:
							paint_height(uv)
						if toolbar.tool_mode == toolbar.ToolMode.SPLAT:
							paint_splat(uv)
							
				if mouse_is_pressed:
					return EditorPlugin.AFTER_GUI_INPUT_STOP

func is_terrain_valid():
	return current_terrain != null
	
func set_edited_terrain(terrain: Terrain):
	current_terrain = terrain
	if current_terrain:
		load_texture_arrays()

func get_uv_from(pos: Vector3):
	return (Vector2(pos.x, pos.z) / float(current_terrain.size)) + Vector2(0.5, 0.5)
	
func rotate_uv(uv: Vector2, rotation: float):
	var rotation_offset = Vector2(0.5,0.5)
	return ((uv - rotation_offset).rotated(rotation) + rotation_offset).clamp(Vector2.ZERO, Vector2.ONE)
	
func is_in_bounds(pixel_position: Vector2i, max_position: Vector2i):
	var more_than_min: bool = pixel_position.x >= 0 and pixel_position.y >= 0 
	var less_than_max: bool =  pixel_position.x < max_position.x and pixel_position.y < max_position.y
	return more_than_min and less_than_max
	
func load_texture_arrays():
	var arrays: Array = current_terrain.get_texture_arrays()
	toolbar.load_textures(arrays[0], arrays[1])

func on_texture_changed(texture: Texture2D, index: int, is_albedo: bool = true):
	if is_terrain_valid():
		current_terrain.set_texture(texture, index, is_albedo)
	
func paint_height(uv: Vector2):
	var heightmap: ImageTexture = current_terrain.get_shader().get_shader_parameter("terrain_heightmap")
	var heightmap_img: Image = heightmap.get_image()
	var heightmap_size: Vector2i = heightmap_img.get_size()
	
	var brush_size = toolbar.get_brush_size()
	var brush_shape = toolbar.get_brush_shape()
	var brush_shape_size = brush_shape.get_size()
	var brush_height = toolbar.get_brush_height()
	var brush_opacity = toolbar.get_brush_opacity()
	
	var rand_rotation = PI * randf()
	
	for x in brush_size:
		for y in brush_size:
			var brush_center = brush_size / 2

			var brush_shape_uv: Vector2 = Vector2(x,y) / brush_size
			brush_shape_uv = rotate_uv(brush_shape_uv, rand_rotation)
			var brush_pixel: Vector2i = Vector2i(brush_shape_uv * Vector2(brush_shape_size))
			brush_pixel = brush_pixel.clamp(Vector2i.ZERO, brush_shape_size - Vector2i.ONE)
			
			var brush_offset: Vector2i = Vector2i(x, y) - Vector2i(brush_center, brush_center)
			var brush_position: Vector2i = Vector2i(Vector2(heightmap_size) * uv)
			var pixel_position: Vector2i = (brush_position + brush_offset)
			
			if is_in_bounds(pixel_position, heightmap_size):
				var alpha: float = brush_shape.get_pixelv(brush_pixel).r * brush_opacity
				var color: Color = heightmap_img.get_pixelv(pixel_position).lerp(Color.WHITE * brush_height, alpha)
			
				heightmap_img.set_pixelv(pixel_position, color)
	
	heightmap.set_image(heightmap_img)
	current_terrain.update_normalmap(true)

func paint_splat(uv: Vector2):
	
	var splatmaps: Array[ImageTexture] = [
		current_terrain.get_shader().get_shader_parameter("terrain_splatmap_01"),
		current_terrain.get_shader().get_shader_parameter("terrain_splatmap_02"),
		current_terrain.get_shader().get_shader_parameter("terrain_splatmap_03"),
		current_terrain.get_shader().get_shader_parameter("terrain_splatmap_04")
	]
	
	var brush_size = toolbar.get_brush_size()
	var brush_opacity = toolbar.get_brush_opacity()
	var brush_shape = toolbar.get_brush_shape()
	var brush_shape_size = brush_shape.get_size()
	
	var brush_color = color_channels[wrapi(toolbar.get_texture_layer(), 1, 5) - 1]
	var splat_index = ((toolbar.get_texture_layer() - 1) / 4)
	
	var rand_rotation = PI * randf()

	for i in splatmaps.size():
		
		var splatmap_img: Image = splatmaps[i].get_image()
		var splatmap_size: Vector2i = splatmap_img.get_size()
		
		var new_color = Color(0,0,0,0)
		if i == splat_index:
			new_color = brush_color
		
		for x in brush_size:
			for y in brush_size:
				var brush_center = brush_size / 2
				var brush_shape_uv: Vector2 = Vector2(x,y) / brush_size
				brush_shape_uv = rotate_uv(brush_shape_uv, rand_rotation)
				var brush_pixel: Vector2i = Vector2i(brush_shape_uv * Vector2(brush_shape_size))
				brush_pixel = brush_pixel.clamp(Vector2i.ZERO, brush_shape_size - Vector2i.ONE)
				
				var brush_offset: Vector2i = Vector2i(x, y) - Vector2i(brush_center, brush_center)
				var brush_position: Vector2i = Vector2i(Vector2(splatmap_size) * uv)
				var pixel_position: Vector2i = brush_position + brush_offset
				
				if is_in_bounds(pixel_position, splatmap_size):
					var alpha: float = brush_shape.get_pixelv(brush_pixel).r * brush_opacity
					var color: Color = splatmap_img.get_pixelv(pixel_position).lerp(new_color, alpha)
					
					splatmap_img.set_pixelv(pixel_position, color)
		
		splatmaps[i].set_image(splatmap_img)
	
