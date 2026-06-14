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

function SkyscraperBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n = self.n

    -- 1. Build solution (random Latin square)
    local sol = generateLatinSquare(n)
    self.solution = sol

    -- 2. Compute all 4n clues from the solution
    local top    = {}
    local bottom = {}
    local left   = {}
    local right  = {}

    for c = 1, n do
        local col_fwd = {}
        local col_rev = {}
        for r = 1, n do
            col_fwd[r] = sol[r][c]
            col_rev[r] = sol[n - r + 1][c]
        end
        top[c]    = countVisible(col_fwd)
        bottom[c] = countVisible(col_rev)
    end

    for r = 1, n do
        local row_fwd = {}
        local row_rev = {}
        for c = 1, n do
            row_fwd[c] = sol[r][c]
            row_rev[c] = sol[r][n - c + 1]
        end
        left[r]  = countVisible(row_fwd)
        right[r] = countVisible(row_rev)
    end

    -- 3. Decide which clues to expose based on difficulty
    local ratio = CLUE_RATIOS[self.difficulty] or 0.40
    local all_clues = {}
    for c = 1, n do
        all_clues[#all_clues + 1] = { side = "top",    idx = c, val = top[c] }
        all_clues[#all_clues + 1] = { side = "bottom", idx = c, val = bottom[c] }
    end
    for r = 1, n do
        all_clues[#all_clues + 1] = { side = "left",   idx = r, val = left[r] }
        all_clues[#all_clues + 1] = { side = "right",  idx = r, val = right[r] }
    end
    shuffle(all_clues)
    local keep = math.max(4, math.floor(#all_clues * ratio))

    local clues = { top = {}, bottom = {}, left = {}, right = {} }
    for i = 1, keep do
        local cl = all_clues[i]
        clues[cl.side][cl.idx] = cl.val
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
