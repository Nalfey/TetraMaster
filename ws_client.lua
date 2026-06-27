-- WebSocket client for Windower (LuaSec-compatible TLS + masked text frames).

local socket = require("socket")

local ws = {}

local function bxor(a, b)
  local r = 0
  local bit = 1
  for _ = 0, 7 do
    if a % 2 ~= b % 2 then
      r = r + bit
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit = bit * 2
  end
  return r
end

local function random_key()
  local bytes = {}
  for _ = 1, 16 do
    bytes[#bytes + 1] = string.char(math.random(0, 255))
  end
  return table.concat(bytes)
end

local function base64_encode(data)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  local i = 1
  while i <= #data do
    local a = data:byte(i) or 0
    local b = data:byte(i + 1) or 0
    local c = data:byte(i + 2) or 0
    local n = a * 65536 + b * 256 + c
    out[#out + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
    out[#out + 1] = alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
    out[#out + 1] = (i + 1 <= #data) and alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
    out[#out + 1] = (i + 2 <= #data) and alphabet:sub(n % 64 + 1, n % 64 + 1) or "="
    i = i + 3
  end
  return table.concat(out)
end

local function encode_control_frame(opcode, payload)
  local len = #payload
  local mask = string.char(math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255))
  local header

  if len < 126 then
    header = string.char(0x80 + opcode, 0x80 + len)
  else
    header = string.char(0x80 + opcode, 0x80 + 126, math.floor(len / 256) % 256, len % 256)
  end

  local masked = {}
  for i = 1, len do
    masked[i] = string.char(bxor(payload:byte(i), mask:byte((i - 1) % 4 + 1)))
  end

  return header .. mask .. table.concat(masked)
end

local function encode_text_frame(payload)
  return encode_control_frame(0x1, payload)
end

local function try_parse_frame(buffer)
  if #buffer < 2 then
    return nil, buffer
  end

  local b1 = buffer:byte(1)
  local b2 = buffer:byte(2)
  local opcode = b1 % 16
  local masked = math.floor(b2 / 128) == 1
  local len = b2 % 128
  local offset = 3

  if len == 126 then
    if #buffer < 4 then
      return nil, buffer
    end
    len = buffer:byte(3) * 256 + buffer:byte(4)
    offset = 5
  elseif len == 127 then
    if #buffer < 10 then
      return nil, buffer
    end
    len = 0
    for i = 3, 10 do
      len = len * 256 + buffer:byte(i)
    end
    offset = 11
  end

  local mask = ""
  if masked then
    if #buffer < offset + 3 then
      return nil, buffer
    end
    mask = buffer:sub(offset, offset + 3)
    offset = offset + 4
  end

  if #buffer < offset + len - 1 then
    return nil, buffer
  end

  local payload = buffer:sub(offset, offset + len - 1)
  local rest = buffer:sub(offset + len)

  if masked then
    local unmasked = {}
    for i = 1, #payload do
      unmasked[i] = string.char(bxor(payload:byte(i), mask:byte((i - 1) % 4 + 1)))
    end
    payload = table.concat(unmasked)
  end

  if opcode == 0x8 then
    return { close = true }, rest
  end

  if opcode == 0x9 then
    return { ping = payload }, rest
  end

  if opcode == 0xA then
    return { pong = true }, rest
  end

  if opcode ~= 0x1 then
    return { ignore = true }, rest
  end

  return { text = payload }, rest
end

local function pending_err(err)
  return err == "timeout" or err == "wantread" or err == "wantwrite"
end

local function send_bytes(sock, data)
  if data == "" then
    return true
  end

  local ok, err = sock:send(data)
  if ok then
    return true
  end

  if pending_err(err) then
    return false
  end

  return false, err
end

local function wrap_tls(ssl_module, tcp, host)
  local attempts = {
    { mode = "client", protocol = "tlsv1_2", verify = "none", servername = host },
    { mode = "client", protocol = "tlsv1_2", verify = "none" },
    { mode = "client", verify = "none" },
  }

  for _, params in ipairs(attempts) do
    local ok, wrapped = pcall(ssl_module.wrap, tcp, params)
    if ok and wrapped then
      wrapped:settimeout(0)
      return wrapped
    end
  end

  return nil, "ssl wrap failed"
end

function ws.handshake_blocking(host, port, path)
  path = path or "/"
  port = port or 443
  local deadline = os.clock() + 5

  local tcp = socket.tcp()
  tcp:settimeout(4)

  local ok, err = tcp:connect(host, port)
  if not ok then
    tcp:close()
    return nil, "connect failed: " .. tostring(err)
  end

  local sock = tcp
  local tls_sock = nil
  local ssl_module = nil
  local use_tls = port == 443

  if use_tls then
    local ssl_ok, ssl = pcall(require, "ssl")
    if not ssl_ok then
      tcp:close()
      return nil, "ssl module required for wss"
    end
    ssl_module = ssl

    local wrapped = nil
    local last_wrap_err = nil
    local param_sets = {
      { mode = "client", protocol = "tlsv1_2", verify = "none" },
      { mode = "client", verify = "none", options = "all" },
      { mode = "client", verify = "none" },
    }

    for _, params in ipairs(param_sets) do
      local wrap_ok, candidate = pcall(ssl.wrap, tcp, params)
      if wrap_ok and candidate then
        wrapped = candidate
        break
      end
      last_wrap_err = candidate
    end

    if not wrapped then
      tcp:close()
      return nil, "ssl wrap failed: " .. tostring(last_wrap_err)
    end

    pcall(function()
      if wrapped.sni and host and host ~= "" then
        wrapped:sni(host)
      end
    end)

    wrapped:settimeout(4)
    local tls_attempts = 0
    while os.clock() < deadline do
      tls_attempts = tls_attempts + 1
      if tls_attempts > 40 then
        wrapped:close()
        return nil, "tls handshake timed out"
      end
      local handshake_ok, handshake_err = wrapped:dohandshake()
      if handshake_ok then
        break
      end
      if handshake_err == "wantread" or handshake_err == "wantwrite" or handshake_err == "timeout" then
        if handshake_err == "timeout" and tls_attempts > 1 then
          -- keep trying until deadline
        end
      else
        wrapped:close()
        return nil, "tls handshake failed: " .. tostring(handshake_err)
      end
    end

    if os.clock() >= deadline then
      wrapped:close()
      return nil, "tls handshake timed out"
    end

    wrapped:settimeout(0)
    sock = wrapped
    tls_sock = wrapped
  end

  local key = base64_encode(random_key())
  local request = table.concat({
    "GET " .. path .. " HTTP/1.1",
    "Host: " .. host,
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: " .. key,
    "Sec-WebSocket-Version: 13",
    "",
    "",
  }, "\r\n")

  sock:settimeout(4)
  local sent_ok, send_err = sock:send(request)
  if not sent_ok then
    sock:close()
    return nil, "ws request failed: " .. tostring(send_err)
  end

  local http_buffer = ""
  while os.clock() < deadline do
    local chunk, recv_err, partial = sock:receive(1024)
    if chunk and chunk ~= "" then
      http_buffer = http_buffer .. chunk
    elseif partial and partial ~= "" then
      http_buffer = http_buffer .. partial
    elseif recv_err and recv_err ~= "timeout" then
      sock:close()
      return nil, "ws response failed: " .. tostring(recv_err)
    end

    local header_end = http_buffer:find("\r\n\r\n", 1, true)
    if header_end then
      local headers = http_buffer:sub(1, header_end - 1)
      if not headers:match("^HTTP/1%.1 101") then
        local status = headers:match("^(HTTP/[^\r\n]+)") or headers
        sock:close()
        return nil, "bad websocket handshake: " .. status
      end
      http_buffer = http_buffer:sub(header_end + 4)
      break
    end
  end

  if os.clock() >= deadline then
    sock:close()
    return nil, "ws handshake timed out"
  end

  sock:settimeout(0)

  return {
    tcp = tcp,
    sock = sock,
    tls_sock = tls_sock,
    host = host,
    port = port,
    path = path,
    use_tls = use_tls,
    ssl_module = ssl_module,
    tcp_connected = true,
    tls_ready = true,
    connection_ready = true,
    handshake_sent = true,
    handshake_done = true,
    http_request = nil,
    pending_send = nil,
    recv_buffer = "",
    http_buffer = http_buffer,
    ws_key = key,
    connect_host = host,
    connect_port = port,
  }
end

function ws.connect(host, port, path)
  local tcp = socket.tcp()
  tcp:settimeout(0)

  local use_tls = port == 443

  local conn = {
    tcp = tcp,
    sock = tcp,
    host = host,
    port = port,
    path = path or "/",
    use_tls = use_tls,
    tls_sock = nil,
    ssl_module = nil,
    tcp_connected = false,
    tls_ready = not use_tls,
    connection_ready = false,
    handshake_sent = false,
    handshake_done = false,
    http_request = nil,
    pending_send = nil,
    recv_buffer = "",
    connect_host = host,
    connect_port = port,
    http_buffer = "",
  }

  if use_tls then
    local ssl_ok, ssl = pcall(require, "ssl")
    if not ssl_ok then
      tcp:close()
      return nil, "ssl module required for wss"
    end
    conn.ssl_module = ssl
  end

  return conn
end

function ws.tick_connection(conn)
  if conn.connection_ready then
    return true
  end

  if not conn.tcp_connected then
    local _, err = conn.tcp:connect(conn.connect_host, conn.connect_port)
    if err == "already connected" or err == "connected" then
      conn.tcp_connected = true
    elseif err and err ~= "timeout" then
      return false, err
    else
      return false
    end
  end

  if conn.use_tls and not conn.tls_ready then
    if not conn.tls_sock then
      local wrapped, wrap_err = wrap_tls(conn.ssl_module, conn.tcp, conn.host)
      if not wrapped then
        return false, wrap_err
      end
      conn.tls_sock = wrapped
    end

    local ok, err = conn.tls_sock:dohandshake()
    if ok then
      conn.tls_ready = true
      conn.sock = conn.tls_sock
    elseif pending_err(err) then
      return false
    else
      return false, err or "tls handshake failed"
    end
  else
    conn.sock = conn.tcp
  end

  conn.connection_ready = true
  return true
end

function ws.connected(conn)
  return conn.connection_ready == true
end

function ws.flush_send(conn)
  if not conn.pending_send or conn.pending_send == "" then
    return true
  end

  local ok, err = send_bytes(conn.sock, conn.pending_send)
  if ok then
    conn.pending_send = nil
    return true
  end

  if not err then
    return false
  end

  return false, err
end

function ws.tick_handshake(conn)
  if conn.handshake_done then
    return true
  end

  local flushed, flush_err = ws.flush_send(conn)
  if flush_err then
    return false, flush_err
  end
  if not flushed then
    return false
  end

  local connected, err = ws.tick_connection(conn)
  if err then
    return false, err
  end
  if not connected then
    return false
  end

  if not conn.http_request then
    local key = base64_encode(random_key())
    conn.ws_key = key
    conn.http_request = table.concat({
      "GET " .. conn.path .. " HTTP/1.1",
      "Host: " .. conn.host,
      "Upgrade: websocket",
      "Connection: Upgrade",
      "Sec-WebSocket-Key: " .. key,
      "Sec-WebSocket-Version: 13",
      "",
      "",
    }, "\r\n")
    conn.http_buffer = ""
  end

  if not conn.handshake_sent then
    local ok, send_err = send_bytes(conn.sock, conn.http_request)
    if not ok and send_err then
      return false, send_err
    end
    if not ok then
      return false
    end
    conn.handshake_sent = true
    conn.http_request = nil
  end

  local chunk, recv_err, partial
  local recv_ok, r1, r2, r3 = pcall(function()
    return conn.sock:receive(1024)
  end)
  if not recv_ok then
    return false, tostring(r1)
  end
  chunk, recv_err, partial = r1, r2, r3
  if chunk and chunk ~= "" then
    conn.http_buffer = conn.http_buffer .. chunk
  elseif partial and partial ~= "" then
    conn.http_buffer = conn.http_buffer .. partial
  elseif recv_err and recv_err ~= "timeout" and not pending_err(recv_err) then
    if recv_err == "closed" then
      return false, "connection closed during websocket handshake"
    end
    return false, recv_err
  end

  local header_end = conn.http_buffer:find("\r\n\r\n", 1, true)
  if not header_end then
    return false
  end

  local headers = conn.http_buffer:sub(1, header_end - 1)
  conn.http_buffer = conn.http_buffer:sub(header_end + 4)

  if not headers:match("^HTTP/1%.1 101") then
    local status = headers:match("^(HTTP/[^\r\n]+)") or headers
    return false, "bad websocket handshake: " .. status
  end

  conn.handshake_done = true
  return true
end

function ws.send(conn, text)
  local payload = encode_text_frame(text)

  if conn.pending_send and conn.pending_send ~= "" then
    conn.pending_send = conn.pending_send .. payload
  else
    conn.pending_send = payload
  end

  return ws.flush_send(conn)
end

function ws.receive_lines(conn)
  local flushed, flush_err = ws.flush_send(conn)
  if flush_err then
    return {}, flush_err
  end
  if not flushed then
    return {}
  end

  local lines = {}

  while true do
    local frame, rest = try_parse_frame(conn.recv_buffer)
    if not frame then
      break
    end
    conn.recv_buffer = rest

    if frame.close then
      return lines, "closed"
    end

    if frame.ping then
      send_bytes(conn.sock, encode_control_frame(0xA, frame.ping))
    elseif frame.text then
      for line in frame.text:gmatch("[^\r\n]+") do
        if line ~= "" then
          lines[#lines + 1] = line
        end
      end
    end
  end

  while true do
    local chunk, err, partial = conn.sock:receive(4096)
    if chunk then
      conn.recv_buffer = conn.recv_buffer .. chunk
    elseif partial and partial ~= "" then
      conn.recv_buffer = conn.recv_buffer .. partial
    else
      if err == "closed" then
        return lines, "closed"
      end
      break
    end

    while true do
      local frame, rest = try_parse_frame(conn.recv_buffer)
      if not frame then
        break
      end
      conn.recv_buffer = rest

      if frame.close then
        return lines, "closed"
      end

      if frame.ping then
        send_bytes(conn.sock, encode_control_frame(0xA, frame.ping))
      elseif frame.text then
        for line in frame.text:gmatch("[^\r\n]+") do
          if line ~= "" then
            lines[#lines + 1] = line
          end
        end
      end
    end

    if not chunk then
      break
    end
  end

  return lines
end

function ws.close(conn)
  if not conn then
    return
  end

  if conn.tls_sock then
    conn.tls_sock:close()
  end

  if conn.tcp then
    conn.tcp:close()
  end
end

return ws
