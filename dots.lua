--- Module for building and managing point clouds
-- point cloud is a list of vector objects, with this module as metatable
local m = {}
m.__index = m

m.DOT_SIZE = 0.1
m.EDGE_SIZE = 0.02
m.DRAW_INDEX = false

local EPSILON = 1e-6
local kdtree


local function sign(n)
  return (n >= 0) and 1 or -1
end


-- `vertices` is an optional list of points in {{x,y,z}} or vector format, or dots instance to clone
function m.new(vertices)
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


m.clone = m.new -- this works because old:clone() is same as m.clone(old)


-- from -0.5, -0.5, -0.5 to 0.5, 0.5, 0.5
function m.grid(xn, yn, zn, staggered, resize)
  staggered = not not staggered
  xn = xn or 10
  yn = yn or xn
  zn = zn or 1

  local cloud = m.new()
  local n = { xn, yn, zn }

  for xi = 0, xn - 1 do
    for yi = 0, yn - 1 do
      for zi = 0, zn - 1 do
        local i = { xi, yi, zi }
        local p = {
          (xi - (xn - 1) / 2) / xn,
          (yi - (yn - 1) / 2) / yn,
          (zi - (zn - 1) / 2) / zn
        }

        if staggered then
          local a = {}
          for d = 1, 3 do
            if n[d] > 1 then
              a[#a + 1] = d
            end
          end

          for k = 1, #a - 1 do
            local d = a[k]
            local by = a[k + 1]
            if i[by] % 2 == 1 then
              p[d] = p[d] + 0.5 / n[d]
            end
          end
        end

        cloud[#cloud + 1] = vector(p[1], p[2], p[3])
      end
    end
  end

  if resize then
    cloud = cloud:scale(xn, yn, zn)
  end

  return cloud
end


function m.random(n)
  n = n or 1
  local cloud = m.new()
  for i = 1, n do
    cloud[i] = vector(
      -1 + 2 * lovr.math.random(),
      -1 + 2 * lovr.math.random(),
      -1 + 2 * lovr.math.random())
  end
  return cloud
end


-- Place n points on line from p1 to p2 (points defined as {x, y, z} or vector)
function m.onLine(p2, p1, n)
  p1 = getmetatable(p1) == getmetatable(vector.up) and p1 or vector(unpack(p1))
  p2 = getmetatable(p2) == getmetatable(vector.up) and p2 or vector(unpack(p2))
  local cloud = m.new()
  for i = 1, n do
    local t = n > 1 and (i - 1) / (n - 1) or 0
    cloud[i] = p1:lerp(p2, t)
  end
  return cloud
end


function m.onCurve(curve, n)
  local segment = curve:getLength() / (n - 1)
  local cloud = m.new()
  for i = 1, n do
    local t = curve:step((i - 1) * segment)
    cloud[#cloud + 1] = vector(curve:evaluate(t))
  end
  return cloud
end


function m.onPlane(n)
  local cloud = m.new()
  local step = 1 / math.sqrt(n > 0 and n or EPSILON)
  for x = -0.5, 0.5, step do
    for z = -0.5, 0.5, step do
      cloud[#cloud + 1] = vector(x, 0, z)
    end
  end
  return cloud
end


--- Distribute n points on surface of a unit sphere (Fibonacci lattice)
function m.onSphere(n)
  local cloud = m.new()
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


--- Distribute n points along the unit circle
function m.onCircle(n)
  local cloud = m.new()
  for i = 1, n do
    local theta = 2 * math.pi * (i - 1) / n
    cloud[i] = vector(
      math.cos(theta),
      0,
      math.sin(theta)
    )
  end
  return cloud
end


--- The 8 points of a unit cube
function m.cube()
  return m.new{{-0.5, -0.5, 0.5},  {0.5, -0.5, 0.5},  {0.5, 0.5, 0.5},  {-0.5, 0.5, 0.5},
               {-0.5, -0.5, -0.5}, {0.5, -0.5, -0.5}, {0.5, 0.5, -0.5}, {-0.5, 0.5, -0.5}}
end


-- Construct cloud from a flexible super-ellipse in XY plane
-- Special cases: e=0 square; e=0.5 rounded square; e=1 circle
function m.superellipse(segments, e)
  local cloud = m.new()
  for gamma = -math.pi, math.pi, math.pi / segments do
    cloud[#cloud + 1] = vector(
      math.abs(math.cos(gamma))^e * sign(math.cos(gamma)),
      math.abs(math.sin(gamma))^e * sign(math.sin(gamma)),
      0) -- Z component is always zero for a 2D shape
  end
  return cloud
end


-- Construct cloud from a flexible super-ellipsoid
--[[ Some special cases for e1, e2 parameters
  0,   1    cylinder
  2,   2    octahedron
  0,   0    cube
  0.5, 0.5  round cube
  1,   1    sphere
  0,   0.5  extruded round rectangle
--]]
function m.superellipsoid(segments, e1, e2)
  e2 = e2 or e1
  local cloud = m.new()
  for theta = -math.pi / 2, math.pi / 2, math.pi / segments do
    for gamma = -math.pi, math.pi, math.pi / segments do
      cloud[#cloud + 1] = vector(
        math.cos(theta)^e1 * math.abs(math.cos(gamma))^e2 * sign(math.cos(gamma)),
        math.cos(theta)^e1 * math.abs(math.sin(gamma))^e2 * sign(math.sin(gamma)),
        math.abs(math.sin(theta))^e1 * sign(math.sin(theta)))
    end
  end
  return cloud
end


function m.fromSolid(solid)
  return m.new(solid.vlist)
end


function m:info()
  return string.format('Pointcloud: %d vertices', #self)
end


function m:toVertices()
  local vs = {}
  for i, dot in ipairs(self) do
    table.insert(vs, { dot.x, dot.y, dot.z })
  end
  return vs
end


function m:map(fn)
  local cloud = self:clone()
  for i, point in ipairs(self) do
    cloud[i] = fn(point, i)
  end
  return cloud
end


function m:lerp(other, alpha)
  assert(#self == #other, 'lerp requires two dots lists of same length')
  local cloud = self:clone()
  for i, point in ipairs(self) do
    cloud[i] = point:lerp(other[i], alpha)
  end
  return cloud
end


-- changes ordering
function m:filter(fn)
  local cloud = m.new()
  local new_from_old = {}
  local new_index = 0
  for i, point in ipairs(self) do
    if fn(point, i) then
      new_index = new_index + 1
      new_from_old[i] = new_index
      cloud[new_index] = point
    end
  end
  cloud.edge_map = {}
  for old_a, edges in pairs(self.edge_map) do
    local new_a = new_from_old[old_a]
    if new_a then
      for old_b, w in pairs(edges) do
        local new_b = new_from_old[old_b]
        if new_b then
          cloud.edge_map[new_a] = cloud.edge_map[new_a] or {}
          cloud.edge_map[new_a][new_b] = w
        end
      end
    end
  end
  return cloud
end


function m:centroid()
  if #self == 0 then
    return vector(0, 0, 0)
  end

  local sum = vector(0, 0, 0)
  for _, point in ipairs(self) do
    sum = sum + point
  end
  return sum * (1 / #self)
end


function m:translate(offset)
  return self:map(function(point)
      return offset + point
    end)
end


function m:transform(transform)
  return self:map(function(point)
      return transform * point
    end)
end


--- Randomize the order of stored points; changes ordering
function m:shuffle()
  local shuffled = m.new(self)
  for i = 1, #shuffled do
    local j = lovr.math.random(1, #shuffled)
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end
  return shuffled
end


--- Displace each point in a random direction
function m:jiggle(amount, time, vertical_scale)
  time = time or 0
  vertical_scale = vertical_scale or 0
  local i = 0
  return self:map(function(point)
    i = i + 1
    return point + vector(
                       amount * (-0.5 + lovr.math.noise(i * 0.17 + time + 0)),
      vertical_scale * amount * (-0.5 + lovr.math.noise(i * 0.17 + time + 3)),
                       amount * (-0.5 + lovr.math.noise(i * 0.17 + time + 7)))
  end)
end


--- Join two or more point clounds into one
function m:add(...)
  local clouds = {self, ...}
  local merged = m.new()
  for _, cloud in ipairs(clouds) do
    local start_index = #merged
    for _, point in ipairs(cloud) do
      table.insert(merged, point)
    end
    for iA, edges in pairs(cloud.edge_map) do
      for iB, w in pairs(edges) do
        merged.edge_map[iA + start_index] = merged.edge_map[iA + start_index] or {}
        merged.edge_map[iA + start_index][iB + start_index] = w
      end
    end
  end
  return merged
end


--- A cartesian product of two cloud points
-- M x N points; each original point being displaced by each point from the other cloud
-- The first operand's edges are preserved, second operand's edges are discarded
function m:mul(other)
  local clouds = {}
  for _, p in ipairs(other) do
    table.insert(clouds, self:transform(mat4(p)))
  end
  return m.new():add(unpack(clouds))
end


-- Remove points for which the closest counterpart in `other` is closer than `distance`
-- The first operand's edges are preserved if both dots survive, second operand's edges are discarded
function m:sub(other, distance)
  distance = distance or 0.1
  return self:filter(function(p)
    for _, o in ipairs(other) do
      if (p - o):length() < distance then
        return false
      end
    end
    return true
  end)
end


-- Multiply all coordinates by a scalar
function m:scale(sx, sy, sz)
  sy = sy or sx
  sz = sz or sx
  return self:transform(mat4():scale(sx, sy, sz))
end


-- Make all the Y components be 0
function m:makeHorizontal()
  local cloud = m.new()
  for _, p1 in ipairs(self) do
    table.insert(cloud, vector(p1.x, 0, p1.z))
  end
  return cloud
end


--- Return the cloud with duplicate points removed, within a given precision, changes ordering
-- For example precision=0.1 the coordinates 0.120 and 0.124 are considered equal while pruning
-- Result depends on point order; last point in a bin survives
function m:prune(precision)
  local bins = {}
  for i,pt in ipairs(self) do
    local h = string.format('%d %d %d',
      math.floor(pt.x / precision + 0.5),
      math.floor(pt.y / precision + 0.5),
      math.floor(pt.z / precision + 0.5))
    bins[h] = i
  end
  local counter = 0
  return self:filter(function(pt)
    counter = counter + 1
    local h = string.format('%d %d %d',
      math.floor(pt.x / precision + 0.5),
      math.floor(pt.y / precision + 0.5),
      math.floor(pt.z / precision + 0.5))
    return bins[h] == counter
  end)
end

--- Progressive ordering / subsampling of an existing point cloud.
-- Based on weighted sample elimination, but implemented directly over the
-- existing Lua point set.
--
-- `count` is the number of existing points to return.
-- If count < #self, it first eliminates down to `count`.
-- Then it recursively orders those selected points so prefixes are well-spread.
local PROGRESSIVE_ALPHA = 8
local PROGRESSIVE_BETA = 0.65
local PROGRESSIVE_GAMMA = 1.5
local PROGRESSIVE_RADIUS_MULT = { 2, math.sqrt(2), 2 ^ (1 / 3) }


function m:progressiveSample(count)
  local n = #self
  if count == nil then
    count = n
  else
    count = math.floor(count)
  end

  local cloud = m.new()
  if n == 0 or count <= 0 then return cloud end
  if count > n then count = n end
  if n == 1 then cloud[1] = self[1]; return cloud end

  local function copyList(t)
    local r = {}
    for i = 1, #t do r[i] = t[i] end
    return r
  end

  local function distance2(i, j)
    local a, b = self[i], self[j]
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2
  end

  local function weightLimitFraction(inputSize, outputSize)
    if inputSize <= outputSize then return 0 end
    local ratio = outputSize / inputSize
    return (1 - ratio ^ PROGRESSIVE_GAMMA) * PROGRESSIVE_BETA
  end

  local function estimateDMax(sampleCount)
    local minx, miny, minz, maxx, maxy, maxz = self:boundingBox()
    local ex = math.abs(maxx - minx)
    local ey = math.abs(maxy - miny)
    local ez = math.abs(maxz - minz)
    local diag = math.sqrt(ex * ex + ey * ey + ez * ez)
    if diag <= 0 then return 1, 3 end

    local extents = { ex, ey, ez }
    table.sort(extents, function(a, b) return a > b end)

    local tolerance = diag * 1e-9
    local dimensions = 0
    for i = 1, 3 do
      if extents[i] > tolerance then dimensions = dimensions + 1 end
    end
    if dimensions < 1 then dimensions = 1 end

    local d_max
    if dimensions >= 3 then
      local volume = extents[1] * extents[2] * extents[3]
      d_max = 2 * (volume / sampleCount / (4 * math.sqrt(2))) ^ (1 / 3)
      dimensions = 3
    elseif dimensions == 2 then
      d_max = 2 * math.sqrt(extents[1] * extents[2] / sampleCount / (2 * math.sqrt(3)))
    else
      d_max = 2 * extents[1] / math.max(sampleCount, 1)
    end
    if d_max <= 0 then d_max = diag end
    if d_max <= 0 then d_max = 1 end
    return d_max, dimensions
  end

  local function pairWeight(i, j, d_max, d_min)
    if d_max <= 0 then return 0 end
    local d2 = distance2(i, j)
    if d2 >= d_max * d_max then return 0 end
    local d = math.sqrt(d2)
    if d < d_min then d = d_min end
    local x = 1 - d / d_max
    if x <= 0 then return 0 end
    return x ^ PROGRESSIVE_ALPHA
  end

  local function eliminateTo(indices, target, d_max, d_min)
    local size = #indices
    if target >= size then return copyList(indices), {} end
    if target < 0 then target = 0 end
    d_min = d_min or 0

    local active = copyList(indices)
    local weight = {}
    for i = 1, #active do weight[active[i]] = 0 end

    if #active > 1024 then
      local grid, cellSize, gridN = {}, d_max * 1.1, 0
      for _, idx in ipairs(active) do
        local p = self[idx]
        local gx = math.floor(p.x / cellSize)
        local gy = math.floor(p.y / cellSize)
        local gz = math.floor(p.z / cellSize)
        local key = gx * 73856093 ^ 2 + gy * 73856093 + gz
        grid[key] = grid[key] or {}
        grid[key][#grid[key] + 1] = idx
        gridN = gridN + 1
      end
      for _, idx in ipairs(active) do
        local p = self[idx]
        local gx = math.floor(p.x / cellSize)
        local gy = math.floor(p.y / cellSize)
        local gz = math.floor(p.z / cellSize)
        for dx = -1, 1 do
          for dy = -1, 1 do
            for dz = -1, 1 do
              local key = (gx + dx) * 73856093 ^ 2 + (gy + dy) * 73856093 + (gz + dz)
              local cell = grid[key]
              if cell then
                for _, nearIdx in ipairs(cell) do
                  if nearIdx > idx then
                    local w = pairWeight(idx, nearIdx, d_max, d_min)
                    if w > 0 then
                      weight[idx] = (weight[idx] or 0) + w
                      weight[nearIdx] = (weight[nearIdx] or 0) + w
                    end
                  end
                end
              end
            end
          end
        end
      end
    else
      for ai = 1, #active - 1 do
        for bi = ai + 1, #active do
          local w = pairWeight(active[ai], active[bi], d_max, d_min)
          if w > 0 then
            weight[active[ai]] = weight[active[ai]] + w
            weight[active[bi]] = weight[active[bi]] + w
          end
        end
      end
    end

    local removed = {}
    while #active > target do
      local maxPos, maxId, maxWeight = 1, active[1], weight[active[1]] or 0
      for pos = 2, #active do
        local id, w = active[pos], weight[active[pos]] or 0
        if w > maxWeight or (w == maxWeight and pos > maxPos) then
          maxWeight, maxPos, maxId = w, pos, id
        end
      end
      table.remove(active, maxPos)
      removed[#removed + 1] = maxId
      weight[maxId] = nil
      for _, id in ipairs(active) do
        local w = pairWeight(maxId, id, d_max, d_min)
        if w > 0 then
          local newW = (weight[id] or 0) - w
          weight[id] = (newW < 0 and newW > -1e-12) and 0 or newW
        end
      end
    end

    local progressiveRemoved = {}
    for i = #removed, 1, -1 do progressiveRemoved[#progressiveRemoved + 1] = removed[i] end
    return active, progressiveRemoved
  end

  local baseDMax, dimensions = estimateDMax(count)
  local radiusMultiplier = PROGRESSIVE_RADIUS_MULT[dimensions]
  local d_min = baseDMax * weightLimitFraction(n, count)

  local function progressiveOrder(indices, currentDMax)
    if #indices < 3 then return copyList(indices) end
    local nextDMax = currentDMax * radiusMultiplier
    local target = math.floor(#indices / 2)
    local survivors, removed = eliminateTo(indices, target, nextDMax, d_min)
    local ordered = progressiveOrder(survivors, nextDMax)
    for i = 1, #removed do ordered[#ordered + 1] = removed[i] end
    return ordered
  end

  local all = {}
  for i = 1, n do all[i] = i end

  local selected = (count < n) and eliminateTo(all, count, baseDMax, d_min) or all
  local ordered = progressiveOrder(selected, baseDMax)
  for i = 1, count do cloud[i] = self[ordered[i]] end
  return cloud
end


-- changes ordering
function m:sortFromCenter()
  local cloud = m.new(self)
  table.sort(cloud, function(a, b) return a:length() < b:length() end)
  return cloud
end


--- Return a cloud with both original points and their symmetries, across 3 major axes
function m:symmetry(with_x, with_y, with_z)
  local cloud = m.new(self)
  if with_x or with_y or with_z then
    if with_x then
      local count = #cloud
      for i = 1, count do
        local point = cloud[i]
        table.insert(cloud, vector(-point.x, point.y, point.z))
      end
    end
    if with_y then
      local count = #cloud
      for i = 1, count do
        local point = cloud[i]
        table.insert(cloud, vector(point.x, -point.y, point.z))
      end
    end
    if with_z then
      local count = #cloud
      for i = 1, count do
        local point = cloud[i]
        table.insert(cloud, vector(point.x, point.y, -point.z))
      end
    end
  end
  return cloud
end


function m:boundingBox()
  if #self == 0 then
    return
  end
  local minx, maxx = self[1].x, self[1].x
  local miny, maxy = self[1].y, self[1].y
  local minz, maxz = self[1].z, self[1].z
  for _, point in ipairs(self) do
    minx = math.min(minx, point.x)
    maxx = math.max(maxx, point.x)
    miny = math.min(miny, point.y)
    maxy = math.max(maxy, point.y)
    minz = math.min(minz, point.z)
    maxz = math.max(maxz, point.z)
  end
  return minx, miny, minz, maxx, maxy, maxz
end


-- Render dots onto pass using geometry of camera-facing circles
function m:draw(pass)
  local pose = mat4()
  local viewPose = pass:getViewPose(1, mat4())
  local q = quaternion(viewPose:getOrientation())
  for i, point in ipairs(self) do
    pose:set(point, vector(m.DOT_SIZE, m.DOT_SIZE, m.DOT_SIZE), q)
    pass:circle(pose, nil, nil, nil, 18)
    if m.DRAW_INDEX then
      pass:text(i, point + vector(0, m.DOT_SIZE * 3, 0), 0.08)
    end
  end
  if self.edge_map then
    for idA, edges in pairs(self.edge_map) do
      for idB, _ in pairs(edges) do
        local pA = self[idA]
        local pB = self[idB]
        pass:cylinder(pA, pB, m.EDGE_SIZE, 7)
      end
    end
  end
end


m.__add = m.add
m.__sub = m.sub
m.__mul = m.mul


------ spatial queries using kd-tree ------
kdtree = {}
kdtree.__index = kdtree


local function metric(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  local dz = a.z - b.z
  return dx*dx + dy*dy + dz*dz
end


local function _heap_swap(h, i, j)
  h[i], h[j] = h[j], h[i]
end


local function _heap_up(h, i)
  while i > 1 do
    local p = math.floor(i / 2)
    if h[p].d2 >= h[i].d2 then break end
    _heap_swap(h, i, p); i = p
  end
end


local function _heap_down(h, i)
  local n = #h
  while true do
    local l = i * 2
    local r = l + 1
    local m = i
    if l <= n and h[l].d2 > h[m].d2 then m = l end
    if r <= n and h[r].d2 > h[m].d2 then m = r end
    if m == i then break end
    _heap_swap(h, i, m); i = m
  end
end


local function _heap_push(h, item, kmax)
  if #h < kmax then
    h[#h + 1] = item
    _heap_up(h, #h)
  elseif kmax > 0 and item.d2 < h[1].d2 then
    h[1] = item
    _heap_down(h, 1)
  end
end


local function treenode(obj, dimension)
  return { obj = obj, left = nil, right = nil, dimension = dimension }
end


local function buildTree(pts, depth)
  local n = #pts
  if n == 0 then return nil end
  local dim = depth % 3
  table.sort(pts, function(a, b)
    if     dim == 0 then return a.x < b.x
    elseif dim == 1 then return a.y < b.y
    else                  return a.z < b.z
    end
  end)
  local mid = math.floor(n / 2) + 1
  local node = treenode(pts[mid], dim)
  local left_pts, right_pts = {}, {}
  for i = 1, mid - 1 do left_pts[#left_pts + 1] = pts[i] end
  for i = mid + 1, n do right_pts[#right_pts + 1] = pts[i] end
  node.left = buildTree(left_pts, depth + 1)
  node.right = buildTree(right_pts, depth + 1)
  return node
end


function kdtree.new(points)
  local self = setmetatable({}, kdtree)
  self.points = {}
  for i, point in ipairs(points) do
    table.insert(self.points, point)
  end
  self.root = buildTree(self.points, 0)
  return self
end


function kdtree:nearest(query_point, n)
  assert(query_point and query_point.x, 'query_point should be a vector or table with x,y,z properties')
  n = n or 1
  if not self.root or n <= 0 then return {} end
  local heap = {}
  local best_obj, best_d2 = nil, math.huge

  local function radius2()
    if n == 1 then
      return best_d2
    else
      if #heap < n then return math.huge else return heap[1].d2 end
    end
  end

  local function offer(d2, obj)
    if (query_point - obj):length() < EPSILON then return end
    if n == 1 then
      if d2 < best_d2 then best_d2, best_obj = d2, obj end
    else
      _heap_push(heap, { d2 = d2, obj = obj }, n)
    end
  end

  local function search(node)
    if not node then return end
    offer(metric(query_point, node.obj), node.obj)
    local dim = node.dimension
    local qv = (dim == 0 and query_point.x) or (dim == 1 and query_point.y) or query_point.z
    local nv = (dim == 0 and node.obj.x)    or (dim == 1 and node.obj.y)    or node.obj.z
    local near = qv < nv and node.left or node.right
    local far  = qv < nv and node.right or node.left
    if near then search(near) end
    local delta = qv - nv
    if delta * delta < radius2() and far then search(far) end
  end

  search(self.root)

  if n == 1 then
    if best_obj then return { best_obj } else return {} end
  end

  local res = {}
  for i = 1, #heap do
    res[i] = heap[i].obj
  end
  return res
end


function m:nearest(query_point, n)
  self.kdtree = self.kdtree or kdtree.new(self)
  local nearest = self.kdtree:nearest(query_point, n)
  local index = nil
  if nearest[1] then
    for i, point in ipairs(self) do
      if (point - nearest[1]):length() < EPSILON then
        index = i
        break
      end
    end
  end
  if not index then print('index not found!') end
  return nearest, index
end


function m:relax(steps, strength)
  local cloud = self:clone()
  local minx, miny, minz, maxx, maxy, maxz = cloud:boundingBox()
  local prev_min = vector(minx, miny, minz)
  local prev_max = vector(maxx, maxy, maxz)
  steps = steps or 10
  strength = strength or (prev_max - prev_min):length() * 0.01
  for _ = 1, steps do
    cloud.kdtree = kdtree.new(cloud)
    for i, point in ipairs(cloud) do
      local nearest = cloud.kdtree:nearest(point, 1)
      if #nearest < 1 then return cloud end
      for _, near in ipairs(nearest) do
        local d = math.max((point - near):length(), 1e-3)
        cloud[i] = point + (point - near):normalize() * (strength / d)
        point = cloud[i]
      end
    end
  end
  local minx2, miny2, minz2, maxx2, maxy2, maxz2 = cloud:boundingBox()
  local new_min = vector(minx2, miny2, minz2)
  local new_max = vector(maxx2, maxy2, maxz2)
  local offset = (prev_min + prev_max - new_min - new_max) * 0.5
  local scale = vector(
    (prev_max.x - prev_min.x) / math.max(new_max.x - new_min.x, 1e-9),
    (prev_max.y - prev_min.y) / math.max(new_max.y - new_min.y, 1e-9),
    (prev_max.z - prev_min.z) / math.max(new_max.z - new_min.z, 1e-9)
  )
  local normalization = mat4():scale(scale.x, scale.y, scale.z):translate(offset)
  for i, point in ipairs(cloud) do
    cloud[i] = normalization * point
  end
  return cloud
end


function m:fillSpace(strength, steps, physics_world, physics_filter)
  local cloud = self:clone()
  local minx, miny, minz, maxx, maxy, maxz = cloud:boundingBox()
  local prev_min = vector(minx, miny, minz)
  local prev_max = vector(maxx, maxy, maxz)
  for _ = 1, steps do
    cloud.kdtree = kdtree.new(cloud)
    for i, point in ipairs(cloud) do
      if physics_world then
        local near = cloud.kdtree:nearest(point, 1)[1]
        if not near then return cloud end
        local prev = point
        local d = math.max((point - near):length(), 1e-3)
        local candidate = point + (point - near):normalize() * (strength / d)
        local hit, _, x, y, z, nx, ny, nz = physics_world:raycast(prev, candidate, nil, physics_filter)
        if nx then
          local stepd = (candidate - prev):length()
          cloud[i] = vector(x, y, z):lerp(prev, 0.9) + vector(nx, ny, nz) * stepd
        else
          cloud[i] = candidate
        end
      else
        local nearest = cloud.kdtree:nearest(point, 1)
        if #nearest < 1 then return cloud end
        for _, near in ipairs(nearest) do
          local d = math.max((point - near):length(), 1e-3)
          cloud[i] = point + (point - near):normalize() * (strength / d)
          point = cloud[i]
        end
      end
    end
  end
  local minx2, miny2, minz2, maxx2, maxy2, maxz2 = cloud:boundingBox()
  local new_min = vector(minx2, miny2, minz2)
  local new_max = vector(maxx2, maxy2, maxz2)
  local offset = (prev_min + prev_max - new_min - new_max) * 0.5
  local scale = vector(
    (prev_max.x - prev_min.x) / math.max(new_max.x - new_min.x, 1e-9),
    (prev_max.y - prev_min.y) / math.max(new_max.y - new_min.y, 1e-9),
    (prev_max.z - prev_min.z) / math.max(new_max.z - new_min.z, 1e-9)
  )
  local normalization = mat4():scale(scale.x, scale.y, scale.z):translate(offset)
  for i, point in ipairs(cloud) do
    cloud[i] = normalization * point
  end
  return cloud
end


function m:proximityConnect(n, longest)
  longest = longest or math.huge
  n = n or 3
  local idFromPoint = {}
  for i, p in ipairs(self) do
    idFromPoint[p] = i
  end
  for i, pA in ipairs(self) do
    local nearests = self:nearest(pA, n)
    for _, pB in ipairs(nearests) do
      local iA = i
      local iB = idFromPoint[pB]
      local weight = (pA - pB):length()
      if weight < longest then
        self.edge_map[iA] = self.edge_map[iA] or {}
        self.edge_map[iB] = self.edge_map[iB] or {}
        self.edge_map[iA][iB] = weight
        self.edge_map[iB][iA] = weight
      end
    end
  end
  return self
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


function m:disconnect()
  local cloud = self:clone()
  cloud.edge_map = {}
  return cloud
end


function m:mst() -- create a copy of dots that reduces the graph to a minimum spanning tree
  local cloud = self:clone()
  local function find(parent, x)
    if parent[x] ~= x then
      parent[x] = find(parent, parent[x])
    end
    return parent[x]
  end

  local function union(parent, rank, a, b)
    local ra, rb = find(parent, a), find(parent, b)
    if ra == rb then return end
    if rank[ra] < rank[rb] then
      parent[ra] = rb
    elseif rank[ra] > rank[rb] then
      parent[rb] = ra
    else
      parent[rb] = ra
      rank[ra] = rank[ra] + 1
    end
  end

  local weighted = {}
  for i, edges in pairs(cloud.edge_map) do
    for j, w in pairs(edges) do
      if i < j then
        assert(cloud[i] ~= nil and cloud[j] ~= nil, "Edge references invalid point index")
        table.insert(weighted, { u = i, v = j, w = w })
      end
    end
  end
  table.sort(weighted, function(a, b) return a.w < b.w end)

  local parent, rank = {}, {}
  for i = 1, #cloud do
    parent[i] = i
    rank[i] = 0
  end

  cloud.edge_map = {}
  for _, e in ipairs(weighted) do
    if find(parent, e.u) ~= find(parent, e.v) then
      union(parent, rank, e.u, e.v)
      cloud.edge_map[e.u] = cloud.edge_map[e.u] or {}
      cloud.edge_map[e.v] = cloud.edge_map[e.v] or {}
      cloud.edge_map[e.u][e.v] = e.w
      cloud.edge_map[e.v][e.u] = e.w
    end
  end

  return cloud
end


function m:pathfind(start_index, goal_index, heuristic_fn)
  -- default heuristic = straight-line distance
  heuristic_fn = heuristic_fn or function(i)
    local a, b = self[i], self[goal_index]
    return a and b and (a - b):length() or math.huge
  end

  if start_index == goal_index then return { start_index } end
  local edges = self.edge_map
  if not edges or not next(edges) then return nil end

  local open_set   = { [start_index] = true }
  local closed_set = {}
  local came_from  = {}
  local g_score    = { [start_index] = 0 }
  local f_score    = { [start_index] = heuristic_fn(start_index) }

  local function popBestNode(set)
    local best, node = math.huge, nil
    for k in pairs(set) do
      local s = f_score[k] or math.huge
      if s < best then best, node = s, k end
    end
    if node then set[node] = nil end
    return node
  end

  local function unwindPath(c_from, current)
    local path = { current }
    while c_from[current] do
      current = c_from[current]
      table.insert(path, 1, current)
    end
    return path
  end

  while next(open_set) do
    local current = popBestNode(open_set)
    if not current then break end
    if current == goal_index then
      return unwindPath(came_from, current)
    end
    closed_set[current] = true

    local neighbors = edges[current]
    if neighbors then
      for neighbor, w in pairs(neighbors) do
        if not closed_set[neighbor] then
          local tentative_g = (g_score[current] or math.huge) + (w or 0)
          if not open_set[neighbor] or tentative_g < (g_score[neighbor] or math.huge) then
            came_from[neighbor] = current
            g_score[neighbor]   = tentative_g
            f_score[neighbor]   = tentative_g + heuristic_fn(neighbor)
            open_set[neighbor]  = true
          end
        end
      end
    end
  end

  return {} -- no path
end



--- triangulation with delaunay ---

-- 3d -> 2d projecting functions; by default use XZ
function m.withXY(vec) return vec.x, vec.y end
function m.withXZ(vec) return vec.x, vec.z end

-- internal triangulator in 0-based index
-- roughly based on https://github.com/mapbox/delaunator/
local function _delaunator(points, getCoords)
  getCoords = getCoords or m.withXZ
  local n = #points
  local coords = {}
  for i = 0, n - 1 do
    local x, y = getCoords(points[i + 1])
    coords[i*2] = x
    coords[i*2 + 1] = y
  end
  local function swap(arr, i, j) arr[i], arr[j] = arr[j], arr[i] end
  local function sort0(ids, dists, n)
    local ids1 = {}
    for i = 0, n - 1 do ids1[i + 1] = ids[i] end
    table.sort(ids1, function(a, b)
      local da, db = dists[a], dists[b]
      return da < db or (da == db and a < b)
    end)
    for i = 0, n - 1 do ids[i] = ids1[i + 1] end
  end
  local function pseudoAngle(dx, dy)
    local p = dx / (math.abs(dx) + math.abs(dy))
    return (dy > 0 and 3 - p or 1 + p) / 4
  end
  local function hashKey(cx, cy, x, y, hashSize)
    return math.floor(pseudoAngle(x - cx, y - cy) * hashSize) % hashSize
  end
  local function inCircle(ax, ay, bx, by, cx, cy, px, py)
    local dx = ax - px; local dy = ay - py
    local ex = bx - px; local ey = by - py
    local fx = cx - px; local fy = cy - py
    local ap = dx * dx + dy * dy
    local bp = ex * ex + ey * ey
    local cp = fx * fx + fy * fy
    return dx * (ey * cp - bp * fy) - dy * (ex * cp - bp * fx) + ap * (ex * fy - ey * fx) < 0
  end
  local function dist(ax, ay, bx, by)
    local dx = ax - bx; local dy = ay - by; return dx * dx + dy * dy
  end
  local function orient2d(ax, ay, bx, by, cx, cy)
    return (ay - cy) * (bx - cx) - (ax - cx) * (by - cy)
  end
  local function circumradius(ax, ay, bx, by, cx, cy)
    local dx = bx - ax; local dy = by - ay
    local ex = cx - ax; local ey = cy - ay
    local bl = dx * dx + dy * dy
    local cl = ex * ex + ey * ey
    local d = 0.5 / (dx * ey - dy * ex)
    local x = (ey * bl - dy * cl) * d
    local y = (dx * cl - ex * bl) * d
    return x * x + y * y
  end
  local function circumcenter(ax, ay, bx, by, cx, cy)
    local dx = bx - ax; local dy = by - ay
    local ex = cx - ax; local ey = cy - ay
    local bl = dx * dx + dy * dy
    local cl = ex * ex + ey * ey
    local d = 0.5 / (dx * ey - dy * ex)
    local x = ax + (ey * bl - dy * cl) * d
    local y = ay + (dx * cl - ex * bl) * d
    return x, y
  end

  local maxTriangles = math.max(2 * n - 5, 0)
  local T, H = {}, {}
  for i = 0, maxTriangles * 3 - 1 do T[i] = 0; H[i] = -1 end

  local hashSize = math.ceil(math.sqrt(n))
  local hullPrev, hullNext, hullTri, hullHash = {}, {}, {}, {}
  for i = 0, n - 1 do hullPrev[i] = 0; hullNext[i] = 0; hullTri[i] = 0 end
  for i = 0, hashSize - 1 do hullHash[i] = -1 end

  local ids, dists = {}, {}
  for i = 0, n - 1 do ids[i] = 0; dists[i] = 0 end

  local triangles_len = 0
  local function link(a, b)
    H[a] = b
    if b ~= -1 then H[b] = a end
  end
  local function addTriangle(i0, i1, i2, a, b, c)
    local t = triangles_len
    T[t] = i0; T[t + 1] = i1; T[t + 2] = i2
    link(t, a); link(t + 1, b); link(t + 2, c)
    triangles_len = triangles_len + 3
    return t
  end
  local function legalize(a, cx, cy)
    local EDGE_STACK_SIZE = 512
    local stack, top = {}, 0
    local function push(x) if top < EDGE_STACK_SIZE then stack[top] = x; top = top + 1 end end
    local function pop() if top == 0 then return nil end; top = top - 1; return stack[top] end
    while true do
      local b = H[a]
      local a0 = a - (a % 3)
      local ar = a0 + ((a + 2) % 3)
      if b == -1 then
        local x = pop(); if not x then return ar else a = x end
      else
        local b0 = b - (b % 3)
        local al = a0 + ((a + 1) % 3)
        local bl = b0 + ((b + 2) % 3)
        local p0 = T[ar]
        local pr = T[a]
        local pl = T[al]
        local p1 = T[bl]
        if inCircle(
          coords[2 * p0], coords[2 * p0 + 1],
          coords[2 * pr], coords[2 * pr + 1],
          coords[2 * pl], coords[2 * pl + 1],
          coords[2 * p1], coords[2 * p1 + 1]) then
          T[a] = p1; T[b] = p0
          local hbl = H[bl]
          if hbl == -1 then
            local e = hullStart
            repeat
              if hullTri[e] == bl then hullTri[e] = a; break end
              e = hullPrev[e]
            until e == hullStart
          end
          link(a, hbl); link(b, H[ar]); link(ar, bl)
          local br = b0 + ((b + 1) % 3)
          push(br)
        else
          local x = pop(); if not x then return ar else a = x end
        end
      end
    end
  end

  local minX, minY = math.huge, math.huge
  local maxX, maxY = -math.huge, -math.huge
  for i = 0, n - 1 do
    local x = coords[2 * i]; local y = coords[2 * i + 1]
    if x < minX then minX = x end
    if y < minY then minY = y end
    if x > maxX then maxX = x end
    if y > maxY then maxY = y end
    ids[i] = i
  end
  local cx = (minX + maxX) / 2
  local cy = (minY + maxY) / 2

  local i0, i1, i2 = 0, 0, 0
  local minDist = math.huge
  for i = 0, n - 1 do
    local d = dist(cx, cy, coords[2 * i], coords[2 * i + 1])
    if d < minDist then i0 = i; minDist = d end
  end
  local i0x, i0y = coords[2 * i0], coords[2 * i0 + 1]
  minDist = math.huge
  for i = 0, n - 1 do
    if i ~= i0 then
      local d = dist(i0x, i0y, coords[2 * i], coords[2 * i + 1])
      if d < minDist and d > 0 then i1 = i; minDist = d end
    end
  end
  local i1x, i1y = coords[2 * i1], coords[2 * i1 + 1]
  local minRadius = math.huge
  for i = 0, n - 1 do
    if i ~= i0 and i ~= i1 then
      local r = circumradius(i0x, i0y, i1x, i1y, coords[2 * i], coords[2 * i + 1])
      if r < minRadius then i2 = i; minRadius = r end
    end
  end
  if minRadius == math.huge then
    for i = 0, n - 1 do dists[i] = (coords[2 * i] - coords[0]) or (coords[2 * i + 1] - coords[1]) or 0 end
    sort0(ids, dists, n)
    return {}, coords
  end
  local i2x, i2y = coords[2 * i2], coords[2 * i2 + 1]
  if orient2d(i0x, i0y, i1x, i1y, i2x, i2y) < 0 then i1, i2 = i2, i1; i1x, i2x = i2x, i1x; i1y, i2y = i2y, i1y end
  local ccx, ccy = circumcenter(i0x, i0y, i1x, i1y, i2x, i2y)
  for i = 0, n - 1 do dists[i] = dist(coords[2 * i], coords[2 * i + 1], ccx, ccy) end
  sort0(ids, dists, n)

  local hullStart = i0
  local hullSize = 3
  hullNext[i0] = i1; hullPrev[i2] = i1
  hullNext[i1] = i2; hullPrev[i0] = i2
  hullNext[i2] = i0; hullPrev[i1] = i0
  hullTri[i0] = 0; hullTri[i1] = 1; hullTri[i2] = 2
  for i = 0, hashSize - 1 do hullHash[i] = -1 end
  hullHash[hashKey(ccx, ccy, i0x, i0y, hashSize)] = i0
  hullHash[hashKey(ccx, ccy, i1x, i1y, hashSize)] = i1
  hullHash[hashKey(ccx, ccy, i2x, i2y, hashSize)] = i2

  triangles_len = 0
  addTriangle(i0, i1, i2, -1, -1, -1)
  local xp, yp = 0, 0
  for k = 0, n - 1 do
    local i = ids[k]
    local x = coords[2 * i]; local y = coords[2 * i + 1]
    if k > 0 and math.abs(x - xp) <= EPSILON and math.abs(y - yp) <= EPSILON then goto continue end
    xp, yp = x, y
    if i == i0 or i == i1 or i == i2 then goto continue end

    local start = 0
    for j = 0, hashSize - 1 do
      start = hullHash[(hashKey(ccx, ccy, x, y, hashSize) + j) % hashSize]
      if start ~= -1 and start ~= hullNext[start] then break end
    end
    start = hullPrev[start]
    local e = start
    local q
    repeat
      q = hullNext[e]
      if orient2d(x, y, coords[2 * e], coords[2 * e + 1], coords[2 * q], coords[2 * q + 1]) >= 0 then
        e = q
        if e == start then e = -1; break end
      else break end
    until false
    if e == -1 then goto continue end

    local t = addTriangle(e, i, hullNext[e], -1, -1, hullTri[e])
    hullTri[i] = legalize(t + 2, ccx, ccy)
    hullTri[e] = t
    hullSize = hullSize + 1

    local nh = hullNext[e]
    repeat
      q = hullNext[nh]
      if orient2d(x, y, coords[2 * nh], coords[2 * nh + 1], coords[2 * q], coords[2 * q + 1]) < 0 then
        t = addTriangle(nh, i, q, hullTri[i], -1, hullTri[nh])
        hullTri[i] = legalize(t + 2, ccx, ccy)
        hullNext[nh] = nh
        hullSize = hullSize - 1
        nh = q
      else break end
    until false

    if e == start then
      repeat
        q = hullPrev[e]
        if orient2d(x, y, coords[2 * q], coords[2 * q + 1], coords[2 * e], coords[2 * e + 1]) < 0 then
          t = addTriangle(q, i, e, -1, hullTri[e], hullTri[q])
          legalize(t + 2, ccx, ccy)
          hullTri[q] = t
          hullNext[e] = e
          hullSize = hullSize - 1
          e = q
        else break end
      until false
    end

    hullStart = e
    hullPrev[i] = e; hullNext[e] = i
    hullPrev[nh] = i; hullNext[i] = nh
    hullHash[hashKey(ccx, ccy, x, y, hashSize)] = i
    hullHash[hashKey(ccx, ccy, coords[2 * e], coords[2 * e + 1], hashSize)] = e
    ::continue::
  end

  local triangles = {}
  for i = 0, triangles_len - 1 do triangles[i + 1] = T[i] + 1 end
  return triangles, coords
end

m._delaunator = _delaunator

function m:triangulate(getCoords)
  local triangles, _ = _delaunator(self, getCoords)
  self.edge_map = self.edge_map or {}
  for i = 1, #triangles, 3 do
    local i1, i2, i3 = triangles[i], triangles[i + 1], triangles[i + 2]
    local p1, p2, p3 = self[i1], self[i2], self[i3]
    local w12 = (p1 - p2):length()
    local w23 = (p2 - p3):length()
    local w31 = (p3 - p1):length()

    self.edge_map[i1] = self.edge_map[i1] or {}
    self.edge_map[i2] = self.edge_map[i2] or {}
    self.edge_map[i3] = self.edge_map[i3] or {}

    self.edge_map[i1][i2] = math.min(self.edge_map[i1][i2] or math.huge, w12)
    self.edge_map[i2][i1] = math.min(self.edge_map[i2][i1] or math.huge, w12)

    self.edge_map[i2][i3] = math.min(self.edge_map[i2][i3] or math.huge, w23)
    self.edge_map[i3][i2] = math.min(self.edge_map[i3][i2] or math.huge, w23)

    self.edge_map[i3][i1] = math.min(self.edge_map[i3][i1] or math.huge, w31)
    self.edge_map[i1][i3] = math.min(self.edge_map[i1][i3] or math.huge, w31)
  end
  return self
end

function m:voronoiCells(remove_boundary, getCoords)
  remove_boundary = not not remove_boundary
  local triangles, coords = _delaunator(self, getCoords or m.withXZ)
  local n = #self
  local bbminx, bbminy = math.huge, math.huge
  local bbmaxx, bbmaxy = -math.huge, -math.huge
  for i = 0, n - 1 do
    local x = coords[2 * i]; local y = coords[2 * i + 1]
    bbminx = math.min(bbminx, x); bbminy = math.min(bbminy, y)
    bbmaxx = math.max(bbmaxx, x); bbmaxy = math.max(bbmaxy, y)
  end

  local tris0 = {}
  for t = 1, #triangles, 3 do
    local p0 = triangles[t] - 1
    local p1 = triangles[t + 1] - 1
    local p2 = triangles[t + 2] - 1
    local id = math.floor((t - 1) / 3)
    tris0[id] = { p0, p1, p2 }
  end

  local point_tris = {}
  for i = 0, n - 1 do point_tris[i] = {} end
  for id, tri in pairs(tris0) do
    for _, p in ipairs(tri) do table.insert(point_tris[p], id) end
  end

  local function circumcenter(ax, ay, bx, by, cx, cy)
    local dx = bx - ax; local dy = by - ay
    local ex = cx - ax; local ey = cy - ay
    local bl = dx * dx + dy * dy
    local cl = ex * ex + ey * ey
    local d = 0.5 / (dx * ey - dy * ex)
    local x = ax + (ey * bl - dy * cl) * d
    local y = ay + (dx * cl - ex * bl) * d
    return x, y
  end

  -- cells is { dot_from_cell = {}, first_cell, second_cell, {p1, p2, p3, ...} }
  local cells = {}
  cells.dot_from_cell = {}

  for i = 0, n - 1 do
    local px, py = coords[2 * i], coords[2 * i + 1]
    local tri_list = point_tris[i]
    if #tri_list >= 3 then
      local centers = {}
      for _, tid in ipairs(tri_list) do
        local tri = tris0[tid]
        local p0, p1, p2 = tri[1], tri[2], tri[3]
        local cx, cy = circumcenter(
          coords[2 * p0], coords[2 * p0 + 1],
          coords[2 * p1], coords[2 * p1 + 1],
          coords[2 * p2], coords[2 * p2 + 1])
        table.insert(centers, { x = cx, y = cy })
      end

      table.sort(centers, function(a, b)
        return math.atan2(a.y - py, a.x - px) < math.atan2(b.y - py, b.x - px)
      end)

      local poly, inside = {}, true
      for _, c in ipairs(centers) do
        table.insert(poly, vector(c.x, 0, c.y))
        if c.x > bbmaxx or c.y > bbmaxy or c.x < bbminx or c.y < bbminy then inside = false end
      end

      if #poly >= 3 and (inside or not remove_boundary) then
        table.insert(cells, poly)
        cells.dot_from_cell[#cells] = i + 1
      end
    end
  end

  return cells
end

return m
