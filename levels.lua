local dispensers = require'dispensers'
local palettes = require'palettes'
local solids = require'solids'
local speck = require'speck'
local dots = require'dots'

local m = {}

local blob_spawners = [==[{color={0.2392,0.2996,0.2538},drawers={{name="spheres",param={radius=0.0281,segments=14.05}}},emit_rate=1366,lifetime=0.8392,lifetime_random=0.1,lightness_random=0.25,movers={{name="size fade",param={strength=1.552,target=1.541,tau=0.4892}},{name="size fade",param={strength=1.324,target=0.06091,tau=0.9372}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="cube",param={size=15.11}}},streaming=true,velocity={__type="vector",x=0,y=0,z=0},velocity_random=1e-05}]==]
local explode_pe = [==[{color={0.9808,0.9543,0},drawers={{name="spheres",param={radius=2.5,segments=8}}},emit_rate=300,lifetime=0.5,lifetime_random=0.6473,lightness_random=0.25,movers={{name="size fade",param={strength=1,target=0.252,tau=0.6625}},{name="color fade",param={color={1,0.489,0.02891,1},strength=0.5005,tau=1e-05}},{name="color fade",param={color={0.3333,0,0,1},strength=1.002,tau=1.109}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="cube",param={size=0.1}}},streaming=false,velocity={__type="vector",x=0,y=0,z=0},velocity_random=12}]==]

local endgame_pe1 = [==[{color={0.9177,0.4387,0.01571},drawers={{name="lines",param={length=22.69,segments=4.855,thickness=0.3319}}},emit_rate=70,lifetime=7.276,lifetime_random=0.1713,lightness_random=0.9404,movers={{name="noisy",param={frequency=0.8044,strength=21.69,time_amp=0.1}},{name="attractor",param={position={__type="vector",x=0,y=0,z=0},relative=false,strength=400}},{name="color fade",param={color={0,0.9618,1,1},strength=0.4662,tau=0.5198}},{name="color fade",param={color={1,0.9429,0,1},strength=0.5712,tau=0.968}},{name="dampener",param={only_vertical=false,strength=0.1}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="cube",param={size=0.698}}},streaming=false,velocity={__type="vector",x=0,y=0,z=0},velocity_random=20}]==]
local endgame_pe2 = [==[{color={0.28,0.4725,1},drawers={{name="spheres",param={radius=0.5403,segments=17.54}}},emit_rate=71.53,lifetime=0.1038,lifetime_random=0.1,lightness_random=0.8331,movers={{name="size fade",param={strength=1,target=5,tau=0.15}},{name="size fade",param={strength=1,target=0.01,tau=0.9}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="cube",param={size=1.716}}},streaming=false,velocity={__type="vector",x=0,y=0,z=0},velocity_random=0.2}]==]

local endgame_emitter_1 = speck.emitterFromString(endgame_pe1)
local endgame_emitter_2 = speck.emitterFromString(endgame_pe2)

local explode_emitter = speck.emitterFromString(explode_pe)

local LAYER_COUNT = 9

m.radii = { 40 }
for i = 2, LAYER_COUNT do m.radii[i] = -80 + 30 * i + lovr.math.randomNormal(20, 0) + i * i * 2 end
m.radii[LAYER_COUNT] = m.radii[LAYER_COUNT] + 50
m.radii[0] = 0

local COLUMN_RADIUS = 24
local SHELL_THICKNESS = 4
local HATCH_ROTATION = 1.5


local BLAST_RADIUS = 40
local EXPLOSION_RADIUS = 50
local EXPLOSION_FORCE = 5e8

local BROADCAST_R = 40


local castshape = lovr.physics.newSphereShape(1)

local full_shell = solids.sphere(1):scale(2)
local shell_mesh = full_shell:clone()
local doorhatch = solids.fromVertices({
  shell_mesh.vlist[shell_mesh.ilist[#shell_mesh.ilist - 2]],
  shell_mesh.vlist[shell_mesh.ilist[#shell_mesh.ilist - 1]],
  shell_mesh.vlist[shell_mesh.ilist[#shell_mesh.ilist]]
  })
doorhatch:mergeIn(doorhatch:flipWinding())

shell_mesh.ilist[#shell_mesh.ilist] = nil -- cut away one face
shell_mesh.ilist[#shell_mesh.ilist] = nil
shell_mesh.ilist[#shell_mesh.ilist] = nil
shell_mesh:mergeIn(shell_mesh:flipWinding())

local hatch_lock_mesh = solids.bipyramid(5):scale(8, 12, 8)


local function getRange(layer)
  if layer > 1 then
    return m.radii[layer - 1], m.radii[layer]
  else
    return 0, m.radii[layer]
  end
end

local function randomPosInLayer(layer, padding)
  padding = padding or 5
  local r1, r2 = getRange(layer)
  local r = r1 + padding + (r2 - r1 - padding * 2) * lovr.math.random()
  return r * vector(lovr.math.random(), lovr.math.random(), lovr.math.random()):normalize()
end


m.barrels = {}

function m.addBarrel(pos, layer)
  local barrel = m.world:newCylinderCollider(pos, 2, 5)
  barrel:setOrientation(quaternion.euler(lovr.math.random() * 2 * math.pi, lovr.math.random() * 2 * math.pi, lovr.math.random() * 2 * math.pi))
  barrel:setMass(barrel:getMass() / 4)
  barrel:setAwake(false)
  barrel:setTag('barrel')
  table.insert(m.barrels, {
      collider = barrel,
      color = palettes[layer][1 + #m.barrels % #palettes[layer]]
    })
  return barrel
end


function m.explodeBarrel(collider)
  if collider:isDestroyed() then return end
  local position = vector(collider:getPosition())
  explode_emitter:setPosition(position)
  explode_emitter:burst()
  collider:destroy()
  local lock_broken = false
  m.world:overlapShape(castshape, position, quaternion(), BLAST_RADIUS, 'hatch_lock',
    function(collider, shape, x, y, z)
      collider:setKinematic(false)
      collider:setAwake(true)
      collider:setLinearVelocity(vector(collider:getWorldVector(0,-1,0)) * 1e2)
      lock_broken = true
    end)
  m.world:overlapShape(castshape, position, nil, EXPLOSION_RADIUS, nil,
    function(collider, shape, x, y, z)
      local pos = vector(x, y, z)
      local dir = (pos - position):normalize()
      collider:applyForce(dir * EXPLOSION_FORCE)
    end)
  for i, barrel in ipairs(m.barrels) do
    if barrel.collider == collider then
      table.remove(m.barrels, i)
      break
    end
  end
  if lock_broken then
    local unlocked_count = m.getLockedCount(current_level)
    if unlocked_count == 2 then
      addText('one lock broken, two remain')
    elseif unlocked_count == 1 then
      addText('two locks broken, one remain')
    elseif unlocked_count == 0 then
      addText('the hatch is unlocked\ni can infiltrate deeper')
      m.unlockHatch(current_level)
      m.changeLayer(current_level, current_level - 1)
    end
  end
end


function m.generate(world, klaxons, boxxer)
  m.world = world
  m.klaxons = klaxons
  m.boxxer = boxxer
  m.hatch_triangles = {}
  m.hatch_sensors = {}
  m.hatch_positions = {}
  m.layer_meshes = {}
  m.barrel_seeds = {}
  m.dispenser_poses = {}
  m.hatch_locks = {}
  m.hatch_sensor_meshes = {}
  for i = 1, LAYER_COUNT do
    m.barrel_seeds[i] = {}
    m.hatch_locks[i] = {}
    m.hatch_triangles[i] = {}
    m.dispenser_poses[i] = {}
    local midradius = m.radii[i] * 0.5 + m.radii[i - 1] * 0.5

    local palette = palettes[i]
    local mesh = solids.new()
    m.layer_meshes[i] = mesh
    local outer_sphere = (i < LAYER_COUNT and shell_mesh or full_shell)
        :clone()
        :transform(mat4():scale(m.radii[i]):rotate(2 * math.pi * i / LAYER_COUNT * HATCH_ROTATION, 0,1,0))
        :flipWinding()
        :setColor(palette[5])
    local outer_collider = world:newMeshCollider(outer_sphere.vlist, outer_sphere.ilist)
    outer_collider:setTag('level')
    mesh:mergeIn(outer_sphere)

    if i > 1 then
      ---[[ INNER SPHERE
      local inner_sphere = shell_mesh
          :clone()
          :transform(mat4():scale(m.radii[i-1] + SHELL_THICKNESS):rotate(2 * math.pi * (i - 1) / LAYER_COUNT * HATCH_ROTATION, 0,1,0))
          :setColor(palette[4])
      local inner_collider = world:newMeshCollider(inner_sphere.vlist, inner_sphere.ilist)
      inner_collider:setTag('level')
      mesh:mergeIn(inner_sphere)
      --]]

      ---[[ HATCH SENSOR
      local hatch = doorhatch
          :clone()
          :transform(mat4():scale(m.radii[i-1] + SHELL_THICKNESS):rotate(2 * math.pi * (i-1) / LAYER_COUNT * HATCH_ROTATION, 0,1,0))
      hatch:updateNormals()
      local hatch_normal = vector(hatch.vlist[1][4], hatch.vlist[1][5], hatch.vlist[1][6])
      local hatch_sensor = world:newMeshCollider(hatch.vlist, hatch.ilist)
      hatch_sensor:setTag('hatch_sensor')
      hatch_sensor:setSensor(false)
      m.hatch_sensors[i] = hatch_sensor
      m.hatch_sensor_meshes[i] = hatch
      --]]
      ---[[ HATCH FRAME VISUALS
      local pA = vector(unpack(hatch.vlist[1])) - SHELL_THICKNESS/3 * hatch_normal
      local pB = vector(unpack(hatch.vlist[2])) - SHELL_THICKNESS/3 * hatch_normal
      local pC = vector(unpack(hatch.vlist[3])) - SHELL_THICKNESS/3 * hatch_normal

      m.hatch_positions[i] = (pA + pB + pC) / 3

      ---[[ HATCH LOCKS
      local lock_positions = {}
      lock_positions[1] = (pA + pB) / 2
      lock_positions[2] = (pB + pC) / 2
      lock_positions[3] = (pC + pA) / 2
      for j, lock_position in ipairs(lock_positions) do
        lock_position = m.hatch_positions[i]:lerp(lock_position, 1.3)
        lock_position = lock_position + lock_position:normalize() * 2.5
        local hatch_lock_collider = world:newConvexCollider(lock_position, hatch_lock_mesh.vlist)
        hatch_lock_collider:setOrientation(quaternion.lookdir(lock_position) * quaternion(math.pi/2, 1,0,0))
        hatch_lock_collider:setKinematic(true)
        hatch_lock_collider:setTag('hatch_lock')
        table.insert(m.hatch_locks[i], hatch_lock_collider)
      end

      --]]

      --[[
      local hatch_broadcast = world:newSphereCollider(m.hatch_positions[i] + BROADCAST_R * m.hatch_positions[i]:normalize(), BROADCAST_R)
      hatch_broadcast:setTag('hatch_broadcast')
      hatch_broadcast:setSensor(true)
      hatch_broadcast:setKinematic(true)
      --]]

      mesh:mergeIn(solids.cylinder(6)
            :transform(mat4()
              :translate((pA + pB) * 0.5)
              :rotate(quaternion.lookdir(pA - pB))
              :rotate(math.pi / 2, 1, 0, 0)
              :scale(SHELL_THICKNESS, pA:distance(pB), SHELL_THICKNESS))
            :setColor(palette[3]))
      mesh:mergeIn(solids.cylinder(6)
            :transform(mat4()
              :translate((pB + pC) * 0.5)
              :rotate(quaternion.lookdir(pB - pC))
              :rotate(math.pi / 2, 1, 0, 0)
              :scale(SHELL_THICKNESS, pB:distance(pC), SHELL_THICKNESS))
            :setColor(palette[3]))
      mesh:mergeIn(solids.cylinder(6)
            :transform(mat4()
              :translate((pC + pA) * 0.5)
              :rotate(quaternion.lookdir(pC - pA))
              :rotate(math.pi / 2, 1, 0, 0)
              :scale(SHELL_THICKNESS, pC:distance(pA), SHELL_THICKNESS))
            :setColor(palette[3]))
      --]]
      ---[[ HATCH COLLIDERS
      local pAB = pA:lerp(pB, 0.5);local pBC = pB:lerp(pC, 0.5);local pCA = pC:lerp(pA, 0.5)
      local triangles = {{pA, pAB, pCA}, {pAB, pB, pBC}, {pCA, pBC, pC}, {pAB, pBC, pCA}}
      for _, triangle in ipairs(triangles) do
        local pA, pB, pC = unpack(triangle)
        local center = (pA + pB + pC) / 3
        --pA = pA:lerp(center, 0.15); pB = pB:lerp(center, 0.15); pC = pC:lerp(center, 0.15)
        pA = pA + (center - pA):normalize() * 3
        pB = pB + (center - pB):normalize() * 3
        pC = pC + (center - pC):normalize() * 3
        local points = {
          pA, pB, pC,
          pA - hatch_normal * SHELL_THICKNESS, pB - hatch_normal * SHELL_THICKNESS, pC - hatch_normal * SHELL_THICKNESS
        }
        local hatch_mesh, hatch_shape = solids.convexHull(points)
        local hatch_collider = world:newCollider(0, 0, 0)
        hatch_collider:setTag('hatch')
        hatch_collider:addShape(hatch_shape)
        hatch_collider:setKinematic(true)
        hatch_mesh = hatch_mesh:setColor(palette[4])
        hatch_mesh.collider = hatch_collider
        table.insert(m.hatch_triangles[i], hatch_mesh)
      end
      --]]
    end
    if i < LAYER_COUNT then
      dots.onSphere(3 + midradius * midradius / 8000):scale(midradius):map(function(pC)
        local c, _, x, y, z, nx, ny, nz = world:raycast(pC, pC * 10)
        local p = vector(x, y, z)
        if c and not world:overlapShape(castshape, p, nil, COLUMN_RADIUS * 2, 'hatch_sensor') then
          table.insert(m.dispenser_poses[i], mat4():target(p, p + vector(nx, ny, nz)))
        end
      end)
      print(#m.dispenser_poses[i], 'dispensers on level', i, 'with r', midradius)
    end
  end
  --m.initial_boxxer_position = randomPosInLayer(#m.radii, 20)
  local r = m.radii[LAYER_COUNT] * 0.5 + m.radii[LAYER_COUNT - 1] * 0.5
  local ax, ay, az = quaternion.lookdir(m.hatch_positions[LAYER_COUNT]):toeuler()
  ax = ax + 0.5
  ay = ay + 0.5
  az = az + 0.5
  m.initial_boxxer_position = quaternion.euler(ax, ay, az):direction() * r
  --m.initial_boxxer_position = m.hatch_positions[LAYER_COUNT]:normalize() + 1000 * vector(lovr.math.random() - 0.5, lovr.math.random() - 0.5, lovr.math.random() - 0.5)
  --m.initial_boxxer_position = m.initial_boxxer_position:normalize() * r
  m.initial_boxxer_orientation = quaternion.lookdir(m.hatch_positions[LAYER_COUNT] - m.initial_boxxer_position)



  local function firstLayer(mesh, palette, layer) -- trail of barrels
    local origin = m.initial_boxxer_position
    local target = m.hatch_positions[LAYER_COUNT]
    local r = (origin:length() + target:length()) * 0.5
    --r = origin:length()
    local n = origin:distance(target) / 40
    local qo = quaternion.lookdir(origin)
    local qt = quaternion.lookdir(target)
    for i = 1, n do
      local p = qo:slerp(qt, i / (n + 1)):direction() * r
      table.insert(m.barrel_seeds[layer], p)
      local c, _, x, y, z, nx, ny, nz = world:raycast(p, vector(0))
      local interpos = vector(x, y, z)
      if c and not world:overlapShape(castshape, interpos, nil, COLUMN_RADIUS * 2, 'hatch_sensor') then
        table.insert(m.dispenser_poses[layer], mat4():target(interpos, interpos + vector(nx, ny, nz)))
      end
    end
  end
  local generation_functions = {
    ---[==[ columns top to bottom
    function(mesh, palette, layer)
      local i = layer
      dots.onSphere(25):scale(m.radii[i] * 0.5 + m.radii[i - 1] * 0.5):map(
        function(pC)
          local colliderA, _, x, y, z = world:raycast(pC, vector(0))
          local pA = vector(x, y, z)
          local colliderB, _, x, y, z = world:raycast(pC, pC * 2.5)
          local pB = vector(x, y, z)
          pA = (pA:length() - SHELL_THICKNESS / 3) * pA:normalize()
          if colliderA and not world:overlapShape(castshape, pA, nil, COLUMN_RADIUS * 2, 'hatch_sensor') and
             colliderB and not world:overlapShape(castshape, pB, nil, COLUMN_RADIUS * 2, 'hatch_sensor') then
            local column = solids.cylinder(8)
              :transform(mat4()
                :translate((pA + pB) * 0.5)
                :rotate(quaternion.lookdir(pA - pB))
                :rotate(math.pi / 2, 1, 0, 0)
                :scale(COLUMN_RADIUS, pA:distance(pB), COLUMN_RADIUS))
              :setColor(palette[2])
            mesh:mergeIn(column)
            mesh:mergeIn(solids.cylinder(8) -- column base
              :transform(mat4()
                :translate(pA + (pB - pA):normalize() * 2)
                :rotate(quaternion.lookdir(pA - pB))
                :rotate(math.pi / 2, 1, 0, 0)
                :scale(COLUMN_RADIUS * 1.5, 5, COLUMN_RADIUS * 1.5))
              :setColor(palette[2]))
            local column_collider = world:newMeshCollider(column.vlist, column.ilist)
            column_collider:setTag('level')
          end
        end)
    end,
    --]==]

    ---[==[ prison bars
    function(mesh, palette, layer)
      local COLUMN_RADIUS = COLUMN_RADIUS / 3
      local midradius = m.radii[layer] * 0.5 + m.radii[layer - 1] * 0.5
      dots.onSphere(15):scale(midradius):map(
        function(origin)
          local target = origin:normalize() + 3 * vector(lovr.math.random() - 0.5, lovr.math.random() - 0.5, lovr.math.random() - 0.5)
          target = target:normalize() * midradius
          local n = origin:distance(target) / 25 + 3
          print('prison column length', n)
          local qo = quaternion.lookdir(origin)
          local qt = quaternion.lookdir(target)
          for i = 1, n do
            local pC = qo:slerp(qt, i / (n + 1)):direction() * midradius
            local colliderA, _, x, y, z = world:raycast(pC, vector(0))
            local pA = vector(x, y, z)
            local colliderB, _, x, y, z = world:raycast(pC, pC * 2.5)
            local pB = vector(x, y, z)
            pA = (pA:length() - SHELL_THICKNESS / 3) * pA:normalize()
            if colliderA and not world:overlapShape(castshape, pA, nil, COLUMN_RADIUS * 2, 'hatch_sensor') and
               colliderB and not world:overlapShape(castshape, pB, nil, COLUMN_RADIUS * 2, 'hatch_sensor') then
              local column = solids.cylinder(8)
                :transform(mat4()
                  :translate((pA + pB) * 0.5)
                  :rotate(quaternion.lookdir(pA - pB))
                  :rotate(math.pi / 2, 1, 0, 0)
                  :scale(COLUMN_RADIUS, pA:distance(pB), COLUMN_RADIUS))
                :setColor(palette[2])
              mesh:mergeIn(column)
              mesh:mergeIn(solids.cylinder(8) -- column base
                :transform(mat4()
                  :translate(pA + (pB - pA):normalize() * 2)
                  :rotate(quaternion.lookdir(pA - pB))
                  :rotate(math.pi / 2, 1, 0, 0)
                  :scale(COLUMN_RADIUS * 1.5, 5, COLUMN_RADIUS * 1.5))
                :setColor(palette[2]))
              local column_collider = world:newMeshCollider(column.vlist, column.ilist)
              column_collider:setTag('level')
            end
          end
        end)
    end,
    --]==]

    ---[==[ columns on outer
    function(mesh, palette, layer)
      local i = layer
      local max_height = (m.radii[i] - m.radii[i - 1]) - 40
      dots.onSphere(80):scale(m.radii[i] * 0.5 + m.radii[i - 1] * 0.5):map(
        function(pC)
          local colliderB, _, x, y, z = world:raycast(pC, pC * 2.5)
          local pB = vector(x, y, z)
          if colliderB and not world:overlapShape(castshape, pB, nil, COLUMN_RADIUS * 2, 'hatch_sensor') then
            local pA = pB - pB:normalize() * (6 + max_height * lovr.math.random())
            local column = solids.cylinder(8)
              :transform(mat4()
                :translate((pA + pB) * 0.5)
                :rotate(quaternion.lookdir(pA - pB))
                :rotate(math.pi / 2, 1, 0, 0)
                :scale(COLUMN_RADIUS, pA:distance(pB), COLUMN_RADIUS))
              :setColor(palette[2])
            mesh:mergeIn(column)
            mesh:mergeIn(solids.cylinder(8) -- column base
              :transform(mat4()
                :translate(pB + (pA - pB):normalize() * 3.5)
                :rotate(quaternion.lookdir(pB - pA))
                :rotate(math.pi / 2, 1, 0, 0)
                :scale(COLUMN_RADIUS * 1.5, 7, COLUMN_RADIUS * 1.5))
              :setColor(palette[2]))
            local column_collider = world:newMeshCollider(column.vlist, column.ilist)
            column_collider:setTag('level')
          end
        end)
    end,
    --]==]

    ---[==[ barrel clusters
    function(mesh, palette, layer)
      local arrangement = dots.onSphere(35):scale(m.radii[layer] * 0.5 + m.radii[layer - 1] * 0.5)
      local cluster = dots.onSphere(8):scale(10)
      local count = 0
      for i, p in ipairs(arrangement) do
        if lovr.math.random() > 0.7 then
          mesh:mergeIn(solids.sphere(1)
            :transform(mat4(p):scale(10 + 20 * lovr.math.random()))
            :setColor(palette[1 + i % #palette]))
        else
          for j, pos in ipairs(cluster:transform(mat4(p))) do
            table.insert(m.barrel_seeds[layer], pos)
            count = count + 1
          end
        end
      end
      print('prepared', count, 'barrels')
    end,

    ---[==[ rails
    function(mesh, palette, layer)
      local midradius = m.radii[layer] * 0.5 + m.radii[layer - 1] * 0.5
      local height = 10
      local COLUMN_RADIUS = 3
      local RAIL_RADIUS = 5
      local tips = {}
      local arrangement = dots.onSphere(35):transform(mat4():rotate(lovr.math.random() * 2 * math.pi):scale(midradius))
      arrangement:map(function(pC)
        local colliderB, _, x, y, z, nx, ny, nz = world:raycast(pC, pC * 4)
        local pB = vector(x, y, z)
        if colliderB and not world:overlapShape(castshape, pB, nil, COLUMN_RADIUS * 2, 'hatch_sensor') then
          local pA = pB + vector(nx, ny, nz) * height
          table.insert(tips, pA)
          local column = solids.cylinder(8)
            :transform(mat4()
              :translate((pA + pB) * 0.5)
              :rotate(quaternion.lookdir(pA - pB))
              :rotate(math.pi / 2, 1, 0, 0)
              :scale(COLUMN_RADIUS, pA:distance(pB), COLUMN_RADIUS))
            :setColor(palette[2])
          mesh:mergeIn(column)
        end
      end)
      tips = dots.new(tips):hamiltonianConnect(start_index)
      for iA, edges in pairs(tips.edge_map) do
        for iB, w in pairs(edges) do
          local pA = tips[iA]
          local pB = tips[iB]
          print('rail', iA, iB, 'layer', layer)
          local rail = solids.cylinder(4)
            :transform(mat4()
              :translate((pA + pB) * 0.5)
              :rotate(quaternion.lookdir(pA - pB))
              :rotate(math.pi / 2, 1, 0, 0)
              :scale(RAIL_RADIUS, pA:distance(pB), RAIL_RADIUS))
            :setColor(palette[1 + (iA + iB) % #palette])
          mesh:mergeIn(rail)
        end
      end
    end,
    --]==]

    --[==[ template
    function(mesh, palette, layer)
    end,
    --]==]
  }

  local deck = {}
  for i = 2, LAYER_COUNT do
    local palette = palettes[i]
    local mesh = m.layer_meshes[i]
    if i == LAYER_COUNT then
      firstLayer(mesh, palette, i)
    else
      if #deck == 0 then
        for j = 1, #generation_functions do
          table.insert(deck, j)
        end
        for j = 1, #generation_functions do
          local k = lovr.math.random(1, #generation_functions)
          deck[j], deck[k] = deck[k], deck[j]
        end
      end
      local gen_index = 5-- table.remove(deck)
      print('using generation fn', gen_index)
      generation_functions[gen_index](mesh, palette, i)
    end
  end

--[=[
  local layer = 2
  for i = 1, 100 do
    local barrel = world:newCylinderCollider(
      (math.random() - 0.5) * 80, (math.random() - 0.5) * 80, (math.random() - 0.5) * 80,
      2, 5)
    barrel:setOrientation(quaternion.euler(lovr.math.random() * 2 * math.pi, lovr.math.random() * 2 * math.pi, lovr.math.random() * 2 * math.pi))
    barrel:setMass(barrel:getMass() / 4)
    --barrel:setAwake(false)
    table.insert(m.layer_barrels[layer], {
        collider = barrel,
        color = palettes[layer][1 + i % #palettes[layer]]
      })
  end
--]=]
end


function m.getLockedCount(layer)
  local remaining_locked = 0
  for i, lock in ipairs(m.hatch_locks[layer]) do
    remaining_locked = remaining_locked + (lock:isKinematic() and 1 or 0)
  end
  return remaining_locked
end

function m.unlockHatch(layer)
  if not m.hatch_sensors[layer] then return end
  print('hatch unlocked')
  m.hatch_sensors[layer]:setSensor(true)
  for i, triangle in ipairs(m.hatch_triangles[current_level]) do
    triangle.collider:setKinematic(false)
    triangle.collider:setMass(15000)
    triangle.collider:setAwake(true)
  end
end


function m.draw(pass, layer)
  if layer == 1 then
    local palette = palettes[8]
    local attr = vector(m.boxxer.fists.left:getPosition())
    endgame_emitter_1.movers[2].param.position = attr
    local t = lovr.timer.getTime()
    if t % 2 < lovr.timer.getDelta() then
      for i, element in ipairs(endgame_emitter_1.movers) do
        if element.name == 'color fade' then
          element.param.color = palette[1 + (i + math.floor(t/2)) % #palette]
        end
      end
      endgame_emitter_1.color = palette[1 + (math.floor(t/2)) % #palette]
      current_fog = palette[1 + (math.floor(t/4)) % #palette]
    end
  end
  local p1, p2, p3 = mat4(), mat4(), mat4()
  for i, barrel in ipairs(m.barrels) do
    p1:set(barrel.collider:getPose())
    p2:set(p1):translate(0, 0, -1.5)
    p3:set(p1):translate(0, 0,  1.5)
    pass:setColor(0.3, 0.3, 0.3)
    pass:cylinder(p2:scale(2.15, 2.15, 0.6), true, nil, nil, 9)
    pass:cylinder(p3:scale(2.15, 2.15, 0.6), true, nil, nil, 9)
    pass:setColor(barrel.color)
    pass:cylinder(p1:scale(2, 2, 5), true, nil, nil, 9)
  end
  for layer = 1, LAYER_COUNT do
    for i, lock_collider in ipairs(m.hatch_locks[layer]) do
      hatch_lock_mesh:draw(pass, mat4(lock_collider:getPose()))
    end
  end
  for i, list in ipairs(m.hatch_triangles) do
    for j, mesh in ipairs(list) do
      mesh:draw(pass, mat4(mesh.collider:getPose()))
    end
  end
  pass:setColor(0, 0, 1)
  for i, hatch_sensor_mesh in ipairs(m.hatch_sensor_meshes) do
    hatch_sensor_mesh:draw(pass)
  end
end


function m.changeLayer(prev, next)
  if next == 1 then
    addText('it is done!\nthe innermost core is breached!')
    addText('<incomming transmittion from beyond the 4th wall>')
    addText('WELL DONE! YOU\'VE WON THE GAME!')
    addText('THANK YOU FOR PLAYING\nTHE KLAXON THREAT XI - VENDETTA IN STRATOVERSE\nSEE YOU IN THE NEXT ONE                                                                                                        ')
    _G.addText = function() end
    endgame_emitter_1:stream()
    endgame_emitter_2:stream()
  end
  print('change layer', prev, '->', next)
  if prev then
    -- unload barrels & klaxons
    for i, barrel in ipairs(m.barrels) do
      if not barrel.collider:isDestroyed() then
        barrel.collider:destroy()
      end
    end
    for i, klaxon in ipairs(m.klaxons.list) do
      klaxon:destroy()
    end
    m.barrels = {}
    dispensers.list = {}

    if prev == LAYER_COUNT then addText('there appears to be another sphere inside of it?') end
  else
    addText('          ')
    addText('what a strange place this is')
    addText('i always wondered where those klaxon bastards come from')
    addText('right.. remember my training! what was it?')
    addText('    ')
    addText('my hand movements control the large robotic arms')
    addText('i can use GRIP to grab moving objects')
    addText('RIGHT STICK controls my rotation')
    addText('with the LEFT STICK i can navigate around')
    addText('move forward with my RIGHT TRIGGER')
    addText('and backward with my LEFT TRIGGER')
    addText('i can try it all out before going deeper')
    addText('especially grabbing objects with the GRIP       ')
    addText('                       ')
    addText('the scouts mentioned some huge hatches that would not open for them')
    addText('i might have to use the explosives                              ')
  end
  if next and next ~= 1 then
    local klaxons = require'klaxons'
    -- generate barrels & klaxons
    local count = 0
    for i, barrel_seed in ipairs(m.barrel_seeds[next]) do
      m.addBarrel(barrel_seed, next)
      count = count + 1
    end
    print('made', count, 'barrels')
    count = 0
    for i, pose in ipairs(m.dispenser_poses[next]) do
      count = count + 1
      dispensers.new(pose, next)
    end
    print('made', count, 'dispensers')


    m.klaxons.list = {}

    if next > 1 and prev then
      local KLAXON_COUNT = math.floor(next + next * lovr.math.random())
      print(KLAXON_COUNT, 'klaxons on level', next)
      for i = 1, KLAXON_COUNT do
        local klaxon = klaxons.spawn(randomPosInLayer(next, 15), next)
      end
    end

    current_fog = palettes[next][#palettes[next]]
    -- end game condition
  end
  current_level = next
end

return m
