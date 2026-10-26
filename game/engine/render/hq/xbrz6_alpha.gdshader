// SPDX-License-Identifier: GPL-3.0-only
// 6 倍 xBRZ 只取透明通道 + 收紧, 与 hq 链颜色合成最终贴图 (= 当初离线 6 倍流水线的做法: hq 链颜色 + tighten(xbrz alpha))。
// 本文件由 生成工具的脚本 生成, 判定部分机械转换自 libretro slang-shaders edge-smoothing/xbrz/shaders/6xbrz.slang
// (Hyllian 的 xBR 框架 MIT; xBRZ 算法 Zenju, GPL-3.0 —— 见 hq/README.md 许可说明)。
// 与原版的差别 (对齐离线用的 C++ xBRZ 1.8 ARGB 模式, 实测透明通道与 hd6x 逐像素相同):
//   像素带 alpha, 距离按 ColorDistanceARGB (alpha 加权 + alpha 差), 等值比较含 alpha; 图外按全透明;
//   混合对 alpha 线性 (= C++ alphaGrad 的 alpha 结果), 颜色不用 (颜色取 hq 链)。
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D orig : filter_nearest;     // 1 倍原图 RGBA
uniform sampler2D color6 : filter_nearest;   // hq 链 6 倍颜色

#define BLEND_NONE 0
#define BLEND_NORMAL 1
#define BLEND_DOMINANT 2
#define LUMINANCE_WEIGHT 1.0
#define EQUAL_COLOR_TOLERANCE 30.0/255.0
#define STEEP_DIRECTION_THRESHOLD 2.2
#define DOMINANT_DIRECTION_THRESHOLD 3.6

const float one_sixth = 1.0 / 6.0;
const float two_sixth = 2.0 / 6.0;
const float four_sixth = 4.0 / 6.0;
const float five_sixth = 5.0 / 6.0;

float DistYCbCr(vec4 pixA, vec4 pixB) {
	vec3 w = vec3(0.2627, 0.6780, 0.0593);
	float scaleB = 0.5 / (1.0 - w.b);
	float scaleR = 0.5 / (1.0 - w.r);
	vec3 diff = pixA.rgb - pixB.rgb;
	float Y = dot(diff, w);
	float Cb = scaleB * (diff.b - Y);
	float Cr = scaleR * (diff.r - Y);
	float d = sqrt(((LUMINANCE_WEIGHT * Y) * (LUMINANCE_WEIGHT * Y)) + (Cb * Cb) + (Cr * Cr));
	// C++ xBRZ ColorDistanceARGB: 透明度低的一方按 alpha 缩小颜色差, 再加上 alpha 差
	return pixA.a < pixB.a ? pixA.a * d + (pixB.a - pixA.a) : pixB.a * d + (pixA.a - pixB.a);
}

bool IsPixEqual(vec4 pixA, vec4 pixB) {
	return DistYCbCr(pixA, pixB) < EQUAL_COLOR_TOLERANCE;
}

bool IsBlendingNeeded(ivec4 blend) {
	return any(notEqual(blend, ivec4(BLEND_NONE)));
}

bool eq(vec4 a, vec4 b) {
	return all(equal(a, b));
}

// 图外按全透明 (C++ xBRZ 1.8 ARGB 的 OobReaderTransparent; libretro 原版是夹到边缘)
vec4 px(ivec2 p, ivec2 sz) {
	return any(lessThan(p, ivec2(0))) || any(greaterThanEqual(p, sz)) ? vec4(0.0) : texelFetch(orig, p, 0);
}

void fragment() {
	ivec2 sz = textureSize(orig, 0);
	vec2 sp = UV * vec2(sz);
	ivec2 p = ivec2(floor(sp));
	vec2 f = fract(sp);
	//   Input Pixel Mapping:  20|21|22|23|24
	//                         19|06|07|08|09
	//                         18|05|00|01|10
	//                         17|04|03|02|11
	//                         16|15|14|13|12
	vec4 src[25];
	src[21] = px(p + ivec2(-1, -2), sz);
	src[22] = px(p + ivec2(0, -2), sz);
	src[23] = px(p + ivec2(1, -2), sz);
	src[6] = px(p + ivec2(-1, -1), sz);
	src[7] = px(p + ivec2(0, -1), sz);
	src[8] = px(p + ivec2(1, -1), sz);
	src[5] = px(p + ivec2(-1, 0), sz);
	src[0] = px(p, sz);
	src[1] = px(p + ivec2(1, 0), sz);
	src[4] = px(p + ivec2(-1, 1), sz);
	src[3] = px(p + ivec2(0, 1), sz);
	src[2] = px(p + ivec2(1, 1), sz);
	src[15] = px(p + ivec2(-1, 2), sz);
	src[14] = px(p + ivec2(0, 2), sz);
	src[13] = px(p + ivec2(1, 2), sz);
	src[19] = px(p + ivec2(-2, -1), sz);
	src[18] = px(p + ivec2(-2, 0), sz);
	src[17] = px(p + ivec2(-2, 1), sz);
	src[9] = px(p + ivec2(2, -1), sz);
	src[10] = px(p + ivec2(2, 0), sz);
	src[11] = px(p + ivec2(2, 1), sz);

ivec4 blendResult = ivec4(BLEND_NONE);
	
	// Preprocess corners
	// Pixel Tap Mapping: --|--|--|--|--
	//                    --|--|07|08|--
	//                    --|05|00|01|10
	//                    --|04|03|02|11
	//                    --|--|14|13|--
	// Corner (1, 1)
	if (!((eq(src[0], src[1]) && eq(src[3], src[2])) || (eq(src[0], src[3]) && eq(src[1], src[2]))))
	{
		float dist_03_01 = DistYCbCr(src[ 4], src[ 0]) + DistYCbCr(src[ 0], src[ 8]) + DistYCbCr(src[14], src[ 2]) + DistYCbCr(src[ 2], src[10]) + (4.0 * DistYCbCr(src[ 3], src[ 1]));
		float dist_00_02 = DistYCbCr(src[ 5], src[ 3]) + DistYCbCr(src[ 3], src[13]) + DistYCbCr(src[ 7], src[ 1]) + DistYCbCr(src[ 1], src[11]) + (4.0 * DistYCbCr(src[ 0], src[ 2]));
		bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_03_01) < dist_00_02;
		blendResult[2] = ((dist_03_01 < dist_00_02) && (!eq(src[0], src[1])) && (!eq(src[0], src[3]))) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
	}

	// Pixel Tap Mapping: --|--|--|--|--
	//                    --|06|07|--|--
	//                    18|05|00|01|--
	//                    17|04|03|02|--
	//                    --|15|14|--|--
	// Corner (0, 1)
	if (!((eq(src[5], src[0]) && eq(src[4], src[3])) || (eq(src[5], src[4]) && eq(src[0], src[3]))))
	{
		float dist_04_00 = DistYCbCr(src[17], src[ 5]) + DistYCbCr(src[ 5], src[ 7]) + DistYCbCr(src[15], src[ 3]) + DistYCbCr(src[ 3], src[ 1]) + (4.0 * DistYCbCr(src[ 4], src[ 0]));
		float dist_05_03 = DistYCbCr(src[18], src[ 4]) + DistYCbCr(src[ 4], src[14]) + DistYCbCr(src[ 6], src[ 0]) + DistYCbCr(src[ 0], src[ 2]) + (4.0 * DistYCbCr(src[ 5], src[ 3]));
		bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_05_03) < dist_04_00;
		blendResult[3] = ((dist_04_00 > dist_05_03) && (!eq(src[0], src[5])) && (!eq(src[0], src[3]))) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
	}
	
	// Pixel Tap Mapping: --|--|22|23|--
	//                    --|06|07|08|09
	//                    --|05|00|01|10
	//                    --|--|03|02|--
	//                    --|--|--|--|--
	// Corner (1, 0)
	if (!((eq(src[7], src[8]) && eq(src[0], src[1])) || (eq(src[7], src[0]) && eq(src[8], src[1]))))
	{
		float dist_00_08 = DistYCbCr(src[ 5], src[ 7]) + DistYCbCr(src[ 7], src[23]) + DistYCbCr(src[ 3], src[ 1]) + DistYCbCr(src[ 1], src[ 9]) + (4.0 * DistYCbCr(src[ 0], src[ 8]));
		float dist_07_01 = DistYCbCr(src[ 6], src[ 0]) + DistYCbCr(src[ 0], src[ 2]) + DistYCbCr(src[22], src[ 8]) + DistYCbCr(src[ 8], src[10]) + (4.0 * DistYCbCr(src[ 7], src[ 1]));
		bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_07_01) < dist_00_08;
		blendResult[1] = ((dist_00_08 > dist_07_01) && (!eq(src[0], src[7])) && (!eq(src[0], src[1]))) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
	}
	
	// Pixel Tap Mapping: --|21|22|--|--
	//                    19|06|07|08|--
	//                    18|05|00|01|--
	//                    --|04|03|--|--
	//                    --|--|--|--|--
	// Corner (0, 0)
	if (!((eq(src[6], src[7]) && eq(src[5], src[0])) || (eq(src[6], src[5]) && eq(src[7], src[0]))))
	{
		float dist_05_07 = DistYCbCr(src[18], src[ 6]) + DistYCbCr(src[ 6], src[22]) + DistYCbCr(src[ 4], src[ 0]) + DistYCbCr(src[ 0], src[ 8]) + (4.0 * DistYCbCr(src[ 5], src[ 7]));
		float dist_06_00 = DistYCbCr(src[19], src[ 5]) + DistYCbCr(src[ 5], src[ 3]) + DistYCbCr(src[21], src[ 7]) + DistYCbCr(src[ 7], src[ 1]) + (4.0 * DistYCbCr(src[ 6], src[ 0]));
		bool dominantGradient = (DOMINANT_DIRECTION_THRESHOLD * dist_05_07) < dist_06_00;
		blendResult[0] = ((dist_05_07 < dist_06_00) && (!eq(src[0], src[5])) && (!eq(src[0], src[7]))) ? ((dominantGradient) ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
	}
	
	vec4 dst[36];
	dst[ 0] = src[0];
	dst[ 1] = src[0];
	dst[ 2] = src[0];
	dst[ 3] = src[0];
	dst[ 4] = src[0];
	dst[ 5] = src[0];
	dst[ 6] = src[0];
	dst[ 7] = src[0];
	dst[ 8] = src[0];
	dst[ 9] = src[0];
	dst[10] = src[0];
	dst[11] = src[0];
	dst[12] = src[0];
	dst[13] = src[0];
	dst[14] = src[0];
	dst[15] = src[0];
	dst[16] = src[0];
	dst[17] = src[0];
	dst[18] = src[0];
	dst[19] = src[0];
	dst[20] = src[0];
	dst[21] = src[0];
	dst[22] = src[0];
	dst[23] = src[0];
	dst[24] = src[0];
	dst[25] = src[0];
	dst[26] = src[0];
	dst[27] = src[0];
	dst[28] = src[0];
	dst[29] = src[0];
	dst[30] = src[0];
	dst[31] = src[0];
	dst[32] = src[0];
	dst[33] = src[0];
	dst[34] = src[0];
	dst[35] = src[0];
	
	// Scale pixel
	if (IsBlendingNeeded(blendResult))
	{
		float dist_01_04 = DistYCbCr(src[1], src[4]);
		float dist_03_08 = DistYCbCr(src[3], src[8]);
		bool haveShallowLine = (STEEP_DIRECTION_THRESHOLD * dist_01_04 <= dist_03_08) && (!eq(src[0], src[4])) && (!eq(src[5], src[4]));
		bool haveSteepLine   = (STEEP_DIRECTION_THRESHOLD * dist_03_08 <= dist_01_04) && (!eq(src[0], src[8])) && (!eq(src[7], src[8]));
		bool needBlend = (blendResult[2] != BLEND_NONE);
		bool doLineBlend = (  blendResult[2] >= BLEND_DOMINANT ||
				   !((blendResult[1] != BLEND_NONE && !IsPixEqual(src[0], src[4])) ||
				 (blendResult[3] != BLEND_NONE && !IsPixEqual(src[0], src[8])) ||
				 (IsPixEqual(src[4], src[3]) && IsPixEqual(src[3], src[2]) && IsPixEqual(src[2], src[1]) && IsPixEqual(src[1], src[8]) && !IsPixEqual(src[0], src[2])) ) );
		
		vec4 blendPix = ( DistYCbCr(src[0], src[1]) <= DistYCbCr(src[0], src[3]) ) ? src[1] : src[3];
		dst[10] = mix(dst[10], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[11] = mix(dst[11], blendPix, (needBlend && doLineBlend) ? ((haveSteepLine) ? 0.750 : ((haveShallowLine) ? 0.250 : 0.000)) : 0.000);
		dst[12] = mix(dst[12], blendPix, (needBlend && doLineBlend) ? ((!haveShallowLine && !haveSteepLine) ? 0.500 : 1.000) : 0.000);
		dst[13] = mix(dst[13], blendPix, (needBlend && doLineBlend) ? ((haveShallowLine) ? 0.750 : ((haveSteepLine) ? 0.250 : 0.000)) : 0.000);
		dst[14] = mix(dst[14], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);
		dst[25] = mix(dst[25], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[26] = mix(dst[26], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.750 : 0.000);
		dst[27] = mix(dst[27], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 1.000 : 0.000);
		dst[28] = mix(dst[28], blendPix, (needBlend) ? ((doLineBlend) ? ((haveSteepLine) ? 1.000 : ((haveShallowLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[29] = mix(dst[29], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[30] = mix(dst[30], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.9711013910) : 0.000);
		dst[31] = mix(dst[31], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[32] = mix(dst[32], blendPix, (needBlend) ? ((doLineBlend) ? ((haveShallowLine) ? 1.000 : ((haveSteepLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[33] = mix(dst[33], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 1.000 : 0.000);
		dst[34] = mix(dst[34], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.750 : 0.000);
		dst[35] = mix(dst[35], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);
		
		dist_01_04 = DistYCbCr(src[7], src[2]);
		dist_03_08 = DistYCbCr(src[1], src[6]);
		haveShallowLine = (STEEP_DIRECTION_THRESHOLD * dist_01_04 <= dist_03_08) && (!eq(src[0], src[2])) && (!eq(src[3], src[2]));
		haveSteepLine   = (STEEP_DIRECTION_THRESHOLD * dist_03_08 <= dist_01_04) && (!eq(src[0], src[6])) && (!eq(src[5], src[6]));
		needBlend = (blendResult[1] != BLEND_NONE);
		doLineBlend = (  blendResult[1] >= BLEND_DOMINANT ||
			  !((blendResult[0] != BLEND_NONE && !IsPixEqual(src[0], src[2])) ||
				(blendResult[2] != BLEND_NONE && !IsPixEqual(src[0], src[6])) ||
				(IsPixEqual(src[2], src[1]) && IsPixEqual(src[1], src[8]) && IsPixEqual(src[8], src[7]) && IsPixEqual(src[7], src[6]) && !IsPixEqual(src[0], src[8])) ) );
		
		blendPix = ( DistYCbCr(src[0], src[7]) <= DistYCbCr(src[0], src[1]) ) ? src[7] : src[1];
		dst[ 7] = mix(dst[ 7], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[ 8] = mix(dst[ 8], blendPix, (needBlend && doLineBlend) ? ((haveSteepLine) ? 0.750 : ((haveShallowLine) ? 0.250 : 0.000)) : 0.000);
		dst[ 9] = mix(dst[ 9], blendPix, (needBlend && doLineBlend) ? ((!haveShallowLine && !haveSteepLine) ? 0.500 : 1.000) : 0.000);
		dst[10] = mix(dst[10], blendPix, (needBlend && doLineBlend) ? ((haveShallowLine) ? 0.750 : ((haveSteepLine) ? 0.250 : 0.000)) : 0.000);
		dst[11] = mix(dst[11], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);
		dst[20] = mix(dst[20], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[21] = mix(dst[21], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.750 : 0.000);
		dst[22] = mix(dst[22], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 1.000 : 0.000);
		dst[23] = mix(dst[23], blendPix, (needBlend) ? ((doLineBlend) ? ((haveSteepLine) ? 1.000 : ((haveShallowLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[24] = mix(dst[24], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[25] = mix(dst[25], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.9711013910) : 0.000);
		dst[26] = mix(dst[26], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[27] = mix(dst[27], blendPix, (needBlend) ? ((doLineBlend) ? ((haveShallowLine) ? 1.000 : ((haveSteepLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[28] = mix(dst[28], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 1.000 : 0.000);
		dst[29] = mix(dst[29], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.750 : 0.000);
		dst[30] = mix(dst[30], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);

		dist_01_04 = DistYCbCr(src[5], src[8]);
		dist_03_08 = DistYCbCr(src[7], src[4]);
		haveShallowLine = (STEEP_DIRECTION_THRESHOLD * dist_01_04 <= dist_03_08) && (!eq(src[0], src[8])) && (!eq(src[1], src[8]));
		haveSteepLine   = (STEEP_DIRECTION_THRESHOLD * dist_03_08 <= dist_01_04) && (!eq(src[0], src[4])) && (!eq(src[3], src[4]));
		needBlend = (blendResult[0] != BLEND_NONE);
		doLineBlend = (  blendResult[0] >= BLEND_DOMINANT ||
			  !((blendResult[3] != BLEND_NONE && !IsPixEqual(src[0], src[8])) ||
				(blendResult[1] != BLEND_NONE && !IsPixEqual(src[0], src[4])) ||
				(IsPixEqual(src[8], src[7]) && IsPixEqual(src[7], src[6]) && IsPixEqual(src[6], src[5]) && IsPixEqual(src[5], src[4]) && !IsPixEqual(src[0], src[6])) ) );
		
		blendPix = ( DistYCbCr(src[0], src[5]) <= DistYCbCr(src[0], src[7]) ) ? src[5] : src[7];
		dst[ 4] = mix(dst[ 4], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[ 5] = mix(dst[ 5], blendPix, (needBlend && doLineBlend) ? ((haveSteepLine) ? 0.750 : ((haveShallowLine) ? 0.250 : 0.000)) : 0.000);
		dst[ 6] = mix(dst[ 6], blendPix, (needBlend && doLineBlend) ? ((!haveShallowLine && !haveSteepLine) ? 0.500 : 1.000) : 0.000);
		dst[ 7] = mix(dst[ 7], blendPix, (needBlend && doLineBlend) ? ((haveShallowLine) ? 0.750 : ((haveSteepLine) ? 0.250 : 0.000)) : 0.000);
		dst[ 8] = mix(dst[ 8], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);
		dst[35] = mix(dst[35], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[16] = mix(dst[16], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.750 : 0.000);
		dst[17] = mix(dst[17], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 1.000 : 0.000);
		dst[18] = mix(dst[18], blendPix, (needBlend) ? ((doLineBlend) ? ((haveSteepLine) ? 1.000 : ((haveShallowLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[19] = mix(dst[19], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[20] = mix(dst[20], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.9711013910) : 0.000);
		dst[21] = mix(dst[21], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[22] = mix(dst[22], blendPix, (needBlend) ? ((doLineBlend) ? ((haveShallowLine) ? 1.000 : ((haveSteepLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[23] = mix(dst[23], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 1.000 : 0.000);
		dst[24] = mix(dst[24], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.750 : 0.000);
		dst[25] = mix(dst[25], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);
		
		
		dist_01_04 = DistYCbCr(src[3], src[6]);
		dist_03_08 = DistYCbCr(src[5], src[2]);
		haveShallowLine = (STEEP_DIRECTION_THRESHOLD * dist_01_04 <= dist_03_08) && (!eq(src[0], src[6])) && (!eq(src[7], src[6]));
		haveSteepLine   = (STEEP_DIRECTION_THRESHOLD * dist_03_08 <= dist_01_04) && (!eq(src[0], src[2])) && (!eq(src[1], src[2]));
		needBlend = (blendResult[3] != BLEND_NONE);
		doLineBlend = (  blendResult[3] >= BLEND_DOMINANT ||
			  !((blendResult[2] != BLEND_NONE && !IsPixEqual(src[0], src[6])) ||
				(blendResult[0] != BLEND_NONE && !IsPixEqual(src[0], src[2])) ||
				(IsPixEqual(src[6], src[5]) && IsPixEqual(src[5], src[4]) && IsPixEqual(src[4], src[3]) && IsPixEqual(src[3], src[2]) && !IsPixEqual(src[0], src[4])) ) );
		
		blendPix = ( DistYCbCr(src[0], src[3]) <= DistYCbCr(src[0], src[5]) ) ? src[3] : src[5];
		dst[13] = mix(dst[13], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[14] = mix(dst[14], blendPix, (needBlend && doLineBlend) ? ((haveSteepLine) ? 0.750 : ((haveShallowLine) ? 0.250 : 0.000)) : 0.000);
		dst[15] = mix(dst[15], blendPix, (needBlend && doLineBlend) ? ((!haveShallowLine && !haveSteepLine) ? 0.500 : 1.000) : 0.000);
		dst[ 4] = mix(dst[ 4], blendPix, (needBlend && doLineBlend) ? ((haveShallowLine) ? 0.750 : ((haveSteepLine) ? 0.250 : 0.000)) : 0.000);
		dst[ 5] = mix(dst[ 5], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);
		dst[30] = mix(dst[30], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.250 : 0.000);
		dst[31] = mix(dst[31], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 0.750 : 0.000);
		dst[32] = mix(dst[32], blendPix, (needBlend && doLineBlend && haveSteepLine) ? 1.000 : 0.000);
		dst[33] = mix(dst[33], blendPix, (needBlend) ? ((doLineBlend) ? ((haveSteepLine) ? 1.000 : ((haveShallowLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[34] = mix(dst[34], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[35] = mix(dst[35], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.9711013910) : 0.000);
		dst[16] = mix(dst[16], blendPix, (needBlend) ? ((doLineBlend) ? 1.000 : 0.4236372243) : 0.000);
		dst[17] = mix(dst[17], blendPix, (needBlend) ? ((doLineBlend) ? ((haveShallowLine) ? 1.000 : ((haveSteepLine) ? 0.750 : 0.500)) : 0.05652034508) : 0.000);
		dst[18] = mix(dst[18], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 1.000 : 0.000);
		dst[19] = mix(dst[19], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.750 : 0.000);
		dst[20] = mix(dst[20], blendPix, (needBlend && doLineBlend && haveShallowLine) ? 0.250 : 0.000);
		
	}
	
		vec4 res = mix( mix( mix( mix( mix( mix(dst[20], dst[21], step(one_sixth, f.x) ), dst[22], step(two_sixth, f.x) ), mix( mix(dst[23], dst[24], step(four_sixth, f.x) ), dst[25], step(five_sixth, f.x) ), step(0.50, f.x) ),
	                                  mix( mix( mix(dst[19], dst[ 6], step(one_sixth, f.x) ), dst[ 7], step(two_sixth, f.x) ), mix( mix(dst[ 8], dst[ 9], step(four_sixth, f.x) ), dst[26], step(five_sixth, f.x) ), step(0.50, f.x) ), step(one_sixth, f.y) ),
	                                  mix( mix( mix(dst[18], dst[ 5], step(one_sixth, f.x) ), dst[ 0], step(two_sixth, f.x) ), mix( mix(dst[ 1], dst[10], step(four_sixth, f.x) ), dst[27], step(five_sixth, f.x) ), step(0.50, f.x) ), step(two_sixth, f.y) ),
	                        mix( mix( mix( mix( mix(dst[17], dst[ 4], step(one_sixth, f.x) ), dst[ 3], step(two_sixth, f.x) ), mix( mix(dst[ 2], dst[11], step(four_sixth, f.x) ), dst[28], step(five_sixth, f.x) ), step(0.50, f.x) ),
	                                  mix( mix( mix(dst[16], dst[15], step(one_sixth, f.x) ), dst[14], step(two_sixth, f.x) ), mix( mix(dst[13], dst[12], step(four_sixth, f.x) ), dst[29], step(five_sixth, f.x) ), step(0.50, f.x) ), step(four_sixth, f.y) ),
	                                  mix( mix( mix(dst[35], dst[34], step(one_sixth, f.x) ), dst[33], step(two_sixth, f.x) ), mix( mix(dst[32], dst[31], step(four_sixth, f.x) ), dst[30], step(five_sixth, f.x) ), step(0.50, f.x) ), step(five_sixth, f.y) ),
	                     step(0.50, f.y) );

	// 收紧过渡带 (= 当初离线 6 倍流水线的 tighten): 软边收成约 1 像素宽的抗锯齿边
	float a = clamp((res.a - 0.3) / 0.4, 0.0, 1.0);
	ivec2 csz = textureSize(color6, 0);
	COLOR = vec4(texelFetch(color6, clamp(ivec2(floor(UV * vec2(csz))), ivec2(0), csz - 1), 0).rgb, a);
}
