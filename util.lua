local util = {}

-- font handling
local fonts = {}
function util.getFont(size)
  assert(type(size) == "number")
  fonts[size] = fonts[size] or love.graphics.newFont("resources/AlegreyaSans-Regular.ttf", size)
  return fonts[size]
end

function util.keys(table)
  local keys = {}
  for k, _ in pairs(table) do
    keys[#keys+1] = k
  end
  return keys
end

function util.clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

function util.remap(value, minValue, maxValue, minReturn, maxReturn)
  return minReturn + (maxReturn - minReturn) * ((value - minValue) / (maxValue - minValue))
end

function util.count(table)
  local c = 0
  for _ in pairs(table) do c = c + 1 end
  return c
end

function util.copy(orig)
  local copy = {}
  if getmetatable(orig) then
    setmetatable(copy, getmetatable(orig))
  end
  for k, v in pairs(orig) do
    if type(v) == "table" then
      v = util.copy(v)
    end
    copy[k] = v
  end
  return copy
end

function util.indexOf(ys, x)
  for i, y in ipairs(ys) do
    if x == y then
      return i
    end
  end
end

function util.find(t, cb)
  for i, v in ipairs(t) do
    if cb(v, i) then
      return v
    end
  end
end

function util.matchall(s, pattern)
  local parts = {}
  for match in s:gmatch(pattern) do
    table.insert(parts, match)
  end
  return parts
end

function util.shortestRotation(a1, a2)
  local angle = a2 - a1
  if angle > math.pi then
    angle = angle - 2 * math.pi
  elseif angle < -math.pi then
    angle = angle + 2 * math.pi
  end
  return a1, angle
end

function util.last(t)
  return t[#t]
end

function util.swapwrap(t, i, j)
  i = ((i - 1 + #t) % #t) + 1
  j = ((j - 1 + #t) % #t) + 1
  t[i], t[j] = t[j], t[i]
end

function util.extend(table, ...)
  for _, other in ipairs({...}) do
    for k, v in pairs(other) do
      table[k] = v
    end
  end
  return table
end

local function pprint(obj, indent, prefix)
  if type(obj) == "table" then
    io.write(string.format("%s%stable=%s, size=%s, metatable=%s\n",
      indent, prefix, obj, util.count(obj), getmetatable(obj)))
    for k, v in pairs(obj) do
      pprint(k, '  ' .. indent, "key: ")
      pprint(v, '  ' .. indent, "value: ")
    end
  else
    io.write(string.format("%s%s%s (%s)\n", indent, prefix, obj, type(obj)))
  end
end

function util.pprint(...)
  for _, obj in ipairs({...}) do
    pprint(obj, "", "")
  end
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

function util.solidColorShader(r, g, b, a)
  solidColor:send('r', r)
  solidColor:send('g', g)
  solidColor:send('b', b)
  solidColor:send('a', a or 1)
  return solidColor
end

return util
