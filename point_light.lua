-- Point light shaddow mapping with VSM

local m = {}

m.gpu = {
  position = vector(50, 20, 0),
  light_color = vector(1, 0.7, 0.7),
  shadow_color = vector(0.3, 0.3, 0.3),
  max_distance = 5000.0,
  falloff_exp = -7,
}


local depth_writer = lovr.graphics.newShader('unlit', [[
uniform float ShadowFarPlane;
uniform vec3 ShadowLightWorld;

vec4 lovrmain() {
  float dist = distance(ShadowLightWorld, PositionWorld);
  float depthNormalized = dist / ShadowFarPlane;
  depthNormalized = clamp(depthNormalized, 0.0, 1.0);
  float depthSquared = depthNormalized * depthNormalized;
  return vec4(depthNormalized, depthSquared, 1., 1.); // Store in R and G channels
}
]], {label = 'point_light_shadow'})


local perspective = lovr.math.newMat4():perspective(math.pi / 2, 1, 0.01, m.gpu.max_distance)
local transforms = {
  Mat4():lookAt(vector(0, 0, 0), vector(1, 0, 0), vector(0, 1, 0)),
  Mat4():lookAt(vector(0, 0, 0), vector(-1, 0, 0), vector(0, 1, 0)),
  Mat4():lookAt(vector(0, 0, 0), vector(0, 1, 0), vector(0, 0, -1)),
  Mat4():lookAt(vector(0, 0, 0), vector(0, -1, 0), vector(0, 0, 1)),
  Mat4():lookAt(vector(0, 0, 0), vector(0, 0, 1), vector(0, 1, 0)),
  Mat4():lookAt(vector(0, 0, 0), vector(0, 0, -1), vector(0, 1, 0))
}


function m.load(resolution, position)
  m.resolution = resolution or 256
  m.gpu.position = position or m.gpu.position
  m.texture = lovr.graphics.newTexture(m.resolution, m.resolution, 6,
    { type = 'cube', format = 'rg32f', linear = true, mipmaps = false, usage = { 'render', 'sample', 'transfer' } })
  m.pass = lovr.graphics.newPass { m.texture }
  return m
end

function m.getPass()
  m.pass:reset()
  -- texture uses RG channels for result, still uses depth-testing with depth channel
  m.pass:setClear({ 1, 1, 1, 1, depth = 1 })
  local pos = m.gpu.position
  for i, transform in ipairs(transforms) do
    transform[13], transform[14], transform[15] = m.gpu.position:unpack()
    m.pass:setViewPose(i, transform)
    m.pass:setProjection(i, perspective)
  end
  m.pass:setDepthTest('<=')
  m.pass:setFaceCull('back')
  m.pass:setShader(depth_writer)
  m.pass:send('ShadowLightWorld', m.gpu.position)
  m.pass:send('ShadowFarPlane', m.gpu.max_distance)
  return m.pass -- pass is prepared for receiving geometry; must be submitted by user
end

function m.send(pass)
  pass:send('ShadowDepthBuffer', m.texture)
  pass:send('ShadowFarPlane', m.gpu.max_distance)
  pass:send('ShadowQuadraticFalloffExp', m.gpu.falloff_exp)
  pass:send('LightPositionWorld', m.gpu.position)
  pass:send('LightColor', m.gpu.light_color)
  pass:send('ShadowColor', m.gpu.shadow_color)
end


return m
