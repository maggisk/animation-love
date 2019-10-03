local Object = require "classic"
local Animation = require "animation"
local util = require "util"
local ui = require "ui"

-- layout config
local layout = {}
layout.sidebar = {width = 200}
layout.header = {height = 100}
layout.footer = {height = 100}
layout.window = {width = 1024, height = 720}

-- color config
local colors = {
  background = {54.8/255, 60.8/255, 72.5/255, 1},
  button = {
    font = {1, 1, 1, 1},
    background = {0, 0, 0, 0},
    selected = {background = {78.6/255, 146.2/255, 228.8/255, 1}},
    hover = {background = {73.6/255, 85.8/255, 100.6/255, 1}},
  },
}

-- global state
local state = {}
state.zoom = 1 -- not used yet
state.playing = false
state.duration = 0
state.timePerFrame = 0.3
state.showEasingPicker = false
state.rotation = {}
state.ui = ui.Area()
state.animation = Animation()
state.frame = state.animation.frames[1]
state.layer = false

-- keyboard and mouse event handlers 
local function adjustLayerPosition(x, y)
  if state.frame and state.layer then
    local frameLayer = state.animation.framelayers[state.frame.id][state.layer.id]
    frameLayer.x = frameLayer.x + x
    frameLayer.y = frameLayer.y + y
  end
end

local function newFrame()
  state.frame = state.animation:newFrame(state.frame)
end

local function setTab(tab)
  state.tab = tab
end

local function newButton(parent, options)
  return ui.Button(parent, util.extend({theme = colors.button}, options))
end

local function changeLayerPriority(direction)
  state.animation:swap('layers', state.layer, direction)
end

local function setEasingFunc(button)
  state.frame.easing = button.easing
end

local function startRotation(x, y)
  state.rotation.active = true
  state.rotation.x = x
  state.rotation.y = y
  state.rotation.angle = state.animation.framelayers[state.frame.id][state.layer.id].angle
end

local function rotate(x, y, centerX, centerY)
  local fl = state.animation.framelayers[state.frame.id][state.layer.id]
  local start = math.atan2(state.rotation.y - centerY - fl.y, state.rotation.x - centerX - fl.x)
  local now = math.atan2(y - centerY - fl.y, x - centerX - fl.x)
  fl.angle = state.rotation.angle + (now - start)
end

local Element = Object:extend()
function Element:new(attr, ...)
  self.attr = attr or {}
  self.children = {...}
  self.events = {}
end

function Element:bind(method)
  return function(...)
    return method(self, ...)
  end
end

function Element:add(...)
  for _, child in ipairs({...}) do
    table.insert(self.children, child)
  end
end

function Element:dispatcher(name, payload)
  return function(element)
    local root = self
    while root.parent do root = root.parent end
    root.attr.dispatch(name, payload)
  end
end

function Element:iter()
  local r, h, t, q = nil, 1, 1, {self}
  return function()
    if h > t then return end
    for _, child in ipairs(q[h].children) do
      t = t + 1
      q[t] = child
    end
    r, q[h] = q[h], nil
    h = h + 1
    return r
  end
end

local function matches(node, attr)
  for k, v in pairs(attr) do
    if node.attr[k] ~= v then return false end
  end
  return true
end

function Element:query(attr)
  local r = {}
  for node in self:iter() do
    if matches(node, attr) then
      r[#r+1] = node
    end
  end
  return r
end

function Element:on(name, fn)
  assert(name and fn)
  self.events[name] = self.events[name] or {}
  table.insert(self.events[name], fn)
  return self
end

function Element:trigger(name, e)
  for _, fn in ipairs(self.events[name] or {}) do
    fn(e)
  end
end

function Element:handleEvent(name, e)
  for _, child in ipairs(self.children) do
    if child:handleEvent(name, e) == false then
      return false
    end
  end
  return self:trigger(name, e)
end

function Element:processMouseEvent(name, e)
  if self:contains(e.x, e.y) then
    for _, child in ipairs(self.children) do
      if child:triggerMouseEvent(e) == false then
        return false
      end
    end
  end
end

function Element:contains(x, y)
  if not self.width or not self.height then return true end -- dummy wrapper
  return (self.x <= x and x <= self.x + self.width and self.y <= y and y <= self.y + self.height)
end

function Element:render(options)
  self.visible = true -- invisible elements don't get event callbacks because... they are not visible
  options = options or {}
  util.extend(self.attr, options.attr)
  self.x, self.y = love.graphics.transformPoint(0, 0)
  self:draw()
  self.width = self.width or self.attr.width or 0
  self.height = self.height or self.attr.height or 0

  if options.layout then
    love.graphics.translate(options.layout.x * self.attr.width, options.layout.y * self.attr.height)
  end
end

local Text = {}
function Text.getDimensions(text, size)
  local font = util.getFont(size)
  local width = font:getWidth(text)
  return width, font:getHeight()
end

function Text.print(text, size, x, y)
  love.graphics.setFont(util.getFont(size))
  love.graphics.print(text, x or 0, y or 0)
end

local function setdefault(t, k, v)
  if not t[k] then t[k] = v end
end

local Button = Element:extend()
function Button:new(attr)
  Element.new(self, attr)
  setdefault(self.attr, 'paddingX', 10)
  setdefault(self.attr, 'paddingY', 5)
  setdefault(self.attr, 'fontsize', 20)

  self:on('__mousemoved', function(x, y)
    self.hovering = self:contains(x, y)
  end)
end

function Button:draw()
  local tw, th = Text.getDimensions(self.attr.text, self.attr.fontsize)
  self.width = self.attr.width or tw + (self.attr.paddingX or 0) * 2
  self.height = self.attr.height or th + (self.attr.paddingY or 0) * 2
  love.graphics.setColor(self.attr.background)
  love.graphics.rectangle("fill", 0, 0, self.width, self.height)
  local x = self.width / 2 - tw / 2
  local y = self.height / 2 - th / 2
  if self.attr.align == "left" then
    x = self.attr.paddingX
  elseif self.attr.align == "right" then
    x = self.width - self.paddingX - th
  end
  love.graphics.setColor(self.attr.color)
  Text.print(self.attr.text, self.attr.fontsize, x, y)
end

local dir = {
  right = {x = -1, y = 0},
  left = {x = 1, y = 0},
  up = {x = 0, y = -1},
  down = {x = 0, y = 1},
}

local Header = Element:extend()
function Header:new(attr, state)
  Element.new(self, attr)
  self.state = state
  self.tab = 'file'

  local h = 30
  local function setTab(tab) self.tab = tab.attr.id end
  Element.new(self, attr,
    -- main tabs
    Button({id = 'file', type = 'main', text = "File"}):on('mousepressed', setTab),
    Button({id = 'edit', type = 'main', text = "Edit"}):on('mousepressed', setTab),
    Button({id = 'layer', type = 'main', text = "Layer"}):on('mousepressed', setTab),
    Button({id = 'frame', type = 'main', text = "Frame"}):on('mousepressed', setTab),

    -- file subtabs
    Button(fileTab, {text = "Save"}):on('mousepressed', self:dispatcher('SAVE')),

    -- edit subtabs
    Button({text = 'Undo', under = 'file'}),
    Button({text = 'Redo', under = 'file'}),

    -- TODO: layer subtabs - delete etc.

    -- frame subtabs
    Button({id = 'easing', under = 'frame', text = ''}):on('mousepressed', self:dispatcher('CHOOSE_EASING')),
    Button({under = 'frame', text = 'move left'}):on('mousepressed', self:dispatcher('MOVE_FRAME', {by = -1})),
    Button({under = 'frame', text = 'move right'}):on('mousepressed', self:dispatcher('MOVE_FRAME', {by = 1})),
    Button({under = 'frame', text = 'add'}):on('mousepressed', self:dispatcher('NEW_FRAME')),
    Button({under = 'frame', text = 'delete'}):on('mousepressed', self:dispatcher('DELETE_FRAME'))
  )

  self:on('resize', function(e)
    self.attr.width = e.width
  end)
end

local function whereami()
  return love.graphics.transformPoint(0, 0)
end

local function move(m)
  if m.to then
    local x, y = whereami()
    love.graphics.translate(m.to.x or x, m.to.y or y)
  end
  if m.by then
    local x, y = whereami()
    love.graphics.translate(x + (m.by.x or 0), y + (m.by.y or 0))
  end
end

function Header:draw()
  self:query({id = 'easing'})[1].attr.text = self.state.frame.easing
  local x = layout.sidebar.width
  local h = 30

  move({to = {x = self.x + layout.sidebar.width, y = self.y + self.attr.height - 30}})
  for _, tab in ipairs(self:query({under = self.tab})) do
    tab:render({layout = dir.right, attr = {height = h}})
  end

  move({by = {y = -h - 3}, to = {x = x}})
  love.graphics.setColor(colors.button.selected.background)
  love.graphics.rectangle("fill", -1000, 0, 100000, 3)

  move({by = {y = -h}})
  for _, tab in ipairs(self:query({type = 'main'})) do
    tab:render({layout = dir.right})
  end
end

-- ui layout
local sidebar = ui.Area(state.ui, {y = layout.header.height})
local header = ui.Area(state.ui)
local footer = ui.Area(state.ui)
local animationArea = ui.Rectangle(state.ui, {
  x = layout.sidebar.width,
  y = layout.header.height,
  background = {1, 1, 1, 1},
})

-- play/stop button
local play = ui.Area(state.ui, {w = 50, h = 50}):on('mousepressed', function()
  state.playing = not state.playing
  state.duration = 0
end)

-- main tabs
local fileTab = newButton(header, {id = 'file', type = 'maintab', text = "File"}):on('mousepressed', setTab)
local editTab = newButton(header, {id = 'edit', type = 'maintab', text = "Edit"}):on('mousepressed', setTab)
local layerTab = newButton(header, {id = 'layer', type = 'maintab', text = "Layer"}):on('mousepressed', setTab)
local frameTab = newButton(header, {id = 'frame', type = 'maintab', text = "Frame"}):on('mousepressed', setTab)
local mainTabs = {fileTab, editTab, layerTab, frameTab}
state.tab = fileTab

-- file subtabs
newButton(fileTab, {text = "Save"}):on('mousepressed', function() state.error = state.animation:save() end)

-- edit subtabs
newButton(editTab, {text = 'Undo'})
newButton(editTab, {text = 'Redo'})

-- TODO: layer subtabs - delete etc.

-- frame subtabs
local easingButton = newButton(frameTab, {text = 'linear speed'}):on('mousepressed', function() state.showEasingPicker = true end)
newButton(frameTab, {text = 'move left'}):on('mousepressed', function()
  state.animation:swap('frames', state.frame, -1)
end)
newButton(frameTab, {text = 'move right'}):on('mousepressed', function()
  state.animation:swap('frames', state.frame, 1)
end)
newButton(frameTab, {text = 'add'}):on('mousepressed', newFrame)
newButton(frameTab, {text = 'delete'}):on('mousepressed', function()
  state.frame = state.animation:tryDeleteFrame(state.frame) or state.frame
end)

-- layer up/down buttons
local layerUp = newButton(state.ui, {text = "up", align = "center"}):on('mousepressed', function() changeLayerPriority(-1) end)
local layerDown = newButton(state.ui, {text = "down", align = "center"}):on('mousepressed', function() changeLayerPriority(1) end)

-- change speed
local faster = newButton(header, {text = "-"}):on('mousepressed', function() state.animation:adjustSpeed(-0.05) end)
local slower = newButton(header, {text = "+"}):on('mousepressed', function() state.animation:adjustSpeed(0.05) end)
local showSpeed = newButton(header)

-- big button to add new frame
local newFrameButton = ui.Rectangle(state.ui):on('mousepressed', newFrame)

-- error message
local errorMessage = newButton(state.ui):on('mousepressed', function() state.error = nil end)

local ew = ui.Rectangle(state.ui):on('mousepressed', function() state.showEasingPicker = false end)
ui.Rectangle(ew, {easing = "linear"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeIn"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeInx2"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeOut"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeOutx2"}):on('mousepressed', setEasingFunc)

-- drawing functions
local draw = {}

function draw.frame(f)
  if f then
    for i = #state.animation.layers, 1, -1 do
      local layer = state.animation:reader(f.id, 'layers', state.animation.layers[i].id)
      local w, h = state.animation.images[layer.id]:getDimensions()
      love.graphics.draw(state.animation.images[layer.id], layer.x, layer.y, layer.angle, 1, 1, w / 2, h / 2)
    end
  end
end

function draw.exactFrame(f1, f2, elapsed, framepos)
  if f1 and f2 then
    local pos = util.easings[f1.easing](framepos)
    for i = #state.animation.layers, 1, -1 do
      local layer = state.animation.layers[i]
      local f1l = state.animation:reader(f1.id, 'layers', layer.id)
      local f2l = state.animation:reader(f2.id, 'layers', layer.id)
      local x = f1l.x * (1 - pos) + f2l.x * pos
      local y = f1l.y * (1 - pos) + f2l.y * pos
      local start, distance = util.shortestRotation(f1l.angle, f2l.angle)
      local angle = start + distance * framepos
      local image = state.animation.images[layer.id]
      love.graphics.draw(image, x, y, angle, 1, 1, image:getWidth() / 2, image:getHeight() / 2)
    end
  end
end

function draw.animationArea()
  -- draw background
  animationArea:moveTo()
  animationArea:draw({
    width = layout.window.width - layout.sidebar.width,
    height = layout.window.height - layout.header.height - layout.footer.height,
  })

  animationArea:moveTo(animationArea.w / 2, animationArea.h / 2)

  if state.playing then
    local total = state.animation:duration()
    local elapsed = util.remap(state.duration % total, 0, total, 1, #state.animation.frames)
    local f1 = state.animation.frames[math.floor(elapsed)]
    local f2 = state.animation.frames[math.ceil(elapsed)]
    draw.exactFrame(f1, f2, (state.duration % total) / total, elapsed % 1)
  else
    local i = util.findIndex(state.animation.frames, state.frame)

    -- draw shadow of frame before this one
    love.graphics.setShader(util.solidColorShader(0, 0, 1, 0.15))
    draw.frame(state.animation.frames[i - 1])

    -- draw shadow of the frame after this one
    love.graphics.setShader(util.solidColorShader(0, 1, 0, 0.15))
    draw.frame(state.animation.frames[i + 1])

    -- and the current frame
    love.graphics.setShader()
    draw.frame(state.animation.frames[i])
  end
end

function draw.sidebar()
  sidebar:moveTo()
  sidebar.children = {}
  for i, layer in ipairs(state.animation.layers) do
    local button = newButton(sidebar):on('mousepressed', function()
      state.layer = state.animation.layers[i]
    end)

    button:draw({fontSize = 20, text = layer.name, width = layout.sidebar.width, selected = (layer == state.layer)}):layout(ui.down)
  end

  -- buttons to move layer up or down
  layerUp:draw({width = layout.sidebar.width / 2, align = "center"}):layout(ui.right)
  layerDown:draw({width = layout.sidebar.width / 2})
end

function draw.header()
  local h = 30 -- tab height
  local hr = 3 -- horizontal separator

  -- main tabs
  header:moveTo(layout.sidebar.width, layout.header.height - h * 2 - hr)
  for _, tab in ipairs(mainTabs) do
    tab:draw({fontSize = 22, align = "left", width = 100, height = h, selected = (tab == state.tab)}):layout(ui.right)
  end

  -- subtabs
  easingButton.text = state.frame.easing
  header:moveTo(layout.sidebar.width, layout.header.height - h)
  for _, tab in ipairs(state.tab.children) do
    tab:draw({height = h}):layout(ui.right)
  end

  -- show total animation time
  header:moveTo(layout.window.width - 160, layout.header.height - h * 2 - hr)
  local time = state.animation:duration()
  showSpeed:draw({width=100, height=30, text = 'Time: ' .. tostring(time):sub(1, 4) .. 's'}):layout(ui.right)
  slower:draw({width=30, height=30, align = "center"}):layout(ui.right)
  faster:draw({width=30, height=30, align = "center"}):layout(ui.right)

  -- a pretty line/separator
  header:moveTo()
  love.graphics.setColor(colors.button.selected.background)
  love.graphics.rectangle("fill", 0, layout.header.height - h - hr, layout.window.width, 3)
end

function draw.footer()
  footer.y = layout.window.height - layout.footer.height

  -- play/pause button
  local r = 25
  footer:moveTo(layout.sidebar.width / 2, layout.footer.height / 2)
  play.x, play.y = love.graphics.transformPoint(-r, -r)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("line", 0, 0, r)
  if state.playing then
    love.graphics.rectangle("fill", -10, -10, 20, 20)
  else
    love.graphics.polygon("fill", -7, -10, -7, 10, 13, 0)
  end

  -- draw all the frames
  local pad = 5
  local size = layout.footer.height - pad * 2
  footer:moveTo(layout.sidebar.width, pad)
  footer.children = {}
  for i, frame in ipairs(state.animation.frames) do
    -- border around the selected frame
    if frame == state.frame then
      love.graphics.setColor(colors.button.selected.background)
      love.graphics.rectangle("fill", -2, -2, size + 4, size + 4)
    end

    local rect = ui.Rectangle(footer):on('mousepressed', function()
      state.frame = frame
    end)

    -- draw white background
    rect:draw({width = size, height = size, background = {1, 1, 1, 1}})

    -- draw preview of the frame
    love.graphics.push()
    love.graphics.translate(size / 2, size / 2)
    love.graphics.scale(0.2, 0.2)
    draw.frame(frame)
    love.graphics.pop()

    -- change position for the next frame
    rect:layout(ui.right, pad)
  end

  if state.playing then
    -- line for current animation time/location
    footer:moveTo(layout.sidebar.width)
    love.graphics.setColor(1, 0, 0, 1)
    local elapsed = (state.duration % state.animation:duration()) % state.animation:duration()
    love.graphics.rectangle("fill", ((size + pad) * #state.animation.frames - pad * 2) * elapsed, 0, 2, size + pad * 2)
  end

  -- add new frame button
  footer:moveTo(layout.window.width - size / 2 - pad, pad)
  newFrameButton:draw({width = size/2, height = size/2, background = {0, 0, 0, 0.8}})
  love.graphics.setLineWidth(3)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.line(size / 4, 10, size / 4, size / 2 - 10)
  love.graphics.line(10, size / 4, size / 2 - 10, size / 4)
end

function draw.easingPicker()
  if not state.showEasingPicker then return end

  ew:draw({width = layout.window.width, height = layout.window.height, background = {0, 0, 0, 0.6}})

  local wpad = 50
  ew:moveTo(wpad, wpad)

  local w, h = 200, 150
  local pad = 20
  for _, button in ipairs(ew.children) do
    -- background
    button:draw({width = w, height = h, background = {0, 0, 0, 0.8}, radius = 10})

    -- draw animation curve
    local line = {}
    for i = 0, 100 do
      line[#line+1] = pad + i / 100 * (w - pad * 2)
      line[#line+1] = h - pad * 2 - util.easings[button.easing](i / 100) * (h - pad * 2 - 30)
    end
    love.graphics.setColor(colors.button.selected.background)
    love.graphics.setLineWidth(2)
    love.graphics.line(line)

    -- dot to show the speed of the animation
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", w - pad, h - pad * 2 - util.easings[button.easing](state.duration % 1) * (h - pad * 2 - 30), 4)
    local tw, th = ui.Text.getDimensions(button.easing, 18)

    -- name
    ui.Text.print(button.easing, 18, w / 2 - tw / 2, h * 0.8)

    -- layout - go to next line when we run out of space
    button:layout(ui.right, wpad)
    local x, y = love.graphics.transformPoint(0, 0)
    if x + w + wpad > layout.window.width then
      love.graphics.translate(-x + wpad, h + pad)
    end
  end
end

function love.load(arg)
  love.graphics.setBackgroundColor(colors.background)
  love.window.setMode(layout.window.width, layout.window.height, {resizable = true, minwidth = 800, minheight = 600})

  for _, filename in ipairs(arg) do
    state.layer = state.animation:newLayer(io.open(filename, 'rb'):read('*a'), filename)
  end
end

local header
function love.draw()
  love.graphics.clear(colors.background)
  header = header or Header({width = 800, height = 100}, state)
  header:render()
  -- state.ui:updateAll({visible = false})
  --
  -- for _, name in ipairs({"header", "footer", "sidebar", "animationArea", "easingPicker"}) do
  --   love.graphics.reset()
  --   love.graphics.origin()
  --   draw[name]()
  -- end
end

function love.update(dt)
  state.duration = state.duration + dt
  -- TODO: loop or no loop?
  -- if state.duration > state.timePerFrame * #state.frames then
  --   state.playing = false
  -- end
  -- TODO: limit framerate when not playing animation?
end

function love.filedropped(file)
  -- accept new images when dropped
  state.layer = state.animation:newLayer(file:read(), file:getFilename())
end

local mountpoints = {}
function love.directorydropped(dir)
  -- love2d bug? we can't mount a directory for a second time after previously mounting and unmounting
  -- so we'll mount it for the first time only and never unmount
  if not mountpoints[dir] then
    mountpoints[dir] = "animation-love-loading-" .. love.math.random(2^32)
    love.filesystem.mount(dir, mountpoints[dir])
  end

  local err, animation = Animation.load(mountpoints[dir])
  if err then
    state.error = err
    error(err)
  else
    state.animation = animation
    state.frame = animation.frames[1]
    state.layer = animation.layers[1]
  end
end

function love.mousepressed(x, y, button)
  state.ui:handleEvent('mousepressed', {x = x, y = y})

  if button == 2 and state.layer then
    startRotation(x, y)
  end
end

function love.mousereleased(x, y, button)
  if button == 2 then
    state.rotation.active = false
  end
end

function love.mousemoved(x, y, dx, dy, istouch)
  state.ui:setHoverState(x, y)

  if state.layer and love.mouse.isDown(1) then
    -- drag layer around with left mouse button
    adjustLayerPosition(dx, dy)
  elseif state.layer and state.rotation.active and love.mouse.isDown(2) then
    -- rotate layer with right mouse button
    rotate(x, y, animationArea:getCenter())
  end
end

function love.keypressed(key, keycode, isrepeat)
  -- adjust layer position with arrow keys
  if key == "left"  then adjustLayerPosition(-1, 0) end
  if key == "right" then adjustLayerPosition(1, 0)  end
  if key == "up"    then adjustLayerPosition(0, -1) end
  if key == "down"  then adjustLayerPosition(0, 1)  end
end

function love.resize(w, h)
  layout.window.width = w
  layout.window.height = h
end
