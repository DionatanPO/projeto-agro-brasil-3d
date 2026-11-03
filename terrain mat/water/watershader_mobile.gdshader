shader_type spatial; 
render_mode depth_draw_opaque; 

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture,repeat_disable; 
uniform vec3 surface_color:source_color;
uniform vec3 depth_color:source_color;
uniform float opacity:hint_range(0.0, 1.0)=0.5; 
uniform sampler2D normal_map:source_color; 
uniform float normal_scale:hint_range(-16.0, 16.0)=1.0;
uniform float beer_factor:hint_range(0.0, 10.0)=2.5; 
uniform float _roughness:hint_range(0.0, 1.0)=0.25; 
uniform float _uv_scale:hint_range(0.0, 3.0)=1.0; 

#include "res://$lib/funcs/normals.gdshaderinc"
#include "res://$lib/funcs/utils.gdshaderinc"
#include "res://$lib/funcs/colour.gdshaderinc"

void fragment() {
	vec3 vw = (INV_VIEW_MATRIX * vec4(VERTEX,1.0)).xyz;

	vec2 uv_scale = vw.xz * _uv_scale;

	// Único normal map animado (em vez de 3 no shader desktop)
	vec3 n = texture(normal_map, uv_scale + TIME * 0.04).rgb;

	float scene_depth = depth_linear(DEPTH_TEXTURE, SCREEN_UV, INV_PROJECTION_MATRIX);

	// Proximidade à superfície (sem blur de 9 taps, sem refração de tela)
	float d = depth_proximity_z(3.0, scene_depth, VERTEX);

	// Beer absorption simples
	d = exp(-d * beer_factor);

	// Fresnel simples
	d += fresnel(4.0, NORMAL, VIEW);

	ROUGHNESS = _roughness;
	ALPHA = clamp(opacity + 1.0 - d, 0.0, 1.0);

	// Normal map único
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = normal_scale;

	// Cor da água por profundidade (sem blur, sem SCREEN_TEXTURE)
	vec3 water_color = mix(depth_color, surface_color, d);

	// Profundidade para turvação simples
	float water_depth = max(scene_depth - (-VERTEX.z), 0.0);
	float visibility = exp(-water_depth * 2.5);

	ALBEDO = mix(water_color, surface_color, visibility);
}
