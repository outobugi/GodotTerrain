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

var _editor_map_normalmap: ViewportTexture
var _editor_map_heightmap: ViewportTexture

const LAYERS_MAX: int = 16
const SPLATMAPS: PackedStringArray = ["terrain_splatmap_01","terrain_splatmap_02","terrain_splatmap_03","terrain_splatmap_04"]
const SPLATMAP_SIZE: int = 1024
const SPLATMAP_MAX: int = 4

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
var map_splatmap_1: ImageTexture
var map_splatmap_2: ImageTexture
var map_splatmap_3: ImageTexture
var map_splatmap_4: ImageTexture

## Array of materials.
var material_layers: Array[TerrainLayerMaterial3D]

var texture_array_albedo: Texture2DArray
var texture_array_normal: Texture2DArray
var texture_array_orm: Texture2DArray

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
		
func get_material_layers() -> Array[TerrainLayerMaterial3D]:
	return material_layers
			
func set_material_layer(material: TerrainLayerMaterial3D, layer: int):
	if layer < material_layers.size():
		if material == null:
			var material_to_remove: TerrainLayerMaterial3D = material_layers[layer]
			material_to_remove.disconnect("texture_changed", _update_textures)
			material_to_remove.disconnect("value_changed", _update_values)
			material_layers.remove_at(layer)
		else:
			material_layers[layer] = material
	else:
		material_layers.push_back(material)
		
	if material:
		material.connect("texture_changed", _update_textures)
		material.connect("value_changed", _update_values)
	
	_update_layers()

func _update_values():
	var uv_scales: PackedVector3Array
	var colors: PackedColorArray
	
	for material in material_layers:
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
	var orm_textures: Array[Texture2D]
	
	for material in material_layers:
		var alb: Texture2D = material.get_texture(TerrainLayerMaterial3D.TextureParam.TEXTURE_ALBEDO)
		var nor: Texture2D = material.get_texture(TerrainLayerMaterial3D.TextureParam.TEXTURE_NORMAL)
		var orm: Texture2D = material.get_texture(TerrainLayerMaterial3D.TextureParam.TEXTURE_ORM)
		albedo_textures.push_back(alb)
		normal_textures.push_back(nor)
		orm_textures.push_back(orm)
	
	texture_array_albedo = _convert_to_albedo_array(albedo_textures)
	texture_array_normal = _convert_to_normal_array(normal_textures, orm_textures)

	RenderingServer.material_set_param(get_rid(), "texture_array_albedo", texture_array_albedo.get_rid())
	RenderingServer.material_set_param(get_rid(), "texture_array_normal", texture_array_normal.get_rid())
	
	RenderingServer.material_set_param(get_rid(), "texture_array_normal_max", texture_array_normal.get_layers() - 1)
	
	enable_grid(texture_array_albedo.get_layers() == 0)
	emit_changed()

func _update_layers():
	_update_textures()
	_update_values()
	
func _update():
	_update_heightmap()
	_update_normalmap()
	_update_splatmaps()
	_update_layers()

func _convert_to_albedo_array(array_albedo: Array) -> Texture2DArray:
	
	var img_arr: Array[Image]
	for tex in array_albedo:
		if tex != null:
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
	
func _convert_to_normal_array(array_normal: Array, array_orm: Array) -> Texture2DArray:
	
	var img_arr: Array[Image]
	
	for i in array_normal.size():
		
		var nor: Texture2D = array_normal[i]
		var orm: Texture2D
		if array_orm.size() > i+1:
			orm = array_orm[i]
			
		if nor != null:
			var img_nor: Image = nor.get_image()
			var img_nor_size: Vector2i = img_nor.get_size()
			
			if img_nor.is_compressed():
				img_nor.decompress()
			
			var img_orm: Image
			var img_orm_size: Vector2i
			
			if orm != null:
				img_orm = orm.get_image()
				img_orm_size = img_orm.get_size()
				if img_orm.is_compressed():
					img_orm.decompress()

			var output_img: Image = Image.create(img_nor.get_size().x, img_nor.get_size().y, true, Image.FORMAT_RGBA8)
			
			for x in img_nor_size.x:
				for y in img_nor_size.y:
					var uv: Vector2 = Vector2(x, y) / Vector2(img_nor_size)
					var n: Color = img_nor.get_pixel(x, y)
					
					var new_pixel = Color(n.r, n.a, 1.0, 1.0)
					
					if img_orm:
						var o: Color = img_orm.get_pixelv(Vector2i(uv*Vector2(img_orm_size)))
						new_pixel.b = o.g # Roughness
						new_pixel.a = o.r # AO
					
					output_img.set_pixel(x, y, new_pixel)
			
			output_img.generate_mipmaps()
			img_arr.push_back(output_img)
			
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
			"hint_string": "Texture2D",
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
			"name": "texture_array_albedo",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2DArray",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "texture_array_normal",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2DArray",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		{
			"name": "texture_array_orm",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2DArray",
			"usage": property_usage | PROPERTY_USAGE_READ_ONLY,
		},
		
	]
	return property_list
	
