@tool
class_name Terrain3D
extends Node3D
@icon("res://addons/terrain_3d/icons/icon_terrain.svg")

signal resolution_changed()
signal material_changed()

const _SURFACE_SHADER: Shader = preload("res://addons/terrain_3d/terrain.gdshader")
const _DEFAULT_GRID_TEXTURE: Texture2D = preload("res://addons/terrain_3d/temp/grid_albedo.png")
const _PARTICLE_SHADER: Shader = preload("res://addons/terrain_3d/particle.gdshader")
const _EDITOR_COLLISION_SIZE: int = 256
const _MIN_TRAVEL_DISTANCE: float = 8.0

@export_enum("512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var size: int = 1024 :
	set = set_size
@export var height: int = 64 :
	set = set_height

@export_group("LOD", "lod_")

@export var lod_count: int = 4 :
	set = set_lod_count
@export_enum("32:32", "64:64", "128:128", "256:256") var lod_size: int = 128 :
	set = set_lod_size

@export var lod_distance: int = 128

@export var lod_disable: bool = false :
	set = set_disabled
	
@export_group("Material", "surface_")

@export var surface_material: TerrainMaterial :
	set = set_material

@export_subgroup("Particles", "particle_")

@export var particle_draw_distance: int = 128 :
	set = set_particle_draw_distance
	
@export var particle_density: int = 4 :
	set = set_particle_density

var particle_process_material: ShaderMaterial # Unused for now because particle shader don't support per instance uniforms
var particle_mesh_array: Array[Array]
var particle_mask_texture: Texture2D

@export_group("Collision", "collision_")

@export_flags_3d_physics var collision_layer: int = 0
@export_flags_3d_physics var collision_mask: int = 0

var particle_emitters: Array[GPUParticles3D]
var lod_meshes: Array
var chunks: Array
var camera: Camera3D
var physics_body: StaticBody3D

var _previous_camera_position: Vector3
var _update_pending: bool = false

func _init():
	
	set_notify_transform(true)
	
	if !is_inside_tree():
		_update_pending = true
		call_deferred("update")
		

func _exit_tree():
	set_process(false)
		
func _process(delta):
	
	if !camera:
		if Engine.is_editor_hint():
			camera = TerrainUtil.get_camera()
		else:
			camera = get_viewport().get_camera_3d()
	else:
		var camera_position = camera.global_transform.origin * Vector3(1,0,1)
		var distance_traveled: float = _previous_camera_position.distance_to(camera_position)
		
		if distance_traveled > _MIN_TRAVEL_DISTANCE:
			_previous_camera_position = camera_position
			
			for chunk in chunks:
				
				var chunk_pos: Vector3 = chunk.global_transform.origin * Vector3(1,0,1)
				var distance: float = (chunk_pos.distance_to(camera_position))
				var new_lod_level = min(int(distance) / lod_distance, lod_count - 1)
				var old_lod_level = chunk.get_current_lod_level()
				
				if new_lod_level != old_lod_level:
					chunk.set_current_lod_level(new_lod_level)
					chunk.mesh = lod_meshes[new_lod_level]
					
		for emitter in particle_emitters:
			emitter.global_transform.origin = camera_position
				
func set_size(value: int):
	if value != size:
		size = value
		emit_signal("resolution_changed")
		if !_update_pending:
			call_deferred("update")
			
func get_size():
	return size
		
func set_height(value: int):
	if value != height:
		height = value
		emit_signal("resolution_changed")
		if !_update_pending:
			call_deferred("update")

func get_height():
	return height

func set_lod_size(value: int):
	if value != lod_size:
		lod_size = value
		if !_update_pending:
			call_deferred("update")
		
func set_lod_count(value: int):
	if value != lod_count:
		lod_count = value
		if !_update_pending:
			call_deferred("update")
		
func set_disabled(value: bool):
	set_process(!value)
	lod_disable = value
	
func set_particle_draw_distance(value: int):
	particle_draw_distance = value
	update_particles()
	
func set_particle_density(value: int):
	particle_density = max(value, 1)
	update_particles()
	
func set_particle_mesh(mesh: Mesh, layer: int, index: int):
	if index < particle_mesh_array[0].size():
		if mesh == null:
			particle_mesh_array[0].remove_at(index)
			particle_mesh_array[1].remove_at(index)
		else:
			particle_mesh_array[0][index] = mesh
			particle_mesh_array[1][index] = layer
	else:
		particle_mesh_array[0].append(mesh)
		particle_mesh_array[1].append(layer)
	
	update_particles()
	
func get_particle_meshes():
	return particle_mesh_array
	
func set_material(material: TerrainMaterial):
	surface_material = material
	surface_material.call_deferred("set_height", height)
	surface_material.call_deferred("set_size", size)
	
	call_deferred("emit_signal", "material_changed")
	
	for mesh in lod_meshes:
		mesh.surface_set_material(0, surface_material)
	
func get_material() -> TerrainMaterial:
	return surface_material
	
func has_material() -> bool:
	return surface_material != null
	
func update_material():
	if surface_material:
		surface_material.set_resolution(size, height)

func update_particles():
	
	if particle_mesh_array.is_empty():
		particle_mesh_array.append(Array())
		particle_mesh_array.append(Array())
	
	if particle_mesh_array[0].size() < particle_emitters.size():
		var count: int = particle_emitters.size() - particle_mesh_array[0].size()
		for i in count:
			var node: GPUParticles3D = particle_emitters.pop_back()
			node.queue_free()
	else:
		var count: int = particle_mesh_array[0].size() - particle_emitters.size()
		for i in count:
			var node: GPUParticles3D = GPUParticles3D.new()
			node.set_explosiveness_ratio(1.0)
			node.set_draw_order(GPUParticles3D.DRAW_ORDER_VIEW_DEPTH)
			particle_emitters.append(node)
			
	if particle_emitters.size() == particle_mesh_array[0].size():
	
		var sqr_radius: float = float(particle_draw_distance) * sqrt(PI)
		var instance_area: int = int((sqr_radius * sqr_radius) / 2.0)
		
		# Why does it need to divided twice by the density? only way I got it to keep the area the same
		var instance_count: int = instance_area / particle_density / particle_density
		
		var splat_channels: Array[Color] = [
			Color(1,0,0,0),
			Color(0,1,0,0),
			Color(0,0,1,0),
			Color(0,0,0,1),
		]
		
		var index: int = 0
		for emitter in particle_emitters:
			if !emitter.is_inside_tree():
				add_child(emitter)
			if is_instance_valid(emitter):
				var layer: int = particle_mesh_array[1][index]
				var mesh: Mesh = particle_mesh_array[0][index]
				emitter.set_draw_pass_mesh(0, mesh)
#				emitter.set_lifetime(60.0)
				emitter.set_amount(instance_count)
				var aabb: AABB
				aabb.size = Vector3(instance_area, height, instance_area)
				aabb.position = -(aabb.size / 2.0)
				emitter.set_visibility_aabb(aabb)
				var material: ShaderMaterial = emitter.get_process_material()
				if !material:
					material = ShaderMaterial.new()
					material.set_shader(_PARTICLE_SHADER)
					material.set_shader_parameter("terrain_heightmap", surface_material.get_shader_parameter("terrain_heightmap"))
					material.set_shader_parameter("terrain_normalmap", surface_material.get_shader_parameter("terrain_normalmap"))
					emitter.set_process_material(material)
				material.set_shader_parameter("terrain_height", height)
				material.set_shader_parameter("terrain_size", size)
				material.set_shader_parameter("seed", index)
				material.set_shader_parameter("instance_count", instance_count)
				material.set_shader_parameter("instance_density", particle_density)
				var splatmap_parameter: String = "terrain_splatmap_0" + str(((layer - 1) / 4)+1)
				material.set_shader_parameter("terrain_splatmap", surface_material.get_shader_parameter(splatmap_parameter))
				var splat_channel: Color = splat_channels[wrapi(layer, 1, 5) - 1]
				material.set_shader_parameter("terrain_splatmap_channel", splat_channel)
				
			index += 1
		
func update():

	clear()
	update_lod()
	
	if lod_meshes.is_empty():
		print("Terrain failed. No meshes were created.")
		return

	update_material()
	update_particles()
	update_collision()
	
	var offset = Vector3(1,0,1) * (lod_size / 2)
	
	var side: int = size / lod_size
	
	for x in side:
		for z in side:
			var chunk: Chunk = Chunk.new()
			add_child(chunk)
			chunk.set_mesh(lod_meshes[0]) 
			var pos = Vector3(x - (side / 2), 0, z - (side / 2)) * lod_size + offset
			chunk.call_deferred("set_position", pos)
			chunks.push_back(chunk)
			
	update_aabb()
	
	_update_pending = false
	
func clear():
	for i in chunks:
		i.queue_free()
	chunks.clear()
	
func update_aabb():
	for chunk in chunks:
		var aabb: AABB = chunk.get_aabb()
		aabb.size.y = height * 2
		chunk.set_custom_aabb(aabb)
		
func update_collision():
	
	if !physics_body:
		physics_body = StaticBody3D.new()
		add_child(physics_body)

	var collision_shape: CollisionShape3D
	if physics_body.get_child_count() > 0:
		collision_shape = physics_body.get_child(0)
	
	if !collision_shape:
		collision_shape = CollisionShape3D.new()
		physics_body.add_child(collision_shape)
		var shape: HeightMapShape3D = HeightMapShape3D.new()
		collision_shape.set_shape(shape)
	
	var shape_size: int = size + 1
	var collision_scale: float = 1.0
	
	if Engine.is_editor_hint():
		# use smaller collider in editor for faster editing
		shape_size = _EDITOR_COLLISION_SIZE + 1
		collision_scale = size / _EDITOR_COLLISION_SIZE
	else:
		# let's not mess with the collision layers in the editor
		physics_body.collision_layer = collision_layer
		physics_body.collision_mask = collision_mask
	
	# non-uniform scaling is usually bad for collision detection
	physics_body.scale = Vector3(collision_scale, 1.0, collision_scale)
	
	collision_shape.shape.map_width = shape_size
	collision_shape.shape.map_depth = shape_size
	
	if has_material():
		var hmap: Image = get_material().get_heightmap().get_image()
		
		var map_data: PackedFloat32Array = PackedFloat32Array()
		
		for y in shape_size:
			for x in shape_size:
				var uv: Vector2 = Vector2(x,y) / float(shape_size)
				var h: float = hmap.get_pixelv(Vector2(hmap.get_size()) * uv).r * height
				map_data.push_back(h)
		
		collision_shape.shape.set_map_data(map_data)
	
func update_lod():
	
	if !lod_count:
		return 
		
	lod_meshes.resize(lod_count)
	var previous_subdivision: int = 1
	
	var subdivision = (lod_size / previous_subdivision)
	
	for i in lod_count:
		
		var mesh = GridMesh.new(subdivision, lod_size)
		mesh.surface_set_material(0, surface_material)
		lod_meshes[i] = mesh
		
		previous_subdivision *= 2
		subdivision = (lod_size / previous_subdivision)

func _notification(what):
	
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		# Lock the transform
		global_transform = Transform3D.IDENTITY
		
func _get_property_list():
	var property_list: Array = [
		{
			"name": "particle_mesh_array",
			"type": TYPE_ARRAY,
			"usage": PROPERTY_USAGE_STORAGE,
		},
		{
			"name": "particle_mask_texture",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_STORAGE,
		},
	]
	return property_list

class Chunk extends MeshInstance3D:
	
	var lod_level: int = -1
	
	func set_current_lod_level(value: int):
		lod_level = value
		
	func get_current_lod_level():
		return lod_level

class GridMesh extends ArrayMesh:
	
	# Do not look here. It's ugly.
	# Source for the mesh generation: https://catlikecoding.com/unity/tutorials/rounded-cube/
	
	var size: Vector3 = Vector3.ONE
	
	func _init(_subdivision: int = 2, _width: int = 64, _height: int = 1):
		
		size = Vector3(_width, _height, _width)
		
		var _data = create(_subdivision)
		
		var arrays = []
		arrays.resize(ArrayMesh.ARRAY_MAX)
		
		arrays[ArrayMesh.ARRAY_VERTEX] = _data[0]
		arrays[ArrayMesh.ARRAY_INDEX] = _data[1]
		
		add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		
	func create(subdivision):
		
		var bounds = Vector3(subdivision, 1, subdivision)
		
		var offset = subdivision / 2

		var subdivision_y = 1

		var cornerVertices = 8
		var edgeVertices = (subdivision + subdivision_y + subdivision - 3) * 4
		
		var faceVertices = (
			(subdivision - 1) * (subdivision_y - 1) +
			(subdivision - 1) * (subdivision - 1) +
			(subdivision_y - 1) * (subdivision - 1)) * 2
			
		var vertices = PackedVector3Array()
		
		var triangles = []
		
		vertices.resize(cornerVertices + edgeVertices + faceVertices)
		
		var v = 0
		var y = 0
		
		while y <= subdivision_y:
			var x = 0
			
			while x <= subdivision:
				vertices[v] = (Vector3(x-offset,y-1 ,0-offset) / bounds) * size
				x += 1
				v += 1
			var z = 1
			while z <= subdivision:
				vertices[v] =( Vector3(subdivision-offset,y-1,z-offset) / bounds) * size
				z += 1
				v += 1
			x = subdivision - 1
			
			while x >= 0:
				vertices[v] = (Vector3(x-offset,y-1,subdivision-offset) / bounds) * size
				x -= 1
				v += 1
			z = subdivision - 1
			while z > 0:
				vertices[v] = (Vector3(0-offset,y-1,z-offset) / bounds) * size
				z -= 1
				v += 1
			y += 1

		var z = 1
		
		while z < subdivision:
			var x = 1
			while x < subdivision:
				vertices[v] = (Vector3(x-offset, 0, z-offset) / bounds) * size
				x += 1
				v += 1
			z += 1
		z = 1
		while z < subdivision:
			var x = 1
			while x < subdivision:
				vertices[v] = (Vector3(x-offset, 0, z-offset) / bounds) * size
				x += 1
				v += 1
			z += 1

		triangles = set_tris(subdivision, subdivision_y)

		return [vertices, triangles]

	func set_tris(subdivision, subdivision_y):
		
		var quads = (subdivision * subdivision_y + subdivision * subdivision + subdivision_y * subdivision) * 2
		var tris = []
		tris.resize(quads*6) 
		var ring = (subdivision+subdivision) * 2
		var t = 0
		var v = 0
		var y = 0
		
		while y < subdivision_y:
			var q = 0
			while q < ring - 1:
				t = set_quad(tris, t, v, v+1, v+ring, v+ring+1)
				v += 1
				q += 1
			t = set_quad(tris, t, v, v-ring+1, v+ring, v+1)
			y += 1
			v += 1
			
		var top_v = ring * subdivision_y
		var x = 0
		
		while x < (subdivision - 1):
			t = set_quad(tris, t, top_v, top_v+1, top_v+ring-1, top_v+ring)
			x += 1
			top_v += 1
		t = set_quad(tris, t, top_v, top_v+1, top_v+ring-1, top_v+2)
		
		var vmin = (ring * (subdivision_y+1)) - 1
		var vmid = vmin + 1
		var vmax = top_v + 2
		
		var z = 1
		while z < (subdivision - 1):
			t = set_quad(tris, t, vmin, vmid, vmin-1, vmid+subdivision-1)
			x = 1
			while x < (subdivision - 1):
				t = set_quad(tris, t, vmid, vmid+1, vmid+subdivision-1, vmid+subdivision)
				x += 1
				vmid += 1
			t = set_quad(tris, t, vmid, vmax, vmid+subdivision-1, vmax+1)
			z += 1
			vmin -= 1
			vmid += 1
			vmax += 1
			
		var vtop = vmin - 2
		t = set_quad(tris, t, vmin, vmid, vtop+1, vtop)
		x = 1
		while x < (subdivision - 1):
			t = set_quad(tris, t, vmid, vmid+1, vtop, vtop-1)
			x += 1
			vtop -= 1
			vmid += 1
		t = set_quad(tris, t, vmid, vtop-2, vtop, vtop-1)

		return PackedInt32Array(tris)

	func set_quad(tris, i, v00, v10, v01, v11):
		
		tris[i] = v00
		tris[i+4] = v10
		tris[i+1] = tris[i+4]
		tris[i+3] = v01
		tris[i+2] = tris[i+3]
		tris[i+5] = v11
		return i + 6

class TerrainUtil extends Object:
	
	# Helper class.
	
	static func get_camera():
		var editor_script: EditorScript = EditorScript.new()
		var editor_interface: EditorInterface = editor_script.get_editor_interface()
		var camera = find_editor_camera(editor_interface.get_editor_main_screen().get_children())
		return camera

	static func find_editor_camera(nodes: Array):
		for child in nodes:
			var camera: Camera3D = find_editor_camera(child.get_children())
			if camera:
				return camera
			if child is Camera3D:
				return child
	
