@tool
@icon("res://addons/terrain_3d/icons/icon_terrain_layer_material.svg")
extends Material
class_name TerrainLayerMaterial3D

## Material used in [TerrainMaterial3D].
##
## Mostly used as an interface for editing [TerrainMaterial3D].

signal texture_changed()
signal value_changed()

enum TextureParam{
	TEXTURE_ALBEDO,
	TEXTURE_NORMAL,
}

var albedo_color: Color = Color.WHITE :
	set = set_albedo
	
var albedo_texture: Texture2D :
	set(value):
		if _texture_is_valid(value):
			albedo_texture = value
			set_texture(TextureParam.TEXTURE_ALBEDO, value)

var normal_texture: Texture2D :
	set(value):
		if _texture_is_valid(value):
			normal_texture = value
			set_texture(TextureParam.TEXTURE_NORMAL, value)

var normal_scale: float

var uv_scale: Vector3 = Vector3.ONE:
	set = set_uv_scale
var uv_anti_tile: bool :
	set = enable_anti_tile

var _shader: RID

func _init():
	_update_shader()
	
func set_albedo(color: Color):
	albedo_color = color
	RenderingServer.material_set_param(get_rid(), "albedo_color", albedo_color)
	emit_changed()
	emit_signal("value_changed")
	
func get_albedo():
	return albedo_color

func set_normal_scale(scale: float):
	normal_scale = scale
	RenderingServer.material_set_param(get_rid(), "normal_scale", normal_scale)
	emit_changed()
	emit_signal("value_changed")
	
func get_normal_scale():
	return normal_scale

func set_uv_scale(scale: Vector3):
	uv_scale = scale
	RenderingServer.material_set_param(get_rid(), "uv_scale", uv_scale)
	emit_changed()
	emit_signal("value_changed")
	
func get_uv_scale():
	return uv_scale
	
func enable_anti_tile(enable: bool):
	uv_anti_tile = enable
	RenderingServer.material_set_param(get_rid(), "uv_anti_tile", uv_anti_tile)
	emit_changed()
	emit_signal("value_changed")

func set_texture(param: TextureParam, texture: Texture2D):
	
	var string_param: String
	var rid: RID
	
	if texture:
		rid = texture.get_rid()

	match param:
		TextureParam.TEXTURE_ALBEDO:
			string_param = "albedo_texture"
		TextureParam.TEXTURE_NORMAL:
			string_param = "normal_texture"
			_update_shader()

	RenderingServer.material_set_param(get_rid(), string_param, rid)
	emit_changed()
	emit_signal("texture_changed")
	
func get_texture(param: TextureParam):
	match param:
		TextureParam.TEXTURE_ALBEDO:
			return albedo_texture
		TextureParam.TEXTURE_NORMAL:
			return normal_texture
	return null
	
func _texture_is_valid(texture: Texture2D):
	if texture:
		var format: int = texture.get_image().get_format()
		var format_name: String = ClassDB.class_get_enum_constants("Image", "Format")[format]
		if format != Image.FORMAT_DXT5:
			printerr("Invalid format. " + "(" + format_name + ")" + " Expected DXT5 RGBA8.")
			return false
	return true
	
func _get_shader_mode():
	return Shader.MODE_SPATIAL

func _get_shader_rid():
	return _shader

func _update_shader():

	var code: String = "shader_type spatial;\n"
	code += "uniform vec4 albedo_color = vec4(1.0);\n"
	code += "uniform sampler2D albedo_texture : source_color,filter_linear_mipmap_anisotropic,repeat_enable;\n"
	code += "uniform sampler2D normal_texture : filter_linear_mipmap_anisotropic,repeat_enable;\n"
	code += "uniform float normal_scale : hint_range(-16.0, 16.0, 0.1);\n"
	code += "uniform vec3 uv_scale = vec3(1.0,1.0,1.0);\n"
	code += "uniform bool uv_anti_tile;\n\n"
	code += "void vertex(){\n"
	code += "	UV*=uv_scale.xy;\n"
	code += "}\n\n"
	code += "void fragment(){\n"
	code += "	ALBEDO=texture(albedo_texture, UV).rgb * albedo_color.rgb;\n"
	code += "	vec4 normal_map =texture(normal_texture, UV);\n"
	
	if normal_texture:
		code += "	NORMAL_MAP=normal_map.rgb;\n"
		code += "	ROUGHNESS=normal_map.a;\n"
	
	code += "}\n"
	
	_shader = RenderingServer.shader_create()
	RenderingServer.shader_set_code(_shader, code)
	RenderingServer.material_set_shader(get_rid(), _shader)
	
func _get_property_list():
	var property_list: Array = [
		{
			"name": "Albedo",
			"type": TYPE_NIL,
			"hint_string": "albedo_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "albedo_texture",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2D",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "albedo_color",
			"type": TYPE_COLOR,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "Normal Map",
			"type": TYPE_NIL,
			"hint_string": "normal_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "normal_texture",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2D",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "normal_scale",
			"type": TYPE_FLOAT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "-16, 16",
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "UV",
			"type": TYPE_NIL,
			"hint_string": "uv_",
			"usage": PROPERTY_USAGE_GROUP,
		},
		{
			"name": "uv_scale",
			"type": TYPE_VECTOR3,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "uv_anti_tile",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
	]
	return property_list
	
	
