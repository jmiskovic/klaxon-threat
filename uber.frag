/*** spherical harmonics shading ***/
vec3 evaluateLightProbe(vec3 probe[9], vec3 dir) {
  return
    .88622692545276 * probe[0] +
    1.0233267079465 * probe[1] * dir.y +
    1.0233267079465 * probe[2] * dir.z +
    1.0233267079465 * probe[3] * dir.x +
    .85808553080978 * probe[4] * dir.x * dir.y +
    .85808553080978 * probe[5] * dir.y * dir.z +
    .24770795610038 * probe[6] * (3. * dir.z * dir.z - 1.) +
    .85808553080978 * probe[7] * dir.x * dir.z +
    .42904276540489 * probe[8] * (dir.x * dir.x - dir.y * dir.y);
}

const vec3 probe[9] = { // extracted from yellowish surrounding and purple floor
  vec3( 0.3264,  0.3535,  0.2181), vec3( 0.4508,  0.4978, 0.3105), vec3(-0.0508, -0.0318,  0.0072),
  vec3(-0.1103, -0.0691,  0.0156), vec3(-0.1914, -0.1199, 0.0270), vec3(-0.0946, -0.0593,  0.0133),
  vec3(-0.1767, -0.2041, -0.1381), vec3( 0,       0,      0),      vec3(-0.3062, -0.3535, -0.2392)
};

void addSH(inout vec4 color, float intensity, vec3 normal) {
  color.rgb *= 1. + intensity * (evaluateLightProbe(probe, normalize(normal)) - 1.);
}

void addShading(inout vec4 color) {
  addSH(color, 0.8, Normal);
}

// portable pow solves undefined bh for negative x values across platforms
float ppow(float x, float y) {
  float x_clamp = max(x, 1e-8);
  return exp(log(x_clamp) * y);
}

/*** distance fog ***/
const float FogStrength = 0.3;
const float FogDistance = 0.2;
const float FogDistanceMul = 0.5;
const float FogPow = 0.8;
//uniform vec3 FogColor;
vec3 FogColor = vec3(0.8, 0.8, 0.8);

void addAtanPowFog(inout vec4 color, float fogDensity, float fogDistance, float fogDistanceMul, float fogPow, vec3 fogColor) {
  float d = length(PositionWorld - CameraPositionWorld);
  float fogAmount = atan(ppow(d * fogDistanceMul, fogPow) * fogDensity * 0.001) / fogDistance;
  color.rgb = mix(color.rgb, fogColor, clamp(fogAmount, 0., 1.));
}


void addFog(inout vec4 color) {
  addAtanPowFog(color, FogStrength, FogDistance, FogDistanceMul, FogPow, FogColor);
}



/*** surface texture ***/
layout(location = 6) in vec3 PositionWrapped;


uniform texture2D surface_texture;

vec4 triplanar( in texture2D t, in vec3 p, in vec3 n, in float k ) {
    vec4 x = texture( sampler2D(t, Sampler), p.yz );
    vec4 y = texture( sampler2D(t, Sampler), p.zx );
    vec4 z = texture( sampler2D(t, Sampler), p.xy );
    vec3 w = pow( abs(n), vec3(k) );
    return (x*w.x + y*w.y + z*w.z) / (w.x + w.y + w.z);
}

void addSurfaceTexture(inout vec4 color) {
  color.rgb *= 1. + 1.5 * triplanar(surface_texture, PositionWrapped * 0.0005, normalize(Normal), 2).b;
}



/*** textured terrain ***/
layout(constant_id = 0) const bool flag_textured_terrain = false;
uniform texture2D TerrainTexture;
layout(location = 7) in vec2 TerrainUV;
layout(location = 8) in float gloss;

void addTerrainTexture(inout vec4 color) {
  color = getPixel(TerrainTexture, TerrainUV);
}



/*** text handling ***/
in flat int isFontDraw;
in vec3 normal;

float screenPxRange() {
  vec2 screenTexSize = vec2(1.) / fwidth(UV);
  return max(.5 * dot(Material.sdfRange, screenTexSize), 1.);
}

float median(float r, float g, float b) {
  return max(min(r, g), min(max(r, g), b));
}



/*** composed uber shader ***/
vec4 lovrmain() {
  vec4 color = DefaultColor;

  if (isFontDraw == 1) {
    color.rgb = Color.rgb;
    vec3 msdf = getPixel(ColorTexture, UV).rgb;
    float sdf = median(msdf.r, msdf.g, msdf.b);
    float screenPxDistance = screenPxRange() * (sdf - .5);
    float alpha = clamp(screenPxDistance + .5, 0., 1.);
    if (alpha <= 0.) discard;
    color.a = alpha;
    return color;
  }

  color.a = 1.0;

  addShading(color);
  addSurfaceTexture(color);
  addFog(color);

  return color;
}
