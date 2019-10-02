local function __decode(lines)
  local line = table.remove(lines):gsub("^ *", "")
  local t = line:sub(1, 1)
  if t == "t" then
    local table = {}
    for _ = 1, tonumber(line:sub(2, -1)) do
      local k = __decode(lines, i)
      table[k] = __decode(lines, i)
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

return {
  decode = decode
}
