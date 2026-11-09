-- Difficulty guarantees for Skyscraper: every size x level builds a unique
-- puzzle quickly, logic.lua (the game's own grader) solves it with the
-- level's rules and no guessing, Medium and Hard need more than tier 1,
-- Easy > Medium > Hard in clues, and a seed gives the same puzzle without
-- reading the clock.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Runs fn with os.clock/os.time/os.date replaced by functions that fail:
-- a generator must bound its work by counts, never by time.
local function withoutClock(fn)
    local oc, ot, od = os.clock, os.time, os.date
    local function boom(name) return function() error("generator read " .. name, 2) end end
    os.clock, os.time, os.date = boom("os.clock"), boom("os.time"), boom("os.date")
    local ok, err = pcall(fn)
    os.clock, os.time, os.date = oc, ot, od
    if not ok then error(err, 0) end
end

describe("Skyscraper difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local function newBoard(n, diff)
        math.randomseed(42)
        return Board:new{ n = n or 5, difficulty = diff or "easy" }
    end

    describe("clues and uniqueness", function()
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

        it("every size and level has exactly one solution", function()
            for _, n in ipairs({ 4, 5 }) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    for seed = 1, 6 do
                        math.randomseed(seed * 7919 + n)
                        local b = Board:new{ n = n, difficulty = diff }
                        local count, exhausted = Board._countSolutions(b.clues, n, 2, 1e7)
                        assert.is_false(exhausted)
                        assert.are.equal(1, count, ("n=%d %s seed %d"):format(n, diff, seed))
                    end
                end
            end
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

        it("generation never reads the clock", function()
            for _, n in ipairs({ 4, 5 }) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    local b = Board:new{ n = n, empty = true }
                    math.randomseed(n * 3)
                    withoutClock(function() b:generate(diff) end)
                end
            end
        end)
    end)
end)
