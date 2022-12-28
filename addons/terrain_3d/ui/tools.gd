@tool
extends VBoxContainer

# A lot of duplicate code and bad naming and no comments

enum ToolMode {
	HEIGHT,
	TEXTURE,
	PARTICLE
}

const MAX_BRUSH_SIZE: int = 512

var tool_mode: ToolMode = ToolMode.HEIGHT
var brush_size: int = 64
var brush_opacity: float = 0.1
var brush_shape_button_group: ButtonGroup
var brush_height: float = 1.0
var texture_layer: int = 1
var texture_layer_buttons: Array[Button]

@onready var brush_height_control = get_node("BrushHeight")

@onready var brush_size_slider = get_node("BrushSize/Slider")
@onready var brush_opacity_slider = get_node("BrushOpacity/Slider")
@onready var brush_height_slider = brush_height_control.get_node("Slider")
@onready var brush_size_value = get_node("BrushSize/Value")
@onready var brush_opacity_value = get_node("BrushOpacity/Value")
@onready var brush_height_value = brush_height_control.get_node("Value")

@onready var brush_shape_list = get_node("BrushShape/GridContainer")

@onready var tool_paint_height = get_node("Buttons/ToolHeight")
@onready var tool_paint_texture = get_node("Buttons/ToolTexture")
@onready var tool_paint_multimesh = get_node("Buttons/ToolMultiMesh")

@onready var texture_layers_control = get_node("TextureLayers")
@onready var texture_layers_list = texture_layers_control.get_node("LayersContainer/Layers")
@onready var texture_layer_error = texture_layers_control.get_node("LayerError")

@onready var mesh_layers_control = get_node("MeshLayers")
@onready var mesh_layers_list = mesh_layers_control.get_node("LayersContainer/Layers")

func init_tools():
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
	
	brush_shape_button_group = brush_shape_list.get_child(0).get_button_group()
	
func set_tool_mode(toggle: bool, mode: ToolMode):
	if toggle:
		tool_mode = mode
	
	texture_layers_control.hide()
	brush_height_control.hide()
	mesh_layers_control.hide()

	match mode:
		ToolMode.HEIGHT:
			brush_height_control.show()
		ToolMode.TEXTURE:
			texture_layers_control.show()
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
	
func get_texture_layer():
	return texture_layer

func brush_size_changed(new_value):
	brush_size = new_value
	brush_size_value.set_text(str(new_value))
	
func brush_opacity_changed(new_value):
	brush_opacity = new_value
	brush_opacity_value.set_text(str(new_value))
	
func brush_height_changed(new_value):
	brush_height = new_value
	brush_height_value.set_text(str(new_value))
	
func _on_texture_selected(id: int):
	for layer in texture_layers_list.get_children():
		if layer.id != id:
			layer.set_selected(false)
	texture_layer = id + 1
	
func clear_texture_layers():
	for node in texture_layers_list.get_children():
		if node is TextureLayerContainer:
			node.queue_free()
			
func clear_mesh_layers():
	for node in mesh_layers_list.get_children():
		if node is MeshLayerContainer:
			node.queue_free()
	
func load_textures(data: Array, callback: Callable):
	clear_texture_layers()

	var show_next_empty: bool = false
	var layer_count: int = 0
	
	if !data.is_empty():
		var albedo_arr: Array = data[0]
		var normal_arr: Array = data[1]
		
		layer_count = albedo_arr.size()
		
		for i in layer_count:
			var layer: TextureLayerContainer = TextureLayerContainer.new(i)
			var albedo: Texture2D = albedo_arr[i]
			var normal: Texture2D = null
			
			if i < normal_arr.size():
				normal = normal_arr[i]
			
			show_next_empty = normal != null
			
			layer.set_layer_data(albedo, normal)
			layer.set_selected(i == texture_layer - 1)
			
			layer.connect("selected", _on_texture_selected)
			layer.connect("changed", callback)
			
			texture_layers_list.add_child(layer)
		
	texture_layer_error.set_visible(!show_next_empty)
		
	if layer_count < 16 and show_next_empty or layer_count == 0:
		var empty_layer: TextureLayerContainer = TextureLayerContainer.new(layer_count)
		empty_layer.connect("selected", _on_texture_selected)
		empty_layer.connect("changed", callback)
		texture_layers_list.add_child(empty_layer)
		
func load_meshes(data: Array, callback: Callable):
	clear_mesh_layers()
	
	var layer_count: int = data[0].size()
	var show_next_empty: bool = false
	
	for i in layer_count:
		var layer: MeshLayerContainer = MeshLayerContainer.new(i)
		var mesh: Mesh = data[0][i]
		
		show_next_empty = mesh != null
		
		layer.set_layer_data(mesh, data[1][i])
		layer.connect("changed", callback)
		
		mesh_layers_list.add_child(layer)
		
	if show_next_empty or layer_count == 0:
		var empty_layer: MeshLayerContainer = MeshLayerContainer.new(layer_count)
		empty_layer.connect("changed", callback)
		mesh_layers_list.add_child(empty_layer)
		
class TextureLayerContainer extends HBoxContainer:
	
	signal selected(id: int)
	signal changed(texture: Texture2D, id: int, is_albedo: bool)
	
	var is_selected: bool = false
	
	var main_button: Button
	var albedo_picker: EditorResourcePicker
	var normal_picker: EditorResourcePicker
	
	var id: int
	
	func _init(layer: int):
		id = layer
		albedo_picker = EditorResourcePicker.new()
		albedo_picker.set_base_type("Texture2D")
		albedo_picker.connect("resource_changed", _on_changed.bind(true))
		albedo_picker.set_toggle_mode(true)
		main_button = albedo_picker.get_child(0)
		
		main_button.connect("toggled", _on_selected)
		
		normal_picker = EditorResourcePicker.new()
		normal_picker.set_base_type("Texture2D")
		normal_picker.connect("resource_changed", _on_changed.bind(false))
	
		albedo_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		normal_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		add_child(albedo_picker)
		add_child(normal_picker)
		
	func _on_changed(texture: Variant, is_albedo: bool):
		# If texture is cleared, Object#null is passed
		# which causes an error "Can't convert Object to Object. 4.0 beta 10
		if texture == null:
			texture = null
		emit_signal("changed", texture, id, is_albedo)
		
	func _on_selected(toggle: bool):
		emit_signal("selected", id)
		set_selected(toggle)
		
	func set_layer_data(albedo: Texture2D, normal: Texture2D):
		albedo_picker.set_edited_resource(albedo)
		normal_picker.set_edited_resource(normal)
	
	func set_selected(select: bool):
		is_selected = select
		main_button.set_pressed_no_signal(select)
	
class MeshLayerContainer extends HBoxContainer:
	
	signal changed(mesh: Mesh, layer: int, id: int)
	
	var mesh_picker: EditorResourcePicker
	var layer_spinbox: SpinBox
	
	var id: int
	
	func _init(layer: int):
		id = layer
		mesh_picker = EditorResourcePicker.new()
		mesh_picker.set_base_type("Mesh")
		mesh_picker.connect("resource_changed", _on_mesh_changed)
		
		layer_spinbox = SpinBox.new()
		layer_spinbox.set_prefix("Layer")
		layer_spinbox.set_min(1)
		layer_spinbox.set_max(16)
		layer_spinbox.connect("value_changed", _on_layer_changed)
	
		layer_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mesh_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		add_child(layer_spinbox)
		add_child(mesh_picker)
	
	func _on_mesh_changed(mesh: Variant):
		if mesh == null:
			mesh = null
		emit_signal("changed", mesh, layer_spinbox.get_value(), id)
		
	func _on_layer_changed(layer: int):
		emit_signal("changed", mesh_picker.get_edited_resource(), layer, id)
		layer_spinbox.apply()
	
	func set_layer_data(mesh: Mesh, layer: int):
		layer_spinbox.set_value_no_signal(layer)
		mesh_picker.set_edited_resource(mesh)
		
