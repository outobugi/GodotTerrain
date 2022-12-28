@tool
extends Material
class_name TerrainMaterial
@icon("res://addons/terrain_3d/icons/icon_terrain_material.svg")

const _SHADER: Shader = preload("res://addons/terrain_3d/terrain.gdshader")
const _DEFAULT_GRID_TEXTURE: Texture2D = preload("res://addons/terrain_3d/temp/grid_albedo.png")
const _NORMALMAP_SHADER: Shader = preload("res://addons/terrain_3d/height_to_normal.gdshader")

const SPLATMAP_SIZE: int = 1024
const MAX_SPLATMAP: int = 4

@export var show_data: bool = false :
	set(show):
		show_data = show
		notify_property_list_changed()

var grid_texture_enabled: bool
var grid_texture_scale: float = 2.0

var resolution_height: float = 64.0
var resolution_size: float = 1024.0

var map_heightmap: ImageTexture
var map_normalmap: ImageTexture
var map_splatmap_1: ImageTexture
var map_splatmap_2: ImageTexture
var map_splatmap_3: ImageTexture
var map_splatmap_4: ImageTexture

var texture_arrays: Array[Array]

var texture_albedo: Texture2DArray
var texture_normal: Texture2DArray

var _viewport_normalmap: SubViewport

func _init():
	RenderingServer.material_set_shader(get_rid(), _SHADER.get_rid())
	RenderingServer.shader_set_default_texture_parameter(_SHADER.get_rid(), "terrain_grid", _DEFAULT_GRID_TEXTURE.get_rid())
	
	call_deferred("_update")
	
func _get_shader_mode():
	return _SHADER.get_mode()

func _get_shader_rid():
	return _SHADER.get_rid()
	
func enable_grid(enable: bool):
	grid_texture_enabled = enable
	RenderingServer.material_set_param(get_rid(), "use_grid", grid_texture_enabled)
	emit_changed()
	
func set_size(size: int):
	resolution_size = size
	RenderingServer.material_set_param(get_rid(), "terrain_size", float(size))
	update_heightmap()
	update_normalmap()
	emit_changed()
	
func set_height(height: int):
	resolution_height = height
	update_normalmap()
	RenderingServer.material_set_param(get_rid(), "terrain_height", float(height))
	emit_changed()
	
func set_resolution(size: int, height: int):
	resolution_height = height
	resolution_size = size
	RenderingServer.material_set_param(get_rid(), "terrain_size", float(size))
	RenderingServer.material_set_param(get_rid(), "terrain_height", float(height))
	update_heightmap()
	update_normalmap()
	emit_changed()
	
func get_heightmap():
	return map_heightmap
	
func update_heightmap():
	# half map sizes cuz gotta go fast
	var map_size: int = (resolution_size/2)+1
	if !map_heightmap:
		map_heightmap = ImageTexture.new()
		var img: Image = Image.create(map_size, map_size, false, Image.FORMAT_RH)
		map_heightmap.set_image(img)
	if map_heightmap.get_size() != Vector2(map_size, map_size):
		map_heightmap.get_image().resize(map_size, map_size)
		map_heightmap.emit_changed()
	RenderingServer.material_set_param(get_rid(), "terrain_heightmap", map_heightmap.get_rid())
	
func get_normalmap():
	return map_normalmap
	
func update_normalmap():
	
	if !Engine.is_editor_hint():
		if _viewport_normalmap:
			_viewport_normalmap.queue_free()
		return
	
	if !map_normalmap:
		map_normalmap = ImageTexture.new()
		
	# This feels so damn hacky bruv
	if !_viewport_normalmap:
		_viewport_normalmap = SubViewport.new()
		_viewport_normalmap.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_viewport_normalmap.world_2d = World2D.new()
		_viewport_normalmap.disable_3d = true
		
		Engine.get_main_loop().get_root().add_child(_viewport_normalmap)
		
		var nmap_mat: ShaderMaterial = ShaderMaterial.new()
		nmap_mat.shader = _NORMALMAP_SHADER
		var canvas: CanvasItem = Sprite2D.new()
		canvas.centered = false
		canvas.material = nmap_mat
		canvas.texture = map_heightmap
		
		_viewport_normalmap.add_child(canvas)
	
	_viewport_normalmap.get_child(0).material.set_shader_parameter("height", resolution_height)
		
	var hmap_size: Vector2i = Vector2i(map_heightmap.get_size())
	if _viewport_normalmap.size != hmap_size:
		_viewport_normalmap.size = hmap_size
	
	_viewport_normalmap.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	await RenderingServer.frame_post_draw
	
	map_normalmap.set_image(_viewport_normalmap.get_texture().get_image())
		
	RenderingServer.material_set_param(get_rid(), "terrain_normalmap", map_normalmap.get_rid())

func _set_splatmap(index: int, map: ImageTexture):
	match index:
		0: map_splatmap_1 = map
		1: map_splatmap_2 = map
		2: map_splatmap_3 = map
		3: map_splatmap_4 = map
	var splatmaps: PackedStringArray = ["terrain_splatmap_01","terrain_splatmap_02","terrain_splatmap_03","terrain_splatmap_04"]
	RenderingServer.material_set_param(get_rid(), splatmaps[index], map.get_rid())
	
func get_splatmap(index: int):
	match index:
		0: return map_splatmap_1
		1: return map_splatmap_2
		2: return map_splatmap_3
		3: return map_splatmap_4
	return null
	
func update_splatmaps():
	var is_first: bool = true
	for map in MAX_SPLATMAP:
		var splatmap: ImageTexture = get_splatmap(map)
		if !splatmap:
			splatmap = ImageTexture.new()
			var img: Image = Image.create(SPLATMAP_SIZE, SPLATMAP_SIZE, true, Image.FORMAT_RGBA8)
			if is_first:
				img.fill(Color(1,0,0,0))
				is_first = false
			splatmap.set_image(img)
		_set_splatmap(map, splatmap)
		
func get_textures():
	return texture_arrays
			
func set_texture(texture: Texture2D, index: int, is_albedo: bool):
	if is_albedo:
		if index < texture_arrays[0].size():
			if texture == null:
				texture_arrays[0].remove_at(index)
			else:
				texture_arrays[0][index] = texture
		else:
			texture_arrays[0].append(texture)
	texture_arrays[1].resize(texture_arrays[0].size())
	if !is_albedo:
		texture_arrays[1][index] = texture
	_update_textures()
	emit_changed()

func _update_textures():
	
	if texture_arrays.is_empty():
		# Resizing to 2 and filling with Array does not create 2 unique Arrays????
		texture_arrays.append(Array())
		texture_arrays.append(Array())
	
	texture_albedo = _convert_array(texture_arrays[0])
	RenderingServer.material_set_param(get_rid(), "texture_albedos", texture_albedo.get_rid())
	
	texture_normal = _convert_array(texture_arrays[1])
	RenderingServer.material_set_param(get_rid(), "texture_normals", texture_normal.get_rid())

	enable_grid(texture_albedo.get_layers() == 0)
	
func _update():
	update_heightmap()
	update_normalmap()
	update_splatmaps()
	_update_textures()

func _convert_array(arr: Array) -> Texture2DArray:
	var img_arr: Array[Image]
	for tex in arr:
		if tex != null and tex is Texture2D:
			var img: Image = tex.get_image()
			
			if img.is_compressed():
				img.decompress()
			
			img.generate_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
				
			img_arr.push_back(img)
	var tex_arr = Texture2DArray.new()
	if !img_arr.is_empty():
		tex_arr.create_from_images(img_arr)
	return tex_arr

func _get_property_list():
	
	var property_usage: int = PROPERTY_USAGE_DEFAULT if show_data else PROPERTY_USAGE_STORAGE
	
	var property_list: Array = [
		{
			"name": "Grid",
			"type": TYPE_NIL,
			"hint_string": "grid_texture_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "grid_texture_enabled",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "grid_texture_scale",
			"type": TYPE_FLOAT,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "Resolution",
			"type": TYPE_NIL,
			"hint_string": "resolution_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "resolution_height",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "resolution_size",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "Maps",
			"type": TYPE_NIL,
			"hint_string": "map_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "map_heightmap",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "map_normalmap",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "map_splatmap_1",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "map_splatmap_2",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "map_splatmap_3",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "map_splatmap_4",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "Textures",
			"type": TYPE_NIL,
			"hint_string": "texture_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "texture_albedo",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2DArray",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "texture_normal",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2DArray",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "texture_arrays",
			"type": TYPE_ARRAY,
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
	]
	return property_list
