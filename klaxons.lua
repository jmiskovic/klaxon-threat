local palettes = require'palettes'
local speck = require'speck'
local levels = require'levels'
local boxxer = require'boxxer'


local m = {}
m.__index = m

m.list = {}

local deflector_preset = [==[{color={0.962,0.02962,0.006644},drawers={{name="spheres",param={radius=0.4257,segments=7.025}}},emit_rate=297.6,lifetime=0.643,lifetime_random=0.2082,lightness_random=0.25,movers={{name="color fade",param={color={1,0.9708,0,1},strength=0.2644,tau=0.2621}},{name="color fade",param={color={0,0.5735,0.9452,1},strength=1.804,tau=0.8503}},{name="color fade",param={color={0.8122,0,0.6391,1},strength=3.548,tau=1.311}},{name="size fade",param={strength=1.547,target=0.4222,tau=0.9934}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="sphere",param={radius=1.365}}},streaming=false,velocity={__type="vector",x=0,y=-0.0001672,z=0},velocity_random=2.817}]==]
local explode_preset = [==[{color={0.2252,0.219,0.2135},drawers={{name="lines",param={length=33.24,segments=3.01,thickness=0.118}}},emit_rate=28.46,lifetime=1.596,lifetime_random=0.1713,lightness_random=0.9404,movers={{name="orthogonal",param={strength=1.354}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="cube",param={size=2.021}}},streaming=false,velocity={__type="vector",x=0,y=0,z=0},velocity_random=8.826}]==]

local explode_emitter = speck.emitterFromString(explode_preset)


deflector_shape = lovr.physics.newSphereShape(3)

local klaxon_source = lovr.audio.newSource('klaxon.ogg', {spatial=true, pitchable=true })
klaxon_source:setSpatialization(1); klaxon_source:setAbsorption(true); klaxon_source:setFalloff(true)
klaxon_source:setLooping(true)

local DETECTION_RANGE = 150
local STOP_RANGE = 30
local AVOID_RANGE = 30
local FORCE = 3e8
local TORQUE = 2e8

local DEFLECTOR_COOLDOWN = 15
local DEFLECTOR_SPEED = 30
local DEFLECTOR_FORCE = 8e9

local avoid_shape = lovr.physics.newSphereShape(10)

function m.spawn(pos, layer)
  local self = setmetatable({}, m)
  self.mylayer = layer
  self.is_alert = false
  self.destroyed_duration = nil
  local r

  self.collider = m.world:newBoxCollider(pos, 10, 15, 15)
  self.side_collider = m.world:newBoxCollider(pos + vector(7.5, 0, 0),  5, 15, 15)
  self.collider:setTag('klaxon'); self.side_collider:setTag('klaxon')
  self.collider:setLinearDamping(0.8); self.side_collider:setLinearDamping(0.8)
  self.collider:setAngularDamping(1.2); self.side_collider:setAngularDamping(1.2)
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
  self.destroyed_duration = nil
  table.insert(m.list, self)
  self.deflector_cooldown = 3
  self.deflector_projectile = nil
  self.deflector_emitter = speck.emitterFromString(deflector_preset)
  return self
end

function m:destroy()
  self.klaxon_source:stop()
  if not self.collider:isDestroyed() then self.collider:destroy() end
  if not self.side_collider:isDestroyed() then self.side_collider:destroy() end
  self.deflector_emitter:stop()
end


function m.update(dt)
  local boxxer_position = vector(boxxer.collider:getPosition())
  for i, self in ipairs(m.list) do
    if self.collider:isDestroyed() then
      table.remove(m.list, i)
      return
    end
    local position = vector(self.collider:getPosition())
    local orientation = quaternion(self.collider:getOrientation())
    self.klaxon_source:setPosition(position)
    if self.slider and self.slider:getPosition() > 9 then -- destroyed
      self.slider:destroy()
      self.slider = nil
      self.destroyed_duration = 0
      explode_emitter:setPosition(position)
      explode_emitter:burst()
    end
    if self.destroyed_duration then
      self.destroyed_duration = self.destroyed_duration + dt
      if self.destroyed_duration > 2 then
        self.klaxon_source:stop()
      else
        self.klaxon_source:setPitch(1 - self.destroyed_duration * 0.45)
      end
    end
    if not self.destroyed_duration then
      if not self.is_alert then -- not alert, scanning
        local collider = m.world:raycast(position, boxxer_position, '~klaxon')
        if collider == boxxer.collider and boxxer_position:distance(position) < DETECTION_RANGE then
          addText('<enemy klaxon locked onto us>')
          self.is_alert = true
          self.klaxon_source:play()
          self.target = boxxer_position
        else
          if position:distance(self.target) < STOP_RANGE or
            m.world:shapecast(avoid_shape, position, position + (self.target - position):normalize() * AVOID_RANGE, nil, 'level') then
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
        self.target = boxxer_position
        ---[[ deflector
        self.deflector_cooldown = self.deflector_cooldown - dt
        if not self.deflector_projectile and self.deflector_cooldown <= 0 then
          self.deflector_cooldown = DEFLECTOR_COOLDOWN
          self.deflector_projectile = { position = position, velocity = (boxxer_position - position):normalize() }
          self.deflector_emitter:stream()
          self.deflector_emitter:setPosition(self.deflector_projectile.position)
        end
        if self.deflector_projectile then
          self.deflector_projectile.position = self.deflector_projectile.position + self.deflector_projectile.velocity * dt * DEFLECTOR_SPEED
          self.deflector_emitter:setPosition(self.deflector_projectile.position)
          m.world:overlapShape(deflector_shape, self.deflector_projectile.position, nil, 10, '~klaxon',
            function(collider, shape, x, y, z)
              if not self.deflector_projectile then return true end
              local pos = vector(x, y, z)
              local dir = (pos - self.deflector_projectile.position):normalize()
              collider:applyForce(dir * DEFLECTOR_FORCE * dt)
              if self.deflector_projectile.position:distance(pos) < 1 then
                self.deflector_projectile = nil
                self.deflector_emitter:stop()
              end
            end)
        end
        --]]
      end
      -- move
      local dir = (self.target - position):normalize()
      local target_orientation = quaternion.lookdir(dir, vector(self.collider:getWorldPoint(0, 1, 0)))
      local orientation_err = target_orientation * orientation:conjugate()
      local _, ax, ay, az = orientation_err:toangleaxis()
      if position:distance(self.target) > STOP_RANGE then
        self.collider:applyForce(dir * dt * FORCE)
        self.side_collider:applyForce(dir * dt * FORCE)
      end

      self.collider:applyTorque(ax * TORQUE, ay * TORQUE, az * TORQUE)
      self.side_collider:applyTorque(ax * TORQUE * dt, ay * TORQUE * dt, az * TORQUE * dt)
      -- loosen join when grabbed
      if self.slider then
        if #self.collider:getJoints() > 1 and #self.side_collider:getJoints() > 1 then
          self.slider:setLimits()
          self.slider:setMotorMode()
        else
          self.slider:setLimits(0, 3)
          self.slider:setMotorMode('position')
        end
      end
    end -- if not destroyed
  end -- klaxon iteration
end


function m.draw(pass)
  for i, self in ipairs(m.list) do
    if self.collider:isDestroyed() then
      table.remove(m.list, i)
      return
    end
    local position = vector(self.collider:getPosition())
    local orientation = quaternion(self.collider:getOrientation())
    pass:setColor(palettes[self.mylayer][3])
    pass:box(position, 10, 15, 15, orientation)

    local side_position = vector(self.side_collider:getPosition())
    local orientation = quaternion(self.side_collider:getOrientation())
    pass:setColor(palettes[self.mylayer][4])
    pass:box(side_position, 5, 15, 15, orientation)

    if not self.destroyed_duration then
      pass:setColor(palettes[self.mylayer][5])
      pass:sphere(position:lerp(side_position, 0.65), 5,  0, 0,1,0, 8)
    end

    --[[ debug destination
    pass:setColor(0.4,0.4,0.4)
    pass:capsule(position, self.target, 0.5, 8)
    --]]
  end
end


return m
