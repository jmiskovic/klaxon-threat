local palettes = require'palettes'

local m = {}
m.__index = m

m.list = {}

function m.spawn(world, level)
  local self = setmetatable({}, m)
  local lvl = determineLevel()
  self.level = lvl
  self.world = world
  self.alert = false
  local r
  if lvl > 1 then
    r = level.radii[lvl - 1] * 1.1 + math.random() * (level.radii[lvl] - level.radii[lvl - 1]) * 0.7
  else
    r = math.random() * level.radii[lvl] * 0.9
  end
  local pos = vector(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5):normalize() * r

  self.collider = world:newBoxCollider(pos, 10, 15, 15)
  self.side_collider = world:newBoxCollider(pos + vector(7.5, 0, 0),  5, 15, 15)
  local slider = lovr.physics.newSliderJoint(self.collider, self.side_collider, vector(1, 0, 0))
  slider:setLimits(0, 3)
  slider:setMotorMode('position')
  slider:setMotorTarget(2)
  --slider:setMaxMotorForce(4)
  slider:setMotorSpring(0.5, -.1)
  self.slider = slider
  table.insert(m.list, self)
  return self
end


function m.update(dt)
  for i, self in ipairs(m.list) do
    if self.slider and self.slider:getForce() > 5e7 then
      self.slider:destroy()
      self.slider = nil
    end
    if not self.alert then

    else
    end
  end
end


function m.draw(pass)
  for i, self in ipairs(m.list) do
    local position = vector(self.collider:getPosition())
    local orientation = quaternion(self.collider:getOrientation())
    pass:setColor(palettes[self.level][3])
    pass:box(position, 10, 15, 15, orientation)

    local side_position = vector(self.side_collider:getPosition())
    pass:setColor(palettes[self.level][4])
    pass:box(side_position, 5, 15, 15, orientation)

    pass:setColor(palettes[self.level][5])
    pass:sphere(position:lerp(side_position, 0.7), 5,  0, 0,1,0, 8)
  end
end


return m
