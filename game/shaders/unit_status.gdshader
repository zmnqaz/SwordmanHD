// SPDX-License-Identifier: GPL-3.0-only
// 战场单位本体的状态着色 (原版绘制, 2026-11-06 对照原版): 先中毒、再冰結各做一次「源 * src_k + 色 * col_k」,
// 幻影再按「源 * ghost_src + 底 * ghost_keep」叠到底上 (两个权重相加可以 > 1, 所以幻影比底亮)。
// 原版按 RGB555 每通道查权重表 (填): t = min(31, floor(v * K / 16)) 再清最低位 (& 0x7bde, 结果总是偶数),
// K = 2 * (k >> 1); 两项按打包的 16 位数直接相加: 清掉的最低位是进位位, 蓝溢出时蓝封顶 31 且绿 +1, 绿溢出时绿封顶且红 +1, 红溢出封顶
// (test 0x20 / 0x400 / 0x8000 只把低通道或满, 进位留在上一通道; 2026-11-06 实测第 1 关殷剑平 1005 像素逐个核对, 见 add555)。
// 这里照这个量化 (q5 / tw / add555), 连续公式会整体偏亮 10~14/255。
// 幻影的「底」那一项要读屏幕, 用预乘 alpha 混合按连续值近似 (只有人物那一项量化)。
// 权重 = (k>>1)/8, 参数都在布局表 map.unit.status_tint (BattleUnit._tint 读表设进来), 这里不写常量。
shader_type canvas_item;
render_mode blend_premul_alpha;
uniform bool tint1_on = false;   // 中毒
uniform vec3 tint1_col = vec3(0.0);
uniform float tint1_col_k = 0.0;
uniform float tint1_src_k = 1.0;
uniform bool tint2_on = false;   // 冰結
uniform vec3 tint2_col = vec3(0.0);
uniform float tint2_col_k = 0.0;
uniform float tint2_src_k = 1.0;
uniform bool ghost = false;      // 幻影
uniform float ghost_src = 1.0;
uniform float ghost_keep = 0.0;

// 0~1 -> 5 位通道值 (原版贴图本是 RGB555)
vec3 q5(vec3 c) {
	return floor(c * 31.0 + 0.5);
}
// 权重表一项: 权重 w = K/16 (K 偶数), t = min(31, floor(v*K/16)) 去掉最低位
vec3 tw(vec3 v5, float w) {
	float k = floor(w * 16.0 + 0.5);
	vec3 t = min(vec3(31.0), floor(v5 * k / 16.0));
	return t - mod(t, 2.0);
}
// 两项 (都已去最低位) 打包相加, 带原版的进位与封顶
vec3 add555(vec3 a, vec3 b) {
	float bl = a.b + b.b;
	float cb = bl >= 32.0 ? 1.0 : 0.0;
	float g = a.g + b.g + cb;
	float cg = g >= 32.0 ? 1.0 : 0.0;
	float r = a.r + b.r + cg;
	return vec3(min(r, 31.0), cg > 0.0 ? 31.0 : g, cb > 0.0 ? 31.0 : bl);
}
void fragment() {
	vec4 s = texture(TEXTURE, UV);
	vec3 v = q5(s.rgb);
	if (tint1_on) {
		v = add555(tw(v, tint1_src_k), tw(q5(tint1_col), tint1_col_k));
	}
	if (tint2_on) {
		v = add555(tw(v, tint2_src_k), tw(q5(tint2_col), tint2_col_k));
	}
	if (ghost) {
		COLOR = vec4(tw(v, ghost_src) / 31.0 * s.a, s.a * (1.0 - ghost_keep));
	} else if (tint1_on || tint2_on) {
		COLOR = vec4(v / 31.0 * s.a, s.a);
	} else {
		COLOR = vec4(s.rgb * s.a, s.a);
	}
}
