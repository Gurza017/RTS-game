// ОСЕВОЙ БИЛБОРД ДЛЯ MultiMesh СТРЕЛ (этап D3). Тот же принцип, что у
// axis_billboard.gdshader (квад лежит вдоль оси и крутится вокруг неё лицом к
// камере), но ось и растворение приезжают ДАННЫМИ ЭКЗЕМПЛЯРА в instance-цвете:
//   COLOR.rgb — ось полёта/втыкания, упакованная как ax*0.5+0.5
//   COLOR.a   — доля покрытия (дизер-растворение), 1 = целая
// custom_data не берём сознательно — у GL Compatibility с ним открытый баг
// (см. шапку FarUnitRenderer); восьмибитная точность оси (~0.4% на канал)
// на тонком кваде стрелы глазом неразличима.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.2;

varying float v_fade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 ax = COLOR.rgb * 2.0 - 1.0;
	float axl = length(ax);
	ax = axl > 0.0001 ? ax / axl : vec3(1.0, 0.0, 0.0);
	v_fade = COLOR.a;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	vec3 z = to_cam - ax * dot(to_cam, ax);
	float zl = length(z);
	if (zl < 0.0001) {
		vec3 tmp = (abs(ax.y) < 0.9) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		z = normalize(cross(ax, tmp));
	} else {
		z = z / zl;
	}
	vec3 y = cross(z, ax);
	mat4 world = mat4(
		vec4(ax, 0.0),
		vec4(y, 0.0),
		vec4(z, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
}

// Растворение — ДИЗЕРОМ, порог среза не снимается никогда (разбор — в
// axis_billboard.gdshader: снятый порог и был «чёрным прямоугольником»)
const int BAYER4[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

void fragment() {
	vec4 col = texture(albedo_tex, UV) * modulate;
	if (v_fade < 0.999) {
		int bx = int(FRAGCOORD.x) & 3;
		int by = int(FRAGCOORD.y) & 3;
		float th = (float(BAYER4[by * 4 + bx]) + 0.5) * 0.0625;
		if (v_fade <= th) {
			discard;
		}
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
