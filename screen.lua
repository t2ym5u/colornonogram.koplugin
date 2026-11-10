local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase                = require("screen_base")
local MenuHelper                = require("menu_helper")
local GenProgress               = require("gen_progress")
local ColorNonogramBoard        = lrequire("board")
local ColorNonogramBoardWidget  = lrequire("board_widget")
local ColorPaletteWidget        = lrequire("palette_widget")

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Colour Nonogram — Rules

Fill cells with colours to match the clues for each row and column.

Rules:
• Each clue shows a number and a colour — that many consecutive cells must be filled with that colour in that row or column.
• Multiple clues mean multiple runs, in order from top/left to bottom/right.
• Runs of the same colour must have at least one empty cell between them.
• Runs of different colours may be directly adjacent (no gap needed).

Pick a colour, or the X to mark cells known to be empty, from the palette below the board. Then tap cells to apply it. Tapping a cell that already has it clears the cell.
]])

local GAME_RULES_FR = [[
Nonogramme Couleur — Règles

Colorez les cases pour correspondre aux indices de chaque ligne et colonne.

Règles :
• Chaque indice indique un nombre et une couleur — autant de cases consécutives de cette couleur doivent être remplies dans cette ligne ou colonne.
• Plusieurs indices signifient plusieurs séquences, dans l'ordre de haut en bas ou de gauche à droite.
• Deux séquences de couleurs différentes peuvent être directement adjacentes (sans case vide entre elles).
• Deux séquences de la même couleur doivent avoir au moins une case vide entre elles.

Choisissez une couleur, ou le X pour marquer les cases vides, dans la palette sous la grille. Puis appuyez sur les cases pour l'appliquer. Appuyer sur une case qui l'a déjà la vide.
]]

local ColorNonogramScreen = ScreenBase:extend{}

function ColorNonogramScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", ColorNonogramBoard.DEFAULT_N)
    local diff  = self.plugin:getSetting("difficulty", "medium")
    self.board  = ColorNonogramBoard:new{ n = n, difficulty = diff, empty = true }
    if not self.board:load(state) then
        GenProgress.run(function(on_progress) self.board:generate(diff, on_progress) end)
    end
    -- The marking a cell tap applies: a colour 1..NUM_COLORS, or MARKED.
    self.active_value = 1
    ScreenBase.init(self)
    -- ScreenBase.init only asks for a "ui" refresh, which on colour e-ink
    -- shows the colours with a greyscale waveform.
    if self:isColorMode() then self:refreshScreen() end
end

function ColorNonogramScreen:isColorMode()
    return ColorNonogramBoardWidget.isColorMode(self:getDisplayMode())
end

-- Flashing whole-screen refresh. On colour e-ink, KOReader only uses its
-- colour waveform (GCC16 here) for a "full" refresh flagged as dithered;
-- "ui"/"flashui" always use greyscale ones. Cell taps stay plain "ui" (no
-- flash, but ghosting builds up), so this runs when the game opens, on a
-- new game, on a display mode switch, and from the "Refresh screen" menu
-- item.
function ColorNonogramScreen:refreshScreen()
    if self:isColorMode() then
        UIManager:setDirty(self, function() return "full", nil, true end)
    else
        UIManager:setDirty(self, "flashui")
    end
end

function ColorNonogramScreen:serializeState()
    return self.board:serialize()
end

function ColorNonogramScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Color Nonogram"), function()
        return {
            { text = _("New game"),            callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = self:getSizeButtonText(), callback = function() self:openSizeMenu() end },
            { text = self:getDiffButtonText(), callback = function() self:openDifficultyMenu() end },
            { text = self:getDisplayButtonText(), callback = function() self:openDisplayMenu() end },
            { text = _("Show solution"),       callback = function() self:onReveal() end },
            { text = _("Refresh screen"),      callback = function() self:refreshScreen() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar({
            { text = _("Check"), callback = function() self:onCheck() end },
            { text = _("Hint"),  callback = function() self:onHint() end },
            { text = _("Clear"), callback = function() self:onClear() end },
            { text = _("Undo"),  callback = function() self:onUndo() end },
        }),
    }

    -- The widget draws its own thick outer border around clues and grid, so
    -- the frame stays borderless: one visible edge around the board, not two.
    -- Clues make the board wider and taller than the grid alone, so it is
    -- fitted to both budget dimensions rather than to a square.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * frame_pad
    self.palette = self:buildPalette()
    local palette_h = self.palette:getSize().h + Size.span.vertical_large
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = ColorNonogramBoardWidget:new{
        board        = self.board,
        max_width    = budget_w - frame_extra,
        max_height   = budget_h - palette_h - frame_extra,
        display_mode = self:getDisplayMode(),
        onCellTap_cb = function(r, c) self:onCellTap(r, c) end,
        show_parent  = self,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    local board_and_palette = VerticalGroup:new{
        align = "center",
        board_frame,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self.palette,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_and_palette,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_and_palette,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function ColorNonogramScreen:buildPalette()
    local values = {}
    for v = 1, ColorNonogramBoard.NUM_COLORS do values[#values + 1] = v end
    values[#values + 1] = ColorNonogramBoard.MARKED
    return ColorPaletteWidget:new{
        values       = values,
        marked_value = ColorNonogramBoard.MARKED,
        active       = self.active_value,
        side         = DeviceScreen:scaleBySize(44),
        gap          = Size.span.horizontal_default,
        display_mode = self:getDisplayMode(),
        on_select    = function(value) self.active_value = value end,
        show_parent  = self,
    }
end

function ColorNonogramScreen:onCellTap(r, c)
    self.board:paintCell(r, c, self.active_value)
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    if self.board:isWon() then
        self:updateStatus(_("Congratulations! Puzzle solved!"))
    else
        self:updateStatus()
    end
end

function ColorNonogramScreen:onCheck()
    self.board:check()
    self.board_widget:refresh()
    if self.board:isWon() then
        self:updateStatus(_("Congratulations! Puzzle solved!"))
    else
        self:updateStatus(_("Wrong cells marked."))
    end
end

function ColorNonogramScreen:onClear()
    self.board:clearUser()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateStatus(_("Board cleared."))
end

function ColorNonogramScreen:onReveal()
    self.board:reveal()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateStatus(_("Solution revealed."))
end

function ColorNonogramScreen:onUndo()
    if self.board:undoMove() then
        self.board_widget:refresh()
        self.plugin:saveState(self.board:serialize())
        self:updateStatus()
    end
end

function ColorNonogramScreen:onNewGame()
    local n    = self.plugin:getSetting("grid_n", ColorNonogramBoard.DEFAULT_N)
    local diff = self.plugin:getSetting("difficulty", "medium")
    self.board  = ColorNonogramBoard:new{ n = n, difficulty = diff, empty = true }
    GenProgress.run(function(on_progress) self.board:generate(diff, on_progress) end)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    -- Colour modes: flash to clear ghosting from the last puzzle. Patterns
    -- mode keeps its plain refresh, as before.
    if self:isColorMode() then
        self:refreshScreen()
    else
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
end

function ColorNonogramScreen:openSizeMenu()
    local sizes = {}
    for _, sz in ipairs(ColorNonogramBoard.SIZES) do
        sizes[#sizes + 1] = { id = sz, text = sz .. "\xC3\x97" .. sz }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.plugin:getSetting("grid_n", ColorNonogramBoard.DEFAULT_N),
        parent    = self,
        on_select = function(sz)
            if sz ~= self.board.n then
                self.plugin:saveSetting("grid_n", sz)
                self:onNewGame()
            end
        end,
    }
end

function ColorNonogramScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDiffButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

function ColorNonogramScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board:isWon() then
        status = _("Congratulations! Puzzle solved!")
    else
        local filled = self.board:countFilled()
        local total  = self.board:countSolutionFilled()
        local n      = self.board.n
        local diff   = self.plugin:getSetting("difficulty", "medium")
        local label  = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        status = self:joinStatus(
            T("%1×%1", n),
            label,
            T(_("Filled: %1/%2"), filled, total))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends here, so the bar follows the board.
    self:refreshActionBar()
end

-- Show solution copies the solution in, so it ends the round too.
function ColorNonogramScreen:isRoundOver()
    return self.board:isWon()
end

function ColorNonogramScreen:getSizeButtonText()
    local n = self.board.n
    return T(_("Size: %1"), n .. "\xC3\x97" .. n)
end

-- Until the player picks one, follow KOReader's own colour rendering choice
-- (Settings > Screen > Color rendering, which defaults to on for colour
-- screens), so colour e-readers get colours and greyscale ones get greys.
local DISPLAY_MODES = {
    { id = "original",  text = _("Original") },
    { id = "patterns",  text = _("Patterns") },
    { id = "color",     text = _("Red, green, blue") },
    { id = "color_alt", text = _("Blue, orange, purple") },
}

function ColorNonogramScreen:getDisplayMode()
    local mode = self.plugin:getSetting("display_mode")
    for _, m in ipairs(DISPLAY_MODES) do
        if m.id == mode then return mode end
    end
    return DeviceScreen:isColorEnabled() and "color" or "original"
end

function ColorNonogramScreen:getDisplayButtonText()
    local mode, label = self:getDisplayMode()
    for _, m in ipairs(DISPLAY_MODES) do
        if m.id == mode then label = m.text end
    end
    return T(_("Display: %1"), label)
end

function ColorNonogramScreen:openDisplayMenu()
    MenuHelper.openPickerMenu{
        title      = _("Display"),
        items      = DISPLAY_MODES,
        current_id = self:getDisplayMode(),
        parent     = self,
        on_select  = function(mode)
            self.plugin:saveSetting("display_mode", mode)
            self.board_widget.display_mode = mode
            self.palette.display_mode      = mode
            -- Every filled cell and swatch changes at once; flash to avoid
            -- ghosting on e-ink.
            self:refreshScreen()
        end,
    }
end

function ColorNonogramScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "medium")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Difficulty: %1"), label)
end

return ColorNonogramScreen
