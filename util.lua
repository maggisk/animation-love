local module = {}

-- simple class support
module.Object = {}
local Object = module.Object
Object.__index = Object

function Object:new()
end

function Object:extend()
  local cls = {}
  for k, v in pairs(self) do
    if k:find("__") == 1 then
      cls[k] = v
    end
  end
  cls.__index = cls
  setmetatable(cls, self)
  return cls
end

function Object:__call(...)
  local obj = setmetatable({}, self)
  obj:new(...)
  return obj
end

-- font handling
local fonts = {}
function module.getFont(size)
  fonts[size] = fonts[size] or love.graphics.newFont("resources/AlegreyaSans-Regular.ttf", size)
  return fonts[size]
end

function module.remap(value, minValue, maxValue, minReturn, maxReturn)
  return minReturn + (maxReturn - minReturn) * ((value - minValue) / (maxValue - minValue))
end

function module.copy(orig)
  local copy = {}
  if getmetatable(orig) then
    setmetatable(copy, getmetatable(orig))
  end
  for k, v in pairs(orig) do
    if type(v) == "table" then
      v = module.copy(v)
    end
    copy[k] = v
  end
  return copy
end

function module.findIndex(ys, x)
  for i, y in ipairs(ys) do
    if x == y then
      return i
    end
  end
end

function module.matchall(s, pattern)
  local parts = {}
  for match in s:gmatch(pattern) do
    table.insert(parts, match)
  end
  return parts
end

function module.shortestRotation(a1, a2)
  local angle = a2 - a1
  if angle > math.pi then
    angle = angle - 2 * math.pi
  elseif angle < -math.pi then
    angle = angle + 2 * math.pi
  end
  return a1, angle
end

function module.last(t)
  return t[#t]
end

function module.getFileInfo(fullPath)
  local fullname = module.last(module.matchall(fullPath, "([^/\\]+)"))
  local dotseparated = module.matchall(fullname, "([^\\.]+)")
  local ext = table.remove(dotseparated)
  return {fullname = fullname, ext = ext, filename = table.concat(dotseparated, ".")}
end

function module.swapwrap(t, i, j)
  i = ((i - 1 + #t) % #t) + 1
  j = ((j - 1 + #t) % #t) + 1
  t[i], t[j] = t[j], t[i]
end

local solidColor = love.graphics.newShader [[
  extern float r, g, b, a, threshold;
  vec4 effect(vec4 col, Image tex, vec2 texcoord, vec2 screencoord) {
    vec4 c = Texel(tex, texcoord.xy);
    if (c.r + c.g + c.b > threshold && c.a > threshold) {
      return vec4(r, g, b, a);
    }
    return vec4(0.0);
  }
]]

solidColor:send('threshold', 0.1)

function module.solidColorShader(r, g, b, a)
  solidColor:send('r', r)
  solidColor:send('g', g)
  solidColor:send('b', b)
  solidColor:send('a', a or 1)
  return solidColor
end

function module.extend(table, ...)
  for _, other in ipairs({...}) do
    for k, v in pairs(other) do
      table[k] = v
    end
  end
  return table
end

-- easing functions
module.easings = {}
function module.easings.linear(t)
  return t
end
function module.easings.easeIn(t)
  return t*t
end
function module.easings.easeOut(t)
  t = t - 1
  return 1-(t*t)
end

return module
