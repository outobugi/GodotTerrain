@tool
@icon("res://addons/terrain_3d/icons/icon_terrain.svg")
class_name Terrain3D
extends Node3D

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

const _EDITOR_COLLISION_SIZE: int = 256

var _update_pending: bool = false

var size: int = 1024 :
	set = set_size, get = get_size
	
var height: int = 64 :
	set = set_height, get = get_height
	
@export_group("Section", "section_")
@export_enum("32:32", "64:64", "128:128", "256:256") var section_size: int = 64 :
	set = set_section_size

@export_group("LOD", "lod_")
@export_range(1,16) var lod_count: int = 4 :
	set = set_lod_count
@export_range(0.0,512.0) var lod_distance: float = 48 :
	set = set_lod_distance

@export_group("Material", "surface_")

@export var surface_material: TerrainMaterial3D :
	set = set_material

@export_group("Detail", "detail_")

@export_range(0,512) var detail_draw_distance: int = 64 :
	set = set_detail_draw_distance
	
@export_range(1,16) var detail_density: int = 4 :
	set = set_detail_density

var detail_instances: Array[RID]
var detail_multimeshes: Array[RID]
var detail_mesh_array: Array[Array]

@export_group("Collision", "collision_")

@export_flags_3d_physics var collision_layer: int = 1
@export_flags_3d_physics var collision_mask: int = 1

var body: RID
var meshes: Array[RID]
var grid: Array[Array]

func _init():
	set_notify_transform(true)
	if !is_inside_tree():
		call_deferred("build", size, section_size, lod_count)
	
func _get_configuration_warnings():
	if !has_material():
		var string_arr: PackedStringArray = ["Terrain has no material. Painting disabled."]
		return string_arr
			
func set_size(value: int):
	if value != size:
		
		size = value
		emit_signal("resolution_changed")
		
		clear(true, true, false)
		build(size, section_size, lod_count)

func get_size():
	return size
		
func set_height(value: int):
	if value != height:
		height = value
		
		if surface_material:
			surface_material.set_height(height)
		
		call_deferred("update_collider_heights")
		emit_signal("resolution_changed")
	
func get_height():
	return height

func set_section_size(value: int):
	if value != section_size:
		section_size = value
		
		clear(true, false, false)
		build(size, section_size, lod_count)

func set_lod_count(value: int):
	if value != lod_count:
		lod_count = value
		
		clear(true, false, false)
		build(size, section_size, lod_count)
		
func set_lod_distance(value: float):
	if value != lod_distance:
		lod_distance = value
		
		for section in grid:
			var lod: int = 0
			for instance in section:
				var min: float = float(lod * section_size) + float(lod_distance) if lod > 0 else float(lod * section_size)
				var max = 0.0 if lod == lod_count - 1 else float((lod + 1) * section_size + lod_distance)
				lod += 1
				
				RenderingServer.instance_geometry_set_visibility_range(instance, min, max, 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
		
func set_detail_draw_distance(value: int):
	detail_draw_distance = value
	update_details()
	
func set_detail_density(value: int):
	detail_density = max(value, 1)
	update_details()

func set_detail_mesh(mesh: Mesh, layer: int, index: int):
	push_warning("Details are not implemented!")
	return
	
	if index < detail_mesh_array[0].size():
		if mesh == null:
			detail_mesh_array[0].remove_at(index)
			detail_mesh_array[1].remove_at(index)
		else:
			detail_mesh_array[0][index] = mesh
			detail_mesh_array[1][index] = layer
	else:
		detail_mesh_array[0].append(mesh)
		detail_mesh_array[1].append(layer)
	
	update_details()
	
## Returns an array of particle meshes used in the particle rendering.
func get_detail_meshes():
	return detail_mesh_array
	
## Sets the [TerrainMaterial3D] to all LOD meshes.
func set_material(material: TerrainMaterial3D):
	
	if material:
		var path: String = material.get_path()
		var is_saved: bool = path.ends_with(".material") or path.ends_with(".res")
		
		if !is_saved:
			push_warning("Material is not saved to disk. Save it as .res or .material!")
			material.call_deferred("set_size", size)
		else:
			set_size(material.get_size())
		
		material.call_deferred("set_height", height)
	
	var rid: RID = RID() if !material else material.get_rid()
	
	for mesh in meshes:
		RenderingServer.mesh_surface_set_material(mesh, 0, rid)

	update_configuration_warnings()
	notify_property_list_changed()
	
	surface_material = material
	call_deferred("emit_signal", "material_changed")
	call_deferred("update_collider_heights")
	
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

## Details are not implemented.
func update_details():
	
	return
	
	if detail_mesh_array.is_empty():
		detail_mesh_array.append(Array())
		detail_mesh_array.append(Array())

	if detail_mesh_array[0].size() < detail_instances.size():
		var count: int = detail_instances.size() - detail_mesh_array[0].size()
		for i in count:
			var instance: RID = detail_instances.pop_back()
			RenderingServer.free_rid(instance)
	else:
		var count: int = detail_mesh_array[0].size() - detail_instances.size()
		for i in count:
			var instance: RID = RenderingServer.instance_create()
			RenderingServer.instance_set_scenario(instance, get_world_3d().get_scenario())
			detail_instances.append(instance)
			
	# Fuck it. Let's free all of them. 
	for base in detail_multimeshes:
		RenderingServer.free_rid(base)
		
	detail_multimeshes.clear()
			
	if detail_instances.size() == detail_mesh_array[0].size():
	
		var sqr_radius: float = float(detail_draw_distance) * sqrt(PI) # Math
		var instance_area: int = int((sqr_radius * sqr_radius) / 2.0)
		
		var instance_count: int = instance_area / detail_density / detail_density
		
		var index: int = 0
		for instance in detail_instances:
			var layer: int = detail_mesh_array[1][index]
			var mesh: Mesh = detail_mesh_array[0][index]
				
			var multimesh: RID = RenderingServer.multimesh_create()
			RenderingServer.instance_set_base(instance, multimesh)
			RenderingServer.multimesh_allocate_data(multimesh, instance_count, RenderingServer.MULTIMESH_TRANSFORM_3D)
			RenderingServer.multimesh_set_mesh(multimesh, mesh.get_rid())
			RenderingServer.instance_set_ignore_culling(instance, true)
			
			for i in instance_count:
				var t: Transform3D = Transform3D.IDENTITY
				RenderingServer.multimesh_instance_set_transform(multimesh, i, t)
			
			index += 1
		
func build(p_size: int, p_section_size: int, p_lod_count: int):
	
	var side: int = p_size / p_section_size
	var scenario: RID = get_world_3d().get_scenario()
	
	var previous_subdv: int = 1
	var subdv: int = p_section_size
	var material: RID = RID() if !surface_material else surface_material.get_rid()
	
	for lod in p_lod_count:
		var mesh: RID = create_section_mesh(p_section_size, subdv, material)
		meshes.push_back(mesh)
		previous_subdv *= 2
		subdv = (p_section_size / previous_subdv)
	
	for x in side:
		for z in side:
			var section: Array = []
			var pos = Vector3(x, 0, z) * p_section_size - Vector3(size / 2, 0, size / 2)
			
			for lod in p_lod_count:
				var t: Transform3D = Transform3D(Basis(), pos)
				var instance: RID = RenderingServer.instance_create()
				var mesh: RID = meshes[lod]

				var min: float = float(lod * p_section_size) + float(lod_distance) if lod > 0 else float(lod * p_section_size)
				var max = 0.0 if lod == p_lod_count - 1 else float((lod + 1) * p_section_size + lod_distance)
				
				RenderingServer.instance_set_base(instance, mesh)
				RenderingServer.instance_set_scenario(instance, scenario)
				RenderingServer.instance_set_transform(instance, t)
				RenderingServer.instance_geometry_set_visibility_range(instance, min, max, 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
				
				section.push_back(instance)
			grid.push_back(section)
			
	update_aabb()
	update_details()
	
	if !body.is_valid():
		body = PhysicsServer3D.body_create()
		var shape: RID = PhysicsServer3D.heightmap_shape_create();

		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, get_world_3d().get_space())
		PhysicsServer3D.body_add_shape(body, shape);

		var shape_data: Dictionary = Dictionary()
		var shape_size: int = p_size + 1
		var shape_scale: float = 1.0
		
		if Engine.is_editor_hint():
			shape_size = _EDITOR_COLLISION_SIZE + 1
			shape_scale = p_size / _EDITOR_COLLISION_SIZE
		else:
			PhysicsServer3D.body_set_collision_layer(body, collision_layer)
			PhysicsServer3D.body_set_collision_mask(body, collision_mask)

		PhysicsServer3D.body_set_shape_transform(body, 0, Transform3D(Basis.from_scale(Vector3(shape_scale, 1.0, shape_scale)), Vector3()))

		var map_data: PackedFloat32Array = PackedFloat32Array()
		map_data.resize(shape_size * shape_size)
	
		shape_data["width"] = shape_size
		shape_data["depth"] = shape_size
		shape_data["heights"] = map_data
		shape_data["min_height"] = 0.0
		shape_data["max_height"] = float(height)

		PhysicsServer3D.shape_set_data(shape, shape_data)

## Clear terrain.
func clear(p_clear_meshes: bool = true, p_clear_collision: bool = true, p_clear_details: bool = true):
	
	if p_clear_meshes:
		for mesh in meshes:
			RenderingServer.free_rid(mesh)
		for section in grid:
			for lod in section:
				RenderingServer.free_rid(lod)
				
		meshes.clear()
		grid.clear()
	
	if p_clear_collision:
		if body.is_valid():
			var shape: RID = PhysicsServer3D.body_get_shape(body, 0)
			PhysicsServer3D.free_rid(shape)
			PhysicsServer3D.free_rid(body);
			body = RID()
			
	if p_clear_details:
		for multimesh in detail_multimeshes:
			RenderingServer.free_rid(multimesh)
		
		for instance in detail_instances:
			RenderingServer.free_rid(instance)
			
		detail_multimeshes.clear()
		detail_instances.clear()
	
## Updates each chunk's [AABB] to match the terrain height.
func update_aabb():
	
	var aabb_size: Vector3 = Vector3(section_size, height, section_size)
	var aabb: AABB = AABB((-aabb_size / 2), aabb_size)
	aabb = aabb.grow(4.0)
	
	for mesh in meshes:
		RenderingServer.mesh_set_custom_aabb(mesh, aabb)
		
func update_collider_heights():
	
	var shape: RID = PhysicsServer3D.body_get_shape(body, 0)
	var shape_data: Dictionary = PhysicsServer3D.shape_get_data(shape)
	var heights: PackedFloat32Array = PackedFloat32Array()
		
	if has_material():
		var hmap: Image = get_material().get_heightmap().get_image()
		for y in shape_data.width:
			for x in shape_data.depth:
				var uv: Vector2 = Vector2(x,y) / Vector2(shape_data.width, shape_data.depth)
				var h: float = hmap.get_pixelv(Vector2(hmap.get_size()) * uv).r * height
				heights.push_back(h)
	else:
		heights.resize(shape_data.width * shape_data.depth)
		
	shape_data.heights = heights
	PhysicsServer3D.shape_set_data(shape, shape_data)
	
func _notification(what):
	
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			global_transform = Transform3D.IDENTITY
			
		NOTIFICATION_PREDELETE:
			clear()
			
		NOTIFICATION_VISIBILITY_CHANGED:
			if is_inside_tree():
				for section in grid:
					for lod in section:
						RenderingServer.instance_set_visible(lod, is_visible_in_tree())
						
				for instance in detail_instances:
					RenderingServer.instance_set_visible(instance, is_visible_in_tree())

		NOTIFICATION_ENTER_WORLD:
			for section in grid:
				for lod in section:
					RenderingServer.instance_set_scenario(lod, get_world_3d().get_scenario())
					
			for instance in detail_instances:
				RenderingServer.instance_set_scenario(instance, get_world_3d().get_scenario())
				
			if body.is_valid():
				PhysicsServer3D.body_set_space(body, get_world_3d().get_space())
				
		NOTIFICATION_EXIT_WORLD:
			for section in grid:
				for lod in section:
					RenderingServer.instance_set_scenario(lod, RID())
			
			for instance in detail_instances:
				RenderingServer.instance_set_scenario(instance, RID())
				
			if body.is_valid():
				PhysicsServer3D.body_set_space(body, RID())

func _get_property_list():
	
	var property_usage: int = PROPERTY_USAGE_DEFAULT
	
	if has_material():
		property_usage = PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
	
	var property_list: Array = [
		{
			"name": "size",
			"type": TYPE_INT,
			"hint_string": "512:512, 1024:1024, 2048:2048, 4096:4096, 8192:8192",
			"hint": PROPERTY_HINT_ENUM,
			"usage": property_usage,
		},
		{
			"name": "height",
			"type": TYPE_INT,
			"hint_string": "1, 8192",
			"hint": PROPERTY_HINT_RANGE,
			"usage": PROPERTY_USAGE_DEFAULT,
		},
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

func create_section_mesh(p_size: int, p_subdivision: int, p_material: RID):
	
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()

	var index: int = 0
	var s: float = p_size
	var subdv: float = p_subdivision
	var ofs: Vector3 = Vector3(p_size,0.0, p_size) / 2.0
	
		# top
	for y in p_subdivision:
		for x in p_subdivision:
			vertices.append(Vector3(x / subdv * s, 0.0, y / subdv * s) - ofs)
			vertices.append(Vector3(x / subdv * s + s / subdv, 0.0, y / subdv * s) - ofs)
			vertices.append(Vector3(x / subdv * s, 0.0, y / subdv * s + s / subdv) - ofs)
			vertices.append(Vector3(x / subdv * s, 0.0, y / subdv * s + s / subdv) - ofs)
			vertices.append(Vector3(x / subdv * s + s / subdv, 0.0, y / subdv * s) - ofs)
			vertices.append(Vector3(x / subdv * s + s / subdv, 0.0, y / subdv * s + s / subdv) - ofs)
			indices.append(index)
			indices.append(index + 1)
			indices.append(index + 2)
			indices.append(index + 3)
			indices.append(index + 4)
			indices.append(index + 5)
			index += 6
	# front
	for x in p_subdivision:
		vertices.append(Vector3(x / subdv * s, -1, 0) - ofs)
		vertices.append(Vector3(x / subdv * s + s / subdv, -1, 0) - ofs)
		vertices.append(Vector3(x / subdv * s, 0, 0) - ofs)
		vertices.append(Vector3(x / subdv * s, 0, 0) - ofs)
		vertices.append(Vector3(x / subdv * s + s / subdv, -1, 0) - ofs)
		vertices.append(Vector3(x / subdv * s + s / subdv, 0, 0) - ofs)
		indices.append(index)
		indices.append(index + 1)
		indices.append(index + 2)
		indices.append(index + 3)
		indices.append(index + 4)
		indices.append(index + 5)
		index += 6
			
		# back
	for x in p_subdivision:
		vertices.append(Vector3(x / subdv * s + s / subdv, 0, s) - ofs)
		vertices.append(Vector3(x / subdv * s + s / subdv, -1, s) - ofs)
		vertices.append(Vector3(x / subdv * s, 0, s) - ofs)
		vertices.append(Vector3(x / subdv * s, 0, s) - ofs)
		vertices.append(Vector3(x / subdv * s + s / subdv, -1, s) - ofs)
		vertices.append(Vector3(x / subdv * s, -1, s) - ofs)
		indices.append(index)
		indices.append(index + 1)
		indices.append(index + 2)
		indices.append(index + 3)
		indices.append(index + 4)
		indices.append(index + 5)
		index += 6
		
	# right
	for x in p_subdivision:
		vertices.append(Vector3(0, 0, x / subdv * s + s / subdv) - ofs)
		vertices.append(Vector3(0, -1, x / subdv * s + s / subdv) - ofs)
		vertices.append(Vector3(0, 0, x / subdv * s) - ofs)
		vertices.append(Vector3(0, 0, x / subdv * s) - ofs)
		vertices.append(Vector3(0, -1, x / subdv * s + s / subdv) - ofs)
		vertices.append(Vector3(0, -1, x / subdv * s) - ofs)
		indices.append(index)
		indices.append(index + 1)
		indices.append(index + 2)
		indices.append(index + 3)
		indices.append(index + 4)
		indices.append(index + 5)
		index += 6
			
		# left
	for x in p_subdivision:
		vertices.append(Vector3(s, -1, x / subdv * s) - ofs)
		vertices.append(Vector3(s, -1, x / subdv * s + s / subdv) - ofs)
		vertices.append(Vector3(s, 0, x / subdv * s) - ofs)
		vertices.append(Vector3(s, 0, x / subdv * s) - ofs)
		vertices.append(Vector3(s, -1, x / subdv * s + s / subdv) - ofs)
		vertices.append(Vector3(s, 0, x / subdv * s + s / subdv) - ofs)
		indices.append(index)
		indices.append(index + 1)
		indices.append(index + 2)
		indices.append(index + 3)
		indices.append(index + 4)
		indices.append(index + 5)
		index += 6
	
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh: RID = RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(mesh, RenderingServer.PRIMITIVE_TRIANGLES, arrays)
	RenderingServer.mesh_surface_set_material(mesh, 0, p_material)
	return mesh
