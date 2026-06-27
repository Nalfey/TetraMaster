character_portraits = {}
character_session = {
  blue = nil,
  red = nil,
  victories = { red = 0, blue = 0 },
}

character_backgrounds = {
  red = nil,
  blue = nil,
}

-- Game sprites live in assets/sprites/Characters (32x32 bake). Full-res sources:
-- tools/card_sprites/Characters — regenerate with tools/build_character_sprites.py
local CHARACTER_ASSET_DIR = "assets/sprites/Characters"
local PREBAKED_CHARACTER_SPRITES = true

local FULL_PORTRAIT_SOURCE_SIZE = 64
local PORTRAIT_DISPLAY_SIZE = 16
local BG_SOURCE_WIDTH = 80
local BG_SOURCE_HEIGHT = 96
local CHARACTER_SCREEN_W = 320
local CHARACTER_EDGE_MARGIN = 2
local VICTORY_DIGIT_SCALE = 0.55

-- Preview two-digit layout (red=12, blue=24). Set true to test multi-digit display.
local VICTORY_COUNT_PREVIEW = false
local VICTORY_PREVIEW_COUNTS = { red = 12, blue = 24 }

local function character_bg_display_width()
  return BG_SOURCE_WIDTH * (PORTRAIT_DISPLAY_SIZE / FULL_PORTRAIT_SOURCE_SIZE)
end

local function character_bg_display_height()
  return BG_SOURCE_HEIGHT * (PORTRAIT_DISPLAY_SIZE / FULL_PORTRAIT_SOURCE_SIZE)
end

local function portrait_display_size()
  return PORTRAIT_DISPLAY_SIZE
end

local function layout_for_side(side)
  local bg_width = character_bg_display_width()
  local bg_height = character_bg_display_height()
  local icon_size = portrait_display_size()
  local center_x

  if side == "red" then
    center_x = CHARACTER_EDGE_MARGIN + bg_width / 2
  else
    center_x = CHARACTER_SCREEN_W - CHARACTER_EDGE_MARGIN - bg_width / 2
  end

  local center_y = CHARACTER_EDGE_MARGIN + bg_height / 2

  return {
    x = center_x - icon_size / 2,
    y = center_y - icon_size / 2,
    size = icon_size,
  }
end

CHARACTER_LAYOUT = {
  red = nil,
  blue = nil,
}

local function portrait_sort_key(filename)
  local id = tonumber(filename:match("^(%d+)_"))
  return id or 9999
end

local function load_character_image(path)
  local ok, image = pcall(love.graphics.newImage, path)
  if ok then
    image:setFilter("nearest", "nearest")
  end
  return ok and image or nil
end

function init_character_portraits()
  character_portraits = {}
  character_backgrounds.red = nil
  character_backgrounds.blue = nil

  character_backgrounds.red = load_character_image(CHARACTER_ASSET_DIR .. "/bg_opponent.png")
  character_backgrounds.blue = load_character_image(CHARACTER_ASSET_DIR .. "/bg_player.png")

  local files = love.filesystem.getDirectoryItems(CHARACTER_ASSET_DIR)
  table.sort(files, function(a, b)
    return portrait_sort_key(a) < portrait_sort_key(b)
  end)

  for _, file in ipairs(files) do
    if file:match("%.png$") and not file:match("^bg_") then
      local path = CHARACTER_ASSET_DIR .. "/" .. file
      local image = load_character_image(path)
      if image then
        local display_name = file:gsub("%.png$", ""):gsub("^%d+_", ""):gsub("_", " ")
        table.insert(character_portraits, {
          file = file,
          name = display_name,
          image = image,
        })
      end
    end
  end

  CHARACTER_LAYOUT.red = layout_for_side("red")
  CHARACTER_LAYOUT.blue = layout_for_side("blue")
end

function pick_random_character_index(exclude)
  if #character_portraits == 0 then
    return nil
  end

  if #character_portraits == 1 then
    return 1
  end

  local index
  repeat
    index = math.random(1, #character_portraits)
  until index ~= exclude

  return index
end

local function normalize_character_name(name)
  return (name or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

function find_character_index_by_name(name)
  local target = normalize_character_name(name)
  if target == "" or target == "random" then
    return nil
  end

  for index, portrait in ipairs(character_portraits) do
    if normalize_character_name(portrait.name) == target then
      return index
    end
  end

  return nil
end

function pick_character_index(preference, exclude)
  if not preference or normalize_character_name(preference) == "random" then
    return pick_random_character_index(exclude)
  end

  local index = find_character_index_by_name(preference)
  if index then
    return index
  end

  return pick_random_character_index(exclude)
end

function init_character_session()
  if #character_portraits == 0 then
    character_session.blue = nil
    character_session.red = nil
    character_session.victories = { red = 0, blue = 0 }
    return
  end

  character_session.victories = { red = 0, blue = 0 }

  local preference = (player_settings and player_settings.character) or "random"
  character_session.blue = pick_character_index(preference)

  if is_duel_active() then
    character_session.red = nil
  else
    character_session.red = pick_random_character_index(character_session.blue)
  end
end

function roll_opponent_character()
  if #character_portraits == 0 then
    character_session.red = nil
    return
  end

  character_session.red = pick_random_character_index(character_session.blue)
end

function set_opponent_character_index(index)
  index = tonumber(index)
  if index and character_portraits[index] then
    character_session.red = index
  end
end

function get_local_character_index()
  return character_session.blue
end

function record_character_victory(winner_side)
  if not character_session.victories or not winner_side then
    return
  end

  if winner_side ~= "red" and winner_side ~= "blue" then
    return
  end

  character_session.victories[winner_side] = (character_session.victories[winner_side] or 0) + 1
end

local function victory_digit_quad(side, count)
  if not score_text_q or not score_text_q[side] then
    return nil
  end

  local quads = score_text_q[side]
  local index = math.min(math.max(count + 1, 1), #quads)
  return quads[index]
end

local function draw_victory_count(side, bg_left, bg_right, bg_bottom)
  local count = character_session.victories and character_session.victories[side] or 0

  if VICTORY_COUNT_PREVIEW then
    count = VICTORY_PREVIEW_COUNTS[side] or count
  end

  if count <= 0 or not graphic_sheet then
    return
  end

  local count_text = tostring(count)
  local digit_scale = VICTORY_DIGIT_SCALE
  if #count_text >= 2 then
    digit_scale = digit_scale * 0.82
  end
  if #count_text >= 3 then
    digit_scale = digit_scale * 0.82
  end

  local digits = {}
  local total_w = 0
  local digit_h = 0

  for i = 1, #count_text do
    local value = tonumber(count_text:sub(i, i))
    local quad = victory_digit_quad(side, value)
    if quad then
      local _, _, qw, qh = quad:getViewport()
      local dw = qw * digit_scale
      local dh = qh * digit_scale
      table.insert(digits, { quad = quad, w = dw })
      total_w = total_w + dw
      digit_h = math.max(digit_h, dh)
    end
  end

  if #digits == 0 then
    return
  end

  local y = bg_bottom - digit_h / 2
  local x = side == "red" and bg_left or (bg_right - total_w)

  love.graphics.setColor(1, 1, 1, 1)
  for _, digit in ipairs(digits) do
    love.graphics.draw(graphic_sheet, digit.quad, x, y, 0, digit_scale, digit_scale)
    x = x + digit.w
  end
end

local function character_draw_scale(portrait_image)
  if not portrait_image then
    return PORTRAIT_DISPLAY_SIZE / FULL_PORTRAIT_SOURCE_SIZE
  end

  if PREBAKED_CHARACTER_SPRITES then
    -- Same scale for portrait and bg preserves the 80x96 vs 64x64 source ratio.
    return PORTRAIT_DISPLAY_SIZE / portrait_image:getWidth()
  end

  return PORTRAIT_DISPLAY_SIZE / FULL_PORTRAIT_SOURCE_SIZE
end

local function draw_side_portrait(side)
  local index = character_session[side]
  local layout = CHARACTER_LAYOUT[side]
  if not index or not layout then
    return
  end

  local portrait = character_portraits[index]
  if not portrait or not portrait.image then
    return
  end

  local portrait_size = layout.size
  local center_x = layout.x + portrait_size / 2
  local center_y = layout.y + portrait_size / 2
  local portrait_scale = character_draw_scale(portrait.image)
  local bg_width = character_bg_display_width()
  local bg_height = character_bg_display_height()
  local bg_left = center_x - bg_width / 2
  local bg_right = center_x + bg_width / 2
  local bg_bottom = center_y + bg_height / 2

  love.graphics.setColor(1, 1, 1, 1)

  local background = character_backgrounds[side]
  if background then
    local bg_origin_x = background:getWidth() / 2
    local bg_origin_y = background:getHeight() / 2
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.draw(
      background,
      center_x,
      center_y,
      0,
      portrait_scale,
      portrait_scale,
      bg_origin_x,
      bg_origin_y
    )
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(portrait.image, layout.x, layout.y, 0, portrait_scale, portrait_scale)
  draw_victory_count(side, bg_left, bg_right, bg_bottom)
end

function draw_character_portraits()
  draw_side_portrait("red")
  draw_side_portrait("blue")
end
