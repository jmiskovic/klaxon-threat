local solids = require'solids'
local speck = require'speck'
local limb = require'limb'

local m = {}

local jet_trail = [==[{color={0.8003,0.7555,0.628},drawers={{name="spheres",param={radius=0.114,segments=8}}},emit_rate=328.5,lifetime=0.7564,lifetime_random=0.1,lightness_random=0.25,movers={{name="sizefade",param={strength=1,target=0.4441,tau=0.6625}},{name="noisy",param={frequency=1.734,strength=3.171,time_amp=0.1}},{name="colorfade",param={color={1,0.489,0.02891,1},strength=0.5005,tau=1e-05}},{name="colorfade",param={color={0.3333,0,0,1},strength=1.002,tau=1.109}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="cube",param={size=0.1}}},streaming=true,velocity={__type="vector",x=0,y=0.006359,z=1.893709},velocity_random=0.3068}]==]

local RADIUS = 2.3
local FORCE = 2e8
local TORQUE = 3e7

local HAND_RADIUS = 0.9
local HAND_FORCE = 2e8
local HAND_EXTENSION = 60

local castshape = lovr.physics.newSphereShape(HAND_RADIUS + 1)

local hand_names = {'left', 'right'}

local PROMPT_SPEED = 12 -- typing chars per second
local PROMPT_HOLD = 4.5 -- how long prompt is shown, chars per second
m.prompt_queue = {}
m.prompt = nil
m.prompt_hud = ''
m.prompt_time = 0
m.last_prompt = nil


function _G.addText(line)
  table.insert(m.prompt_queue, line)
end

local function typewriter(dt)
  if not m.prompt or m.prompt_time > #m.prompt / PROMPT_HOLD then
    m.prompt = table.remove(m.prompt_queue, 1)
  end
  if not m.prompt then
    m.prompt_hud = ''
    return
  end
  if (m.last_prompt ~= m.prompt) then
    m.prompt_time = 0
  end
  local trimmed = m.prompt:gsub('%s+$', '') -- poor man's timing control: use '   ' or 'pause   ' for delays
  m.prompt_hud = string.sub(trimmed, 1, m.prompt_time * PROMPT_SPEED)
  if #m.prompt_hud > 0 then m.prompt_hud = m.prompt_hud .. '_' end
  m.prompt_time = m.prompt_time + dt
  m.last_prompt = m.prompt
end

function m.generate(world)
  m.position = vector(0, 0, 170)
  m.orientation = quaternion(0, 0, 0, 0)
  m.emitter = speck.emitterFromString(jet_trail):stream()
  m.drawables = {}
  m.world = world
  local icosphere = solids.sphere(0):scale(RADIUS * 2)
  local cockpit = icosphere:triangleToLine()
  table.insert(m.drawables, cockpit)
  m.collider = world:newSphereCollider(m.position, RADIUS)
  m.collider:setTag('boxxer')
  m.collider:setLinearDamping(2.8)
  m.collider:setFriction(0)
  m.collider:setRestitution(0)
  m.collider:setAngularDamping(2.3)
  m.collider:setContinuous(true)
  m.fists = {}
  m.hand_joints = {}
  m.limbs = {}
  for i, handness in ipairs(hand_names) do
    local hand = world:newSphereCollider(m.position + vector(handness == 'left' and -3 or 3, 0, -10), HAND_RADIUS)
    hand:setTag('fist')
    hand:setDegreesOfFreedom('xyz', '')
    hand:setLinearDamping(50)
    hand:setContinuous(true)
    m.fists[handness] = hand
    m.limbs[handness] = limb.new({ 8, 7 }, m.collider, hand, vector(handness == 'left' and -2 or 2, -1, -0.3))
    m.limbs[handness].thickness = 0.3
  end
  return m
end


function m.update(dt)
  m.position = vector(m.collider:getPosition())
  m.orientation = quaternion(m.collider:getOrientation())
  local dir = m.orientation:direction()
  m.emitter:setPosition(m.position - dir * 2)
  m.emitter.initial_velocity = -2 * dir

  local thrust = (lovr.system.isKeyDown('u') and 1) or lovr.headset.getAxis('right', 'trigger')
  thrust = thrust - 0.3 * ((lovr.system.isKeyDown('y') and 1) or lovr.headset.getAxis('left', 'trigger'))
  m.collider:applyForce(dt * dir * thrust * FORCE)

  local dz = 0.05 -- deadzone
  -- pitch and yaw
  local tx, ty = lovr.headset.getAxis('right', 'thumbstick')
  tx = (lovr.system.isKeyDown('h') and 1) or (lovr.system.isKeyDown('f') and -1) or tx
  ty = (lovr.system.isKeyDown('t') and 1) or (lovr.system.isKeyDown('g') and -1) or ty
  -- yaw (left/right turn)
  if tx > dz then
   local v = quaternion(m.collider:getOrientation()) * vector(0, -1, 0)
   m.collider:applyTorque(v * dt * TORQUE * math.abs(tx - dz))
  end
  if tx < -dz then
   local v = quaternion(m.collider:getOrientation()) * vector(0, 1, 0)
   m.collider:applyTorque(v * dt * TORQUE * math.abs(tx - dz))
  end
  -- pitch (forward/backward tilt)
  if ty > dz then
   local v = quaternion(m.collider:getOrientation()) * vector(-1, 0, 0)
   m.collider:applyTorque(v * dt * TORQUE * math.abs(ty - dz))
  end
  if ty < -dz then
   local v = quaternion(m.collider:getOrientation()) * vector(1, 0, 0)
   m.collider:applyTorque(v * dt * TORQUE * math.abs(ty - dz))
  end
  -- strafe
  local tx, ty = lovr.headset.getAxis('left', 'thumbstick')
  tx = (lovr.system.isKeyDown('l') and 1) or (lovr.system.isKeyDown('j') and -1) or tx
  ty = (lovr.system.isKeyDown('i') and 1) or (lovr.system.isKeyDown('k') and -1) or ty
  if tx > dz then
   local v = quaternion(m.collider:getOrientation()) * vector(1, 0, 0)
   m.collider:applyForce(v * dt * FORCE * math.abs(tx - dz))
  end
  if tx < -dz then
   local v = quaternion(m.collider:getOrientation()) * vector(-1, 0, 0)
   m.collider:applyForce(v * dt * FORCE * math.abs(tx - dz))
  end
  if ty > dz then
   local v = quaternion(m.collider:getOrientation()) * vector(0, 1, 0)
   m.collider:applyForce(v * dt * FORCE * math.abs(ty - dz))
  end
  if ty < -dz then
   local v = quaternion(m.collider:getOrientation()) * vector(0, -1, 0)
   m.collider:applyForce(v * dt * FORCE * math.abs(ty - dz))
  end
  -- arm manipulation
  local boxxer_pose = mat4(m.position, m.orientation)
  local head_position = vector(lovr.headset.getPosition())
  for i, handness in ipairs(hand_names) do
    local position = vector(lovr.headset.getPosition(handness))
    local collider = m.fists[handness]
    local actual_arm = vector(collider:getPosition())
    local target_arm = boxxer_pose:mul((position - vector(0, -0.3, -0.3) - head_position) * vector(HAND_EXTENSION / 2, HAND_EXTENSION * 3 / 8, HAND_EXTENSION) + vector(0, 0, -10))
    target_arm = target_arm + m.collider:getLinearVelocity() * dt
    collider:applyForce((target_arm - actual_arm) * HAND_FORCE * dt)
    if (lovr.headset.isDown(handness, 'grip') or lovr.system.isKeyDown('lshift'))
      and not m.hand_joints[handness] then
      local grabbed_collider = m.world:overlapShape(castshape, actual_arm, quaternion(), 0, '~fist ~boxxer')
      if grabbed_collider and not grabbed_collider:isKinematic() then
        m.hand_joints[handness] = lovr.physics.newWeldJoint(collider, grabbed_collider)
      end
    end
    if (lovr.headset.wasReleased(handness, 'grip') or lovr.system.wasKeyReleased('lshift')) and m.hand_joints[handness] then
      m.hand_joints[handness]:destroy()
      m.hand_joints[handness] = nil
    end
  end
  typewriter(dt)
end


function m.draw(pass)
  for j, drawable in ipairs(m.drawables) do
    drawable:draw(pass, m.position, 1, m.orientation)
  end
  pass:setColor(0.4, 0.2, 0.2)
  for i, handness in ipairs(hand_names) do
    pass:sphere(vector(m.fists[handness]:getPosition()), HAND_RADIUS, 0, 0,1,0, 12)
    m.limbs[handness]:nudge(.1 * vector(handness == 'left' and -1 or 1, -.3, 0))
    m.limbs[handness]:update()
    m.limbs[handness]:draw(pass, 0x0a0405, 8)
  end
  pass:setColor(0xffccaa)
  pass:text(m.prompt_hud, mat4(m.position, m.orientation):translate(-.3, 0.3, -RADIUS * 0.8):scale(0.1))
end

return m
