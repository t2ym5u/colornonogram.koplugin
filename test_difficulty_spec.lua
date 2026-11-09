-- Difficulty guarantees for Color Nonogram (see docs/dev/TESTING.md,
-- "Difficulty specs"). Every level is solved by pure line logic (no trial);
-- the levels differ by the number of half-passes the line solver needs
-- (Board.STEP_BAND) and by fill density (Easy fullest, Hard emptiest).
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("ColorNonogram difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    -- 1.6.0: line logic alone finishes every puzzle (never "assume a cell,
    -- see if it breaks"), which also proves it unique; the levels differ by
    -- how long the chain of line deductions is (half-passes), in order.
    describe("difficulty", function()
        local SEEDS = 30
        local function gen(n, diff, seed)
            math.randomseed(seed * 7919 + n)
            local b = Board:new{ n = n, difficulty = diff, empty = true }
            local how = b:generate(diff)
            return b, how
        end

        it("every level is solved by line logic alone, inside its band", function()
            for _, n in ipairs(Board.SIZES) do
                local prev_avg, prev_fill = -1, 2
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    local band = Board.STEP_BAND[n][diff]
                    local sum, fill, inside = 0, 0, 0
                    for seed = 1, SEEDS do
                        local b = gen(n, diff, seed)
                        local rc, cc = Board._computeClues(b.solution, n)
                        local ok, steps = Board._lineSolve(rc, cc, n)
                        assert.is_true(ok, n .. " " .. diff .. " seed " .. seed)
                        assert.are.equal(1, (Board._countSolutions(rc, cc, n, 2, 200000)))
                        if steps >= band[1] and steps <= band[2] then inside = inside + 1 end
                        sum = sum + steps
                        local f = 0
                        for r = 1, n do for c = 1, n do
                            if b.solution[r][c] ~= 0 then f = f + 1 end
                        end end
                        fill = fill + f / (n * n)
                    end
                    assert.is_true(inside >= SEEDS - 1, n .. " " .. diff .. ": " .. inside)
                    local avg = sum / SEEDS
                    assert.is_true(avg > prev_avg + 1, n .. " " .. diff .. " steps " .. avg)
                    -- easy is the fullest grid, hard the emptiest
                    assert.is_true(fill / SEEDS < prev_fill, n .. " " .. diff)
                    prev_avg, prev_fill = avg, fill / SEEDS
                end
            end
        end)

        it("the same seed gives the same puzzle", function()
            for _, diff in ipairs({ "easy", "hard" }) do
                local a = gen(8, diff, 5):serialize()
                local b = gen(8, diff, 5):serialize()
                assert.are.same(a, b)
            end
        end)

        it("generates fast enough for a Kobo", function()
            -- ~25x slower there; the progress bar covers the rest
            local worst = 0
            for seed = 1, 10 do
                local t0 = os.clock()
                gen(8, "hard", seed)
                worst = math.max(worst, os.clock() - t0)
            end
            assert.is_true(worst < 0.25, "worst " .. worst)
        end)

        it("the step bands are ordered and disjoint, Easy starts at 1", function()
            for _, n in ipairs(Board.SIZES) do
                local B = Board.STEP_BAND[n]
                assert.are.equal(1, B.easy[1])
                assert.is_true(B.easy[2] < B.medium[1] and B.medium[1] <= B.medium[2])
                assert.is_true(B.medium[2] < B.hard[1])
            end
        end)

        -- Generation is bounded by draw counts, never by time: with a clock
        -- that jumps 1000 s at every read, a seed still gives the same
        -- puzzle.
        it("generation never reads the clock", function()
            local oc, ot = os.clock, os.time
            for _, n in ipairs(Board.SIZES) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    local a = gen(n, diff, 11):serialize()
                    local t = 0
                    os.clock = function() t = t + 1000; return t end
                    os.time = function(x) if x then return ot(x) end; t = t + 1000; return t end
                    local ok, b = pcall(function() return gen(n, diff, 11):serialize() end)
                    os.clock, os.time = oc, ot
                    assert.is_true(ok, tostring(b))
                    assert.are.same(a, b)
                end
            end
            local src = assert(io.open(DIR .. "board.lua")):read("*a")
            assert.is_nil(src:find("os%.clock"))
            assert.is_nil(src:find("os%.time"))
        end)
    end)
end)
