local grid_utils = require("grid_utils")
local Hint      = require("hint")

local emptyGrid     = grid_utils.emptyGrid
local emptyBoolGrid = grid_utils.emptyBoolGrid
local copyGrid      = grid_utils.copyGrid
local shuffle       = grid_utils.shuffle

local DEFAULT_N          = 5
local DEFAULT_DIFFICULTY = "easy"

-- logic.lua sits next to this file; load it by path (plugin-own modules
-- share names across plugins, see docs/dev/PITFALLS.md).
local _dir  = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Logic = assert(loadfile(_dir .. "logic.lua"))()

-- Difficulty ids; generate() says how each one is graded by logic.lua.
local LOGIC_LEVELS = { easy = 1, medium = 2, hard = 3 }
-- Easy keeps at least this share of the 4n clues; Medium aims halfway
-- between that and Hard.
local EASY_CLUE_RATIO = 0.60
-- Latin squares tried for one whose full clue set the level's rules solve.
local SQUARE_ATTEMPTS = { 150, 60, 60 }
-- Medium/Hard: digs tried for one that really needs the level's rules.
local DIG_ATTEMPTS = 12

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Count how many buildings are visible looking left-to-right through a row
local function countVisible(row)
    local count  = 0
    local tallest = 0
    for _, h in ipairs(row) do
        if h > tallest then
            count   = count + 1
            tallest = h
        end
    end
    return count
end

-- Generate a random valid Latin square of size n x n via backtracking
local function generateLatinSquare(n)
    local grid = emptyGrid(n)

    local function valid(r, c, v)
        for k = 1, c - 1 do
            if grid[r][k] == v then return false end
        end
        for k = 1, r - 1 do
            if grid[k][c] == v then return false end
        end
        return true
    end

    local function fill(pos)
        if pos > n * n then return true end
        local r = math.ceil(pos / n)
        local c = ((pos - 1) % n) + 1
        local digits = {}
        for i = 1, n do digits[i] = i end
        shuffle(digits)
        for _, v in ipairs(digits) do
            if valid(r, c, v) then
                grid[r][c] = v
                if fill(pos + 1) then return true end
                grid[r][c] = 0
            end
        end
        return false
    end

    fill(1)
    return grid
end

-- ---------------------------------------------------------------------------
-- Uniqueness check
-- ---------------------------------------------------------------------------

-- Every ordering of 1..n with its visibility from each end, built once per n
-- (120 for n = 5). A solution is one ordering per row, so the search below
-- places a whole row at a time.
local perm_cache = {}

local function rowPermutations(n)
    if perm_cache[n] then return perm_cache[n] end
    local perms, cur, used = {}, {}, {}
    local function build(k)
        if k > n then
            local p, rev = {}, {}
            for i = 1, n do p[i] = cur[i]; rev[i] = cur[n - i + 1] end
            p.left, p.right = countVisible(p), countVisible(rev)
            perms[#perms + 1] = p
            return
        end
        for v = 1, n do
            if not used[v] then
                used[v], cur[k] = true, v
                build(k + 1)
                used[v] = false
            end
        end
    end
    build(1)
    perm_cache[n] = perms
    return perms
end

-- Counts Latin-square completions (up to `limit`) consistent with the
-- visible clues. Rows are placed whole, from the orderings that match the
-- row's left/right clues; a row is rejected as soon as it repeats a digit in
-- a column or makes a top clue unreachable (seen from the top, a column can
-- only still gain one building per remaining row, and only with a taller
-- one). Bottom clues are checked on the last row. Returns
-- (solutions_found, exhausted); exhausted=true means node_budget was hit
-- before the search concluded, so the count isn't proof.
--
-- The previous cell-by-cell search only checked clues once a row or column
-- was complete: 5×5 Hard took up to 6 s on a desktop, minutes on a Kobo.
local NODE_BUDGET_UNIQUENESS = 500000

local function countSolutions(clues, n, limit, node_budget)
    local perms = rowPermutations(n)
    local rows = {}
    for r = 1, n do
        local list = {}
        for _, p in ipairs(perms) do
            if (not clues.left[r] or p.left == clues.left[r])
               and (not clues.right[r] or p.right == clues.right[r]) then
                list[#list + 1] = p
            end
        end
        rows[r] = list
    end

    local used = {}               -- used[c][v]: digit v already in column c
    local top_max, top_vis = {}, {}
    for c = 1, n do used[c], top_max[c], top_vis[c] = {}, 0, 0 end
    local placed = {}
    local solutions, nodes, exhausted = 0, 0, false

    local function bottomOk()
        for c = 1, n do
            local want = clues.bottom[c]
            if want then
                local tallest, seen = 0, 0
                for r = n, 1, -1 do
                    local h = placed[r][c]
                    if h > tallest then tallest, seen = h, seen + 1 end
                end
                if seen ~= want then return false end
            end
        end
        return true
    end

    local function search(r)
        if r > n then
            if bottomOk() then solutions = solutions + 1 end
            return
        end
        local left_after = n - r
        for _, p in ipairs(rows[r]) do
            nodes = nodes + 1
            if nodes > node_budget then exhausted = true; return end
            local ok = true
            for c = 1, n do
                local v = p[c]
                if used[c][v] then ok = false; break end
                local want = clues.top[c]
                if want then
                    local mx, vis = top_max[c], top_vis[c]
                    if v > mx then mx, vis = v, vis + 1 end
                    -- too many seen already, or not enough rows/taller
                    -- digits left to reach the clue
                    if vis > want or vis + math.min(left_after, n - mx) < want then
                        ok = false; break
                    end
                end
            end
            if ok then
                local saved_max, saved_vis = {}, {}
                for c = 1, n do
                    local v = p[c]
                    used[c][v] = true
                    saved_max[c], saved_vis[c] = top_max[c], top_vis[c]
                    if v > top_max[c] then top_max[c], top_vis[c] = v, top_vis[c] + 1 end
                end
                placed[r] = p
                search(r + 1)
                for c = 1, n do
                    used[c][p[c]] = false
                    top_max[c], top_vis[c] = saved_max[c], saved_vis[c]
                end
            end
            if solutions >= limit or exhausted then return end
        end
    end
    search(1)
    return solutions, exhausted
end

-- ---------------------------------------------------------------------------
-- SkyscraperBoard
-- ---------------------------------------------------------------------------

local SkyscraperBoard = {}
SkyscraperBoard.__index = SkyscraperBoard
SkyscraperBoard._countSolutions = countSolutions   -- exposed for the specs

function SkyscraperBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n           = opts.n or DEFAULT_N,
        difficulty  = opts.difficulty or DEFAULT_DIFFICULTY,
        solution    = nil,
        grid        = nil,
        given       = nil,
        clues       = nil,
        wrong_marks = nil,
        sel_r       = nil,
        sel_c       = nil,
    }, self)
    -- opts.empty: the caller loads a save or generates itself, so don't
    -- build a puzzle that would be thrown away.
    if not opts.empty then obj:generate(obj.difficulty) end
    return obj
end

-- ---------------------------------------------------------------------------
-- Generate
-- ---------------------------------------------------------------------------

local function computeAllClues(sol, n)
    local top, bottom, left, right = {}, {}, {}, {}
    for c = 1, n do
        local col_fwd, col_rev = {}, {}
        for r = 1, n do
            col_fwd[r] = sol[r][c]
            col_rev[r] = sol[n - r + 1][c]
        end
        top[c]    = countVisible(col_fwd)
        bottom[c] = countVisible(col_rev)
    end
    for r = 1, n do
        local row_fwd, row_rev = {}, {}
        for c = 1, n do
            row_fwd[c] = sol[r][c]
            row_rev[c] = sol[r][n - c + 1]
        end
        left[r]  = countVisible(row_fwd)
        right[r] = countVisible(row_rev)
    end
    return { top = top, bottom = bottom, left = left, right = right }
end

-- Squares whose full clue set logic.lua solves with tier 1 alone (so with
-- every tier), checked by the specs. Used, turned or mirrored at random,
-- only if SQUARE_ATTEMPTS random squares all fail: that keeps the work
-- bounded by a count, never by the clock, and still never ships a puzzle
-- that needs a guess.
local FALLBACK_SQUARES = {
    [4] = {
        { 2, 3, 4, 1 },
        { 3, 4, 1, 2 },
        { 4, 1, 2, 3 },
        { 1, 2, 3, 4 },
    },
    [5] = {
        { 4, 5, 2, 1, 3 },
        { 1, 4, 3, 2, 5 },
        { 2, 1, 5, 3, 4 },
        { 5, 3, 1, 4, 2 },
        { 3, 2, 4, 5, 1 },
    },
}

local function fallbackSquare(n)
    local base = FALLBACK_SQUARES[n]
    local turn, mirror = math.random(4) - 1, math.random(2) == 2
    local sol = emptyGrid(n)
    for r = 1, n do
        for c = 1, n do
            local rr, cc = r, c
            for _ = 1, turn do rr, cc = cc, n - rr + 1 end
            if mirror then cc = n - cc + 1 end
            sol[rr][cc] = base[r][c]
        end
    end
    return sol
end

-- The clue slots in a random order, and the full clue set of a square
-- whose full clues logic.lua solves with rules up to `tier`. Even the full
-- 4n clues of a random square often leave several solutions, or one that
-- only trial and error finds; hiding clues can only make that worse, so
-- such a square is replaced, never dug.
local function newDig(n, tier)
    local sol, clues
    for _ = 1, SQUARE_ATTEMPTS[tier] do
        local cand = generateLatinSquare(n)
        local cand_clues = computeAllClues(cand, n)
        if Logic.solve(cand_clues, n, tier) then
            sol, clues = cand, cand_clues
            break
        end
    end
    if not sol then
        sol = fallbackSquare(n)
        clues = computeAllClues(sol, n)
    end
    local order = {}
    for c = 1, n do
        order[#order + 1] = { "top", c }
        order[#order + 1] = { "bottom", c }
    end
    for r = 1, n do
        order[#order + 1] = { "left", r }
        order[#order + 1] = { "right", r }
    end
    shuffle(order)
    return { n = n, sol = sol, clues = clues, order = order, removals = {} }
end

-- One pass over the clues still shown: a clue is hidden if logic.lua,
-- allowed rules up to `tier`, still solves the grid; otherwise it stays.
-- Stops once `stop_after` clues are hidden in all. Returns how many this
-- pass hid. Every state of the dig is a checked puzzle.
local function digPass(dig, tier, stop_after, on_progress)
    local clues, removals = dig.clues, dig.removals
    local removed = 0
    for i, slot in ipairs(dig.order) do
        if #removals >= stop_after then break end
        if on_progress then on_progress(i / #dig.order) end
        local side, idx = slot[1], slot[2]
        local saved = clues[side][idx]
        if saved then
            clues[side][idx] = nil
            if Logic.solve(clues, dig.n, tier) then
                removals[#removals + 1] = slot
                removed = removed + 1
            else
                clues[side][idx] = saved
            end
        end
    end
    return removed
end

-- The clue set after the first `count` removals of the dig.
local function digPrefix(dig, count)
    local clues = computeAllClues(dig.sol, dig.n)
    for i = 1, count do
        local slot = dig.removals[i]
        clues[slot[1]][slot[2]] = nil
    end
    return clues
end

-- Levels, all graded by logic.lua (no level ever needs a guess):
--   Easy   dug with tier 1 only (edge bounds + singles), and at least
--          EASY_CLUE_RATIO of the clues stay.
--   Hard   dug with tier 2 (one clue at a time), then with tier 3 (both
--          clues together, rows without clues): the fewest clues; needs
--          tier 2, and tier 3 whenever tier 3 hid something.
--   Medium the same dig stopped halfway between Easy's clue count and the
--          end of tier 2, and never before the first state tier 1 cannot
--          solve: needs tier 2, shows more clues than Hard.
-- (Fewer clues never make a puzzle easier for logic.lua, so "tier 1 can
-- solve it" switches off once along the dig and a binary search finds it.)
-- A dig that tier 1 can still solve at the end, or where Medium would equal
-- Hard, is redone on a new square, a bounded number of times (counted,
-- never timed: the same seed must give the same puzzle on every device).
-- If all fail, the last dig is used anyway; it is still solvable without
-- guessing.
--
-- on_progress (optional): called with a 0..1 fraction while digging, for
-- game-common's GenProgress bar.
function SkyscraperBoard:generate(difficulty, on_progress)
    self.difficulty = difficulty or self.difficulty
    if not FALLBACK_SQUARES[self.n] then self.n = DEFAULT_N end
    local n     = self.n
    local slots = 4 * n
    local diff  = LOGIC_LEVELS[self.difficulty] and self.difficulty or "medium"
    local easy_removals = slots - math.ceil(slots * EASY_CLUE_RATIO)

    local dig, keep
    if diff == "easy" then
        dig = newDig(n, 1)
        digPass(dig, 1, easy_removals, on_progress)
        keep = #dig.removals
    else
        for attempt = 1, DIG_ATTEMPTS do
            -- Most first attempts succeed: give the first one 80 % of the
            -- bar and each later one 80 % of what is left.
            local from, span = 1 - 0.2 ^ (attempt - 1), 0.8 * 0.2 ^ (attempt - 1)
            local function progress(f)
                if on_progress then on_progress(from + span * f * 0.5) end
            end
            dig = newDig(n, 2)
            digPass(dig, 2, slots, progress)
            local m = #dig.removals
            -- First prefix length that tier 1 cannot solve (m + 1: none).
            local lo, hi = 0, m + 1
            if Logic.solve(dig.clues, n, 1) then lo = m + 1 end
            while hi - lo > 1 do
                local mid = math.floor((lo + hi) / 2)
                if Logic.solve(digPrefix(dig, mid), n, 1) then lo = mid else hi = mid end
            end
            local first_l2 = lo + 1
            local ok = first_l2 <= m
            local tier3 = 0
            if ok and (diff == "hard" or first_l2 == m) then
                tier3 = digPass(dig, 3, slots, function(f) progress(1 + f) end)
            end
            if diff == "hard" then
                keep = #dig.removals
            else
                local mid = math.floor((easy_removals + m) / 2)
                keep = math.min(math.max(first_l2, math.min(mid, m - 1)), m)
            end
            if ok and (m > first_l2 or tier3 > 0) then break end
        end
    end
    if on_progress then on_progress(1) end

    self.solution = dig.sol
    self.clues    = digPrefix(dig, keep)

    -- Reset player grid (all empty, no given cells in skyscraper)
    self.grid        = emptyGrid(n)
    self.given       = emptyBoolGrid(n)   -- always false; kept for API consistency
    self.wrong_marks = emptyBoolGrid(n)
    self.sel_r       = nil
    self.sel_c       = nil
end

-- ---------------------------------------------------------------------------
-- Cell access
-- ---------------------------------------------------------------------------

function SkyscraperBoard:selectCell(r, c)
    self.sel_r = r
    self.sel_c = c
end

function SkyscraperBoard:setCell(r, c, v)
    if v < 0 or v > self.n then return false end
    self.grid[r][c] = v
    self.wrong_marks[r][c] = false
    return true
end

function SkyscraperBoard:clearCell(r, c)
    self.grid[r][c] = 0
    self.wrong_marks[r][c] = false
    return true
end

function SkyscraperBoard:getDisplayValue(r, c)
    return self.grid[r][c]
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

function SkyscraperBoard:checkConflicts()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local v = self.grid[r][c]
            self.wrong_marks[r][c] = (v ~= 0 and v ~= self.solution[r][c])
        end
    end
end

-- Solved when the grid keeps the rules: every row and column holds 1..n
-- once and every shown clue sees the right count. Puzzles built since 1.6.0
-- have one solution, so that is the stored one; a save from before could
-- have had several, and any of them counts.
function SkyscraperBoard:isSolved()
    local n = self.n
    local g = self.grid
    for i = 1, n do
        local in_row, in_col = {}, {}
        for j = 1, n do
            local a, b = g[i][j], g[j][i]
            if a < 1 or a > n or in_row[a] or b < 1 or b > n or in_col[b] then
                return false
            end
            in_row[a], in_col[b] = true, true
        end
    end
    local clues = self.clues or {}
    local function sees(want, line)
        return not want or countVisible(line) == want
    end
    for i = 1, n do
        local row, row_rev, col, col_rev = {}, {}, {}, {}
        for j = 1, n do
            row[j], row_rev[j] = g[i][j], g[i][n - j + 1]
            col[j], col_rev[j] = g[j][i], g[n - j + 1][i]
        end
        if not (sees(clues.left and clues.left[i], row)
                and sees(clues.right and clues.right[i], row_rev)
                and sees(clues.top and clues.top[i], col)
                and sees(clues.bottom and clues.bottom[i], col_rev)) then
            return false
        end
    end
    return true
end

function SkyscraperBoard:getRemainingCells()
    local n   = self.n
    local cnt = 0
    for r = 1, n do
        for c = 1, n do
            if self.grid[r][c] == 0 then cnt = cnt + 1 end
        end
    end
    return cnt
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

-- Givens live in `given`, and the player's own work in `grid` (not `user`).
Hint.install(SkyscraperBoard, {
    getUser     = function(b, r, c) return b.grid[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] end,
    isGiven     = function(b, r, c) return b.given[r] and b.given[r][c] == true end,
    setCell     = function(b, r, c, v) return b:setCell(r, c, v) end,
    clearCell   = function(b, r, c) return b:clearCell(r, c) end,
})

function SkyscraperBoard:serialize()
    local n = self.n
    local clues_out = {
        top    = {},
        bottom = {},
        left   = {},
        right  = {},
    }
    for k, t in pairs(self.clues) do
        for i, v in pairs(t) do
            clues_out[k][i] = v
        end
    end
    return {
        n           = n,
        difficulty  = self.difficulty,
        solution    = copyGrid(self.solution, n),
        grid        = copyGrid(self.grid, n),
        clues       = clues_out,
        wrong_marks = copyGrid(self.wrong_marks, n),
    }
end

function SkyscraperBoard:load(data)
    if type(data) ~= "table" or not data.solution then return false end
    local n = data.n or DEFAULT_N
    self.n          = n
    self.difficulty = data.difficulty or DEFAULT_DIFFICULTY
    self.solution   = copyGrid(data.solution, n)
    self.grid       = copyGrid(data.grid or {}, n)
    self.given      = emptyBoolGrid(n)

    self.clues = { top = {}, bottom = {}, left = {}, right = {} }
    if type(data.clues) == "table" then
        for k, t in pairs(data.clues) do
            if self.clues[k] then
                for i, v in pairs(t) do
                    self.clues[k][i] = v
                end
            end
        end
    end

    self.wrong_marks = emptyBoolGrid(n)
    if data.wrong_marks then
        for r = 1, n do
            for c = 1, n do
                local v = data.wrong_marks[r] and data.wrong_marks[r][c]
                self.wrong_marks[r][c] = (v == true or v == 1)
            end
        end
    end
    self.sel_r = nil
    self.sel_c = nil
    return true
end

-- Export helper for widget
SkyscraperBoard.countVisible = countVisible

-- For the specs
SkyscraperBoard._computeAllClues = computeAllClues
SkyscraperBoard._fallbackSquare  = fallbackSquare

return SkyscraperBoard
