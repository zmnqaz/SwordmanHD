// SPDX-License-Identifier: GPL-3.0-only
// 发光部件 (原版 type 2~6): 近似滤色 1-(1-dst)(1-src)。原版公式未确认 。
// 用预乘 alpha 混合实现: 结果 = c + dst*(1-max(c)), 对灰白光效与滤色等价; 不读屏幕纹理, 避免 Godot 屏幕拷贝时序导致的黑块。
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform float strength = 1.0;
uniform bool red = false;   // 红色版 (隐藏宝箱的闪光): 蓝白色换成红色, 见 red_tint.gdshader
void fragment() {
	vec4 s = texture(TEXTURE, UV);
	if (red) {
		float v = max(max(s.r, s.g), s.b);
		s.rgb = vec3(v, s.g * s.g * 0.6, s.r * s.r * 0.4);
	}
	vec3 c = s.rgb * s.a * strength;
	COLOR = vec4(c, max(max(c.r, c.g), c.b));
}
