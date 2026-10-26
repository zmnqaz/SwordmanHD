// SPDX-License-Identifier: GPL-3.0-only
// 原版 type 7: 正片叠底 (目标色 × 贴图色), 纯黑 (透明色键, 含高清放大后的近黑) 不画。
// 依据: 原版回合横幅 Misc/Cha_tur 底条 (灰 49) 实测压暗到底图的 0.15~0.2 倍, 白边处 ≈ 1 倍 (B4 差异)。
// 重制版 GameType7 用「越暗越不透明」的普通混合近似, 底条偏亮, 不采用。
shader_type canvas_item;
render_mode blend_mul;
void fragment() {
	vec4 s = texture(TEXTURE, UV);
	float v = max(max(s.r, s.g), s.b);
	float a = v < 0.03 ? 0.0 : s.a;
	COLOR = vec4(mix(vec3(1.0), s.rgb, a), 1.0);
}
