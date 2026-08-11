// ═══════════════════════════════════════════════════════════════════════════
// СПРАЙТ БОЙЦА В ОБЩЕМ MultiMesh: КАДР И ЗЕРКАЛО ИЗ INSTANCE-ЦВЕТА
// ═══════════════════════════════════════════════════════════════════════════
// Задача: рисовать тысячи бойцов немногими вызовами отрисовки, СОХРАНИВ
// покадровую анимацию и разворот спрайта влево/вправо. У каждого экземпляра
// MultiMesh свои — только трансформ и цвет; кадр и зеркало едут во втором.
//
// ПОЧЕМУ НЕ custom_data (штатный способ передать в шейдер четыре числа на
// экземпляр): у GL Compatibility — рендерера этого проекта — открытый
// непочиненный баг с его надёжностью (godot/godot#96503). Поэтому та же
// четвёрка чисел передаётся через use_colors, который в проекте уже проверен
// (см. FarUnitRenderer). Тон фракции сюда не нужен вовсе: стороны отличаются
// РАЗНЫМИ PNG (game_settings.unit_folder), а не подкраской, так что все четыре
// канала цвета свободны.
//
// Раскладка COLOR:
//   r — номер кадра в ленте, закодирован как frame/255 (см. INV_255 ниже)
//   g — зеркало по горизонтали: >0.5 — отражать
//   b, a — свободны
//
// Лист кадров ГОРИЗОНТАЛЬНЫЙ (frame_count кадров в ряд) — ровно тот формат,
// который уже разбирает SpriteSheetParser, новый арт не нужен.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform float frame_count = 1.0;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

// Кадр едет в цвете целым числом, поделённым на 255: канал цвета в
// GL Compatibility может оказаться восьмибитным, и дробная доля потерялась бы.
// 255 кадров — потолок заведомо недостижимый (самая длинная лента в проекте
// восьмикадровая)
const float INV_255 = 1.0 / 255.0;

void vertex() {
	// БИЛБОРД С СОХРАНЕНИЕМ МАСШТАБА, ось Y мировая — то же, что
	// BILLBOARD_FIXED_Y у StandardMaterial3D, которым нарисованы ближние бойцы
	// сейчас. Собственный код нужен потому, что штатный билборд нельзя
	// совместить с выбором кадра по instance-цвету.
	//
	// Масштаб берётся ДЛИНОЙ базисных векторов, то есть БЕЗ ЗНАКА. Отсюда и
	// зеркало через цвет, а не через Basis.scaled(-1,1,1), как у дальних
	// бойцов: отрицательный масштаб здесь просто потерялся бы
	vec3 scl = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	// Ось «вправо по экрану» кладём горизонтально: боец не должен заваливаться
	// при наклоне камеры
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
	float fidx = floor(COLOR.r * 255.0 + 0.5);
	fidx = clamp(fidx, 0.0, max(frame_count - 1.0, 0.0));
	// Зеркалим ВНУТРИ кадра, а не по всей ленте: отражать надо картинку бойца,
	// а не выбор кадра
	float u = (COLOR.g > 0.5) ? (1.0 - UV.x) : UV.x;
	vec2 uv = vec2((u + fidx) / max(frame_count, 1.0), UV.y);
	vec4 col = texture(albedo_tex, uv);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	// Scissor: спрайт пишет глубину — в плотном строю нет мерцания сортировки
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}
