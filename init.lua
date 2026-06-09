local function get_image_content_center(image_data)
  local w, h = image_data:getWidth(), image_data:getHeight()
  local sum_x, sum_y, count = 0, 0, 0

  for py = 0, h - 1 do
    for px = 0, w - 1 do
      local _, _, _, a = image_data:getPixel(px, py)
      if a > 0.04 then
        sum_x = sum_x + px
        sum_y = sum_y + py
        count = count + 1
      end
    end
  end

  if count == 0 then
    return (w - 1) / 2, (h - 1) / 2
  end

  return sum_x / count, sum_y / count
end

function init_graphics()
  local ok, font = pcall(love.graphics.newFont, "assets/fonts/Cinzel-Bold.ttf", 26)
  if ok then
    end_game_font = font
    end_game_font:setFilter("linear", "linear")
  else
    end_game_font = love.graphics.newFont(26)
  end

  cursor_frames = {}
  cursor_frame_anchors = {}

  coin_frames = {}
  for i = 1, 8 do
    local frame = love.graphics.newImage(
      string.format("assets/sprites/Coin/coin_%02d.png", i)
    )
    frame:setFilter("nearest", "nearest")
    coin_frames[i] = frame
  end

  explosion_frames = {}
  for i = 1, 8 do
    local frame = love.graphics.newImage(
      string.format("assets/sprites/Explosion/explosion_%02d.png", i)
    )
    frame:setFilter("nearest", "nearest")
    explosion_frames[i] = frame
  end

  for i = 1, 8 do
    local path = string.format("assets/sprites/Cursor/Cursor_%02d.png", i)
    local image_data = love.image.newImageData(path)
    local anchor_x, anchor_y = get_image_content_center(image_data)
    local frame = love.graphics.newImage(image_data)

    frame:setFilter("nearest", "nearest")
    table.insert(cursor_frames, frame)
    table.insert(cursor_frame_anchors, { x = anchor_x, y = anchor_y })
  end

  graphic_sheet = love.graphics.newImage("assets/sprites/graphics.png")
  sheet_w = graphic_sheet:getWidth()
  sheet_h = graphic_sheet:getHeight()

  background_q = love.graphics.newQuad(10, 498, 320, 240, sheet_w, sheet_h)
  grid_q = love.graphics.newQuad(340, 498, 224, 240, sheet_w, sheet_h)
  cards_q = init_card_quads()

  card_back_blue_q = love.graphics.newQuad(18, 822, 42, 51, sheet_w, sheet_h)
  card_back_red_q = love.graphics.newQuad(66, 822, 42, 51, sheet_w, sheet_h)

  block_card_q = love.graphics.newQuad(114, 822, 42, 51, sheet_w, sheet_h)
  block_card2_q = love.graphics.newQuad(162, 822, 42, 51, sheet_w, sheet_h)

  score_divider_q = love.graphics.newQuad(202, 759, 43, 23, sheet_w, sheet_h)

  card_back_q = love.graphics.newQuad(210, 822, 42, 51, sheet_w, sheet_h)

  arrow_q = init_arrow_quads()

  score_text_q = init_score_text()

  stat_text_q = {}
  local stat_text = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B",
                     "C", "D", "E", "F", "P", "M", "X"}

  for i, v in ipairs(stat_text) do
      local x_offset = 356 + ((i - 1) * 8)-- + 1
      local q = love.graphics.newQuad(x_offset, 822, 7, 7, sheet_w, sheet_h)
      stat_text_q[v] = q
    --   table.insert(stat_text_q, q)
  end

  local battle_font_ok
  battle_font_ok, battle_font = pcall(love.graphics.newFont, "assets/fonts/Cinzel-Bold.ttf", 18)
  if battle_font_ok then
    battle_font:setFilter("linear", "linear")
  else
    battle_font = love.graphics.newFont(18)
  end
end

function init_empty_grid()
  card_grid = {}

  for i = 1, 4 do
    card_grid[i] = {}

    for j = 1, 4 do
      card_grid[i][j] = nil
    end
  end
end

function init_grid()
  card_grid = {}

  local disabled_spaces = math.random(0, 6)
  -- local disabled_spaces = 0

  for i = 1, 4 do
    card_grid[i] = {}

    for j = 1, 4 do
      card_grid[i][j] = nil
    end
  end

  local i = 0
  while i < disabled_spaces do
    local x = math.random(1, 4)
    local y = math.random(1, 4)

    if card_grid[x][y] == nil then
      local c = { side = "neutral" }

      if math.random(1, 2) == 1 then
        c.side = "neutral2"
      end

      card_grid[x][y] = c

      i = i + 1
    end
  end

  -- Debug:
  -- place_card(math.random(1, 99), 1, 1, "blue")
end

function init_card_quads()
  local quads = {}

  local card_w = 42
  local card_h = 51
  local card_spacing = 10
  local card_max_w = 11 + (12 * card_w) + (12 * card_spacing)
  local card_max_h = 11 + (8 * card_h) + (8 * card_spacing)
  for y = 11, card_max_h, card_h + card_spacing do
    for x = 11, card_max_w, card_w + card_spacing do
      q = love.graphics.newQuad(x, y, card_w, card_h, sheet_w, sheet_h)
      table.insert(quads, q)
    end
  end

  return quads
end


function init_arrow_quads()
    local arrows = {}

    arrows["upleft"] = love.graphics.newQuad(202, 790, 8, 8, sheet_w, sheet_h)
    arrows["up"] = love.graphics.newQuad(210, 790, 8, 8, sheet_w, sheet_h)
    arrows["upright"] = love.graphics.newQuad(218, 790, 8, 8, sheet_w, sheet_h)
    arrows["downleft"] = love.graphics.newQuad(226, 790, 8, 8, sheet_w, sheet_h)
    arrows["down"] = love.graphics.newQuad(234, 790, 8, 8, sheet_w, sheet_h)
    arrows["downright"] = love.graphics.newQuad(242, 790, 8, 8, sheet_w, sheet_h)
    arrows["left"] = love.graphics.newQuad(202, 798, 8, 8, sheet_w, sheet_h)
    arrows["right"] = love.graphics.newQuad(210, 798, 8, 8, sheet_w, sheet_h)

    return arrows
end

function init_score_text()
    local text = {}
    text["red"] = {}
    text["blue"] = {}

    table.insert(text["blue"], love.graphics.newQuad(154, 762, 16, 20, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(11, 764, 13, 19, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(26, 763, 16, 21, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(42, 763, 16, 22, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(58, 764, 17, 21, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(75, 763, 15, 21, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(90, 762, 16, 21, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(106, 763, 16, 20, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(122, 762, 16, 22, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(138, 762, 16, 22, sheet_w, sheet_h))
    table.insert(text["blue"], love.graphics.newQuad(171, 762, 27, 20, sheet_w, sheet_h))

    table.insert(text["red"], love.graphics.newQuad(154, 762 + 34, 16, 20, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(11, 764 + 34, 13, 19, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(26, 763 + 34, 16, 21, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(42, 763 + 34, 16, 22, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(58, 764 + 34, 17, 21, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(75, 763 + 34, 15, 21, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(90, 762 + 34, 16, 21, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(106, 763 + 34, 16, 20, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(122, 762 + 34, 16, 22, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(138, 762 + 34, 16, 22, sheet_w, sheet_h))
    table.insert(text["red"], love.graphics.newQuad(171, 762 + 34, 27, 20, sheet_w, sheet_h))

    return text
end
