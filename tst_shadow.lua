-- Shadow demo: point light VSM on simple primitives (~40 lines of Lua + shader)
local light = require'point_light'

light.load(512)
light.gpu.falloff_exp = -7
light.gpu.light_color = vector(0.95, 0.85, 0.9)
light.gpu.shadow_color = vector(0.2, 0.15, 0.2)

local shader = lovr.graphics.newShader('unlit', [[
/*** point light shadow receiving ***/
layout(constant_id = 2) const bool flag_receive_shadow = true;
layout(set = 2, binding = 1) uniform textureCube ShadowDepthBuffer;
uniform vec3 LightPositionWorld;
uniform vec3 LightColor;
uniform vec3 ShadowColor;
uniform float ShadowQuadraticFalloffExp;
uniform float ShadowFarPlane;

float reduceBleeding(float p_max, float amount) {
  return clamp((p_max - amount) / (1. - amount), 0., 1.);
}

float calculateVSMShadow(vec2 moments, float currentDepth) {
  float bias = 0.0001;
  currentDepth -= bias;
  if (currentDepth <= moments.x) // fully lit
      return 1.0;
  float variance = moments.y - (moments.x * moments.x);
  variance = max(variance, 1e-6);
  float d = currentDepth - moments.x;
  // Chebyshev's inequality: P(x >= currentDepth) <= variance / (variance + d^2)
  // This gives an upper bound on the probability that the occluder depth is
  // greater than or equal to the current depth, i.e., the probability of *not* being shadowed.
  float p_max = variance / (variance + d * d);
  return p_max;
}

void addShadow(inout vec4 color) {
  if (!flag_receive_shadow) return;
  vec3 lightVec = PositionWorld - LightPositionWorld;
  float distSq = dot(lightVec, lightVec);
  float dist = sqrt(distSq);

  float currentDepthNormalized = dist / ShadowFarPlane;
  vec3 lookupDir = normalize(vec3(-lightVec.x, lightVec.y, lightVec.z));
  vec2 moments = getPixel(ShadowDepthBuffer, lookupDir).rg;
  float lit = calculateVSMShadow(moments, currentDepthNormalized);
  lit = reduceBleeding(lit, 0.15);
  float attenuation = 1.0 / (1.0 + pow(10., ShadowQuadraticFalloffExp) * distSq);
  color.rgb = color.rgb * ShadowColor + color.rgb * lit * attenuation * LightColor;

  vec3 N = normalize(Normal);
  vec3 V = normalize(CameraPositionWorld - PositionWorld);
  vec3 L = normalize(LightPositionWorld - PositionWorld);
  float NdotL = max(dot(N, L), 0.0);
  float NdotV = max(dot(N, V), 0.0);
  if (NdotL <= 0.0 || NdotV <= 0.0) return;

  color.rgb += NdotL * lit * LightColor * attenuation * 0.2;
}

vec4 lovrmain() {
  vec4 color = DefaultColor;
  addShadow(color);
  return color;
}

]])


local function scene(pass)
  local t = lovr.timer.getTime()
  lovr.math.setRandomSeed(0)
  pass:box(0, -1, 0, 50, 2, 50)
  for i = 1, 20 do
    local s = 0.1 + 0.4 * lovr.math.random()
    pass:setColor(s, s, s)
    pass:sphere(
      (lovr.math.random() - 0.5) * 30,
      lovr.math.random() * 30,
      (lovr.math.random() - 0.5) * 30,
      0.5)
  end
  for i = 1, 20 do
    local s = 0.1 + 0.4 * lovr.math.random()
    pass:setColor(s, s, s)
    pass:box(
      (lovr.math.random() - 0.5) * 30,
      lovr.math.random() * 30,
      (lovr.math.random() - 0.5) * 30,
      0.5 + 1.5 * lovr.math.random(),
      0.5 + 1.5 * lovr.math.random(),
      0.5 + 1.5 * lovr.math.random())
  end
end


function lovr.draw(wpass)
  if lovr.system .isKeyDown('f1') then
    light.gpu.position = mat4(wpass:getViewPose(1)) * vector(0, 10, -30)
  end

  local pass

    -- Shadow pass
  pass = light.getPass()
  local spass = pass
  scene(pass)
  lovr.graphics.submit(spass)

  pass = wpass
  pass:setShader(shader)
  light.send(pass)
  scene(pass)
  pass:setColor(0.2, 0.2, 0.2)
  pass:sphere(0, 0, 0, -100)
end