_addon = {
    name = 'TetraMaster',
    author = 'Nalfey',
    version = '1.1.6',
    description = 'Launch Tetra Master and duel party members.',
}

local protocol = dofile(windower.addon_path .. 'protocol.lua')
local duel_bridge = dofile(windower.addon_path .. 'duel_bridge.lua')

local runtime_dir = windower.addon_path .. 'runtime\\'
local exe_name = 'TetraMaster.exe'

local pending_challenge = nil
local pending_connect = nil
local notified_challenges = {}
local host_connect_ip_override = nil
local relay_host_override = nil
local DEFAULT_RELAY_HOST = 'relay.tetramasters.uk'
local RELAY_DOMAIN = 'tetramasters.uk'
local debug_mode = false

local function chat(msg)
    windower.add_to_chat(207, 'TetraMaster: ' .. msg)
end

local function debug_chat(msg)
    if debug_mode then
        chat(msg)
    end
end

local function exe_path()
    return runtime_dir .. exe_name
end

local function player_name()
    local player = windower.ffxi.get_player()
    if not player then
        return nil
    end
    return player.name
end

local function find_party_member(name)
    local party = windower.ffxi.get_party()
    if not party then
        return nil
    end

    local target = name:lower()
    for i = 0, 5 do
        local member = party['p' .. i]
        if member and member.name and member.name:lower() == target then
            return member
        end
    end

    return nil
end

local function in_party_with(name)
    local me = player_name()
    if not me then
        return false, 'not logged in.'
    end

    if me:lower() == name:lower() then
        return false, 'you cannot duel yourself.'
    end

    local member = find_party_member(name)
    if not member then
        return false, name .. ' is not in your party.'
    end

    return true, me
end

local function send_party_line(line)
    windower.send_command('input /p ' .. line)
end

local function announce_challenge(challenger, target)
    send_party_line(challenger .. ' challenges ' .. target .. ' to a TetraMaster duel!')
end

local function announce_accept(guest_name)
    send_party_line(guest_name .. ' accepts the duel!')
end

local function announce_decline(guest_name)
    send_party_line(guest_name .. ' declines the TetraMaster duel.')
end

local function send_ipc_handshake(kind, ...)
    windower.send_ipc_message(protocol.format_ipc(kind, ...))
end

local function bridge_dir(session_id, local_name)
    return windower.addon_path .. 'sync\\' .. session_id .. '\\' .. local_name
end

local function launch_solo()
    if duel_bridge.is_busy() then
        duel_bridge.force_reset(true)
    end

    local path = exe_path()
    if not windower.file_exists(path) then
        chat('executable not found.')
        chat('Run build\\build-fused.ps1 from this addon folder.')
        return
    end

    if not duel_bridge.launch_game({}) then
        return
    end

    chat('launching solo game...')
end

local function build_duel_args(role, session_id, my_role, peer_name, host_ip, port)
    local me = player_name() or 'player'
    local args = {
        '--duel',
        role,
        my_role,
        session_id,
        peer_name,
        bridge_dir(session_id, me),
    }

    if role == 'guest' then
        args[#args + 1] = host_ip
        args[#args + 1] = tostring(port or protocol.DEFAULT_PORT)
    else
        args[#args + 1] = tostring(port or protocol.DEFAULT_PORT)
    end

    return args
end

local function launch_duel(role, session_id, my_role, peer_name, host_ip, port)
    if duel_bridge.launch_game(build_duel_args(role, session_id, my_role, peer_name, host_ip, port)) then
        debug_chat('launching duel (' .. role .. ')...')
    else
        duel_bridge.shutdown('launch_failed')
    end
end

local function is_relay_connect(host)
    if not host or host == '' then
        return false
    end
    local lower = host:lower()
    if lower == DEFAULT_RELAY_HOST:lower() or lower == '145.241.251.131' then
        return true
    end
    if lower == RELAY_DOMAIN or lower:sub(-#('.' .. RELAY_DOMAIN)) == '.' .. RELAY_DOMAIN then
        return true
    end
    if relay_host_override and relay_host_override ~= false and host == relay_host_override then
        return true
    end
    return false
end

local function get_relay_host()
    if relay_host_override == false then
        return nil
    end
    return relay_host_override or DEFAULT_RELAY_HOST
end

local function relay_port_for(host)
    if protocol.should_use_wss(host) then
        return protocol.DEFAULT_WSS_PORT
    end
    return protocol.DEFAULT_PORT
end

local function start_relay_duel(session_id, local_name, peer_name, relay_host, port, tcp_role)
    local game_role = tcp_role == 'host' and 'challenger' or 'guest'
    local game_args = build_duel_args(tcp_role, session_id, game_role, peer_name, relay_host, port)
    if duel_bridge.start_relay(session_id, peer_name, tcp_role, relay_host, port, local_name, game_args) then
        debug_chat('waiting for relay (' .. tcp_role .. ')...')
    end
end

local function start_host_duel(session_id, challenger, guest, port)
    duel_bridge.start_host(session_id, guest, port, challenger)
    launch_duel('host', session_id, 'challenger', guest, nil, port)
end

local function start_guest_duel(session_id, guest, challenger, host_ip, port)
    if duel_bridge.start_guest(session_id, challenger, host_ip, port, guest) then
        launch_duel('guest', session_id, 'guest', challenger, host_ip, port)
    end
end

local function begin_duel_as_host(challenge)
    if duel_bridge.is_busy() then
        return
    end

    local relay_host = get_relay_host()
    if relay_host then
        start_relay_duel(challenge.session_id, challenge.challenger, challenge.guest, relay_host, relay_port_for(relay_host), 'host')
    else
        local host_ip = duel_bridge.get_connect_ip(host_connect_ip_override)
        start_host_duel(challenge.session_id, challenge.challenger, challenge.guest, port)
        send_ipc_handshake('CONNECT', challenge.session_id, host_ip, port)
    end
end

local function set_pending_challenge(session_id, challenger, guest)
    pending_challenge = {
        session_id = session_id,
        challenger = challenger,
        guest = guest,
        sent_at = os.clock(),
    }
end

local function notify_guest_challenge(session_id, challenger, guest)
    local session_key = session_id:lower()
    if notified_challenges[session_key] and pending_challenge and protocol.sessions_equal(pending_challenge.session_id, session_id) then
        set_pending_challenge(session_id, challenger, guest)
        return
    end

    set_pending_challenge(session_id, challenger, guest)
    notified_challenges[session_key] = true
    chat(challenger .. ' challenged you to a TetraMaster duel!')
    chat('Type //tm accept or //tm decline')
end

local function issue_challenge(target_name)
    if duel_bridge.is_busy() then
        chat('a duel session is still active or ending.')
        chat('Use //tm reset if you cannot start a new duel.')
        return
    end

    local ok, me_or_err = in_party_with(target_name)
    if not ok then
        chat(me_or_err)
        return
    end

    local me = me_or_err
    local session_id = protocol.make_session_id(me, target_name)
    set_pending_challenge(session_id, me, target_name)

    announce_challenge(me, target_name)
    send_ipc_handshake('CHALLENGE', session_id, me, target_name)
    chat('challenge sent to ' .. target_name .. '. Waiting for accept...')
    if not get_relay_host() then
        chat('host: allow TCP ' .. protocol.DEFAULT_PORT .. ' in Windows Firewall.')
        chat('and forward port ' .. protocol.DEFAULT_PORT .. ' on your router, or use Tailscale with //tm hostip <ip>.')
    end
end

local function accept_challenge()
    if not pending_challenge then
        chat('no pending duel challenge.')
        return
    end

    local me = player_name()
    if not me or me:lower() ~= pending_challenge.guest:lower() then
        chat('you are not the challenged player.')
        return
    end

    local challenge = pending_challenge
    pending_challenge = nil

    announce_accept(me)
    send_ipc_handshake('ACCEPT', challenge.session_id, me)

    local relay_host = get_relay_host()
    if relay_host then
        start_relay_duel(challenge.session_id, challenge.guest, challenge.challenger, relay_host, relay_port_for(relay_host), 'guest')
        debug_chat('accepted. Connecting to relay...')
    else
        pending_connect = challenge
        chat('accepted. Waiting for ' .. challenge.challenger .. ' to host the duel...')
    end
end

local function decline_challenge()
    if not pending_challenge then
        chat('no pending duel challenge.')
        return
    end

    local me = player_name()
    if not me or me:lower() ~= pending_challenge.guest:lower() then
        chat('you are not the challenged player.')
        return
    end

    local challenge = pending_challenge
    pending_challenge = nil
    announce_decline(me)
    send_ipc_handshake('DECLINE', challenge.session_id, challenge.challenger)
    chat('duel declined.')
end

local function handle_tm_message(msg)
    local me = player_name()
    if not me or not msg then
        return
    end

    if msg.kind == 'CHALLENGE' then
        if me:lower() ~= msg.arg2:lower() then
            return
        end

        notify_guest_challenge(msg.session, msg.arg1, msg.arg2)
        return
    end

    if msg.kind == 'ACCEPT' then
        if not pending_challenge or not protocol.sessions_equal(pending_challenge.session_id, msg.session) then
            return
        end

        if me:lower() ~= pending_challenge.challenger:lower() then
            return
        end

        local challenge = pending_challenge
        pending_challenge = nil
        begin_duel_as_host(challenge)
        return
    end

    if msg.kind == 'CONNECT' then
        if not pending_connect or not protocol.sessions_equal(pending_connect.session_id, msg.session) then
            return
        end

        if me:lower() ~= pending_connect.guest:lower() then
            return
        end

        local challenge = pending_connect
        pending_connect = nil

        local connect_host = msg.arg1
        local port = tonumber(msg.arg2) or relay_port_for(connect_host)
        if is_relay_connect(connect_host) then
            start_relay_duel(challenge.session_id, challenge.guest, challenge.challenger, connect_host, port, 'guest')
        else
            start_guest_duel(challenge.session_id, challenge.guest, challenge.challenger, connect_host, port)
        end
        return
    end

    if msg.kind == 'DECLINE' then
        if pending_challenge and protocol.sessions_equal(pending_challenge.session_id, msg.session) then
            if me:lower() == pending_challenge.challenger:lower() then
                pending_challenge = nil
                chat(msg.arg1 .. ' declined your duel.')
            end
        end
        return
    end

    if msg.kind == 'RESIGN' then
        if duel_bridge.is_active() and protocol.sessions_equal(duel_bridge.get_session_id(), msg.session) then
            duel_bridge.shutdown('opponent_left')
        end
    end
end

local function handle_friendly_accept(accepter)
    local me = player_name()
    if not me or not accepter or not pending_challenge then
        return
    end

    if me:lower() ~= pending_challenge.challenger:lower() then
        return
    end

    if pending_challenge.guest:lower() ~= accepter:lower() then
        return
    end

    local challenge = pending_challenge
    pending_challenge = nil
    begin_duel_as_host(challenge)
end

local function handle_friendly_decline(decliner)
    local me = player_name()
    if not me or not decliner or not pending_challenge then
        return
    end

    if me:lower() ~= pending_challenge.challenger:lower() then
        return
    end

    if pending_challenge.guest:lower() ~= decliner:lower() then
        return
    end

    pending_challenge = nil
    chat(decliner .. ' declined your duel.')
end

local function clear_duel_state()
    pending_challenge = nil
    pending_connect = nil
    notified_challenges = {}
end

duel_bridge.set_session_end_handler(function(reason)
    clear_duel_state()

    if reason == 'opponent_left' then
        chat('duel ended. Your opponent closed the game.')
    elseif reason == 'connection_closed' then
        chat('duel ended. Relay connection failed.')
    elseif reason == 'manual_resign' or reason == 'force_reset' then
        chat('duel session ended.')
    end
end)

local function handle_incoming_text(text)
    local challenger, guest = protocol.parse_friendly_challenge(text)
    if challenger and guest then
        local me = player_name()
        if me and me:lower() == guest:lower() then
            notify_guest_challenge(protocol.make_session_id(challenger, guest), challenger, guest)
        end
        return
    end

    local accepter = protocol.parse_friendly_accept(text)
    if accepter then
        handle_friendly_accept(accepter)
        return
    end

    local decliner = protocol.parse_friendly_decline(text)
    if decliner then
        handle_friendly_decline(decliner)
    end
end

local function handle_command(command, ...)
    command = command and command:lower() or ''
    local args = {...}

    if command == '' or command == 'play' or command == 'start' then
        launch_solo()
    elseif command == 'duel' then
        if not args[1] then
            chat('usage: //tm duel <player_name>')
            return
        end
        issue_challenge(args[1])
    elseif command == 'hostip' then
        if not args[1] or args[1]:lower() == 'clear' then
            host_connect_ip_override = nil
            chat('host connect IP cleared (auto-detect on next duel).')
        else
            host_connect_ip_override = args[1]
            chat('host will advertise ' .. args[1] .. ' when the duel starts.')
        end
    elseif command == 'relayhost' then
        if not args[1] or args[1]:lower() == 'clear' then
            relay_host_override = nil
            chat('relay host reset to default (' .. DEFAULT_RELAY_HOST .. ').')
        elseif args[1]:lower() == 'direct' then
            relay_host_override = false
            chat('using direct host connection (no relay).')
        else
            relay_host_override = args[1]
            chat('relay host set to ' .. args[1])
        end
    elseif command == 'accept' then
        accept_challenge()
    elseif command == 'decline' then
        decline_challenge()
    elseif command == 'resign' then
        if duel_bridge.is_busy() then
            local session_id = duel_bridge.get_session_id()
            if session_id then
                send_ipc_handshake('RESIGN', session_id, player_name() or 'unknown')
            end
            duel_bridge.shutdown('manual_resign')
            chat('you resigned from the duel.')
        else
            chat('no active duel.')
        end
    elseif command == 'reset' then
        if duel_bridge.get_session_id() then
            send_ipc_handshake('RESIGN', duel_bridge.get_session_id(), player_name() or 'unknown')
        end
        duel_bridge.force_reset(true)
        clear_duel_state()
        chat('TetraMaster reset. Reload with //lua r TetraMaster if play/duel still fails.')
    elseif command == 'debug' then
        debug_mode = not debug_mode
        duel_bridge.set_debug(debug_mode)
        chat('debug mode ' .. (debug_mode and 'on' or 'off') .. '.')
    elseif command == 'help' then
        chat('//tm play - solo game')
        chat('//tm duel <name> - challenge a party member')
        chat('//tm relayhost <host> - relay server (default ' .. DEFAULT_RELAY_HOST .. ', uses wss on domains)')
        chat('//tm relayhost direct - connect guest to host PC instead')
        chat('//tm relayhost clear - reset relay host to default')
        chat('//tm hostip <ip> - host advertises this IP (direct mode / Tailscale)')
        chat('//tm hostip clear - use auto IP again')
        chat('//tm accept / //tm decline - respond to a challenge')
        chat('//tm resign - leave an active duel')
        chat('//tm reset - force-clear a stuck duel (closes TetraMaster.exe)')
        chat('//tm debug - toggle connection progress messages')
        chat('//tm help - show this message')
    else
        chat('unknown command. Use //tm help')
    end
end

windower.register_event('addon command', function(command, ...)
    handle_command(command, ...)
end)

windower.register_event('unhandled command', function(command, ...)
    if command:lower() == 'tm' then
        handle_command(({...})[1], select(2, ...))
    end
end)

windower.register_event('ipc message', function(msg)
    handle_tm_message(protocol.parse_ipc(msg))
end)

windower.register_event('incoming text', function(original, modified, mode)
    handle_incoming_text(modified or original)
end)

windower.register_event('prerender', function()
    duel_bridge.tick()
end)

windower.register_event('logout', function()
    if duel_bridge.is_busy() then
        duel_bridge.force_reset(false)
    end
    clear_duel_state()
end)

windower.register_event('load', function()
    chat('loaded. //tm play or //tm duel <party member>')
end)
