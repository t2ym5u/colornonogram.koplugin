local Blitbuffer = require("ffi/blitbuffer")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local GestureRange  = require("ui/gesturerange")
local RenderText = require("ui/rendertext")
local UIManager  = require("ui/uimanager")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

-- ---------------------------------------------------------------------------
-- Colors
-- Color index → e-ink gray shade:
--   0 = empty (white)
--   1 = dark gray (GRAY_4)
--   2 = medium gray (GRAY_9)
--   3 = light gray (GRAY_D)
-- ---------------------------------------------------------------------------

local CELL_COLORS = {
    [0] = Blitbuffer.COLOR_WHITE,
    [1] = Blitbuffer.COLOR_GRAY_4,
    [2] = Blitbuffer.COLOR_GRAY_9,
    [3] = Blitbuffer.COLOR_GRAY_D,
}
-- Text color on top of each shade (for the digit inside clue)
local CELL_TEXT_COLOR = {
    [0] = Blitbuffer.COLOR_BLACK,
    [1] = Blitbuffer.COLOR_WHITE,
    [2] = Blitbuffer.COLOR_BLACK,
    [3] = Blitbuffer.COLOR_BLACK,
}

local C_BG        = Blitbuffer.COLOR_WHITE
local C_LINE      = Blitbuffer.COLOR_BLACK
local C_CLUE_BG   = Blitbuffer.COLOR_GRAY_E
local C_WRONG_DOT = Blitbuffer.COLOR_GRAY_4

-- ---------------------------------------------------------------------------
-- ColorNonogramBoardWidget
--
-- Layout:
--   Top-left corner:       empty
--   Top strip (clue_h):    column clues
--   Left strip (clue_w):   row clues
--   Main area (size×size): user grid
-- ---------------------------------------------------------------------------

local ColorNonogramBoardWidget = GridWidgetBase:extend{
    board      = nil,
    size_ratio = 0.65,
}

function ColorNonogramBoardWidget:init()
    local n = self.board.n
    self.cols = n
    self.rows = n
    GridWidgetBase.init(self)

    -- Clue area sizes: each clue entry takes one cell-sized slot
    local max_row_clue_len = 0
    for r = 1, n do
        local l = #self.board.row_clues[r]
        if l > max_row_clue_len then max_row_clue_len = l end
    end
    local max_col_clue_len = 0
    for c = 1, n do
        local l = #self.board.col_clues[c]
        if l > max_col_clue_len then max_col_clue_len = l end
    end

    self.clue_w = math.ceil(max_row_clue_len * self.cell_w)
    self.clue_h = math.ceil(max_col_clue_len * self.cell_h)

    local total_w = self.clue_w + self.size
    local total_h = self.clue_h + self.size
    self.dimen      = Geom:new{ w = total_w, h = total_h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = total_w, h = total_h }

    self.grid_ox = self.clue_w
    self.grid_oy = self.clue_h

    local cell_min  = math.min(self.cell_w, self.cell_h)
    local clue_size = math.max(8, math.floor(cell_min * 0.50))
    self.clue_face  = Font:getFace("cfont", clue_size)

    -- Re-register gesture events with new paint_rect
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges   = "tap",
                range = function() return self.paint_rect end,
            }
        },
    }
end

-- Override getCellFromPoint to account for clue offset
function ColorNonogramBoardWidget:getCellFromPoint(x, y)
    local local_x = x - self.paint_rect.x - self.grid_ox
    local local_y = y - self.paint_rect.y - self.grid_oy
    if local_x < 0 or local_y < 0 then return nil end
    local col = math.min(self.cols, math.floor(local_x / self.cell_w) + 1)
    local row = math.min(self.rows, math.floor(local_y / self.cell_h) + 1)
    if row < 1 or col < 1 then return nil end
    return row, col
end

function ColorNonogramBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then return false end
    local row, col = self:getCellFromPoint(ges.pos.x, ges.pos.y)
    if not row then return false end
    if self.onCellTap_cb then self.onCellTap_cb(row, col) end
    return true
end

function ColorNonogramBoardWidget:refresh()
    local rect = self.paint_rect
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end)
end

-- ---------------------------------------------------------------------------
-- paintTo
-- ---------------------------------------------------------------------------

function ColorNonogramBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board  = self.board
    local n      = board.n
    local cw     = self.cell_w
    local ch     = self.cell_h
    local ox     = x + self.grid_ox
    local oy     = y + self.grid_oy
    local gsize  = self.size

    -- Background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    -- Clue area background
    bb:paintRect(x, y,              self.clue_w,          self.clue_h,          C_CLUE_BG)
    bb:paintRect(x, y + self.clue_h, self.clue_w,         gsize,                C_CLUE_BG)
    bb:paintRect(x + self.clue_w, y, gsize,                self.clue_h,          C_CLUE_BG)

    local face       = self.clue_face
    local clue_tc    = Blitbuffer.COLOR_BLACK

    -- Helper: draw a colored rectangle with number inside
    local function drawClueEntry(bx, by, bw, bh, color_idx, len_val)
        if color_idx and color_idx > 0 then
            local bg = CELL_COLORS[color_idx] or C_CLUE_BG
            bb:paintRect(bx + 1, by + 1, bw - 2, bh - 2, bg)
            local tc = CELL_TEXT_COLOR[color_idx] or C_LINE
            local txt = tostring(len_val)
            local m   = RenderText:sizeUtf8Text(0, bw - 2, face, txt, true, false)
            local tx  = bx + math.floor((bw - m.x) / 2)
            local ty  = by + math.floor((bh - (m.y_bottom - m.y_top)) / 2) - m.y_top
            RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, tc)
        end
    end

    -- Draw column clues (top area, each column)
    for c = 1, n do
        local clue     = board.col_clues[c]
        local num      = #clue
        local col_x    = ox + math.floor((c - 1) * cw)
        for i = 1, num do
            local entry           = clue[i]
            local slot_from_bottom = num - i
            local slot_y = y + self.clue_h - math.floor((slot_from_bottom + 1) * ch)
            if slot_y < y then slot_y = y end
            if entry.color and entry.color > 0 then
                drawClueEntry(col_x, slot_y, math.ceil(cw), math.ceil(ch),
                              entry.color, entry.len)
            else
                -- Empty clue: just a dash
                local txt = "-"
                local m   = RenderText:sizeUtf8Text(0, math.floor(cw), face, txt, true, false)
                local tx  = col_x + math.floor((cw - m.x) / 2)
                local ty  = slot_y + math.floor((ch - (m.y_bottom - m.y_top)) / 2) - m.y_top
                RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, clue_tc)
            end
        end
    end

    -- Draw row clues (left area, each row)
    for r = 1, n do
        local clue  = board.row_clues[r]
        local num   = #clue
        local row_y = oy + math.floor((r - 1) * ch)
        for i = 1, num do
            local entry           = clue[i]
            local slot_from_right = num - i
            local slot_x = x + self.clue_w - math.floor((slot_from_right + 1) * cw)
            if slot_x < x then slot_x = x end
            if entry.color and entry.color > 0 then
                drawClueEntry(slot_x, row_y, math.ceil(cw), math.ceil(ch),
                              entry.color, entry.len)
            else
                local txt = "-"
                local m   = RenderText:sizeUtf8Text(0, math.floor(cw), face, txt, true, false)
                local tx  = slot_x + math.floor((cw - m.x) / 2)
                local ty  = row_y + math.floor((ch - (m.y_bottom - m.y_top)) / 2) - m.y_top
                RenderText:renderUtf8Text(bb, tx, ty, face, txt, true, false, clue_tc)
            end
        end
    end

    -- Draw user grid cells
    for r = 1, n do
        for c = 1, n do
            local cx   = ox + math.floor((c - 1) * cw)
            local cy   = oy + math.floor((r - 1) * ch)
            local cew  = math.ceil(cw)
            local ceh  = math.ceil(ch)
            local v    = board.user[r][c]
            local bg   = CELL_COLORS[v] or C_BG
            if bg ~= C_BG then
                bb:paintRect(cx, cy, cew, ceh, bg)
            end
            -- Wrong mark: small dot in corner
            if board.wrong[r][c] then
                local dot = math.max(2, math.floor(math.min(cew, ceh) / 6))
                local pad = math.max(1, math.floor(math.min(cew, ceh) / 10))
                bb:paintRect(cx + cew - pad - dot, cy + pad, dot, dot, C_WRONG_DOT)
            end
        end
    end

    -- Grid lines for main area
    local thin_line  = 1
    local thick_line = math.max(2, math.floor(math.min(cw, ch) / 10))
    for i = 0, n do
        local lw = (i == 0 or i == n) and thick_line or thin_line
        local px = ox + math.floor(i * cw)
        local py = oy + math.floor(i * ch)
        drawLine(bb, px, oy, lw, gsize, C_LINE)
        drawLine(bb, ox, py, gsize, lw, C_LINE)
    end

    -- Outer border for the whole widget
    local bthick = thick_line
    drawLine(bb, x, y, bthick, self.dimen.h, C_LINE)
    drawLine(bb, x + self.dimen.w - bthick, y, bthick, self.dimen.h, C_LINE)
    drawLine(bb, x, y, self.dimen.w, bthick, C_LINE)
    drawLine(bb, x, y + self.dimen.h - bthick, self.dimen.w, bthick, C_LINE)
end

return ColorNonogramBoardWidget
