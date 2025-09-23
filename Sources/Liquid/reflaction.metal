#include <metal_stdlib>

#include "reflaction.h"
#include "utils.h"
using namespace metal;

inline float calculateDispersiveIndex(float baseIndex, float chroma,
                                      float lambda) {
  if (chroma < 0.001f) return baseIndex;
  float l2 = lambda * lambda, l4 = l2 * l2;
  float B = chroma * 0.08f * (baseIndex - 1.0f);
  float C = chroma * 0.003f * (baseIndex - 1.0f);
  return baseIndex + B / l2 + C / l4;
}

float4 refraction(float2 screenUV, float3 normal, float height, float thickness,
                  float refractiveIndex, float chromaticAberration,
                  float2 uSize, texture2d<float> backgroundTexture,
                  sampler samp, float blurRadius) {
  float baseHeight = thickness * 8.0f;
  float3 incident = float3(0.0, 0.0, -1.0);
  float4 refractColor;
  float2 texelSize = 1.0f / uSize;

  if (chromaticAberration > 0.001f) {
    float iorR =
        calculateDispersiveIndex(refractiveIndex, chromaticAberration, 0.68f);
    float iorG =
        calculateDispersiveIndex(refractiveIndex, chromaticAberration, 0.55f);
    float iorB =
        calculateDispersiveIndex(refractiveIndex, chromaticAberration, 0.42f);

    float3 refrR = refract(incident, normal, 1.0f / iorR);
    float lenR = (height + baseHeight) / max(0.001f, fabs(refrR.z));
    float2 uvR = screenUV - (refrR.xy * lenR) / uSize;
    float red = (blurRadius > 0.001f)
                    ? applyKawaseBlur(backgroundTexture, samp, uvR, texelSize,
                                      blurRadius)
                          .r
                    : backgroundTexture.sample(samp, uvR).r;

    float3 refrG = refract(incident, normal, 1.0f / iorG);
    float lenG = (height + baseHeight) / max(0.001f, fabs(refrG.z));
    float2 refractionDisplacement = refrG.xy * lenG;
    float2 uvG = screenUV - refractionDisplacement / uSize;
    float4 smpG = (blurRadius > 0.001f)
                      ? applyKawaseBlur(backgroundTexture, samp, uvG, texelSize,
                                        blurRadius)
                      : backgroundTexture.sample(samp, uvG);

    float3 refrB = refract(incident, normal, 1.0f / iorB);
    float lenB = (height + baseHeight) / max(0.001f, fabs(refrB.z));
    float2 uvB = screenUV - (refrB.xy * lenB) / uSize;
    float blue = (blurRadius > 0.001f)
                     ? applyKawaseBlur(backgroundTexture, samp, uvB, texelSize,
                                       blurRadius)
                           .b
                     : backgroundTexture.sample(samp, uvB).b;

    refractColor = float4(red, smpG.g, blue, smpG.a);
  } else {
    float3 refr = refract(incident, normal, 1.0f / refractiveIndex);
    float len = (height + baseHeight) / max(0.001f, fabs(refr.z));
    float2 refractionDisplacement = refr.xy * len;
    float2 uv = screenUV - refractionDisplacement / uSize;
    refractColor = (blurRadius > 0.001f)
                       ? applyKawaseBlur(backgroundTexture, samp, uv, texelSize,
                                         blurRadius)
                       : backgroundTexture.sample(samp, uv);
  }
  return refractColor;
}
