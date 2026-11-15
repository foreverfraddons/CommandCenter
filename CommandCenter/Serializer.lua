-- Compact, chat-safe serializer for addon messages.
local _, S = ...
local Ser = {}
S.Ser = Ser

local format, byte, char, tostring, tonumber, type = string.format, string.byte, string.char, tostring, tonumber, type

local function esc(s)
  return (s:gsub("[%c|~%^]", function(c) return format("~%02x", byte(c)) end))
end
local function unesc(s)
  return (s:gsub("~(%x%x)", function(h) return char(tonumber(h, 16)) end))
end

local function ser(v, out)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = "S" .. esc(v) .. "^"
  elseif t == "number" then
    if v == math.floor(v) and math.abs(v) < 2^53 then
      out[#out + 1] = format("N%d^", v)
    else
      out[#out + 1] = "N" .. format("%.10g", v) .. "^"
    end
  elseif t == "boolean" then
    out[#out + 1] = v and "B" or "b"
  elseif t == "table" then
    out[#out + 1] = "T"
    for k, val in pairs(v) do
      local kt = type(k)
      if (kt == "string" or kt == "number") and val ~= nil and type(val) ~= "function" then
        ser(k, out)
        ser(val, out)
      end
    end
    out[#out + 1] = "t"
  else
    out[#out + 1] = "b" -- unsupported -> false
  end
end

function Ser.Serialize(v)
  local out = {}
  ser(v, out)
  return table.concat(out)
end

local function parse(s, i)
  local c = s:sub(i, i)
  if c == "S" then
    local j = s:find("^", i + 1, true)
    if not j then error("truncated string") end
    return unesc(s:sub(i + 1, j - 1)), j + 1
  elseif c == "N" then
    local j = s:find("^", i + 1, true)
    if not j then error("truncated number") end
    return tonumber(s:sub(i + 1, j - 1)), j + 1
  elseif c == "B" then
    return true, i + 1
  elseif c == "b" then
    return false, i + 1
  elseif c == "T" then
    local t = {}
    i = i + 1
    local len = #s
    while true do
      if i > len then error("truncated table") end
      if s:sub(i, i) == "t" then return t, i + 1 end
      local k, v
      k, i = parse(s, i)
      v, i = parse(s, i)
      if k ~= nil then t[k] = v end
    end
  end
  error("bad token '" .. tostring(c) .. "' at " .. i)
end

function Ser.Deserialize(s)
  if type(s) ~= "string" or s == "" then return nil end
  local ok, v = pcall(parse, s, 1)
  if ok then return v end
  return nil, v
end
