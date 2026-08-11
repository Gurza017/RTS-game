// ТУМАН ВОЙНЫ. Одна большая горизонтальная плоскость поверх всей карты;
// что где закрыто — читается из маски, которую пересчитывает scripts/FogOfWar.gd.
//
// Маска: R = «видно прямо сейчас» (кто-то из своих смотрит сюда),
//        G = «когда-либо разведано». Два состояния, а не одно, потому что
//        разведанная, но покинутая земля должна оставаться видимой рельефом
//        (игрок помнит, что там было), а вот ЮНИТОВ на ней быть не должно —
//        их гасит уже не шейдер, а Unit.tick_visual по тому же признаку.
//
// depth_test_disabled — намеренно: плоскость лежит почти на земле (y≈0.05),
// а закрывать она обязана и деревья пятиметровой высоты, и постройки. Без
// отключённого теста глубины крона куста торчала бы из тумана.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never,
	depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D fog_mask : filter_linear, source_color;
// Полуразмеры карты в метрах: по ним мировые координаты переводятся в UV.
// UV считается ИЗ МИРОВОЙ ТОЧКИ, а не из встроенного UV квада, чтобы поворот
// или размер плоскости нельзя было рассогласовать с маской по невнимательности
uniform vec2 map_half = vec2(130.0, 73.125);
uniform vec4 fog_color : source_color = vec4(0.16, 0.17, 0.20, 1.0);
// Непрозрачность неразведанного и уже разведанного, но сейчас не просматриваемого
uniform float hidden_alpha = 0.86;
uniform float seen_alpha   = 0.42;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz + map_half) / (2.0 * map_half);
	// За краем карты туман сплошной: иначе на бортике маска берётся с
	// зажимом крайнего пикселя и «протекает» полосой открытой земли
	vec4 m = texture(fog_mask, clamp(uv, vec2(0.0), vec2(1.0)));
	float lit  = m.r;
	float seen = m.g;
	float a = mix(mix(hidden_alpha, seen_alpha, seen), 0.0, lit);
	ALBEDO = fog_color.rgb;
	ALPHA  = a;
}
