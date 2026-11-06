// SPDX-License-Identifier: GPL-3.0-only
// 狂暴的红色光晕 (原版绘制, 2026-11-06 对照原版): 宽度 w 在 0..6 间每 0.12 秒 ±2 往返;
//   ① 把人物当前帧最近邻拉伸进 (W+w) x (H+w) 的缓冲 (左右各宽 w/2、上方高 w、下方不变, 脚底对齐);
//   ② 在缓冲 (w/2, w) 处按人物原尺寸的形状写 0 = 把人物本身挖掉, 人物不变红;
//   ③ 以剩下的环为形状, 屏幕上 (x - w/2, y - w) 起做「底 * dst_keep + 红 * col_k」(0x7c00)。
// 顶点把四边按 ① 推开 (UV 仍是 0..1 = 拉伸后的取样), base_uv = 这一点在人物原尺寸贴图上的位置 (挖掉用)。
// 红色那一项按原版权重表量化 (同 unit_status.gdshader 的 tw); 底那一项预乘 alpha 混合按连续值。参数在布局表 map.unit.status_tint.berserk。
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform vec3 col = vec3(1.0, 0.0, 0.0);
uniform float col_k = 0.375;
uniform float dst_keep = 0.75;
uniform float width = 0.0;         // w, 原版像素
uniform float px_per_orig = 1.0;   // 贴图像素 / 原版像素 (高清贴图 6 倍时 = 6)
varying vec2 base_uv;
void vertex() {
	vec2 size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	float mx = width * 0.5 * px_per_orig;
	float my = width * px_per_orig;
	VERTEX = vec2(mix(-mx, size.x + mx, UV.x), mix(-my, size.y, UV.y));
	base_uv = VERTEX / size;
}
vec3 tw(vec3 v5, float w) {
	float k = floor(w * 16.0 + 0.5);
	vec3 t = min(vec3(31.0), floor(v5 * k / 16.0));
	return t - mod(t, 2.0);
}
void fragment() {
	float a_st = texture(TEXTURE, UV).a;
	float a_un = 0.0;
	if (base_uv.x >= 0.0 && base_uv.y >= 0.0 && base_uv.x <= 1.0 && base_uv.y <= 1.0) {
		a_un = texture(TEXTURE, base_uv).a;
	}
	float m = (a_st > 0.5 && a_un <= 0.5) ? 1.0 : 0.0;   // 原版按「有像素」二值判定
	vec3 red = tw(floor(col * 31.0 + 0.5), col_k) / 31.0;
	COLOR = vec4(red * m, m * (1.0 - dst_keep));
}
