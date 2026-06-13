local palettes = require'palettes'

local m = {}
m.__index = m

m.list = {}

local klaxon_source = lovr.audio.newSource('klaxon.ogg', {spatial=true, pitchable=true })
--local klaxon_source = lovr.audio.newSource('white_noise_long.wav', {spatial=true})
klaxon_source:setLooping(true)
klaxon_source:setSpatialization(1)
--klaxon_source:setVolume(.3)
klaxon_source:setAbsorption(true)
klaxon_source:setFalloff(true)

function m.spawn(world, level)
  local self = setmetatable({}, m)
  local lvl = determineLevel()
  self.level = lvl
  self.world = world
  self.alert = false
  self.destroyed_duration = nil
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
  slider:setMotorSpring(0.5, -.1)
  slider:setSpring(0.5, -.1)
  self.slider = slider
  self.klaxon_source = klaxon_source:clone()
  self.klaxon_source:seek(math.random())
  self.klaxon_source:play()

  table.insert(m.list, self)
  return self
end


function m.update(dt)
  for i, self in ipairs(m.list) do
    local position = vector(self.collider:getPosition())
    self.klaxon_source:setPosition(position)
    if self.slider and self.slider:getPosition() > 5 then
      self.slider:destroy()
      self.slider = nil
      self.destroyed_duration = 0
    end
    if self.destroyed_duration then
      self.destroyed_duration = self.destroyed_duration + dt
      if self.destroyed_duration > 2 then
        self.klaxon_source:stop()
      else
        self.klaxon_source:setPitch(1 - self.destroyed_duration * 0.45)
      end
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
