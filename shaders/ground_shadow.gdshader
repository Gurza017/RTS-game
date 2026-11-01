shader_type spatial;
// Мягкая тень у основания постройки (ТЗ 30.10.2026): эллипс на земле,
// плотный в середине и тающий к краю. Глубину не пишет, свет не считает
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 shade : source_color = vec4(0.04, 0.07, 0.03, 1.0);
uniform float strength = 0.5;
// С какой доли радиуса начинается спад (0 — сразу, 1 — жёсткий край)
uniform float core = 0.35;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	float a = 1.0 - smoothstep(core, 1.0, d);
	ALBEDO = shade.rgb;
	ALPHA = strength * a * a;
}
