local palettes = require'palettes'

local m = {}
m.__index = m

m.list = {}

local klaxon_source = lovr.audio.newSource('klaxon.ogg', {spatial=true, pitchable=true })
klaxon_source:setSpatialization(1); klaxon_source:setAbsorption(true); klaxon_source:setFalloff(true)
klaxon_source:setLooping(true)

local DETECTION_RANGE = 100
local AVOID_RANGE = 30
local FORCE = 4e8
local TORQUE = 4e8

local castshape = lovr.physics.newSphereShape(10)


function m.spawn()
  local self = setmetatable({}, m)
  local lvl = determineLevel()
  self.is_alert = false
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
  self.collider:setTag('klaxon'); self.side_collider:setTag('klaxon')
  self.collider:setAngularDamping(2); self.side_collider:setAngularDamping(2)
  local slider = lovr.physics.newSliderJoint(self.collider, self.side_collider, vector(1, 0, 0))
  slider:setLimits(0, 3)
  slider:setMotorMode('position')
  slider:setMotorTarget(2)
  slider:setMotorSpring(0.5, -.1)
  slider:setSpring(0.5, -.1)
  self.slider = slider
  self.klaxon_source = klaxon_source:clone()
  self.klaxon_source:seek(math.random())
  self.target = pos
  table.insert(m.list, self)
  return self
end


function m.update(dt)
  local boxxer_position = vector(m.boxxer.collider:getPosition())
  for i, self in ipairs(m.list) do
    local position = vector(self.collider:getPosition())
    local orientation = quaternion(self.collider:getOrientation())
    self.klaxon_source:setPosition(position)
    if self.slider and self.slider:getPosition() > 9 then -- destroyed
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
    if not self.is_alert then -- not alert, scanning
      local collider = m.world:raycast(position, boxxer_position, '~klaxon')
      if collider == m.boxxer.collider and boxxer_position:distance(position) < DETECTION_RANGE then
        addText('<enemy klaxon locked onto us>')
        self.is_alert = true
        self.klaxon_source:play()
        --self.target = boxxer_position
      else
        if position:distance(self.target) < 10 or
          m.world:shapecast(castshape, position, position + (self.target - position):normalize() * AVOID_RANGE, nil, 'level') then
          for i = 1, 5 do
            local potential_target = position + vector(1e3 * (lovr.math.random() - 0.5), 1e3 * (lovr.math.random() - 0.5), 1e3 * (lovr.math.random() - 0.5))
            local collider, shape, x, y, z = m.world:raycast(position, potential_target, '~klaxon')
            if collider then
              potential_target = vector(x, y, z)
              if position:distance(potential_target) > position:distance(self.target) then
                self.target = potential_target
              end
            end
          end
        end
      end
    else -- hunting
      --self.target = boxxer_position
    end
    local dir = (self.target - position):normalize()
    local target_orientation = quaternion.lookdir(dir, vector(self.collider:getWorldPoint(0, 1, 0)))
    local orientation_err = target_orientation * orientation:conjugate()
    local _, ax, ay, az = orientation_err:toangleaxis()
    self.collider:applyForce(dir * dt * FORCE)
    self.collider:applyTorque(ax * TORQUE, ay * TORQUE, az * TORQUE)
    self.side_collider:applyForce(dir * dt * FORCE)
    self.side_collider:applyTorque(ax * TORQUE * dt, ay * TORQUE * dt, az * TORQUE * dt)
  end
end


function m.draw(pass)
  for i, self in ipairs(m.list) do
    local position = vector(self.collider:getPosition())
    local orientation = quaternion(self.collider:getOrientation())
    pass:setColor(palettes[self.level][3])
    pass:box(position, 10, 15, 15, orientation)

    local side_position = vector(self.side_collider:getPosition())
    local orientation = quaternion(self.side_collider:getOrientation())
    pass:setColor(palettes[self.level][4])
    pass:box(side_position, 5, 15, 15, orientation)

    pass:setColor(palettes[self.level][5])
    pass:sphere(position:lerp(side_position, 0.65), 5,  0, 0,1,0, 8)

    pass:setColor(0.4,0.4,0.4)
    pass:capsule(position, self.target, 0.5, 8)
  end
end


return m
