local util = require "util"
local Object = require "classic"
local playback = require "playback"

local colors = {
  background = {0.157, 0.173, 0.204, 1},
  button = {
    font = {1, 1, 1, 1},
    background = {0, 0, 0, 0},
    selected = {background = {78.6/255, 146.2/255, 228.8/255, 1}},
    hovering = {background = {73.6/255, 85.8/255, 100.6/255, 1}},
  },
  currentFrameBorder = {78.6/255, 146.2/255, 228.8/255, 1},
}

local dir = {
  left = {x = -1, y = 0},
  right = {x = 1, y = 0},
  up = {x = 0, y = -1},
  down = {x = 0, y = 1},
}

local function whereami()
  return love.graphics.transformPoint(0, 0)
end

local function move(m)
  if m.to then
    local x, y = whereami()
    love.graphics.origin()
    love.graphics.translate(m.to.x or x, m.to.y or y)
  end
  if m.by then
    local x, y = whereami()
    love.graphics.translate(m.by.x or 0, m.by.y or 0)
  end
end

local function matches(table, attr)
  for k, v in pairs(attr) do
    if table[k] ~= v then return false end
  end
  return true
end

local function first(iter, default)
  for v in iter do return v end
  return default
end

local function background(color, ...)
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", ...)
  love.graphics.setColor(r, g, b, a)
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

local Element = Object:extend()
function Element:new(attr, ...)
  self.attr = attr or {}
  self.children = {...}
  self.events = {}
  self.context = {}
end

function Element:add(...)
  for _, child in ipairs({...}) do
    child.context = self.context
    table.insert(self.children, child)
  end
  return self.children[#self.children]
end

function Element:getOrCreate(query, create)
  for e in self:query(query) do return e end
  return self:add(create())
end

function Element:callback(eventName, payload)
  return function()
    self.context.dispatch(eventName, payload)
  end
end

function Element:iter()
  local r, h, t, q = nil, 1, 1, {self}
  return function()
    if h <= t then
      for i = 1, #q[h].children do
        t = t + 1
        q[t] = q[h].children[i]
      end
      r, q[h] = q[h], nil
      h = h + 1
      return r
    end
  end
end

function Element:query(q)
  local iter = self:iter()
  return function()
    for node in iter do
      if matches(node.attr, q) then
        return node
      end
    end
  end
end

function Element:getCenter()
  return (self.width or self.attr.width) / 2, (self.height or self.attr.height) / 2
end

function Element:on(name, fn)
  assert(name and fn)
  self.events[name] = self.events[name] or {}
  table.insert(self.events[name], fn)
  return self
end

function Element:off(name, fn)
  assert(self:hasListener(name, fn))
  table.remove(self.events[name], util.indexOf(self.events[name], fn))
end

function Element:hasListener(name, fn)
  return util.indexOf(self.events[name] or {}, fn) ~= nil
end

function Element:trigger(name, e)
  if self.events[name] then
    for _, fn in ipairs(self.events[name]) do
      if fn(self, e) == false then
        return false
      end
    end
  end
end

function Element:broadcast(name, e)
  -- like an event, but the order doesn't matter and it's not cancellable
  for node in self:iter() do node:trigger(name, e) end
end

function Element:processEvent(name, e)
  for i = #self.children, 1, -1 do
    if self.children[i]:processEvent(name, e) == false then
      return false
    end
  end
  local isMouseEvent = (e.x and e.y) ~= nil
  if self.visible and (
      (not isMouseEvent and self:trigger(name, e) == false) or
      (isMouseEvent and self:contains(e.x, e.y) and self:trigger(name, e) == false) or
      (isMouseEvent and self:trigger('window' .. name, e) == false)) then
    return false
  end
end

function Element:contains(x, y)
  if not self.x or not self.y or not self.width or not self.height then return true end -- dummy wrapper
  return (self.x <= x and x <= self.x + self.width and self.y <= y and y <= self.y + self.height)
end

function Element:render(attr, layout)
  self.visible = true 
  for _, child in ipairs(self.children) do
    -- forward context object to child
    child.context = self.context
    -- mark child invisible so it won't receive keyboard/mouse events unless this
    -- elements renders it when we call draw()
    child.visible = false
  end

  -- extend attributes with those passed to render
  -- XXX: since we merge the given table into self.attr, once merged it can not be set to nil again, which is.. not great
  util.extend(self.attr, attr)

  -- simple auto layouting when element should take up all available space
  self.x, self.y = whereami()
  self.width  = self.attr.width  or self.context.window.width  - self.x - (self.attr.right or 0)
  self.height = self.attr.height or self.context.window.height - self.y - (self.attr.bottom or 0)

  -- render it
  love.graphics.push()
  self:draw()
  love.graphics.pop()

  -- move rendering coordinates for next element if parent element specifies it
  if layout then self:layout(layout) end
end

function Element:layout(dir)
  love.graphics.translate(dir.x * self.width, dir.y * self.height)
end

function Element:draw()
end

local Button = Element:extend()
function Button:new(attr)
  Element.new(self, util.extend({
    paddingX = 10,
    fontsize = 20,
    theme = colors.button,
  }, attr))

  if not self.attr.height and not self.attr.paddingY then
    self.attr.paddingY = 5
  end

  self:on('windowmousemoved', self.onMouseMoved)
end

function Button:onMouseMoved(e)
  self.attr.hovering = self:contains(e.x, e.y)
end

function Button:getTheme()
  local theme = self.attr.theme
  for _, k in ipairs({'hovering', 'selected'}) do
    if self.attr[k] == true and self.attr.theme[k] then
      theme = util.extend({}, theme, self.attr.theme[k])
    end
  end
  return theme
end

function Button:draw()
  local theme = self:getTheme()
  local tw, th = Text.getDimensions(self.attr.text, self.attr.fontsize)
  self.width = self.attr.width or tw + (self.attr.paddingX or 0) * 2
  self.height = self.attr.height or th + (self.attr.paddingY or 0) * 2
  background(theme.background, 0, 0, self.width, self.height)
  local x = self.width / 2 - tw / 2
  local y = self.height / 2 - th / 2
  if self.attr.align == "left" then
    x = self.attr.paddingX
  elseif self.attr.align == "right" then
    x = self.width - self.paddingX - th -- untested
  end
  love.graphics.setColor(theme.font)
  Text.print(self.attr.text, self.attr.fontsize, x, y)
end

local Header = Element:extend()
function Header:new(attr)
  self.tab = 'file'

  local function setTab(tab) self.tab = tab.attr.id end

  Element.new(self, attr,
    -- main tabs
    Button({id = 'file', type = 'main', text = "File"}):on('mousepressed', setTab),
    Button({id = 'edit', type = 'main', text = "Edit"}):on('mousepressed', setTab),
    Button({id = 'layer', type = 'main', text = "Layer"}):on('mousepressed', setTab),
    Button({id = 'joint', type = 'main', text = "Joints"}):on('mousepressed', setTab),
    Button({id = 'frame', type = 'main', text = "Frame"}):on('mousepressed', setTab),

    -- file subtabs
    Button({text = "New", below = 'file'}):on('mousepressed', self:callback('NEW_PROJECT')),
    Button({text = "Save", below = 'file'}):on('mousepressed', self:callback('SAVE')),

    -- edit subtabs
    Button({text = 'Undo', below = 'edit'}):on('mousepressed', self:callback('UNDO')),
    Button({text = 'Redo', below = 'edit'}):on('mousepressed', self:callback('REDO')),

    -- layer subtabs
    Button({text = 'Delete', below = 'layer'}):on('mousepressed', self:callback('DELETE_LAYER')),

    -- joint subtabs
    Button({text = "New", below = 'joint'}):on('mousepressed', self:callback('NEW_JOINT')),

    -- frame subtabs
    Button({below = 'frame', id = 'easing'}):on('mousepressed', self:callback('BROADCAST', {event = 'easingtoggle'})),
    Button({below = 'frame', text = 'move left'}):on('mousepressed', self:callback('MOVE_FRAME', -1)),
    Button({below = 'frame', text = 'move right'}):on('mousepressed', self:callback('MOVE_FRAME', 1)),
    Button({below = 'frame', text = 'add'}):on('mousepressed', self:callback('NEW_FRAME')),
    Button({below = 'frame', text = 'delete'}):on('mousepressed', self:callback('DELETE_FRAME')),

    -- buttons to move layers up/down
    Button({type = 'movelayer', text = "up"}):on('mousepressed', self:callback('CHANGE_LAYER_PRIORITY', -1)),
    Button({type = 'movelayer', text = "down"}):on('mousepressed', self:callback('CHANGE_LAYER_PRIORITY', 1))
  )
end

function Header:draw()
  first(self:query({id = 'easing'})).attr.text = self.context.state.frame.easing
  local h = 30 -- tab height

  -- button far left to change which layer is on top of which
  move({to = {y = self.attr.height - h}})
  for button in self:query({type = 'movelayer'}) do
    button:render({fontsize = 16}, dir.right)
  end

  -- subtabs first
  move({to = {x = self.attr.left}})
  for tab in self:query({below = self.tab}) do
    tab:render({height = h}, dir.right)
  end

  -- pretty line separator
  move({to = {x = self.attr.left}, by = {y = -3}})
  background(colors.button.selected.background, -self.attr.left, 0, self.width, 3)

  -- main tabs
  move({by = {y = -h}})
  for tab in self:query({type = 'main'}) do
    tab:render({selected = (self.tab == tab.attr.id), align = "left", height = h, fontsize = 28, width = 100}, dir.right)
  end
end

local Sidebar = Element:extend()
function Sidebar:draw()
  for _, layer in ipairs(self.context.state.animation.layers) do
    local button = self:getOrCreate({id = layer.id}, function()
      return Button({id = layer.id}):on('mousepressed', self:callback('SELECT_LAYER', layer.id))
    end)
    button:render({text = layer.name, width = self.attr.width, selected = (layer.id == self.context.state.layer.id)}, dir.down)
  end
end

local Frame = Element:extend()
function Frame:draw()
  local player = self.attr.player
  if not self.attr.player then
    if self.context.state.animation.frames[self.attr.frame] then
      player = self.context.state.player
      player:setFrame(self.attr.frame)
    else
      return
    end
  end

  background(self.attr.background or {1, 1, 1, 1}, 0, 0, self.attr.width, self.attr.height)

  local function hideOverflow() love.graphics.rectangle("fill", 0, 0, self.attr.width, self.attr.height) end
  love.graphics.stencil(hideOverflow, "replace", 1)

  love.graphics.translate(self.attr.offsetX or 0, self.attr.offsetY or 0)

  local x, y = self:getCenter()
  move({by = {x = x, y = y}})
  love.graphics.scale(self.attr.scale or 1)

  love.graphics.setStencilTest("equal", 1)
  love.graphics.setShader(self.attr.shader or nil) -- allow setting shader to false
  player:draw()
  love.graphics.setShader()
  love.graphics.setStencilTest()
end

local AnimationArea = Element:extend()
function AnimationArea:new(attr)
  Element.new(self, attr)
  self.frame = self:add(Frame())
  self.clickcount = {}

  self:on('wheelmoved', self.onWheelMoved)
  self:on('mousepressed', self.onMousePressed)
  self:on('windowmousereleased', self.onWindowMouseReleased)
  self:on('toggleplay', self.onTogglePlay)
end

function AnimationArea:onWheelMoved(e)
  self.context.dispatch('ZOOM', e.scrollY)
end

function AnimationArea:onMousePressed(e)
  if self.context.state.layer then
    -- to use as event id on move and rotation events
    self.clickcount[e.button] = (self.clickcount[e.button] or 0) + 1

    if e.button == 1 then
      self:on('windowmousemoved', self.onDragMove)
    elseif e.button == 2 then
      self:on('windowmousemoved', self.onRotateMove)
      local s = self.context.state
      self.rotation = {x = e.x, y = e.y, angle = s.animation.framelayers[s.frame.id][s.layer.id].angle}
    end
  end
end

function AnimationArea:onWindowMouseReleased(e)
  if e.button == 1 and self:hasListener('windowmousemoved', self.onDragMove) then
    self:off('windowmousemoved', self.onDragMove)
  elseif e.button == 2 and self:hasListener('windowmousemoved', self.onRotateMove) then
    self:off('windowmousemoved', self.onRotateMove)
  end
end

function AnimationArea:onDragMove(e)
  if love.keyboard.isDown('lctrl', 'rctrl') then
    self.context.dispatch('MOVE_CENTER', {x = e.dx, y = e.dy})
  else
    self.context.dispatch('MOVE_LAYER', self.context.state.layer,
      {x = e.dx, y = e.dy, all = love.keyboard.isDown('lctrl'), id = self.clickcount[1]})
  end
end

function AnimationArea:onRotateMove(e)
  local x, y = self:getCenter()
  local center = {x = self.x + x, y = self.y + y}
  self.context.dispatch('ROTATE_LAYER',
    {start = self.rotation, now = e, center = center, id = self.clickcount[2]})
end

function AnimationArea:onTogglePlay()
  self.context.playing = not self.context.playing
  if self.context.playing then
    local animation = self.context.state.animation
    self.player = playback.Animation(animation.state, animation.images)
    self.player.loop = true
    self:on('tick', self.tick)
  else
    self:off('tick', self.tick)
    self.player = false
  end
end

function AnimationArea:tick(dt)
  self.player:update(dt)
end

function AnimationArea:draw()
  background({1, 1, 1, 1}, 0, 0, self.width, self.height)
  local attr = {width = self.width, height = self.height, player = self.player,
    background = {0, 0, 0, 0}, scale = self.context.state.zoom,
    offsetX = self.context.state.offsetX, offsetY = self.context.state.offsetY}

  if attr.player then
    self.frame:render(attr)
  else
    local frame = util.indexOf(self.context.state.animation.frames, self.context.state.frame)
    self.frame:render(util.extend(attr, {frame = frame - 1, shader = util.solidColorShader(0, 0, 0, 0.1)}))
    self.frame:render(util.extend(attr, {frame = frame + 1, shader = util.solidColorShader(1, 1, 0, 0.15)}))
    self.frame:render(util.extend(attr, {frame = frame, shader = false}))
  end
end

local PlayButton = Element:extend()
function PlayButton:new(attr)
  Element.new(self, attr)
  self:on('mousepressed', self.onMousePressed)
end

function PlayButton:onMousePressed(e)
  local x, y = self:getCenter()
  if (self.x + x - e.x)^2 + (self.y + y - e.y)^2 <= self.r^2 then
    self.context.dispatch('BROADCAST', {event = 'toggleplay'})
  end
end

function PlayButton:draw()
  self.r = self.height / 4
  local x, y = self:getCenter()
  move({by = {x = x, y = y}})
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("line", 0, 0, self.r)
  if self.context.playing then
    love.graphics.rectangle("fill", -10, -10, 20, 20)
  else
    love.graphics.polygon("fill", -7, -10, -7, 10, 13, 0)
  end
end

local Frames = Element:extend()
function Frames:draw()
  local pad = 5
  move({by = {y = pad}})
  local framesize = self.height - pad * 2
  for i, frame in ipairs(self.context.state.animation.frames) do
    local elem = self:getOrCreate({id = frame.id}, function()
      return Frame({id = frame.id, scale = 0.2}):on('mousepressed', self:callback('SELECT_FRAME', frame.id))
    end)
    elem:render({width = framesize, height = framesize, frame = i})
    if frame == self.context.state.frame then
      love.graphics.setColor(colors.currentFrameBorder)
      love.graphics.setLineWidth(3)
      love.graphics.rectangle("line", 1, 1, framesize - 2, framesize - 2)
      love.graphics.setColor(1, 1, 1, 1)
    end
    move({by = {x = pad}})
    elem:layout(dir.right)
  end
end

local Easing = Element:extend()
function Easing:new(attr)
  Element.new(self, attr)
  self.button = self:add(Button({align = "left", text = self.attr.name}))
end

function Easing:draw()
  background(colors.background, 0, 0, self.attr.width, self.attr.height)
  self.button:render({width = self.attr.width, height = self.attr.height})
  local bw = 120 -- button space
  local lw = self.attr.width - bw - 10 -- easing line width
  move({by = {x = bw, y = self.attr.height / 2}})
  love.graphics.setColor(colors.button.selected.background)
  love.graphics.line(0, 0, lw, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.circle("fill", lw * playback.easing[self.attr.name](self.attr.time), 0, 4)
  self.height = self.button.height
end

local EasingPicker = Element:extend()
function EasingPicker:new(attr)
  Element.new(self, attr)
  self.isOpen = false
  self.names = util.keys(playback.easing)
  table.sort(self.names)

  for _, name in ipairs(self.names) do
    self:add(Easing({name = name})):on('mousepressed', self:callback('SELECT_EASING', name))
  end

  self:on('easingtoggle', self.toggle)
  self:on('windowmousepressed', self.toggle)
end

function EasingPicker:toggle()
  self.isOpen = not self.isOpen
  self.start = self.context.state.duration
  return false
end

function EasingPicker:draw()
  self.visible = self.isOpen
  if not self.isOpen then return end
  move({to = {x = self.attr.left, y = self.attr.top}})

  self.x, self.y = whereami()
  self.width = 400
  self.height = 30 * #self.children

  local time = (self.context.state.duration - self.start) % 2 / 2
  for _, child in ipairs(self.children) do
    child:render({time = time, width = self.width, height = 30}, dir.down)
  end
end

local Window = Element:extend()
function Window:new(attr)
  Element.new(self, attr,
    Header({height = 100, left = 200}),
    Sidebar({width = 200, bottom = 100}),
    AnimationArea({bottom = 100}),
    PlayButton({width = 200}),
    Frames(),
    EasingPicker({left = 200, top = 100})
  )
end

function Window:draw()
  background(colors.background, 0, 0, self.width, self.height)

  for _, child in ipairs(self.children) do
    child:render({}, dir.right)
    if child.x + child.width >= self.width then
      move({to = {x = 0}, by = {y = child.height}})
    end
  end
end

return {
  Window = Window,
}
