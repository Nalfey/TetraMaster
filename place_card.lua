ARROW_DIRECTIONS = {
  { name = "up",        dx = 0,  dy = -1, counter = "down" },
  { name = "down",      dx = 0,  dy = 1,  counter = "up" },
  { name = "left",      dx = -1, dy = 0,  counter = "right" },
  { name = "right",     dx = 1,  dy = 0,  counter = "left" },
  { name = "upleft",    dx = -1, dy = -1, counter = "downright" },
  { name = "upright",   dx = 1,  dy = -1, counter = "downleft" },
  { name = "downleft",  dx = -1, dy = 1,  counter = "upright" },
  { name = "downright", dx = 1,  dy = 1,  counter = "upleft" },
}

placement = {
  active = false,
  phase = "idle",
  placed_x = 0,
  placed_y = 0,
  placed_card = nil,
  pending_battles = {},
  select_index = 1,
  on_complete = nil,
  continue_after_battle = false,
  network = nil,
  awaiting_remote_choice = false,
  remote_battle_queue = {},
  pending_remote_battles = {},
  pending_remote_select = nil,
}

local function get_card_at(x, y)
  if x < 1 or x > 4 or y < 1 or y > 4 then
    return nil
  end

  if not card_grid[x][y] then
    return nil
  end

  if card_grid[x][y].side == "blue" or card_grid[x][y].side == "red" then
    return card_grid[x][y]
  end

  return nil
end

local function stat_min(a, b)
  return math.min(a, b)
end

local function stat_max(a, b)
  return math.max(a, b)
end

local function stat_min3(a, b, c)
  return math.min(a, math.min(b, c))
end

local function stat_max3(a, b, c)
  return math.max(a, math.max(b, c))
end

local function get_battle_stat_values(attacker, defender)
  if attacker.type == "P" then
    return attacker.hidden_attack, defender.hidden_physical_defense
  end

  if attacker.type == "M" then
    return attacker.hidden_attack, defender.hidden_magical_defense
  end

  if attacker.type == "X" then
    return attacker.hidden_attack,
      stat_min(defender.hidden_physical_defense, defender.hidden_magical_defense)
  end

  if attacker.type == "A" then
    return stat_max3(attacker.hidden_attack, attacker.hidden_physical_defense, attacker.hidden_magical_defense),
      stat_min3(defender.hidden_attack, defender.hidden_physical_defense, defender.hidden_magical_defense)
  end

  return attacker.hidden_attack, defender.hidden_physical_defense
end

function roll_card_battle(attacker, defender)
  local attacker_power, defender_power = get_battle_stat_values(attacker, defender)
  local actual_attack_score = math.random(0, attacker_power)
  local actual_defend_score = math.random(0, defender_power)

  local attacker_final = attacker_power - actual_attack_score
  local defender_final = defender_power - actual_defend_score

  return {
    attacker_power = attacker_power,
    defender_power = defender_power,
    attacker_final = attacker_final,
    defender_final = defender_final,
    attacker_wins = attacker_final > defender_final,
  }
end

local function maybe_upgrade_battle_class(card)
  if card.type == "P" or card.type == "M" then
    if math.random(1, 64) == 1 then
      card.type = "X"
    end
  elseif card.type == "X" then
    if math.random(1, 128) == 1 then
      card.type = "A"
    end
  end
end

local function collect_arrow_targets(ox, oy, winner_side, seen)
  local flips = {}
  local card = get_card_at(ox, oy)

  if not card or not card.arrows then
    return flips
  end

  for _, dir in ipairs(ARROW_DIRECTIONS) do
    if card.arrows[dir.name] then
      local nx = ox + dir.dx
      local ny = oy + dir.dy
      local key = nx .. "," .. ny

      if not seen[key] then
        local target = get_card_at(nx, ny)
        if target and target.side ~= winner_side then
          seen[key] = true
          flips[#flips + 1] = {
            gx = nx,
            gy = ny,
            card = target,
            from_dx = -dir.dx,
            from_dy = -dir.dy,
            origin_gx = ox,
            origin_gy = oy,
          }
        end
      end
    end
  end

  return flips
end

-- Combos only follow a battle win: one wave from the loser and the attacker.
local function collect_battle_win_combos(attacker_x, attacker_y, defender_x, defender_y, winner_side)
  local flips = {}
  local seen = { [defender_x .. "," .. defender_y] = true }

  local function append_from(ox, oy)
    for _, flip in ipairs(collect_arrow_targets(ox, oy, winner_side, seen)) do
      flips[#flips + 1] = flip
    end
  end

  append_from(defender_x, defender_y)
  append_from(attacker_x, attacker_y)

  return flips
end

local function collect_reverse_combo_flips(px, py, loser_side)
  local flips = {}
  local placed = get_card_at(px, py)

  if not placed or not placed.arrows then
    return flips
  end

  for _, dir in ipairs(ARROW_DIRECTIONS) do
    if placed.arrows[dir.name] then
      local nx = px + dir.dx
      local ny = py + dir.dy
      local adjacent = get_card_at(nx, ny)

      if adjacent and adjacent ~= placed and adjacent.side == loser_side then
        flips[#flips + 1] = {
          gx = nx,
          gy = ny,
          card = adjacent,
          from_dx = -dir.dx,
          from_dy = -dir.dy,
        }
      end
    end
  end

  return flips
end

local function build_instant_capture_steps(gx, gy, card, winner_side)
  return {
    { type = "flash", gx = gx, gy = gy, card = card, new_side = winner_side },
  }
end

local function build_battle_win_capture_steps(attacker_x, attacker_y, defender_x, defender_y, defender, winner_side)
  local steps = {
    { type = "flash", gx = defender_x, gy = defender_y, card = defender, new_side = winner_side },
  }

  local flips = collect_battle_win_combos(attacker_x, attacker_y, defender_x, defender_y, winner_side)
  if #flips > 0 then
    play_sound("combo_woosh")
  end

  for index, flip in ipairs(flips) do
    steps[#steps + 1] = {
      type = "combo",
      origin_gx = flip.origin_gx,
      origin_gy = flip.origin_gy,
      count = index,
      gx = flip.gx,
      gy = flip.gy,
      card = flip.card,
      new_side = winner_side,
      from_dx = flip.from_dx,
      from_dy = flip.from_dy,
    }
  end

  return steps
end

local function build_reverse_loss_steps(px, py, placed_card, winner_side)
  local loser_side = placed_card.side
  local steps = {}
  local flips = collect_reverse_combo_flips(px, py, loser_side)

  if #flips > 0 then
    play_sound("combo_woosh")
  end

  for index, flip in ipairs(flips) do
    steps[#steps + 1] = {
      type = "combo",
      origin_gx = px,
      origin_gy = py,
      count = index,
      gx = flip.gx,
      gy = flip.gy,
      card = flip.card,
      new_side = winner_side,
      from_dx = flip.from_dx,
      from_dy = flip.from_dy,
    }
  end

  steps[#steps + 1] = {
    type = "flash",
    gx = px,
    gy = py,
    card = placed_card,
    new_side = winner_side,
  }

  return steps
end

local function run_capture_steps(steps, on_complete)
  start_capture_sequence(steps, on_complete)
end

local function reverse_combo_on_loss(placed_card, px, py, winner_side, on_complete)
  local steps = build_reverse_loss_steps(px, py, placed_card, winner_side)
  run_capture_steps(steps, function()
    play_capture_sound(winner_side)
    if on_complete then
      on_complete()
    end
  end)
end

local function is_mutual_battle(placed_card, px, py, dir)
  local defender = get_card_at(px + dir.dx, py + dir.dy)
  if not defender or defender.side == placed_card.side then
    return false
  end

  if not placed_card.arrows[dir.name] or not defender.arrows[dir.counter] then
    return false
  end

  return true
end

local function collect_pending_battles(placed_card, px, py)
  local battles = {}

  for _, dir in ipairs(ARROW_DIRECTIONS) do
    if is_mutual_battle(placed_card, px, py, dir) then
      table.insert(battles, {
        def_x = px + dir.dx,
        def_y = py + dir.dy,
        attack_dir = dir.name,
        counter_dir = dir.counter,
      })
    end
  end

  return battles
end

local function refresh_pending_battles()
  local placed_card = placement.placed_card
  local px, py = placement.placed_x, placement.placed_y
  placement.pending_battles = collect_pending_battles(placed_card, px, py)
end

local function apply_instant_capture(attacker, defender, gx, gy, on_complete)
  local steps = build_instant_capture_steps(gx, gy, defender, attacker.side)
  play_sound("flip_card")
  run_capture_steps(steps, function()
    play_capture_sound(attacker.side)
    if on_complete then
      on_complete()
    end
  end)
end

local function schedule_placement_continue()
  placement.continue_after_battle = true
end

local function resolve_battle(placed_card, px, py, battle)
  if is_battle_anim_active() or is_capture_fx_active() then
    schedule_placement_continue()
    return
  end

  local defender = get_card_at(battle.def_x, battle.def_y)
  local dir = {
    name = battle.attack_dir,
    dx = battle.def_x - px,
    dy = battle.def_y - py,
    counter = battle.counter_dir,
  }

  if not defender or not is_mutual_battle(placed_card, px, py, dir) then
    refresh_pending_battles()
    schedule_placement_continue()
    return
  end

  local result
  if placement.network and placement.network.remote then
    result = placement.remote_battle_queue[1]
    if not result then
      schedule_placement_continue()
      return
    end
    table.remove(placement.remote_battle_queue, 1)
  else
    result = roll_card_battle(placed_card, defender)
    if placement.network and placement.network.on_battle then
      placement.network.on_battle({
        type = "battle",
        px = px,
        py = py,
        dx = battle.def_x,
        dy = battle.def_y,
        result = result,
      })
    end
  end

  start_battle_animation(px, py, battle.def_x, battle.def_y, result, function()
    local function after_capture_fx()
      if result.attacker_wins then
        maybe_upgrade_battle_class(placed_card)
      else
        maybe_upgrade_battle_class(defender)
      end

      refresh_pending_battles()
      schedule_placement_continue()
    end

    if result.attacker_wins then
      play_sound("flip_card")
      run_capture_steps(build_battle_win_capture_steps(px, py, battle.def_x, battle.def_y, defender, placed_card.side), function()
        play_capture_sound(placed_card.side)
        after_capture_fx()
      end)
    else
      reverse_combo_on_loss(placed_card, px, py, defender.side, after_capture_fx)
    end
  end)
end

function is_placement_resolving()
  return placement.active
end

function is_match_resolution_active()
  return placement.active or is_battle_anim_active() or is_capture_fx_active()
end

function is_battle_select_active()
  return placement.active and placement.phase == "select_battle"
end

function get_battle_select_options()
  return placement.pending_battles
end

function get_battle_select_index()
  return placement.select_index
end

function cycle_battle_select(delta)
  if not is_battle_select_active() or #placement.pending_battles == 0 then
    return
  end

  placement.select_index = ((placement.select_index - 1 + delta) % #placement.pending_battles) + 1
  play_sound("cursor")
end

function confirm_battle_select()
  if not is_battle_select_active() then
    return
  end

  local battle = placement.pending_battles[placement.select_index]
  if not battle then
    return
  end

  placement.phase = "battle"
  resolve_battle(placement.placed_card, placement.placed_x, placement.placed_y, battle)
end

function begin_next_battle()
  if is_battle_anim_active() or is_capture_fx_active() then
    schedule_placement_continue()
    return
  end

  if placement.network and placement.network.remote then
    flush_pending_remote_messages()
    if #placement.pending_battles == 0 then
      finish_placement()
    end
    return
  end

  if #placement.pending_battles == 0 then
    finish_placement()
    return
  end

  if #placement.pending_battles > 1 and not hands[current_turn].ai_controlled then
    if placement.network and placement.network.await_remote_choice then
      placement.phase = "select_battle"
      placement.awaiting_remote_choice = true
      placement.network.await_remote_choice(#placement.pending_battles)
      return
    end

    placement.phase = "select_battle"
    placement.select_index = math.min(placement.select_index, #placement.pending_battles)
    return
  end

  local battle_index = 1
  if hands[current_turn].ai_controlled and #placement.pending_battles > 1 then
    battle_index = math.random(1, #placement.pending_battles)
  end

  local battle = placement.pending_battles[battle_index]
  placement.phase = "battle"
  resolve_battle(placement.placed_card, placement.placed_x, placement.placed_y, battle)
end

function process_placement_step()
  if is_battle_anim_active() or is_capture_fx_active() then
    return
  end

  if placement.phase == "battle" or placement.continue_after_battle then
    placement.continue_after_battle = false
    begin_next_battle()
  end
end

function finish_placement()
  placement.active = false
  placement.phase = "idle"
  placement.pending_battles = {}
  placement.continue_after_battle = false
  placement.awaiting_remote_choice = false
  placement.remote_battle_queue = {}
  placement.pending_remote_battles = {}
  placement.pending_remote_select = nil

  local callback = placement.on_complete
  local network = placement.network
  placement.on_complete = nil
  placement.network = nil

  if callback then
    callback(network)
  end
end

local function process_instant_captures(placed_card, px, py, on_complete)
  local captures = {}

  for _, dir in ipairs(ARROW_DIRECTIONS) do
    if placed_card.arrows[dir.name] then
      local defender = get_card_at(px + dir.dx, py + dir.dy)
      if defender and defender.side ~= placed_card.side and not defender.arrows[dir.counter] then
        captures[#captures + 1] = {
          gx = px + dir.dx,
          gy = py + dir.dy,
          defender = defender,
        }
      end
    end
  end

  local index = 1

  local function next_capture()
    if index > #captures then
      if on_complete then
        on_complete()
      end
      return
    end

    local capture = captures[index]
    index = index + 1
    apply_instant_capture(placed_card, capture.defender, capture.gx, capture.gy, next_capture)
  end

  next_capture()
end

function start_placement_resolution(px, py, card, on_complete)
  placement.active = true
  placement.phase = "captures"
  placement.placed_x = px
  placement.placed_y = py
  placement.placed_card = card
  placement.select_index = 1
  placement.on_complete = on_complete

  process_instant_captures(card, px, py, function()
    refresh_pending_battles()
    begin_next_battle()
  end)
end

local function apply_remote_battle_now(msg)
  local battle
  for _, candidate in ipairs(placement.pending_battles) do
    if candidate.def_x == msg.dx and candidate.def_y == msg.dy then
      battle = candidate
      break
    end
  end

  if not battle then
    return false
  end

  placement.remote_battle_queue = { msg.result }
  placement.phase = "battle"
  resolve_battle(placement.placed_card, placement.placed_x, placement.placed_y, battle)
  return true
end

function flush_pending_remote_messages()
  if not placement.network or not placement.network.remote then
    return
  end

  if is_battle_anim_active() or is_capture_fx_active() or not placement.active then
    return
  end

  if placement.pending_remote_select and not is_battle_select_active() then
    local count = placement.pending_remote_select
    placement.pending_remote_select = nil
    set_remote_battle_options(count)
    return
  end

  while #placement.pending_remote_battles > 0 do
    if is_battle_anim_active() or is_capture_fx_active() then
      return
    end

    local msg = table.remove(placement.pending_remote_battles, 1)
    if apply_remote_battle_now(msg) then
      return
    end

    table.insert(placement.pending_remote_battles, 1, msg)
    return
  end
end

function apply_remote_battle(msg)
  if not placement.network or not placement.network.remote then
    return
  end

  if not placement.active or is_battle_anim_active() or is_capture_fx_active() then
    placement.pending_remote_battles[#placement.pending_remote_battles + 1] = msg
    return
  end

  if not apply_remote_battle_now(msg) then
    placement.pending_remote_battles[#placement.pending_remote_battles + 1] = msg
  end
end

function queue_or_apply_remote_select_battle(count)
  if not placement.network or not placement.network.remote then
    return
  end

  if not placement.active or is_battle_anim_active() or is_capture_fx_active() then
    placement.pending_remote_select = count
    return
  end

  set_remote_battle_options(count)
end

function set_remote_battle_options(count)
  placement.select_index = 1
  placement.phase = "select_battle"
end

function apply_remote_battle_choice(index)
  if not placement.awaiting_remote_choice then
    return
  end

  placement.awaiting_remote_choice = false
  placement.select_index = index
  confirm_battle_select()
end

function place_card(x, y, card, on_complete, opts)
  if not card then
    return
  end

  placement.network = opts

  card_grid[x][y] = card
  play_sound("put")

  if not card.arrows then
    if on_complete then
      on_complete()
    end
    placement.network = nil
    return
  end

  start_placement_resolution(x, y, card, on_complete)
end

function update_placement(dt)
  update_battle_animation(dt)
  update_capture_fx(dt)

  if placement.continue_after_battle and not is_battle_anim_active() and not is_capture_fx_active() then
    process_placement_step()
  end

  flush_pending_remote_messages()
end
