#include <metal_stdlib>
using namespace metal;

float4 applyKawaseBlur(texture2d<float> tex, sampler samp, float2 uv,
                       float2 texelSize, float blurRadius) {
  if (blurRadius < 0.001f) return tex.sample(samp, uv);
  float4 color = float4(0.0);
  float totalWeight = 0.0;
  float offset = blurRadius;

  float2 offsets1[4] = {float2(-offset, -offset), float2(offset, -offset),
                        float2(-offset, offset), float2(offset, offset)};
  for (uint i = 0; i < 4; i++) {
    float2 suv = uv + offsets1[i] * texelSize;
    if (all(suv >= 0.0) && all(suv <= 1.0)) {
      color += tex.sample(samp, suv);
      totalWeight += 1.0;
    }
  }

  float offset2 = offset * 1.5f;
  float2 offsets2[4] = {float2(0, -offset2), float2(0, offset2),
                        float2(-offset2, 0), float2(offset2, 0)};
  for (uint i = 0; i < 4; i++) {
    float2 suv = uv + offsets2[i] * texelSize;
    if (all(suv >= 0.0) && all(suv <= 1.0)) {
      color += tex.sample(samp, suv) * 0.8f;
      totalWeight += 0.8f;
    }
  }

  float offset3 = offset * 0.7f;
  float2 offsets3[4] = {float2(-offset3, 0), float2(offset3, 0),
                        float2(0, -offset3), float2(0, offset3)};
  for (uint i = 0; i < 4; i++) {
    float2 suv = uv + offsets3[i] * texelSize;
    if (all(suv >= 0.0) && all(suv <= 1.0)) {
      color += tex.sample(samp, suv) * 0.6f;
      totalWeight += 0.6f;
    }
  }

  color += tex.sample(samp, uv) * 2.0f;
  totalWeight += 2.0f;
  return (totalWeight > 0.0f) ? (color / totalWeight) : tex.sample(samp, uv);
}
