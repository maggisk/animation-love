local util = require "util"
local playback = require "playback"

local function locate(array, id)
  for i = 1, #array do
    if array[i].id == id then
      return array[i]
    end
  end
  assert(false)
end

local function encode(obj, buf, indent)
  local t = type(obj)
  if t == "table" then
    buf[#buf+1] = indent .. "t" .. util.count(obj)
    for k, v in pairs(obj) do
      encode(k, buf, indent .. "  ")
      encode(v, buf, indent .. "  ")
    end
  elseif t == "number" then
    buf[#buf+1] = indent .. "n" .. obj
  elseif t == "string" then
    assert(obj:find("\n") == nil, "can not encode strings with newline characters")
    buf[#buf+1] = indent .. "s" .. obj
  else
    error("can not encode type: " .. t)
  end
end

local Animation = util.Object:extend()
function Animation:new(state)
  self.images = {} -- love image objects
  self.blobs = {}  -- image binary strings

  -- json serializable state object
  self.state = state or {
    maxId = 1,
    layers = {},
    frames = {{id = 1, easing = 'linear', time = 0.3}},
    joints = {},
    framelayers = {{}},
    framejoints = {{}},
  }

  -- make it accessible on the animation object without using .state
  util.extend(self, self.state)
end

function Animation:nextId()
  self.state.maxId = self.state.maxId + 1
  return self.state.maxId
end

function Animation:newLayer(blob, imagepath)
  local layer = {}
  layer.id = self:nextId()
  local m = util.matchall(imagepath, "([^./\\]+)")
  layer.name = m[#m - 1]
  layer.ext = m[#m]

  table.insert(self.state.layers, layer)

  self.blobs[layer.id] = blob
  self.images[layer.id] = love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(blob, imagepath)))

  for _, frame in ipairs(self.state.frames) do
    self.state.framelayers[frame.id][layer.id] = {x = 0, y = 0, angle = 0}
  end

  return layer
end

function Animation:newFrame(source)
  source = source or self.state.frames[#self.state.frames]
  frame = util.extend({}, source)
  frame.id = self:nextId()
  table.insert(self.state.frames, frame)

  self.state.framelayers[frame.id] = {}
  for _, layer in ipairs(self.state.layers) do
    self.state.framelayers[frame.id][layer.id] = util.copy(self.state.framelayers[source.id][layer.id])
  end

  self.state.framejoints[frame.id] = {}
  for _, joint in ipairs(self.state.joints) do
    self.state.framejoints[frame.id][joint.id] = util.copy(self.state.framejoints[source.id][joint.id])
  end

  return frame
end

function Animation:tryDeleteFrame(frame)
  if #self.state.frames > 1 then
    local i = util.findIndex(self.state.frames, frame)
    table.remove(self.state.frames, i)
    self.state.framelayers[frame.id] = nil
    self.state.framejoints[frame.id] = nil
    return self.state.frames[i] or self.state.frames[#self.state.frames]
  end
end

function Animation:reader(frameId, type, typeId)
  assert(frameId)
  assert(typeId)
  local thisFrame = self.state['frame' .. type][frameId][typeId]
  local allFrames = locate(self.state[type], typeId)
  return setmetatable({}, {
    __index = function(_, k)
      return thisFrame[k] or allFrames[k]
    end
  })
end

function Animation:duration()
  local sum = 0
  for _, frame in ipairs(self.state.frames) do
    sum = sum + frame.time
  end
  return sum
end

function Animation:swap(type, item, direction)
  local i = util.findIndex(self.state[type], item)
  util.swapwrap(self.state[type], i, i + direction)
end

function Animation:adjustSpeed(percentage)
  for _, frame in ipairs(self.state.frames) do
    frame.time = frame.time + frame.time * percentage
  end
end

function Animation:encode()
  local buf = {}
  encode(self.state, buf, "")
  return table.concat(buf, "\n")
end

function Animation:save(savedir)
  savedir = savedir or "animation-love-" .. love.math.random(10000)
  if love.filesystem.getInfo(savedir) then
    for _, f in ipairs(love.filesystem.getDirectoryItems(savedir)) do
      love.filesystem.remove(savedir .. '/' .. f)
    end
  end
  love.filesystem.createDirectory(savedir)

  local success, message = love.filesystem.write(savedir .. "/animation.txt", self:encode())
  if not success then return message end

  for _, layer in ipairs(self.layers) do
    local success, message = love.filesystem.write(string.format("%s/%s.%s", savedir, layer.name, layer.ext), self.blobs[layer.id])
    if not success then return message end
  end

  love.system.openURL("file://" .. love.filesystem.getSaveDirectory() .. "/" .. savedir)
end

function Animation.load(savedir)
  local s, message = love.filesystem.read(savedir .. "/animation.txt")
  if not s then return message, nil end

  local animation = Animation(playback.decode(util.matchall(s, "([^\r\n]+)")))

  for i, layer in ipairs(animation.layers) do
    local path = string.format("%s/%s.%s", savedir, layer.name, layer.ext)
    local blob, message = love.filesystem.read(path)
    if not blob then return message, nil end
    animation.blobs[layer.id] = blob
    animation.images[layer.id] = love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(blob, path)))
  end

  return nil, animation
end

return Animation
