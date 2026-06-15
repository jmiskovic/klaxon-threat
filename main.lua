--[[
local chui = require'chui'
local speck = require'speck'

local stream = [==[{color={0.07581,0.5685,0.4397},drawers={{name="lines",param={length=18.37,segments=7,thickness=0.007929}}},emit_rate=110.1,lifetime=2.342,lifetime_random=0.1,lightness_random=0.25,movers={{name="noisy",param={frequency=1.806,strength=5.318,time_amp=0.3723}},{name="orthogonal",param={strength=8.904}}},position={__type="vector",x=0,y=3.113,z=-6.985},spawners={{name="cube",param={size=6.15}}},streaming=true,velocity={__type="vector",x=0,y=0,z=1.326},velocity_random=1e-05}]==]
local emitter = speck.emitterFromString(stream):stream()



_G.font = lovr.graphics.newFont('PromptFont.otf', 36)
chui.setFont(font)

local function start_game()
  emitter:stop()
  emitter:remove()
  local game = require'game'
end

local panel = chui.panel{ pose = mat4(0, 1.5, -2):scale(0.2), palette = chui.palettes[6] }
panel:label{ text= 'THE KLAXON THREAT XI', span = {1, 0.1}  }
panel:row()
panel:label{ text= '· VENDETTA IN STRATOVERSE ·', text_scale = 0.7, span = {1, 0} }
panel:row()
panel:row()
panel:row()
panel:button{ thickness=0.2, span={3, 0.8}, text='ENTER THE\nSTRATOVERSE', callback=start_game }
panel:row()
panel:button{ thickness=0.1, span={3, 0.6}, text='EXIT', callback=function() lovr.event.quit() end }
panel:layout()

function lovr.draw(pass)
  local dt = lovr.timer.getDelta()
  emitter:update(dt)
  panel:update(dt)
  emitter:draw(pass)
  panel:draw(pass)
  pass:setColor(0.1, 0.2, 0.2)
  pass:cylinder(0, -0.1, 0,  3, .2,  math.pi/2, 1,0,0)
end
--]]
local game = require'game'
