// SPDX-License-Identifier: GPL-3.0-only
// 贴图形状 (源像素非 0) 范围内的「底」按权重表调亮/调暗: 底 = T[k][底] (RGB555 每通道 min(31, floor(v*K/16)) 再清最低位, K = 2*(k>>1))。
// 营地五魂分配时的描边呼吸 (传 字段, k 16↔32 往返, 见 CampSpirit.glow_step) 用它: 底下的内容亮度 1~2 倍呼吸, 描边贴图自身颜色不画。
// 要读屏幕 (同 part_invert 的 type 6)。
shader_type canvas_item;
uniform float k = 16.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
void fragment() {
	vec4 s = texture(TEXTURE, UV);
	vec3 d = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 v = floor(d * 31.0 + 0.5);
	float kk = 2.0 * floor(k / 2.0);
	vec3 t = min(vec3(31.0), floor(v * kk / 16.0));
	t = t - mod(t, 2.0);
	COLOR = vec4(mix(d, t / 31.0, step(0.5, s.a)), 1.0);
}
