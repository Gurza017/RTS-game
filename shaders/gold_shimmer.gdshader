// БЛЕСК ЗОЛОТА. Накладывается ВТОРЫМ квадом поверх основного спрайта жилы
// и использует парную текстуру *_Highlight.png из assets/environment/resources.
//
// Отличия от cyl_billboard.gdshader:
//   • blend_add вместо scissor — блик подмешивается, а не вырезается по альфе,
//     поэтому его можно плавно гасить и разжигать;
//   • интенсивность гоняется по TIME прямо в шейдере. Никакого _process на
//     стороне GDScript: сотня жил на карте не стоит ни одного такта CPU,
//     анимация «сама играет» с момента появления узла.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform sampler2D highlight_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 0.92, 0.55, 1.0);

// ВНИМАНИЕ: *_Highlight.png — это ГОРИЗОНТАЛЬНЫЙ СПРАЙТ-ШИТ (768x128 = 6 кадров
// по 128x128), готовая покадровая анимация блика. Раньше шейдер брал texture()
// по голому UV и натягивал ВЕСЬ лист на один квад — на жиле было видно шесть
// слипшихся кадров, «линейный забор мигающих цветов». Теперь режем лист как
// в cyl_billboard.gdshader и показываем РОВНО ОДИН кадр за раз.
uniform float frame_count = 1.0;
uniform float frame_fps = 8.0;
// Случайный сдвиг фазы — соседние самородки переливаются вразнобой
uniform float phase = 0.0;
// Общая яркость блика поверх основного спрайта. НИЗКАЯ НАРОЧНО: кучи стоят
// плотно внахлёст (см. PIECE_MIN_GAP в Main.gd — это специально ради вида
// единого навала), поэтому у соседних кусков блики почти всегда перекрываются
// на экране, а аддитивное смешивание СКЛАДЫВАЕТ перекрывающиеся вклады. При
// 0.85 два-три наложившихся блика уходили за 1.0 и весь стык прогорал в
// сплошное белое пятно — та самая «грязная подсветка», которую когда-то
// приняли за дефект самой текстуры. 0.85 было бы уместно для ОДНОГО
// самородка в одиночестве; в куче правильная яркость — та, что не
// прогорает даже при 3 наложившихся кусках
uniform float gain = 0.22;

// Квад блика построен ПОД ОБРЕЗАННЫЙ основной спрайт (ResourceNode обрезает
// прозрачные поля кадра через AtlasTexture — см. _maybe_load_sprite). У
// блика своя анимация кадров, единым AtlasTexture его не обрезать, поэтому
// сюда передаётся та же обрезка в долях ОДНОГО кадра (xy — угол, zw —
// размер): фрагментный шейдер сначала сужает UV до этого прямоугольника, и
// только потом выбирает кадр листа — рисунок блика ложится на рисунок жилы
// пиксель в пиксель, без отдельного холста вокруг
uniform vec4 crop_rect = vec4(0.0, 0.0, 1.0, 1.0);

void vertex() {
	// Тот же цилиндрический билборд, что и у основного спрайта, — блик
	// обязан висеть строго в его плоскости, иначе «отклеится» при орбите
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	float len = length(to_cam);
	vec3 fwd = (len > 0.001) ? to_cam / len : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
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
	// Номер текущего кадра листа: та же схема, что у cyl_billboard.gdshader
	float fidx = (frame_fps > 0.0 && frame_count > 1.0)
		? floor(mod(TIME * frame_fps + phase, frame_count))
		: 0.0;
	vec2 local = crop_rect.xy + UV * crop_rect.zw;
	vec2 uv = vec2((local.x + fidx) / frame_count, local.y);
	vec4 col = texture(highlight_tex, uv);
	ALBEDO = col.rgb * tint.rgb * gain;
	ALPHA  = col.a * tint.a * gain;
}
