HAND_LAYOUT = {
  blue = { x = 260, y = 8 },
  red = { x = 16, y = 28 },
}

cursor_anim = {
  frame = 1,
  timer = 0,
  frame_duration = 0.16,
}

-- Keyboard focus state
keyboard_focus = {
  area = "hand",
  hand_index = 1,
  grid_x = 2,
  grid_y = 2,
}

local function is_player_turn()
  if is_duel_active() then
    return is_local_duel_turn() and not is_coin_toss_active() and DUEL.match_ready
  end

  return hands and not hands[current_turn].ai_controlled and not is_coin_toss_active()
end

local function is_endgame()
  return hands and #hands["red"].cards == 0 and #hands["blue"].cards == 0
end

function reset_keyboard_focus()
  keyboard_focus.area = "hand"
  keyboard_focus.hand_index = 1
  keyboard_focus.grid_x = 2
  keyboard_focus.grid_y = 2
end

function get_hand_card_screen_rect(index)
  local card_height = 51
  local card_width = 42

  if hands["blue"] and #hands["blue"].cards == 5 then
    card_height = 42
    card_width = 35
  end

  return HAND_LAYOUT.blue.x, HAND_LAYOUT.blue.y + (index - 1) * card_height, card_width, card_height
end

function get_grid_tile_screen_rect(gx, gy)
  return 73 + (gx - 1) * 42, 9 + (gy - 1) * 52, 42, 52
end

function get_keyboard_focus_rect()
  if keyboard_focus.area == "grid" then
    return get_grid_tile_screen_rect(keyboard_focus.grid_x, keyboard_focus.grid_y)
  end

  return get_hand_card_screen_rect(keyboard_focus.hand_index)
end

function update_cursor_animation(dt)
  if not cursor_frames or #cursor_frames == 0 then
    return
  end

  cursor_anim.timer = cursor_anim.timer + dt

  while cursor_anim.timer >= cursor_anim.frame_duration do
    cursor_anim.timer = cursor_anim.timer - cursor_anim.frame_duration
    cursor_anim.frame = cursor_anim.frame % #cursor_frames + 1
  end
end

function draw_game_cursor()
  if is_coin_toss_active() or is_placement_resolving() or not is_player_turn() or is_endgame() or not cursor_frames or #cursor_frames == 0 then
    return
  end

  local x, y, w, h = get_keyboard_focus_rect()
  local frame = cursor_frames[cursor_anim.frame]
  local anchor = cursor_frame_anchors[cursor_anim.frame]

  local screen_anchor_x = x - 15
  local screen_anchor_y = y + h / 2

  love.graphics.draw(
    frame,
    screen_anchor_x - anchor.x,
    screen_anchor_y - anchor.y
  )
end

function handle_keyboard(key)
  if is_coin_toss_active() or is_endgame() then
    return false
  end

  if is_battle_select_active() then
    if key == "return" or key == "kpenter" then
      if is_duel_active() and not is_duel_host() and placement.network and placement.network.remote then
        duel_on_battle_choice(get_battle_select_index())
        return true
      end

      confirm_battle_select()
      return true
    end

    if key == "up" or key == "left" then
      cycle_battle_select(-1)
      return true
    end

    if key == "down" or key == "right" then
      cycle_battle_select(1)
      return true
    end

    return false
  end

  if is_placement_resolving() or not is_player_turn() then
    return false
  end

  local hand = hands[current_turn]

  if key == "escape" then
    if hand.selected_card then
      hand.selected_card = nil
      keyboard_focus.area = "hand"
      play_sound("escape")
      return true
    end
    return false
  end

  if key == "return" or key == "kpenter" then
    if hand.selected_card then
      local gx, gy = keyboard_focus.grid_x, keyboard_focus.grid_y
      if card_grid[gx][gy] == nil then
        local selected = hand.selected_card
        if is_duel_active() then
          duel_on_local_place(gx, gy, keyboard_focus.hand_index, hand, selected)
          hand.selected_card = nil
          keyboard_focus.area = "hand"
        else
          place_card(gx, gy, selected, function()
            hand:remove_selected_card()
            keyboard_focus.area = "hand"
            keyboard_focus.hand_index = math.min(
              math.max(keyboard_focus.hand_index, 1),
              math.max(#hand.cards, 1)
            )
            turn_end()
          end)
        end
      else
        play_sound("error")
      end
    elseif keyboard_focus.hand_index >= 1 and keyboard_focus.hand_index <= #hand.cards then
      hand.selected_card = hand.cards[keyboard_focus.hand_index]
      keyboard_focus.area = "grid"
      play_sound("choose_card")
    else
      play_sound("error")
    end
    return true
  end

  if hand.selected_card then
    keyboard_focus.area = "grid"

    if key == "left" then
      keyboard_focus.grid_x = math.max(1, keyboard_focus.grid_x - 1)
    elseif key == "right" then
      keyboard_focus.grid_x = math.min(4, keyboard_focus.grid_x + 1)
    elseif key == "up" then
      keyboard_focus.grid_y = math.max(1, keyboard_focus.grid_y - 1)
    elseif key == "down" then
      keyboard_focus.grid_y = math.min(4, keyboard_focus.grid_y + 1)
    else
      return false
    end

    play_sound("cursor")
    return true
  end

  keyboard_focus.area = "hand"

  if key == "up" then
    keyboard_focus.hand_index = math.max(1, keyboard_focus.hand_index - 1)
  elseif key == "down" then
    keyboard_focus.hand_index = math.min(#hand.cards, keyboard_focus.hand_index + 1)
  else
    return false
  end

  play_sound("cursor")
  return true
end
