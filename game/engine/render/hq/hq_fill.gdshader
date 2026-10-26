// SPDX-License-Identifier: GPL-3.0-only
// 透明区向外填色一圈 (= 生成工具的脚本 fill_transparent 的一次迭代): 未知像素取 8 邻域已知像素的均值。
// alpha 作「已知」标记 (>0 已知, 输出 1/0); 邻域按 np.roll 的回绕取, 与离线一致。
// hqx 会把邻近像素的颜色混进边缘, 透明处必须先填上相近颜色, 否则轮廓发黑。
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D src : filter_nearest;

void fragment() {
	ivec2 sz = textureSize(src, 0);
	ivec2 p = ivec2(floor(UV * vec2(sz)));
	vec4 c = texelFetch(src, p, 0);
	vec4 res = vec4(c.rgb, 1.0);
	if (c.a <= 0.0) {
		ivec3 acc = ivec3(0);
		int cnt = 0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) {
					continue;
				}
				vec4 n = texelFetch(src, (p + ivec2(dx, dy) + sz) % sz, 0);
				if (n.a > 0.0) {
					acc += ivec3(round(n.rgb * 255.0));
					cnt += 1;
				}
			}
		}
		// 整数均值 (向下取整, 同离线 astype(uint8)): 浮点均值恰为 x.5 (两邻居、和为奇数) 时, 写入 8 位目标的舍入方向各 GPU/驱动不同
		// (llvmpipe 与 NVIDIA 实测有差), 会让下游 hqx 的阈值判定翻转
		res = cnt > 0 ? vec4(vec3(acc / cnt) / 255.0, 1.0) : vec4(0.0);
	}
	COLOR = res;
}
