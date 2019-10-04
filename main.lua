require 'strict'
local Object = require "classic"
local Animation = require "animation"
local util = require "util"
local ui = require "ui"
local playback = require "playback"

-- global state
local state = {}
state.duration = 0
state.zoom = 1 -- TODO

-- root ui object, initialized in love.load
local window

local history = {}
history._undo = {}
history._redo = {}

function history.push()
  table.insert(history._undo, state.animation:copy())
end

function history.undo()
  if #history._undo > 0 then
    table.insert(history._redo, state.animation:copy())
    history.set(table.remove(history._undo))
  end
end

function history.redo()
  if #history._redo > 0 then
    table.insert(history._undo, state.animation:copy())
    history.set(table.remove(history._redo))
  end
end

function history.set(animation)
  state.animation = animation
  state.player = playback.Animation(state.animation.state, state.animation.images)
  state.frame = state.animation.frames[1]
  state.layer = state.animation.layers[1]
end

-- ui event handlers
local eventhandler = {}

local function dispatch(eventName, ...)
  util.pprint(eventName, ...)
  assert(eventhandler[eventName], "Missing UI event handler: " .. eventName)
  eventhandler[eventName](...)
end

function eventhandler.NEW_PROJECT()
  state.animation = Animation()
  state.frame = state.animation.frames[1]
  state.layer = nil
  state.player = playback.Animation(state.animation.state, state.animation.images)
end

function eventhandler.UNDO()
  history.undo()
end

function eventhandler.REDO()
  history.redo()
end

function eventhandler.MOVE_LAYER(layer, e)
  -- TODO: push to history when movement starts
  layer = state.animation.framelayers[state.frame.id][layer.id]
  layer.x = layer.x + e.dx
  layer.y = layer.y + e.dy
end

function eventhandler.SELECT_LAYER(id)
  state.layer = util.find(state.animation.layers, function(layer) return layer.id == id end)
  assert(state.layer)
end

function eventhandler.SELECT_NEXT_LAYER(prev)
  if state.layer then
    local i = util.indexOf(state.animation.layers, state.layer)
    if prev then
      state.layer = state.animation.layers[i - 1] or state.animation.layers[#state.animation.layers]
    else
      state.layer = state.animation.layers[i + 1] or state.animation.layers[1]
    end
  end
end

function eventhandler.CHANGE_LAYER_PRIORITY(diff)
  if #state.animation.layers > 1 then
    history.push()
    state.animation:swap('layers', state.layer, diff)
  end
end

function eventhandler.ROTATE_LAYER(r)
  -- TODO: push to history when rotation starts
  local layer = state.animation.framelayers[state.frame.id][state.layer.id]
  local mouseStartAngle = math.atan2(r.start.y - r.center.y - layer.y, r.start.x - r.center.x - layer.x)
  local mouseCurrentAngle = math.atan2(r.now.y - r.center.y - layer.y, r.now.x - r.center.x - layer.x)
  layer.angle = r.start.angle + (mouseCurrentAngle - mouseStartAngle)
end

function eventhandler.DELETE_LAYER()
  if state.layer then
    history.push()
    state.layer = state.animation:deleteLayer(state.layer)
  end
end

function eventhandler.SAVE()
  state.animation:save()
end

function eventhandler.NEW_FRAME()
  history.push()
  state.frame = state.animation:newFrame(state.frame)
end

function eventhandler.DELETE_FRAME()
  history.push()
  state.frame = state.animation:tryDeleteFrame(state.frame)
end

function eventhandler.SELECT_FRAME(id)
  state.frame = util.find(state.animation.frames, function(frame) return frame.id == id end)
  assert(state.frame)
end

function eventhandler.MOVE_FRAME(diff)
  history.push()
  state.animation:swap('frames', state.frame, diff)
end

function eventhandler.SELECT_EASING(name)
  history.push()
  state.frame.easing = name
end

function eventhandler.BROADCAST(data)
  window:broadcast(data.event, data.payload)
end

function love.load(arg)
  local w, h = love.graphics.getDimensions()
  love.window.setMode(w, h, {resizable = true, minwidth = 800, minheight = 600})
  love.window.setDisplaySleepEnabled(true)
  love.window.setTitle("Animation Love")

  window = ui.Window()
  window.context = {
    state = state,
    window = {width = w, height = h},
    dispatch = dispatch,
  }

  dispatch('NEW_PROJECT')

  for _, filename in ipairs(arg) do
    state.layer = state.animation:newLayer(io.open(filename, 'rb'):read('*a'), filename)
  end
end

function love.draw()
  window:render()
end

function love.update(dt)
  window:broadcast('tick', dt)
  state.duration = state.duration + dt
end

function love.filedropped(file)
  history.push()
  state.layer = state.animation:newLayer(file:read(), file:getFilename())
end

local mountpoints = {}
function love.directorydropped(dir)
  -- love2d bug? we can't mount a directory for a second time after previously mounting and unmounting
  -- so we'll mount it for the first time only and never unmount
  if not mountpoints[dir] then
    mountpoints[dir] = "mount-" .. love.math.random(2^64)
    love.filesystem.mount(dir, mountpoints[dir])
  end

  local err, animation = Animation.load(mountpoints[dir])
  if err then
    state.error = err
  else
    state.animation = animation
    state.frame = animation.frames[1]
    state.layer = animation.layers[1]
  end
end

function love.mousepressed(x, y, button)
  window:processMouseEvent('mousepressed', {x = x, y = y, button = button})
end

function love.mousereleased(x, y, button)
  window:processMouseEvent('mousereleased', {x = x, y = y, button = button})
end

function love.mousemoved(x, y, dx, dy, istouch)
  window:processMouseEvent('mousemoved', {x = x, y = y, dx = dx, dy = dy})
end

function love.keypressed(key, keycode, isrepeat)
  window:processEvent('keypressed', {key = key, kekycode = keycode, isrepeat = isrepeat})

  -- keyboard shortcuts
  if state.layer and key == 'left' then
    dispatch('MOVE_LAYER', state.layer, {dx = -1, dy = 0})
  elseif state.layer and key == 'right' then
    dispatch('MOVE_LAYER', state.layer, {dx = 1, dy = 0})
  elseif state.layer and key == 'up' then
    dispatch('MOVE_LAYER', state.layer, {dx = 0, dy = -1})
  elseif state.layer and key == 'down' then
    dispatch('MOVE_LAYER', state.layer, {dx = 0, dy = 1})
  elseif key == 'tab' then
    dispatch('SELECT_NEXT_LAYER', love.keyboard.isDown('lshift', 'rshift'))
  elseif key == 'z' and love.keyboard.isDown('lctrl') then
    dispatch('UNDO')
  elseif key == 'y' and love.keyboard.isDown('lctrl') then
    dispatch('REDO')
  end
end

function love.resize(w, h)
  window.context.window = {width = w, height = h}
end
