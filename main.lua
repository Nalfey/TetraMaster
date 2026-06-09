require("protocol")
local bridge = require("bridge")
require("audio")
require("battle")
require("place_card")
require("init")
require("input")
require("coin_toss")
require("end_game_text")

require("card")
require("hand")
require("duel")
require("game")

local function log_boot_error(err)
  local log_path = (os.getenv("USERPROFILE") or ".") .. "/Desktop/Windower4/addons/TetraMaster/sync/boot_error.log"
  local file = io.open(log_path, "a")
  if file then
    file:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n" .. tostring(err) .. "\n\n")
    file:close()
  end
end

function love.load()
  local ok, err = pcall(function()
    math.randomseed(os.time())
    duel_init_from_args(arg)
    Game = Game()

    if is_duel_active() and bridge.is_enabled() then
      bridge.write_heartbeat()
    end
  end)

  if not ok then
    log_boot_error(debug.traceback(err, 2))
    error(err)
  end
end

function love.quit()
  if is_duel_active() then
    duel_send_resign()
  end
end

function love.draw()
  love.graphics.push()
  -- love.graphics.scale(zoom)

  Game:draw()

  love.graphics.setColor(1, 1, 1)
  love.graphics.pop()
end

function love.update(dt)
    if is_duel_active() then
      duel_poll()
    end

    Game:update(dt)
end

function love.focus(focus)
  if focus and is_duel_active() and bridge.is_enabled() then
    bridge.write_heartbeat()
  end
end

function love.keypressed(key, scancode, isrepeat)
  if isrepeat then
    return
  end

  if handle_keyboard(key) then
    return
  end

  if key == "escape" then
    play_sound("escape")
    love.event.quit()
  end

  if key == "l" then
    in_game = not in_game
  end

  if key == "r" and not is_duel_active() then
    init_grid()
  end
end

function turn_end()
  if current_turn == "red" then
    current_turn = "blue"
    return
  end

  current_turn = "red"
end
