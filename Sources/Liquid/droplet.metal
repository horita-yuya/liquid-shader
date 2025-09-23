#include <metal_stdlib>

#include "droplet.h"
#include "fresnel.h"
#include "reflaction.h"

using namespace metal;

inline float sphericalCapHeight(float r, float a, float H) {
  if (r >= a || H <= 0.0f) return 0.0f;
  float R = (a * a + H * H) / (2.0f * H);
  float t = max(1e-6f, R * R - r * r);
  return H - (R - sqrt(t));
}

inline float2 sphericalCapGrad(float2 d, float a, float H) {
  float r = length(d);
  if (r < 1e-6f || r >= a || H <= 0.0f) return float2(0.0);
  float R = (a * a + H * H) / (2.0f * H);
  float denom = sqrt(max(1e-6f, R * R - r * r));
  return d / denom;
}

inline float3 sampleReflectionSimple(float2 uv, float3 N, float2 uSize,
                                     texture2d<float> bg, sampler sp,
                                     float distPx) {
  float3 I = float3(0, 0, -1);
  float3 R = reflect(I, normalize(N));
  float2 off = uv + (R.xy * (distPx / uSize));
  return bg.sample(sp, clamp(off, float2(0.0), float2(1.0))).rgb;
}

struct MaskInfo {
  float alpha;
  float2 centerPx;
  float radiusPx;
  float2 pPx;
  float2 d;
  float r;
};

inline MaskInfo step_mask(float2 uv, constant DropletParams& u) {
  MaskInfo mi;
  mi.centerPx = u.shapeCenter * u.uSize;
  mi.radiusPx = u.shapeRadius * min(u.uSize.x, u.uSize.y);
  mi.pPx = uv * u.uSize;
  mi.d = mi.pPx - mi.centerPx;
  mi.r = length(mi.d);
  mi.alpha = 1.0;
  return mi;
}

struct GeoInfo {
  float heightPx;
  float3 N;
  float2 grad;
};

inline GeoInfo step_geometry(const MaskInfo mi, float thickness) {
  GeoInfo g;
  float a = max(1.0f, mi.radiusPx);
  g.heightPx = sphericalCapHeight(mi.r, a, thickness);
  g.grad = sphericalCapGrad(mi.d, a, thickness);
  const float NORMAL_SCALE = 10.0f;
  g.N = normalize(float3(-NORMAL_SCALE * g.grad, 1.0));
  return g;
}

inline float4 step_refraction(float2 uv, const GeoInfo g, float rOverA,
                              constant DropletParams& u, texture2d<float> bg,
                              sampler sp) {
  float slopeF = saturate(length(g.grad));
  float radialF = saturate(rOverA);
  float grazingF = max(slopeF, radialF);

  const float EDGE_BOOST = 1.8f;
  const float EDGE_POWER = 2.2f;
  float nonLinear = 1.0f + EDGE_BOOST * pow(grazingF, EDGE_POWER);

  const float REFRACTION_HEIGHT_SCALE = 10.0f;
  float thicknessProxy = g.heightPx * REFRACTION_HEIGHT_SCALE * nonLinear;

  float cosV = max(0.0f, dot(normalize(g.N), float3(0, 0, 1)));
  float fresnelLF = 1.0f - cosV;
  float blurBase = u.gaussianBlur;
  float blurNow =
      blurBase * (0.35f + 0.65f * slopeF) * (1.0f + 1.6f * fresnelLF);

  return refraction(uv, g.N, g.heightPx, thicknessProxy, u.ior,
                    u.chromaticAberration, u.uSize, bg, sp, blurNow);
}

struct ReflInfo {
  float3 rgb;
  float F;
};

inline ReflInfo step_reflection(float2 uv, const GeoInfo g,
                                constant DropletParams& u, texture2d<float> bg,
                                sampler sp) {
  ReflInfo ri;

  const float REFLECT_DIST_PX = 50.0f;
  float3 refl =
      sampleReflectionSimple(uv, g.N, u.uSize, bg, sp, REFLECT_DIST_PX);

  float cosT = max(0.0f, dot(normalize(g.N), float3(0, 0, 1)));
  float F = fresnelSchlickFromIOR(cosT, u.ior);

  const float REFLECT_GAIN = 1.8f;
  ri.rgb = refl * REFLECT_GAIN;
  ri.F = F;
  return ri;
}

inline float3 step_rim(const MaskInfo mi, const GeoInfo g,
                       constant DropletParams& u) {
  float a = max(1.0f, mi.radiusPx);
  float sd = mi.r - a;
  float rimSigma = 2.2f;
  float rim = exp(-(sd * sd) / (2.0f * rimSigma * rimSigma));
  float dir = pow(max(0.0f, dot(normalize(g.N.xy),
                                float2(cos(u.lightAngle), sin(u.lightAngle)))),
                  2.0f);
  float amt = (0.5f * u.ambientStrength + 1.1f * u.lightIntensity * dir) * rim;
  return float3(amt);
}

inline float3 step_contactShadow(const MaskInfo mi, constant DropletParams& u) {
  float2 L = float2(cos(u.lightAngle), sin(u.lightAngle));
  float r2 = dot(mi.d, mi.d);
  float a = max(1.0f, mi.radiusPx);
  float axial = max(0.0f, dot(normalize(mi.d + 1e-5f), -L));
  float gauss = exp(-r2 / (2.0f * (0.28f * a) * (0.28f * a)));
  float amt = 0.08f * (0.4f + 0.6f * axial) * gauss;
  return float3(-amt);
}

inline float3 getHighlightColor(float3 bg, float targetBrightness) {
  float lum = dot(bg, float3(0.299, 0.587, 0.114));
  float3 base = float3(targetBrightness);
  if (lum > 0.001f) base = (bg / lum) * targetBrightness;
  return clamp(base, 0.0f, 1.0f);
}

inline float3 step_sun_glint(const MaskInfo m, const GeoInfo g,
                             constant DropletParams& u, float3 bgRGB) {
  float2 L2 = float2(cos(u.lightAngle), sin(u.lightAngle));
  float3 L = normalize(float3(L2, 0.6));
  float3 V = float3(0, 0, 1);

  float3 Rl = reflect(-L, normalize(g.N));
  float spec = pow(max(0.0f, dot(normalize(Rl), V)), 120.0f);
  spec *= max(0.0f, dot(normalize(g.N), L));

  float a = max(1.0f, m.radiusPx);
  float rOverA = clamp(m.r / a, 0.0f, 1.0f);
  float edgeT = 1.0f - rOverA;
  const float EDGE_WIDTH = 0.045f;
  float edgeMask = exp(-(edgeT * edgeT) / (2.0f * EDGE_WIDTH * EDGE_WIDTH));

  float cosV = max(0.0f, dot(normalize(g.N), V));
  float grazing = pow(1.0f - cosV, 1.6f);

  float3 hiCol = getHighlightColor(bgRGB, 0.98f);
  const float GLINT_GAIN = 2.6f;
  float amp = GLINT_GAIN * max(0.0f, u.lightIntensity);

  return hiCol * (amp * spec * edgeMask * grazing);
}

inline float3 step_composite(float3 bg, float3 refr, const ReflInfo ri,
                             float3 rim, float3 contact) {
  float3 col = mix(refr, ri.rgb, ri.F);
  col += rim;
  col += contact;
  return col;
}

vertex Varyings vsMain2(uint vid [[vertex_id]],
                        constant VertexIn* vtx [[buffer(0)]]) {
  Varyings o;
  VertexIn v = vtx[vid];
  o.position = float4(v.pos, 0.0, 1.0);
  o.uv = v.uv;
  return o;
}

fragment float4 fsDroplet(Varyings in [[stage_in]],
                          constant DropletParams& u [[buffer(1)]],
                          texture2d<float> bgTex [[texture(0)]],
                          sampler samp [[sampler(0)]]) {
  float2 uv = in.uv;

  MaskInfo m = step_mask(uv, u);
  float4 bg = bgTex.sample(samp, uv);
  if (m.alpha < 1e-3f) return bg;

  GeoInfo g = step_geometry(m, u.thickness);

  float rOverA = m.r / max(1.0f, m.radiusPx);
  float4 refr = step_refraction(uv, g, rOverA, u, bgTex, samp);

  ReflInfo ri = step_reflection(uv, g, u, bgTex, samp);
  float3 rim = step_rim(m, g, u);
  float3 cshadow = step_contactShadow(m, u);
  float3 water = step_composite(bg.rgb, refr.rgb, ri, rim, cshadow);

  float4 outC = mix(bg, float4(water, 1.0), m.alpha);
  outC.rgb += step_sun_glint(m, g, u, bg.rgb);

  return outC;
}
