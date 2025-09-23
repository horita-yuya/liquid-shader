#ifndef fresnel_h
#define fresnel_h

#define USE_FRESNEL 1

using namespace metal;

// Full Customize
// inline float fresnelSchlick(float cosTheta, float bias, float scale,
//                            float power) {
//  float oneMinus = 1.0f - clamp(cosTheta, 0.0f, 1.0f);
//  return clamp(bias + scale * pow(oneMinus, power), 0.0f, 1.0f);
//}

inline float fresnelSchlickFromIOR(float cosTheta, float ior) {
  // https://en.wikipedia.org/wiki/Schlick%27s_approximation
  // relative to vacuum
  float r0 = (1.0f - ior) / (1.0f + ior);
  float m = 1.0f - saturate(cosTheta);
  return r0 + (1.0f - r0) * pow(m, 5.0f);
}

#endif
