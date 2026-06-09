local class = require("libs/middleclass/middleclass")

Hand = class("Hand")

function Hand:create_empty(side, opts)
    opts = opts or {}
    local hand = self:allocate()
    hand.cards = {}
    hand.side = side
    hand.selected_card = nil
    hand.ai_controlled = false
    hand.hidden = opts.hidden or false
    return hand
end

function Hand:initialize(side, ai, opts)
    opts = opts or {}
    self.cards = {}
    self.side = side
    self.selected_card = nil
    self.ai_controlled = ai
    self.hidden = opts.hidden or false

    local i = 0
    while #self.cards < 5 do
        local base_card = BASE_CARDS[math.random(1, #BASE_CARDS - 1)]

        if base_card ~= nil and base_card.id ~= nil then
            local c = Card:new(base_card, self.side)

            if c then
                table.insert(self.cards, c)
                i = i + 1
            end
        end
    end
end

function Hand:draw(x, y)
    local card_height = 51
    local card_width = 42
    local s = 1

    if #self.cards == 5 then
        s = (42 / card_height)
        card_height = 42
        card_width = 35
    end

    if self.ai_controlled or self.hidden then
        if #self.cards > 0 then
            local s = 42 / 51
            local stack_offset = 10

            love.graphics.setColor(1, 1, 1)
            for i = 1, #self.cards do
                local card_y = y + (i - 1) * stack_offset
                love.graphics.draw(graphic_sheet, card_back_q, x, card_y, 0, s, s)
            end
        end
        return
    end

    for i, v in ipairs(self.cards) do
        love.graphics.setColor(100 / 255, 100 / 255, 100 / 255, 100 / 255)
        local y = y + ((i - 1) * card_height)

        if not self.selected_card then
            love.graphics.setColor(1, 1, 1)
        end

        if keyboard_focus.area == "hand" and keyboard_focus.hand_index == i and not self.selected_card then
            love.graphics.setColor(1, 1, 1, 200 / 255)
        end

        if self.selected_card then
            if v == self.selected_card then
                love.graphics.setColor(1, 1, 1)
            end
        end

        if self.side == "blue" then
           love.graphics.draw(graphic_sheet, card_back_blue_q, x, y, 0, s, s)
       elseif self.side == "red" then
          love.graphics.draw(graphic_sheet, card_back_red_q, x, y, 0, s, s)
        end

        v:draw(x, y, s, card_height, card_width)
    end

    love.graphics.setColor(1, 1, 1)
end

function Hand:remove_selected_card()
    for i, v in ipairs(self.cards) do
        if v == self.selected_card then
            table.remove(self.cards, i)
            break
        end
    end

    self.selected_card = nil
end

function Hand:index_of(card)
    for i, v in ipairs(self.cards) do
        if v == card then
            return i
        end
    end

    return nil
end

function Hand:remove_card(card)
    for i, v in ipairs(self.cards) do
        if v == card then
            table.remove(self.cards, i)
            if self.selected_card == card then
                self.selected_card = nil
            end
            return true
        end
    end

    return false
end

function Hand:remove_card_at_index(index)
    if not index or index < 1 or index > #self.cards then
        return false
    end

    if self.selected_card == self.cards[index] then
        self.selected_card = nil
    end

    table.remove(self.cards, index)
    return true
end

function Hand:ai_move(on_complete)
    while 1 == 1 do
        local x = math.random(1, 4)
        local y = math.random(1, 4)

        if card_grid[x][y] == nil then
            local card = self.cards[math.random(1, #self.cards)]

            self.selected_card = card

            place_card(x, y, card, function()
              self:remove_selected_card()
              if on_complete then
                on_complete()
              end
            end)
            return
        end
    end
end
