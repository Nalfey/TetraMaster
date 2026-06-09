local class = require("libs/middleclass/middleclass")

Card = class("Card")

function Card:initialize(base_card, side)
    if not self:check_base_card(base_card) then
        return false
    end

    self.card_id = base_card.id
    self.name = base_card.name
    self.attack = base_card.attack
    self.type = base_card.type
    self.physical_defense = base_card.physical_defense
    self.magical_defense = base_card.magical_defense

    self.attack_string = base_card.attack_string
    self.physical_defense_string = base_card.physical_defense_string
    self.magical_defense_string = base_card.magical_defense_string

    self.side = side

    self.arrows = {}

    local directions = {"up",
                        "down",
                        "left",
                        "right",
                        "upleft",
                        "upright",
                        "downleft",
                        "downright"
                       }

    for i, v in ipairs(directions) do
        if math.random(1, 2) == 1 then
            self.arrows[v] = true
        end
    end
end

function Card:check_base_card(base_card)
  if base_card.id and
      base_card.name and
      base_card.attack and
      base_card.type and
      base_card.physical_defense and
      base_card.magical_defense then
      return true
  end


    return false
end

function Card.from_snapshot(snapshot, side)
    local card = setmetatable({}, { __index = Card })

    card.card_id = tonumber(snapshot.card_id) or snapshot.card_id
    card.name = snapshot.name
    card.attack = tonumber(snapshot.attack) or snapshot.attack
    card.type = snapshot.type
    card.physical_defense = tonumber(snapshot.physical_defense) or snapshot.physical_defense
    card.magical_defense = tonumber(snapshot.magical_defense) or snapshot.magical_defense
    card.attack_string = snapshot.attack_string
    card.physical_defense_string = snapshot.physical_defense_string
    card.magical_defense_string = snapshot.magical_defense_string
    card.side = side
    card.uid = tonumber(snapshot.uid) or snapshot.uid
    card.arrows = {}

    for _, name in ipairs(snapshot.arrows or {}) do
        card.arrows[name] = true
    end

    return card
end

function Card:draw(x, y, s, card_height, card_width)
    local quad = cards_q[self.card_id]
    if not quad then
        return
    end

    love.graphics.draw(graphic_sheet, quad, x, y, 0, s, s)

    local card_height = card_height or 51
    local card_width = card_width or 42
    local arrow_height = 5
    local x_offset = 18
    local y_offset = 22

    if card_height == 42 then
        y_offset = 17
        x_offset = 13
    end

    -- Arrows
    if self.arrows["up"] then
        love.graphics.draw(graphic_sheet, arrow_q["up"], x + x_offset, y)
    end

    if self.arrows["down"] then
        love.graphics.draw(graphic_sheet, arrow_q["down"], x + x_offset, y + card_height - 8)
    end

    if self.arrows["left"] then
        love.graphics.draw(graphic_sheet, arrow_q["left"], x, y + y_offset)
    end

    if self.arrows["right"] then
        love.graphics.draw(graphic_sheet, arrow_q["right"], x + card_width - 8, y + y_offset)
    end

    if self.arrows["upleft"] then
        love.graphics.draw(graphic_sheet, arrow_q["upleft"], x, y)
    end

    if self.arrows["downleft"] then
        love.graphics.draw(graphic_sheet, arrow_q["downleft"], x, y + card_height - 8)
    end

    if self.arrows["downright"] then
        love.graphics.draw(graphic_sheet, arrow_q["downright"], x + card_width - 8, y + card_height - 8)
    end

    if self.arrows["upright"] then
        love.graphics.draw(graphic_sheet, arrow_q["upright"], x + card_width - 8, y)
    end

    local text_x = (card_width / 2) - ((6 * 4) / 2) + x
    local text_y = card_height - 15 + y

    love.graphics.draw(graphic_sheet, stat_text_q[tostring(self.attack_string)], text_x, text_y)
    love.graphics.draw(graphic_sheet, stat_text_q[tostring(self.type)], text_x + 6, text_y)
    love.graphics.draw(graphic_sheet, stat_text_q[tostring(self.physical_defense_string)], text_x + 12, text_y)
    love.graphics.draw(graphic_sheet, stat_text_q[tostring(self.magical_defense_string)], text_x + 18, text_y)
end
