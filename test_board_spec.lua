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


    -- Board:new() auto-generates internally (seeded, so deterministic).
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

    describe("countSolutions", function()
        local none = function() return { top = {}, bottom = {}, left = {}, right = {} } end

        it("counts all 576 Latin squares of order 4 when no clue is shown", function()
            local count, exhausted = Board._countSolutions(none(), 4, 1000, 1e7)
            assert.is_false(exhausted)
            assert.are.equal(576, count)
        end)

        it("finds exactly one solution for every generated puzzle", function()
            for seed = 1, 20 do
                math.randomseed(seed)
                local b = Board:new{ n = 5, difficulty = "hard" }
                local count, exhausted = Board._countSolutions(b.clues, 5, 2, 1e7)
                assert.is_false(exhausted)
                assert.are.equal(1, count)
            end
        end)

        it("generates a 5×5 Hard puzzle quickly (was up to 6 s on a desktop)", function()
            local t = os.clock()
            for seed = 1, 20 do
                math.randomseed(seed)
                Board:new{ n = 5, difficulty = "hard" }
            end
            assert.is_true(os.clock() - t < 5, "20 puzzles took " .. (os.clock() - t) .. " s")
        end)
    end)
    describe("logic grading", function()
        local Logic
        setup(function()
            Logic = dofile(DIR .. "logic.lua")
        end)

        local SEEDS = 30
        local TIER = { easy = 1, medium = 2, hard = 3 }

        local function gen(n, diff, seed)
            math.randomseed(seed)
            local b = Board:new{ n = n, empty = true }
            b:generate(diff)
            return b
        end

        local function clueCount(b)
            local k = 0
            for _, side in pairs(b.clues) do
                for _ in pairs(side) do k = k + 1 end
            end
            return k
        end

        it("every level is solved by logic alone, with the level's rules", function()
            for _, n in ipairs({ 4, 5 }) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    for seed = 1, SEEDS do
                        local b = gen(n, diff, seed)
                        local where = ("n=%d %s seed %d"):format(n, diff, seed)
                        local ok, vals = Logic.solve(b.clues, n, TIER[diff])
                        assert.is_true(ok, where)
                        assert.are.same(b.solution, vals, where)
                        -- Medium and Hard really need more than tier 1.
                        if diff ~= "easy" then
                            assert.is_false((Logic.solve(b.clues, n, 1)), where)
                        end
                    end
                end
            end
        end)

        it("Easy > Medium > Hard in clues, Hard showing a subset of Medium's", function()
            for _, n in ipairs({ 4, 5 }) do
                local sums = { easy = 0, medium = 0, hard = 0 }
                for seed = 1, SEEDS do
                    local e, m, h = gen(n, "easy", seed), gen(n, "medium", seed), gen(n, "hard", seed)
                    local ce, cm, ch = clueCount(e), clueCount(m), clueCount(h)
                    sums.easy, sums.medium, sums.hard = sums.easy + ce, sums.medium + cm, sums.hard + ch
                    assert.is_true(ch < cm, ("n=%d seed %d: Hard %d clues, Medium %d"):format(n, seed, ch, cm))
                    assert.is_true(ch >= 3)
                    assert.are.same(m.solution, h.solution)
                    for side, t in pairs(h.clues) do
                        for i, v in pairs(t) do
                            assert.are.equal(v, m.clues[side][i])
                        end
                    end
                end
                assert.is_true(sums.easy > sums.medium and sums.medium > sums.hard,
                    ("n=%d clue totals %d / %d / %d"):format(n, sums.easy, sums.medium, sums.hard))
            end
        end)

        it("the same seed gives the same puzzle", function()
            for _, n in ipairs({ 4, 5 }) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    for seed = 1, 5 do
                        local a, b = gen(n, diff, seed), gen(n, diff, seed)
                        assert.are.same(a.solution, b.solution)
                        assert.are.same(a.clues, b.clues)
                    end
                end
            end
        end)

        it("generates quickly at every size and level", function()
            for _, n in ipairs({ 4, 5 }) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    local worst = 0
                    for seed = 1, SEEDS do
                        math.randomseed(seed)
                        local b = Board:new{ n = n, empty = true }
                        local t0 = os.clock()
                        b:generate(diff)
                        worst = math.max(worst, os.clock() - t0)
                    end
                    -- generous: ~0.03 s worst on a desktop
                    assert.is_true(worst < 0.5, ("n=%d %s took %.3f s"):format(n, diff, worst))
                end
            end
        end)

        it("only fills a grid when its solution is unique, and fills it right", function()
            local solved = 0
            for seed = 1, 400 do
                local n = 4 + seed % 2
                math.randomseed(seed * 7 + 3)
                local b = Board:new{ n = n, difficulty = "easy" }
                local all = Board._computeAllClues(b.solution, n)
                local ratio = math.random() * 0.6 + 0.4
                local clues = { top = {}, bottom = {}, left = {}, right = {} }
                for side, t in pairs(all) do
                    for i, v in pairs(t) do
                        if math.random() < ratio then clues[side][i] = v end
                    end
                end
                local ok, vals = Logic.solve(clues, n, 3)
                if ok then
                    solved = solved + 1
                    local count, exhausted = Board._countSolutions(clues, n, 2, 1e7)
                    assert.is_false(exhausted)
                    assert.are.equal(1, count, ("n=%d seed %d"):format(n, seed))
                    assert.are.same(b.solution, vals)
                end
            end
            assert.is_true(solved > 50)
        end)

        it("the fallback squares are solved by tier 1 in every orientation", function()
            for _, n in ipairs({ 4, 5 }) do
                for seed = 1, 40 do
                    math.randomseed(seed)
                    local sol = Board._fallbackSquare(n)
                    local ok, vals = Logic.solve(Board._computeAllClues(sol, n), n, 1)
                    assert.is_true(ok)
                    assert.are.same(sol, vals)
                end
            end
        end)

        it("accepts any grid that keeps the rules (saves from before 1.6.0)", function()
            -- A 4x4 with no clue at all: any Latin square is a win.
            local b = Board:new{ n = 4, empty = true }
            assert.is_true(b:load({
                n = 4, difficulty = "hard",
                solution = { { 1, 2, 3, 4 }, { 2, 3, 4, 1 }, { 3, 4, 1, 2 }, { 4, 1, 2, 3 } },
                grid = { { 2, 1, 4, 3 }, { 1, 2, 3, 4 }, { 4, 3, 2, 1 }, { 3, 4, 1, 2 } },
                clues = { top = {}, bottom = {}, left = {}, right = {} },
            }))
            assert.is_true(b:isSolved())
            -- A clue it breaks: left of row 1 sees 2 and 4, not 3.
            b.clues.left[1] = 3
            assert.is_false(b:isSolved())
            b.clues.left[1] = 2
            assert.is_true(b:isSolved())
            -- A repeated height is never a win.
            b.grid[1][1] = 1
            assert.is_false(b:isSolved())
        end)

        it("loads a save from before 1.6.0", function()
            local data = {
                n = 4, difficulty = "medium",
                solution = { { 1, 2, 3, 4 }, { 2, 3, 4, 1 }, { 3, 4, 1, 2 }, { 4, 1, 2, 3 } },
                grid = { { 1, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } },
                clues = { top = { 4, nil, 2 }, bottom = {}, left = { [2] = 3 }, right = { 1 } },
                wrong_marks = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } },
            }
            local b = Board:new{ n = 4, empty = true }
            assert.is_true(b:load(data))
            assert.are.equal("medium", b.difficulty)
            assert.are.equal(4, b.clues.top[1])
            assert.are.equal(3, b.clues.left[2])
            assert.are.equal(1, b:getDisplayValue(1, 1))
            assert.are.equal(15, b:getRemainingCells())
            assert.is_false(b:isSolved())
        end)
    end)
end)
