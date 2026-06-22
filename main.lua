_G.font = lovr.graphics.newFont('PromptFont.otf', 36)

local music = lovr.audio.newSource('intro.ogg')
music:setLooping(true)
music:play()
music:setVolume(0)
local ambient = lovr.audio.newSource('ambient.ogg')
ambient:setLooping(true)
ambient:setVolume(0.1)

local skip_menu = true

if not skip_menu then
  local speck = require'speck'

  local stream = [==[{color={0.07581,0.5685,0.4397},drawers={{name="lines",param={length=18.37,segments=7,thickness=0.007929}}},emit_rate=200,lifetime=2.342,lifetime_random=0.1,lightness_random=0.25,movers={{name="noisy",param={frequency=1.806,strength=5.318,time_amp=0.3723}},{name="orthogonal",param={strength=8.904}}},position={__type="vector",x=0,y=3.113,z=-6.985},spawners={{name="cube",param={size=6.15}}},streaming=true,velocity={__type="vector",x=0,y=0,z=1.326},velocity_random=1e-05}]==]
  local emitter = speck.emitterFromString(stream):stream()

  local function start_game()
    emitter:stop()
    emitter:remove()
    music:stop()
    ambient:play()
    require'game'
  end

  function lovr.draw(pass)
    pass:setFont(font)
    local t = lovr.timer.getTime()
    pass:setColor(0.9, 0.7, 0.3)
    pass:text('THE KLAXON THREAT XI', 0, 2.5, -8, 1.5)
    pass:setColor(0.9, 0.8, 0.3)
    pass:text('· VENDETTA IN STRATOVERSE ·', 0, 1.4, -6, 0.5)
    pass:setColor(0.5, 0.5, 0.4)
    pass:text('press trigger to\nenter the stratoverse', 0, 0.6, -4, 0.2 + 0.05 * math.sin(t * 0.2))
    music:setVolume((t - 0.5) * 0.02)
    local dt = lovr.timer.getDelta()
    emitter:update(dt)
    emitter:draw(pass)
    pass:setColor(0.1, 0.2, 0.2)
    pass:cylinder(0, -0.1, 0,  3, .2,  math.pi/2, 1,0,0)

    if lovr.headset.wasPressed('left', 'trigger') or  lovr.headset.wasPressed('right', 'trigger') then
      start_game()
    end
  end
else
  require'game'
end
