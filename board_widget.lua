local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local GestureRange  = require("ui/gesturerange")
local RenderText = require("ui/rendertext")
local UIManager  = require("ui/uimanager")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine
local drawDiagonalLine = gwb.drawDiagonalLine

local Screen         = Device.screen

-- ---------------------------------------------------------------------------
-- Cell styles
--
-- 4 display modes, picked by the screen:
--   "original"  — for greyscale e-ink.
--   "patterns"  — for greyscale e-ink. Three grey shades alone are hard to
--                 tell apart on e-ink, so each colour index also gets its own
--                 texture: 1 = solid black, 2 = horizontal stripes,
--                 3 = dots on light grey.
--   "color"     — for colour e-ink: red, green, blue. Fully saturated
--                 primaries stay distinct on the muted colour filter of
--                 colour e-ink screens, and each maps to a different primary
--                 of that filter.
--   "color_alt" — blue, orange, purple, for players who can't tell red from
--                 green. The three also differ in lightness (orange is light,
--                 blue and purple dark), which helps with other kinds of
--                 colour blindness too.
-- All values come from KOReader's own highlight palette
-- (Blitbuffer.HIGHLIGHT_COLORS), which is used on colour e-ink already.
-- ---------------------------------------------------------------------------

local C_BG        = Blitbuffer.COLOR_WHITE
local C_LINE      = Blitbuffer.COLOR_BLACK
local C_CLUE_BG   = Blitbuffer.COLOR_GRAY_E

local PALETTES = {
    original = {
        [1] = Blitbuffer.COLOR_GRAY_4,
        [2] = Blitbuffer.COLOR_GRAY_9,
        [3] = Blitbuffer.COLOR_GRAY_D,
    },
    patterns = {
        [1] = Blitbuffer.COLOR_BLACK,
        [2] = Blitbuffer.COLOR_WHITE,
        [3] = Blitbuffer.COLOR_GRAY_D,
    },
    color = {
        [1] = Blitbuffer.colorFromString("#FF3300"), -- red
        [2] = Blitbuffer.colorFromString("#00AA66"), -- green
        [3] = Blitbuffer.colorFromString("#0066FF"), -- blue
    },
    color_alt = {
        [1] = Blitbuffer.colorFromString("#0066FF"), -- blue
        [2] = Blitbuffer.colorFromString("#FF8800"), -- orange
        [3] = Blitbuffer.colorFromString("#EE00FF"), -- purple
    },
}

-- True for the display modes that paint RGB colours (see PALETTES).
local function isColorMode(mode)
    return PALETTES[mode] ~= nil
end

-- Stripes and dots are aligned to (ax, ay) instead of each cell's corner,
-- so a run of same-colour cells reads as one continuous texture.
local function firstStep(from, anchor, period)
    return anchor + math.ceil((from - anchor) / period) * period
end

local function paintStripes(bb, x, y, w, h, ax, ay, period, thick)
    local yy = firstStep(y, ay, period)
    while yy < y + h do
        bb:paintRect(x, yy, w, math.min(thick, y + h - yy), C_LINE)
        yy = yy + period
    end
end

local function paintDots(bb, x, y, w, h, ax, ay, period, thick)
    -- Offset by half a period so dots don't sit on the grid lines.
    local half = math.floor(period / 2)
    local yy = firstStep(y, ay + half, period)
    while yy < y + h do
        local xx = firstStep(x, ax + half, period)
        while xx < x + w do
            bb:paintRect(xx, yy, math.min(thick, x + w - xx), math.min(thick, y + h - yy), C_LINE)
            xx = xx + period
        end
        yy = yy + period
    end
end

-- Paint colour index v (1..3) into a rect. The texture scale follows the
-- cell size, so it stays visible on small cells and isn't noisy on big ones.
local function paintStyle(bb, mode, v, x, y, w, h, ax, ay, cell)
    local palette = PALETTES[mode]
    if not palette then
        return
    end
    local c = palette[v]
    -- The framebuffer is inverted in night mode; pre-invert colours so the hue
    -- stays the same, as ReaderView does for highlight colours.
    if (mode == "color" or mode == "color_alt") and Screen.night_mode then c = c:invert() end
    bb:paintRectRGB32(x, y, w, h, c)
    if mode ~= "patterns" or v < 2 then
        return
    end
    local period = math.max(4, math.floor(cell / 5))
    local thick  = math.max(1, math.floor(period / 3))
    if v == 2 then
        paintStripes(bb, x, y, w, h, ax, ay, period, thick)
    elseif v == 3 then
        paintDots(bb, x, y, w, h, ax, ay, period, thick + 1)
    end
end

-- The "known empty" mark: same X as nonogram.koplugin's crossed cells.
local function paintMark(bb, x, y, w, h)
    local pad   = math.max(2, math.floor(math.min(w, h) / 8))
    local dlen  = math.max(0, math.floor(math.min(w, h) - pad * 2))
    local thick = math.max(1, math.floor(math.min(w, h) / 12))
    drawDiagonalLine(bb, x + pad, y + pad,     dlen, 1,  1, C_LINE, thick)
    drawDiagonalLine(bb, x + pad, y + h - pad, dlen, 1, -1, C_LINE, thick)
end

-- Clue number colour: white on dark fills, black on light ones (e.g. the
-- orange), judged by the fill's luminance.
local function clueTextColor(mode, v)
    if mode == "original" or mode == "patterns" then
        return v == 1 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    end
    local palette = PALETTES[mode]
    if not palette then
        return Blitbuffer.COLOR_BLACK
    end
    local c = palette[v]
    local luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    return luma < 128 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
end

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
    max_width  = nil,   -- pixel budget for clues + grid (nil = unbounded)
    max_height = nil,
    -- "original", "patterns", "color" or "color_alt", see Cell styles above.
    display_mode = "original",
    -- Top-level widget (the game screen) to mark dirty on refresh().
    show_parent = nil,
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

    -- The base sizes the grid alone from size_ratio, but the clue strips
    -- add max_row_clue_len columns and max_col_clue_len rows of cells on
    -- top of it, which pushed the grid off-screen on clue-heavy puzzles.
    -- Pick one cell size so clues + grid fit max_width x max_height.
    -- Given a budget, fill it; without one, keep the base's size_ratio.
    local cell = math.min(self.cell_w, self.cell_h)
    if self.max_width or self.max_height then
        cell = math.huge
        if self.max_width then
            cell = math.min(cell, self.max_width / (n + max_row_clue_len))
        end
        if self.max_height then
            cell = math.min(cell, self.max_height / (n + max_col_clue_len))
        end
    end
    cell = math.max(8, math.floor(cell))
    self.size      = cell * n
    self.cell_w    = cell
    self.cell_h    = cell
    self.cell_w_px = cell
    self.cell_h_px = cell

    self.clue_w = max_row_clue_len * cell
    self.clue_h = max_col_clue_len * cell

    local total_w = self.clue_w + self.size
    local total_h = self.clue_h + self.size
    self.dimen      = Geom:new{ w = total_w, h = total_h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = total_w, h = total_h }

    self.grid_ox = self.clue_w
    self.grid_oy = self.clue_h

    -- Largest clue font whose widest number fits a clue slot. Font:getFace
    -- scales its size by DPI, so measure rather than derive it from pixels;
    -- measure unbounded, since sizeUtf8Text truncates at its width argument.
    local sample = tostring(n):gsub("%d", "8")
    local lo, hi, best = 6, math.max(6, cell), 6
    while lo <= hi do
        local mid  = math.floor((lo + hi) / 2)
        local face = Font:getFace("cfont", mid)
        local m    = RenderText:sizeUtf8Text(0, math.huge, face, sample, true, false)
        if m.x <= cell * 0.8 and (m.y_top + m.y_bottom) <= cell * 0.6 then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    self.clue_face = Font:getFace("cfont", best)

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

-- Mark the top-level screen dirty: UIManager ignores setDirty on nested
-- widgets. Callers so far happened to also update the status line (which
-- dirties the screen), which is the only reason this used to work.
function ColorNonogramBoardWidget:refresh()
    local rect = self.paint_rect
    -- Plain "ui" even in colour modes: on colour e-ink the colour waveforms
    -- (dithered "partial"/"full") always do a flashing full update, which
    -- made the whole screen flash on every tap. The screen does a colour
    -- flash refresh at set points instead (see refreshScreen in screen.lua).
    UIManager:setDirty(self.show_parent or self, function()
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
    local MARKED = board.MARKED
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
    local mode       = self.display_mode
    local cell       = math.min(cw, ch)

    -- Helper: draw a colored rectangle with number inside
    local function drawClueEntry(bx, by, bw, bh, color_idx, len_val)
        if color_idx and color_idx > 0 then
            paintStyle(bb, mode, color_idx, bx + 1, by + 1, bw - 2, bh - 2, bx, by, cell)
            local tc = clueTextColor(mode, color_idx)
            local txt = tostring(len_val)
            local m   = RenderText:sizeUtf8Text(0, math.huge, face, txt, true, false)
            local tx  = bx + math.floor((bw - m.x) / 2)
            local ty  = by + math.floor((bh - (m.y_bottom - m.y_top)) / 2)
            if mode == "patterns" and color_idx ~= 1 then
                -- Black stripes and dots would eat into black digits. A thin
                -- white halo that follows the glyph shapes keeps them
                -- readable while the texture stays visible around them,
                -- unlike a plain backing rectangle.
                local r = math.max(2, math.floor(cell / 20))
                for dx = -r, r, r do
                    for dy = -r, r, r do
                        if dx ~= 0 or dy ~= 0 then
                            RenderText:renderUtf8Text(bb, tx + dx, ty + dy, face, txt, true, false, C_BG)
                        end
                    end
                end
            end
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
                local m   = RenderText:sizeUtf8Text(0, math.huge, face, txt, true, false)
                local tx  = col_x + math.floor((cw - m.x) / 2)
                local ty  = slot_y + math.floor((ch - (m.y_bottom - m.y_top)) / 2)
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
                local m   = RenderText:sizeUtf8Text(0, math.huge, face, txt, true, false)
                local tx  = slot_x + math.floor((cw - m.x) / 2)
                local ty  = row_y + math.floor((ch - (m.y_bottom - m.y_top)) / 2)
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
            if v and v > 0 then
                paintStyle(bb, mode, v, cx, cy, cew, ceh, ox, oy, cell)
            elseif v == MARKED then
                paintMark(bb, cx, cy, cew, ceh)
            end
            -- Wrong mark: small square in corner. Black with a white rim so
            -- it shows on every fill, including solid black and the colours.
            if board.wrong[r][c] then
                local dot = math.max(3, math.floor(math.min(cew, ceh) / 5))
                local pad = math.max(1, math.floor(math.min(cew, ceh) / 10))
                local dx, dy = cx + cew - pad - dot, cy + pad
                bb:paintRect(dx - 1, dy - 1, dot + 2, dot + 2, C_BG)
                bb:paintRect(dx, dy, dot, dot, C_LINE)
            end
        end
    end

    -- Grid lines for main area
    local thin_line  = 1
    local thick_line = math.max(2, math.floor(math.min(cw, ch) / 10))
    for i = 0, n do
        local lw = (i == 0 or i == n) and thick_line or thin_line
        -- The closing line sits inside the grid so it doesn't spill past
        -- the widget's own border.
        local inset = (i == n) and lw or 0
        local px = ox + math.floor(i * cw) - inset
        local py = oy + math.floor(i * ch) - inset
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

-- Shared with the colour palette, so its buttons look like grid cells.
ColorNonogramBoardWidget.paintStyle = paintStyle
ColorNonogramBoardWidget.paintMark  = paintMark
ColorNonogramBoardWidget.isColorMode = isColorMode

return ColorNonogramBoardWidget
