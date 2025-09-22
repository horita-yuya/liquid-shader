#ifndef droplet_h
#define droplet_h

struct VertexIn {
  float2 pos;
  float2 uv;
};

struct Varyings {
  float4 position [[position]];
  float2 uv;
};

struct DropletParams {
  float2 uSize;
  float thickness;
  float ior;
  float chromaticAberration;
  float lightAngle;
  float lightIntensity;
  float ambientStrength;
  float gaussianBlur;
  // normalized
  float2 shapeCenter;
  // normalized
  float shapeRadius;
  float time;
};

#endif
