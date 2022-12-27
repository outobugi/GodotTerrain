@tool
class_name TerrainTextureArray
extends Texture2DArray

const MAX_TEXTURE_SLOTS: int = 16

@export var texture_array: Array[Texture2D] :
	set(arr):
		texture_array = arr
		update()

func set_texture(texture: Texture2D, index: int):
	if index >= texture_array.size():
		texture_array.append(texture)
	else:
		texture_array[index] = texture
	update()
	
func get_array():
	return texture_array
	
func update():
	
	var img_arr: Array[Image]
	for tex in texture_array:
		if tex != null:
			var img: Image = tex.get_image()
			
			if img.is_compressed():
				img.decompress()
			
			img.generate_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
				
			img_arr.push_back(img)
	
	if !img_arr.is_empty():
		create_from_images(img_arr)
		
	notify_property_list_changed()

static func convert_array(arr: Array) -> Texture2DArray:
	var img_arr: Array[Image]
	for tex in arr:
		if tex != null and tex is Texture2D:
			var img: Image = tex.get_image()
			
			if img.is_compressed():
				img.decompress()
			
			img.generate_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
				
			img_arr.push_back(img)
	var tex_arr = Texture2DArray.new()
	if !img_arr.is_empty():
		tex_arr.create_from_images(img_arr)
	return tex_arr
