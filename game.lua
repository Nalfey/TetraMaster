local class = require("libs/middleclass/middleclass")
local stateful = require("libs/stateful/stateful")

require("libs/TLfres/TLfres")

Game = class("Game")
Game:include(stateful)

local EndGame = Game:addState("EndGame")
local CoinToss = Game:addState("CoinToss")

local function check_endgame()
  if #hands["red"].cards == 0 and #hands["blue"].cards == 0 then
    return true
  end

  return false
end

local function reset_window_size(z)
    TLfres.setScreen({w=320*z, h=240*z, full=false, vsync=true, aa=0, resizable=false}, 320, false, false)
    zoom = love.graphics.getWidth() / 320
end

local function count_score(side)
    local c = 0
    for i = 0, 3 do
      for j = 0, 3 do
        if card_grid[i + 1][j + 1] then
            if card_grid[i + 1][j + 1].side == side then
                c = c + 1
            end
        end
      end
    end

    return c
end

local function score_quad(side, count)
    local quads = score_text_q[side]
    if not quads then
        return nil
    end

    local index = math.min(math.max(count + 1, 1), #quads)
    return quads[index]
end

local function setup_board()
  init_grid()

  hands = {
      ["red"] = Hand:new("red", true),
      ["blue"] = Hand:new("blue", false)
  }

  reset_keyboard_focus()
end

local function setup_duel_placeholder()
  init_empty_grid()
  hands = {
      ["red"] = Hand:create_empty("red", { hidden = true }),
      ["blue"] = Hand:create_empty("blue"),
  }
  reset_keyboard_focus()
end

local function draw_duel_status()
  if not is_duel_active() or DUEL.match_ready then
    return
  end

  love.graphics.setColor(1, 1, 1)
  local text = "Waiting for " .. duel_peer_name() .. "..."

  if is_duel_host() and not DUEL.connected then
    text = "Waiting for opponent to connect..."
  elseif not is_duel_host() and not DUEL.connected then
    text = "Connecting to " .. duel_peer_name() .. "..."
  end

  love.graphics.printf(text, 20, 110, 280, "center")
end

local function start_new_match(game)
  setup_board()
  game:gotoState("CoinToss")
  game:load()
end

function Game:initialize()
    love.graphics.setDefaultFilter("nearest", "nearest")
    init_audio()
    play_sound("splash_screen")
    play_music()
    init_graphics()
    cards = require("cards")

    self.ai_turn_counter = {
        cur_time = 0,
        tar_time = 1
    }

    if is_duel_active() then
      setup_duel_placeholder()
    else
      setup_board()
      self:gotoState("CoinToss")
      self:load()
    end

    reset_window_size(4)
end

function Game:draw()
    TLfres.transform()
    love.graphics.draw(graphic_sheet, background_q, 0, 0)

    love.graphics.draw(graphic_sheet, grid_q, 48, 0)

    local grid_start_x = 73
    local grid_start_y = 9
    local grid_spacing_x = 42
    local grid_spacing_y = 52

    for i = 0, 3 do
      for j = 0, 3 do
          love.graphics.setColor(1, 1, 1)

          local x = grid_start_x + i * grid_spacing_x
          local y = grid_start_y + j * grid_spacing_y
          local ox, oy = get_card_draw_offset(i + 1, j + 1)

        if card_grid[i + 1][j + 1] then
          local c = card_grid[i + 1][j + 1]

          if c.side == "blue" then
             love.graphics.draw(graphic_sheet, card_back_blue_q, x + ox, y + oy)
          elseif c.side == "red" then
            love.graphics.draw(graphic_sheet, card_back_red_q, x + ox, y + oy)
          end

          -- If it has a card id then draw the card
          if c.card_id then
              c:draw(x + ox, y + oy)
          -- Otherwise draw the neutral cards
          elseif c.side == "neutral" then
            love.graphics.draw(graphic_sheet, block_card_q, x, y)
          elseif c.side == "neutral2" then
            love.graphics.draw(graphic_sheet, block_card2_q, x, y)
          end
        end
      end
    end

    -- Score
    love.graphics.draw(graphic_sheet, score_divider_q, 16, 185)

    -- Opponent hand (face-down, left side) — draws nothing when empty
    hands["red"]:draw(HAND_LAYOUT.red.x, HAND_LAYOUT.red.y)

    -- Player hand (always face-up, right side)
    hands["blue"]:draw(HAND_LAYOUT.blue.x, HAND_LAYOUT.blue.y)

    local red_score_q = score_quad("red", count_score("red"))
    local blue_score_q = score_quad("blue", count_score("blue"))

    if red_score_q then
      love.graphics.draw(graphic_sheet, red_score_q, 25, 170)
    end

    if blue_score_q then
      love.graphics.draw(graphic_sheet, blue_score_q, 38, 203)
    end

    self:draw_ui()
    draw_duel_status()

    TLfres.letterbox(4,3)
end

function Game:draw_ui()
    if is_battle_select_active() then
      draw_battle_select_highlight(get_battle_select_index(), get_battle_select_options())
    end

    draw_battle_animation()
    draw_game_cursor()
end

function CoinToss:load()
  start_coin_toss()
end

function CoinToss:update(dt)
  if update_coin_toss(dt) then
    if not is_duel_active() then
      current_turn = get_coin_toss_first_turn()
    end
    self:gotoState()
  end
end

function CoinToss:draw_ui()
  draw_coin_toss()
end

function Game:update(dt)
    update_cursor_animation(dt)
    update_placement(dt)

    if is_coin_toss_active() or is_placement_resolving() then
      return
    end

    if is_duel_active() then
      if check_endgame() then
        if is_duel_host() then
          duel_send_game_over()
        end
        self:gotoState("EndGame")
        self:load()
      end
      return
    end

    if hands[current_turn].ai_controlled then
        self.ai_turn_counter.cur_time = self.ai_turn_counter.cur_time + dt

        if self.ai_turn_counter.cur_time > self.ai_turn_counter.tar_time then
            self.ai_turn_counter.cur_time = 0

            if check_endgame() then
              start_new_match(self)
              return
            end

            hands[current_turn]:ai_move(function()
              turn_end()
            end)
        end
    end

    if check_endgame() then
      self:gotoState("EndGame")
      self:load()
    end
end

function EndGame:load()
  self.stay_counter = {
      cur_time = 0,
      tar_time = 3
  }

  local blue_score = count_score("blue")
  local red_score = count_score("red")

  if blue_score == red_score then
    self.outcome_label = "DRAW"
    play_sound("tie_game")
  elseif blue_score > red_score then
    if red_score == 0 then
      self.outcome_label = "PERFECT"
      play_sound("perfect_game")
    else
      self.outcome_label = "WIN"
      play_sound("win_game")
    end
  else
    self.outcome_label = "LOSE"
    play_sound("lose_game")
  end
end

function EndGame:update(dt)
  self.stay_counter.cur_time = self.stay_counter.cur_time + dt

  if self.stay_counter.cur_time <= self.stay_counter.tar_time then
    return
  end

  if is_duel_active() then
    if is_duel_host() then
      duel_auto_rematch(self)
    end
    return
  end

  self:gotoState()
  start_new_match(self)
end

function EndGame:draw_ui()
  if not self.outcome_label then
    return
  end

  draw_end_game_outcome(self.outcome_label, 160, 110)
end
