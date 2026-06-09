local bridge = require("bridge")
local protocol = require("protocol")

DUEL = {
  active = false,
  network_role = nil,
  player_role = nil,
  peer_name = "",
  session_id = "",
  is_host = false,
  connected = false,
  waiting = false,
  current_turn_role = nil,
  pending_select = false,
  match_ready = false,
}

local function role_to_local_side(role)
  if role == DUEL.player_role then
    return "blue"
  end
  return "red"
end

local function local_side_to_role(side)
  if side == "blue" then
    return DUEL.player_role
  end

  if DUEL.player_role == "challenger" then
    return "guest"
  end
  return "challenger"
end

function is_duel_active()
  return DUEL.active
end

function is_duel_host()
  return DUEL.is_host
end

function is_local_duel_turn()
  if not DUEL.active or not DUEL.current_turn_role then
    return false
  end
  return DUEL.current_turn_role == DUEL.player_role
end

function duel_waiting()
  return DUEL.waiting
end

function duel_peer_name()
  return DUEL.peer_name
end

local function snapshot_card(card, side_role)
  local arrows = {}
  for name, enabled in pairs(card.arrows) do
    if enabled then
      arrows[#arrows + 1] = name
    end
  end

  return {
    uid = card.uid,
    card_id = card.card_id,
    name = card.name,
    attack = card.attack,
    type = card.type,
    physical_defense = card.physical_defense,
    magical_defense = card.magical_defense,
    attack_string = card.attack_string,
    physical_defense_string = card.physical_defense_string,
    magical_defense_string = card.magical_defense_string,
    side_role = side_role or local_side_to_role(card.side),
    arrows = arrows,
  }
end

local function card_from_snapshot(snapshot)
  return Card.from_snapshot(snapshot, role_to_local_side(snapshot.side_role))
end

local function stamp_hand_uids(cards, start_id)
  local next_id = start_id
  for _, card in ipairs(cards) do
    card.uid = next_id
    next_id = next_id + 1
  end
  return next_id
end

local function snapshot_cell(cell)
  if not cell then
    return { kind = "empty" }
  end

  if cell.card_id then
    return { kind = "card", card = snapshot_card(cell) }
  end

  return { kind = "block", side = cell.side }
end

local function snapshot_grid()
  local cells = {}

  for y = 1, 4 do
    for x = 1, 4 do
      cells[#cells + 1] = snapshot_cell(card_grid[x][y])
    end
  end

  return cells
end

local function table_at(tbl, index)
  return tbl[index] or tbl[tostring(index)]
end

local function snapshot_list(snapshots)
  local list = {}

  if not snapshots then
    return list
  end

  for i = 1, #snapshots do
    list[#list + 1] = snapshots[i]
  end

  if #list == 0 then
    for i = 1, 5 do
      local snap = table_at(snapshots, i)
      if snap then
        list[#list + 1] = snap
      end
    end
  end

  return list
end

local function apply_grid_snapshot(cells)
  init_empty_grid()

  for index = 1, 16 do
    local cell = table_at(cells, index)
    local y = math.floor((index - 1) / 4) + 1
    local x = ((index - 1) % 4) + 1

    if cell then
      if cell.kind == "block" then
        card_grid[x][y] = { side = cell.side }
      elseif cell.kind == "card" then
        card_grid[x][y] = card_from_snapshot(cell.card)
      end
    end
  end
end

local function build_hand_from_snapshots(snapshots, local_side, hidden)
  local hand = Hand:create_empty(local_side, { hidden = hidden })

  for _, snapshot in ipairs(snapshot_list(snapshots)) do
    table.insert(hand.cards, card_from_snapshot(snapshot))
  end

  return hand
end

local function seed_host_rng()
  local seed = 0

  for i = 1, #DUEL.session_id do
    seed = (seed * 31 + string.byte(DUEL.session_id, i)) % 2147483646
  end

  math.randomseed(seed + os.time())
end

local function send(msg)
  bridge.send(msg)
end

local function duel_force_quit()
  DUEL.active = false
  bridge.clear_heartbeat()
  love.event.quit()
end

function duel_send_resign()
  if DUEL.active then
    send({ type = "disconnect", reason = "window_closed" })
    bridge.clear_heartbeat()
    bridge.write_closed_flag()
  end
end

local function generate_match_state()
  seed_host_rng()
  init_grid()

  local challenger_hand = Hand:new("blue", false)
  local guest_hand = Hand:new("red", false, { hidden = true })

  local next_uid = stamp_hand_uids(challenger_hand.cards, 1)
  stamp_hand_uids(guest_hand.cards, next_uid)

  local challenger_snapshots = {}
  for _, card in ipairs(challenger_hand.cards) do
    table.insert(challenger_snapshots, snapshot_card(card, "challenger"))
  end

  local guest_snapshots = {}
  for _, card in ipairs(guest_hand.cards) do
    table.insert(guest_snapshots, snapshot_card(card, "guest"))
  end

  local coin_result = math.random(1, 2) == 1 and 4 or 8
  local first_role = coin_result == 8 and "challenger" or "guest"

  return {
    cells = snapshot_grid(),
    challenger_hand = challenger_snapshots,
    guest_hand = guest_snapshots,
    coin_result = coin_result,
    first_turn = first_role,
  }
end

local function apply_match_state(state)
  if not state then
    return
  end

  if state.cells then
    apply_grid_snapshot(state.cells)
  end

  if DUEL.player_role == "challenger" then
    hands = {
      ["blue"] = build_hand_from_snapshots(state.challenger_hand, "blue", false),
      ["red"] = build_hand_from_snapshots(state.guest_hand, "red", true),
    }
  else
    hands = {
      ["blue"] = build_hand_from_snapshots(state.guest_hand, "blue", false),
      ["red"] = build_hand_from_snapshots(state.challenger_hand, "red", true),
    }
  end

  DUEL.current_turn_role = state.first_turn
  current_turn = role_to_local_side(state.first_turn)
  DUEL.match_ready = true
  DUEL.waiting = false
  reset_keyboard_focus()
  start_coin_toss_forced(state.coin_result)
end

local function host_begin_match(rematch)
  local state = generate_match_state()
  send({
    type = rematch and "rematch_start" or "match_start",
    state = state,
  })
  apply_match_state(state)
end

local function host_handle_place_intent(msg)
  if not DUEL.is_host or msg.role ~= DUEL.current_turn_role then
    return
  end

  local local_side = role_to_local_side(msg.role)
  local hand = hands[local_side]
  local card = hand.cards[msg.hand_index]

  if not card or card_grid[msg.gx][msg.gy] ~= nil then
    return
  end

  current_turn = local_side
  duel_host_place_card(msg.gx, msg.gy, card, hand, msg.hand_index)
end

local function find_duel_arg_index(args)
  for i = 1, #args do
    if args[i] == "--duel" then
      return i
    end
  end
  return nil
end

function duel_init_from_args(argv)
  local args = argv or arg or {}
  local idx = find_duel_arg_index(args)

  if not idx then
    DUEL.active = false
    return false
  end

  DUEL.active = true
  DUEL.network_role = args[idx + 1]
  DUEL.player_role = args[idx + 2]
  DUEL.session_id = args[idx + 3]
  DUEL.peer_name = args[idx + 4]
  local sync_dir = args[idx + 5]

  DUEL.is_host = DUEL.network_role == "host"
  DUEL.waiting = true
  DUEL.connected = false
  DUEL.match_ready = false

  bridge.init(sync_dir:gsub("\\", "/"))
  return true
end

function duel_start_if_ready(game)
  if not DUEL.active or not DUEL.is_host or not DUEL.connected or DUEL.match_ready then
    return
  end

  host_begin_match(false)
  game:gotoState("CoinToss")
  game:load()
end

function duel_auto_rematch(game)
  if not DUEL.active or not DUEL.is_host or not game then
    return
  end

  host_begin_match(true)
  game:gotoState("CoinToss")
  game:load()
end

function duel_host_place_card(gx, gy, card, hand, hand_index)
  hand_index = hand_index or hand:index_of(card)

  send({
    type = "place_card",
    role = local_side_to_role(hand.side),
    gx = gx,
    gy = gy,
    hand_index = hand_index,
    card = snapshot_card(card),
  })

  place_card(gx, gy, card, function()
    hand:remove_card(card)
    turn_end()
    duel_notify_turn_after_placement()
  end, {
    on_battle = function(battle_msg)
      send(battle_msg)
    end,
    await_remote_choice = function(count)
      send({
        type = "select_battle",
        count = count,
        role = DUEL.current_turn_role,
      })
    end,
  })
end

function duel_notify_turn_after_placement()
  if not DUEL.is_host then
    return
  end

  DUEL.current_turn_role = local_side_to_role(current_turn)
  send({
    type = "turn",
    role = DUEL.current_turn_role,
  })
end

function duel_on_local_place(gx, gy, hand_index, hand, card)
  if not is_local_duel_turn() then
    return
  end

  if DUEL.is_host then
    card = card or hand.cards[hand_index]
    if not card then
      return
    end
    duel_host_place_card(gx, gy, card, hand, hand_index)
    return
  end

  send({
    type = "place_intent",
    role = DUEL.player_role,
    gx = gx,
    gy = gy,
    hand_index = hand_index,
  })
end

function duel_on_battle_choice(index)
  if DUEL.is_host or not is_local_duel_turn() then
    return
  end

  send({
    type = "battle_choice",
    role = DUEL.player_role,
    index = index,
  })
end

local function remove_card_from_hand(hand, msg)
  if msg.hand_index then
    local held = hand.cards[msg.hand_index]
    if held and (not msg.card.uid or held.uid == tonumber(msg.card.uid)) then
      hand:remove_card_at_index(msg.hand_index)
      return
    end
  end

  if msg.card and msg.card.uid then
    for i, held in ipairs(hand.cards) do
      if held.uid == tonumber(msg.card.uid) then
        hand:remove_card_at_index(i)
        return
      end
    end
  end
end

local function guest_apply_place_card(msg)
  local local_side = role_to_local_side(msg.role)
  local hand = hands[local_side]

  remove_card_from_hand(hand, msg)

  local card = card_from_snapshot(msg.card)
  current_turn = local_side

  place_card(msg.gx, msg.gy, card, function()
    keyboard_focus.area = "hand"
    reset_keyboard_focus()
  end, {
    remote = true,
  })
end

local function guest_handle_message(msg)
  if msg.type == "hello" then
    DUEL.connected = true
    return
  end

  if msg.type == "match_start" or msg.type == "rematch_start" then
    DUEL.connected = true
    if msg.state then
      apply_match_state(msg.state)
      if Game then
        Game:gotoState("CoinToss")
        Game:load()
      end
    end
    return
  end

  if msg.type == "place_card" then
    guest_apply_place_card(msg)
    return
  end

  if msg.type == "battle" then
    apply_remote_battle(msg)
    return
  end

  if msg.type == "select_battle" then
    DUEL.pending_select = true
    set_remote_battle_options(msg.count)
    return
  end

  if msg.type == "turn" then
    DUEL.current_turn_role = msg.role
    current_turn = role_to_local_side(msg.role)
    DUEL.pending_select = false
    return
  end

  if msg.type == "game_over" then
    DUEL.waiting = false
    if Game then
      Game:gotoState("EndGame")
      Game:load()
    end
    return
  end

  if msg.type == "resign" or msg.type == "disconnect" then
    duel_force_quit()
  end
end

local function host_handle_message(msg)
  if msg.type == "peer_connected" then
    DUEL.connected = true
    duel_start_if_ready(Game)
    return
  end

  if msg.type == "place_intent" then
    host_handle_place_intent(msg)
    return
  end

  if msg.type == "battle_choice" then
    apply_remote_battle_choice(msg.index)
    return
  end

  if msg.type == "resign" or msg.type == "disconnect" then
    duel_force_quit()
  end
end

function duel_poll()
  if not DUEL.active then
    return
  end

  bridge.write_heartbeat()

  local messages = bridge.poll()
  for _, msg in ipairs(messages) do
    if DUEL.is_host then
      host_handle_message(msg)
    else
      guest_handle_message(msg)
    end
  end
end

function duel_send_game_over()
  if DUEL.is_host then
    send({ type = "game_over" })
  end
end
