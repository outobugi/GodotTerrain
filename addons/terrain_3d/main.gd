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
	toolbar.call_deferred("init_tools")
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
				
				var was_pressed: bool = mouse_is_pressed
				
				if event is InputEventMouseButton and event.get_button_index() == 1:
					mouse_is_pressed = event.is_pressed()
					
				if event is InputEventMouseMotion and mouse_is_pressed:
					
					if !ray_data.is_empty():
						
						var uv: Vector2 = get_uv_from(ray_data.position)
						
						if toolbar.tool_mode == toolbar.ToolMode.HEIGHT:
							paint_height(uv)
						if toolbar.tool_mode == toolbar.ToolMode.TEXTURE:
							paint_splat(uv)
							
				if was_pressed and !mouse_is_pressed:
					current_terrain.update_collision()
							
				if mouse_is_pressed:
					return EditorPlugin.AFTER_GUI_INPUT_STOP

func is_terrain_valid():
	return current_terrain != null
	
func set_edited_terrain(terrain: Terrain):
	current_terrain = terrain
	if current_terrain:
		call_deferred("load_textures")
		call_deferred("load_meshes")

func get_uv_from(pos: Vector3):
	return (Vector2(pos.x, pos.z) / float(current_terrain.size)) + Vector2(0.5, 0.5)
	
func rotate_uv(uv: Vector2, rotation: float):
	var rotation_offset = Vector2(0.5,0.5)
	return ((uv - rotation_offset).rotated(rotation) + rotation_offset).clamp(Vector2.ZERO, Vector2.ONE)
	
func is_in_bounds(pixel_position: Vector2i, max_position: Vector2i):
	var more_than_min: bool = pixel_position.x >= 0 and pixel_position.y >= 0 
	var less_than_max: bool =  pixel_position.x < max_position.x and pixel_position.y < max_position.y
	return more_than_min and less_than_max
	
func load_textures():
	var textures: Array = []
	if current_terrain.has_material():
		textures = current_terrain.get_material().get_textures()
	toolbar.load_textures(textures, on_surface_texture_changed)
	
func load_meshes():
	toolbar.load_meshes(current_terrain.get_particle_meshes(), on_particle_mesh_changed)

func on_surface_texture_changed(texture: Texture2D, index: int, is_albedo: bool = true):
	if is_terrain_valid():
		if current_terrain.has_material():
			current_terrain.get_material().set_texture(texture, index, is_albedo)
		call_deferred("load_textures")
		
func on_particle_mesh_changed(mesh: Mesh, layer: int, index: int):
	if is_terrain_valid():
		current_terrain.set_particle_mesh(mesh, layer, index)
		call_deferred("load_meshes")
		
func paint_height(uv: Vector2):
	var heightmap: ImageTexture = current_terrain.get_material().get_heightmap()
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
	current_terrain.get_material().update_normalmap(true)

func paint_splat(uv: Vector2):
	
	var brush_size = toolbar.get_brush_size()
	var brush_opacity = toolbar.get_brush_opacity()
	var brush_shape = toolbar.get_brush_shape()
	var brush_shape_size = brush_shape.get_size()
	
	var brush_color = color_channels[wrapi(toolbar.get_texture_layer(), 1, 5) - 1]
	var splat_index = (toolbar.get_texture_layer() - 1) / 4
	
	var rand_rotation = PI * randf()

	for i in TerrainMaterial.MAX_SPLATMAP:
		
		var splatmap_img: Image = current_terrain.get_material().get_splatmap(i).get_image()
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
		
		current_terrain.get_material().get_splatmap(i).set_image(splatmap_img)
	
