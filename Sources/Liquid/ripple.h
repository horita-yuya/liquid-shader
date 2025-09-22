#ifndef ripple_h
#define ripple_h

#include "utils.h"

using namespace metal;

struct RippleParams {
  float2 uSize;
  float thickness;
  float refractiveIndex;
  float chromaticAberration;
  float lightAngle;
  float lightIntensity;
  float ambientStrength;
  float gaussianBlur;
  float saturation;
  float lightness;
  float2 shapeCenter;
  float shapeRadius;
  float time;

  int rippleCount;
  float rippleAmplitude;
  float rippleFrequencyHz;
  float rippleSpeedPxPerSec;
  float rippleDecayTime;
  float rippleDecayDist;
  float rippleNormalScale;

  // fresnel
  float reflectStrength;
  float reflectDistancePx;
  float specularIntensity;
  float specularShininess;
  float envRotation;

  float ior;
};

struct VertexIn {
  float2 pos;
  float2 uv;
};

struct Varyings {
  float4 position [[position]];
  float2 uv;
};

struct CompositeRipple {
  float h;
  float2 grad;
};

inline float rippleIntensity(CompositeRipple r) {
  return clamp(abs(r.h) * 2.0f + length(r.grad) * 0.5f, 0.0f, 1.0f);
}

inline CompositeRipple composeRipplePixel(float2 pPx, constant RippleParams& u,
                                          constant float4* rippleData,
                                          int count) {
  CompositeRipple acc = {0.0f, float2(0.0)};

  // rad/s
  float omega = TWO_PI * u.rippleFrequencyHz;
  // px/s
  float v = max(1.0f, u.rippleSpeedPxPerSec);

  for (int i = 0; i < count; ++i) {
    float2 cUV = rippleData[i].xy;
    float t0 = rippleData[i].z;
    float dt = u.time - t0;

    if (dt <= 0.0f) {
      continue;
    }

    float2 cPx = cUV * u.uSize;
    float2 d = pPx - cPx;
    float r = length(d);

    if (r <= 1e-6f) {
      continue;
    }

    float tau = dt - r / v;
    if (tau <= 0.0f) {
      continue;
    }

    float A = u.rippleAmplitude * exp(-u.rippleDecayTime * tau) *
              exp(-u.rippleDecayDist * r);
    float phase = omega * tau;
    float h = A * sin(phase);

    float dAdr = A * (u.rippleDecayTime / v - u.rippleDecayDist);
    float dHdr = dAdr * sin(phase) + A * (omega * cos(phase)) * (-1.0f / v);

    float2 grad = dHdr * (d / r);

    acc.h += h;
    acc.grad += grad;
  }
  return acc;
}

#endif
