local grid_utils = require("grid_utils")

local emptyGrid     = grid_utils.emptyGrid
local emptyBoolGrid = grid_utils.emptyBoolGrid
local copyGrid      = grid_utils.copyGrid
local shuffle       = grid_utils.shuffle

local DEFAULT_N          = 5
local DEFAULT_DIFFICULTY = "easy"

-- Fraction of clues to keep per difficulty
local CLUE_RATIOS = { easy = 0.60, medium = 0.40, hard = 0.25 }

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

-- Counts Latin-square completions (up to `limit`) consistent with the
-- currently-visible clues, using full backtracking with clue checks applied
-- as soon as a row/column completes (n is small -- 4 or 5 -- so this stays
-- cheap even without per-cell clue pruning). Returns (solutions_found,
-- exhausted); exhausted=true means node_budget was hit before the search
-- concluded, so the count isn't proof. Mirrors
-- sudokukiller.koplugin/board.lua's countCageSolutions.
local NODE_BUDGET_UNIQUENESS = 500000

local function countSolutions(clues, n, limit, node_budget)
    local grid = {}
    for r = 1, n do grid[r] = {}; for c = 1, n do grid[r][c] = 0 end end
    local solutions, nodes, exhausted = 0, 0, false

    local function rowComplete(r) for c = 1, n do if grid[r][c] == 0 then return false end end return true end
    local function colComplete(c) for r = 1, n do if grid[r][c] == 0 then return false end end return true end
    local function checkRowClues(r)
        local seq = {}
        for c = 1, n do seq[c] = grid[r][c] end
        if clues.left[r] and countVisible(seq) ~= clues.left[r] then return false end
        if clues.right[r] then
            local rev = {}
            for i = 1, n do rev[i] = seq[n - i + 1] end
            if countVisible(rev) ~= clues.right[r] then return false end
        end
        return true
    end
    local function checkColClues(c)
        local seq = {}
        for r = 1, n do seq[r] = grid[r][c] end
        if clues.top[c] and countVisible(seq) ~= clues.top[c] then return false end
        if clues.bottom[c] then
            local rev = {}
            for i = 1, n do rev[i] = seq[n - i + 1] end
            if countVisible(rev) ~= clues.bottom[c] then return false end
        end
        return true
    end

    local function candidatesFor(r, c)
        local used = {}
        for cc = 1, n do if grid[r][cc] ~= 0 then used[grid[r][cc]] = true end end
        for rr = 1, n do if grid[rr][c] ~= 0 then used[grid[rr][c]] = true end end
        local cands = {}
        for v = 1, n do if not used[v] then cands[#cands + 1] = v end end
        return cands
    end

    local cells = {}
    for r = 1, n do for c = 1, n do cells[#cells + 1] = { r = r, c = c } end end

    local function search(depth)
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end
        if depth > #cells then solutions = solutions + 1; return end
        local best_idx, best_cands, best_len = nil, nil, n + 1
        for i, cell in ipairs(cells) do
            if grid[cell.r][cell.c] == 0 then
                local cands = candidatesFor(cell.r, cell.c)
                if #cands < best_len then
                    best_len, best_cands, best_idx = #cands, cands, i
                    if best_len <= 1 then break end
                end
            end
        end
        if best_idx == nil then solutions = solutions + 1; return end
        if best_len == 0 then return end
        local cell = cells[best_idx]
        for _, v in ipairs(best_cands) do
            grid[cell.r][cell.c] = v
            local ok = true
            if rowComplete(cell.r) and not checkRowClues(cell.r) then ok = false end
            if ok and colComplete(cell.c) and not checkColClues(cell.c) then ok = false end
            if ok then search(depth + 1) end
            grid[cell.r][cell.c] = 0
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
    obj:generate(obj.difficulty)
    return obj
end

-- ---------------------------------------------------------------------------
-- Generate
-- ---------------------------------------------------------------------------

-- Even the FULL 4n-clue set (before any digging) is not always unique for
-- an arbitrary Latin square -- distinct squares can happen to produce
-- identical visibility-clue vectors in all 4 directions (same structural
-- shape as kakuro's "generalized rectangle swap", just at these small grid
-- sizes: n=4 gives only 16 clues total). Digging can only ever remove
-- information, so a Latin square whose full clue set is already ambiguous
-- can never be rescued by hiding clues -- it needs a fresh Latin square
-- instead. Bounded retry: n is tiny (4-5) so both generateLatinSquare and
-- countSolutions are cheap.
local FULL_CLUE_MAX_ATTEMPTS = 30

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

function SkyscraperBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n = self.n

    -- 1-2. Build a solution whose FULL clue set is already unique, retrying
    -- with a fresh Latin square if not (see comment above).
    local sol, clues
    for _attempt = 1, FULL_CLUE_MAX_ATTEMPTS do
        local candidate_sol = generateLatinSquare(n)
        local candidate_clues = computeAllClues(candidate_sol, n)
        local solutions, exhausted = countSolutions(candidate_clues, n, 2, NODE_BUDGET_UNIQUENESS)
        if not exhausted and solutions == 1 then
            sol, clues = candidate_sol, candidate_clues
            break
        end
    end
    if not sol then
        -- Every attempt's full clue set was ambiguous (should be very
        -- rare) -- fall back to the last candidate rather than looping
        -- forever; digging below will still only remove clues that don't
        -- introduce *additional* ambiguity, it just can't fix what was
        -- already broken before any digging.
        sol = generateLatinSquare(n)
        clues = computeAllClues(sol, n)
    end
    self.solution = sol

    -- 3. Decide which clues to expose: dig one at a time (like
    -- sudoku-common's hole-digging), starting with every clue visible and
    -- verifying with countSolutions after each tentative hide, putting the
    -- clue back if that broke uniqueness -- the old "shuffle clues, keep a
    -- flat ratio" approach never checked this (see
    -- docs/generator_robustness_audit.md's Tier 2 table: measured near-0%
    -- unique even on Easy -- skyscraper has no cell givens at all, only
    -- these clues, so this is the only lever available).
    local ratio = CLUE_RATIOS[self.difficulty] or 0.40
    local all_clues = {}
    for c = 1, n do
        all_clues[#all_clues + 1] = { side = "top",    idx = c }
        all_clues[#all_clues + 1] = { side = "bottom", idx = c }
    end
    for r = 1, n do
        all_clues[#all_clues + 1] = { side = "left",   idx = r }
        all_clues[#all_clues + 1] = { side = "right",  idx = r }
    end
    local keep = math.max(4, math.floor(#all_clues * ratio))
    local target_hide = #all_clues - keep

    shuffle(all_clues)
    local hidden = 0
    for _, cl in ipairs(all_clues) do
        if hidden >= target_hide then break end
        local saved = clues[cl.side][cl.idx]
        clues[cl.side][cl.idx] = nil
        local solutions, exhausted = countSolutions(clues, n, 2, NODE_BUDGET_UNIQUENESS)
        if not exhausted and solutions == 1 then
            hidden = hidden + 1
        else
            clues[cl.side][cl.idx] = saved
        end
    end
    self.clues = clues

    -- 4. Reset player grid (all empty, no given cells in skyscraper)
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

function SkyscraperBoard:isSolved()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if self.grid[r][c] ~= self.solution[r][c] then return false end
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

return SkyscraperBoard
