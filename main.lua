local json = require "json"
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
state.zoom = 1
state.playing = false
state.duration = 0
state.timePerFrame = 0.3
state.layers = {}
state.frames = {}
state.showEasingPicker = false
state.ui = ui.Area()

-- a layer in animation (an image)
local Layer = util.Object:extend()
function Layer:new(imageData, rawData, fileData)
  self.x, self.y = 0, 0
  self.imageData = imageData
  self.rawData = rawData
  self.fileData = fileData
  self.image = love.graphics.newImage(imageData)
  self.orientation = 0
end

-- a frame in the animation
local Frame = util.Object:extend()
function Frame:new(data)
  self.data = data or {}
  self.easing = "linear"
end

function Frame:get(layer, name, default)
  self.data[layer] = self.data[layer] or {}
  return self.data[layer][name] or default
end

function Frame:set(layer, name, v)
  self.data[layer] = self.data[layer] or {}
  self.data[layer][name] = v
end

function Frame:rotate(layer, x, y)
  local lx = self:get(layer, 'x', 0)
  local ly = self:get(layer, 'y', 0)
  self:set(layer, 'orientation', self.start.orientation + math.atan2(ly - y, lx - x) - math.atan2(ly - self.start.y, lx - self.start.x))
end

function Frame:startRotation(layer, x, y)
  self.start = {x = x, y = y, orientation = self:get(layer, 'orientation', 0)}
end

-- create initial frame
local firstFrame = Frame()
table.insert(state.frames, firstFrame)
state.currentFrame = firstFrame

-- save animation to disk
local function saveToDisk()
  local savedir = "joints-save-" .. love.math.random(10000)
  if love.filesystem.getInfo(savedir) then
    for _, f in ipairs(love.filesystem.getDirectoryItems(savedir)) do
      love.filesystem.remove(savedir .. '/' .. f)
    end
  end
  love.filesystem.createDirectory(savedir)

  local data = {version = 1, timePerFrame = state.timePerFrame, frames = {}, layers = {}}

  for i, frame in ipairs(state.frames) do
    data.frames[i] = {}
    for j, layer in ipairs(state.layers) do
      data.frames[i][j] = {
        x = frame:get(layer, 'x', 0),
        y = frame:get(layer, 'y', 0),
        orientation = frame:get(layer, 'orientation', 0),
      }
    end
  end

  for i, layer in ipairs(state.layers) do
    data.layers[i] = {
      fileData = layer.fileData
    }
  end

  local success, message = love.filesystem.write(savedir .. "/data.json", json.encode(data))
  if not success then return message end

  for _, layer in ipairs(state.layers) do
    local success, message = love.filesystem.write(savedir .. "/" .. layer.fileData.fullname, layer.rawData)
    if not success then return message end
  end

  love.system.openURL("file://" .. love.filesystem.getSaveDirectory() .. "/" .. savedir)
end

-- load back previously saved animation
local function loadFromDisk(savedir)
  local s, message = love.filesystem.read(savedir .. "/data.json")
  if not s then return message end
  local data = json.decode(s)

  state.timePerFrame = data.timePerFrame
  state.frames = {}
  state.layers = {}

  for i, layer in ipairs(data.layers) do
    local rawData, message = love.filesystem.read(savedir .. "/" .. layer.fileData.fullname)
    if not rawData then return message end
    local imageData = love.image.newImageData(love.filesystem.newFileData(rawData, layer.fileData.fullname))
    table.insert(state.layers, Layer(imageData, rawData, layer.fileData))
  end

  for i, frameData in ipairs(data.frames) do
    local frame = Frame()
    for j, layer in ipairs(state.layers) do
      for k, v in pairs(frameData[j]) do
        frame:set(layer, k, v)
      end
    end
    table.insert(state.frames, frame)
  end

  state.currentLayer = state.layers[1]
  state.currentFrame = state.frames[1]
end

-- utility functions
local function elapsedPercentage(fdiff)
  local total = (#state.frames + (fdiff or 0)) * state.timePerFrame
  return (state.duration % total) / total
end

local function adjustLayerPos(x, y)
  local f = state.currentFrame
  local layer = state.currentLayer
  if f and layer then
    f:set(layer, 'x', f:get(layer, 'x', 0) + x)
    f:set(layer, 'y', f:get(layer, 'y', 0) + y)
  end
end

local function addNewFrame()
  local frame = util.copy(state.currentFrame)
  table.insert(state.frames, util.findIndex(state.frames, state.currentFrame) + 1, frame)
  state.currentFrame = frame
end

local function newButton(parent, options)
  return ui.Button(parent, util.extend({theme = colors.button}, options))
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
local function setTab(tab) state.menu = tab end
local fileTab = newButton(header, {text = "File"}):on('mousepressed', setTab)
local editTab = newButton(header, {text = "Edit"}):on('mousepressed', setTab)
local layerTab = newButton(header, {text = "Layer"}):on('mousepressed', setTab)
local frameTab = newButton(header, {text = "Frame"}):on('mousepressed', setTab)
local mainTabs = {fileTab, editTab, layerTab, frameTab}
state.menu = fileTab

-- file subtabs
newButton(fileTab, {text = "Save"}):on('mousepressed', function() state.error = saveToDisk() end)

-- edit subtabs
newButton(editTab, {text = 'Undo'})
newButton(editTab, {text = 'Redo'})

-- TODO: layer subtabs - delete etc.

-- frame subtabs
function setEasing(tab) state.currentFrame.easing = tab.id end
local easingButton = newButton(frameTab, {text = 'linear speed'}):on('mousepressed', function() state.showEasingPicker = true end)
newButton(frameTab, {text = 'move left'}):on('mousepressed', function()
  local i = util.findIndex(state.frames, state.currentFrame)
  util.swapwrap(state.frames, i, i - 1)
end)
newButton(frameTab, {text = 'move right'}):on('mousepressed', function()
  local i = util.findIndex(state.frames, state.currentFrame)
  util.swapwrap(state.frames, i, i + 1)
end)
newButton(frameTab, {text = 'add'}):on('mousepressed', addNewFrame)
newButton(frameTab, {text = 'delete'}):on('mousepressed', function()
  if #state.frames > 1 then
    local i = util.findIndex(state.frames, state.currentFrame)
    table.remove(state.frames, i)
    state.currentFrame = state.frames[i] or state.frames[#state.frames]
  end
end)

local function changeLayerPriority(direction)
  if #state.layers >= 2 then
    local from = util.findIndex(state.layers, state.currentLayer)
    local to = math.max(1, math.min(#state.layers, from + direction))
    state.layers[from], state.layers[to] = state.layers[to], state.layers[from]
  end
end

-- layer up/down buttons
local layerUp = newButton(state.ui, {text = "up", align = "center"}):on('mousepressed', function() changeLayerPriority(-1) end)
local layerDown = newButton(state.ui, {text = "down", align = "center"}):on('mousepressed', function() changeLayerPriority(1) end)

-- change speed
local faster = newButton(header, {text = "-"}):on('mousepressed', function() state.timePerFrame = state.timePerFrame - 0.02 end)
local slower = newButton(header, {text = "+"}):on('mousepressed', function() state.timePerFrame = state.timePerFrame + 0.02 end)
local showSpeed = newButton(header)

-- big button to add new frame
local newFrameButton = ui.Rectangle(state.ui):on('mousepressed', addNewFrame)

-- error message
local errorMessage = newButton(state.ui):on('mousepressed', function() state.error = nil end)

local ew = ui.Rectangle(state.ui):on('mousepressed', function() state.showEasingPicker = false end)
local function setEasingFunc(button) state.currentFrame.easing = button.easing end
ui.Rectangle(ew, {easing = "linear"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeIn"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeInx2"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeOut"}):on('mousepressed', setEasingFunc)
ui.Rectangle(ew, {easing = "easeOutx2"}):on('mousepressed', setEasingFunc)

-- drawing functions
local draw = {}

function draw.frame(f)
  if f then
    for i = #state.layers, 1, -1 do
      local layer = state.layers[i]
      love.graphics.draw(layer.image, f:get(layer, 'x', 0), f:get(layer, 'y', 0), f:get(layer, 'orientation', 0), 1, 1,
        layer.image:getWidth() / 2, layer.image:getHeight() / 2)
    end
  end
end

function draw.exactFrame(f1, f2, elapsed, framepos)
  if f1 and f2 then
    local pos = util.easings[f1.easing](framepos)
    for i = #state.layers, 1, -1 do
      local layer = state.layers[i]
      local x = f1:get(layer, 'x', 0) * (1 - pos) + f2:get(layer, 'x', 0) * pos
      local y = f1:get(layer, 'y', 0) * (1 - pos) + f2:get(layer, 'y', 0) * pos
      local start, distance = util.shortestRotation(f1:get(layer, 'orientation', 0), f2:get(layer, 'orientation', 0))
      local orientation = start + distance * framepos
      love.graphics.draw(layer.image, x, y, orientation, 1, 1, layer.image:getWidth() / 2, layer.image:getHeight() / 2)
    end
  end
end

function draw.animationArea()
  -- draw background
  animationArea:gotoPosition()
  animationArea:draw({
    width = layout.window.width - layout.sidebar.width,
    height = layout.window.height - layout.header.height - layout.footer.height,
  })

  animationArea:gotoPosition(animationArea.w / 2, animationArea.h / 2)

  if state.playing then
    local total = #state.frames * state.timePerFrame
    local elapsed = util.remap(state.duration % total, 0, total, 1, #state.frames)
    local f1 = state.frames[math.floor(elapsed)]
    local f2 = state.frames[math.ceil(elapsed)]
    draw.exactFrame(f1, f2, (state.duration % total) / total, elapsed % 1)
  else
    local i = util.findIndex(state.frames, state.currentFrame)

    -- draw shadow of frame before this one
    love.graphics.setShader(util.solidColorShader(0, 0, 1, 0.15))
    draw.frame(state.frames[i - 1])

    -- draw shadow of the frame after this one
    love.graphics.setShader(util.solidColorShader(0, 1, 0, 0.15))
    draw.frame(state.frames[i + 1])

    -- and the current frame
    love.graphics.setShader()
    draw.frame(state.frames[i])
  end
end

function draw.sidebar()
  sidebar:gotoPosition()
  for i, layer in ipairs(state.layers) do
    -- get or create button for this layer
    if not sidebar.children[i] then
      sidebar.children[i] = newButton(sidebar):on('mousepressed', function()
        state.currentLayer = state.layers[i]
      end)
    end
    button = sidebar.children[i]

    -- draw it
    button:draw({fontSize = 20, text = layer.fileData.filename, width = layout.sidebar.width, selected = (layer == state.currentLayer)})
          :layout(ui.down)
  end

  -- buttons to move layer up or down
  layerUp:draw({width = layout.sidebar.width / 2, align = "center"}):layout(ui.right)
  layerDown:draw({width = layout.sidebar.width / 2}):layout(ui.right)
end

function draw.header()
  local h = 30 -- tab height
  local hr = 3 -- horizontal separator

  -- main tabs
  header:gotoPosition(layout.sidebar.width, layout.header.height - h * 2 - hr)
  for _, tab in ipairs(mainTabs) do
    tab:draw({fontSize = 22, align = "left", width = 100, height = h, selected = (tab == state.menu)}):layout(ui.right)
  end

  -- subtabs
  easingButton.text = state.currentFrame.easing
  header:gotoPosition(layout.sidebar.width, layout.header.height - h)
  for _, tab in ipairs(state.menu.children) do
    tab:draw({height = h, selected = (tab.id == state.currentFrame.easing)}):layout(ui.right)
  end

  -- show total animation time
  header:gotoPosition(layout.window.width - 160, layout.header.height - h * 2 - hr)
  showSpeed:draw({width=100, height=30, text = 'Time: ' .. tostring(state.timePerFrame * #state.frames):sub(1, 4) .. 's'}):layout(ui.right)
  slower:draw({width=30, height=30, align = "center"}):layout(ui.right)
  faster:draw({width=30, height=30, align = "center"}):layout(ui.right)

  -- a pretty line/separator
  header:gotoPosition()
  love.graphics.setColor(colors.button.selected.background)
  love.graphics.rectangle("fill", 0, layout.header.height - h - hr, layout.window.width, 3)
end

function draw.footer()
  footer.y = layout.window.height - layout.footer.height

  -- play/pause button
  local r = 25
  footer:gotoPosition(layout.sidebar.width / 2, layout.footer.height / 2)
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
  footer:gotoPosition(layout.sidebar.width, pad)
  for i, frame in ipairs(state.frames) do
    -- border around the selected frame
    if frame == state.currentFrame then
      love.graphics.setColor(colors.button.selected.background)
      love.graphics.rectangle("fill", -2, -2, size+4, size+4)
    end

    -- get or create ui rectangle for frame
    if not footer.children[i] then
      footer.children[i] = ui.Rectangle(footer):on('mousepressed', function()
        state.currentFrame = state.frames[i]
      end)
    end
    local rect = footer.children[i]

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
    footer:gotoPosition(layout.sidebar.width)
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.rectangle("fill", ((size + pad) * #state.frames - pad * 2) * elapsedPercentage(), 0, 2, size + pad * 2)
  end

  -- add new frame button
  footer:gotoPosition(layout.window.width - size / 2 - pad, pad)
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
  ew:gotoPosition(wpad, wpad)

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

function love.load()
  love.graphics.setBackgroundColor(colors.background)
  love.window.setMode(layout.window.width, layout.window.height, {resizable = true, minwidth = 800, minheight = 600})
end

function love.draw()
  love.graphics.clear(colors.background)
  state.ui:updateAll({visible = false})

  for _, name in ipairs({"header", "footer", "sidebar", "animationArea", "easingPicker"}) do
    love.graphics.reset()
    love.graphics.origin()
    draw[name]()
  end
end

function love.update(dt)
  state.duration = state.duration + dt
  -- TODO: loop or no loop?
  if state.duration > state.timePerFrame * #state.frames then
    state.playing = false
  end
  -- TODO: limit framerate when not playing animation?
end

function love.filedropped(file)
  -- accept new images when dropped
  local rawData = file:read()
  file:seek(0)
  local imageData = love.image.newImageData(file)
  local fileData = util.getFileInfo(file:getFilename())
  local layer = Layer(imageData, rawData, fileData)
  table.insert(state.layers, layer)
  state.currentLayer = state.currentLayer or layer
end

function love.directorydropped(dir)
  -- load previously saved project
  love.filesystem.mount(dir, "loading")
  state.error = loadFromDisk("loading")
  print(state.error)
  love.filesystem.unmount("loading")
end

function love.mousepressed(x, y, button)
  state.ui:handleEvent('mousepressed', {x = x, y = y})

  if button == 2 and state.currentLayer then
    local ax, ay = animationArea:getCenter()
    state.currentFrame:startRotation(state.currentLayer, x - ax, y - ay)
  end
end

function love.mousemoved(x, y, dx, dy, istouch)
  state.ui:setHoverState(x, y)

  local frame = state.currentFrame
  local layer = state.currentLayer
  if layer and love.mouse.isDown(1) then
    -- drag layer around with left mouse button
    frame:set(layer, 'x', frame:get(layer, 'x', 0) + dx)
    frame:set(layer, 'y', frame:get(layer, 'y', 0) + dy)
  elseif layer and love.mouse.isDown(2) then
    -- rotate layer with right mouse button
    local ax, ay = animationArea:getCenter()
    frame:rotate(state.currentLayer, x - ax, y - ay)
  end
end

function love.keypressed(key, keycode, isrepeat)
  -- adjust layer position with arrow keys
  if key == "left"  then adjustLayerPos(-1, 0) end
  if key == "right" then adjustLayerPos(1, 0)  end
  if key == "up"    then adjustLayerPos(0, -1) end
  if key == "down"  then adjustLayerPos(0, 1)  end
end

function love.resize(w, h)
  layout.window.width = w
  layout.window.height = h
end
