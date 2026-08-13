// ═══════════════════════════════════════════════════════════════════════════
// РАСТИТЕЛЬНОСТЬ В ОБЩЕМ MultiMesh: ВЕТЕР ИЗ INSTANCE-ЦВЕТА
// ═══════════════════════════════════════════════════════════════════════════
// То же самое, что cyl_billboard.gdshader, но пригодное для MultiMesh.
//
// Зачем понадобилось. У каждого растения СВОЯ фаза колыхания и СВОЯ длительность
// цикла (см. BillboardUtil.make_wind_material) — без разброса лес машет одним
// куском и читается как «ползающие кусты». Раз параметры свои, то и материал
// был свой: две тысячи ShaderMaterial на две тысячи растений, то есть две
// тысячи отдельных вызовов отрисовки. Замер (qa_veg, вся карта в кадре, армии
// нет): 1762 вызова и 75 кадров в секунду на RTX 4070 — потолок ДО появления
// первого бойца.
//
// Здесь разброс переехал в instance-цвет, и весь лес одного сорта рисуется
// одним вызовом, сохраняя прежний вид до кадра.
//
// Раскладка COLOR (как и у бойцов — через use_colors, а НЕ custom_data:
// у GL Compatibility с ним открытый баг godot/godot#96503):
//   r — фаза колыхания, доля цикла [0..1)
//   g — длительность цикла, нормированная в [0..1] между cycle_min и cycle_max
//   b, a — свободны
shader_type spatial;
render_mode unshaded, cull_disabled;

// По текселям, как и у cyl_billboard: арт пиксельный, линейная фильтрация его
// размазывает. Мипмапы оставлены — без них дальний лес мерцает на движении
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform vec4 modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;
uniform float frame_count = 1.0;
// Границы разброса длительности цикла — те же числа, что в BillboardUtil
uniform float cycle_min = 2.4;
uniform float cycle_max = 4.0;
// Вертикальная компенсация наклона камеры (см. BillboardUtil.V_STRETCH)
uniform float v_stretch = 1.0;

void vertex() {
	// Тянем ОТ НИЖНЕЙ КРОМКИ КВАДА: низ растения лежит на грунте, растяжение
	// от центра увело бы его в землю на четверть высоты (см. cyl_billboard)
	VERTEX.y = VERTEX.y * v_stretch + abs(VERTEX.y) * (v_stretch - 1.0);
	// Цилиндрический билборд: квад доворачивается к позиции камеры вокруг
	// СВОЕЙ оси. Для MultiMesh MODEL_MATRIX уже содержит трансформ экземпляра,
	// поэтому origin — это позиция конкретного растения, а не всего бакета
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	float len = length(to_cam);
	vec3 fwd = (len > 0.001) ? to_cam / len : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	// Масштаб экземпляра сохраняем: им задаётся размер конкретного куста
	// (у бакета один меш на всех) и усыхание вырубаемого дерева
	vec3 scl = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	mat4 world = mat4(
		vec4(right * scl.x, 0.0),
		vec4(0.0, scl.y, 0.0, 0.0),
		vec4(fwd * scl.z, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
}

void fragment() {
	float fidx = 0.0;
	if (frame_count > 1.0) {
		float cyc = cycle_min + COLOR.g * (cycle_max - cycle_min);
		// Скорость задаётся ЦИКЛОМ, а не кадрами в секунду: ленты в 6 и в 8
		// кадров обязаны качаться одинаково долго (см. BillboardUtil)
		float fps = frame_count / max(cyc, 0.01);
		fidx = floor(mod(TIME * fps + COLOR.r * frame_count, frame_count));
	}
	vec2 uv = vec2((UV.x + fidx) / max(frame_count, 1.0), UV.y);
	vec4 col = texture(albedo_tex, uv) * modulate;
	ALBEDO = col.rgb;
	ALPHA = col.a;
	// Scissor: пишем глубину, нет мерцания сортировки при перекрытии крон
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
