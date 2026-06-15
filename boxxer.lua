local solids = require'solids'
local speck = require'speck'
local fabrik = require'fabrik'

local m = {}

local jet_trail = [==[{color={0.8,0.75,0.62},drawers={{name="spheres",param={radius=0.114,segments=8}}},emit_rate=30.5,lifetime=2,lifetime_random=0.1,lightness_random=0.25,movers={{name="sizefade",param={strength=1,target=0.4441,tau=0.6625}},{name="noisy",param={frequency=1.734,strength=3.171,time_amp=0.1}},{name="colorfade",param={color={1,0.489,0.02891,1},strength=0.5005,tau=1e-05}},{name="colorfade",param={color={0.3333,0,0,1},strength=1.002,tau=1.109}}},position={__type="vector",x=0,y=0,z=0},spawners={{name="cube",param={size=0.1}}},streaming=true,velocity={__type="vector",x=0,y=0.006359,z=1.893709},velocity_random=0.3068}]==]

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

local function rep(val, n) local t = {}; for i=1,n do t[i]=val end; return t end

local function makeCockpit(self, threshold)
  local icosphere = solids.sphere(1):scale(RADIUS * 2)
  local cockpit = solids.new()
  local s = 0.15
  for i = 1, #icosphere.ilist, 3 do
    local a = vector(unpack(icosphere.vlist[icosphere.ilist[i]]))
    local b = vector(unpack(icosphere.vlist[icosphere.ilist[i + 1]]))
    local c = vector(unpack(icosphere.vlist[icosphere.ilist[i + 2]]))
    local m = b; local n = c
    local pos = (m + n)*0.5
    local thickness = pos.z < 0 and 0.08 or 0.3
    local scale = vector(thickness, thickness, m:distance(n) * 0.76)
    local orient = quaternion.lookdir(m - n)
    cockpit:mergeIn(solids.cube():transform(mat4(pos, scale, orient)):setColor(s, s, s))
  end
  cockpit:mergeIn(solids.cylinder(10):transform(mat4(0, -RADIUS * 0.8, 0):scale(RADIUS * 0.9, 0.05, RADIUS * 0.9)):setColor(s, s, s))
  return cockpit
end

function m.generate(world)
  m.position = vector(120, -80, 140) * 0
  m.orientation = quaternion(0, 0, 0, 0)
  m.emitter = speck.emitterFromString(jet_trail):stream()
  m.world = world
  m.cockpit = makeCockpit()
  m.collider = world:newSphereCollider(m.position, RADIUS)
  m.collider:setTag('boxxer')
  m.collider:setLinearDamping(2.8)
  m.collider:setFriction(0)
  m.collider:setRestitution(0)
  m.collider:setAngularDamping(2.3)
  m.collider:setContinuous(true)
  m.fists = {}
  m.hand_joints = {}
  m.cables_upper = {}
  m.cables_lower = {}
  for i, handness in ipairs(hand_names) do
    local hand = world:newSphereCollider(m.position + vector(handness == 'left' and -3 or 3, 0, -10), HAND_RADIUS)
    hand:setTag('fist')
    hand:setDegreesOfFreedom('xyz', '')
    hand:setLinearDamping(30)
    hand:setContinuous(true)
    m.fists[handness] = hand
    m.cables_upper[handness] = fabrik.new(rep(0.05, 7), m.position)
    m.cables_lower[handness] = fabrik.new(rep(0.1, 9), m.position)
  end
  return m
end


function m.update(dt)
  local dir = m.orientation:direction()
  m.emitter:setPosition(m.position - dir * 2)
  m.emitter.initial_velocity = -2 * dir

  local thrust = (lovr.system.isKeyDown('u') and 1) or lovr.headset.getAxis('right', 'trigger')
  thrust = thrust - 0.3 * ((lovr.system.isKeyDown('y') and 1) or lovr.headset.getAxis('left', 'trigger'))
  m.collider:applyForce(dt * dir * thrust * FORCE)

  local dz = 0.05 -- deadzone
  -- pitch and yaw
  local tx, ty = lovr.headset.getAxis('right', 'thumbstick')
  tx = (lovr.system.isKeyDown('l') and 1) or (lovr.system.isKeyDown('j') and -1) or tx
  ty = (lovr.system.isKeyDown('i') and 1) or (lovr.system.isKeyDown('k') and -1) or ty
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
  tx = (lovr.system.isKeyDown('h') and 1) or (lovr.system.isKeyDown('f') and -1) or tx
  ty = (lovr.system.isKeyDown('t') and 1) or (lovr.system.isKeyDown('g') and -1) or ty
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
    if handness == 'right' and not lovr.headset.getName() then
      position = vector(0.3, 1.2, -0.3)
    end
    local collider = m.fists[handness]
    local actual_arm = vector(collider:getPosition())
    local target_arm = boxxer_pose:mul((position - vector(0, -0.3, -0.2) - head_position) * vector(HAND_EXTENSION / 2, HAND_EXTENSION * 3 / 8, HAND_EXTENSION) + vector(0, 0, -10))
    target_arm = target_arm + m.collider:getLinearVelocity() * dt
    collider:applyForce((target_arm - actual_arm) * HAND_FORCE * dt)
    collider:setSensor(target_arm:distance(actual_arm) > 15) -- get out of jail
    if (lovr.headset.isDown(handness, 'grip') or lovr.system.isKeyDown('lshift'))
      and not m.hand_joints[handness] then
      local grabbed_collider = m.world:overlapShape(castshape, actual_arm, nil, 0, '~fist ~boxxer')
      if grabbed_collider and not grabbed_collider:isKinematic() then
        m.hand_joints[handness] = lovr.physics.newWeldJoint(collider, grabbed_collider)
      end
    end
    if (lovr.headset.wasReleased(handness, 'grip') or lovr.system.wasKeyReleased('lshift')) and m.hand_joints[handness] then
      m.hand_joints[handness]:destroy()
      m.hand_joints[handness] = nil
    end
    m.cables_upper[handness]:nudge(vector.down * 5 * dt)
    m.cables_lower[handness]:nudge(vector.down * 5 * dt)
  end
  typewriter(dt)
end


local beam_offsets = {}
for i = 1, 4 do
  beam_offsets[i] = vector(
    lovr.math.randomNormal(0.15, 0),
    lovr.math.randomNormal(0.15, 0),
    lovr.math.randomNormal(0.15, 0))
end


function m.draw(pass)
  m.position = vector(m.collider:getPosition())
  m.orientation = quaternion(m.collider:getOrientation())
  m.cockpit:draw(pass, m.position, 1, m.orientation)
  for i, handness in ipairs(hand_names) do
    local outward = handness == 'left' and -1 or 1
    local fist_pos = vector(m.fists[handness]:getPosition())
    local shoulder_pos = m.position + m.orientation * vector(outward * 2, -1, -0.3)
    local elbow_pos = shoulder_pos:lerp(fist_pos, 0.2) + m.orientation * vector(outward * 4, -1, 0)
    local hand_pos = vector(m.collider:getWorldPoint(lovr.headset.getPosition(handness)))

    pass:setColor(0.4, 0.2, 0.2)
    pass:sphere(hand_pos, 0.06, nil, 6)
    pass:sphere(fist_pos, HAND_RADIUS, 0, 0,1,0, 12)
    pass:setColor(0.05, 0, 0)
    local thickness = 0.15
    for i, beam_offset in ipairs(beam_offsets) do
      pass:capsule(shoulder_pos + beam_offset, elbow_pos, thickness, 7)
      thickness = 0.08
    end
    local thickness = 0.1
    for i = #beam_offsets, 1, -1 do
      local beam_offset = beam_offsets[i]
      pass:capsule(elbow_pos + beam_offset, fist_pos, thickness, 7)
      thickness = 0.07
    end
    pass:capsule(shoulder_pos, hand_pos, 0.04, 8)
    pass:setColor(0.08, 0.08, 0.08)
    m.cables_upper[handness]:update(shoulder_pos, elbow_pos, 0.3)
    m.cables_lower[handness]:update(elbow_pos, fist_pos,     0.3)
    m.cables_upper[handness]:drawCapsules(pass, 0.05, 7)
    m.cables_lower[handness]:drawCapsules(pass, 0.05, 7)
  end
  pass:setColor(0xffccaa)
  pass:text(m.prompt_hud, mat4(m.position, m.orientation):translate(-.3, 0.3, -RADIUS * 0.8):scale(0.1))
end

return m
