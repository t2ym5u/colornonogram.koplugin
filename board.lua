local grid_utils = require("grid_utils")
local UndoStack  = require("undo_stack")

local emptyGrid = grid_utils.emptyGrid

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local SIZES      = { 6, 8 }
local DEFAULT_N  = 8
local NUM_COLORS = 3   -- 1, 2, 3 plus 0 = empty

-- ---------------------------------------------------------------------------
-- Clue computation
-- Color nonogram clues: consecutive runs of same color (not empty)
-- ---------------------------------------------------------------------------

local function computeClues(grid, n)
    local row_clues = {}
    local col_clues = {}

    for r = 1, n do
        local clue = {}
        local run_color, run_len = 0, 0
        for c = 1, n do
            local v = grid[r][c]
            if v ~= 0 and v == run_color then
                run_len = run_len + 1
            elseif v ~= 0 then
                if run_color ~= 0 then
                    clue[#clue + 1] = { len = run_len, color = run_color }
                end
                run_color = v
                run_len   = 1
            else
                if run_color ~= 0 then
                    clue[#clue + 1] = { len = run_len, color = run_color }
                end
                run_color = 0
                run_len   = 0
            end
        end
        if run_color ~= 0 then
            clue[#clue + 1] = { len = run_len, color = run_color }
        end
        row_clues[r] = (#clue > 0) and clue or { { len = 0, color = 0 } }
    end

    for c = 1, n do
        local clue = {}
        local run_color, run_len = 0, 0
        for r = 1, n do
            local v = grid[r][c]
            if v ~= 0 and v == run_color then
                run_len = run_len + 1
            elseif v ~= 0 then
                if run_color ~= 0 then
                    clue[#clue + 1] = { len = run_len, color = run_color }
                end
                run_color = v
                run_len   = 1
            else
                if run_color ~= 0 then
                    clue[#clue + 1] = { len = run_len, color = run_color }
                end
                run_color = 0
                run_len   = 0
            end
        end
        if run_color ~= 0 then
            clue[#clue + 1] = { len = run_len, color = run_color }
        end
        col_clues[c] = (#clue > 0) and clue or { { len = 0, color = 0 } }
    end

    return row_clues, col_clues
end

-- ---------------------------------------------------------------------------
-- ColorNonogramBoard
-- ---------------------------------------------------------------------------

local ColorNonogramBoard = {}
ColorNonogramBoard.__index = ColorNonogramBoard

function ColorNonogramBoard:new(opts)
    opts = opts or {}
    local n   = opts.n or DEFAULT_N
    local obj = setmetatable({
        n          = n,
        difficulty = opts.difficulty or "medium",
        solution   = emptyGrid(n, n, 0),
        user       = emptyGrid(n, n, 0),
        row_clues  = {},
        col_clues  = {},
        wrong      = emptyGrid(n, n, false),
        undo       = UndoStack:new{ max_size = 500 },
    }, self)
    obj:generate(obj.difficulty)
    return obj
end

function ColorNonogramBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n = self.n

    -- Fill density: 55-65%
    local density = (self.difficulty == "easy")   and 0.50
                 or (self.difficulty == "hard")   and 0.70
                 or 0.60

    -- Generate solution: each non-empty cell gets a random color 1..NUM_COLORS
    -- Ensure no row or column is entirely empty
    local ok = false
    local attempts = 0
    while not ok and attempts < 100 do
        attempts = attempts + 1
        for r = 1, n do
            for c = 1, n do
                if math.random() < density then
                    self.solution[r][c] = math.random(NUM_COLORS)
                else
                    self.solution[r][c] = 0
                end
            end
        end
        -- Check no empty rows/cols
        ok = true
        for r = 1, n do
            local has = false
            for c = 1, n do
                if self.solution[r][c] ~= 0 then has = true; break end
            end
            if not has then ok = false; break end
        end
        if ok then
            for c = 1, n do
                local has = false
                for r = 1, n do
                    if self.solution[r][c] ~= 0 then has = true; break end
                end
                if not has then ok = false; break end
            end
        end
    end

    self.row_clues, self.col_clues = computeClues(self.solution, n)
    self.user  = emptyGrid(n, n, 0)
    self.wrong = emptyGrid(n, n, false)
    self.undo:clear()
end

-- tapCell: cycles user value 0 → 1 → 2 → ... → NUM_COLORS → 0
function ColorNonogramBoard:tapCell(r, c)
    local old  = self.user[r][c]
    local next
    if old >= NUM_COLORS then
        next = 0
    else
        next = old + 1
    end
    self.undo:push{ r = r, c = c, old = old }
    self.user[r][c] = next
    self.wrong[r][c] = false
    return true
end

function ColorNonogramBoard:undoMove()
    local entry = self.undo:pop()
    if not entry then return false end
    self.user[entry.r][entry.c]  = entry.old
    self.wrong[entry.r][entry.c] = false
    return true
end

function ColorNonogramBoard:check()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            self.wrong[r][c] = (self.user[r][c] ~= self.solution[r][c])
        end
    end
end

function ColorNonogramBoard:isWon()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if self.user[r][c] ~= self.solution[r][c] then
                return false
            end
        end
    end
    return true
end

function ColorNonogramBoard:countFilled()
    local n, count = self.n, 0
    for r = 1, n do
        for c = 1, n do
            if self.user[r][c] ~= 0 then count = count + 1 end
        end
    end
    return count
end

function ColorNonogramBoard:countSolutionFilled()
    local n, count = self.n, 0
    for r = 1, n do
        for c = 1, n do
            if self.solution[r][c] ~= 0 then count = count + 1 end
        end
    end
    return count
end

function ColorNonogramBoard:clearUser()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            self.user[r][c]  = 0
            self.wrong[r][c] = false
        end
    end
    self.undo:clear()
end

function ColorNonogramBoard:reveal()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            self.user[r][c]  = self.solution[r][c]
            self.wrong[r][c] = false
        end
    end
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

function ColorNonogramBoard:serialize()
    local n = self.n
    local sol_flat, usr_flat = {}, {}
    for r = 1, n do
        for c = 1, n do
            sol_flat[#sol_flat + 1] = self.solution[r][c]
            usr_flat[#usr_flat + 1] = self.user[r][c]
        end
    end
    -- Serialize clues
    local rc, cc = {}, {}
    for r = 1, n do
        rc[r] = {}
        for i, entry in ipairs(self.row_clues[r]) do
            rc[r][i] = { entry.len, entry.color }
        end
    end
    for c = 1, n do
        cc[c] = {}
        for i, entry in ipairs(self.col_clues[c]) do
            cc[c][i] = { entry.len, entry.color }
        end
    end
    return {
        n          = n,
        difficulty = self.difficulty,
        solution   = sol_flat,
        user       = usr_flat,
        row_clues  = rc,
        col_clues  = cc,
    }
end

function ColorNonogramBoard:load(data)
    if type(data) ~= "table" or not data.solution then return false end
    local n = data.n or DEFAULT_N
    self.n          = n
    self.difficulty = data.difficulty or "medium"
    self.solution   = emptyGrid(n, n, 0)
    self.user       = emptyGrid(n, n, 0)
    self.wrong      = emptyGrid(n, n, false)
    if data.solution then
        local idx = 1
        for r = 1, n do
            for c = 1, n do
                self.solution[r][c] = data.solution[idx] or 0
                self.user[r][c]     = data.user and data.user[idx] or 0
                idx = idx + 1
            end
        end
    end
    if data.row_clues and data.col_clues then
        self.row_clues = {}
        self.col_clues = {}
        for r = 1, n do
            self.row_clues[r] = {}
            local rc = data.row_clues[r] or {}
            for i, entry in ipairs(rc) do
                self.row_clues[r][i] = { len = entry[1] or 0, color = entry[2] or 0 }
            end
            if #self.row_clues[r] == 0 then
                self.row_clues[r] = { { len = 0, color = 0 } }
            end
        end
        for c = 1, n do
            self.col_clues[c] = {}
            local cc = data.col_clues[c] or {}
            for i, entry in ipairs(cc) do
                self.col_clues[c][i] = { len = entry[1] or 0, color = entry[2] or 0 }
            end
            if #self.col_clues[c] == 0 then
                self.col_clues[c] = { { len = 0, color = 0 } }
            end
        end
    else
        self.row_clues, self.col_clues = computeClues(self.solution, n)
    end
    self.undo:clear()
    return true
end

ColorNonogramBoard.SIZES      = SIZES
ColorNonogramBoard.DEFAULT_N  = DEFAULT_N
ColorNonogramBoard.NUM_COLORS = NUM_COLORS

return ColorNonogramBoard
