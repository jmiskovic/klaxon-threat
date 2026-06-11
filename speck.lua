local serpent = require'serpent'
local m = {}

local Particle = {}
Particle.__index = Particle

function Particle.new(e, position, velocity, lifetime, color)
  local self = setmetatable({}, Particle)
  self.emitter = e
  self.position = position
  self.velocity = velocity
  self.lifetime = lifetime
  self.attached = nil
  self.size = 1
  self.age = 0
  self.color = color
  return self
end


function Particle:attach(e)
  if self.attached then
    self.attached:stop()
    self.attached.dispose_when_done = true
  end
  self.attached = e
  return self
end


function Particle:update(dt)
  self.age = self.age + dt
  for _, mover in ipairs(self.emitter.movers) do
    mover.fn(self, mover.param, dt)
  end
  self.position = self.position + self.velocity * dt
  if self.attached then
    self.attached.position = self.position
  end
end


function Particle:isAlive()
  return self.age < self.lifetime
end


function Particle:remove()
  self.age = self.lifetime
  if self.attached then
    self.attached:stop()
    self.attached.dispose_when_done = true
    self.attached = nil
  end
end


local Emitter = {}
Emitter.__index = Emitter

function Emitter.new(options)
  local self = setmetatable({}, Emitter)
  self.dispose_when_done = false
  self.initial_velocity = options.velocity or vector(0)
  self.position = options.position or vector(0)
  self.emit_rate = options.emit_rate or 100
  self.lifetime = options.lifetime or 5.0
  self.lifetime_random = options.lifetime_random or 0.1
  self.particles = {}
  self.time_since_last_emit = lovr.math.random() / self.emit_rate
  self.velocity_random = options.velocity_random or 1.0
  self.movers = {}
  self.color = options.color or {1,1,1,1}
  self.lightness_random = options.lightness_random or 0
  self.drawers = {}
  self.spawners = {}
  self.streaming = false
  return self
end


function Emitter:setPosition(x_or_vector, y, z)
  if getmetatable(x_or_vector) == getmetatable(vector.up) then
    self.position = x_or_vector
  else
    self.position = vector(x_or_vector, y, z)
  end
end


function Emitter:burst(count, dispose_when_done)
  if dispose_when_done ~= nil then
    self.dispose_when_done = not not dispose_when_done
  end
  count = count or self.emit_rate
  for _ = 1, count do
    self:emitParticle()
  end
  self.time_since_last_emit = 0
end


function Emitter:stream(rate)
  self.emit_rate = rate or self.emit_rate
  self.streaming = true
  self.time_since_last_emit = lovr.math.random() / self.emit_rate
  return self
end


function Emitter:stop()
  self.streaming = false
  self.periodic_burst_count = nil
end


function Emitter:update(dt)
  for i = #self.particles, 1, -1 do
    local particle = self.particles[i]
    if particle:isAlive() then
      particle:update(dt)
    else
      table.remove(self.particles, i)
      particle:remove()
    end
  end

  if self.streaming then
    self.time_since_last_emit = self.time_since_last_emit + dt
    local emit_count = math.floor(self.time_since_last_emit * self.emit_rate)
    self.time_since_last_emit = self.time_since_last_emit - emit_count / self.emit_rate
    for _ = 1, emit_count do
      self:emitParticle()
    end
  end

  if self.dispose_when_done and #self.particles == 0 then
    m.removeEmitter(self)
  end
end


function Emitter:draw(pass)
  for _, drawer in ipairs(self.drawers) do
    drawer.fn(self, pass, drawer.param)
  end
end


function Emitter:emitParticle()
  if #self.spawners == 0 then return end
  local spawner = self.spawners[lovr.math.random(1, #self.spawners)]
  local spawn_position = spawner and spawner.fn(self, spawner.param) or self.position
  local random_velocity = self.initial_velocity + vector(
    (lovr.math.random() * 2 - 1) * self.velocity_random,
    (lovr.math.random() * 2 - 1) * self.velocity_random,
    (lovr.math.random() * 2 - 1) * self.velocity_random
  )
  local lifetime = lovr.math.randomNormal(self.lifetime_random, self.lifetime)
  local color = {}
  if self.lightness_random > 0 then
    local s = lovr.math.randomNormal(self.lightness_random * 0.1, 0)
    color = {
      self.color[1] + s,
      self.color[2] + s,
      self.color[3] + s,
      self.color[4]
    }
  else
    color = {unpack(self.color)}
  end
  if lovr.system.wasKeyPressed('f12') then require'repl'() end
  local particle = Particle.new(self, spawn_position, random_velocity, lifetime, color)
  table.insert(self.particles, particle)
end


function Emitter:remove()
  for i, p in ipairs(self.particles) do
    p:remove()
  end
  self.particles = {}
end


function Emitter:addSpawner(spawner)
  assert(spawner.name and spawner.fn and spawner.param)
  table.insert(self.spawners, spawner)
end


function Emitter:addMover(mover)
  assert(mover.name and mover.fn and mover.param)
  table.insert(self.movers, mover)
end


function Emitter:addDrawer(drawer)
  assert(drawer.name and drawer.fn and drawer.param)
  table.insert(self.drawers, drawer)
end


function Emitter:spawnCube(size)
  self:addSpawner{
    name = 'cube',
    param = { size = size or 10.0 },
    fn = function(emitter, param)
      return emitter.position + vector(
        (-1 + 2 * lovr.math.random()) * param.size,
        (-1 + 2 * lovr.math.random()) * param.size,
        (-1 + 2 * lovr.math.random()) * param.size
      )
    end,
  }
  return self
end


function Emitter:spawnSphere(radius)
  self:addSpawner{
    name = 'sphere',
    param = { radius = radius or 5.0 },
    fn = function(emitter, param)
      local theta = lovr.math.random() * math.pi * 2
      local phi = math.acos(2 * lovr.math.random() - 1)
      local r = param.radius * (lovr.math.random() ^ (1/3))
      local dx = r * math.sin(phi) * math.cos(theta)
      local dy = r * math.sin(phi) * math.sin(theta)
      local dz = r * math.cos(phi)
      return emitter.position + vector(dx, dy, dz)
    end,
  }
  return self
end


function Emitter:spawnPoints(points)
  self:addSpawner{
    name = 'points',
    param = { points = points },
    fn = function(emitter, param)
      return param.points[lovr.math.random(1, #param.points)]
    end,
  }
  return self
end


function Emitter:moveGravity(gravity)
  self:addMover{
    name = 'gravity',
    param = { gravity = gravity or vector(0, -1, 0) },
    fn = function(particle, param, dt)
      particle.velocity = particle.velocity + param.gravity * dt
    end,
  }
  return self
end


function Emitter:moveNoisy(strength, frequency, time_amp)
  local t = 0
  self:addMover{
    name = 'noisy',
    param = { strength = strength or 0.7, frequency = frequency or 1.0, time_amp = time_amp or 0.1 },
    fn = function(particle, param, dt)
      t = t + dt * param.time_amp / 100
      local pos = particle.position * param.frequency
      local noise_force = vector(
        param.strength * (-0.5 + lovr.math.noise(t, pos:unpack())),
        param.strength * (-0.5 + lovr.math.noise(100 + t, pos:unpack())),
        param.strength * (-0.5 + lovr.math.noise(-100 + t, pos:unpack()))
      )
      particle.velocity = particle.velocity + noise_force * dt
    end,
  }
  return self
end


function Emitter:moveAttractor(position, strength, relative)
  self:addMover{
    name = 'attractor',
    param = { position = position or vector(0, 0, 0), strength = strength or 1.0, relative = relative or false },
    fn = function(particle, param, dt)
      local position = param.position
      if param.relative then
        position = position + self.position
      end
      local distance = particle.position:distance(position)
      local direction = position - particle.position
      local force = direction:normalize() * (param.strength / (1e-2 + distance^2))
      particle.velocity = particle.velocity + force * dt
    end,
  }
  return self
end


function Emitter:moveDampener(strength, only_vertical)
  self:addMover{
    name = 'dampener',
    param = { strength = strength or 0.5, only_vertical = only_vertical or false },
    fn = function(particle, param, dt)
      if param.only_vertical then
        particle.velocity = particle.velocity * vector(1, 1 - param.strength * 0.1, 1)
      else
        particle.velocity = particle.velocity * (1 - param.strength * 0.1)
      end
    end,
  }
  return self
end


function Emitter:moveColorFade(color, tau, strength)
  self:addMover{
    name = 'color fade',
    param = { color = color, tau = tau or 0.5, strength = strength or 1.0 },
    fn = function(p, param, dt)
      local t = p.age / p.lifetime
      local d = math.abs(t - param.tau)
      local shape = math.max(0, 1 - d * d * 4)
      local alpha = shape * param.strength * dt * 10
      p.color[1] = p.color[1] + (param.color[1] - p.color[1]) * alpha
      p.color[2] = p.color[2] + (param.color[2] - p.color[2]) * alpha
      p.color[3] = p.color[3] + (param.color[3] - p.color[3]) * alpha
    end,
  }
  return self
end


function Emitter:moveSizeFade(targetSize, tau, strength)
  self:addMover{
    name = 'size fade',
    param = { target = targetSize or 0.2, tau = tau or 0.75, strength = strength or 1.0 },
    fn = function(p, param, dt)
      local t = p.age / p.lifetime
      local d = math.abs(t - param.tau)
      local shape = math.max(0, 1 - d * d * 4)
      local alpha = shape * param.strength * dt * 10
      p.size = p.size + (param.target - p.size) * alpha
    end,
  }
  return self
end


function Emitter:moveZap(prob, strength)
  self:addMover{
    name = 'zap',
    param = { prob = prob or 0.5, strength = strength or 1.0 },
    fn = function(p, param, dt)
      if lovr.math.random() < param.prob * dt * 10 then
        p.position = vector(
          lovr.math.randomNormal(param.strength * 0.01, p.position.x),
          lovr.math.randomNormal(param.strength * 0.01, p.position.y),
          lovr.math.randomNormal(param.strength * 0.01, p.position.z)
        )
      end
    end,
  }
  return self
end


function Emitter:moveOrthogonal(strength)
  local function sign(x)
    return x > 0 and 1 or (x < 0 and -1 or 0)
  end
  self:addMover{
    name = 'orthogonal',
    param = { strength = strength or 0.75 },
    fn = function(p, param, dt)
      local abs_x, abs_y, abs_z = math.abs(p.velocity.x), math.abs(p.velocity.y), math.abs(p.velocity.z)
      local orthogonal_velocity
      if abs_y > abs_x and abs_y > abs_z then
        orthogonal_velocity = vector(0, sign(p.velocity.y) * abs_y, 0)
      elseif abs_z > abs_x and abs_z > abs_y then
        orthogonal_velocity = vector(0, 0, sign(p.velocity.z) * abs_z)
      else
        orthogonal_velocity = vector(sign(p.velocity.x) * abs_x, 0, 0)
      end
      p.velocity = p.velocity + (orthogonal_velocity - p.velocity) * param.strength * dt
    end,
  }
  return self
end


function Emitter:drawLines(thickness, segments, length)
  local history = setmetatable({}, {__mode="k"})
  self:addDrawer{
    name = 'lines',
    param = { thickness = thickness or 0.02, segments = segments or 7, length = length or 3 },
    fn = function(self, pass, param)
      local dt = lovr.timer.getDelta()
      local segments = math.max(3, param.segments)
      local max_history = param.length or 4
      for _, particle in ipairs(self.particles) do
        pass:setColor(particle.color)
        if not history[particle] then
          history[particle] = {}
        end
        table.insert(history[particle], 1, particle.position)
        if #history[particle] > max_history then
          table.remove(history[particle])
        end
        for i = 1, #history[particle] - 1 do
          local from_pos = history[particle][i]
          local to_pos = history[particle][i + 1]
          pass:capsule(to_pos, from_pos,
            param.thickness * particle.size, segments)
        end
      end
    end
  }
  return self
end


function Emitter:drawTaperLines(thickness, segments, length, taper)
  local history = setmetatable({}, {__mode="k"})
  self:addDrawer{
    name = 'taper lines',
    param = { thickness = thickness or 0.02, segments = segments or 7, length = length or 3, taper = taper or math.pi/2 },
    fn = function(self, pass, param)
      local dt = lovr.timer.getDelta()
      local segments = math.max(3, param.segments)
      local max_history = param.length or 4
      for _, particle in ipairs(self.particles) do
        pass:setColor(particle.color)
        if not history[particle] then
          history[particle] = {}
        end
        table.insert(history[particle], 1, particle.position)
        if #history[particle] > max_history then
          table.remove(history[particle])
        end
        for i = 1, #history[particle] - 1 do
          local from_pos = history[particle][i]
          local to_pos = history[particle][i + 1]
          local taper_mul = math.cos((1 + param.taper) * math.abs(i - #history[particle] / 2) / max_history)
          pass:capsule(to_pos, from_pos,
            param.thickness * particle.size * taper_mul, segments)
        end
      end
    end
  }
  return self
end


function Emitter:drawSpheres(radius, segments)
  self:addDrawer{
    name = 'spheres',
    param = { radius = radius or 0.02, segments = segments or 14 },
    fn = function(self, pass, param)
      pass:origin()
      local segments = math.max(4, param.segments)
      for _, particle in ipairs(self.particles) do
        pass:setColor(particle.color)
        pass:sphere(particle.position, param.radius * particle.size, nil, segments)
      end
    end
  }
  return self
end


function Emitter:drawSprites(size, path, rotation_is_random, angular_velocity, angular_velocity_random)
  local rotation = setmetatable({}, {__mode="k"})
  local rotation_velocity = setmetatable({}, {__mode="k"})
  local texture = nil
  local loaded_path
  self:addDrawer{
    name = 'sprites',
    param = { size = size or 0.2, path = path,
      rotation_is_random = rotation_is_random or false,
      angular_velocity = angular_velocity or 0,
      angular_velocity_random = angular_velocity_random or 0 },
    fn = function(self, pass, param)
      if loaded_path ~= param.path then
        texture = lovr.graphics.newTexture(param.path)
        loaded_path = param.path
      end
      local dt = lovr.timer.getDelta()
      local orientation = quaternion(pass:getViewPose(1, mat4()):getOrientation())
      local dir = orientation:direction()
      pass:setMaterial(texture)
      pass:setAlphaToCoverage(true)
      for _, p in ipairs(self.particles) do
        if not rotation[p] then
          rotation[p] = param.rotation_is_random and lovr.math.random() * math.pi * 2 or 0
          rotation_velocity[p] = param.angular_velocity + (-0.5 + lovr.math.random()) * param.angular_velocity_random
        end
        rotation[p] = rotation[p] + rotation_velocity[p] * dt
        local s = p.size * param.size
        pass:setColor(p.color)
        pass:plane(p.position, s, s, quaternion(rotation[p], dir:unpack()) * orientation)
      end
      pass:setAlphaToCoverage(false)
      pass:setMaterial()
    end
  }
  return self
end


function Emitter:drawMonkeys(size)
  self:addDrawer{
    name = 'monkeys',
    param = { size = size or 0.1 },
    fn = function(self, pass, param)
      for _, particle in ipairs(self.particles) do
        pass:setColor(particle.color)
        pass:monkey(particle.position, param.size * particle.size)
      end
    end
  }
  return self
end


function Emitter:drawEmitters(proto)
  local serialized
  if type(proto) == 'string' then
    serialized = proto
  elseif proto then
    serialized = proto:serialize()
  end
  self:addDrawer{
    name = 'emitters',
    param = { serialized = serialized },
    fn = function(self, pass, param)
      for _, particle in ipairs(self.particles) do
        if not particle.attached and param.serialized then
          local emitter = m.emitterFromString(param.serialized)
          particle:attach(emitter)
          emitter:stream()
        end
      end
    end
  }
  return self
end


function Emitter:clone()
  local serialized = self:serialize()
  return m.emitterFromString(serialized)
end


function Emitter:serialize()
  local data = {
    position = self.position,
    velocity = self.initial_velocity,
    emit_rate = self.emit_rate,
    lifetime = self.lifetime,
    lifetime_random = self.lifetime_random,
    velocity_random = self.velocity_random,
    color = self.color,
    lightness_random = self.lightness_random,
    spawners = {},
    movers = {},
    drawers = {},
    streaming = self.streaming,
  }
  for i, spawner in ipairs(self.spawners) do
    data.spawners[i] = {
      name = spawner.name,
      param = spawner.param
    }
  end
  for i, mover in ipairs(self.movers) do
    data.movers[i] = {
      name = mover.name,
      param = mover.param
    }
  end
  for i, drawer in ipairs(self.drawers) do
    data.drawers[i] = {
      name = drawer.name,
      param = drawer.param
    }
  end
  return serpent.line(data, { compact=true, comment=false, numformat='%.4g' })
end


local function inflateVectors(obj)
  if type(obj) ~= "table" then
    return obj
  end
  if obj.__type == "vector" then
    return vector(obj.x, obj.y, obj.z)
  end
  for k, v in pairs(obj) do
    obj[k] = inflateVectors(v)
  end
  return obj
end


function m.emitterFromString(serialized_emitter)
  local success, data = serpent.load(serialized_emitter)
  if not success then
    error('Failed to deserialize emitter: ' .. data)
  end
  data = inflateVectors(data)

  local emitter = Emitter.new({
    position = data.position,
    velocity = data.velocity,
    emit_rate = data.emit_rate,
    lifetime = data.lifetime,
    lifetime_random = data.lifetime_random,
    velocity_random = data.velocity_random,
    color = data.color,
    lightness_random = data.lightness_random,
  })
  if data.streaming then
    emitter:stream()
  end

  for _, spawner_data in ipairs(data.spawners or {}) do
    local spawner_name = spawner_data.name
    local param = spawner_data.param
    if spawner_name == 'cube' then
      emitter:spawnCube(param.size)
    elseif spawner_name == 'sphere' then
      emitter:spawnSphere(param.radius)
    elseif spawner_name == 'points' then
      emitter:spawnPoints(param.points)
    end
  end

  for _, mover_data in ipairs(data.movers or {}) do
    local mover_name = mover_data.name
    local param = mover_data.param
    if mover_name == 'gravity' then
      emitter:moveGravity(param.gravity)
    elseif mover_name == 'noisy' then
      emitter:moveNoisy(param.strength, param.frequency, param.time_amp)
    elseif mover_name == 'dampener' then
      emitter:moveDampener(param.strength, param.only_vertical)
    elseif mover_name == 'attractor' then
      emitter:moveAttractor(param.position, param.strength, param.relative)
    elseif mover_name == 'color fade' then
      emitter:moveColorFade(param.color, param.tau, param.strength)
    elseif mover_name == 'size fade' then
      emitter:moveSizeFade(param.target, param.tau, param.strength)
    elseif mover_name == 'zap' then
      emitter:moveZap(param.prob, param.strength)
    elseif mover_name == 'orthogonal' then
      emitter:moveOrthogonal(param.strength)
    end
  end

  for _, drawer_data in ipairs(data.drawers or {}) do
    local drawer_name = drawer_data.name
    local param = drawer_data.param

    if drawer_name == 'lines' then
      emitter:drawLines(param.thickness, param.segments, param.length)
    elseif drawer_name == 'taper lines' then
      emitter:drawTaperLines(param.thickness, param.segments, param.length, param.taper)
    elseif drawer_name == 'spheres' then
      emitter:drawSpheres(param.radius, param.segments)
    elseif drawer_name == 'sprites' then
      emitter:drawSprites(param.size, param.path)
    elseif drawer_name == 'monkeys' then
      emitter:drawMonkeys(param.size)
    elseif drawer_name == 'emitters' then
      emitter:drawEmitters(param.serialized)
    end
  end
  m.addEmitter(emitter)
  return emitter
end


function m.emitter(options)
  local e = Emitter.new(options)
  m.addEmitter(e)
  return e
end


function m.update(dt)
  for _, emitter in ipairs(m.emitters) do
    emitter:update(dt)
  end
end


function m.draw(pass)
  for _, emitter in ipairs(m.emitters) do
    emitter:draw(pass)
  end
end


m.emitters = {}


function m.addEmitter(e)
  table.insert(m.emitters, e)
end


function m.removeEmitter(e)
  for i, v in ipairs(m.emitters) do
    if v == e then
      e:remove()
      table.remove(m.emitters, i)
      return
    end
  end
end


function m.reset()
  for i, e in ipairs(m.emitters) do
    e:stop()
    e:remove()
  end
  m.emitters = {}
end

return m
