coin_toss = {
  active = false,
  phase = "intro",
  display_frame = 8,
  intro_frame = 4,
  result = 8,
  elapsed = 0,
  intro_pause = 1,
  result_pause = 1.2,
  toss_duration = 0.557,
  frame_interval = 0.035,
  flip_cycles = 3,
  min_flip_cycles = 2,
  max_flip_cycles = 5,
  min_toss_scale = 0.75,
  max_toss_scale = 1.35,
}

local COIN_CENTER_X = 156
local COIN_CENTER_Y = 112

local function random_toss_timing()
  coin_toss.flip_cycles = math.random(coin_toss.min_flip_cycles, coin_toss.max_flip_cycles)

  local base_duration = coin_toss.toss_duration
  if sounds.coin then
    base_duration = sounds.coin:getDuration()
  end

  local scale = coin_toss.min_toss_scale
    + math.random() * (coin_toss.max_toss_scale - coin_toss.min_toss_scale)
  coin_toss.toss_duration = base_duration * scale
  coin_toss.frame_interval = coin_toss.toss_duration / (8 * coin_toss.flip_cycles)
end

function start_coin_toss()
  start_coin_toss_forced(math.random(1, 2) == 1 and 4 or 8)
end

function start_coin_toss_forced(result_frame)
  coin_toss.result = result_frame == 4 and 4 or 8
  coin_toss.intro_frame = math.random(1, 2) == 1 and 4 or 8
  coin_toss.phase = "intro"
  coin_toss.elapsed = 0
  coin_toss.display_frame = coin_toss.intro_frame
  coin_toss.active = true
end

function is_coin_toss_active()
  return coin_toss.active
end

function update_coin_toss(dt)
  if not coin_toss.active then
    return false
  end

  coin_toss.elapsed = coin_toss.elapsed + dt

  if coin_toss.phase == "intro" then
    coin_toss.display_frame = coin_toss.intro_frame

    if coin_toss.elapsed >= coin_toss.intro_pause then
      coin_toss.phase = "toss"
      coin_toss.elapsed = 0

      random_toss_timing()

      if sounds.coin then
        play_sound("coin")
      end
    end

    return false
  end

  if coin_toss.phase == "toss" then
    if coin_toss.elapsed >= coin_toss.toss_duration then
      coin_toss.phase = "result"
      coin_toss.elapsed = 0
      coin_toss.display_frame = coin_toss.result
      return false
    end

    coin_toss.display_frame = math.floor(coin_toss.elapsed / coin_toss.frame_interval) % 8 + 1
    return false
  end

  coin_toss.display_frame = coin_toss.result

  if coin_toss.elapsed >= coin_toss.result_pause then
    coin_toss.active = false
    return true
  end

  return false
end

function get_coin_toss_first_turn()
  if coin_toss.result == 8 then
    return "blue"
  end

  return "red"
end

function draw_coin_toss()
  if not coin_frames or not coin_frames[coin_toss.display_frame] then
    return
  end

  local frame = coin_frames[coin_toss.display_frame]
  local w, h = frame:getWidth(), frame:getHeight()

  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(frame, COIN_CENTER_X - w / 2, COIN_CENTER_Y - h / 2)
end
