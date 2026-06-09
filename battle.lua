battle_anim = {
  active = false,
  phase = "idle",
  elapsed = 0,
  countdown_elapsed = 0,
  attacker_gx = 0,
  attacker_gy = 0,
  defender_gx = 0,
  defender_gy = 0,
  attacker_power = 0,
  defender_power = 0,
  attacker_final = 0,
  defender_final = 0,
  attacker_wins = false,
  dir_x = 0,
  dir_y = 0,
  explosion_x = 0,
  explosion_y = 0,
  explosion_frame = 1,
  on_complete = nil,
}

local APPEAR_DURATION = 0.12
local APPROACH_DURATION = 0.16
local RETURN_DURATION = 0.11
local EXPLOSION_FRAME_DURATION = 0.05
local COUNTDOWN_ACTIVE = 0.42
local RESULT_HOLD = 0.28
local MAX_TRANSLATION = 5.5

local function ease_out_quad(t)
  return 1 - (1 - t) * (1 - t)
end

local function ease_in_cubic(t)
  return t * t * t
end

local function ease_in_quad(t)
  return t * t
end

local function explosion_duration()
  return #explosion_frames * EXPLOSION_FRAME_DURATION
end

local function countdown_active_duration()
  return explosion_duration() + RETURN_DURATION + COUNTDOWN_ACTIVE
end

local function total_battle_resolve_duration()
  return countdown_active_duration() + RESULT_HOLD
end

local function compute_clash_direction(attacker_gx, attacker_gy, defender_gx, defender_gy)
  local ax, ay, aw, ah = get_grid_tile_screen_rect(attacker_gx, attacker_gy)
  local dx, dy, dw, dh = get_grid_tile_screen_rect(defender_gx, defender_gy)
  local screen_dx = (dx + dw / 2) - (ax + aw / 2)
  local screen_dy = (dy + dh / 2) - (ay + ah / 2)
  local length = math.sqrt(screen_dx * screen_dx + screen_dy * screen_dy)

  if length == 0 then
    return 1, 0
  end

  return screen_dx / length, screen_dy / length
end

local function get_clash_point(progress)
  local ax, ay, dx, dy = battle_anim.attacker_gx, battle_anim.attacker_gy,
    battle_anim.defender_gx, battle_anim.defender_gy
  local ax_x, ax_y, aw, ah = get_grid_tile_screen_rect(ax, ay)
  local dx_x, dx_y, dw, dh = get_grid_tile_screen_rect(dx, dy)
  local acx = ax_x + aw / 2 + battle_anim.dir_x * MAX_TRANSLATION * progress
  local acy = ax_y + ah / 2 + battle_anim.dir_y * MAX_TRANSLATION * progress
  local dcx = dx_x + dw / 2 - battle_anim.dir_x * MAX_TRANSLATION * progress
  local dcy = dx_y + dh / 2 - battle_anim.dir_y * MAX_TRANSLATION * progress
  return (acx + dcx) / 2, (acy + dcy) / 2
end

local function is_countdown_phase()
  return battle_anim.phase == "explosion"
    or battle_anim.phase == "return"
    or battle_anim.phase == "countdown"
    or battle_anim.phase == "result_hold"
end

local function get_final_display_values()
  if battle_anim.attacker_wins then
    return battle_anim.attacker_final, 0
  end

  return 0, battle_anim.defender_final
end

local function get_battle_display_values()
  if battle_anim.phase == "appear" or battle_anim.phase == "approach" then
    return battle_anim.attacker_power, battle_anim.defender_power
  end

  if battle_anim.phase == "result_hold" then
    return get_final_display_values()
  end

  if not is_countdown_phase() then
    return battle_anim.attacker_power, battle_anim.defender_power
  end

  if battle_anim.countdown_elapsed >= countdown_active_duration() then
    return get_final_display_values()
  end

  local t = math.min(1, battle_anim.countdown_elapsed / countdown_active_duration())
  local eased = ease_in_cubic(t)

  if battle_anim.attacker_wins then
    local defender_display = math.max(0, math.floor(battle_anim.defender_power * (1 - eased)))
    local attacker_display = math.max(
      battle_anim.attacker_final,
      math.floor(battle_anim.attacker_power - (battle_anim.attacker_power - battle_anim.attacker_final) * eased)
    )
    return attacker_display, defender_display
  end

  local attacker_display = math.max(0, math.floor(battle_anim.attacker_power * (1 - eased)))
  local defender_display = math.max(
    battle_anim.defender_final,
    math.floor(battle_anim.defender_power - (battle_anim.defender_power - battle_anim.defender_final) * eased)
  )
  return attacker_display, defender_display
end

local function get_translation_progress()
  if battle_anim.phase == "appear" then
    return 0
  end

  if battle_anim.phase == "approach" then
    return ease_out_quad(math.min(1, battle_anim.elapsed / APPROACH_DURATION))
  end

  if battle_anim.phase == "explosion" then
    return 1
  end

  if battle_anim.phase == "return" then
    local t = math.min(1, battle_anim.elapsed / RETURN_DURATION)
    return 1 - ease_in_quad(t)
  end

  return 0
end

function is_battle_anim_active()
  return battle_anim.active
end

function get_card_draw_offset(gx, gy)
  if not battle_anim.active then
    return 0, 0
  end

  if battle_anim.phase == "appear" or battle_anim.phase == "countdown" or battle_anim.phase == "result_hold" then
    return 0, 0
  end

  local progress = get_translation_progress()

  if gx == battle_anim.attacker_gx and gy == battle_anim.attacker_gy then
    return battle_anim.dir_x * MAX_TRANSLATION * progress, battle_anim.dir_y * MAX_TRANSLATION * progress
  end

  if gx == battle_anim.defender_gx and gy == battle_anim.defender_gy then
    return -battle_anim.dir_x * MAX_TRANSLATION * progress, -battle_anim.dir_y * MAX_TRANSLATION * progress
  end

  return 0, 0
end

function start_battle_animation(attacker_gx, attacker_gy, defender_gx, defender_gy, result, on_complete)
  battle_anim.active = true
  battle_anim.phase = "appear"
  battle_anim.elapsed = 0
  battle_anim.countdown_elapsed = 0
  battle_anim.attacker_gx = attacker_gx
  battle_anim.attacker_gy = attacker_gy
  battle_anim.defender_gx = defender_gx
  battle_anim.defender_gy = defender_gy
  battle_anim.attacker_power = result.attacker_power
  battle_anim.defender_power = result.defender_power
  battle_anim.attacker_final = result.attacker_final
  battle_anim.defender_final = result.defender_final
  battle_anim.attacker_wins = result.attacker_wins
  battle_anim.explosion_frame = 1
  battle_anim.on_complete = on_complete

  battle_anim.dir_x, battle_anim.dir_y = compute_clash_direction(attacker_gx, attacker_gy, defender_gx, defender_gy)
  battle_anim.explosion_x, battle_anim.explosion_y = get_clash_point(1)
end

local function finish_battle_animation()
  local callback = battle_anim.on_complete
  battle_anim.active = false
  battle_anim.phase = "idle"
  battle_anim.on_complete = nil

  if callback then
    callback()
  end
end

function update_battle_animation(dt)
  if not battle_anim.active then
    return
  end

  battle_anim.elapsed = battle_anim.elapsed + dt

  if is_countdown_phase() then
    battle_anim.countdown_elapsed = battle_anim.countdown_elapsed + dt
  end

  if battle_anim.phase == "appear" then
    if battle_anim.elapsed >= APPEAR_DURATION then
      battle_anim.phase = "approach"
      battle_anim.elapsed = 0
    end
    return
  end

  if battle_anim.phase == "approach" then
    if battle_anim.elapsed >= APPROACH_DURATION then
      battle_anim.phase = "explosion"
      battle_anim.elapsed = 0
      battle_anim.countdown_elapsed = 0
      battle_anim.explosion_frame = 1
      battle_anim.explosion_x, battle_anim.explosion_y = get_clash_point(1)
      play_sound("card_battle")
    end
    return
  end

  if battle_anim.phase == "explosion" then
    local frame = math.floor(battle_anim.elapsed / EXPLOSION_FRAME_DURATION) + 1

    if frame > #explosion_frames then
      battle_anim.phase = "return"
      battle_anim.elapsed = 0
      return
    end

    battle_anim.explosion_frame = frame
    return
  end

  if battle_anim.phase == "return" then
    if battle_anim.elapsed >= RETURN_DURATION then
      battle_anim.phase = "countdown"
      battle_anim.elapsed = 0
    end
    return
  end

  if battle_anim.phase == "countdown" then
    if battle_anim.countdown_elapsed >= countdown_active_duration() then
      battle_anim.phase = "result_hold"
      battle_anim.elapsed = 0
    end
    return
  end

  if battle_anim.phase == "result_hold" then
    if battle_anim.elapsed >= RESULT_HOLD then
      finish_battle_animation()
    end
  end
end

local function draw_battle_number(value, tile_x, tile_y, tile_w, tile_h)
  if not battle_font then
    return
  end

  local text = tostring(math.floor(value))
  local previous_font = love.graphics.getFont()
  local x = tile_x + tile_w / 2 - battle_font:getWidth(text) / 2
  local y = tile_y + tile_h / 2 - battle_font:getHeight() / 2

  love.graphics.setFont(battle_font)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.print(text, x + 1, y + 1)
  love.graphics.setColor(1, 0.88, 0.18)
  love.graphics.print(text, x, y)
  love.graphics.setFont(previous_font)
end

local function draw_battle_digits()
  local attacker_display, defender_display = get_battle_display_values()
  local ax, ay, aw, ah = get_grid_tile_screen_rect(battle_anim.attacker_gx, battle_anim.attacker_gy)
  local dx, dy, dw, dh = get_grid_tile_screen_rect(battle_anim.defender_gx, battle_anim.defender_gy)
  local ox1, oy1 = get_card_draw_offset(battle_anim.attacker_gx, battle_anim.attacker_gy)
  local ox2, oy2 = get_card_draw_offset(battle_anim.defender_gx, battle_anim.defender_gy)

  draw_battle_number(attacker_display, ax + ox1, ay + oy1, aw, ah)
  draw_battle_number(defender_display, dx + ox2, dy + oy2, dw, dh)
end

function draw_battle_animation()
  if not battle_anim.active then
    return
  end

  if battle_anim.phase ~= "idle" then
    draw_battle_digits()
  end

  if battle_anim.phase == "explosion" and explosion_frames[battle_anim.explosion_frame] then
    local frame = explosion_frames[battle_anim.explosion_frame]
    local fw, fh = frame:getWidth(), frame:getHeight()
    love.graphics.setColor(1, 1, 1)
    love.graphics.setBlendMode("add")
    love.graphics.draw(
      frame,
      battle_anim.explosion_x - fw / 2,
      battle_anim.explosion_y - fh / 2
    )
    love.graphics.setBlendMode("alpha")
  end

  love.graphics.setColor(1, 1, 1)
end

function draw_battle_select_highlight(select_index, options)
  if not options or #options == 0 then
    return
  end

  local choice = options[select_index]
  if not choice then
    return
  end

  local x, y, w, h = get_grid_tile_screen_rect(choice.def_x, choice.def_y)
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(1, 1, 1)
end
