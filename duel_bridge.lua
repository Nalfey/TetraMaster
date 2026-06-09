-- Windower-side TCP bridge between remote peer and local LOVE client.

local socket = require("socket")
local protocol = dofile(windower.addon_path .. "protocol.lua")

local bridge = {
  active = false,
  winding_down = false,
  winding_reason = nil,
  role = nil,
  session_id = nil,
  local_name = nil,
  sync_dir = nil,
  inbox_path = nil,
  outbox_path = nil,
  heartbeat_path = nil,
  closed_flag_path = nil,
  inbox_offset = 0,
  outbox_offset = 0,
  server = nil,
  client = nil,
  recv_buffer = "",
  peer_name = nil,
  connect_host = nil,
  connect_port = nil,
  connected_announced = false,
  game_launched = false,
  launch_time = nil,
  nudge_counter = 0,
  last_tcp_ping = 0,
  on_session_end = nil,
}

local HEARTBEAT_TIMEOUT = 30
local LAUNCH_GRACE = 15
local QUIT_NUDGE_INTERVAL = 30
local TCP_KEEPALIVE_INTERVAL = 15
local MAX_GAME_INSTANCES = 2

local function chat(msg)
  windower.add_to_chat(207, "TetraMaster: " .. msg)
end

local function ensure_dir(path)
  os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
end

local function count_running_games()
  local handle = io.popen('tasklist /FI "IMAGENAME eq TetraMaster.exe" /NH 2>nul')
  if not handle then
    return 0
  end

  local count = 0
  for line in handle:lines() do
    if line:lower():find("tetramaster.exe", 1, true) then
      count = count + 1
    end
  end

  handle:close()
  return count
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

local function reset_sync_files()
  ensure_dir(bridge.sync_dir)

  local inbox = io.open(bridge.inbox_path, "w")
  if inbox then
    inbox:close()
  end

  local outbox = io.open(bridge.outbox_path, "w")
  if outbox then
    outbox:close()
  end

  if bridge.closed_flag_path and windower.file_exists(bridge.closed_flag_path) then
    os.remove(bridge.closed_flag_path)
  end

  bridge.inbox_offset = 0
  bridge.outbox_offset = 0
end

local function send_tcp(msg)
  if not bridge.client then
    return false
  end

  local line = protocol.encode(msg) .. "\n"
  local ok, err = bridge.client:send(line)
  return ok, err
end

local function queue_to_game(msg)
  append_line(bridge.inbox_path, protocol.encode(msg))
end

local function send_ipc_resign()
  if bridge.session_id and bridge.local_name then
    windower.send_ipc_message(protocol.format_ipc("RESIGN", bridge.session_id, bridge.local_name))
  end
end

local function close_tcp()
  if bridge.client then
    bridge.client:close()
    bridge.client = nil
  end

  if bridge.server then
    bridge.server:close()
    bridge.server = nil
  end
end

function bridge.set_session_end_handler(handler)
  bridge.on_session_end = handler
end

function bridge.is_active()
  return bridge.active or bridge.winding_down
end

function bridge.complete_shutdown(reason, silent)
  close_tcp()

  bridge.active = false
  bridge.winding_down = false
  bridge.winding_reason = nil
  bridge.game_launched = false
  bridge.launch_time = nil
  bridge.nudge_counter = 0
  bridge.last_tcp_ping = 0
  bridge.role = nil
  bridge.session_id = nil
  bridge.local_name = nil
  bridge.peer_name = nil
  bridge.connected_announced = false

  if bridge.on_session_end and not silent then
    bridge.on_session_end(reason)
  end
end

local function begin_wind_down(reason)
  bridge.active = false
  bridge.winding_down = true
  bridge.winding_reason = reason
  bridge.nudge_counter = 0
end

local function end_duel(reason)
  if bridge.client then
    send_tcp({ type = "disconnect", reason = reason })
  end

  send_ipc_resign()
  queue_to_game({ type = "disconnect", reason = reason })
  close_tcp()
  begin_wind_down(reason)
end

local function end_duel_for_opponent(reason)
  queue_to_game({ type = "disconnect", reason = reason })
  close_tcp()
  begin_wind_down(reason)
end

function bridge.shutdown(reason)
  reason = reason or "stop"

  if reason == "restart" or reason == "stop" or reason == "launch_failed" then
    bridge.complete_shutdown(reason, true)
    return
  end

  if reason == "opponent_left" or reason == "connection_closed" then
    chat("opponent left the duel.")
    end_duel_for_opponent(reason)
    return
  end

  if reason == "local_quit" or reason == "manual_resign" or reason == "game_closed" then
    if reason == "game_closed" or reason == "local_quit" then
      chat("TetraMaster window closed. Ending duel session.")
    end
    end_duel(reason)
    return
  end
end

function bridge.stop(reason)
  bridge.shutdown(reason or "stop")
end

local function set_sync_paths(session_id, local_name)
  bridge.sync_dir = windower.addon_path .. "sync\\" .. session_id .. "\\" .. local_name
  bridge.inbox_path = bridge.sync_dir .. "\\inbox.txt"
  bridge.outbox_path = bridge.sync_dir .. "\\outbox.txt"
  bridge.heartbeat_path = bridge.sync_dir .. "\\heartbeat.txt"
  bridge.closed_flag_path = bridge.sync_dir .. "\\closed.flag"
end

local function within_launch_grace()
  return bridge.launch_time and (os.time() - bridge.launch_time) < LAUNCH_GRACE
end

local function read_heartbeat_age()
  local file = io.open(bridge.heartbeat_path, "r")
  if not file then
    return nil
  end

  local value = tonumber(file:read("*a"))
  file:close()

  if not value then
    return nil
  end

  return os.time() - value
end

local function game_process_alive()
  if within_launch_grace() then
    return true
  end

  local age = read_heartbeat_age()
  return age ~= nil and age <= HEARTBEAT_TIMEOUT
end

local function check_closed_flag()
  if not bridge.closed_flag_path or not windower.file_exists(bridge.closed_flag_path) then
    return
  end

  if within_launch_grace() then
    return
  end

  os.remove(bridge.closed_flag_path)

  if bridge.active or bridge.game_launched or bridge.winding_down then
    bridge.shutdown("game_closed")
  end
end

local function tick_wind_down()
  bridge.nudge_counter = bridge.nudge_counter + 1

  if bridge.nudge_counter % QUIT_NUDGE_INTERVAL == 0 then
    queue_to_game({ type = "disconnect", reason = bridge.winding_reason or "session_ended" })
  end

  if not game_process_alive() then
    bridge.complete_shutdown(bridge.winding_reason or "session_ended")
  end
end

local function check_game_heartbeat()
  if not bridge.active or not bridge.game_launched then
    return
  end

  if not game_process_alive() then
    bridge.shutdown("game_closed")
  end
end

function bridge.start_host(session_id, peer_name, port, local_name)
  bridge.shutdown("restart")

  bridge.active = true
  bridge.role = "host"
  bridge.session_id = session_id
  bridge.peer_name = peer_name
  bridge.local_name = local_name
  set_sync_paths(session_id, local_name)
  reset_sync_files()

  bridge.server = assert(socket.bind("*", port or protocol.DEFAULT_PORT))
  bridge.server:settimeout(0)
  chat("waiting for duel connection on port " .. tostring(port or protocol.DEFAULT_PORT) .. "...")
end

function bridge.start_guest(session_id, peer_name, host_ip, port, local_name)
  bridge.shutdown("restart")

  bridge.active = true
  bridge.role = "guest"
  bridge.session_id = session_id
  bridge.peer_name = peer_name
  bridge.local_name = local_name
  set_sync_paths(session_id, local_name)
  reset_sync_files()

  local client = socket.tcp()
  client:settimeout(0)
  local ok, err = client:connect(host_ip, port or protocol.DEFAULT_PORT)
  if not ok and err ~= "timeout" then
    chat("failed to connect to host (" .. tostring(err) .. ").")
    bridge.active = false
    client:close()
    return false
  end

  bridge.client = client
  bridge.connect_host = host_ip
  bridge.connect_port = port or protocol.DEFAULT_PORT
  chat("connecting to host " .. host_ip .. ":" .. tostring(bridge.connect_port) .. "...")
  return true
end

function bridge.launch_game(args)
  local path = windower.addon_path .. "runtime\\TetraMaster.exe"
  if not windower.file_exists(path) then
    chat("executable not found. Run build\\build-fused.ps1")
    bridge.shutdown("launch_failed")
    return false
  end

  local running = count_running_games()
  if running >= MAX_GAME_INSTANCES then
    chat("already running " .. MAX_GAME_INSTANCES .. " TetraMaster windows (test limit).")
    return false
  end

  local cmd = 'start "" "' .. path .. '"'
  for _, v in ipairs(args) do
    cmd = cmd .. ' "' .. tostring(v):gsub('"', '') .. '"'
  end

  os.execute(cmd)

  if bridge.active then
    bridge.game_launched = true
    bridge.launch_time = os.time()
  end

  return true
end

function bridge.get_local_ip()
  local udp = socket.udp()
  udp:settimeout(0)
  local ok = udp:setpeername("8.8.8.8", 80)
  if not ok then
    udp:close()
    return "127.0.0.1"
  end
  local ip = udp:getsockname()
  udp:close()
  return ip or "127.0.0.1"
end

function bridge.get_session_id()
  return bridge.session_id
end

function bridge.tick()
  check_closed_flag()

  if bridge.winding_down then
    tick_wind_down()
    return
  end

  if not bridge.active then
    return
  end

  check_game_heartbeat()

  if bridge.client then
    local now = os.time()
    if now - bridge.last_tcp_ping >= TCP_KEEPALIVE_INTERVAL then
      send_tcp({ type = "ping" })
      bridge.last_tcp_ping = now
    end
  end

  if bridge.role == "host" and bridge.server and not bridge.client then
    local client = bridge.server:accept()
    if client then
      client:settimeout(0)
      bridge.client = client
      chat("opponent connected.")
      queue_to_game({ type = "peer_connected" })
      send_tcp({
        type = "hello",
        role = "host",
        session = bridge.session_id,
      })
    end
  end

  if bridge.role == "guest" and bridge.client then
    local _, err = bridge.client:connect(bridge.connect_host, bridge.connect_port)
    if not bridge.connected_announced and (err == "already connected" or err == "connected") then
      bridge.connected_announced = true
      chat("connected to host.")
    end
  end

  if bridge.client then
    local chunk, err, partial = bridge.client:receive("*l")
    if chunk then
      local msg = protocol.decode(chunk)
      if msg then
        if msg.type == "ping" then
          return
        end

        if msg.type == "resign" or msg.type == "disconnect" then
          bridge.shutdown("opponent_left")
          return
        end

        queue_to_game(msg)
      end
    elseif partial and partial ~= "" then
      bridge.recv_buffer = bridge.recv_buffer .. partial
    elseif err == "closed" then
      bridge.shutdown("connection_closed")
      return
    end
  end

  local lines, new_offset = read_new_lines(bridge.outbox_path, bridge.outbox_offset)
  bridge.outbox_offset = new_offset

  for _, line in ipairs(lines) do
    local msg = protocol.decode(line)
    if msg then
      if msg.type == "resign" or msg.type == "disconnect" then
        bridge.shutdown("local_quit")
        return
      end

      if bridge.client then
        send_tcp(msg)
      end
    end
  end
end

return bridge
