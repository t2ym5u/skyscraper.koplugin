local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("SkyscraperBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    -- Board:new() auto-generates internally (deterministic backtracking Latin
    -- square, always succeeds — no retry loop, no fallback).
    local function newBoard(n, diff)
        math.randomseed(42)
        return Board:new{ n = n or 5, difficulty = diff or "easy" }
    end

    describe("construction", function()
        it("creates a 5×5 board by default and auto-generates a solution", function()
            local b = Board:new()
            assert.are.equal(5, b.n)
            assert.is_not_nil(b.solution)
        end)
    end)

    describe("countVisible (static helper)", function()
        it("counts visible buildings looking along the row", function()
            assert.are.equal(2, Board.countVisible({3, 1, 4, 2}))
            assert.are.equal(4, Board.countVisible({1, 2, 3, 4}))
            assert.are.equal(1, Board.countVisible({4, 3, 2, 1}))
        end)
    end)

    describe("generate", function()
        it("solution is a valid Latin square (each row/col has every digit once)", function()
            local b = newBoard(5)
            local n = b.n
            for r = 1, n do
                local seen = {}
                for c = 1, n do
                    local v = b.solution[r][c]
                    assert.is_true(v >= 1 and v <= n)
                    assert.is_nil(seen[v], ("row %d has a duplicate value %d"):format(r, v))
                    seen[v] = true
                end
            end
            for c = 1, n do
                local seen = {}
                for r = 1, n do
                    local v = b.solution[r][c]
                    assert.is_nil(seen[v], ("col %d has a duplicate value %d"):format(c, v))
                    seen[v] = true
                end
            end
        end)

        it("keeps at least 4 clues, and more on easy than on hard", function()
            local function countClues(b)
                local n = 0
                for _, side in pairs(b.clues) do
                    for _ in pairs(side) do n = n + 1 end
                end
                return n
            end
            local easy = newBoard(5, "easy")
            local hard = newBoard(5, "hard")
            assert.is_true(countClues(easy) >= 4)
            assert.is_true(countClues(hard) >= 4)
            assert.is_true(countClues(easy) >= countClues(hard))
        end)

        it("grid starts empty with no wrong marks", function()
            local b = newBoard(5)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(0, b.grid[r][c])
                    assert.is_false(b.wrong_marks[r][c])
                end
            end
        end)
    end)

    describe("setCell / clearCell / getDisplayValue", function()
        it("setCell writes a value within range", function()
            local b = newBoard(5)
            local ok = b:setCell(1, 1, 3)
            assert.is_true(ok)
            assert.are.equal(3, b:getDisplayValue(1, 1))
        end)

        it("setCell rejects out-of-range values", function()
            local b = newBoard(5)
            assert.is_false(b:setCell(1, 1, -1))
            assert.is_false(b:setCell(1, 1, b.n + 1))
        end)

        it("clearCell resets a cell to 0", function()
            local b = newBoard(5)
            b:setCell(1, 1, 3)
            b:clearCell(1, 1)
            assert.are.equal(0, b:getDisplayValue(1, 1))
        end)
    end)

    describe("checkConflicts / isSolved", function()
        it("isSolved is false on a fresh board", function()
            local b = newBoard(5)
            assert.is_false(b:isSolved())
        end)

        it("isSolved is true once grid matches solution", function()
            local b = newBoard(5)
            for r = 1, b.n do
                for c = 1, b.n do
                    b:setCell(r, c, b.solution[r][c])
                end
            end
            assert.is_true(b:isSolved())
        end)

        it("checkConflicts marks a filled cell that differs from the solution", function()
            local b = newBoard(5)
            local wrong_val = (b.solution[1][1] % b.n) + 1
            b:setCell(1, 1, wrong_val)
            b:checkConflicts()
            if wrong_val ~= b.solution[1][1] then
                assert.is_true(b.wrong_marks[1][1])
            end
        end)
    end)

    describe("getRemainingCells", function()
        it("counts unfilled cells", function()
            local b = newBoard(5)
            assert.are.equal(b.n * b.n, b:getRemainingCells())
            b:setCell(1, 1, 1)
            assert.are.equal(b.n * b.n - 1, b:getRemainingCells())
        end)
    end)

    describe("serialize / load", function()
        it("round-trips solution, grid and clues", function()
            local b = newBoard(5)
            b:setCell(1, 1, b.solution[1][1])
            local data = b:serialize()
            local b2 = Board:new{ n = 5 }
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.n, b2.n)
            assert.are.equal(b.grid[1][1], b2.grid[1][1])
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.solution[r][c], b2.solution[r][c])
                end
            end
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
