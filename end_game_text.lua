local glow_offsets = {}

for radius = 1, 4 do
  for angle = 0, 15 do
    local radians = angle * math.pi / 8
    table.insert(glow_offsets, {
      math.floor(math.cos(radians) * radius + 0.5),
      math.floor(math.sin(radians) * radius + 0.5),
    })
  end
end

local outcome_styles = {
  WIN = {
    glow = { 0.55, 0.75, 1, 0.22 },
    outline = { 0.92, 0.96, 1, 0.65 },
  },
  LOSE = {
    glow = { 1, 0.3, 0.3, 0.24 },
    outline = { 1, 0.82, 0.82, 0.65 },
  },
  DRAW = {
    glow = { 0.72, 0.72, 0.78, 0.2 },
    outline = { 0.88, 0.88, 0.92, 0.6 },
  },
  PERFECT = {
    glow = { 0.55, 0.75, 1, 0.22 },
    outline = { 0.92, 0.96, 1, 0.65 },
  },
}

function draw_end_game_outcome(label, center_x, center_y)
  if not end_game_font then
    return
  end

  local style = outcome_styles[label] or outcome_styles.WIN
  local glow = style.glow
  local outline = style.outline
  local previous_font = love.graphics.getFont()

  love.graphics.setFont(end_game_font)

  local text_w = end_game_font:getWidth(label)
  local text_h = end_game_font:getHeight()
  local x = center_x - text_w / 2
  local y = center_y - text_h / 2

  for _, off in ipairs(glow_offsets) do
    love.graphics.setColor(glow[1], glow[2], glow[3], glow[4])
    love.graphics.print(label, x + off[1] * 2, y + off[2] * 2)
  end

  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        love.graphics.setColor(outline[1], outline[2], outline[3], outline[4])
        love.graphics.print(label, x + dx, y + dy)
      end
    end
  end

  love.graphics.setColor(0.9, 0.45, 0.1, 0.7)
  love.graphics.print(label, x, y + 1)

  love.graphics.setColor(0.18, 0.2, 0.28)
  love.graphics.print(label, x, y)

  love.graphics.setColor(1, 0.75, 0.22, 0.35)
  love.graphics.print(label, x, y - 1)

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(previous_font)
end
