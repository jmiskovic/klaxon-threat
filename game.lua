local dispensers = require'dispensers'
local palettes = require'palettes'
local levels = require'levels'
local boxxer = require'boxxer'
local klaxons = require'klaxons'
local speck = require'speck'
local light = require'point_light'

function _G.determineLevel()
  local r = vector(boxxer.collider:getPosition()):length()
  for i = 1, #levels.radii do
    if r < levels.radii[i]  then
      return i
    end
  end
  return #levels.radii
end


local world = lovr.physics.newWorld{tags={'boxxer', 'level', 'hatch', 'hatch_sensor', 'hatch_broadcast', 'hatch_lock', 'klaxon', 'fist', 'head', 'barrel', 'dispenser'}}
world:disableCollisionBetween('boxxer', 'fist')
world:disableCollisionBetween('fist', 'hatch_sensor') -- lol
world:disableCollisionBetween('barrel', 'hatch_broadcast')
world:setGravity(0, 0, 0)

klaxons.world = world
dispensers.world = world

levels.generate(world, klaxons, boxxer)
levels.changeLayer(nil, #levels.radii)

boxxer.position = levels.initial_boxxer_position
boxxer.orientation = levels.initial_boxxer_orientation
boxxer.generate(world)

local thump_source = lovr.audio.newSource('thump.ogg', {spatial=true, pitchable=true })
thump_source:setSpatialization(1); thump_source:setAbsorption(true); thump_source:setFalloff(15, .1)

local explode_source = lovr.audio.newSource('xplode.ogg', {spatial=true, pitchable=true })
explode_source:setSpatialization(1); explode_source:setAbsorption(true); explode_source:setFalloff(15, .1)

local BARREL_EXPLODE_VELOCITY = 25


local to_explode = {}

world:setCallbacks{
  enter = function(a, b, contact)
    local snd = thump_source:clone()
    snd:setPitch(1 + lovr.math.randomNormal(0.1, 0))
    local impact_velocity = vector(a:getLinearVelocity()):distance(vector(b:getLinearVelocity()))
    snd:setPosition(contact:getPoints())
    snd:setVolume(impact_velocity * 1e-2)
    snd:play()
    local atag = a:getTag(); local btag = b:getTag()
    if atag == 'boxxer' or btag == 'boxxer' then
      local other = atag == 'boxxer' and b or a
      local otag = other:getTag()
      if otag == 'hatch_broadcast' then
        local locked = #levels.hatch_locks[current_level] > 1
        addText(locked and 'hatch seems locked by those diamond contraptions' or
                'hatch is unlocked and i can go beyond it')
      end
    elseif atag == 'fist' or btag == 'fist' then
      local other = atag == 'fist' and b or a
    end
    if atag == 'barrel' or btag == 'barrel' then
      local other = atag == 'barrel' and b or a
      local otag = other:getTag()
      if impact_velocity > BARREL_EXPLODE_VELOCITY and otag ~= 'fist' then
        table.insert(to_explode, atag == 'barrel' and a or b)
      end
    end
  end,
--[[
local to_change_level = nil

  exit = function(a, b)
    local atag = a:getTag(); local btag = b:getTag()
    if atag == 'boxxer' or btag == 'boxxer' then
      local other = atag == 'boxxer' and b or a
      local otag = other:getTag()
      if otag == 'hatch_sensor' and current_level then
        print('exit hatch_sensor')
        local level = determineLevel()
        if level ~= current_level - 1 then print('level mismatch, expected', current_level - 1, 'got', level) end
        if level < current_level then
          to_change_level = level
          other:setSensor(false) -- solidifying the gate behind
        end
      end
    end
  end,
  if to_change_level then
    levels.changeLayer(current_level, to_change_level)
    current_level = to_change_level
    to_change_level = nil
  end
--]]
}

local level_filter = nil

function lovr.update(dt)
  for i, explode in ipairs(to_explode) do
    local snd = explode_source:clone()
    snd:setPitch(1 + lovr.math.randomNormal(0.1, 0))
    snd:setPosition(explode:getPosition())
    snd:play()
    levels.explodeBarrel(explode)
  end
  to_explode = {}
  boxxer.update(dt)
  world:update(1/60)
  lovr.audio.setPose(boxxer.collider:getPose())
  klaxons.update(dt)
  speck.update(dt)
  light.gpu.position = vector(boxxer.fists.left:getPosition()):lerp(
    vector(boxxer.fists.right:getPosition()), 0.5)
end


local function setPerspective(pass, boxxer_pose)
  for view = 1, pass:getViewCount() do
    local headset_pose = mat4(pass:getViewPose(view))
    pass:setViewPose(view, boxxer_pose * headset_pose)
  end
end


light.load(512)
light.gpu.light_color = vector(1, 0.95, 0.7)
light.gpu.shadow_color = vector(0.4, 0.3, 0.4)
light.gpu.falloff_exp = -4
_G.current_fog = vec3(0.8, 0.8, 0.8)
local shader = lovr.graphics.newShader('uber.vert', 'uber.frag')
local texture = lovr.graphics.newTexture('surface.jpg')

local sphshape = lovr.physics.newSphereShape(0.2)

function lovr.draw(wpass)
  local pass
  pass = light.getPass()
  for i, mesh in ipairs(levels.layer_meshes) do
    if (not level_filter) or level_filter == i then
      mesh:draw(pass)
    end
  end
  levels.draw(pass, current_level)

  boxxer.draw(pass)
  klaxons.draw(pass)
  dispensers.draw(pass)

  lovr.graphics.submit(pass)
  pass = wpass

  pass:setFont(font)
  --pass:text(lovr.timer.getFPS(), 0.2, 1.5, -0.5, 0.05)
  setPerspective(pass, mat4(boxxer.position, boxxer.orientation))

  pass:setFaceCull('back')
  pass:setSampler('nearest')
  pass:setShader(shader)
  pass:send('surface_texture', texture)
  pass:send('fog_color', current_fog)

  light.send(pass)

--[[
  if lovr.system.isKeyDown('tab') then
    require'phywire'.xray(pass, world)
    return
  end
--]]

  pass:setColor(1,1,1)
  for i, mesh in ipairs(levels.layer_meshes) do
    if (not level_filter) or level_filter == i then
      mesh:draw(pass)
    end
  end
  levels.draw(pass, 2)

  boxxer.draw(pass)
  klaxons.draw(pass)
  dispensers.draw(pass)

  pass:setShader()
  speck.draw(pass)

  -- require'phywire'.draw(pass, world)

  --[[
  pass:setColor(0, 1, 0)
  local layer_count = 5
  local radii = {50, 120, 250, 350, 500}
  for i = 2, 2 do
    local dots = require'dots'
    dots.onSphere(130 + i):scale(radii[i]):map(
      function(pA)
        pass:setColor(0,1,1)
        pass:sphere(pA * 0.9, 3)
        pass:line(pA * 0.9, vector(0))
        local collider, shape, x, y, z, nx, ny, nz, triangle, fraction = world:raycast(pA * 0.9, vector(0))
        local pB = vector(x, y, z)
        if collider and collider:getTag() ~= 'hatch' then
          pass:setColor(0,0,1)
          pass:sphere(pB, 5)
        end
      end
    )
  end
  --]]

end


function lovr.resize(width, height)
end


function lovr.keypressed(key)
  if key == 'space' then
    local dir = boxxer.orientation:direction()
    local pos = boxxer.position + dir * 10
    local barrel = levels.addBarrel(pos, current_level)
    barrel:setLinearVelocity(dir * 100)
  end
end

function lovr._wheelmoved(_, dy)
  local dir = dy > 0 and 1 or -1
  level_filter = level_filter or 0
  level_filter = 1 + (level_filter - 1 + dir) % #levels.layer_meshes
  print('level filter', level_filter)
end

function lovr.mousepressed(x, y, button)
  if button == 1 then
    table.remove(levels.hatch_locks[current_level], 1)
  end
  if button == 3 then
    level_filter = nil
  end
end

--require'phygrab'.integrate(world)