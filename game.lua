local levels = require'levels'
local boxxer = require'boxxer'
local klaxons = require'klaxons'
local speck = require'speck'

local font = lovr.graphics.newFont('PromptFont.otf', 36)


local world = lovr.physics.newWorld{tags={'boxxer', 'level', 'hatch', 'klaxon', 'fist', 'head'}}
world:disableCollisionBetween('boxxer', 'fist')
world:setGravity(0, 0, 0)
local level = levels.generate(world)
local boxxer = boxxer.generate(world)

klaxons.world = world
klaxons.boxxer = boxxer
klaxons.level = level

local thump_source = lovr.audio.newSource('thump.ogg', {spatial=true, pitchable=true })
thump_source:setSpatialization(1); thump_source:setAbsorption(true); thump_source:setFalloff(true)

function _G.determineLevel()
  local r = vector(boxxer.collider:getPosition()):length()
  for i = 1, #level.radii do
    if r < level.radii[i]  then
      return i
    end
  end
  return #level.radii
end

local hatch_enter_level = nil

world:setCallbacks{
  enter = function(a, b, contact)
    local snd = thump_source:clone()
    snd:setPosition(contact:getPoints())
    snd:setVolume(contact:getOverlap() * 1e2)
    snd:play()
    local atag = a:getTag(); local btag = b:getTag()
    if atag == 'boxxer' or btag == 'boxxer' then
      local other = atag == 'boxxer' and b or a
      local otag = other:getTag()
      print('boxxer collision')
      if otag == 'hatch' then
        hatch_enter_level = determineLevel()
      end
    elseif atag == 'fist' or btag == 'fist' then
      local other = atag == 'fist' and b or a
      print('fist collision')
    end
  end,
  exit = function(a, b)
    local atag = a:getTag(); local btag = b:getTag()
    if atag == 'boxxer' or btag == 'boxxer' then
      local other = atag == 'boxxer' and b or a
      local otag = other:getTag()
      if otag == 'hatch' and hatch_enter_level then
        local level = determineLevel()
        if level < hatch_enter_level then
          other:setSensor(false)
          print('solidifying the gate behind')
        end
      end
    end
  end
}


for i = 1, 0 do
  local klaxon = klaxons.spawn()
end


local level_filter = nil

function lovr.update(dt)
  boxxer.update(dt)
  world:update(1/60)
  lovr.audio.setPose(boxxer.collider:getPose())
  klaxons.update(dt)
  speck.update(dt)
end


local function setPerspective(pass, boxxer_pose)
  for view = 1, pass:getViewCount() do
    local headset_pose = mat4(pass:getViewPose(view))
    pass:setViewPose(view, boxxer_pose * headset_pose)
  end
end



local shader = lovr.graphics.newShader('uber.vert', 'uber.frag')
local texture = lovr.graphics.newTexture('surface.jpg')

local sphshape = lovr.physics.newSphereShape(0.2)

function lovr.draw(pass)
  pass:setFont(font)
  --pass:text(lovr.timer.getFPS(), 0.2, 1.5, -0.5, 0.05)
  setPerspective(pass, mat4(boxxer.position, boxxer.orientation))

  pass:setFaceCull('back')
  pass:setSampler('nearest')
  pass:setShader(shader)
  pass:send('surface_texture', texture)

  if lovr.system.isKeyDown('tab') then
    require'phywire'.xray(pass, world)
    return
  end

  pass:setColor(1,1,1)
  for i, mesh in ipairs(level.layer_meshes) do
    if (not level_filter) or level_filter == i then
      mesh:draw(pass)
    end
  end
  for i, mesh in ipairs(level.hatch_meshes) do
    mesh:draw(pass, mat4(mesh.collider:getPose()))
  end

  boxxer.draw(pass)
  klaxons.draw(pass)
  speck.draw(pass)

  --require'phywire'.draw(pass, world)

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
end

function lovr._wheelmoved(_, dy)
  local dir = dy > 0 and 1 or -1
  level_filter = level_filter or 0
  level_filter = 1 + (level_filter - 1 + dir) % #level.layer_meshes
  print('level filter', level_filter)
end

function lovr.mousepressed(x, y, button)
  if button == 3 then
    level_filter = nil
  end
end

--require'phygrab'.integrate(world)