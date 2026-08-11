// ОСЕВОЙ БИЛБОРД: квад жёстко лежит вдоль ЗАДАННОЙ МИРОВОЙ ОСИ и вращается
// вокруг НЕЁ лицом к камере.
//
// Зачем: стрела должна лететь наклонённой строго по вектору скорости (вверх
// по дуге — горизонтально в вершине — вниз к цели) и при этом оставаться
// видимой с любого ракурса. Обычный билборд разворачивает квад целиком и
// съедает наклон; квад без билборда исчезает, когда камера смотрит вдоль него.
//
// Локальный +X меша ложится на ось (у QuadMesh это длинная сторона, если
// size = Vector2(длина, толщина)), локальный +Z — нормаль, смотрит на камеру.
//
// Воткнувшаяся стрела ставит ось ОДИН РАЗ и выключает _process: доворот
// к камере дальше делает GPU, ЦП на неё не тратится вовсе.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.3;
uniform vec3 axis = vec3(1.0, 0.0, 0.0);

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 ax = normalize(axis);
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	// Составляющая направления на камеру, перпендикулярная оси
	vec3 z = to_cam - ax * dot(to_cam, ax);
	float zl = length(z);
	if (zl < 0.0001) {
		// Камера точно на оси — берём любую перпендикулярную (вырожденный случай)
		vec3 tmp = (abs(ax.y) < 0.9) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		z = normalize(cross(ax, tmp));
	} else {
		z = z / zl;
	}
	vec3 y = cross(z, ax);
	// Масштаб узла сохраняем (билборд иначе его затирает)
	vec3 scl = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	mat4 world = mat4(
		vec4(ax * scl.x, 0.0),
		vec4(y * scl.y, 0.0),
		vec4(z * scl.z, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
}

void fragment() {
	vec4 col = texture(albedo_tex, UV) * modulate;
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
