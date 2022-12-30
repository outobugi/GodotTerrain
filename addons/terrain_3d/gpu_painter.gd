@tool
extends Node

# for now only normalmap is modified on the GPU
# height painting may be a bit sluggish with higher resolutions but it's nothing too severe

const NORMALMAP_SHADER: Shader = preload("res://addons/terrain_3d/height_to_normal.gdshader")

var viewport_normalmap: SubViewport
var viewport_heightmap: SubViewport

var canvas_normalmap: Sprite2D
var canvas_heightmap: Sprite2D

func _ready():
	viewport_normalmap = SubViewport.new()
	setup_viewport(viewport_normalmap)
	canvas_normalmap = Sprite2D.new()
	canvas_normalmap.centered = false
	var nmap_mat: ShaderMaterial = ShaderMaterial.new()
	nmap_mat.shader = NORMALMAP_SHADER
	canvas_normalmap.material = nmap_mat
	viewport_normalmap.add_child(canvas_normalmap)
	add_child(viewport_normalmap)
	
func setup_viewport(viewport: SubViewport):
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	
func attach_terrain_material(material: TerrainMaterial3D):
	
	if material:
		var heightmap = material.get_heightmap()
		canvas_normalmap.set_texture(heightmap)
		canvas_normalmap.get_material().set_shader_parameter("height", float(material.get_height()))
		
		var _size: Vector2i = Vector2i(heightmap.get_size())
	
		if viewport_normalmap.size != _size:
			viewport_normalmap.size = _size
			
		refresh_normalmap()
			
		await RenderingServer.frame_post_draw
			
		material.set_normalmap(viewport_normalmap.get_texture(), true)
	
func update_resolution(size: int, height: int):
	canvas_normalmap.get_material().set_shader_parameter("height", float(height))
	viewport_normalmap.size = Vector2i(size, size)
	refresh_normalmap()

func clear():
	canvas_normalmap.set_texture(null)
	
func refresh_normalmap():
	viewport_normalmap.render_target_update_mode = SubViewport.UPDATE_ONCE
