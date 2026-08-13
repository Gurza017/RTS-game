// ═══════════════════════════════════════════════════════════════════════════
// ПОЛОСКА ЗДОРОВЬЯ В ОБЩЕМ MultiMesh: ДОЛЯ ЖИЗНИ ИЗ INSTANCE-ЦВЕТА
// ═══════════════════════════════════════════════════════════════════════════
// Раньше полоска была ДВУМЯ узлами на бойца (корень + заливка) со СВОИМ
// QuadMesh, у которого при каждом уроне менялись size и center_offset. Замер
// (qa_hotspot, 600 бойцов, тумблер Alt поднят): +2.8 мс кадра и +720 вызовов
// отрисовки — самая дорогая мелочь в интерфейсе.
//
// ПОЧЕМУ ДОЛЯ ЕДЕТ ЦВЕТОМ, А НЕ МАСШТАБОМ ЭКЗЕМПЛЯРА. Билборд в Godot
// подменяет базис MODELVIEW целиком, и масштаб узла при этом ТЕРЯЕТСЯ
// (billboard_keep_scale по умолчанию выключен) — ровно поэтому в старом коде
// ширина задавалась размером самого меша, а не scale. В MultiMesh менять меш
// на экземпляр нельзя, поэтому доля передаётся каналом цвета (тот же приём,
// что у кадра и зеркала бойца в mm_unit_sprite.gdshader), а обрезка делается
// в фрагменте.
//
// ЯКОРЬ — ЛЕВЫЙ КРАЙ: UV.x идёт от 0 слева, и отсечка по frac оставляет
// нетронутым именно левый край, как и было у прежнего center_offset.
//
// Раскладка COLOR: r — доля здоровья [0..1], остальное свободно.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 bar_color : source_color = vec4(0.86, 0.12, 0.12, 1.0);

varying float v_frac;

void vertex() {
	v_frac = COLOR.r;
	// Билборд с СОХРАНЕНИЕМ МАСШТАБА, ось Y мировая: длину базисных векторов
	// берём сами, поэтому подмена базиса её не съедает
	vec3 scl = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	cam_right.y = 0.0;
	cam_right = normalize(cam_right);
	vec3 fwd = normalize(cross(cam_right, vec3(0.0, 1.0, 0.0)));
	mat4 world = mat4(
		vec4(cam_right * scl.x, 0.0),
		vec4(0.0, scl.y, 0.0, 0.0),
		vec4(fwd * scl.z, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
}

void fragment() {
	// Всё, что правее доли жизни, не рисуется вовсе — полоска укорачивается
	// слева направо, а не сжимается к центру
	if (UV.x > v_frac) {
		discard;
	}
	ALBEDO = bar_color.rgb;
	ALPHA = bar_color.a;
}
