local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer     = require("ffi/blitbuffer")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")

local BoardWidget = lrequire("board_widget")

local C_BG   = Blitbuffer.COLOR_WHITE
local C_LINE = Blitbuffer.COLOR_BLACK

-- ---------------------------------------------------------------------------
-- ColorPaletteWidget — a row of swatches, one per marking the player can
-- apply (each colour, then the "known empty" mark). Each swatch is painted
-- exactly like a grid cell with that value, so the player can match them at
-- a glance. The active swatch gets a thick frame.
-- ---------------------------------------------------------------------------

local ColorPaletteWidget = InputContainer:extend{
    values       = nil,  -- e.g. { 1, 2, 3, MARKED }
    marked_value = nil,  -- the value in `values` that means "known empty"
    active       = nil,  -- currently selected value
    side         = 40,   -- swatch size in px
    gap          = 10,   -- space between swatches in px
    display_mode = "original",
    -- Grid cell size, so stripes and dots use the same scale as on the board.
    texture_cell = nil,
    on_select    = nil,  -- function(value)
    -- Top-level widget (the game screen) to mark dirty on repaint.
    show_parent  = nil,
}

function ColorPaletteWidget:init()
    local n = #self.values
    self.dimen      = Geom:new{ w = n * self.side + (n - 1) * self.gap, h = self.side }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h }
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            }
        },
    }
end

function ColorPaletteWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local local_x = ges.pos.x - self.paint_rect.x
    local i = math.floor(local_x / (self.side + self.gap)) + 1
    -- Taps in the gap after a swatch don't count.
    if i < 1 or i > #self.values or local_x - (i - 1) * (self.side + self.gap) >= self.side then
        return false
    end
    local value = self.values[i]
    if value ~= self.active then
        self.active = value
        self:refresh()
        if self.on_select then self.on_select(value) end
    end
    return true
end

-- UIManager only repaints top-level widgets (setDirty on a nested widget
-- like this one is ignored), so mark the screen dirty and refresh only our
-- region, like KOReader's Button does with its show_parent.
function ColorPaletteWidget:refresh()
    UIManager:setDirty(self.show_parent or self, function() return "ui", self.paint_rect end)
end

function ColorPaletteWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    local s      = self.side
    local tcell  = self.texture_cell or s
    local thin   = 1
    -- Active frame: thick black border, then a white ring inside it so the
    -- frame still stands out against the solid black swatch.
    local thick  = math.max(3, math.floor(s / 10))
    local ring   = math.max(2, math.floor(s / 20))

    for i, v in ipairs(self.values) do
        local sx = x + (i - 1) * (s + self.gap)
        local active = (v == self.active)
        local border = active and thick or thin
        local inset  = active and (thick + ring) or thin
        local fx, fy, fw, fh = sx + inset, y + inset, s - 2 * inset, s - 2 * inset

        bb:paintRect(sx, y, s, s, C_LINE)
        bb:paintRect(sx + border, y + border, s - 2 * border, s - 2 * border, C_BG)
        if v == self.marked_value then
            BoardWidget.paintMark(bb, fx, fy, fw, fh)
        else
            BoardWidget.paintStyle(bb, self.display_mode, v, fx, fy, fw, fh, fx, fy, tcell)
        end
    end
end

return ColorPaletteWidget
