// SPDX-License-Identifier: LGPL-2.1-or-later
// hqx 放大一级 (2/3/4 倍), 与 ffmpeg 滤镜 hqx=N 同一算法 (当初的离线 6 倍流水线也用它)。
// 移植自 libretro slang-shaders edge-smoothing/hqx (Maxim Stepin / Cameron Zemek / Jules Blok, LGPL-2.1+):
// 原版两 pass (先算 3x3 模式再查表), 这里合成一 pass —— 模式只看本源像素的 3x3 邻域, 就地算即可。
// 插值权重查 hq{2,3,4}x.png (同出处): x = 8 邻域差异位, y = 交叉差异位 * N*N + 子像素序号。
// 透明通道不参与 (调用方先把透明区填色, 输出 alpha 恒 1)。
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D src : filter_nearest;
uniform sampler2D lut : filter_nearest;
uniform int scale = 3;

const ivec3 THRESHOLD = ivec3(48, 7, 6);

ivec3 px(ivec2 p, ivec2 sz) {
	return ivec3(round(texelFetch(src, clamp(p, ivec2(0), sz - 1), 0).rgb * 255.0));
}

// 与 ffmpeg vf_hqx 的 rgb2yuv 表一致: 0~255 整数 RGB 算 YUV 后向零截断。全程整数运算 (GLSL int 除法向零截断):
// 浮点矩阵乘在不同 GPU/驱动 (FMA 合并、舍入) 下会让恰好整数的结果落到 n-1, 阈值判定翻转 (2026-10 llvmpipe 与 NVIDIA 实测有差)
ivec3 yuv(ivec3 c) {
	return ivec3((299 * c.r + 587 * c.g + 114 * c.b) / 1000,
			(-169 * c.r - 331 * c.g + 500 * c.b) / 1000,
			(500 * c.r - 419 * c.g - 81 * c.b) / 1000);
}

float diff(ivec3 a, ivec3 b) {
	ivec3 d = abs(a - b);
	return (d.x > THRESHOLD.x || d.y > THRESHOLD.y || d.z > THRESHOLD.z) ? 1.0 : 0.0;
}

void fragment() {
	ivec2 sz = textureSize(src, 0);
	vec2 sp = UV * vec2(sz);
	ivec2 p = ivec2(floor(sp));
	vec2 fp = fract(sp);
	ivec3 w1 = yuv(px(p + ivec2(-1, -1), sz));
	ivec3 w2 = yuv(px(p + ivec2(0, -1), sz));
	ivec3 w3 = yuv(px(p + ivec2(1, -1), sz));
	ivec3 w4 = yuv(px(p + ivec2(-1, 0), sz));
	ivec3 w5 = yuv(px(p, sz));
	ivec3 w6 = yuv(px(p + ivec2(1, 0), sz));
	ivec3 w7 = yuv(px(p + ivec2(-1, 1), sz));
	ivec3 w8 = yuv(px(p + ivec2(0, 1), sz));
	ivec3 w9 = yuv(px(p + ivec2(1, 1), sz));
	float ix = diff(w5, w1) + 2.0 * diff(w5, w2) + 4.0 * diff(w5, w3) + 8.0 * diff(w5, w4)
			+ 16.0 * diff(w5, w6) + 32.0 * diff(w5, w7) + 64.0 * diff(w5, w8) + 128.0 * diff(w5, w9);
	float iy = diff(w4, w2) + 2.0 * diff(w2, w6) + 4.0 * diff(w8, w4) + 8.0 * diff(w6, w8);
	float s = float(scale);
	vec2 sub = floor(fp * s);
	ivec2 li = ivec2(int(ix), int(iy * s * s + sub.x + sub.y * s));
	ivec4 wt = ivec4(round(texelFetch(lut, li, 0) * 255.0));
	ivec2 q = ivec2(sign(fp - 0.5));
	// 整数加权后整除 (ffmpeg 是右移, 权重和为 2 的幂时相同); 与帧缓冲无关, 没有浮点取整问题
	ivec3 res = (wt.x * px(p, sz) + wt.y * px(p + q, sz) + wt.z * px(p + ivec2(q.x, 0), sz) + wt.w * px(p + ivec2(0, q.y), sz)) / (wt.x + wt.y + wt.z + wt.w);
	COLOR = vec4(vec3(res) / 255.0, 1.0);
}
