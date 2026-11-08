// SPDX-License-Identifier: GPL-3.0-only
shader_type canvas_item;
// 安全区外的边 (engine/ui/edge_mirror.gd):
//   左右 (宽屏): 把已画好的画面 (安全区 keep_a~keep_b) 按边界镜像铺出去并压暗;
//   上下 (4:3 等比 16:10 高的屏幕) 与四角: 纯黑 (同原来的留边; 上下镜像会出现倒过来的人物, 模糊填充用户不要, 2026-11-08)。
// 只改安全区之外的像素; 安全区内 alpha = 0, 原画面不受影响。
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 keep_a = vec2(0.0);  // 安全区左上 / 右下 (屏幕比例)
uniform vec2 keep_b = vec2(1.0);
uniform float dim_near = 0.62;  // 紧贴安全区处的亮度
uniform float dim_far = 0.34;   // 离安全区一个安全区宽度处的亮度

void fragment() {
	vec2 uv = SCREEN_UV;
	bool in_x = uv.x >= keep_a.x && uv.x <= keep_b.x;
	bool in_y = uv.y >= keep_a.y && uv.y <= keep_b.y;
	if (in_x && in_y) {
		COLOR = vec4(0.0);
	} else if (in_y) {
		float w = keep_b.x - keep_a.x;
		float d = uv.x < keep_a.x ? keep_a.x - uv.x : uv.x - keep_b.x;
		float t = mod(d, 2.0 * w);
		t = t > w ? 2.0 * w - t : t;
		float su = uv.x < keep_a.x ? keep_a.x + t : keep_b.x - t;
		vec3 c = texture(screen_tex, vec2(su, uv.y)).rgb;
		COLOR = vec4(c * mix(dim_near, dim_far, clamp(d / w, 0.0, 1.0)), 1.0);
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	}
}
