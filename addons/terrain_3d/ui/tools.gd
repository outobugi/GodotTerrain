@tool
extends VBoxContainer

# A mess that it called UI code.
# Needs renaming and refactoring

const BRUSH_PREVIEW_MATERIAL: ShaderMaterial = preload("res://addons/terrain_3d/ui/brush_preview.material")

enum ToolMode {
	HEIGHT,
	TEXTURE,
	PARTICLE
}

const MAX_BRUSH_SIZE: int = 512

var tool_mode: ToolMode = ToolMode.HEIGHT

var brush_size: int = 64
var brush_opacity: float = 0.1
var brush_height: float = 1.0
var material_layer: int = 0

var editor_interface: EditorInterface

@onready var brush_height_control = get_node("BrushHeight")
@onready var brush_size_slider = get_node("BrushSize/Slider")
@onready var brush_opacity_name = get_node("BrushOpacity/Label")
@onready var brush_opacity_slider = get_node("BrushOpacity/Slider")
@onready var brush_height_slider = brush_height_control.get_node("Slider")
@onready var brush_size_value = get_node("BrushSize/Value")
@onready var brush_opacity_value = get_node("BrushOpacity/Value")
@onready var brush_height_value = brush_height_control.get_node("Value")

@onready var brush_shape_button_group: ButtonGroup = preload("res://addons/terrain_3d/ui/shape_group.tres")

@onready var brush_shape_list = get_node("BrushShape/GridContainer")

@onready var tool_paint_height = get_node("Buttons/ToolHeight")
@onready var tool_paint_texture = get_node("Buttons/ToolTexture")
@onready var tool_paint_multimesh = get_node("Buttons/ToolMultiMesh")

@onready var material_layers_control = get_node("MaterialLayers")
@onready var material_layers_list = material_layers_control.get_node("VBox/Container/Layers")

@onready var mesh_layers_control = get_node("MeshLayers")
@onready var mesh_layers_list = mesh_layers_control.get_node("VBox/Container/Layers")

@onready var category_labels: Array = [
	$MaterialLayers/VBox/Label,
	$MeshLayers/VBox/Label
]

func init_toolbar():
	brush_size_slider.connect("value_changed", brush_size_changed)
	brush_opacity_slider.connect("value_changed", brush_opacity_changed)
	brush_height_slider.connect("value_changed", brush_height_changed)
	
	brush_size_slider.set_max(MAX_BRUSH_SIZE)
	brush_opacity_slider.set_max(1)
	brush_height_slider.set_max(1)
	brush_size_slider.set_step(1)
	brush_opacity_slider.set_step(0.01)
	brush_height_slider.set_step(0.01)
	
	set_brush_size(brush_size)
	set_brush_opacity(brush_opacity)
	set_brush_height(brush_height)
	
	tool_paint_height.connect("toggled", set_tool_mode.bind(ToolMode.HEIGHT))
	tool_paint_texture.connect("toggled", set_tool_mode.bind(ToolMode.TEXTURE))
	tool_paint_multimesh.connect("toggled", set_tool_mode.bind(ToolMode.PARTICLE))
	tool_paint_height.set_pressed(true)
	set_tool_mode(true, ToolMode.HEIGHT)
	
	load_brushes()

	# Set up theme
	
	for label in category_labels:
		label.set("theme_override_styles/normal", get_theme_stylebox("bg", "EditorInspectorCategory"))
		label.set("theme_override_fonts/font", get_theme_font("bold", "EditorFonts"))
		label.set("theme_override_font_sizes/font_size",get_theme_font_size("bold_size", "EditorFonts"))
	
	mesh_layers_control.set("theme_override_styles/panel", get_theme_stylebox("panel", "Panel"))
	material_layers_control.set("theme_override_styles/panel", get_theme_stylebox("panel", "Panel"))

func load_brushes():
	var path: String = "res://addons/terrain_3d/brush/"
	var brush_directory: DirAccess = DirAccess.open(path)
	var is_first: bool = true
	
	for button in brush_shape_list.get_children():
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
				brush_button.custom_minimum_size = Vector2(33,33)
				brush_button.size_flags_vertical = SIZE_SHRINK_CENTER
				brush_button.expand_icon = true
				brush_button.icon = texture
				brush_button.material = BRUSH_PREVIEW_MATERIAL

				if is_first:
					brush_button.call_deferred("set_pressed", true)
					is_first = false
				brush_shape_list.add_child(brush_button)
				
				brush_count += 1
		brush_name = brush_directory.get_next()

	if brush_count == 0:
		print("No brushes found! Please check the brush folder in addons/terrain_3d/brush")

func set_tool_mode(toggle: bool, mode: ToolMode):
	if toggle:
		tool_mode = mode
	
	material_layers_control.hide()
	brush_height_control.hide()
	mesh_layers_control.hide()

	match mode:
		ToolMode.HEIGHT:
			brush_height_control.show()
			brush_opacity_name.set_text("Opacity")
		ToolMode.TEXTURE:
			material_layers_control.show()
			brush_opacity_name.set_text("Hardness")
		ToolMode.PARTICLE:
			mesh_layers_control.show()
			
func set_brush_size(value):
	brush_size_slider.set_value(value)
	
func set_brush_opacity(value):
	brush_opacity_slider.set_value(value)
	
func set_brush_height(value):
	brush_height_slider.set_value(value)

func get_brush_size():
	return brush_size_slider.get_value()
	
func get_brush_opacity():
	return brush_opacity_slider.get_value()
	
func get_brush_shape():
	return brush_shape_button_group.get_pressed_button().get_button_icon().get_image()
	
func get_brush_height():
	return brush_height_slider.get_value()
	
func get_material_layer():
	return material_layer

func brush_size_changed(new_value):
	brush_size = new_value
	brush_size_value.set_text(str(new_value))
	
func brush_opacity_changed(new_value):
	brush_opacity = new_value
	brush_opacity_value.set_text(str(new_value))
	
func brush_height_changed(new_value):
	brush_height = new_value
	brush_height_value.set_text(str(new_value))
	
func _on_resource_inspected(resource: Resource):
	editor_interface.inspect_object(resource, "", true)
	
func _on_material_layer_selected(id: int):
	for layer in material_layers_list.get_children():
		if layer.id != id:
			layer.set_selected(false)
	material_layer = id
	
func clear_layers():
	for node in material_layers_list.get_children():
		if node is MaterialLayerContainer:
			node.queue_free()
			
func clear_meshes():
	for node in mesh_layers_list.get_children():
		if node is MeshLayerContainer:
			node.queue_free()
	
func load_layers(data: Array[TerrainLayerMaterial3D], callback: Callable):
	
	clear_layers()
	
	var layer_count: int = 0
	
	if !data.is_empty():
		layer_count = data.size()
		
		for i in layer_count:
			var layer: MaterialLayerContainer = MaterialLayerContainer.new(i)
			var mat: TerrainLayerMaterial3D = data[i]

			layer.set_layer_data(mat)
			layer.set_selected(i == material_layer)
			
			layer.connect("inspected", _on_resource_inspected)
			layer.connect("selected", _on_material_layer_selected)
			layer.connect("changed", callback)

			material_layers_list.add_child(layer)

	if layer_count < TerrainMaterial3D.LAYERS_MAX or layer_count == 0:
		var empty_layer: MaterialLayerContainer = MaterialLayerContainer.new(layer_count)
		empty_layer.connect("selected", _on_material_layer_selected)
		empty_layer.connect("changed", callback)
		material_layers_list.add_child(empty_layer)
		
func load_meshes(data: Array[Array], callback: Callable):
	clear_meshes()
	
	var layer_count: int = 0
	
	if !data.is_empty():
		layer_count = data[0].size()
		for i in layer_count:
			var layer: MeshLayerContainer = MeshLayerContainer.new(i)
			var mesh: Mesh = data[0][i]
			
			layer.set_layer_data(mesh, data[1][i])
			layer.connect("inspected", _on_resource_inspected)
			layer.connect("changed", callback)
			
			mesh_layers_list.add_child(layer)

	var empty_layer: MeshLayerContainer = MeshLayerContainer.new(layer_count)
	empty_layer.connect("changed", callback)
	mesh_layers_list.add_child(empty_layer)
		
class MaterialLayerContainer extends HBoxContainer:
	
	signal selected(id: int)
	signal changed(layer_material: TerrainLayerMaterial3D, id: int)
	signal inspected(layer_material: TerrainLayerMaterial3D)
	
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
		emit_signal("changed", layer_material, id)
		
	func _on_selected(layer_material: Variant, inspect: bool):
		if inspect:
			emit_signal("inspected", layer_material)
		
	func set_layer_data(layer_material: TerrainLayerMaterial3D):
		material_picker.set_edited_resource(layer_material)
		
	func set_selected(select: bool):
		is_selected = select
		queue_redraw()

class MeshLayerContainer extends HBoxContainer:
	
	signal changed(mesh: Mesh, layer: int, id: int)
	signal inspected(mesh: Mesh)
	
	var mesh_picker: EditorResourcePicker
	var layer_list: OptionButton
	
	var id: int
	
	func _init(layer: int):
		id = layer
		mesh_picker = EditorResourcePicker.new()
		mesh_picker.set_base_type("Mesh")
		mesh_picker.connect("resource_changed", _on_mesh_changed)
		mesh_picker.connect("resource_selected", _on_selected)
		
		layer_list = OptionButton.new()
		
		for i in TerrainMaterial3D.LAYERS_MAX:
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
		if inspect:
			emit_signal("inspected", mesh)
		
	func set_layer_data(mesh: Mesh, layer: int):
		mesh_picker.set_edited_resource(mesh)
		layer_list._select_int(layer)
		
