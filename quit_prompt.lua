quit_prompt = {
  active = false,
  confirmed = false,
}

function is_quit_prompt_active()
  return quit_prompt.active
end

function show_quit_prompt()
  quit_prompt.active = true
end

function hide_quit_prompt()
  quit_prompt.active = false
end

function force_app_quit()
  quit_prompt.confirmed = true
  quit_prompt.active = false
  love.event.quit()
end

function confirm_quit_prompt()
  play_sound("escape")
  force_app_quit()
end

function handle_quit_prompt_key(key)
  if not quit_prompt.active then
    return false
  end

  if key == "return" or key == "kpenter" or key == "y" then
    confirm_quit_prompt()
    return true
  end

  if key == "escape" or key == "n" then
    hide_quit_prompt()
    play_sound("escape")
    return true
  end

  return true
end

function draw_quit_prompt()
  if not quit_prompt.active then
    return
  end

  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 0, 0, 320, 240)

  local font = battle_font or love.graphics.getFont()
  local previous_font = love.graphics.getFont()
  love.graphics.setFont(font)

  local title = "Leave duel?"
  local hint = "Enter = yes    Esc = no"
  local title_w = font:getWidth(title)
  local hint_w = font:getWidth(hint)
  local title_h = font:getHeight()
  local title_x = 160 - title_w / 2
  local title_y = 98
  local hint_x = 160 - hint_w / 2
  local hint_y = title_y + title_h + 10

  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        love.graphics.setColor(0.15, 0.08, 0.02, 0.9)
        love.graphics.print(title, title_x + dx, title_y + dy)
        love.graphics.print(hint, hint_x + dx, hint_y + dy)
      end
    end
  end

  love.graphics.setColor(1, 0.92, 0.35, 1)
  love.graphics.print(title, title_x, title_y)
  love.graphics.setColor(0.92, 0.92, 0.92, 1)
  love.graphics.print(hint, hint_x, hint_y)

  love.graphics.setFont(previous_font)
  love.graphics.setColor(1, 1, 1, 1)
end

function request_duel_quit()
  if not is_duel_active() then
    play_sound("escape")
    force_app_quit()
    return
  end

  show_quit_prompt()
end

function love_wants_to_quit()
  if not is_duel_active() or quit_prompt.confirmed then
    return false
  end

  show_quit_prompt()
  return true
end
