#include <metal_stdlib>

#include "fresnel.h"
#include "reflaction.h"
#include "ripple.h"
#include "utils.h"

using namespace metal;

#define MAX_RIPPLES 16

inline float3 sampleScreenReflection(float2 uv, float3 N,
                                     constant RippleParams& u,
                                     texture2d<float> tex, sampler samp) {
  float3 I = float3(0.0, 0.0, -1.0);
  float3 R = reflect(I, normalize(N));

  float c = cos(u.envRotation), s = sin(u.envRotation);
  float2 Rxy = float2(R.x * c - R.y * s, R.x * s + R.y * c);
  float2 off = uv + (Rxy * (u.reflectDistancePx / u.uSize));

  return tex.sample(samp, clamp(off, float2(0.0), float2(1.0))).rgb;
}

vertex Varyings vsMain(uint vid [[vertex_id]],
                       constant VertexIn* vtx [[buffer(0)]]) {
  Varyings o;
  VertexIn v = vtx[vid];
  o.position = float4(v.pos, 0.0, 1.0);
  o.uv = v.uv;
  return o;
}

fragment float4 fsRipple(Varyings in [[stage_in]],
                         constant RippleParams& u [[buffer(1)]],
                         constant float4* rippleB [[buffer(2)]],
                         texture2d<float> bgTex [[texture(0)]],
                         sampler samp [[sampler(0)]]) {
  float2 uv = in.uv;
  float2 pPx = uv * u.uSize;

  CompositeRipple rip =
      composeRipplePixel(pPx, u, rippleB, min(u.rippleCount, (int)MAX_RIPPLES));
  float3 N = normalFromGrad(rip.grad, u.rippleNormalScale);

  float intensity = rippleIntensity(rip);
  float blurNow = u.gaussianBlur * intensity;
  float4 refr =
      refraction(uv, N, rip.h, 0.0f, u.refractiveIndex, u.chromaticAberration,
                 u.uSize, bgTex, samp, blurNow);

  float3 refl = sampleScreenReflection(uv, N, u, bgTex, samp);

  float cosVN =
      clamp(dot(normalize(float3(0, 0, 1)), normalize(N)), 0.0f, 1.0f);
  float rf = fresnelSchlickFromIOR(cosVN, u.ior);
  float3 water = mix(refr.rgb, refl, rf);

  water = applySaturationLightness(water, u.saturation, u.lightness);

  return float4(water, 1.0);
}
