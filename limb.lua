local m = {}
m.__index = m


function m.new(lengths, origin_collider, target_collider, origin_offset, target_offset)
  local self = setmetatable({}, m)
  self.lengths = lengths
  self.strength = 0.5
  self.origin_collider = origin_collider
  self.target_collider = target_collider
  self.origin_offset = origin_offset or vector(0)
  self.target_offset = target_offset or vector(0)
  self.origin = vector(origin_collider:getWorldPoint(origin_offset))
  self.target = vector(target_collider:getWorldPoint(target_offset))
  self.thickness = 0.4
  self.joints = {}
  local direction = vector.normalize(self.target - self.origin)
  local total_length = 0
  table.insert(self.joints, self.origin + direction * total_length)
  for _, length in ipairs(lengths) do
    table.insert(self.joints, self.origin + direction * total_length)
    total_length = total_length + length
  end
  return self
end

function m:nudge(offset)
  offset = quaternion(self.origin_collider:getOrientation()) * offset
  for i = 2, #self.joints - 1 do
    self.joints[i] = self.joints[i] + offset
  end
end

function m:update(strength)
  self.origin = vector(self.origin_collider:getWorldPoint(self.origin_offset))
  self.target = vector(self.target_collider:getWorldPoint(self.target_offset))
  strength = math.min(1, strength or self.strength)
  self.joints[#self.joints] = vector.lerp(self.joints[#self.joints], self.target, strength)
  for link = #self.joints - 1, 1, -1 do
    local diff = vector.normalize(self.joints[link + 1] - self.joints[link]) * self.lengths[link]
    diff = self.joints[link + 1] - diff
    self.joints[link] = vector.lerp(self.joints[link], diff, strength)
  end
  self.joints[1] = vector.lerp(self.joints[1], self.origin, strength)
  for link = 2, #self.joints, 1 do
    local diff = vector.normalize(self.joints[link - 1] - self.joints[link]) * self.lengths[link - 1]
    diff = self.joints[link - 1] - diff
    self.joints[link] = vector.lerp(self.joints[link], diff, strength)
  end
end

function m:drawCapsules(pass, thickness, segments)
  thickness = thickness or 0.05
  segments = segments or 7
  for i = 1, #self.joints - 1 do
    pass:capsule(self.joints[i], self.joints[i+1], thickness, segments)
  end
  pass:capsule(self.joints[#self.joints], self.target, thickness, segments)
  pass:capsule(self.origin, self.joints[1], thickness, segments)
end

function m:draw(pass, color, segments)
  pass:setColor(color)
  self:drawCapsules(pass, self.thickness, segments)
end

return m
