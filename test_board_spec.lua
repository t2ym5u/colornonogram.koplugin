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

    describe("tapCell / undoMove", function()
        it("cycles a cell 0 -> 1 -> 2 -> 3 -> 0", function()
            local b = newBoard()
            b.user[1][1] = 0
            b:tapCell(1, 1)
            assert.are.equal(1, b.user[1][1])
            b:tapCell(1, 1)
            assert.are.equal(2, b.user[1][1])
            b:tapCell(1, 1)
            assert.are.equal(3, b.user[1][1])
            b:tapCell(1, 1)
            assert.are.equal(0, b.user[1][1])
        end)

        it("undoMove restores the previous value", function()
            local b = newBoard()
            b.user[1][1] = 0
            b:tapCell(1, 1)
            assert.is_true(b:undoMove())
            assert.are.equal(0, b.user[1][1])
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
    end)

    describe("serialize / load", function()
        it("round-trips solution, user grid and clues", function()
            local b = newBoard()
            b:reveal()
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

        it("load returns false for invalid data", function()
            local b = newBoard()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
