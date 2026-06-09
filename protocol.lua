-- Minimal newline-delimited JSON codec for duel sync messages.

local protocol = {}

local function escape_str(s)
  return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

local function encode_value(v)
  local t = type(v)
  if t == "string" then
    return escape_str(v)
  elseif t == "number" then
    return tostring(v)
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "table" then
    if v[1] ~= nil then
      local parts = {}
      for i = 1, #v do
        parts[#parts + 1] = encode_value(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end

    local parts = {}
    for k, val in pairs(v) do
      parts[#parts + 1] = escape_str(k) .. ":" .. encode_value(val)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end

  return "null"
end

function protocol.encode(msg)
  return encode_value(msg)
end

local function skip_ws(s, i)
  while i <= #s do
    local c = s:sub(i, i)
    if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then
      break
    end
    i = i + 1
  end
  return i
end

local function parse_value(s, i)
  i = skip_ws(s, i)

  local c = s:sub(i, i)
  if c == '"' then
    local j = i + 1
    local out = {}
    while j <= #s do
      local ch = s:sub(j, j)
      if ch == '"' then
        return table.concat(out), j + 1
      elseif ch == "\\" then
        j = j + 1
        out[#out + 1] = s:sub(j, j)
        j = j + 1
      else
        out[#out + 1] = ch
        j = j + 1
      end
    end
    return nil, i
  end

  if c == "{" then
    local obj = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == "}" then
      return obj, i + 1
    end

    while i <= #s do
      local key
      key, i = parse_value(s, i)
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then
        return nil, i
      end
      i = i + 1
      local val
      val, i = parse_value(s, i)
      obj[key] = val
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == "}" then
        return obj, i + 1
      elseif sep == "," then
        i = i + 1
      else
        return nil, i
      end
    end
    return nil, i
  end

  if c == "[" then
    local arr = {}
    i = i + 1
    i = skip_ws(s, i)
    if s:sub(i, i) == "]" then
      return arr, i + 1
    end

    while i <= #s do
      local val
      val, i = parse_value(s, i)
      arr[#arr + 1] = val
      i = skip_ws(s, i)
      local sep = s:sub(i, i)
      if sep == "]" then
        return arr, i + 1
      elseif sep == "," then
        i = i + 1
      else
        return nil, i
      end
    end
    return nil, i
  end

  if s:sub(i, i + 3) == "true" then
    return true, i + 4
  end
  if s:sub(i, i + 4) == "false" then
    return false, i + 5
  end
  if s:sub(i, i + 3) == "null" then
    return nil, i + 4
  end

  local j = i
  while j <= #s do
    local ch = s:sub(j, j)
    if not ch:match("[%d%.%-eE%+]") then
      break
    end
    j = j + 1
  end

  if j > i then
    return tonumber(s:sub(i, j - 1)), j
  end

  return nil, i
end

function protocol.decode(line)
  if not line or line == "" then
    return nil
  end

  local value, i = parse_value(line, 1)
  if value == nil and line:sub(1, 1) ~= "{" and line:sub(1, 1) ~= "[" then
    return nil
  end

  return value
end

protocol.TM_PREFIX = "TM/"
protocol.DEFAULT_PORT = 19876
protocol.IPC_PREFIX = "tetramaster|"

function protocol.format_handshake(kind, ...)
  local parts = { kind }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  return protocol.TM_PREFIX .. table.concat(parts, "/")
end

function protocol.format_ipc(kind, ...)
  local parts = { "tetramaster", kind }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  return table.concat(parts, "|")
end

function protocol.parse_handshake(text)
  if not text then
    return nil
  end

  text = text:gsub("^%b() %s*", "")

  local legacy = text:match("<<TM:([^>]+)>>")
  if legacy then
    text = "TM/" .. legacy:gsub(":", "/")
  end

  if text:sub(1, #protocol.TM_PREFIX) ~= protocol.TM_PREFIX then
    return nil
  end

  local body = text:sub(#protocol.TM_PREFIX + 1)
  local parts = {}
  for part in body:gmatch("[^/]+") do
    parts[#parts + 1] = part
  end

  if #parts == 0 then
    return nil
  end

  return {
    kind = parts[1],
    session = parts[2],
    arg1 = parts[3],
    arg2 = parts[4],
    arg3 = parts[5],
  }
end

function protocol.parse_ipc(text)
  if not text or text:sub(1, #protocol.IPC_PREFIX) ~= protocol.IPC_PREFIX then
    return nil
  end

  local parts = {}
  for part in text:gmatch("([^|]+)") do
    parts[#parts + 1] = part
  end

  if #parts < 2 or parts[1] ~= "tetramaster" then
    return nil
  end

  return {
    kind = parts[2],
    session = parts[3],
    arg1 = parts[4],
    arg2 = parts[5],
    arg3 = parts[6],
  }
end

function protocol.parse_friendly_challenge(text)
  if not text then
    return nil
  end

  text = text:gsub("^%b() %s*", "")
  local challenger, guest = text:match("([%w]+) challenges ([%w]+) to a TetraMaster duel!")
  if challenger and guest then
    return challenger, guest
  end

  return nil
end

function protocol.make_session_id(name_a, name_b)
  if name_a:lower() < name_b:lower() then
    return name_a .. "_" .. name_b
  end
  return name_b .. "_" .. name_a
end

return protocol
