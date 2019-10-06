local function __decode(lines)
  local line = table.remove(lines):gsub("^ *", "")
  local t = line:sub(1, 1)
  if t == "t" then
    local table = {}
    for _ = 1, tonumber(line:sub(2, -1)) do
      local k = __decode(lines)
      table[k] = __decode(lines)
    end
    return table
  elseif t == "n" then
    return tonumber(line:sub(2, -1))
  elseif t == "s" then
    return line:sub(2, -1)
  else
    error("can't decode line: " .. line)
  end
end

local function decode(lines)
  local n = #lines
  for i = 1, math.floor(n / 2) do
    lines[i], lines[n - i + 1] = lines[n - i + 1], lines[i]
  end
  return __decode(lines)
end

local easing = {}
function easing.linear(t)
  return t
end
function easing.easeIn(t)
  return t*t
end
function easing.easeInx2(t)
  return t*t*t
end
function easing.easeOut(t)
  t = t - 1
  return 1-(t*t)
end
function easing.easeOutx2(t)
  t = t - 1
  return 1-(t*t*-t)
end

local Animation = {}
Animation.__index = Animation
setmetatable(Animation, {
  __call = function(_, data, images)
    local self = setmetatable({}, Animation)
    self.data = data
    self.images = images
    self:reset()
    return self
  end
})

function Animation:reset()
  self.frame = 1
  self.elapsed = 0
  self.done = false
end

function Animation:getTotalDuration()
  local sum = 0
  for _, frame in ipairs(self.data.frames) do
    sum = sum + frame.duration
  end
  return sm
end

function Animation:update(dt)
  if not self.done then
    self.elapsed = self.elapsed + dt
    if self.elapsed >= self.data.frames[self.frame].duration then
      self.elapsed = self.elapsed % self.data.frames[self.frame].duration
      if self.frame < #self.data.frames - 1 then
        self.frame = self.frame + 1
      elseif self.loop then
        self.frame = 1
      else
        self.done = true
        self.elapsed = self.data.frames[self.frame].duration
      end
    end
  end
end

function Animation:setFrame(frame)
  assert(type(frame) == "number", "expected number, got " .. type(frame))
  assert(frame >= 1 and frame <= #self.data.frames, "out of bounds frame")
  self.frame = frame
  self.elapsed = 0
end

function Animation:seek(time)
  if self.loop then
    time = time % self.getTotalDuration()
  end

  self:reset()
  for i = 1, #self.data.frames - 1 do
    local frame = self.data.frames[i]
    if frame.duration <= time then
      self.frame = self.frame + 1
      time = time - frame.duration
      self.elapsed = self.elapsed + frame.duration
    else
      self:update(time)
    end
  end
end

function Animation:draw()
  local r, g, b, a = love.graphics.getColor()
  local thisFrame = self.data.frames[self.frame]
  local nextFrame = self.data.frames[self.frame + 1] or thisFrame
  for i = #self.data.layers, 1, -1 do
    local thisLayer = self.data.framelayers[thisFrame.id][self.data.layers[i].id]
    local nextLayer = self.data.framelayers[nextFrame.id][self.data.layers[i].id]
    local pos = easing[thisLayer.easing or thisFrame.easing](self.elapsed / thisFrame.duration)
    local image = self.images[self.data.layers[i].id]
    local w, h = image:getDimensions()
    local x = thisLayer.x * (1 - pos) + nextLayer.x * pos
    local y = thisLayer.y * (1 - pos) + nextLayer.y * pos
    local angle = thisLayer.angle * (1 - pos) + nextLayer.angle * pos
    local scaleX = (thisLayer.scaleX or thisFrame.scaleX) * (1 - pos) + (nextLayer.scaleX or nextFrame.scaleX) * pos
    local scaleY = (thisLayer.scaleY or thisFrame.scaleY) * (1 - pos) + (nextLayer.scaleY or nextFrame.scaleY) * pos
    local shearX = (thisLayer.shearX or thisFrame.shearX) * (1 - pos) + (nextLayer.shearX or nextFrame.shearX) * pos
    local shearY = (thisLayer.shearY or thisFrame.shearY) * (1 - pos) + (nextLayer.shearY or nextFrame.shearY) * pos
    love.graphics.push()
    love.graphics.setColor(1, 1, 1, thisLayer.opacity)
    love.graphics.shear(shearX, shearY)
    love.graphics.draw(image, x, y, angle, scaleX, scaleY, w / 2, h / 2)
    love.graphics.pop()
  end
  love.graphics.setColor(r, g, b, a)
end

local function fromDirectory()
  -- TODO
end

return {
  decode = decode,
  easing = easing,
  fromDirectory = fromDirectory,
  Animation = Animation,
}
