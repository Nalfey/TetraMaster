local protocol = require("protocol")

local bridge = {
  inbox_path = nil,
  outbox_path = nil,
  heartbeat_path = nil,
  inbox_offset = 0,
  enabled = false,
  last_heartbeat = 0,
}

function bridge.init(sync_dir)
  if not sync_dir then
    bridge.enabled = false
    return false
  end

  bridge.inbox_path = sync_dir .. "/inbox.txt"
  bridge.outbox_path = sync_dir .. "/outbox.txt"
  bridge.heartbeat_path = sync_dir .. "/heartbeat.txt"
  bridge.inbox_offset = 0
  bridge.last_heartbeat = 0
  bridge.enabled = true
  return true
end

function bridge.is_enabled()
  return bridge.enabled
end

local function read_new_lines(path, offset)
  local file = io.open(path, "r")
  if not file then
    return {}, offset
  end

  file:seek("set", offset)
  local chunk = file:read("*a") or ""
  file:close()

  if chunk == "" then
    return {}, offset
  end

  local lines = {}
  for line in chunk:gmatch("[^\r\n]+") do
    if line ~= "" then
      lines[#lines + 1] = line
    end
  end

  return lines, offset + #chunk
end

local function append_line(path, line)
  local file = io.open(path, "a")
  if not file then
    return false
  end
  file:write(line .. "\n")
  file:close()
  return true
end

function bridge.poll()
  if not bridge.enabled then
    return {}
  end

  local lines, new_offset = read_new_lines(bridge.inbox_path, bridge.inbox_offset)
  bridge.inbox_offset = new_offset

  local messages = {}
  for _, line in ipairs(lines) do
    local msg = protocol.decode(line)
    if msg then
      messages[#messages + 1] = msg
    end
  end

  return messages
end

function bridge.send(msg)
  if not bridge.enabled then
    return false
  end

  return append_line(bridge.outbox_path, protocol.encode(msg))
end

function bridge.write_heartbeat()
  if not bridge.enabled or not bridge.heartbeat_path then
    return
  end

  local now = os.time()
  if now == bridge.last_heartbeat then
    return
  end

  bridge.last_heartbeat = now
  local file = io.open(bridge.heartbeat_path, "w")
  if file then
    file:write(tostring(now))
    file:close()
  end
end

function bridge.clear_heartbeat()
  if bridge.heartbeat_path then
    os.remove(bridge.heartbeat_path)
  end
  bridge.last_heartbeat = 0
end

function bridge.write_closed_flag()
  if not bridge.enabled then
    return
  end

  local closed_path = bridge.heartbeat_path and bridge.heartbeat_path:gsub("heartbeat%.txt", "closed.flag")
  if not closed_path then
    return
  end

  local file = io.open(closed_path, "w")
  if file then
    file:write("1")
    file:close()
  end
end

return bridge
