// NOTE: Shader automatically converted from Godot Engine 4.0.beta11's StandardMaterial3D.

shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_disabled,diffuse_burley,specular_schlick_ggx;
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color,filter_linear_mipmap,repeat_enable;
uniform float point_size : hint_range(0,128);
uniform float roughness : hint_range(0,1);
uniform sampler2D texture_metallic : hint_default_white,filter_linear_mipmap,repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r,filter_linear_mipmap,repeat_enable;
uniform float specular;
uniform float metallic;
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

uniform int instance_count = 402;
uniform int instance_density = 2;

float random(vec2 xy){
	return fract(tan(distance(xy*PI, xy))*xy.x);
}

void vertex() {
	
	bool is_shadow_pass = VIEWPORT_SIZE.y <= 1.0;
	
	float count_sqrt = sqrt(float(instance_count));
	float spacing = float(instance_density) / 2.0;
	
	vec3 pos = vec3(0.0, 0.0, 0.0);
	pos.z = float(INSTANCE_ID / int(count_sqrt));
	pos.x = float(INSTANCE_ID % int(count_sqrt));

	pos.x -= count_sqrt * 0.5;
	pos.z -= count_sqrt * 0.5;
	pos *= spacing;
	
	vec3 offset = CAMERA_POSITION_WORLD;
	
	pos.x += offset[0] - mod(offset[0], spacing);
	pos.z += offset[2] - mod(offset[2], spacing);
	
	
	float rand_offset = random(pos.xz);
	
	VERTEX.x += pos.x + rand_offset;
	VERTEX.z += pos.z + rand_offset;
	
}

