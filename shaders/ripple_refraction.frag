#version 460 core

// ⚠️ 这一行不能省。
//
// Flutter 的 impellerc 默认不启用 include 指令，
// 缺了它 `#include <flutter/runtime_effect.glsl>` 会编译失败，
// FragmentProgram.fromAsset 抛异常 → 加载标记为失败
// → RippleShaderView 永远走「原样显示」分支，
// 表现就是「没有动画，只是普通的变换值」。
#extension GL_GOOGLE_include_directive : enable

#include <flutter/runtime_effect.glsl>

// A12 水波折射着色器（方案 A）。
//
// 前五版水波都是 Canvas 叠加绘制：在组件**上面**画环、画渐变、加色混合。
// 底层像素一个都没动，所以用户始终觉得「像两个图层」「不像波纹」。
// 这是叠加绘制的天花板，不是参数问题。
//
// 片元着色器逐像素重采样纹理，能让**组件内容本身**被拉伸挤压，
// 这才是真正的折射（放大镜）效果。

precision mediump float;

// ⚠️ uniform 的声明顺序必须与 Dart 侧 setFloat 的索引严格一致。
// 顺序错了不会报错，只会得到莫名其妙的画面。
uniform vec2 uSize;        // 0,1  组件尺寸（像素）
uniform float uProgress;   // 2    动画进度 0..1
uniform float uIntensity;  // 3    强度 0..1
uniform float uSquash;     // 4    纵向压缩（扁长组件用）
uniform vec4 uTint;        // 5,6,7,8  高光染色（premultiplied 前的 rgba）
uniform sampler2D uTexture;

out vec4 fragColor;

// 波前在 [0,1] 之间折返：撞到边界原路弹回。
//
// 用户明确要求「像波浪一样碰到壁面会反弹」，
// 瞬时事件需要「敲一下、整个组件荡一荡」的手感。
float waveFront(float t, float phaseOffset) {
    float d = t * 2.5 + phaseOffset;
    float k = floor(d);
    float f = d - k;
    // mod(k,2) 为 0 时外行、为 1 时回弹。
    // mix 的第三参数只在 0/1 取值，等价于分支但无跳转。
    return mix(f, 1.0 - f, mod(k, 2.0));
}

// 环带剖面：单向高斯凸起。
//
// ⚠️ 必须单向（恒非负）。曾用「内侧正、外侧负」的对撞式剖面，
// 两股位移在波前相遇，相邻采样点被压到 2%，
// 内容原地折叠成一团——那不是放大镜，是像素乱挤。
float ringProfile(float dist, float front, float width) {
    float x = (dist - front) / width;
    // 用 step 代替 if-return：部分 GLSL 后端对函数中途 return
    // 的支持参差不齐，无分支写法更安全，也便于编译器展开。
    // step(x, 2.0) 在 |x| <= 2 时为 1，否则为 0。
    float inRange = step(abs(x), 2.0);
    return exp(-3.0 * x * x) * inRange;
}

void main() {
    vec2 fragPos = FlutterFragCoord().xy;
    vec2 uv = fragPos / uSize;

    // 归一化到以中心为原点、边界为 1.0 的空间。
    // 纵向按 uSquash 缩放，让扁长组件的波纹不至于被拉成扁线，
    // 同时保持圆形波的本质（第三版曾让椭圆完全跟随长宽比，
    // 结果环变成 16.7:1 的一条线）。
    vec2 centered = (uv - 0.5) * 2.0;
    centered.y /= max(uSquash, 0.05);
    float dist = length(centered);

    float envelope = pow(max(1.0 - uProgress, 0.0), 1.2);

    vec2 offset = vec2(0.0);
    float glow = 0.0;

    if (envelope > 0.01 && dist > 0.0001) {
        vec2 dir = centered / dist;
        float bandWidth = clamp(0.10 + 0.10 * uIntensity, 0.06, 0.24);
        // 位移上限占半宽的比例。
        //
        // ⚠️ 上限由「采样位置必须同侧单调」决定，实测 0.14 是临界值：
        // 再大就会出现 d(sampleUv)/d(uv) < 0，同一侧的采样点交叉，
        // 内容折叠成一团（网格方案栽过同样的坑）。
        // 取 0.12 留约 15% 余量。
        //
        // 注意径向位移在中心两侧必然反向，那是透镜的固有性质、
        // 不算折叠——判定折叠只能在同一侧内部做。
        float amp = 0.12 * uIntensity * envelope;

        // 三道波错开相位，形成一圈接一圈荡开。
        // 固定 3 次迭代，便于编译器完全展开。
        // 内部不用 continue——改为乘掩码，无分支。
        for (int i = 0; i < 3; i++) {
            float phase = float(i) * 0.22;
            float front = waveFront(uProgress, phase);
            float fade = envelope * max(1.0 - float(i) * 0.3, 0.0);
            float p = ringProfile(dist, front, bandWidth);
            float w = p * fade;

            // 位移恒为「向外」，方向由径向单位向量给出。
            offset += dir * w * amp;
            glow += w;
        }
    }

    // 边缘渐隐：靠近边界时位移趋零，避免采样越界露出空白。
    float edgeFade = clamp((1.0 - dist) / 0.18, 0.0, 1.0);
    offset *= edgeFade;

    // 折射的本质：采样位置偏移。
    // 波前内侧被拉伸（放大）、外侧被压缩（缩小）。
    vec2 sampleUv = uv - offset * 0.5;
    sampleUv = clamp(sampleUv, vec2(0.0), vec2(1.0));

    vec4 color = texture(uTexture, sampleUv);

    // 一层很淡的高光，只是给波峰一点「水面反光」的提示，
    // 不承担主要观感——主角是上面的采样偏移。
    float highlight = clamp(glow, 0.0, 1.0) * 0.18 * uIntensity * edgeFade;
    color.rgb += uTint.rgb * highlight * color.a;

    fragColor = color;
}
