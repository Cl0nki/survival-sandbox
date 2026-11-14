shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform sampler2D stain_map : filter_linear, repeat_disable;
uniform sampler2D soil_map : filter_linear, repeat_disable;
uniform vec2 uv_world_size = vec2(40.0, 40.0);
uniform vec3 world_origin = vec3(0.0, 0.0, 0.0);
uniform float detail_meters = 2.0;
uniform float blend_sharpness = 8.0;

uniform sampler2D albedo_r : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_r : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_r : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_g : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_g : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_g : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_g : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_g : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_b : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_b : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_b : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_b : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_a : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_a : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_a : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_a : hint_default_black, filter_linear_mipmap, repeat_enable;

// Fluid stains: R water, G gas, B oil.
uniform sampler2D albedo_water : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_water : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_water : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_water : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_water : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_gas : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_gas : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_gas : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_gas : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_gas : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_oil : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_oil : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_oil : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_oil : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_oil : hint_default_black, filter_linear_mipmap, repeat_enable;

// Soil patches: R sand, G clay, B gravel.
uniform sampler2D albedo_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_sand : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_sand : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_sand : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_sand : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_clay : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_clay : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_clay : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_clay : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_clay : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_gravel : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_gravel : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_gravel : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_gravel : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_gravel : hint_default_black, filter_linear_mipmap, repeat_enable;

// Scrap-yard asphalt overlay (asphalt_map.r).
uniform sampler2D asphalt_map : filter_linear, repeat_disable;
uniform sampler2D albedo_asphalt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_asphalt : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_asphalt : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_asphalt : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_asphalt : hint_default_black, filter_linear_mipmap, repeat_enable;

// Forest floors: R oak, G birch, B spruce.
uniform sampler2D forest_map : filter_linear, repeat_disable;
uniform sampler2D albedo_oak : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_oak : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_oak : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_oak : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_oak : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_birch : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_birch : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_birch : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_birch : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_birch : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform sampler2D albedo_spruce : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_spruce : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_spruce : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_spruce : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_spruce : hint_default_black, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec4 height_blend(vec4 splat, vec4 heights, float sharpness) {
	float max_h = max(
		max(splat.r + heights.r, splat.g + heights.g),
		max(splat.b + heights.b, splat.a + heights.a)
	);
	vec4 w = max(splat + heights - vec4(max_h) + vec4(1.0 / sharpness), vec4(0.0));
	float wsum = w.r + w.g + w.b + w.a;
	return w / max(wsum, 1e-4);
}

void mix_rgb_overlay(
	inout vec3 albedo,
	inout vec3 n_blend,
	inout float rough,
	inout float ao,
	vec3 mask,
	float sharpness,
	vec2 detail_uv,
	sampler2D albedo_x,
	sampler2D normal_x,
	sampler2D rough_x,
	sampler2D ao_x,
	sampler2D height_x,
	sampler2D albedo_y,
	sampler2D normal_y,
	sampler2D rough_y,
	sampler2D ao_y,
	sampler2D height_y,
	sampler2D albedo_z,
	sampler2D normal_z,
	sampler2D rough_z,
	sampler2D ao_z,
	sampler2D height_z
) {
	float cover = clamp(mask.r + mask.g + mask.b, 0.0, 1.0);
	if (cover <= 1e-4) {
		return;
	}
	vec3 heights = vec3(
		texture(height_x, detail_uv).r,
		texture(height_y, detail_uv).r,
		texture(height_z, detail_uv).r
	);
	float max_h = max(max(mask.r + heights.r, mask.g + heights.g), mask.b + heights.b);
	vec3 ow = max(mask + heights - vec3(max_h) + vec3(1.0 / sharpness), vec3(0.0));
	ow /= max(ow.x + ow.y + ow.z, 1e-4);

	vec3 o_albedo =
		texture(albedo_x, detail_uv).rgb * ow.x
		+ texture(albedo_y, detail_uv).rgb * ow.y
		+ texture(albedo_z, detail_uv).rgb * ow.z;
	vec3 n_x = texture(normal_x, detail_uv).xyz * 2.0 - 1.0;
	vec3 n_y = texture(normal_y, detail_uv).xyz * 2.0 - 1.0;
	vec3 n_z = texture(normal_z, detail_uv).xyz * 2.0 - 1.0;
	vec3 o_n = normalize(n_x * ow.x + n_y * ow.y + n_z * ow.z);
	float o_rough =
		texture(rough_x, detail_uv).r * ow.x
		+ texture(rough_y, detail_uv).r * ow.y
		+ texture(rough_z, detail_uv).r * ow.z;
	float o_ao =
		texture(ao_x, detail_uv).r * ow.x
		+ texture(ao_y, detail_uv).r * ow.y
		+ texture(ao_z, detail_uv).r * ow.z;

	albedo = mix(albedo, o_albedo, cover);
	n_blend = normalize(mix(n_blend, o_n, cover));
	rough = mix(rough, o_rough, cover);
	ao = mix(ao, o_ao, cover);
}

void fragment() {
	vec2 splat_uv = (world_pos.xz - world_origin.xz) / uv_world_size + vec2(0.5);
	vec2 detail_uv = world_pos.xz / max(detail_meters, 0.001);
	float sharpness = max(blend_sharpness, 0.001);

	vec4 splat = texture(splat_map, splat_uv);
	vec4 base_h = vec4(
		texture(height_r, detail_uv).r,
		texture(height_g, detail_uv).r,
		texture(height_b, detail_uv).r,
		texture(height_a, detail_uv).r
	);
	vec4 w = height_blend(splat, base_h, sharpness);

	vec3 albedo =
		texture(albedo_r, detail_uv).rgb * w.r
		+ texture(albedo_g, detail_uv).rgb * w.g
		+ texture(albedo_b, detail_uv).rgb * w.b
		+ texture(albedo_a, detail_uv).rgb * w.a;

	vec3 n_r = texture(normal_r, detail_uv).xyz * 2.0 - 1.0;
	vec3 n_g = texture(normal_g, detail_uv).xyz * 2.0 - 1.0;
	vec3 n_b = texture(normal_b, detail_uv).xyz * 2.0 - 1.0;
	vec3 n_a = texture(normal_a, detail_uv).xyz * 2.0 - 1.0;
	vec3 n_blend = normalize(n_r * w.r + n_g * w.g + n_b * w.b + n_a * w.a);

	float rough =
		texture(rough_r, detail_uv).r * w.r
		+ texture(rough_g, detail_uv).r * w.g
		+ texture(rough_b, detail_uv).r * w.b
		+ texture(rough_a, detail_uv).r * w.a;

	float ao =
		texture(ao_r, detail_uv).r * w.r
		+ texture(ao_g, detail_uv).r * w.g
		+ texture(ao_b, detail_uv).r * w.b
		+ texture(ao_a, detail_uv).r * w.a;

	mix_rgb_overlay(
		albedo, n_blend, rough, ao,
		texture(soil_map, splat_uv).rgb, sharpness, detail_uv,
		albedo_sand, normal_sand, rough_sand, ao_sand, height_sand,
		albedo_clay, normal_clay, rough_clay, ao_clay, height_clay,
		albedo_gravel, normal_gravel, rough_gravel, ao_gravel, height_gravel
	);
	mix_rgb_overlay(
		albedo, n_blend, rough, ao,
		texture(stain_map, splat_uv).rgb, sharpness, detail_uv,
		albedo_water, normal_water, rough_water, ao_water, height_water,
		albedo_gas, normal_gas, rough_gas, ao_gas, height_gas,
		albedo_oil, normal_oil, rough_oil, ao_oil, height_oil
	);
	mix_rgb_overlay(
		albedo, n_blend, rough, ao,
		texture(forest_map, splat_uv).rgb, sharpness, detail_uv,
		albedo_oak, normal_oak, rough_oak, ao_oak, height_oak,
		albedo_birch, normal_birch, rough_birch, ao_birch, height_birch,
		albedo_spruce, normal_spruce, rough_spruce, ao_spruce, height_spruce
	);

	float asphalt_cover = clamp(texture(asphalt_map, splat_uv).r, 0.0, 1.0);
	if (asphalt_cover > 1e-4) {
		vec3 a_albedo = texture(albedo_asphalt, detail_uv).rgb;
		vec3 a_n = texture(normal_asphalt, detail_uv).xyz * 2.0 - 1.0;
		float a_rough = texture(rough_asphalt, detail_uv).r;
		float a_ao = texture(ao_asphalt, detail_uv).r;
		albedo = mix(albedo, a_albedo, asphalt_cover);
		n_blend = normalize(mix(n_blend, a_n, asphalt_cover));
		rough = mix(rough, a_rough, asphalt_cover);
		ao = mix(ao, a_ao, asphalt_cover);
	}

	NORMAL_MAP = n_blend * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = 0.0;
	AO = ao;
}
