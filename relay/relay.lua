#!/usr/bin/env lua5.4
-- TetraMaster duel relay: pairs host + guest by session and forwards JSON lines.

local socket = require("socket")

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/[^/]+$") or "."
end

package.path = script_dir() .. "/?.lua;" .. package.path
local protocol = require("protocol")

local BIND_HOST = os.getenv("TM_RELAY_BIND") or "127.0.0.1"
local BIND_PORT = tonumber(os.getenv("TM_RELAY_PORT") or tostring(protocol.DEFAULT_PORT)) or protocol.DEFAULT_PORT
local MAX_SESSIONS = tonumber(os.getenv("TM_RELAY_MAX_SESSIONS") or "64") or 64
local IDLE_TIMEOUT = tonumber(os.getenv("TM_RELAY_IDLE_SEC") or "600") or 600

local server = assert(socket.bind(BIND_HOST, BIND_PORT))
server:settimeout(0)

local clients = {}
local sessions = {}

local function session_count()
  local count = 0
  for _ in pairs(sessions) do
    count = count + 1
  end
  return count
end

local function log(msg)
  io.stdout:write(os.date("%Y-%m-%d %H:%M:%S"), " relay: ", msg, "\n")
  io.stdout:flush()
end

local function client_send(sock, msg)
  local line = protocol.encode(msg) .. "\n"
  local sent = 0

  while sent < #line do
    local ok, err = sock:send(line, sent + 1)
    if not ok then
      return false, err
    end
    sent = sent + ok
  end

  return true
end

local function remove_client(sock)
  local client = clients[sock]
  if not client then
    return
  end

  if client.session then
    local sess = sessions[client.session]
    if sess then
      if sess.host_sock == sock then
        sess.host_sock = nil
      end
      if sess.guest_sock == sock then
        sess.guest_sock = nil
      end
      if not sess.host_sock and not sess.guest_sock then
        sessions[client.session] = nil
        log("session closed " .. client.session)
      else
        sess.paired = false
      end
    end
  end

  sock:close()
  clients[sock] = nil
end

local function try_pair(session_id)
  local sess = sessions[session_id]
  if not sess or sess.paired or not sess.host_sock or not sess.guest_sock then
    return
  end

  local host = clients[sess.host_sock]
  local guest = clients[sess.guest_sock]
  if not host or not guest or not host.joined or not guest.joined then
    return
  end

  sess.paired = true
  client_send(sess.host_sock, { type = "relay_paired" })
  client_send(sess.guest_sock, {
    type = "hello",
    role = "host",
    session = session_id,
  })
  log(
    "paired "
      .. session_id
      .. " ("
      .. (host.player or "?")
      .. " host, "
      .. (guest.player or "?")
      .. " guest)"
  )
end

local function reject_join(sock, reason)
  client_send(sock, { type = "join_reject", reason = reason })
  remove_client(sock)
end

local function handle_join(sock, msg)
  local client = clients[sock]
  if not client or client.joined then
    return
  end

  local role = msg.role
  local session_id = msg.session and msg.session:lower() or nil
  local player = msg.player or ""

  if role ~= "host" and role ~= "guest" then
    reject_join(sock, "invalid_role")
    return
  end

  if not session_id or session_id == "" then
    reject_join(sock, "missing_session")
    return
  end

  local sess = sessions[session_id]
  if not sess then
    if session_count() >= MAX_SESSIONS then
      reject_join(sock, "server_full")
      return
    end
    sess = { paired = false, created = socket.gettime() }
    sessions[session_id] = sess
  end

  local slot = role .. "_sock"
  if sess[slot] then
    local stale_sock = sess[slot]
    if stale_sock ~= sock and clients[stale_sock] then
      log("replacing stale " .. role .. " for " .. session_id)
      remove_client(stale_sock)
    end
  end

  sess[slot] = sock
  client.joined = true
  client.role = role
  client.session = session_id
  client.player = player
  client.last_active = socket.gettime()

  client_send(sock, { type = "join_ok" })
  log("join " .. session_id .. " " .. role .. " (" .. player .. ")")
  try_pair(session_id)
end

local function peer_sock(sock)
  local client = clients[sock]
  if not client or not client.joined or not client.session then
    return nil
  end

  local sess = sessions[client.session]
  if not sess or not sess.paired then
    return nil
  end

  if client.role == "host" then
    return sess.guest_sock
  end
  return sess.host_sock
end

local function forward(sock, msg)
  local dest = peer_sock(sock)
  if not dest or not clients[dest] then
    return
  end

  client_send(dest, msg)
end

local function handle_line(sock, line)
  local msg = protocol.decode(line)
  if not msg or not msg.type then
    return
  end

  local client = clients[sock]
  if client then
    client.last_active = socket.gettime()
  end

  if msg.type == "join" then
    handle_join(sock, msg)
    return
  end

  if msg.type == "ping" then
    return
  end

  if msg.type == "join_ok" or msg.type == "join_reject" or msg.type == "relay_paired" then
    return
  end

  forward(sock, msg)
end

local function accept_client(sock)
  sock:settimeout(0)
  clients[sock] = {
    sock = sock,
    buffer = "",
    joined = false,
    last_active = socket.gettime(),
  }
  log("client connected " .. tostring(sock:getpeername()))
end

local function read_clients()
  for sock, client in pairs(clients) do
    while true do
      local line, err, partial = sock:receive("*l")
      if line then
        handle_line(sock, line)
      elseif partial and partial ~= "" then
        client.buffer = client.buffer .. partial
      elseif err == "closed" then
        log("client disconnected " .. tostring(sock:getpeername()))
        remove_client(sock)
        break
      else
        break
      end
    end
  end
end

local function reap_idle_sessions()
  local now = socket.gettime()
  for session_id, sess in pairs(sessions) do
    if not sess.paired then
      local newest = sess.created or now
      for _, slot in ipairs({ "host_sock", "guest_sock" }) do
        local sock = sess[slot]
        local client = sock and clients[sock]
        if client and client.last_active then
          newest = math.max(newest, client.last_active)
        end
      end
      if now - newest > IDLE_TIMEOUT then
        log("idle timeout " .. session_id)
        if sess.host_sock then
          remove_client(sess.host_sock)
        end
        if sess.guest_sock then
          remove_client(sess.guest_sock)
        end
        sessions[session_id] = nil
      end
    end
  end
end

log("listening on " .. BIND_HOST .. ":" .. tostring(BIND_PORT))

while true do
  local read_list = { server }
  for sock in pairs(clients) do
    read_list[#read_list + 1] = sock
  end

  local readable = socket.select(read_list, nil, 1)
  if readable then
    for _, sock in ipairs(readable) do
      if sock == server then
        local client_sock = server:accept()
        if client_sock then
          accept_client(client_sock)
        end
      else
        local line, err, partial = sock:receive("*l")
        if line then
          handle_line(sock, line)
        elseif partial and partial ~= "" then
          local client = clients[sock]
          if client then
            client.buffer = client.buffer .. partial
          end
        elseif err == "closed" then
          log("client disconnected " .. tostring(sock:getpeername()))
          remove_client(sock)
        end
      end
    end
  end

  reap_idle_sessions()
end
