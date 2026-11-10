local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("ColorNonogramBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local function newBoard(diff)
        math.randomseed(42)
        return Board:new({ n = 6, difficulty = diff or "easy" })
    end

    describe("new / generate", function()
        it("creates a 6x6 board with matching row/col clue counts", function()
            local b = newBoard()
            assert.are.equal(6, b.n)
            assert.are.equal(6, #b.row_clues)
            assert.are.equal(6, #b.col_clues)
        end)

        it("no row or column is entirely empty", function()
            local b = newBoard()
            for r = 1, b.n do
                local has = false
                for c = 1, b.n do if b.solution[r][c] ~= 0 then has = true end end
                assert.is_true(has, "row " .. r .. " is empty")
            end
            for c = 1, b.n do
                local has = false
                for r = 1, b.n do if b.solution[r][c] ~= 0 then has = true end end
                assert.is_true(has, "col " .. c .. " is empty")
            end
        end)
    end)

    describe("generate progress", function()
        it("reports progress between 0 and 1", function()
            math.randomseed(3)
            local b = Board:new{ n = 8, difficulty = "hard", empty = true }
            local calls = 0
            b:generate("hard", function(f)
                calls = calls + 1
                assert.is_true(f > 0 and f < 1)
            end)
            assert.is_true(calls > 0)
        end)
    end)

    describe("paintCell / undoMove", function()
        it("applies the active marking, or clears a cell that already has it", function()
            local M = Board.MARKED
            for _, case in ipairs({
                { from = 0, value = 2, to = 2 },
                { from = 2, value = 2, to = 0 },
                { from = 1, value = 3, to = 3 },
                { from = 0, value = M, to = M },
                { from = M, value = M, to = 0 },
                { from = 2, value = M, to = M },
                { from = M, value = 1, to = 1 },
            }) do
                local b = newBoard()
                b.user[1][1] = case.from
                b:paintCell(1, 1, case.value)
                assert.are.equal(case.to, b.user[1][1],
                    "from " .. case.from .. " with " .. case.value)
            end
        end)

        it("undoMove restores the previous value", function()
            for _, value in ipairs({ 1, Board.MARKED }) do
                local b = newBoard()
                b.user[1][1] = 2
                b:paintCell(1, 1, value)
                assert.is_true(b:undoMove())
                assert.are.equal(2, b.user[1][1], "after painting " .. value)
            end
        end)

        it("returns false when there is nothing to undo", function()
            local b = newBoard()
            assert.is_false(b:undoMove())
        end)
    end)

    describe("check / isWon", function()
        it("isWon is false on a fresh board and true once matching the solution", function()
            local b = newBoard()
            assert.is_false(b:isWon())
            b:reveal()
            assert.is_true(b:isWon())
        end)

        it("isWon accepts any grid that keeps the clues", function()
            -- two answers: each row and column is "1 of colour 1", so any
            -- permutation matrix keeps the clues
            local b = Board:new{ n = 6, empty = true }
            local sol = {}
            for r = 1, 6 do sol[r] = {} for c = 1, 6 do sol[r][c] = (r == c) and 1 or 0 end end
            b.solution = sol
            b.row_clues, b.col_clues = Board._computeClues(sol, 6)
            for r = 1, 6 do for c = 1, 6 do b.user[r][c] = (c == 7 - r) and 1 or 0 end end
            assert.is_true(b:isWon())
            b.user[1][6] = 2
            assert.is_false(b:isWon())
        end)
        
        it("isWon treats empty marks as empty cells", function()
            local b = newBoard()
            b:reveal()
            local filled_r, filled_c
            for r = 1, b.n do
                for c = 1, b.n do
                    if b.solution[r][c] == 0 then b.user[r][c] = Board.MARKED end
                    if b.solution[r][c] > 0 then filled_r, filled_c = r, c end
                end
            end
            assert.is_true(b:isWon())
            b.user[filled_r][filled_c] = Board.MARKED
            assert.is_false(b:isWon())
        end)

        it("isWon ignores marked cells when matching deterministic clues", function()
            local b = Board:new{ n = 6, empty = true }
            local solution = {}
            for r = 1, 6 do
                solution[r] = {}
                for c = 1, 6 do solution[r][c] = (r == c) and 1 or 0 end
            end
            b.solution = solution
            b.row_clues, b.col_clues = Board._computeClues(solution, 6)
            b:reveal()
            for r = 1, 6 do
                for c = 1, 6 do
                    if solution[r][c] == 0 then b.user[r][c] = Board.MARKED end
                end
            end
            assert.is_true(b:isWon())
            b.user[1][1] = Board.MARKED
            assert.is_false(b:isWon())
        end)

        it("check flags an empty mark only where the solution has a colour", function()
            local b = newBoard()
            b:reveal()
            local empty_r, empty_c, filled_r, filled_c
            for r = 1, b.n do
                for c = 1, b.n do
                    if b.solution[r][c] == 0 then empty_r, empty_c = r, c
                    else filled_r, filled_c = r, c end
                end
            end
            b.user[empty_r][empty_c]   = Board.MARKED
            b.user[filled_r][filled_c] = Board.MARKED
            b:check()
            assert.is_false(b.wrong[empty_r][empty_c])
            assert.is_true(b.wrong[filled_r][filled_c])
        end)

        it("check ignores unmarked cells", function()
            local b = newBoard()
            local filled_r, filled_c
            for r = 1, b.n do
                for c = 1, b.n do
                    if b.solution[r][c] > 0 then filled_r, filled_c = r, c end
                end
            end
            b:check()
            assert.are.equal(0, b.user[filled_r][filled_c])
            assert.is_false(b.wrong[filled_r][filled_c])
        end)

        it("check flags a cell that differs from the solution", function()
            local b = newBoard()
            b.user[1][1] = (b.solution[1][1] % 3) + 1
            b:check()
            local wrong = (b.user[1][1] ~= b.solution[1][1])
            assert.are.equal(wrong, b.wrong[1][1])
        end)
    end)

    describe("clearUser", function()
        it("resets every user cell to 0", function()
            local b = newBoard()
            b:reveal()
            b:clearUser()
            assert.are.equal(0, b:countFilled())
        end)

        it("countFilled does not count empty marks", function()
            local b = newBoard()
            b:clearUser()
            b.user[1][1] = Board.MARKED
            b.user[1][2] = 3
            assert.are.equal(1, b:countFilled())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips solution, user grid and clues", function()
            local b = newBoard()
            b:reveal()
            b.user[1][1] = Board.MARKED
            local data = b:serialize()

            local b2 = Board:new({ n = 6 })
            assert.is_true(b2:load(data))
            assert.are.equal(b.n, b2.n)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.solution[r][c], b2.solution[r][c])
                    assert.are.equal(b.user[r][c], b2.user[r][c])
                end
            end
        end)

        it("loads a save from 1.5.x", function()
            -- same format: flat solution/user, clues as { len, color }
            local data = { n = 6, difficulty = "easy", solution = {}, user = {} }
            for i = 1, 36 do data.solution[i] = (i % 7 == 1) and 2 or 0; data.user[i] = 0 end
            local b = Board:new{ n = 6, empty = true }
            assert.is_true(b:load(data))   -- no clues stored: derived again
            assert.are.equal(1, #b.row_clues[1])
            assert.are.equal(2, b.row_clues[1][1].color)
            b:reveal()
            assert.is_true(b:isWon())
        end)

        it("load returns false for invalid data", function()
            local b = newBoard()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)

    describe("new{ empty = true }", function()
        it("builds no puzzle, and load fills it from a save", function()
            local saved = Board:new{ n = 6, difficulty = "hard" }:serialize()
            local b = Board:new{ n = 6, difficulty = "hard", empty = true }
            assert.is_nil(next(b.row_clues))
            assert.is_true(b:load(saved))
            assert.are.same(saved, b:serialize())
        end)
    end)
end)
