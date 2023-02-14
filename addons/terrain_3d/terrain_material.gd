@tool
@icon("res://addons/terrain_3d/icons/icon_terrain_material.svg")
extends Material
class_name TerrainMaterial3D

# Maybe generate the shader code somewhere here? Out of sight, out of mind.

## Material used in [Terrain3D].
##
## This material is not meant to be edited directly. All needed maps are created automatically.

const _SHADER: Shader = preload("res://addons/terrain_3d/terrain.gdshader")

var _editor_map_normalmap: ViewportTexture

const LAYERS_MAX: int = 256

## Enables inspecting all of the data used in the material.
@export var advanced: bool = false :
	set(val):
		advanced = val
		notify_property_list_changed()

var grid_texture_enabled: bool = false :
	set = enable_grid
var grid_texture_scale: float = 2.0 :
	set = set_grid_scale

var resolution_height: int = 64
var resolution_size: int = 1024

var parallax_enabled: bool = true :
	set = enable_parallax
var parallax_depth: float = 1.0 :
	set = set_parallax_depth

var map_heightmap: ImageTexture
var map_normalmap: Texture2D
var map_controlmap: ImageTexture

## Array of materials.
var layer_materials: Array[TerrainLayerMaterial3D]
## 
var layer_texture_array_albedo: Texture2DArray
var layer_texture_array_normal: Texture2DArray

func _init():
	call_deferred("_update")
	
func _get_shader_mode():
	return Shader.MODE_SPATIAL

func _get_shader_rid():
	return _SHADER.get_rid()
	
func enable_grid(enable: bool):
	grid_texture_enabled = enable
	RenderingServer.material_set_param(get_rid(), "terrain_use_grid", grid_texture_enabled)
	emit_changed()
	
func set_grid_scale(scale: float):
	grid_texture_scale = scale
	RenderingServer.material_set_param(get_rid(), "terrain_grid_scale", grid_texture_scale)
	emit_changed()
	
func enable_parallax(enable: bool):
	parallax_enabled = enable
	RenderingServer.material_set_param(get_rid(), "parallax_enabled", parallax_enabled)
	emit_changed()
	
func set_parallax_depth(depth: float):
	parallax_depth = depth
	RenderingServer.material_set_param(get_rid(), "parallax_depth", parallax_depth)
	emit_changed()
	
func set_size(size: int):
	resolution_size = size
	RenderingServer.material_set_param(get_rid(), "terrain_size", float(size))
	_update_heightmap()
	_update_normalmap()
	emit_changed()
	
func get_size() -> int:
	return resolution_size
	
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
	
func set_heightmap(map: Texture2D):
	map_heightmap = map
	_update_heightmap()
	emit_changed()
	
func get_heightmap() -> ImageTexture:
	return map_heightmap
	
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
	
func get_normalmap() -> Texture2D:
	if _editor_map_normalmap:
		return _editor_map_normalmap
	return map_normalmap
	
func _apply_editor_normalmap():
	if _editor_map_normalmap:
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
	
func _update_controlmap():
	if !map_controlmap:
		map_controlmap = ImageTexture.new()
		var img: Image = Image.create(resolution_size / 2, resolution_size / 2, false, Image.FORMAT_RGB8)
		img.fill(Color(0,0,0,1))
		map_controlmap.set_image(img)
		
	RenderingServer.material_set_param(get_rid(), "terrain_controlmap", map_controlmap.get_rid())

func get_controlmap():
	return map_controlmap
	
func get_layer_materials() -> Array[TerrainLayerMaterial3D]:
	return layer_materials
			
func set_layer_material(material: TerrainLayerMaterial3D, layer: int):
	if layer < layer_materials.size():
		if material == null:
			var material_to_remove: TerrainLayerMaterial3D = layer_materials[layer]
			material_to_remove.disconnect("texture_changed", _update_textures)
			material_to_remove.disconnect("value_changed", _update_values)
			layer_materials.remove_at(layer)
		else:
			layer_materials[layer] = material
	else:
		layer_materials.push_back(material)
	
	_update_layers()

func _update_values():
	var uv_scales: PackedVector3Array
	var colors: PackedColorArray
	
	for material in layer_materials:
		var uv: Vector3 = material.get_uv_scale()
		var color: Color = material.get_albedo()
		uv_scales.push_back(uv)
		colors.push_back(color)
		
	RenderingServer.material_set_param(get_rid(), "texture_uv_scale_array", uv_scales)
	RenderingServer.material_set_param(get_rid(), "texture_color_array", colors)
	emit_changed()
	
func _update_textures():
	var albedo_textures: Array[Texture2D]
	var normal_textures: Array[Texture2D]
	
	for material in layer_materials:
		var alb: Texture2D = material.get_texture(TerrainLayerMaterial3D.TextureParam.TEXTURE_ALBEDO)
		var nor: Texture2D = material.get_texture(TerrainLayerMaterial3D.TextureParam.TEXTURE_NORMAL)
		albedo_textures.push_back(alb)
		normal_textures.push_back(nor)
		
	layer_texture_array_albedo = _convert_array(albedo_textures)
	layer_texture_array_normal = _convert_array(normal_textures)

	RenderingServer.material_set_param(get_rid(), "texture_array_albedo", layer_texture_array_albedo.get_rid())
	RenderingServer.material_set_param(get_rid(), "texture_array_normal", layer_texture_array_normal.get_rid())
	
	RenderingServer.material_set_param(get_rid(), "texture_array_normal_max", layer_texture_array_normal.get_layers() - 1)
	
	enable_grid(layer_texture_array_albedo.get_layers() == 0)
	emit_changed()

func _update_layers():
	
	for material in layer_materials:
		if !material.is_connected("texture_changed", _update_textures):
			material.connect("texture_changed", _update_textures)
		if !material.is_connected("value_changed", _update_values):
			material.connect("value_changed", _update_values)
	
	_update_textures()
	_update_values()
	
func _update():
	
	RenderingServer.material_set_shader(get_rid(), _SHADER.get_rid())
	
	_update_heightmap()
	_update_normalmap()
	_update_controlmap()
	_update_layers()

func _convert_array(array_albedo: Array) -> Texture2DArray:
	
	var img_arr: Array[Image]
	
	for tex in array_albedo:
		if tex != null:
			var img: Image = tex.get_image()
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
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "resolution_size",
			"type": TYPE_INT,
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
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
			"hint_string": "Texture2D",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "map_controlmap",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "Layers",
			"type": TYPE_NIL,
			"hint_string": "layer_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "layer_materials",
			"type": TYPE_ARRAY,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "TerrainLayerMaterial3D",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "layer_texture_array_albedo",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2DArray",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "layer_texture_array_normal",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2DArray",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
		
		
	]
	return property_list
	
