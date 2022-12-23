@tool
extends VBoxContainer

signal texture_changed(texture: Texture2D, index: int, is_albedo: bool)

enum ToolMode {
	HEIGHT,
	SPLAT,
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
@onready var tool_paint_splat = get_node("Buttons/ToolSplat")

@onready var texture_layers_normals = get_node("TextureLayersNormals/Show")
@onready var texture_layers_details = get_node("TextureLayersDetails/Show")
@onready var texture_layers_control = get_node("TextureLayers/Layers")

func _ready():
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
	tool_paint_splat.connect("toggled", set_tool_mode.bind(ToolMode.SPLAT))
	tool_paint_height.set_pressed(true)
	set_tool_mode(true, ToolMode.HEIGHT)
	
	texture_layers_normals.connect("toggled", toggle_normalmap_picker)
	
	brush_shape_button_group = brush_shape_list.get_child(0).get_button_group()
	
func set_tool_mode(toggle: bool, mode: ToolMode):
	if toggle:
		tool_mode = mode
	
	texture_layers_control.hide()
	brush_height_control.hide()
	texture_layers_normals.set_disabled(true)
	texture_layers_details.set_disabled(true)
	
	match mode:
		ToolMode.HEIGHT:
			brush_height_control.show()
		ToolMode.SPLAT:
			texture_layers_control.show()
			texture_layers_normals.set_disabled(false)
			texture_layers_details.set_disabled(false)

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
	
func toggle_normalmap_picker(toggle: bool):
	for control in texture_layers_control.get_children():
		if control.get_child_count() > 0:
			control.get_child(2).visible = toggle

func on_texture_selected(toggle: bool, idx: int):
	for i in texture_layer_buttons.size():
		if i != idx:
			texture_layer_buttons[i].set_pressed_no_signal(false)
	texture_layer = idx + 1
	
func on_albedo_changed(tex: Texture2D, idx: int):
	emit_signal("texture_changed", tex, idx, true)
	
func on_normalmap_changed(tex: Texture2D, idx: int):
	emit_signal("texture_changed", tex, idx, false)

func load_textures(albedo_arr: Array, normal_arr: Array):
	
	var has_texture_layers: bool = texture_layers_control.get_child_count() > 0
	
	for i in 16:
		
		var albedo_picker: EditorResourcePicker
		var normal_picker: EditorResourcePicker
		
		if !has_texture_layers:
			var hbox: HBoxContainer = HBoxContainer.new()
			
			albedo_picker = EditorResourcePicker.new()
			albedo_picker.connect("resource_changed", on_albedo_changed.bind(i))
			albedo_picker.set_toggle_mode(true)
			var texture_button: Button = albedo_picker.get_child(0)
			texture_layer_buttons.append(texture_button)
			texture_button.connect("toggled", on_texture_selected.bind(i))
			
			normal_picker = EditorResourcePicker.new()
			normal_picker.connect("resource_changed", on_normalmap_changed.bind(i))
			normal_picker.hide()
			var label: Label = Label.new()
			label.set_text("Layer "+ str(i+1))
			
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			albedo_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			normal_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			hbox.add_child(label)
			hbox.add_child(albedo_picker)
			hbox.add_child(normal_picker)
			
			texture_layers_control.add_child(hbox)
			
		if has_texture_layers:
			albedo_picker = texture_layers_control.get_child(i).get_child(1)
			normal_picker = texture_layers_control.get_child(i).get_child(2)
		
		albedo_picker.set_edited_resource(albedo_arr[i])
		normal_picker.set_edited_resource(normal_arr[i])
