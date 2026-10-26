// SPDX-License-Identifier: GPL-3.0-only
shader_type canvas_item;
// 宽屏安全区两侧: 把已画好的画面 (安全区内) 按边界镜像铺出去并压暗, 不留黑边 (engine/ui/edge_mirror.gd)。
// 只改安全区之外的像素; 安全区内 alpha = 0, 原画面不受影响。
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float safe_a = 0.0;  // 安全区左右边界 (屏幕宽度的比例)
uniform float safe_b = 1.0;
uniform float dim_near = 0.62;  // 紧贴安全区处的亮度
uniform float dim_far = 0.34;   // 离安全区一个安全区宽度处的亮度

void fragment() {
	float u = SCREEN_UV.x;
	float w = safe_b - safe_a;
	float d = 0.0;
	if (u < safe_a) {
		d = safe_a - u;
	} else if (u > safe_b) {
		d = u - safe_b;
	} else {
		COLOR = vec4(0.0);
	}
	if (d > 0.0) {
		float t = mod(d, 2.0 * w);
		t = t > w ? 2.0 * w - t : t;
		float su = u < safe_a ? safe_a + t : safe_b - t;
		vec3 c = texture(screen_tex, vec2(su, SCREEN_UV.y)).rgb;
		COLOR = vec4(c * mix(dim_near, dim_far, clamp(d / w, 0.0, 1.0)), 1.0);
	}
}
