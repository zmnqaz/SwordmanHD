// SPDX-License-Identifier: GPL-3.0-only
// 把 6 倍烘焙结果缩到 3 / 4 倍 (手机、低分辨率屏用, 贴图面积降到 1/4 ~ 4/9: 读回、压缩、显存、磁盘缓存都跟着降)。
// 线性采样: 3 倍时每个输出像素正好是 2x2 个 6 倍像素的平均, 4 倍时是 1.5 倍缩小。透明区的颜色已经由 hq_fill 填过一圈, 缩小时不会把黑边混进来。
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D src : filter_linear, repeat_disable;

void fragment() {
	COLOR = texture(src, UV);
}
