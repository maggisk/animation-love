local util = require "util"

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


local Area = util.Object:extend()
function Area:new(parent, options)
  self.parent = parent
  self.x, self.y = 0, 0
  self.w, self.h = 0, 0
  self.theme = {}
  util.extend(self, options)
  self.children = {}
  self.events = {}
  if parent then
    parent.children[#parent.children + 1] = self
  end
end

function Area:updateAll(props)
  util.extend(self, props)
  for _, child in ipairs(self.children) do
    child:updateAll(props)
  end
end

function Area:getCenter()
  return self.x + self.w / 2, self.y + self.h / 2
end

function Area:gotoPosition(x, y)
  love.graphics.origin()
  love.graphics.translate(self.x + (x or 0), self.y + (y or 0))
end

function Area:getTheme(o, ...)
  local theme = util.extend({}, o.theme)
  for _, k in ipairs({...}) do
    if o[k] then
      util.extend(theme, self.theme[k])
    end
  end
  return theme
end

function Area:contains(x, y)
  return self.x <= x and x <= self.x + self.w and self.y < y and y < self.y + self.h
end

function Area:layout(dir, x, y)
  love.graphics.translate(self.w * dir.x + (x or 0), self.h * dir.y + (y or 0))
end

function Area:on(name, fn)
  assert(name and fn)
  self.events[name] = fn
  return self
end

function Area:trigger(name, ...)
  assert(name)
  if self.events[name] then
    return self.events[name](self, ...)
  end
end

function Area:setHoverState(x, y)
  self.hover = self:contains(x, y)
  for _, child in ipairs(self.children) do
    child:setHoverState(x, y)
  end
end

function Area:handleEvent(name, e)
  -- Area can't be invislble but child classes can
  if self.visible or getmetatable(self) == Area then
    for _, child in ipairs(self.children) do
      if child:handleEvent(name, e) == false then
        -- prevent parent objects from getting event notification by returning false in callback
        return
      end
    end
    if self:contains(e.x, e.y) then
      return self:trigger(name)
    end
  end
end

local Rectangle = Area:extend()
function Rectangle:draw(o)
  self.visible = true
  o = util.extend({}, self, o)
  if o.width  then self.w = o.width  end
  if o.height then self.h = o.height end
  local background = (o and o.background) or self.background
  if background then
    love.graphics.setColor(background)
    love.graphics.rectangle("fill", 0, 0, self.w, self.h, o.radius)
  end
  self.x, self.y = love.graphics.transformPoint(0, 0)
end

local Button = Area:extend()
function Button:new(parent, options)
  assert(self and parent)
  Area.new(self, parent, options)
  self.paddingX = 10
  self.paddingY = 5
  self.width = "auto"
  self.height = "auto"
  self.fontSize = 18
  self.align = "left"
  util.extend(self, options)
end

function Button:draw(o)
  self.visible = true
  o = util.extend({}, self, o)

  local tw, th = Text.getDimensions(o.text or "", o.fontSize)
  local w, h = o.width, o.height

  -- decide dimensions of auto-sized button
  if w == "auto" then w = tw + o.paddingX * 2 end
  if h == "auto" then h = th + o.paddingY * 2 end

  -- save position and size for layouting
  self.x, self.y = love.graphics.transformPoint(0, 0)
  self.w, self.h = w, h

  local theme = self:getTheme(o, "hover", "selected")
  love.graphics.setColor(theme.background)
  love.graphics.rectangle("fill", 0, 0, w, h)

  if o.text then
    local x = w / 2 - tw / 2
    local y = h / 2 - th / 2
    if o.align == "left" then x = o.paddingX end
    love.graphics.setColor(theme.font)
    Text.print(o.text, o.fontSize, x, y)
  end

  return self
end

return {
  Area = Area,
  Rectangle = Rectangle,
  Text = Text,
  Button = Button,
  left = {x = -1, y = 0},
  right = {x = 1, y = 0},
  up = {x = 0, y = -1},
  down = {x = 0, y = 1},
}
