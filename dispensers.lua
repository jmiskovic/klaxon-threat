local solids = require'solids'

local m = {}
m.__index = m

m.list = {}

local button_shape = solids.sphere(1):scale(6):map(function(x,y,z)
    z = z^1/3
    if z > 0 then z = z * 0.2 end
    return x, y, z
  end)

local frame_shape = solids.cylinder(12)
  :map(function(x, y, z)
    if y < 0 then
      x = x * 1.5
      z = z * 1.5
    end
    return x, y, z
  end)
  :transform(mat4(0, 0, -3)
    :rotate(-math.pi/2,1,0,0)
    :scale(8, 14, 8))
  :mergeIn(solids.cylinder(12):transform(mat4(0, 0, 1.5):rotate(-math.pi/2, 1,0,0):scale(14, 5, 14)))


function m.new(pose, layer)
  local pos = vector(pose:getPosition())
  local orientation = quaternion(pose:getOrientation())
  local self = setmetatable({}, m)
  self.layer = layer
  self.pose = pose
  self.pos = pos
  self.dir = orientation:direction()

  self.frame = m.world:newMeshCollider(frame_shape.vlist, frame_shape.ilist)
  self.frame:setPose(pos, orientation)


  orientation = orientation * quaternion(lovr.math.random() * 2 * math.pi, 0,0,1) * quaternion(math.pi/2, 0,1,0)
  self.button_pos = self.pose * vector(0, 0, -7)
  self.button_dir = orientation:direction()

  local _, button_shape = solids.convexHull(button_shape.vlist)
  self.button = m.world:newCollider()
  self.button:addShape(button_shape)
  self.button:setPose(self.button_pos + orientation:direction() * 7, orientation)
  self.button:setTag('dispenser')
  self.slider = lovr.physics.newSliderJoint(nil, self.button, self.button_dir)
  self.slider:setLimits(-2.5, 1)
  self.slider:setMotorMode('position')
  self.slider:setMotorSpring(2, 0.4)
  self.slider:setMaxMotorForce(2e6)
  table.insert(m.list, self)
  self.last_extrusion = 0
  return self
end


function m.draw(pass)
  pass:setColor(.3, .3, .3)
  for i, self in ipairs(m.list) do
    frame_shape:draw(pass, self.pose)
  end
  pass:setColor(.2, .1, .0)
  for i, self in ipairs(m.list) do
    local extrusion = self.slider:getPosition()
    local pose = mat4(self.button:getPose())
    button_shape:draw(pass, pose)
    pass:cylinder(self.button_pos, pose * vector(0,0,0), 1.8, false, nil, nil, 6)
    if extrusion < -2 and self.last_extrusion >= -2 then
      local levels = require'levels'
      local barrel = levels.addBarrel(self.pos + self.dir * 15, self.layer)
      barrel:setLinearVelocity(self.dir * 10)
      self.cooldown = 5
    end
    self.last_extrusion = extrusion
  end
end


return m