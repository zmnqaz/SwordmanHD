// SPDX-License-Identifier: GPL-3.0-only
// 红色版 (隐藏宝箱的闪光): 把原版宝箱闪光的蓝白色换成红色 (亮处偏白红, 蓝点变红点), alpha 与动画节奏不变。
// 普通 (非混合) 部件用; 发光 (滤色) 部件的红色版在 screen_blend.gdshader 的 red 参数里。
shader_type canvas_item;
void fragment() {
	vec4 s = texture(TEXTURE, UV);
	float v = max(max(s.r, s.g), s.b);
	COLOR = vec4(v, s.g * s.g * 0.6, s.r * s.r * 0.4, s.a) * COLOR.a;
}
