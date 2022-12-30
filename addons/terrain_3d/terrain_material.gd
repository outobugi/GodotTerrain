@tool
extends Material
class_name TerrainMaterial3D
@icon("res://addons/terrain_3d/icons/icon_terrain_material.svg")

# Maybe generate the shader code somwhere here?

## Material used to render [Terrain3D].
##
## This material is not meant to be edited directly. All needed maps are created automatically.

const _SHADER: Shader = preload("res://addons/terrain_3d/terrain.gdshader")
const _DEFAULT_GRID_TEXTURE: Texture2D = preload("res://addons/terrain_3d/temp/grid_albedo.png")
const _NORMALMAP_SHADER: Shader = preload("res://addons/terrain_3d/height_to_normal.gdshader")

var _editor_map_normalmap: ViewportTexture
var _editor_map_heightmap: ViewportTexture

const SPLATMAPS: PackedStringArray = ["terrain_splatmap_01","terrain_splatmap_02","terrain_splatmap_03","terrain_splatmap_04"]
const SPLATMAP_SIZE: int = 1024
const SPLATMAP_MAX: int = 4
const TEXTURE_ALBEDO: int = 0
const TEXTURE_NORMALMAP: int = 1

## Enables inspecting all of the data used in the material.
@export var advanced: bool = false :
	set(val):
		advanced = val
		notify_property_list_changed()

var grid_texture_enabled: bool = true
var grid_texture_scale: float = 2.0

var resolution_height: int = 64
var resolution_size: int = 1024

var map_heightmap: ImageTexture
var map_normalmap: ImageTexture
var map_splatmap_1: ImageTexture
var map_splatmap_2: ImageTexture
var map_splatmap_3: ImageTexture
var map_splatmap_4: ImageTexture

## Array of arrays of textures. Contains albedos and normals.
var texture_arrays: Array[Array]

## [Texture2DArray] created from [i]texture_arrays[/i].
var texture_albedo: Texture2DArray
## [Texture2DArray] created from [i]texture_arrays[/i].
var texture_normal: Texture2DArray

func _init():
	RenderingServer.material_set_shader(get_rid(), _SHADER.get_rid())
	RenderingServer.shader_set_default_texture_parameter(_SHADER.get_rid(), "terrain_grid", _DEFAULT_GRID_TEXTURE.get_rid())
	call_deferred("_update")
	
func _get_shader_mode():
	return Shader.MODE_SPATIAL

func _get_shader_rid():
	return _SHADER.get_rid()
	
func enable_grid(enable: bool):
	grid_texture_enabled = enable
	RenderingServer.material_set_param(get_rid(), "use_grid", grid_texture_enabled)
	emit_changed()
	
func set_size(size: int):
	resolution_size = size
	RenderingServer.material_set_param(get_rid(), "terrain_size", float(size))
	_update_heightmap()
	_update_normalmap()
	emit_changed()
	
func set_height(height: int):
	resolution_height = height
	_update_normalmap()
	RenderingServer.material_set_param(get_rid(), "terrain_height", float(height))
	emit_changed()
	
func get_height() -> int:
	return resolution_height
	
func set_resolution(size: int, height: int):
	resolution_height = height
	resolution_size = size
	RenderingServer.material_set_param(get_rid(), "terrain_size", float(size))
	RenderingServer.material_set_param(get_rid(), "terrain_height", float(height))
	_update_heightmap()
	_update_normalmap()
	emit_changed()
	
func set_heightmap(map: Texture2D, temp: bool = false):
	if temp:
		_editor_map_heightmap = map
	else:
		map_heightmap = map
	_update_heightmap()
	emit_changed()
	
func get_heightmap() -> ImageTexture:
	return map_heightmap
	
func _apply_editor_heightmap():
	map_heightmap.set_image(_editor_map_heightmap.get_image())
	
func _update_heightmap():
	var map_size: int = (resolution_size)+1
	if !map_heightmap:
		map_heightmap = ImageTexture.new()
		var img: Image = Image.create(map_size, map_size, false, Image.FORMAT_RH)
		map_heightmap.set_image(img)
	if map_heightmap.get_size() != Vector2(map_size, map_size):
		var img: Image = map_heightmap.get_image()
		img.resize(map_size, map_size)
		map_heightmap.set_image(img)
	RenderingServer.material_set_param(get_rid(), "terrain_heightmap", map_heightmap.get_rid())
	
func set_normalmap(map: Texture2D, temp: bool = false):
	if temp:
		_editor_map_normalmap = map
	else:
		map_normalmap = map
	_update_normalmap()
	emit_changed()
	
func get_normalmap() -> ImageTexture:
	return map_normalmap
	
func _apply_editor_normalmap():
	map_normalmap.set_image(_editor_map_normalmap.get_image())
	
func _update_normalmap():
	
	if !map_normalmap:
		map_normalmap = ImageTexture.new()
		var map_size: Vector2 = map_heightmap.get_size()
		var img: Image = Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGB8)
		img.fill(Color8(127, 127, 255))
		map_normalmap.set_image(img)
		
	var use_editor_normalmap: bool = false
	var map: Variant = null
	if _editor_map_normalmap:
		if !_editor_map_normalmap.get_image().is_empty():
			map = _editor_map_normalmap.get_rid()
			use_editor_normalmap = true
	
	if !use_editor_normalmap:
		map = map_normalmap.get_rid()
		
	RenderingServer.material_set_param(get_rid(), "terrain_normalmap", map)
	
func set_splatmap(index: int, map: Texture2D):
	match index:
		0: map_splatmap_1 = map
		1: map_splatmap_2 = map
		2: map_splatmap_3 = map
		3: map_splatmap_4 = map
	
	RenderingServer.material_set_param(get_rid(), SPLATMAPS[index], map.get_rid())
	emit_changed()
	
func get_splatmap(index: int) -> ImageTexture:
	match index:
		0: return map_splatmap_1
		1: return map_splatmap_2
		2: return map_splatmap_3
		3: return map_splatmap_4
	return null
	
func _update_splatmaps():
	var is_first: bool = true
	for map in SPLATMAP_MAX:
		var splatmap: ImageTexture = get_splatmap(map)
		if !splatmap:
			splatmap = ImageTexture.new()
			var img: Image = Image.create(SPLATMAP_SIZE, SPLATMAP_SIZE, true, Image.FORMAT_RGBA8)
			if is_first:
				img.fill(Color(1,0,0,0))
				is_first = false
			splatmap.set_image(img)
		set_splatmap(map, splatmap)
		
func get_textures() -> Array[Array]:
	return texture_arrays
			
func set_texture(texture: Texture2D, index: int, is_albedo: bool):
	if is_albedo:
		if index < texture_arrays[TEXTURE_ALBEDO].size():
			if texture == null:
				texture_arrays[TEXTURE_ALBEDO].remove_at(index)
			else:
				texture_arrays[TEXTURE_ALBEDO][index] = texture
		else:
			texture_arrays[TEXTURE_ALBEDO].append(texture)
	texture_arrays[TEXTURE_NORMALMAP].resize(texture_arrays[TEXTURE_ALBEDO].size())
	if !is_albedo:
		texture_arrays[TEXTURE_NORMALMAP][index] = texture
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
	_update_heightmap()
	_update_normalmap()
	_update_splatmaps()
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
	
	var property_usage: int = PROPERTY_USAGE_DEFAULT if advanced else PROPERTY_USAGE_STORAGE
	
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
