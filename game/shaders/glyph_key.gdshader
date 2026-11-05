// SPDX-License-Identifier: GPL-3.0-only
// 字模底色抠掉: 原版字模每格自带一块羊皮纸底 (和原版面板同色, 贴上去看不出); 高清面板颜色不同, 底就成了一个个浅色方块。
// 与底色 key 相近的像素按距离淡出 (lo 以内全透明, hi 以外不动), 只留笔画与描边 (UiNumber 高清画质用)
shader_type canvas_item;

uniform vec3 key = vec3(0.937, 0.871, 0.580);
uniform float lo = 0.05;
uniform float hi = 0.13;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR.a *= smoothstep(lo, hi, distance(t.rgb, key));
}
