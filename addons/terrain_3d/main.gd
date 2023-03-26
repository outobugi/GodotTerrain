@tool
extends EditorPlugin

var current_terrain: Terrain3D

var mouse_is_pressed: bool = false
var pending_collision_update: bool = false
var toolbar: TerrainToolUI
var gizmo_plugin: Terrain3DGizmoPlugin
var normalmap_generator: NormalmapGenerator

func _enter_tree():
	toolbar = TerrainToolUI.new()
	toolbar.hide()
	normalmap_generator = NormalmapGenerator.new()
	gizmo_plugin = Terrain3DGizmoPlugin.new()
	gizmo_plugin.material = toolbar.GIZMO_MATERIAL # Having the material in toolbar makes it easier to change the brush texture
	add_node_3d_gizmo_plugin(gizmo_plugin)
	add_child(normalmap_generator)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, toolbar)

func _exit_tree():
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, toolbar)
	remove_node_3d_gizmo_plugin(gizmo_plugin)
	toolbar.queue_free()
	normalmap_generator.queue_free()
	
func _handles(object: Object):
	if object is Terrain3D:
		return true
	return false
	
func _edit(object: Object):
	if object is Terrain3D:
		
		if object == current_terrain:
			return
			
		current_terrain = object
		
		load_materials()
		load_meshes()
		
		normalmap_generator.load_heightmap_from(object.get_material())
		
		if !object.is_connected("material_changed", _terrain_on_material_changed):
			object.connect("material_changed", _terrain_on_material_changed)
		if !object.is_connected("resolution_changed", _terrain_on_resolution_changed):
			object.connect("resolution_changed", _terrain_on_resolution_changed)

func _clear():
	
	if is_terrain_valid():
		if current_terrain.is_connected("material_changed", _terrain_on_material_changed):
			current_terrain.disconnect("material_changed", _terrain_on_material_changed)
		if current_terrain.is_connected("resolution_changed", _terrain_on_resolution_changed):
			current_terrain.disconnect("resolution_changed", _terrain_on_resolution_changed)
	current_terrain = null
	
func _make_visible(visible: bool):
	toolbar.visible = visible
	
	if is_terrain_valid() and !visible:
		current_terrain.clear_gizmos()

func _apply_changes():
	if is_terrain_valid():
		if current_terrain.has_material():
			current_terrain.get_material()._apply_editor_normalmap()
	
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent):
	
	if is_terrain_valid():
		if event is InputEventMouse:
			var mouse_pos: Vector2 = event.get_position()
		
			var ray_param: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
			ray_param.set_from(camera.global_transform.origin)
			ray_param.set_to(camera.project_position(mouse_pos, 1024.0))
			
			var space = current_terrain.get_world_3d().get_space()
			var ray_data: Dictionary = PhysicsServer3D.space_get_direct_state(space).intersect_ray(ray_param)
			
			if !ray_data.is_empty():
				
				gizmo_plugin.gizmo_position = ray_data.position
				gizmo_plugin.gizmo_size = toolbar.get_brush_size()
				current_terrain.update_gizmos()
			
			var was_pressed: bool = mouse_is_pressed
			
			if event is InputEventMouseButton and event.get_button_index() == 1:
				mouse_is_pressed = event.is_pressed()
				
			if event is InputEventMouseMotion and mouse_is_pressed:
				
				if !ray_data.is_empty():
					
					if current_terrain.has_material():
						var coord: Vector2 = get_coord_from(ray_data.position)
						
						if toolbar.current_tool == toolbar.Tool.HEIGHT:
							paint_height(coord)
							pending_collision_update = true
						if toolbar.current_tool == toolbar.Tool.TEXTURE:
							paint_control(coord)
						
			if was_pressed and !mouse_is_pressed:
				if pending_collision_update:
					current_terrain.update_collider_heights()
					pending_collision_update = false
						
			if mouse_is_pressed:
				return EditorPlugin.AFTER_GUI_INPUT_STOP
				

func is_terrain_valid():
	return is_instance_valid(current_terrain)

func _terrain_on_material_changed():
	normalmap_generator.load_heightmap_from(current_terrain.get_material())
	load_materials()
	
func _terrain_on_resolution_changed():
	normalmap_generator.update_resolution(current_terrain.get_size(), current_terrain.get_height())

func get_coord_from(pos: Vector3):
	return (Vector2(pos.x, pos.z) + (Vector2(current_terrain.size, current_terrain.size) / 2.0))
	
func rotate_uv(uv: Vector2, rotation: float):
	var rotation_offset = Vector2(0.5,0.5)
	return ((uv - rotation_offset).rotated(rotation) + rotation_offset).clamp(Vector2.ZERO, Vector2.ONE)
	
func is_in_bounds(pixel_position: Vector2i, max_position: Vector2i):
	var more_than_min: bool = pixel_position.x >= 0 and pixel_position.y >= 0 
	var less_than_max: bool =  pixel_position.x < max_position.x and pixel_position.y < max_position.y
	return more_than_min and less_than_max
	
func load_materials():
	var layers: Array[TerrainLayerMaterial3D] = []
	if is_terrain_valid():
		if current_terrain.has_material():
			layers = current_terrain.get_material().get_layer_materials()
	toolbar.load_materials(layers, on_material_changed)
	
func load_meshes():
	var meshes: Array[Array]
	if is_terrain_valid():
		meshes = current_terrain.get_detail_meshes()
	toolbar.load_meshes(meshes, on_mesh_changed)

func on_material_changed(material: TerrainLayerMaterial3D, layer: int, inspect: bool):
	if is_terrain_valid():
		if !inspect:
			if current_terrain.has_material():
				current_terrain.get_material().set_layer_material(material, layer)
			call_deferred("load_materials")
			if !material:
				get_editor_interface().inspect_object(current_terrain, "", true)
		else:
			get_editor_interface().inspect_object(material, "", true)
	
func on_mesh_changed(mesh: Mesh, layer: int, index: int, inspect: bool = false):
	if is_terrain_valid():
		if !inspect:
			if current_terrain.has_material():
				current_terrain.set_detail_mesh(mesh, layer, index)
			call_deferred("load_meshes")
			if !mesh:
				get_editor_interface().inspect_object(current_terrain, "", true)
		else:
			get_editor_interface().inspect_object(mesh, "", true)
		
func paint_height(coord: Vector2):
	var heightmap: ImageTexture = current_terrain.get_material().get_heightmap()
	var heightmap_img: Image = heightmap.get_image()
	var heightmap_size: Vector2i = heightmap_img.get_size()
	
	var brush_size: int = toolbar.get_brush_size()
	var brush_shape: Image = toolbar.get_brush_shape()
	var brush_shape_size: Vector2i = brush_shape.get_size()
	var brush_opacity: float = toolbar.get_brush_opacity()
	var brush_flow: float = toolbar.get_brush_flow()
	
	var rand_rotation: float = PI * randf()
	
	for x in brush_size:
		for y in brush_size:
			var brush_center: int = brush_size / 2

			var brush_shape_uv: Vector2 = Vector2(x,y) / brush_size
			brush_shape_uv = rotate_uv(brush_shape_uv, rand_rotation)
			
			var brush_offset: Vector2i = Vector2i(x, y) - Vector2i(brush_center, brush_center)
			var brush_position: Vector2i = Vector2i(Vector2(heightmap_size) * (coord / current_terrain.size))
			var pixel_position: Vector2i = brush_position + brush_offset
			
			if is_in_bounds(pixel_position, heightmap_size):
				var brush_pixel_position: Vector2i = Vector2i(brush_shape_uv * Vector2(brush_shape_size))
				brush_pixel_position = brush_pixel_position.clamp(Vector2i.ZERO, brush_shape_size - Vector2i.ONE)
				
				var alpha: float = brush_shape.get_pixelv(brush_pixel_position).r
				var source: float = heightmap_img.get_pixelv(pixel_position).r
				var target: float = source
				
				if toolbar.current_mode == toolbar.Mode.HEIGHT_ADD:
					target = lerp(source, source + (brush_opacity * alpha), brush_flow)
					
				if toolbar.current_mode == toolbar.Mode.HEIGHT_SUBTRACT:
					target = lerp(source, source - (brush_opacity * alpha), brush_flow)
					
				if toolbar.current_mode == toolbar.Mode.HEIGHT_MULTIPLY:
					target = lerp(source, source * ((brush_opacity * alpha) + 1.0), brush_flow)
					
				if toolbar.current_mode == toolbar.Mode.HEIGHT_LEVEL:
					target = lerp(source, brush_opacity, alpha * brush_flow)
					
				heightmap_img.set_pixelv(pixel_position, Color(clamp(target, 0, 1), 0, 0, 1))
	
	heightmap.set_image(heightmap_img)
	normalmap_generator.refresh_normalmap()
	
func paint_control(coord: Vector2):
	
	var controlmap: ImageTexture = current_terrain.get_material().get_controlmap()
	var controlmap_img: Image = controlmap.get_image()
	var controlmap_size: Vector2i = controlmap.get_size()
	
	var brush_size: int = toolbar.get_brush_size() / (current_terrain.size / controlmap_size.x)
	var brush_shape: Image = toolbar.get_brush_shape()
	var brush_shape_size: Vector2i = brush_shape.get_size()
	var brush_opacity: float = toolbar.get_brush_opacity()
	var brush_flow: float = toolbar.get_brush_flow()

	var layer_index: int = toolbar.get_material_layer()
	# Max is 255 (256 because 0 is first)
	
	var rand_rotation: float = PI * randf()
	
	for x in brush_size:
		for y in brush_size:
			var brush_center = brush_size / 2
			var brush_shape_uv: Vector2 = Vector2(x,y) / brush_size
			brush_shape_uv = rotate_uv(brush_shape_uv, rand_rotation)
			
			var brush_offset: Vector2i = Vector2i(x, y) - Vector2i(brush_center, brush_center)
			var brush_position: Vector2i = Vector2i(Vector2(controlmap_size) * (coord / current_terrain.size))
			var pixel_position: Vector2i = (brush_position + brush_offset)
			
			if is_in_bounds(pixel_position, controlmap_size):
				var brush_pixel_position: Vector2i = Vector2i(brush_shape_uv * Vector2(brush_shape_size))
				brush_pixel_position = brush_pixel_position.clamp(Vector2i.ZERO, brush_shape_size - Vector2i.ONE)
			
				var alpha: float = brush_shape.get_pixelv(brush_pixel_position).r
				var index_mask: float = 1.0 if alpha > 0.5 else 0.0
				var source_color: Color = controlmap_img.get_pixelv(pixel_position)
				var target_color: Color = source_color # Color(layer1, layer2, blend, unused)
				
				if toolbar.current_mode == toolbar.Mode.TEXTURE_REPLACE:
					var index: int = lerp( int(source_color.r * 255), layer_index, index_mask)
					target_color.r = float(index) / 255.0
					target_color.b = lerp(source_color.b, 0.0, alpha*brush_flow*index_mask) # Weight
					
				if toolbar.current_mode == toolbar.Mode.TEXTURE_BLEND:
					var index: int = lerp(int(source_color.g * 255), layer_index, index_mask)
					target_color.g = float(index) / 255.0
					target_color.b = lerp(source_color.b, brush_opacity, alpha*brush_flow*index_mask) # Weight

				controlmap_img.set_pixelv(pixel_position, target_color)
	
	controlmap.set_image(controlmap_img)
	
	
	
## GIZMO ##
	
class Terrain3DGizmoPlugin extends EditorNode3DGizmoPlugin:
	
	var material: ShaderMaterial
	var mesh: BoxMesh = BoxMesh.new()
	
	var gizmo_position: Vector3
	var gizmo_size: float
	
	func _get_gizmo_name():
		return "Terrain3D"
		
	func _has_gizmo(for_node_3d: Node3D):
		return for_node_3d is Terrain3D
		
	func _redraw(gizmo: EditorNode3DGizmo):
		
		gizmo.clear()
		var t: Transform3D = Transform3D(Basis.from_scale(Vector3.ONE * gizmo_size), gizmo_position)
		gizmo.add_mesh(mesh, material, t)

## VIEWPORT RENDERING ##
class NormalmapGenerator extends Node:
	
	const NORMALMAP_SHADER: Shader = preload("res://addons/terrain_3d/height_to_normal.gdshader")
	var viewport_normalmap: SubViewport
	var canvas_normalmap: Sprite2D

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
		
	func load_heightmap_from(material: TerrainMaterial3D):
		
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

## UI ##

class TerrainToolUI extends MarginContainer:

	const BRUSH_PREVIEW_MATERIAL: ShaderMaterial = preload("res://addons/terrain_3d/ui/brush_preview.material")
	const GIZMO_MATERIAL: ShaderMaterial = preload("res://addons/terrain_3d/ui/gizmo.material")
	const ICON_SCULPT: Texture = preload("res://addons/terrain_3d/icons/icon_height_brush.svg")
	const ICON_PAINT: Texture = preload("res://addons/terrain_3d/icons/icon_brush.svg")
	const ICON_DETAIL: Texture = preload("res://addons/terrain_3d/icons/icon_multimesh.svg")

	enum Tool {
		HEIGHT,
		TEXTURE,
		detail,
		NONE
	}

	enum Mode {
		HEIGHT_ADD,
		HEIGHT_SUBTRACT,
		HEIGHT_MULTIPLY,
		HEIGHT_LEVEL,
		TEXTURE_REPLACE,
		TEXTURE_BLEND,
		detail_MASK,
		MAX
	}

	const MAX_BRUSH_SIZE: int = 200

	var current_tool: Tool = Tool.NONE
	var current_mode: Mode = Mode.MAX
	var current_material_layer: int = 0

	var tool_buttons: HBoxContainer
	var brush_mode_option: BrushToolControl
	var brush_size_slider: BrushToolControl
	var brush_opacity_slider: BrushToolControl
	var brush_flow_slider: BrushToolControl
	var brush_shape_list: BrushToolControl

	var brush_shape_button_group: ButtonGroup = ButtonGroup.new()
	var tool_button_group: ButtonGroup = ButtonGroup.new()

	var material_layers: LayerListContainer
	var mesh_layers: LayerListContainer

	func _init():
		
		custom_minimum_size.x = 230
		set("theme_override_constants/margin_right", 5)
		
		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(vbox)
		
		brush_size_slider = BrushToolControl.new(BrushToolControl.Type.SLIDER, "Size", "m", MAX_BRUSH_SIZE)
		brush_opacity_slider = BrushToolControl.new(BrushToolControl.Type.SLIDER, "Opacity", "%")
		brush_flow_slider = BrushToolControl.new(BrushToolControl.Type.SLIDER, "Flow", "%")
		brush_shape_list = BrushToolControl.new(BrushToolControl.Type.BUTTON_GRID, "Shape")
		brush_mode_option = BrushToolControl.new(BrushToolControl.Type.OPTION, "Mode")
		
		tool_buttons = HBoxContainer.new()
		
		var tool_height: Button = Button.new()
		tool_height.icon = ICON_SCULPT
		tool_height.text = " Sculpt"
		tool_buttons.add_child(tool_height)
		var tool_texture: Button = Button.new()
		tool_texture.icon = ICON_PAINT
		tool_texture.text = " Paint"
		tool_buttons.add_child(tool_texture)
		var tool_detail: Button = Button.new()
		tool_detail.icon = ICON_DETAIL
		tool_detail.text = " Detail"
		tool_buttons.add_child(tool_detail)

		for button in tool_buttons.get_children():
			button.toggle_mode = true
			button.button_group = tool_button_group
			button.size_flags_horizontal = SIZE_EXPAND_FILL
			
		material_layers = LayerListContainer.new("Layers")
		mesh_layers = LayerListContainer.new("Details")
		
		tool_height.connect("toggled", set_tool.bind(Tool.HEIGHT))
		tool_texture.connect("toggled", set_tool.bind(Tool.TEXTURE))
		tool_detail.connect("toggled", set_tool.bind(Tool.detail))
		tool_height.set_pressed(true)
		set_tool(true, Tool.HEIGHT)
		
		brush_mode_option.get_type_control().connect("item_selected", set_mode)
		brush_shape_button_group.connect("pressed", _on_brush_shape_changed)
		
		vbox.add_child(tool_buttons)
		vbox.add_child(HSeparator.new())
		vbox.add_child(brush_mode_option)
		vbox.add_child(HSeparator.new())
		vbox.add_child(brush_shape_list)
		vbox.add_child(brush_size_slider)
		vbox.add_child(brush_opacity_slider)
		vbox.add_child(brush_flow_slider)
		vbox.add_child(material_layers)
		vbox.add_child(mesh_layers)

		call_deferred("load_default_values")
		
	func load_default_values():
		set_brush_size(64)
		set_brush_opacity(50)
		set_brush_flow(25)
		load_brushes()

	func load_brushes():
		var path: String = "res://addons/terrain_3d/brush/"
		var brush_directory: DirAccess = DirAccess.open(path)
		var is_first: bool = true
		
		for button in brush_shape_list.get_type_control().get_children():
			button.queue_free()
			
		var brush_count: int = 0
			
		brush_directory.list_dir_begin()
		var brush_name = brush_directory.get_next()
		while brush_name:
			if !brush_directory.current_is_dir():
				if brush_name.ends_with(".png"):
					var brush: Image = load(path+brush_name)
					var texture: ImageTexture = ImageTexture.create_from_image(brush)
					var brush_button: Button = Button.new()
				
					brush_button.toggle_mode = true
					brush_button.action_mode = 0
					brush_button.button_group = brush_shape_button_group
					brush_button.custom_minimum_size = Vector2(36,36)
					brush_button.size_flags_vertical = SIZE_SHRINK_CENTER
					brush_button.expand_icon = true
					brush_button.icon = texture
					brush_button.material = BRUSH_PREVIEW_MATERIAL

					if is_first:
						brush_button.call_deferred("set_pressed", true)
						is_first = false
						
					brush_shape_list.get_type_control().add_child(brush_button)
					brush_count += 1
					
			brush_name = brush_directory.get_next()

		if brush_count == 0:
			print("No brushes found! Please check the brush folder in addons/terrain_3d/brush")

	func set_tool(toggle: bool, tool: Tool):
		
		if current_tool == tool:
			return
		
		if toggle:
			current_tool = tool

			material_layers.hide()
			mesh_layers.hide()
			
			var options: OptionButton = brush_mode_option.get_type_control()
			options.clear()

			match tool:
				Tool.HEIGHT:
					for mode in Mode.MAX:
						var mode_name = Mode.keys()[mode]
						if mode_name.begins_with("HEIGHT_"):
							mode_name = mode_name.trim_prefix("HEIGHT_")
							options.add_item(mode_name.to_pascal_case(), mode)
							
					set_mode(options.get_item_index(Mode.HEIGHT_ADD))
					
				Tool.TEXTURE:
					material_layers.show()
					for mode in Mode.MAX:
						var mode_name = Mode.keys()[mode]
						if mode_name.begins_with("TEXTURE_"):
							mode_name = mode_name.trim_prefix("TEXTURE_")
							options.add_item(mode_name.to_pascal_case(), mode)
							
					set_mode(options.get_item_index(Mode.TEXTURE_REPLACE))
							
				Tool.detail:
					mesh_layers.show()
					
				
	func set_mode(index: int):
		
		var mode: Mode = brush_mode_option.get_type_control().get_item_id(index)

		current_mode = mode

		brush_opacity_slider.get_label().set_text("Opacity")
		brush_opacity_slider.show()
		brush_flow_slider.show()
		
		match mode:
			Mode.HEIGHT_ADD:
				pass
			Mode.HEIGHT_SUBTRACT:
				pass
			Mode.HEIGHT_MULTIPLY:
				pass
			Mode.HEIGHT_LEVEL:
				brush_opacity_slider.get_label().set_text("Height")
			Mode.TEXTURE_REPLACE:
				brush_flow_slider.hide()
				brush_opacity_slider.hide()
			Mode.TEXTURE_BLEND:
				brush_opacity_slider.get_label().set_text("Blend")
		
		
	func get_mode():
		return brush_mode_option.get_type_control().get_selected()
				
	func set_brush_size(value):
		brush_size_slider.get_type_control().set_value(value)
		
	func set_brush_opacity(value):
		brush_opacity_slider.get_type_control().set_value(value)
		
	func set_brush_flow(value):
		brush_flow_slider.get_type_control().set_value(value)
		
	func get_brush_size():
		return brush_size_slider.get_type_control().get_value()
		
	func get_brush_opacity():
		return brush_opacity_slider.get_type_control().get_value() / 100.0
	
	func get_brush_flow():
		return pow(brush_flow_slider.get_type_control().get_value() / 100.0, 2.2)
		
	func get_brush_shape():
		return brush_shape_button_group.get_pressed_button().get_button_icon().get_image()
		
	func get_material_layer():
		return current_material_layer
		
	func _on_brush_shape_changed(brush_shape: Button):
		var img: Image = brush_shape.get_button_icon().get_image()
		var texture: ImageTexture = GIZMO_MATERIAL.get_shader_parameter("brush_shape")
		texture.set_image(img)
		
	func _on_material_layer_selected(id: int):
		for layer in material_layers.get_list().get_children():
			if layer.id != id:
				layer.set_selected(false)
		current_material_layer = id
		
	func load_materials(data: Array[TerrainLayerMaterial3D], callback: Callable):
		
		material_layers.clear()
		
		var layer_count: int = 0
		
		if !data.is_empty():
			layer_count = data.size()
			
			for i in layer_count:
				var layer: MaterialLayerContainer = MaterialLayerContainer.new(i)
				var mat: TerrainLayerMaterial3D = data[i]

				layer.set_layer_data(mat)
				layer.set_selected(i == current_material_layer)
		
				layer.connect("selected", _on_material_layer_selected)
				layer.connect("changed", callback)

				material_layers.add_layer(layer)

		if layer_count < TerrainMaterial3D.LAYERS_MAX or layer_count == 0:
			var empty_layer: MaterialLayerContainer = MaterialLayerContainer.new(layer_count)
			empty_layer.connect("selected", _on_material_layer_selected)
			empty_layer.connect("changed", callback)
			material_layers.add_layer(empty_layer)
			
	func load_meshes(data: Array[Array], callback: Callable):
		
		mesh_layers.clear()
		
		var layer_count: int = 0
		var max_layers: int = 10
		
		if !data.is_empty():
			layer_count = data[0].size()
			for i in layer_count:
				var layer: MeshLayerContainer = MeshLayerContainer.new(i, max_layers)
				var mesh: Mesh = data[0][i]
				
				layer.set_layer_data(mesh, data[1][i])
				layer.connect("changed", callback)
				
				mesh_layers.add_layer(layer)

		var empty_layer: MeshLayerContainer = MeshLayerContainer.new(layer_count, max_layers)
		empty_layer.connect("changed", callback)
		mesh_layers.add_layer(empty_layer)
		
class MaterialLayerContainer extends HBoxContainer:
	
	signal selected(id: int)
	signal changed(layer_material: TerrainLayerMaterial3D, id: int, inspect: bool)
	
	var is_selected: bool = false
	
	var material_picker: EditorResourcePicker
	
	var id: int
	
	func _init(layer: int):
		id = layer
		material_picker = EditorResourcePicker.new()
		material_picker.set_base_type("TerrainLayerMaterial3D")
		material_picker.connect("resource_changed", _on_changed)
		material_picker.connect("resource_selected", _on_selected)
		
		var label = Label.new()
	
		label.text = "Layer "+str(id+1)
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		label.size_flags_vertical = SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		material_picker.size_flags_horizontal = SIZE_EXPAND_FILL
		size_flags_horizontal = SIZE_EXPAND_FILL
		
		add_child(label)
		add_child(material_picker)

		queue_redraw()
		
	func _notification(what):
		if what == NOTIFICATION_DRAW:
			if is_selected:
				var stylebox = get_theme_stylebox("bg_selected", "EditorProperty")
				draw_style_box(stylebox, Rect2(Vector2.ZERO, get_size()))
				
	func _gui_input(event):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				emit_signal("selected", id)
				set_selected(true)
	
	func _on_changed(layer_material: Variant):
		# If texture is cleared, Object#null is passed
		# which causes an error "Can't convert Object to Object
		if layer_material == null:
			layer_material = null
		emit_signal("changed", layer_material, id, false)
		
	func _on_selected(layer_material: Variant, inspect: bool):
		emit_signal("changed", layer_material, id, true)
		
	func set_layer_data(layer_material: TerrainLayerMaterial3D):
		material_picker.set_edited_resource(layer_material)
		
	func set_selected(select: bool):
		is_selected = select
		queue_redraw()

class MeshLayerContainer extends HBoxContainer:
	
	signal changed(mesh: Mesh, layer: int, id: int)
	
	var mesh_picker: EditorResourcePicker
	var layer_list: OptionButton
	
	var id: int
	
	func _init(layer: int, max_layers: int):
		id = layer
		mesh_picker = EditorResourcePicker.new()
		mesh_picker.set_base_type("Mesh")
		mesh_picker.connect("resource_changed", _on_mesh_changed)
		mesh_picker.connect("resource_selected", _on_selected)
		
		layer_list = OptionButton.new()
		
		for i in max_layers:
			layer_list.add_item("Layer " + str(i+1))
		
		layer_list.connect("item_selected", _on_layer_changed)
	
		layer_list.size_flags_horizontal = SIZE_EXPAND_FILL
		mesh_picker.size_flags_horizontal = SIZE_EXPAND_FILL
		size_flags_horizontal = SIZE_EXPAND_FILL
		
		add_child(layer_list)
		add_child(mesh_picker)
	
	func _on_mesh_changed(mesh: Variant):
		if mesh == null:
			mesh = null
		var layer = max(0, layer_list.get_selected())
		emit_signal("changed", mesh, layer, id)
		
	func _on_layer_changed(layer: int):
		var mesh: Variant = mesh_picker.get_edited_resource()
		if mesh == null:
			mesh = null
		emit_signal("changed", mesh, layer, id)
		
	func _on_selected(mesh: Variant, inspect: bool):
		var layer = max(0, layer_list.get_selected())
		emit_signal("changed", mesh, layer, id, true)
		
	func set_layer_data(mesh: Mesh, layer: int):
		mesh_picker.set_edited_resource(mesh)
		layer_list._select_int(layer)
		
class BrushToolControl extends HBoxContainer:
	
	enum Type {
		SLIDER,
		OPTION,
		BUTTON_GRID,
	}
	
	var type: Type
	var suffix: String
	
	func _init(control_type: Type, tool_name: String, value_suffix: String = "", max: float = 100.0):
		
		type = control_type
		suffix = value_suffix
		
		var label: Label = Label.new()
		label.custom_minimum_size.x = 64
		label.text = tool_name
		add_child(label)
		
		match type:
			Type.SLIDER:
				var slider = HSlider.new()
				slider.max_value = max
				slider.step = 1.0
				slider.size_flags_horizontal = SIZE_EXPAND_FILL
				slider.size_flags_vertical = SIZE_SHRINK_CENTER
				slider.connect("value_changed", _on_changed)
				add_child(slider)
				var value: Label = Label.new()
				value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				value.custom_minimum_size.x = 48
				value.clip_text = true
				value.text = str(0)
				add_child(value)
			Type.OPTION:
				var option_button: OptionButton = OptionButton.new()
				option_button.size_flags_horizontal = SIZE_EXPAND_FILL
				option_button.connect("item_selected", _on_changed)
				add_child(option_button)
			Type.BUTTON_GRID:
				var container: HFlowContainer = HFlowContainer.new()
				container.size_flags_horizontal = SIZE_EXPAND_FILL
				container.size_flags_vertical = SIZE_SHRINK_CENTER
				add_child(container)
		
	func _on_changed(variant: Variant):
		
		if type == Type.SLIDER:
			get_child(2).set_text(str(variant)+suffix)
	
	func get_type_control() -> Control:
		return get_child(1)
		
	func get_label() -> Label:
		return get_child(0)
		
class LayerListContainer extends PanelContainer:
	
	var list: VBoxContainer
	var label: Label
	
	func _init(list_name: String):
		
		var vbox: VBoxContainer = VBoxContainer.new()
		add_child(vbox)
		label = Label.new()
		vbox.add_child(label)
		var scroll: ScrollContainer = ScrollContainer.new()
		vbox.add_child(scroll)
		list = VBoxContainer.new()
		scroll.add_child(list)
		
		vbox.size_flags_vertical = SIZE_FILL
		label.text = list_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		list.size_flags_horizontal = SIZE_EXPAND_FILL
		list.size_flags_vertical = SIZE_EXPAND_FILL
		
		size_flags_vertical = SIZE_EXPAND_FILL
		
		call_deferred("load_editor_theme")
		
	func add_layer(layer: HBoxContainer):
		list.add_child(layer)
		
	func clear():
		for i in list.get_children():
			i.queue_free()
	
	func load_editor_theme():
		label.set("theme_override_styles/normal", get_theme_stylebox("bg", "EditorInspectorCategory"))
		label.set("theme_override_fonts/font", get_theme_font("bold", "EditorFonts"))
		label.set("theme_override_font_sizes/font_size",get_theme_font_size("bold_size", "EditorFonts"))
		set("theme_override_styles/panel", get_theme_stylebox("panel", "Panel"))
	
	func get_list():
		return list
		
		
