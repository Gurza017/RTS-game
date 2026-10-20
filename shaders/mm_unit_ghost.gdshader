// ═══════════════════════════════════════════════════════════════════════════
// СИЛУЭТ БОЙЦА СКВОЗЬ ПОСТРОЙКУ (ТЗ 14.10.2026, п. 1)
// ═══════════════════════════════════════════════════════════════════════════
// Второй проход (next_pass) материала бакета бойцов. Рисует полупрозрачный
// силуэт цвета фракции ТОЛЬКО там, где поверх бойца лежит видимый пиксель
// здания. Как это узнаётся — трафаретом, без сортировок на ЦП:
//   • рисунок постройки пишет в трафарет 1 (BillboardUtil.building_shader);
//   • основной проход бойца пишет 0 там, где боец ВИДЕН (запись — только при
//     прошедшем тесте глубины), — так «боец перед зданием» метку стирает,
//     в каком бы порядке ни шли непрозрачные;
//   • здесь — чтение «== 1» без теста глубины: силуэт ложится ровно на
//     пиксели здания, закрывающие бойца. Деревья, трупы и другие бойцы
//     трафарет не трогают, сквозь них силуэта нет.
// Проход прозрачный (blend_mix) — идёт после всех непрозрачных, когда
// трафарет кадра уже окончательный.
// Вершинная часть — ДОСЛОВНАЯ копия mm_unit_sprite (билборд с мировой Y):
// разойдись она — силуэт уехал бы от бойца.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled;
stencil_mode read, compare_equal, 1;

uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform float frame_count = 1.0;
uniform vec3 ghost_color : source_color = vec3(0.45, 0.75, 1.0);
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.50;
// Лёгкое свечение кромки: силуэт читается и на светлой стене
uniform float ghost_rim : hint_range(0.0, 1.0) = 0.35;

void vertex() {
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
	float fc = max(frame_count, 1.0);
	float fidx = clamp(floor(COLOR.r * 255.0 + 0.5), 0.0, fc - 1.0);
	float u = (COLOR.g > 0.5) ? (1.0 - UV.x) : UV.x;
	vec2 uv = vec2((u + fidx) / fc, UV.y);
	float a = texture(albedo_tex, uv).a;
	// Только тело (запечённая тень в листе — полупрозрачная, её не берём)
	if (a < 0.5) {
		discard;
	}
	// Кромка: сосед в 2 текселя прозрачен — пиксель на краю силуэта
	vec2 px = vec2(1.0) / vec2(textureSize(albedo_tex, 0));
	float edge = 0.0;
	edge = max(edge, 1.0 - step(0.5, texture(albedo_tex, uv + vec2(px.x * 2.0, 0.0)).a));
	edge = max(edge, 1.0 - step(0.5, texture(albedo_tex, uv - vec2(px.x * 2.0, 0.0)).a));
	edge = max(edge, 1.0 - step(0.5, texture(albedo_tex, uv + vec2(0.0, px.y * 2.0)).a));
	edge = max(edge, 1.0 - step(0.5, texture(albedo_tex, uv - vec2(0.0, px.y * 2.0)).a));
	ALBEDO = mix(ghost_color, vec3(1.0), edge * ghost_rim);
	ALPHA = ghost_alpha + edge * 0.25;
}
