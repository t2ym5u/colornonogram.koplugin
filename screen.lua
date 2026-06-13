local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local ScreenBase                = require("screen_base")
local MenuHelper                = require("menu_helper")
local ColorNonogramBoard        = lrequire("board")
local ColorNonogramBoardWidget  = lrequire("board_widget")

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Colour Nonogram — Rules

Fill cells with colours to match the clues for each row and column.

Rules:
• Each clue shows a number and a colour — that many consecutive cells must be filled with that colour in that row or column.
• Multiple clues mean multiple runs, in order from top/left to bottom/right.
• Runs of the same colour must have at least one empty cell between them.
• Runs of different colours may be directly adjacent (no gap needed).

Tap a cell to cycle through available colours. Mark cells as empty with a long-press.
]])

local GAME_RULES_FR = [[
Nonogramme Couleur — Règles

Colorez les cases pour correspondre aux indices de chaque ligne et colonne.

Règles :
• Chaque indice indique un nombre et une couleur — autant de cases consécutives de cette couleur doivent être remplies dans cette ligne ou colonne.
• Plusieurs indices signifient plusieurs séquences, dans l'ordre de haut en bas ou de gauche à droite.
• Deux séquences de couleurs différentes peuvent être directement adjacentes (sans case vide entre elles).
• Deux séquences de la même couleur doivent avoir au moins une case vide entre elles.

Appuyez sur une case pour faire défiler les couleurs disponibles. Appui long pour marquer une case vide.
]]

local ColorNonogramScreen = ScreenBase:extend{}

function ColorNonogramScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", ColorNonogramBoard.DEFAULT_N)
    local diff  = self.plugin:getSetting("difficulty", "medium")
    self.board  = ColorNonogramBoard:new{ n = n, difficulty = diff }
    if not self.board:load(state) then
        self.board:generate(diff)
    end
    ScreenBase.init(self)
end

function ColorNonogramScreen:serializeState()
    return self.board:serialize()
end

function ColorNonogramScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local is_landscape = self:isLandscape()

    self.board_widget = ColorNonogramBoardWidget:new{
        board        = self.board,
        onCellTap_cb = function(r, c) self:onCellTap(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_total       = self.board_widget.dimen.w + (Size.padding.large + Size.margin.default) * 2
    local right_panel_width = sw - board_total - Size.span.horizontal_default
    local button_width = is_landscape
        and math.max(right_panel_width - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("New"),
              callback = function() self:onNewGame() end },
            { id = "size_button", text = self:getSizeButtonText(),
              callback = function() self:openSizeMenu() end },
            { id = "diff_button", text = self:getDiffButtonText(),
              callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.size_button = top_buttons:getButtonById("size_button")
    self.diff_button = top_buttons:getButtonById("diff_button")

    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("Check"),  callback = function() self:onCheck() end },
            { text = _("Clear"),  callback = function() self:onClear() end },
            { text = _("Reveal"), callback = function() self:onReveal() end },
            { text = _("Undo"),   callback = function() self:onUndo() end },
        }},
    }

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

function ColorNonogramScreen:onCellTap(r, c)
    self.board:tapCell(r, c)
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
    self.board  = ColorNonogramBoard:new{ n = n, difficulty = diff }
    self.board:generate(diff)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function ColorNonogramScreen:openSizeMenu()
    local sizes = {}
    for _, sz in ipairs(ColorNonogramBoard.SIZES) do
        sizes[#sizes + 1] = { id = sz, text = sz .. "\xC3\x97" .. sz }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select grid size"),
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
        status = T(_("%1\xC3\x97%2 \xC2\xB7 %3 \xC2\xB7 Filled: %4/%5"),
                   n, n, label, filled, total)
    end
    ScreenBase.updateStatus(self, status)
end

function ColorNonogramScreen:getSizeButtonText()
    local n = self.board.n
    return T(_("Size: %1"), n .. "\xC3\x97" .. n)
end

function ColorNonogramScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "medium")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Diff: %1"), label)
end

return ColorNonogramScreen
