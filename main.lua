require("protocol")
local bridge = require("bridge")
require("audio")
require("battle")
require("capture_fx")
require("place_card")
require("init")
require("characters")
require("input")
require("coin_toss")
require("end_game_text")
require("quit_prompt")

require("card")
require("hand")
require("duel")
require("game")

local function log_runtime_error(err)
  local log_path = (os.getenv("USERPROFILE") or ".") .. "/Desktop/Windower4/addons/TetraMaster/sync/runtime_error.log"
  local file = io.open(log_path, "a")
  if file then
    file:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n" .. tostring(err) .. "\n\n")
    file:close()
  end
end

local function log_boot_error(err)
  log_runtime_error(err)
end

player_settings = { character = "random" }
addon_root = nil
launch_player_name = nil

local function parse_launch_args(argv)
  local args = argv or arg or {}
  for i = 1, #args - 1 do
    if args[i] == "--addon-path" then
      addon_root = args[i + 1]
    elseif args[i] == "--player-name" then
      launch_player_name = args[i + 1]
    end
  end
end

parse_launch_args(arg)

local function load_player_settings()
  if addon_root then
    player_settings = require("player_settings").load(addon_root, launch_player_name)
  end
end

function love.load()
  local ok, err = pcall(function()
    math.randomseed(os.time())
    load_player_settings()
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
  if love_wants_to_quit() then
    return true
  end

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
  local ok, err = pcall(function()
    if is_duel_active() then
      duel_poll()
    end

    Game:update(dt)

    if is_duel_active() then
      duel_try_finish_game_over(Game)
    end
  end)

  if not ok then
    log_runtime_error(debug.traceback(err, 2))
    error(err)
  end
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

  if handle_quit_prompt_key(key) then
    return
  end

  if handle_keyboard(key) then
    return
  end

  if key == "escape" then
    if is_duel_active() then
      request_duel_quit()
      return
    end

    play_sound("escape")
    force_app_quit()
    return
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
