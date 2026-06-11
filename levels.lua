local solids = require'solids'
local palettes = require'palettes'
local dots = require'dots'

local m = {}


local LAYER_COUNT = 7
local radii = {100, 300, 500, 700, 900, 1100, 1300, 1500, 1700, 1900, 2100, 2300, 2500, 2700}

for i = 1, #radii do radii[i] = 20 + 120 * i end

local COLUMN_RADIUS = 24
local SHELL_THICKNESS = 8

local castshape = lovr.physics.newSphereShape(1)

local shell_mesh = solids.sphere(1):scale(2)
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

function m.generate(world)
  local level = {}
  level.world = world
  level.radii = radii
  level.hatch_meshes = {}
  level.layer_meshes = {}
  for i = 1, LAYER_COUNT do
    local palette = palettes[i]
    local mesh = solids.new()
    level.layer_meshes[i] = mesh
    local outer_sphere = shell_mesh
        :clone()
        :transform(mat4():scale(radii[i]):rotate(2 * math.pi * i / LAYER_COUNT, 0,1,0))
        :flipWinding()
        :setColor(palette[1])
    local outer_collider = world:newMeshCollider(outer_sphere.vlist, outer_sphere.ilist)
    outer_collider:setTag('level')
    mesh:mergeIn(outer_sphere)

    if i > 1 then
      ---[[ INNER SPHERE
      local inner_sphere = shell_mesh
          :clone()
          :transform(mat4():scale(radii[i-1] + SHELL_THICKNESS):rotate(2 * math.pi * (i-1) / LAYER_COUNT, 0,1,0))
          :setColor(palettes[1][i])
      local inner_collider = world:newMeshCollider(inner_sphere.vlist, inner_sphere.ilist)
      --inner_collider:setSensor(true)
      mesh:mergeIn(inner_sphere)
      --]]

      ---[[ HATCH SENSOR
      local hatch = doorhatch
          :clone()
          :transform(mat4():scale(radii[i-1] + SHELL_THICKNESS):rotate(2 * math.pi * (i-1) / LAYER_COUNT, 0,1,0))
      hatch:updateNormals()
      local hatch_normal = vector(hatch.vlist[1][4], hatch.vlist[1][5], hatch.vlist[1][6])
      local hatch_sensor = world:newMeshCollider(hatch.vlist, hatch.ilist)
      hatch_sensor:setTag('hatch')
      hatch_sensor:setSensor(true)
      --]]
      ---[[ HATCH FRAME VISUALS
      local pA = vector(unpack(hatch.vlist[1])) - SHELL_THICKNESS/3 * hatch_normal
      local pB = vector(unpack(hatch.vlist[2])) - SHELL_THICKNESS/3 * hatch_normal
      local pC = vector(unpack(hatch.vlist[3])) - SHELL_THICKNESS/3 * hatch_normal
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
        pA = pA:lerp(center, 0.15); pB = pB:lerp(center, 0.15); pC = pC:lerp(center, 0.15)
        local points = {
          pA, pB, pC,
          pA - hatch_normal * SHELL_THICKNESS, pB - hatch_normal * SHELL_THICKNESS, pC - hatch_normal * SHELL_THICKNESS
        }
        local hatch_mesh, hatch_shape = solids.convexHull(points)
        local hatch_collider = world:newCollider(0, 0, 0)
        hatch_collider:addShape(hatch_shape)
        hatch_collider:setMass(5000)
        hatch_collider:setAwake(false)
        hatch_mesh = hatch_mesh:setColor(palette[4])
        hatch_mesh.collider = hatch_collider
        table.insert(level.hatch_meshes, hatch_mesh)
      end
      --]]
    end
  end

  level.column_meshes = {}
  for i = 2, LAYER_COUNT do
    local palette = palettes[i]
    local mesh = level.layer_meshes[i]
    ---[[ COLUMNS
    dots.onSphere(25):scale(radii[i] * 0.5 + radii[i - 1] * 0.5):map(
      function(pC)
        local colliderA, _, x, y, z = world:raycast(pC, vector(0))
        local pA = vector(x, y, z)
        local colliderB, _, x, y, z = world:raycast(pC, pC * 2.5)
        local pB = vector(x, y, z)
        pA = (pA:length() - SHELL_THICKNESS / 3) * pA:normalize()
        if colliderA and not world:overlapShape(castshape, pA, nil, COLUMN_RADIUS * 2, 'hatch') and
           colliderB and not world:overlapShape(castshape, pB, nil, COLUMN_RADIUS * 2, 'hatch') then
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
    --]]
  end

  for i = 1, 300 do
    local barrel = world:newCylinderCollider(
      (math.random() - 0.5) * 200, (math.random() - 0.5) * 200, (math.random() - 0.5) * 200,
      2, 5)
    barrel:setMass(barrel:getMass() / 4)
  end
  return level
end


return m
