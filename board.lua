local grid_utils = require("grid_utils")
local UndoStack  = require("undo_stack")
local Hint      = require("hint")

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

-- Line logic to a fixpoint: every row keeps only the placements that fit
-- the values its cells can still take (from the columns), then every
-- column does the same with the rows; repeat until nothing changes. This
-- is how a player solves it without guessing: each line on its own, from
-- its clue and the cells already known, settles the cells all its
-- placements agree on.
-- Returns ok (false on a contradiction) and the number of half-passes that
-- learned something (all rows, or all columns, = one half-pass): how long
-- the chain of deductions is.
local function propagate(row_live, col_live, n)
    local changed, steps = true, 0
    while changed do
        changed = false
        local any = false
        for r = 1, n do
            local achievable = {}
            for c = 1, n do achievable[c] = achievableSetAt(col_live[c], r) end
            local filtered = filterByAchievable(row_live[r], achievable, n)
            if #filtered == 0 then return false, steps end
            if #filtered < #row_live[r] then any = true end
            row_live[r] = filtered
        end
        if any then steps = steps + 1; changed = true end
        any = false
        for c = 1, n do
            local achievable = {}
            for r = 1, n do achievable[r] = achievableSetAt(row_live[r], c) end
            local filtered = filterByAchievable(col_live[c], achievable, n)
            if #filtered == 0 then return false, steps end
            if #filtered < #col_live[c] then any = true end
            col_live[c] = filtered
        end
        if any then steps = steps + 1; changed = true end
    end
    return true, steps
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
    -- opts.empty: the caller loads a save or generates itself, so don't
    -- build a puzzle that would be thrown away.
    if not opts.empty then obj:generate(obj.difficulty) end
    return obj
end

-- There's no "reveal a subset" mechanic here -- the row/col clues ARE the
-- entire puzzle, deduced from nothing else -- so like nonogram.koplugin
-- this generates+verifies whole candidate solutions instead of digging:
-- build a random solution, derive its clues, keep it only if it passes the
-- check below; otherwise retry.
--
-- 1.6.0: no guessing. A grid is kept only if lineSolve() finishes it --
-- pure line-by-line logic, never "assume this cell, see if it breaks" --
-- which also proves the solution unique. (Up to 1.5.x a branching search
-- proved uniqueness, and accepted grids only trial and error could solve;
-- when 400 draws found none it even kept a grid with several solutions.)
-- Difficulty is how long the chain of deductions is: the half-passes
-- lineSolve() needs (rows, then columns, ...), which must fall in the
-- level's band below, on a grid drawn at the level's fill density. Fuller
-- grids give long runs that settle many cells at once, so Easy is the
-- fullest and Hard the emptiest (it used to be the other way round).
local DENSITY = {
    [6] = { easy = 0.75, medium = 0.60, hard = 0.50 },
    [8] = { easy = 0.75, medium = 0.60, hard = 0.55 },
}
-- [n][difficulty] = { fewest half-passes, most half-passes }
local STEP_BAND = {
    [6] = { easy = { 1, 3 }, medium = { 4, 5 }, hard = { 6, math.huge } },
    [8] = { easy = { 1, 3 }, medium = { 4, 5 }, hard = { 6, math.huge } },
}
local MAX_ATTEMPTS      = 400   -- draws; see the fallbacks below
local FALLBACK_DENSITY  = 0.85  -- nearly every such grid solves line by line
local FALLBACK_ATTEMPTS = 100

local function lineSolve(row_clues, col_clues, n)
    local row_live, col_live = {}, {}
    for r = 1, n do row_live[r] = enumerateLines(row_clues[r], n) end
    for c = 1, n do col_live[c] = enumerateLines(col_clues[c], n) end
    local ok, steps = propagate(row_live, col_live, n)
    if not ok then return false, steps end
    for r = 1, n do
        if #row_live[r] ~= 1 then return false, steps end
    end
    return true, steps
end

local function randomGrid(n, density)
    local g = emptyGrid(n, n, 0)
    for r = 1, n do
        for c = 1, n do
            if math.random() < density then g[r][c] = math.random(NUM_COLORS) end
        end
    end
    return g
end

local function hasEmptyLine(row_clues, col_clues, n)
    for i = 1, n do
        if row_clues[i][1].len == 0 or col_clues[i][1].len == 0 then return true end
    end
    return false
end

-- How far `steps` falls outside `band` (0 = inside).
local function bandDistance(steps, band)
    if steps < band[1] then return band[1] - steps end
    if steps > band[2] then return steps - band[2] end
    return 0
end

-- on_progress (optional): called with a 0..1 fraction as it goes.
-- Returns how the grid was found, for the specs: "band" (the usual case),
-- "near" (line-solvable but outside the level's band), "dense" (the denser
-- fallback) or "full" (every cell filled: each clue is its whole line).
-- Draws are counted, never timed, so a seed always gives the same grid.
function ColorNonogramBoard:generate(difficulty, on_progress)
    self.difficulty = difficulty or self.difficulty
    local n = self.n
    local diff = DENSITY[n] and DENSITY[n][self.difficulty] and self.difficulty or "medium"
    local density = (DENSITY[n] or DENSITY[8])[diff]
    local band = (STEP_BAND[n] or STEP_BAND[8])[diff]

    local best, best_rc, best_cc, best_dist, how
    for attempt = 1, MAX_ATTEMPTS do
        -- Hard takes ~20 draws, the others a handful
        if on_progress then on_progress(attempt / (attempt + 20)) end
        local candidate = randomGrid(n, density)
        local row_clues, col_clues = computeClues(candidate, n)
        if not hasEmptyLine(row_clues, col_clues, n) then
            local solved, steps = lineSolve(row_clues, col_clues, n)
            if solved then
                local dist = bandDistance(steps, band)
                if not best or dist < best_dist then
                    best, best_rc, best_cc, best_dist = candidate, row_clues, col_clues, dist
                    if dist == 0 then break end
                end
            end
        end
    end
    how = best and (best_dist == 0 and "band" or "near")

    -- Nothing line-solvable at all (not seen in thousands of seeds): a
    -- fuller grid, then the full grid.
    if not best then
        for _ = 1, FALLBACK_ATTEMPTS do
            local candidate = randomGrid(n, FALLBACK_DENSITY)
            local row_clues, col_clues = computeClues(candidate, n)
            if not hasEmptyLine(row_clues, col_clues, n)
               and lineSolve(row_clues, col_clues, n) then
                best, best_rc, best_cc, how = candidate, row_clues, col_clues, "dense"
                break
            end
        end
    end
    if not best then
        best = randomGrid(n, 2)
        best_rc, best_cc = computeClues(best, n)
        how = "full"
    end

    self.solution, self.row_clues, self.col_clues = best, best_rc, best_cc
    self.user  = emptyGrid(n, n, 0)
    self.wrong = emptyGrid(n, n, false)
    self.undo:clear()
    return how
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

-- Like tapCell(), but goes straight to a colour instead of cycling. Used by
-- the Hint button, and undoable through the same stack as a hand-made move.
function ColorNonogramBoard:setCellColor(r, c, v)
    local old = self.user[r][c]
    if old == v then return true end
    self.undo:push{ r = r, c = c, old = old }
    self.user[r][c]  = v
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

-- Won when the grid keeps every clue (1.6.0: not only when it equals the
-- stored solution -- a save from before 1.6.0 may hold a puzzle with more
-- than one answer, and any of them wins).
local function sameClue(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i].len ~= b[i].len or (a[i].len > 0 and a[i].color ~= b[i].color) then
            return false
        end
    end
    return true
end

function ColorNonogramBoard:isWon()
    local n = self.n
    local rc, cc = computeClues(self.user, n)
    for i = 1, n do
        if not sameClue(rc[i], self.row_clues[i]) or not sameClue(cc[i], self.col_clues[i]) then
            return false
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

Hint.install(ColorNonogramBoard, {
    getUser     = function(b, r, c) return b.user[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] end,
    isEmpty     = function(v) return v == 0 end,
    setCell     = function(b, r, c, v) return b:setCellColor(r, c, v) end,
    blank       = 0,
})

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
-- Generator internals, for the specs and measurement scripts.
ColorNonogramBoard._computeClues  = computeClues
ColorNonogramBoard._enumerateLines = enumerateLines
ColorNonogramBoard._propagate     = propagate
ColorNonogramBoard._countSolutions = countSolutions
ColorNonogramBoard._lineSolve     = lineSolve
ColorNonogramBoard.STEP_BAND      = STEP_BAND
ColorNonogramBoard.DEFAULT_N  = DEFAULT_N
ColorNonogramBoard.NUM_COLORS = NUM_COLORS

return ColorNonogramBoard
