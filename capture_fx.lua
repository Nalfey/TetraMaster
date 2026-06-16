capture_fx = {
  active = false,
  phase = nil,
  elapsed = 0,
  steps = {},
  step_index = 0,
  on_complete = nil,
  combo_label = nil,
}

local FLASH_DURATION = 0.42
local WIPE_DURATION = 0.38

local function ease_out_quad(t)
  return 1 - (1 - t) * (1 - t)
end

function is_capture_fx_active()
  return capture_fx.active
end

local function finish_sequence()
  capture_fx.active = false
  capture_fx.phase = nil
  capture_fx.combo_label = nil
  local callback = capture_fx.on_complete
  capture_fx.on_complete = nil
  capture_fx.steps = {}
  capture_fx.step_index = 0

  if callback then
    callback()
  end
end

local function current_step()
  return capture_fx.steps[capture_fx.step_index]
end

local function begin_step()
  local step = current_step()
  if not step then
    finish_sequence()
    return
  end

  capture_fx.elapsed = 0

  if step.type == "flash" then
    capture_fx.phase = "flash"
    capture_fx.combo_label = nil
  elseif step.type == "combo" then
    capture_fx.phase = "combo"
    capture_fx.combo_label = {
      gx = step.origin_gx,
      gy = step.origin_gy,
      count = step.count,
    }
  end
end

local function advance_step()
  capture_fx.step_index = capture_fx.step_index + 1
  begin_step()
end

function start_capture_sequence(steps, on_complete)
  if #steps == 0 then
    if on_complete then
      on_complete()
    end
    return
  end

  capture_fx.active = true
  capture_fx.steps = steps
  capture_fx.step_index = 1
  capture_fx.on_complete = on_complete
  begin_step()
end

local function apply_step_flip(step)
  if step.card then
    step.card.side = step.new_side
  end
end

function update_capture_fx(dt)
  if not capture_fx.active then
    return
  end

  local step = current_step()
  if not step then
    finish_sequence()
    return
  end

  capture_fx.elapsed = capture_fx.elapsed + dt

  if step.type == "flash" then
    local t = capture_fx.elapsed / FLASH_DURATION
    if t >= 1 then
      apply_step_flip(step)
      advance_step()
    elseif t >= 0.48 and not step.flipped then
      step.flipped = true
      apply_step_flip(step)
    end
    return
  end

  if step.type == "combo" then
    if capture_fx.elapsed >= WIPE_DURATION then
      apply_step_flip(step)
      capture_fx.combo_label = nil
      advance_step()
    end
  end
end

local function draw_flash_overlay(gx, gy, progress)
  local x, y, w, h = get_grid_tile_screen_rect(gx, gy)
  local ox, oy = get_card_draw_offset(gx, gy)
  x = x + ox
  y = y + oy

  local ramp = math.min(1, progress / 0.48)
  local fade = progress > 0.48 and (1 - (progress - 0.48) / 0.52) or 1
  local alpha = ease_out_quad(ramp) * fade * 0.72

  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 1, 1, alpha * 0.45)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setBlendMode("alpha")
end

local LINE_THICK = 4

local function draw_directional_wipe(x, y, w, h, from_dx, from_dy, progress)
  progress = math.min(1, math.max(0, progress))
  from_dx = from_dx or 0
  from_dy = from_dy or 1

  local is_diagonal = from_dx ~= 0 and from_dy ~= 0

  love.graphics.setColor(1, 1, 1, 0.55)

  if is_diagonal then
    local ix = x + w * (from_dx > 0 and (1 - progress) or progress)
    local iy = y + h * (from_dy > 0 and (1 - progress) or progress)

    if from_dx > 0 and from_dy > 0 then
      -- Origin: bottom-right. Fill grows from that corner toward top-left.
      love.graphics.rectangle("fill", ix, iy, x + w - ix, y + h - iy)
      love.graphics.setColor(1, 1, 1, 0.95)
      love.graphics.rectangle("fill", ix, iy, x + w - ix, LINE_THICK)
      love.graphics.rectangle("fill", ix, iy, LINE_THICK, y + h - iy)
    elseif from_dx < 0 and from_dy < 0 then
      -- Origin: top-left.
      love.graphics.rectangle("fill", x, y, ix - x, iy - y)
      love.graphics.setColor(1, 1, 1, 0.95)
      love.graphics.rectangle("fill", x, iy - LINE_THICK, ix - x, LINE_THICK)
      love.graphics.rectangle("fill", ix - LINE_THICK, y, LINE_THICK, iy - y)
    elseif from_dx > 0 and from_dy < 0 then
      -- Origin: top-right.
      love.graphics.rectangle("fill", ix, y, x + w - ix, iy - y)
      love.graphics.setColor(1, 1, 1, 0.95)
      love.graphics.rectangle("fill", ix, iy - LINE_THICK, x + w - ix, LINE_THICK)
      love.graphics.rectangle("fill", ix, y, LINE_THICK, iy - y)
    else
      -- Origin: bottom-left.
      love.graphics.rectangle("fill", x, iy, ix - x, y + h - iy)
      love.graphics.setColor(1, 1, 1, 0.95)
      love.graphics.rectangle("fill", x, iy, ix - x, LINE_THICK)
      love.graphics.rectangle("fill", ix - LINE_THICK, iy, LINE_THICK, y + h - iy)
    end
    return
  end

  if from_dy < 0 then
    local edge = y + h * progress
    love.graphics.rectangle("fill", x, y, w, h * progress)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.rectangle("fill", x, edge - LINE_THICK / 2, w, LINE_THICK)
  elseif from_dy > 0 then
    local edge = y + h * (1 - progress)
    love.graphics.rectangle("fill", x, edge, w, y + h - edge)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.rectangle("fill", x, edge - LINE_THICK / 2, w, LINE_THICK)
  elseif from_dx < 0 then
    local fill_w = w * progress
    local edge = x + fill_w
    love.graphics.rectangle("fill", x, y, fill_w, h)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.rectangle("fill", edge - LINE_THICK / 2, y, LINE_THICK, h)
  elseif from_dx > 0 then
    local edge = x + w * (1 - progress)
    love.graphics.rectangle("fill", edge, y, x + w - edge, h)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.rectangle("fill", edge - LINE_THICK / 2, y, LINE_THICK, h)
  end
end

local function draw_wipe_overlay(gx, gy, progress, from_dx, from_dy)
  local x, y, w, h = get_grid_tile_screen_rect(gx, gy)
  local ox, oy = get_card_draw_offset(gx, gy)
  draw_directional_wipe(x + ox, y + oy, w, h, from_dx, from_dy, progress)
end

local function draw_combo_label(label)
  if not label or not battle_font then
    return
  end

  local x, y, w, h = get_grid_tile_screen_rect(label.gx, label.gy)
  local text = label.count .. " COMBO"
  local previous_font = love.graphics.getFont()
  love.graphics.setFont(battle_font)

  local text_w = battle_font:getWidth(text)
  local text_h = battle_font:getHeight()
  local tx = x + w / 2 - text_w / 2
  local ty = y + h / 2 - text_h / 2

  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        love.graphics.setColor(0.35, 0.12, 0.02, 0.85)
        love.graphics.print(text, tx + dx, ty + dy)
      end
    end
  end

  love.graphics.setColor(1, 0.72, 0.18, 1)
  love.graphics.print(text, tx, ty - 1)
  love.graphics.setColor(1, 0.92, 0.35, 1)
  love.graphics.print(text, tx, ty)

  love.graphics.setFont(previous_font)
  love.graphics.setColor(1, 1, 1)
end

function draw_capture_fx()
  if not capture_fx.active then
    return
  end

  local step = current_step()
  if not step then
    return
  end

  if step.type == "flash" then
    local progress = math.min(1, capture_fx.elapsed / FLASH_DURATION)
    draw_flash_overlay(step.gx, step.gy, progress)
  elseif step.type == "combo" then
    if capture_fx.combo_label then
      draw_combo_label(capture_fx.combo_label)
    end
    local progress = math.min(1, capture_fx.elapsed / WIPE_DURATION)
    draw_wipe_overlay(step.gx, step.gy, progress, step.from_dx, step.from_dy)
  end

  love.graphics.setColor(1, 1, 1)
end

function get_capture_fx_overlay(gx, gy)
  if not capture_fx.active then
    return nil
  end

  local step = current_step()
  if not step or step.gx ~= gx or step.gy ~= gy then
    return nil
  end

  if step.type == "flash" then
    return "flash", math.min(1, capture_fx.elapsed / FLASH_DURATION)
  end

  if step.type == "combo" then
    return "wipe", math.min(1, capture_fx.elapsed / WIPE_DURATION)
  end

  return nil
end
