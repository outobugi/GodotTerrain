
@tool
class_name Terrain
extends StaticBody3D

const SHADER: Shader = preload("res://addons/terrain_3d/terrain.gdshader")
const DEFAULT_GRID_TEXTURE: Texture2D = preload("res://addons/terrain_3d/temp/grid_albedo.png")

const MIN_TRAVEL_DISTANCE: float = 8.0



@export_enum("512:512", "1024:1024", "2048:2048", "4096:4096", "8192:8192") var size: int = 1024 :
	set = set_size
@export var height: int = 64 :
	set = set_height
# Partition is the count of chunks on each side.
@export var partition: int = 8 :
	set = set_partition

@export_group("LOD", "lod_")
# Amount of LODs
@export var lod_count: int = 4 :
	set = set_lod_count
# LOD change distance
@export var lod_distance: int = 128
# Freezes LOD processing
@export var lod_disable: bool = false :
	set = set_disabled
	
@export_group("Material", "shader_")

var shader_material: ShaderMaterial
var shader_texture_arrays: Array[Array]


var lod_meshes: Array
var chunks: Array
var camera: Camera3D
var collision_shape: CollisionShape3D
var previous_camera_position: Vector3

func _init():
	
	set_notify_transform(true)
	
	if !is_inside_tree():
		call_deferred("update")
		
func _exit_tree():
	set_process(false)
		
func _process(delta):
	
	if !camera:
		camera = TerrainUtil.get_camera()
	else:
		var camera_position = camera.global_transform.origin * Vector3(1,0,1)
		var distance_traveled: float = previous_camera_position.distance_to(camera_position)
		
		if distance_traveled > MIN_TRAVEL_DISTANCE:
			previous_camera_position = camera_position
			
			for chunk in chunks:
				
				var chunk_pos: Vector3 = chunk.global_transform.origin * Vector3(1,0,1)
				var distance: float = (chunk_pos.distance_to(camera_position))
				var new_lod_level = min(int(distance) / lod_distance, lod_count - 1)
				var old_lod_level = chunk.get_current_lod_level()
				
				if new_lod_level != old_lod_level:
					chunk.set_current_lod_level(new_lod_level)
					chunk.mesh = lod_meshes[new_lod_level]
				
func set_size(value: int):
	if value != size:
		size = value
		call_deferred("update")
		
		if shader_material:
			shader_material.set_shader_parameter("terrain_size", float(value))
		
func set_height(value: int):
	if value != height:
		height = value
		
		if shader_material:
			shader_material.set_shader_parameter("terrain_height", float(value))
			update_normalmap(true)
			
		update_aabb()
		
func set_partition(value: int):
	if value != partition:
		partition = value
		call_deferred("update")
		
func set_lod_count(value: int):
	if value != lod_count:
		lod_count = value
		call_deferred("update")
		
func set_disabled(value: bool):
	set_process(!value)
	lod_disable = value
	
func set_texture(texture: Texture2D, index: int, is_albedo: bool):
	validate_texture_arrays()
	
	var tex_arr: int = 0
	if !is_albedo:
		tex_arr = 1
	
	shader_texture_arrays[tex_arr][index] = texture
	update_textures()
	
func get_texture_arrays():
	validate_texture_arrays()
	return shader_texture_arrays
	
func get_shader():
	return shader_material
	
func update_shader(force_reset: bool = false):
	
	if !shader_material:
		shader_material = ShaderMaterial.new()
		shader_material.set_shader(SHADER)
	
	if shader_material:
		update_heightmap(force_reset)
		update_normalmap(force_reset)
		update_splatmaps(force_reset)
		update_textures()
		
	for mesh in lod_meshes:
		mesh.surface_set_material(0, shader_material)
		
func update_heightmap(force: bool = false):
	shader_material.set_shader_parameter("terrain_height", height)
	var heightmap: ImageTexture = shader_material.get_shader_parameter("terrain_heightmap")
	if !heightmap or force:
		heightmap = ImageTexture.new()
		var img: Image = Image.create(1025, 1025, false, Image.FORMAT_RH)
		heightmap.set_image(img)
		shader_material.set_shader_parameter("terrain_heightmap", heightmap)
		
func update_normalmap(force: bool = false):
	var normalmap: ImageTexture = shader_material.get_shader_parameter("terrain_normalmap")
	if !normalmap or force:
		var heightmap: ImageTexture = shader_material.get_shader_parameter("terrain_heightmap")
		var img: Image = heightmap.get_image().duplicate()
		img.bump_map_to_normal_map(height)
		img.shrink_x2()
		img.generate_mipmaps()
		normalmap = ImageTexture.create_from_image(img)
		shader_material.set_shader_parameter("terrain_normalmap", normalmap)
		
func update_splatmaps(force: bool = false):
	var splatmaps: PackedStringArray = ["terrain_splatmap_01","terrain_splatmap_02","terrain_splatmap_03","terrain_splatmap_04"]
	var is_first: bool = true
	for texture in splatmaps:
		var splatmap: ImageTexture = shader_material.get_shader_parameter(texture)
		if !splatmap or force:
			splatmap = ImageTexture.new()
			var img: Image = Image.create(1024, 1024, true, Image.FORMAT_RGBA8)
			if is_first:
				img.fill(Color(1,0,0,0))
				is_first = false
			splatmap.set_image(img)
			shader_material.set_shader_parameter(texture, splatmap)

func update_textures():
	var albedo_array: Texture2DArray = shader_material.get_shader_parameter("texture_albedos")
	var normal_array: Texture2DArray = shader_material.get_shader_parameter("texture_normals")
	
	validate_texture_arrays()
	
	albedo_array = convert_to_texture_array(shader_texture_arrays[0])
	shader_material.set_shader_parameter("texture_albedos", albedo_array)
	
	normal_array = convert_to_texture_array(shader_texture_arrays[1])
	shader_material.set_shader_parameter("texture_normals", normal_array)

	var use_grid_texture: bool = albedo_array.get_layers() == 0
	if use_grid_texture:
		shader_material.set_shader_parameter("terrain_grid", DEFAULT_GRID_TEXTURE)
	shader_material.set_shader_parameter("use_grid", use_grid_texture)
	
func convert_to_texture_array(arr: Array):
	var img_arr: Array[Image]
	for tex in arr:
		if tex != null:
			var img: Image = tex.get_image()
			if img.is_compressed():
				img.decompress()
			
			img.generate_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
			img_arr.push_front(img)
			
	var tex_arr: Texture2DArray = Texture2DArray.new()
	
	if !img_arr.is_empty():
		img_arr.reverse()
		tex_arr.create_from_images(img_arr)
	return tex_arr
	
func validate_texture_arrays():
	if shader_texture_arrays.size() != 2:
		shader_texture_arrays.clear()
		var a = Array()
		a.resize(16)
		shader_texture_arrays.append(a)
		var n = Array()
		n.resize(16)
		shader_texture_arrays.append(n)
	
func update_multimeshes():
	# create a multimesh for each splat
	pass

func update():

	clear()
	update_lod_meshes()
	
	if lod_meshes.is_empty():
		return
		
	update_shader()
	update_multimeshes()
	update_collision()

	var chunk_size = size / partition
	var chunk_offset = Vector3(1,0,1) * (chunk_size / 2)
	
	for x in partition:
		for z in partition:
			var chunk: Chunk = Chunk.new()
			add_child(chunk)
			
			chunk.set_mesh(lod_meshes[0]) 
			var pos = Vector3(x - (partition / 2), 0, z - (partition / 2)) * chunk_size + chunk_offset
			chunk.call_deferred("set_position", pos)
			chunks.push_back(chunk)
			
	update_aabb()
	
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
	
	if !collision_shape:
		collision_shape = CollisionShape3D.new()
		
		add_child(collision_shape)
		
		var shape: HeightMapShape3D = HeightMapShape3D.new()
		collision_shape.set_shape(shape)
	
	collision_shape.shape.map_width = size + 1
	collision_shape.shape.map_depth = size + 1
	
func update_lod_meshes():
	
	var chunk_size = size / partition
		
	if !lod_count or !chunk_size:
		return 
		
	lod_meshes.resize(lod_count)
	var previous_subdivision: int = 1
	
	var subdivision = (chunk_size / previous_subdivision)
	
	for i in lod_count:
		
		var mesh = GridMesh.new(subdivision, chunk_size)
		mesh.surface_set_material(0, shader_material)
		lod_meshes[i] = mesh
		
		previous_subdivision *= 2
		subdivision = (chunk_size / previous_subdivision)

func _notification(what):
	
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		# Lock the transform
		global_transform = Transform3D.IDENTITY
		
func _get_property_list():
	var property_list: Array = [
		{
			"name": "shader_material",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_DEFAULT,
		},
		{
			"name": "shader_texture_arrays",
			"type": TYPE_ARRAY,
			"usage": PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_DEFAULT,
		}
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
		
class TerrainTextureArray extends Texture2DArray:
	
	const MAX_TEXTURE_SLOTS: int = 16

	@export var texture_array: Array[Texture2D]
	
	func _init():
		texture_array.resize(MAX_TEXTURE_SLOTS)
		texture_array.fill(null)
		
	func set_texture(texture: Texture2D, index: int):
		texture_array[index] = texture
		update()
		emit_changed()
		
	func update():
		
		var img_arr: Array[Image]
		for tex in texture_array:
			if tex != null:
				var img: Image = tex.get_image()
				
				if img.is_compressed():
					img.decompress()
				
				img.convert(Image.FORMAT_RGBA8)
					
				img_arr.push_front(img)
		
		if !img_arr.is_empty():
			create_from_images(img_arr)
			
		notify_property_list_changed()

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
	
