#ifndef utils_h
#define utils_h

using namespace metal;

static constant float TWO_PI = 6.2831853f;

inline float3 normalFromGrad(float2 g, float scale) {
  return normalize(float3(-scale * g, 1.0));
}

inline float2x2 rotate2d(float a) {
  return float2x2(cos(a), -sin(a), sin(a), cos(a));
}

inline float3 applySaturationLightness(float3 color, float saturation,
                                       float lightness) {
  float luminance = dot(color, float3(0.299, 0.587, 0.114));
  float3 saturated = mix(float3(luminance), color, saturation);
  float3 adjusted = saturated * lightness;
  return clamp(adjusted, float3(0.0), float3(1.0));
}

float4 applyKawaseBlur(texture2d<float> tex, sampler samp, float2 uv,
                       float2 texelSize, float blurRadius);

#endif
