-- Windower-side TCP bridge between remote peer and local LOVE client.

local socket = require("socket")
local protocol = dofile(windower.addon_path .. "protocol.lua")
local ws_client = dofile(windower.addon_path .. "ws_client.lua")

local bridge = {
  active = false,
  winding_down = false,
  winding_reason = nil,
  wind_down_started = nil,
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
  relay_mode = false,
  transport = "tcp",
  ws_conn = nil,
  relay_session_ready = false,
  pending_game_args = nil,
  join_sent = false,
  game_launched = false,
  solo_session = false,
  launch_attempts = 0,
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
local debug_mode = false

local function chat(msg)
  windower.add_to_chat(207, "TetraMaster: " .. msg)
end

local function debug_chat(msg)
  if debug_mode then
    chat(msg)
  end
end

function bridge.set_debug(enabled)
  debug_mode = enabled and true or false
end

local HEARTBEAT_CHECK_INTERVAL = 2
local PROCESS_COUNT_CACHE_SEC = 20
local last_heartbeat_check = 0
local process_count_cache = { value = 0, at = 0 }

local function ensure_dir(path)
  windower.create_dir(path:gsub("\\", "/"))
end

local function refresh_process_count()
  if bridge.solo_session then
    return process_count_cache.value
  end

  local now = os.time()
  if now - process_count_cache.at < PROCESS_COUNT_CACHE_SEC then
    return process_count_cache.value
  end

  local handle = io.popen('tasklist /FI "IMAGENAME eq TetraMaster.exe" /NH 2>nul')
  local count = 0
  if handle then
    for line in handle:lines() do
      if line:lower():find("tetramaster.exe", 1, true) then
        count = count + 1
      end
    end
    handle:close()
  end

  process_count_cache.value = count
  process_count_cache.at = now
  return count
end

local function count_running_games()
  return refresh_process_count()
end

local function invalidate_process_count()
  process_count_cache.at = 0
end

local function cleanup_lingering_games(reason, was_solo, had_game, silent)
  if not had_game then
    return
  end

  invalidate_process_count()
  local running = count_running_games()
  if running == 0 then
    return
  end

  local should_kill = false
  if was_solo or reason == "force_reset" then
    should_kill = true
  elseif running > MAX_GAME_INSTANCES then
    should_kill = true
    if not silent then
      chat("closed leftover TetraMaster processes (" .. running .. " running).")
    end
  end

  if should_kill then
    os.execute("taskkill /IM TetraMaster.exe /F 2>nul")
    invalidate_process_count()
  end
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
  if bridge.transport == "wss" then
    if not bridge.ws_conn or not bridge.ws_conn.handshake_done then
      return false
    end

    local line = protocol.encode(msg)
    local ok, err = ws_client.send(bridge.ws_conn, line)
    if not ok then
      return false, err
    end
    return true
  end

  if not bridge.client then
    return false
  end

  local line = protocol.encode(msg) .. "\n"
  local sent = 0

  while sent < #line do
    local ok, err = bridge.client:send(line, sent + 1)
    if not ok then
      return false, err
    end
    sent = sent + ok
  end

  return true
end

local function queue_to_game(msg)
  append_line(bridge.inbox_path, protocol.encode(msg))
end

local function try_launch_pending_game()
  if bridge.game_launched or not bridge.pending_game_args or not bridge.relay_session_ready then
    return
  end

  if bridge.launch_attempts >= 1 then
    return
  end

  bridge.launch_attempts = bridge.launch_attempts + 1
  if bridge.launch_game(bridge.pending_game_args) then
    debug_chat("launching duel (" .. bridge.role .. ")...")
    bridge.pending_game_args = nil
  end
end

local function send_relay_join()
  if not bridge.relay_mode or bridge.join_sent then
    return true
  end

  local ok = send_tcp({
    type = "join",
    role = bridge.role,
    session = bridge.session_id:lower(),
    player = bridge.local_name,
  })

  if ok then
    bridge.join_sent = true
    return true
  end

  return false
end

local function handle_tcp_message(msg)
  if not msg or not msg.type then
    return
  end

  if msg.type == "ping" then
    return
  end

  if msg.type == "join_ok" then
    if bridge.role == "host" and bridge.relay_mode then
      bridge.relay_session_ready = true
      try_launch_pending_game()
    end
    return
  end

  if msg.type == "join_reject" then
    if msg.reason == "ip_limit" then
      chat("relay limit: max 2 TetraMaster connections per internet connection.")
    else
      chat("relay rejected join (" .. tostring(msg.reason or "unknown") .. ").")
    end
    bridge.shutdown("connection_closed")
    return
  end

  if msg.type == "relay_paired" then
    if bridge.role == "host" then
      debug_chat("opponent connected.")
      queue_to_game({ type = "peer_connected" })
    end
    bridge.relay_session_ready = true
    try_launch_pending_game()
    return
  end

  if msg.type == "hello" and bridge.role == "guest" and bridge.relay_mode then
    debug_chat("connected to host.")
    bridge.relay_session_ready = true
    queue_to_game(msg)
    try_launch_pending_game()
    return
  end

  if msg.type == "resign" or msg.type == "disconnect" then
    bridge.shutdown("opponent_left")
    return
  end

  queue_to_game(msg)
end

local function drain_tcp_inbox()
  if bridge.transport == "wss" then
    if not bridge.ws_conn or not bridge.ws_conn.handshake_done then
      return
    end

    local lines, err = ws_client.receive_lines(bridge.ws_conn)
    for _, line in ipairs(lines) do
      local msg = protocol.decode(line)
      if msg then
        handle_tcp_message(msg)
      end
    end

    if err == "closed" then
      bridge.shutdown("connection_closed")
    end
    return
  end

  if not bridge.client then
    return
  end

  while true do
    local chunk, err, partial = bridge.client:receive("*l")
    if chunk then
      local msg = protocol.decode(chunk)
      if msg then
        handle_tcp_message(msg)
      end
    elseif partial and partial ~= "" then
      bridge.recv_buffer = bridge.recv_buffer .. partial
      local newline = bridge.recv_buffer:find("\n", 1, true)
      while newline do
        local line = bridge.recv_buffer:sub(1, newline - 1):gsub("\r$", "")
        bridge.recv_buffer = bridge.recv_buffer:sub(newline + 1)
        if line ~= "" then
          local msg = protocol.decode(line)
          if msg then
            handle_tcp_message(msg)
          end
        end
        newline = bridge.recv_buffer:find("\n", 1, true)
      end
      break
    elseif err == "closed" then
      bridge.shutdown("connection_closed")
      return
    else
      break
    end
  end
end

local function send_resign_handshake()
  if not bridge.session_id or not bridge.local_name then
    return
  end

  windower.send_ipc_message(protocol.format_ipc("RESIGN", bridge.session_id, bridge.local_name))
end

local function close_tcp()
  if bridge.ws_conn then
    ws_client.close(bridge.ws_conn)
    bridge.ws_conn = nil
  end

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
  return bridge.active
end

function bridge.is_busy()
  return bridge.active or bridge.winding_down or bridge.game_launched or bridge.solo_session
end

function bridge.complete_shutdown(reason, silent)
  local was_solo = bridge.solo_session
  local had_game = bridge.game_launched

  close_tcp()

  bridge.active = false
  bridge.winding_down = false
  bridge.winding_reason = nil
  bridge.wind_down_started = nil
  bridge.game_launched = false
  bridge.solo_session = false
  bridge.launch_attempts = 0
  bridge.launch_time = nil
  bridge.nudge_counter = 0
  bridge.last_tcp_ping = 0
  last_heartbeat_check = 0
  invalidate_process_count()
  bridge.role = nil
  bridge.session_id = nil
  bridge.local_name = nil
  bridge.peer_name = nil
  bridge.connected_announced = false
  bridge.relay_mode = false
  bridge.transport = "tcp"
  bridge.ws_conn = nil
  bridge.relay_session_ready = false
  bridge.pending_game_args = nil
  bridge.join_sent = false
  bridge.inbox_path = nil
  bridge.outbox_path = nil
  bridge.heartbeat_path = nil
  bridge.closed_flag_path = nil
  bridge.sync_dir = nil
  bridge.inbox_offset = 0
  bridge.outbox_offset = 0

  cleanup_lingering_games(reason, was_solo, had_game, silent)

  if bridge.on_session_end and not silent then
    bridge.on_session_end(reason)
  end
end

local function begin_wind_down(reason)
  bridge.active = false
  bridge.winding_down = true
  bridge.winding_reason = reason
  bridge.nudge_counter = 0
  bridge.wind_down_started = os.time()
end

local function end_duel(reason)
  if bridge.client then
    send_tcp({ type = "disconnect", reason = reason })
  end

  send_resign_handshake()
  queue_to_game({ type = "disconnect", reason = reason })
  close_tcp()
  begin_wind_down(reason)
end

local function end_duel_for_opponent(reason)
  queue_to_game({ type = "disconnect", reason = reason })
  close_tcp()
  begin_wind_down(reason)
end

function bridge.force_reset(kill_game)
  close_tcp()
  if kill_game then
    os.execute('taskkill /IM TetraMaster.exe /F 2>nul')
    invalidate_process_count()
  end
  bridge.complete_shutdown("force_reset", true)
end

function bridge.shutdown(reason)
  reason = reason or "stop"

  if reason == "restart" or reason == "stop" or reason == "launch_failed" or reason == "force_reset" then
    bridge.complete_shutdown(reason, true)
    return
  end

  if reason == "manual_resign" then
    bridge.complete_shutdown(reason, false)
    return
  end

  if reason == "connection_closed" then
    if not bridge.game_launched then
      bridge.complete_shutdown(reason, false)
      return
    end
    chat("relay connection lost.")
    end_duel_for_opponent(reason)
    return
  end

  if reason == "opponent_left" then
    chat("opponent left the duel.")
    end_duel_for_opponent(reason)
    return
  end

  if reason == "local_quit" or reason == "game_closed" then
    if reason == "game_closed" or reason == "local_quit" then
      chat("TetraMaster window closed. Ending duel session.")
    end
    if bridge.solo_session and not bridge.active then
      bridge.complete_shutdown(reason, false)
      return
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
  if not bridge.heartbeat_path then
    return nil
  end

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

local WIND_DOWN_TIMEOUT = 45

local function game_exe_running()
  return refresh_process_count() > 0
end

local function game_process_alive()
  if not bridge.game_launched then
    return false
  end

  if bridge.solo_session then
    return true
  end

  if within_launch_grace() then
    return true
  end

  local age = read_heartbeat_age()
  if age ~= nil and age <= HEARTBEAT_TIMEOUT then
    return true
  end

  return game_exe_running()
end

local function check_closed_flag()
  if not bridge.closed_flag_path or not windower.file_exists(bridge.closed_flag_path) then
    return
  end

  if within_launch_grace() then
    return
  end

  os.remove(bridge.closed_flag_path)

  if bridge.active or bridge.game_launched or bridge.winding_down or bridge.solo_session then
    bridge.shutdown("game_closed")
  end
end

local function tick_wind_down()
  if not bridge.game_launched or not game_exe_running() then
    bridge.complete_shutdown(bridge.winding_reason or "session_ended")
    return
  end

  if bridge.wind_down_started and (os.time() - bridge.wind_down_started) >= WIND_DOWN_TIMEOUT then
    bridge.complete_shutdown(bridge.winding_reason or "session_ended")
    return
  end

  bridge.nudge_counter = bridge.nudge_counter + 1

  if bridge.nudge_counter % QUIT_NUDGE_INTERVAL == 0 then
    queue_to_game({ type = "disconnect", reason = bridge.winding_reason or "session_ended" })
  end

  if not game_process_alive() then
    bridge.complete_shutdown(bridge.winding_reason or "session_ended")
  end
end

local function check_game_heartbeat()
  if not bridge.game_launched or bridge.solo_session then
    return
  end

  if not bridge.active then
    return
  end

  local now = os.time()
  if now - last_heartbeat_check < HEARTBEAT_CHECK_INTERVAL then
    return
  end
  last_heartbeat_check = now

  if not game_process_alive() then
    bridge.shutdown("game_closed")
  end
end

function bridge.start_host(session_id, peer_name, port, local_name)
  bridge.shutdown("restart")

  bridge.active = true
  bridge.role = "host"
  bridge.relay_mode = false
  bridge.join_sent = false
  bridge.session_id = session_id
  bridge.peer_name = peer_name
  bridge.local_name = local_name
  set_sync_paths(session_id, local_name)
  reset_sync_files()

  bridge.server = assert(socket.bind("*", port or protocol.DEFAULT_PORT))
  bridge.server:settimeout(0)
  debug_chat("waiting for duel connection on port " .. tostring(port or protocol.DEFAULT_PORT) .. "...")
end

function bridge.start_guest(session_id, peer_name, host_ip, port, local_name)
  bridge.shutdown("restart")

  bridge.active = true
  bridge.role = "guest"
  bridge.relay_mode = false
  bridge.join_sent = false
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
    chat("host must allow inbound TCP " .. tostring(port or protocol.DEFAULT_PORT) .. " (firewall/router).")
    bridge.active = false
    client:close()
    return false
  end

  bridge.client = client
  bridge.connect_host = host_ip
  bridge.connect_port = port or protocol.DEFAULT_PORT
  debug_chat("connecting to host " .. host_ip .. ":" .. tostring(bridge.connect_port) .. "...")
  return true
end

local function start_relay_tcp(local_name, relay_host, port)
  bridge.connect_port = port or protocol.DEFAULT_PORT
  local client = socket.tcp()
  client:settimeout(0)
  local ok, err = client:connect(relay_host, bridge.connect_port)
  if not ok and err ~= "timeout" then
    chat("failed to connect to relay (" .. tostring(err) .. ").")
    bridge.active = false
    client:close()
    return false
  end

  bridge.client = client
  bridge.connect_host = relay_host
  debug_chat("connecting to relay " .. relay_host .. ":" .. tostring(bridge.connect_port) .. "...")
  return true
end

function bridge.start_relay(session_id, peer_name, role, relay_host, port, local_name, game_args)
  bridge.shutdown("restart")

  bridge.active = true
  bridge.solo_session = false
  bridge.role = role
  bridge.relay_mode = true
  bridge.join_sent = false
  bridge.relay_session_ready = false
  bridge.pending_game_args = game_args
  bridge.launch_attempts = 0
  bridge.session_id = session_id
  bridge.peer_name = peer_name
  bridge.local_name = local_name
  set_sync_paths(session_id, local_name)
  reset_sync_files()

  local use_wss = protocol.should_use_wss(relay_host)
  if not use_wss then
    return start_relay_tcp(local_name, relay_host, port)
  end

  bridge.transport = "wss"
  bridge.connect_host = relay_host
  bridge.connect_port = port or protocol.DEFAULT_WSS_PORT

  local conn, err = ws_client.connect(relay_host, bridge.connect_port, protocol.DEFAULT_WS_PATH)
  if not conn then
    chat("failed to connect to relay (" .. tostring(err) .. ").")
    bridge.active = false
    return false
  end

  bridge.ws_conn = conn
  debug_chat("connecting to relay wss://" .. relay_host .. protocol.DEFAULT_WS_PATH .. " ...")
  return true
end

function bridge.launch_game(args)
  local path = windower.addon_path .. "runtime\\TetraMaster.exe"
  if not windower.file_exists(path) then
    chat("executable not found. Run build\\build-fused.ps1")
    bridge.shutdown("launch_failed")
    return false
  end

  if bridge.game_launched then
    return false
  end

  if not bridge.active then
    -- Solo play: skip tasklist (avoids flashing console windows during monitoring).
  else
    invalidate_process_count()
    local running = count_running_games()
    if running >= MAX_GAME_INSTANCES then
      chat("already running " .. MAX_GAME_INSTANCES .. " TetraMaster windows (test limit).")
      chat("Use //tm reset to close leftover game windows.")
      return false
    end
  end

  local cmd = 'start "" /MIN "' .. path .. '"'
  for _, v in ipairs(args) do
    cmd = cmd .. ' "' .. tostring(v):gsub('"', '') .. '"'
  end

  os.execute(cmd)

  bridge.game_launched = true
  bridge.launch_time = os.time()
  bridge.solo_session = not bridge.active

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

function bridge.get_public_ip()
  local ok, http = pcall(require, "socket.http")
  if not ok then
    return nil
  end

  http.TIMEOUT = 8
  local body, status = http.request("http://api.ipify.org")
  if status ~= 200 or not body then
    return nil
  end

  return body:match("^(%d+%.%d+%.%d+%.%d+)$")
end

function bridge.get_connect_ip(override_ip)
  if override_ip and override_ip ~= "" then
    return override_ip
  end

  debug_chat("looking up your public IP for duel...")
  local public_ip = bridge.get_public_ip()
  if public_ip then
    return public_ip
  end

  chat("could not fetch public IP. Use //tm hostip <ip> (Tailscale recommended).")
  return bridge.get_local_ip()
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

  if bridge.solo_session and bridge.game_launched and not bridge.active then
    return
  end

  if not bridge.active then
    return
  end

  check_game_heartbeat()

  if bridge.client or bridge.ws_conn then
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
      debug_chat("opponent connected.")
      queue_to_game({ type = "peer_connected" })
      send_tcp({
        type = "hello",
        role = "host",
        session = bridge.session_id,
      })
    end
  end

  if bridge.ws_conn then
    if not bridge.ws_conn.handshake_done then
      local ready, err = ws_client.tick_handshake(bridge.ws_conn)
      if err then
        chat("relay websocket handshake failed (" .. tostring(err) .. ").")
        bridge.shutdown("connection_closed")
        return
      end
    else
      ws_client.flush_send(bridge.ws_conn)
    end

    if bridge.ws_conn.handshake_done and bridge.relay_mode and not bridge.join_sent then
      send_relay_join()
    end
  end

  if bridge.client then
    local _, err = bridge.client:connect(bridge.connect_host, bridge.connect_port)
    if not bridge.connected_announced and (err == "already connected" or err == "connected") then
      bridge.connected_announced = true
      if bridge.relay_mode then
        send_relay_join()
      elseif bridge.role == "guest" then
        debug_chat("connected to host.")
      end
    end
  end

  if bridge.client or (bridge.ws_conn and bridge.ws_conn.handshake_done) then
    drain_tcp_inbox()
    if not bridge.active then
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

      if bridge.client or (bridge.ws_conn and bridge.ws_conn.handshake_done) then
        send_tcp(msg)
      end
    end
  end
end

return bridge
