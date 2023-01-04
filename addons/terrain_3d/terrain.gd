@tool
class_name Terrain3D
extends Node3D
@icon("res://addons/terrain_3d/icons/icon_terrain.svg")

## Terrain3D creates a grid of MeshInstance3D's with varying LOD meshes.
##
## Similar to GridMap, it handles the rendering and collision internally.
## It uses [HeightMapShape3D] for collision and a special [TerrainMaterial3D] for rendering.
## Supports terrains up to 64km2 in size.[br]
## [br]
## [b]Note:[/b] It is recommended to save the [TerrainMaterial3D] to disk as a binary resource (.res or .material) for faster load times.

## Emitted when size or height changes.
signal resolution_changed()
## Emitted when material changes.
signal material_changed()

const _SURFACE_SHADER: Shader = preload("res://addons/terrain_3d/terrain.gdshader")
const _DEFAULT_GRID_TEXTURE: Texture2D = preload("res://addons/terrain_3d/temp/grid_albedo.png")
const _PARTICLE_SHADER: Shader = preload("res://addons/terrain_3d/particle.gdshader")
const _EDITOR_COLLISION_SIZE: int = 256
const _MIN_TRAVEL_DISTANCE: float = 8.0

var _update_pending: bool = false

@export_enum("512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var size: int = 1024 :
	set = set_size
@export var height: int = 64 :
	set = set_height

@export_group("LOD", "lod_")

@export var lod_count: int = 4 :
	set = set_lod_count
@export_enum("32:32", "64:64", "128:128", "256:256") var lod_size: int = 64 :
	set = set_lod_size
@export var lod_bias: float = 0.2 :
	set = set_lod_bias

@export_group("Material", "surface_")

@export var surface_material: TerrainMaterial3D :
	set = set_material

@export_subgroup("Particles", "particle_")

@export var particle_draw_distance: int = 64 :
	set = set_particle_draw_distance
	
@export var particle_density: int = 4 :
	set = set_particle_density

var particle_emitters: Array[GPUParticles3D]
var particle_process_material: ShaderMaterial # Unused for now because particle shader doesn't support per instance uniforms
var particle_mesh_array: Array[Array]
var particle_mask_texture: Texture2D

@export_group("Collision", "collision_")

@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

var physics_body: StaticBody3D
var mesh: TerrainGridMesh
var grid: Array[RID]
var camera: Camera3D

func _init():
	set_notify_transform(true)
	if !is_inside_tree():
		_update_pending = true
		call_deferred("update")
		
func _exit_tree():
	clear()
	set_process(false)
		
func _process(delta):
	if !camera:
		if Engine.is_editor_hint():
			camera = TerrainUtil.get_camera()
		else:
			camera = get_viewport().get_camera_3d()
	else:
		var camera_position = camera.global_transform.origin * Vector3(1,0,1)
		
		for emitter in particle_emitters:
			emitter.global_transform.origin = camera_position
			
func set_visible(value: bool):
	super(value)
	for i in grid:
		RenderingServer.instance_set_visible(i, value)
				
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
			
func set_lod_bias(value: float):
	if value != lod_bias:
		lod_bias = value
		if !_update_pending:
			for i in grid:
				RenderingServer.instance_geometry_set_lod_bias(i, lod_bias)
		
func set_particle_draw_distance(value: int):
	particle_draw_distance = value
	update_particles()
	
## Sets the density/spacing of the particles drawn on the terrain
func set_particle_density(value: int):
	particle_density = max(value, 1)
	update_particles()
	
## Sets an mesh to a specific particle emitter.
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
	
## Returns an array of particle meshes used in the particle rendering.
func get_particle_meshes():
	return particle_mesh_array
	
## Sets the [TerrainMaterial3D] to all LOD meshes.
func set_material(material: TerrainMaterial3D):
	surface_material = material
	if surface_material:
		surface_material.call_deferred("set_height", height)
		surface_material.call_deferred("set_size", size)
	
	call_deferred("emit_signal", "material_changed")
	
	mesh.surface_set_material(0, surface_material)
	
## Returns the assigned [TerrainMaterial3D]
func get_material() -> TerrainMaterial3D:
	return surface_material
	
## Check if the terrain has [TerrainMaterial3D]
func has_material() -> bool:
	return surface_material != null
	
## Passes terrain properties to the [TerrainMaterial3D]
func update_material():
	if surface_material:
		surface_material.set_resolution(size, height)

## Update or creates an array of [GPUParticles3D].
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
		
		var splat_channels: Array[Color] = [Color(1,0,0,0), Color(0,1,0,0), Color(0,0,1,0), Color(0,0,0,1)]
		
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
					material.set_shader_parameter("terrain_heightmap", surface_material.get_heightmap())
					material.set_shader_parameter("terrain_normalmap", surface_material.get_normalmap())
					emitter.set_process_material(material)
					
				material.set_shader_parameter("terrain_height", height)
				material.set_shader_parameter("terrain_size", size)
				material.set_shader_parameter("seed", index)
				material.set_shader_parameter("instance_count", instance_count)
				material.set_shader_parameter("instance_density", particle_density)
				material.set_shader_parameter("terrain_splatmap", surface_material.get_splatmap(layer / 4))
				var splat_channel: Color = splat_channels[wrapi(layer, 0, 4)]
				material.set_shader_parameter("terrain_splatmap_channel", splat_channel)
			index += 1
		
## Updates all of the terrain. Calls every [i]update_[/i] function.
func update():

	clear()
	
	update_material()
	update_particles()
	update_collision()
	
	var offset = Vector3(1,0,1) * (lod_size / 2)
	var side: int = size / lod_size
	var scenario: RID = get_world_3d().get_scenario()
	
	mesh = TerrainGridMesh.new(float(lod_size), lod_count)
	mesh.surface_set_material(0, surface_material)
	
	for x in side:
		for z in side:
			var instance: RID = RenderingServer.instance_create2(mesh.get_rid(), scenario)
			var pos = Vector3(x - (side / 2), 0, z - (side / 2)) * lod_size + offset
			var t: Transform3D = Transform3D(Basis(), pos)
			
			RenderingServer.instance_set_transform(instance, t)
			RenderingServer.instance_geometry_set_lod_bias(instance, lod_bias)
			
			grid.push_back(instance)
			
	update_aabb()
	_update_pending = false
	
## Clear all chunk instances.
func clear():
	for i in grid:
		RenderingServer.free_rid(i)
	grid.clear()
	
## Updates each chunk's [AABB] to match the terrain height.
func update_aabb():
	for i in grid:
		var aabb_size: Vector3 = Vector3(lod_size+2, height, lod_size+2)
		var aabb: AABB = AABB(Vector3(-lod_size/2, -2, -lod_size/2), aabb_size)
		RenderingServer.instance_set_custom_aabb(i, aabb)
		
## Creates a missing or updates current [StaticBody] with [HeightMapShape3D] and applies existing heightmap to it.
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

class TerrainGridMesh extends ArrayMesh:

	func _init(size: float, lod_count: int):
		
		lod_count -= 1
		
		var vertices: PackedVector3Array = PackedVector3Array()
		var indices: Array[PackedInt32Array] = []

		var index: int = 0
		var subdv = size
		var ofs = Vector3(size,0.0,size) / 2.0
		var previous_subdv = 1.0

		var count = lod_count

		while count >= 0:
			var lod_indices: PackedInt32Array = PackedInt32Array()
			# top
			for y in subdv:
				for x in subdv:
					vertices.append(Vector3(x / subdv * size, 0.0, y / subdv * size) - ofs)
					vertices.append(Vector3(x / subdv * size + size / subdv, 0.0, y / subdv * size) - ofs)
					vertices.append(Vector3(x / subdv * size, 0.0, y / subdv * size + size / subdv) - ofs)
					vertices.append(Vector3(x / subdv * size, 0.0, y / subdv * size + size / subdv) - ofs)
					vertices.append(Vector3(x / subdv * size + size / subdv, 0.0, y / subdv * size) - ofs)
					vertices.append(Vector3(x / subdv * size + size / subdv, 0.0, y / subdv * size + size / subdv) - ofs)
					lod_indices.append(index)
					lod_indices.append(index + 1)
					lod_indices.append(index + 2)
					lod_indices.append(index + 3)
					lod_indices.append(index + 4)
					lod_indices.append(index + 5)
					index += 6;
			# front
			for x in subdv:
				vertices.append(Vector3(x / subdv * size, -1, 0) - ofs)
				vertices.append(Vector3(x / subdv * size + size / subdv, -1, 0) - ofs)
				vertices.append(Vector3(x / subdv * size, 0, 0) - ofs)
				vertices.append(Vector3(x / subdv * size, 0, 0) - ofs)
				vertices.append(Vector3(x / subdv * size + size / subdv, -1, 0) - ofs)
				vertices.append(Vector3(x / subdv * size + size / subdv, 0, 0) - ofs)
				lod_indices.append(index)
				lod_indices.append(index + 1)
				lod_indices.append(index + 2)
				lod_indices.append(index + 3)
				lod_indices.append(index + 4)
				lod_indices.append(index + 5)
				index += 6;
				
			# back
			for x in subdv:
				vertices.append(Vector3(x / subdv * size + size / subdv, 0, size) - ofs)
				vertices.append(Vector3(x / subdv * size + size / subdv, -1, size) - ofs)
				vertices.append(Vector3(x / subdv * size, 0, size) - ofs)
				vertices.append(Vector3(x / subdv * size, 0, size) - ofs)
				vertices.append(Vector3(x / subdv * size + size / subdv, -1, size) - ofs)
				vertices.append(Vector3(x / subdv * size, -1, size) - ofs)
				lod_indices.append(index)
				lod_indices.append(index + 1)
				lod_indices.append(index + 2)
				lod_indices.append(index + 3)
				lod_indices.append(index + 4)
				lod_indices.append(index + 5)
				index += 6;
				
			# right
			for x in subdv:
				vertices.append(Vector3(0, 0, x / subdv * size + size / subdv) - ofs)
				vertices.append(Vector3(0, -1, x / subdv * size + size / subdv) - ofs)
				vertices.append(Vector3(0, 0, x / subdv * size) - ofs)
				vertices.append(Vector3(0, 0, x / subdv * size) - ofs)
				vertices.append(Vector3(0, -1, x / subdv * size + size / subdv) - ofs)
				vertices.append(Vector3(0, -1, x / subdv * size) - ofs)
				lod_indices.append(index)
				lod_indices.append(index + 1)
				lod_indices.append(index + 2)
				lod_indices.append(index + 3)
				lod_indices.append(index + 4)
				lod_indices.append(index + 5)
				index += 6;
				
			# left
			for x in subdv:
				vertices.append(Vector3(size, -1, x / subdv * size) - ofs)
				vertices.append(Vector3(size, -1, x / subdv * size + size / subdv) - ofs)
				vertices.append(Vector3(size, 0, x / subdv * size) - ofs)
				vertices.append(Vector3(size, 0, x / subdv * size) - ofs)
				vertices.append(Vector3(size, -1, x / subdv * size + size / subdv) - ofs)
				vertices.append(Vector3(size, 0, x / subdv * size + size / subdv) - ofs)
				lod_indices.append(index)
				lod_indices.append(index + 1)
				lod_indices.append(index + 2)
				lod_indices.append(index + 3)
				lod_indices.append(index + 4)
				lod_indices.append(index + 5)
				index += 6;
					
			previous_subdv *= 2
			subdv = (size / previous_subdv)
			indices.append(lod_indices)
			
			count -= 1
		
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices[0]
		var blend_shapes = []
		
		var lods = {}
		for i in lod_count:
			lods[float(i+1)] = indices[i + 1]
		
		add_surface_from_arrays(RenderingServer.PRIMITIVE_TRIANGLES, arrays, [], lods)
	

class TerrainUtil extends Object:
	
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
	
