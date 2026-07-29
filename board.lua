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
-- Uniqueness counter: same line-candidate-enumeration + row/column
-- propagation-to-a-fixed-point technique as nonogram.koplugin, generalized
-- for per-cell values in {0=empty, 1..NUM_COLORS} instead of boolean, and
-- for a color-dependent gap rule: two consecutive clue runs need a
-- mandatory >=1 empty cell between them ONLY if they're the same color
-- (this is what computeClues above actually encodes -- two different-
-- colored runs can sit directly adjacent with zero gap, since they'd never
-- have merged into one run in the first place).
-- ---------------------------------------------------------------------------

local NUM_VALUES = NUM_COLORS + 1 -- 0 (empty) plus 1..NUM_COLORS

local function enumerateLines(clue, n)
    if #clue == 1 and clue[1].len == 0 then
        local empty = {}
        for i = 1, n do empty[i] = 0 end
        return { empty }
    end
    local m = #clue
    local minlen = 0
    for i, seg in ipairs(clue) do
        minlen = minlen + seg.len
        if i < m and clue[i].color == clue[i + 1].color then minlen = minlen + 1 end
    end
    if minlen > n then return {} end
    local slack = n - minlen

    local results = {}
    local line = {}
    for i = 1, n do line[i] = 0 end

    local function place(i, pos, gaps_left)
        if i > m then
            local copy = {}
            for j = 1, n do copy[j] = line[j] end
            results[#results + 1] = copy
            return
        end
        for extra = 0, gaps_left do
            local start = pos + extra
            local finish = start + clue[i].len - 1
            if finish > n then break end
            for j = start, finish do line[j] = clue[i].color end
            local mandatory = (i < m and clue[i].color == clue[i + 1].color) and 1 or 0
            place(i + 1, finish + 1 + mandatory, gaps_left - extra)
            for j = start, finish do line[j] = 0 end
        end
    end
    place(1, 1, slack)
    return results
end

local function achievableSetAt(lines, pos)
    local seen, count = {}, 0
    for _, line in ipairs(lines) do
        local v = line[pos]
        if not seen[v] then seen[v] = true; count = count + 1 end
        if count == NUM_VALUES then break end
    end
    return seen
end

local function filterByAchievable(lines, achievable, n)
    local out = {}
    for _, line in ipairs(lines) do
        local ok = true
        for pos = 1, n do
            if not achievable[pos][line[pos]] then ok = false; break end
        end
        if ok then out[#out + 1] = line end
    end
    return out
end

local function propagate(row_live, col_live, n)
    local changed = true
    while changed do
        changed = false
        for r = 1, n do
            local achievable = {}
            for c = 1, n do achievable[c] = achievableSetAt(col_live[c], r) end
            local filtered = filterByAchievable(row_live[r], achievable, n)
            if #filtered == 0 then return false end
            if #filtered < #row_live[r] then changed = true end
            row_live[r] = filtered
        end
        for c = 1, n do
            local achievable = {}
            for r = 1, n do achievable[r] = achievableSetAt(row_live[r], c) end
            local filtered = filterByAchievable(col_live[c], achievable, n)
            if #filtered == 0 then return false end
            if #filtered < #col_live[c] then changed = true end
            col_live[c] = filtered
        end
    end
    return true
end

local function copyLiveState(row_live, col_live, n)
    local r2, c2 = {}, {}
    for r = 1, n do r2[r] = row_live[r] end
    for c = 1, n do c2[c] = col_live[c] end
    return r2, c2
end

local function countSolutions(row_clues, col_clues, n, limit, node_budget)
    local row_live, col_live = {}, {}
    for r = 1, n do row_live[r] = enumerateLines(row_clues[r], n) end
    for c = 1, n do col_live[c] = enumerateLines(col_clues[c], n) end

    local solutions, nodes, exhausted = 0, 0, false

    local function search(row_live, col_live)
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end

        if not propagate(row_live, col_live, n) then return end

        local all_singletons = true
        for r = 1, n do
            if #row_live[r] ~= 1 then all_singletons = false; break end
        end
        if all_singletons then
            solutions = solutions + 1
            return
        end

        local best_is_row, best_idx, best_len = true, nil, math.huge
        for r = 1, n do
            if #row_live[r] >= 2 and #row_live[r] < best_len then
                best_len, best_idx, best_is_row = #row_live[r], r, true
            end
        end
        for c = 1, n do
            if #col_live[c] >= 2 and #col_live[c] < best_len then
                best_len, best_idx, best_is_row = #col_live[c], c, false
            end
        end

        local live = best_is_row and row_live[best_idx] or col_live[best_idx]
        for _, candidate in ipairs(live) do
            local r2, c2 = copyLiveState(row_live, col_live, n)
            if best_is_row then r2[best_idx] = { candidate } else c2[best_idx] = { candidate } end
            search(r2, c2)
            if solutions >= limit or exhausted then return end
        end
    end

    search(row_live, col_live)
    return solutions, exhausted
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

-- There's no "reveal a subset" mechanic here -- the row/col clues ARE the
-- entire puzzle, deduced from nothing else -- so like nonogram.koplugin
-- this generates+verifies whole candidate solutions instead of digging:
-- build a random solution, derive its clues, and keep it only if
-- countSolutions proves it's the unique grid matching those clues;
-- otherwise retry.
local function uniquenessNodeBudget(n)
    if n <= 6 then return 30000 end
    return 80000
end

function ColorNonogramBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n = self.n

    -- Fill density: 55-65%
    local density = (self.difficulty == "easy")   and 0.50
                 or (self.difficulty == "hard")   and 0.70
                 or 0.60

    local budget = uniquenessNodeBudget(n)
    local best_solution, best_row_clues, best_col_clues

    for attempt = 1, 400 do
        local candidate = emptyGrid(n, n, 0)
        for r = 1, n do
            for c = 1, n do
                if math.random() < density then
                    candidate[r][c] = math.random(NUM_COLORS)
                else
                    candidate[r][c] = 0
                end
            end
        end

        local no_empty_lines = true
        for r = 1, n do
            local has = false
            for c = 1, n do if candidate[r][c] ~= 0 then has = true; break end end
            if not has then no_empty_lines = false; break end
        end
        if no_empty_lines then
            for c = 1, n do
                local has = false
                for r = 1, n do if candidate[r][c] ~= 0 then has = true; break end end
                if not has then no_empty_lines = false; break end
            end
        end

        if no_empty_lines then
            local row_clues, col_clues = computeClues(candidate, n)
            if not best_solution then
                best_solution, best_row_clues, best_col_clues = candidate, row_clues, col_clues
            end
            local solutions, exhausted = countSolutions(row_clues, col_clues, n, 2, budget)
            if solutions == 1 and not exhausted then
                best_solution, best_row_clues, best_col_clues = candidate, row_clues, col_clues
                break
            end
        end
    end

    self.solution, self.row_clues, self.col_clues = best_solution, best_row_clues, best_col_clues
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
