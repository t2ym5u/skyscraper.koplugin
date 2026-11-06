-- Human-style, no-trial solver for Skyscraper: heights 1..n fill an n x n
-- grid as a Latin square, and a clue on an edge says how many buildings are
-- seen from there (a taller one hides the shorter ones behind it). Used by
-- the generator to grade a dig: a clue may only be hidden if this solver
-- can still finish the grid, so a player never has to guess.
--
-- The solver only ever rules out a height that the rules below forbid; it
-- never tries a height to see whether it leads to a contradiction. A grid it
-- fills this way has exactly one solution. Rules, by tier:
--
--   1. Edge bounds, singles and short lines. Read once from the clues: a 1
--      puts the tallest building next to that edge, an n puts 1..n in
--      rising order from it, and a clue k caps the i-th cell from its edge
--      at n - k + i (k buildings must still rise into view behind it).
--      Then plain Latin square work: a cell with one height left gets it, a
--      height with one place left in a row or column goes there. And a
--      clued row or column with only SHORT_LINE cells left empty: of the
--      (at most two) ways to finish it, keep the ones its clues allow.
--   2. One clue at a time. For a row or column, list the orderings of
--      1..n that fit the heights still possible in each cell and show the
--      right count from ONE edge; a height that no such ordering puts on a
--      cell is struck out. Each clue of the line is used on its own.
--   3. Both clues together, and lines without clues. The same, keeping
--      only the orderings that show the right counts from both ends at
--      once; a line with no clue gets the same treatment with the Latin
--      rule alone.
--
-- solve(clues, n, level) -> solved (bool), values (grid[r][c], 0 if not
-- found) and a stats table { short_line = , one_clue = , two_clues = }
-- counting the rounds in which each kind of line step made progress.

local SHORT_LINE = 2

local perm_cache = {}

-- Every ordering of 1..n, with how many buildings it shows from its start
-- (.a) and from its end (.b).
local function permutations(n)
    if perm_cache[n] then return perm_cache[n] end
    local perms, cur, used = {}, {}, {}
    local function visible(p, from, to, step)
        local tallest, seen = 0, 0
        for i = from, to, step do
            if p[i] > tallest then tallest, seen = p[i], seen + 1 end
        end
        return seen
    end
    local function build(k)
        if k > n then
            local p = {}
            for i = 1, n do p[i] = cur[i] end
            p.a, p.b = visible(p, 1, n, 1), visible(p, n, 1, -1)
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

-- The 2n lines of the grid, as flat cell indices in order from the clue
-- `a` edge (left / top), built once per n.
local line_cache = {}

local function lineCells(n)
    if line_cache[n] then return line_cache[n] end
    local out = {}
    for r = 1, n do
        local cells = {}
        for c = 1, n do cells[c] = (r - 1) * n + c end
        out[#out + 1] = cells
    end
    for c = 1, n do
        local cells = {}
        for r = 1, n do cells[r] = (r - 1) * n + c end
        out[#out + 1] = cells
    end
    line_cache[n] = out
    return out
end

local function solve(clues, n, level)
    local total = n * n
    -- cand[(i - 1) * n + v]: height v still possible on cell i.
    local cand, cnt, val = {}, {}, {}
    for i = 1, total do
        cnt[i], val[i] = n, 0
    end
    for x = 1, total * n do cand[x] = true end
    local LC = lineCells(n)
    local L = {}
    for r = 1, n do
        L[r] = { cells = LC[r], a = clues.left[r], b = clues.right[r] }
        L[n + r] = { cells = LC[n + r], a = clues.top[r], b = clues.bottom[r] }
    end
    local stats = { short_line = 0, one_clue = 0, two_clues = 0 }
    local bad = false

    local function strike(i, v)
        local x = (i - 1) * n + v
        if cand[x] then
            cand[x] = false
            cnt[i] = cnt[i] - 1
            if cnt[i] == 0 then bad = true end
            return true
        end
        return false
    end

    local function result()
        local grid = {}
        for r = 1, n do
            grid[r] = {}
            for c = 1, n do grid[r][c] = val[(r - 1) * n + c] end
        end
        return grid
    end

    -- Tier 1a: edge bounds, once.
    for _, line in ipairs(L) do
        for side = 1, 2 do
            local k
            if side == 1 then k = line.a else k = line.b end
            if k then
                for i = 1, n do
                    local cell = line.cells[side == 1 and i or n - i + 1]
                    if k == 1 then
                        if i == 1 then
                            for v = 1, n - 1 do strike(cell, v) end
                        end
                    elseif k == n then
                        for v = 1, n do
                            if v ~= i then strike(cell, v) end
                        end
                    else
                        for v = n - k + i + 1, n do strike(cell, v) end
                    end
                end
            end
        end
    end
    if bad then return false, result(), stats end

    local solved = 0

    -- Tier 1b: Latin singles until nothing changes. Returns false on a
    -- contradiction.
    local function singles()
        local changed = true
        while changed do
            changed = false
            for i = 1, total do
                if val[i] == 0 and cnt[i] == 1 then
                    local v
                    local base = (i - 1) * n
                    for x = 1, n do if cand[base + x] then v = x; break end end
                    val[i] = v
                    solved = solved + 1
                    changed = true
                    local r, c = math.floor((i - 1) / n), (i - 1) % n
                    for k = 0, n - 1 do
                        local j1, j2 = r * n + k + 1, k * n + c + 1
                        if j1 ~= i then strike(j1, v) end
                        if j2 ~= i then strike(j2, v) end
                    end
                    if bad then return false end
                end
            end
            for li = 1, #L do
                local cells = L[li].cells
                for v = 1, n do
                    local where, count, done = nil, 0, false
                    for _, i in ipairs(cells) do
                        if val[i] == v then done = true; break end
                        if cand[(i - 1) * n + v] then where, count = i, count + 1 end
                    end
                    if not done then
                        if count == 0 then return false end
                        if count == 1 then
                            for x = 1, n do
                                if x ~= v then strike(where, x) end
                            end
                            changed = true
                        end
                    end
                end
            end
        end
        return true
    end

    -- Tiers 2 and 3: strike every height no fitting ordering of the line
    -- puts on a cell. joint = false checks each clue alone, true both at
    -- once. Returns true if something was struck, nil on a contradiction.
    local perms = permutations(n)
    local function linePass(joint, max_open)
        local changed = false
        for li = 1, #L do
            local line = L[li]
            local cells = line.cells
            local open = 0
            for _, i in ipairs(cells) do
                if val[i] == 0 then open = open + 1 end
            end
            if open > 0 and open <= max_open and (line.a or line.b or (joint and max_open == n)) then
                local checks
                if joint then
                    checks = { { line.a, line.b } }
                else
                    checks = {}
                    if line.a then checks[#checks + 1] = { line.a, nil } end
                    if line.b then checks[#checks + 1] = { nil, line.b } end
                end
                for _, chk in ipairs(checks) do
                    local wa, wb = chk[1], chk[2]
                    local support = {}
                    for p = 1, n do support[p] = {} end
                    local any = false
                    for _, perm in ipairs(perms) do
                        if (not wa or perm.a == wa) and (not wb or perm.b == wb) then
                            local fits = true
                            for p = 1, n do
                                if not cand[(cells[p] - 1) * n + perm[p]] then fits = false; break end
                            end
                            if fits then
                                any = true
                                for p = 1, n do support[p][perm[p]] = true end
                            end
                        end
                    end
                    if not any then return nil end
                    for p = 1, n do
                        local i = cells[p]
                        for v = 1, n do
                            if cand[(i - 1) * n + v] and not support[p][v] then
                                strike(i, v)
                                changed = true
                            end
                        end
                    end
                    if bad then return nil end
                end
            end
        end
        return changed
    end

    while true do
        if not singles() then return false, result(), stats end
        if solved == total then return true, result(), stats end
        local progressed = false
        local got = linePass(true, SHORT_LINE)
        if got == nil then return false, result(), stats end
        if got then
            stats.short_line = stats.short_line + 1
            progressed = true
        elseif level >= 2 then
            got = linePass(false, n)
            if got == nil then return false, result(), stats end
            if got then
                stats.one_clue = stats.one_clue + 1
                progressed = true
            elseif level >= 3 then
                got = linePass(true, n)
                if got == nil then return false, result(), stats end
                if got then
                    stats.two_clues = stats.two_clues + 1
                    progressed = true
                end
            end
        end
        if not progressed then return false, result(), stats end
    end
end

return {
    solve        = solve,
    permutations = permutations,
}
