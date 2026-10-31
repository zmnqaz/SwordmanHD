// SPDX-License-Identifier: GPL-3.0-only
// 发光部件 (原版 type 2~6): 饱和相加 结果 = 底 * dst_keep + 源 * strength (超过 1 夹成白)。
// 与 一致 (近景血条闪光: 底*12/16 + 白*10/16, T_k[c] = c*k/16,), 部件参数 p8 = 源权重 (strength = p8/16), p10 = 底保留 (dst_keep = p10/16);
// 最常见的 (p8, 16) 就是纯相加 (源按 p8/16 减弱)。亮的底上 (岩壁、地面高光) 相加会烧成白, 这正是原版火把 / 灯的光晕。
// 2026-10-31 以前这里是近似滤色 1-(1-dst)(1-src) 且强度取 p8*0.05, 在亮底上几乎没效果 (序章壁灯没有光晕, 与原版 对照差很多)。
// 用预乘 alpha 混合实现: out = c + dst*(1-a), 取 c = 源*alpha*strength、a = alpha*(1-dst_keep); 不读屏幕纹理, 避免 Godot 屏幕拷贝时序导致的黑块。
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform float strength = 1.0;
uniform float dst_keep = 1.0;
uniform bool red = false;   // 红色版 (隐藏宝箱的闪光): 蓝白色换成红色, 见 red_tint.gdshader
void fragment() {
	vec4 s = texture(TEXTURE, UV);
	if (red) {
		float v = max(max(s.r, s.g), s.b);
		s.rgb = vec3(v, s.g * s.g * 0.6, s.r * s.r * 0.4);
	}
	vec3 c = s.rgb * s.a * strength;
	COLOR = vec4(c, s.a * (1.0 - dst_keep));
}
