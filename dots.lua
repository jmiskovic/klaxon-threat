--- Module for building and managing point clouds
-- point cloud is a list of vector objects, with this module as metatable
local m = {}
m.__index = m


local function m_new(vertices)
  local cloud = {}
  cloud.edge_map = {}
  if type(vertices) == 'table' then
    for i, vertex in ipairs(vertices) do
      if type(vertex) == 'table' then
        if  vertex.cross then
          cloud[i] = vertex
        else
          cloud[i] = vector(unpack(vertex))
        end
      else
        error('unsupported input data')
      end
    end
    for iA, edges in pairs(vertices.edge_map or {}) do
      for iB, w in pairs(edges) do
        cloud.edge_map[iA] = cloud.edge_map[iA] or {}
        cloud.edge_map[iA][iB] = w
      end
    end
  end
  return setmetatable(cloud, m)
end

m.new = m_new


m.clone = m_new -- this works because old:clone() is same as m.clone(old)


--- Distribute n points on surface of a unit sphere (Fibonacci lattice)
function m.onSphere(n)
  local cloud = m_new()
  for i = 0, n - 1 do
    local ro = math.pi * (3 - math.sqrt(5)) -- golden angle
    local zi = 1 - i * 2 / (n - 1)
    local ri = math.sqrt(1 - zi * zi)
    local phi = i * ro
    cloud[i + 1] = vector(
      ri * math.cos(phi),
      ri * math.sin(phi),
      (1 - (i + 1/2) * 2 / (n - 1))
    )
  end
  return cloud
end


function m:map(fn)
  local cloud = self:clone()
  for i, point in ipairs(self) do
    cloud[i] = fn(point, i)
  end
  return cloud
end


function m:transform(transform)
  return self:map(function(point)
      return transform * point
    end)
end


-- Multiply all coordinates by a scalar
function m:scale(sx, sy, sz)
  sy = sy or sx
  sz = sz or sx
  return self:transform(mat4():scale(sx, sy, sz))
end


function m:hamiltonianConnect(start_index)
  local n = #self
  if n <= 1 then
    self.edge_map = {}
    return self
  end

  start_index = start_index or 1
  if start_index < 1 or start_index > n then start_index = 1 end

  local visited = {}
  local order = {}
  local current = start_index
  visited[current] = true
  order[1] = current

  for k = 2, n do
    local best, bestd2 = nil, math.huge
    local a = self[current]
    for i = 1, n do
      if not visited[i] then
        local b = self[i]
        local dx = a.x - b.x
        local dy = a.y - b.y
        local dz = a.z - b.z
        local d2 = dx*dx + dy*dy + dz*dz
        if d2 < bestd2 then
          bestd2 = d2
          best = i
        end
      end
    end
    if not best then break end
    visited[best] = true
    order[k] = best
    current = best
  end

  self.edge_map = {}
  for i = 1, #order - 1 do
    local u = order[i]
    local v = order[i + 1]
    local w = (self[u] - self[v]):length()
    self.edge_map[u] = self.edge_map[u] or {}
    self.edge_map[v] = self.edge_map[v] or {}
    self.edge_map[u][v] = w
    self.edge_map[v][u] = w
  end

  return self, order
end


return m
