#ifndef reflaction_h
#define reflaction_h

using namespace metal;

float4 refraction(float2 screenUV, float3 normal, float height, float thickness,
                  float refractiveIndex, float chromaticAberration,
                  float2 uSize, texture2d<float> backgroundTexture,
                  sampler samp, float blurRadius);

#endif
