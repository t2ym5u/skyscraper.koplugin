local Blitbuffer = require("ffi/blitbuffer")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")
local Size       = require("ui/size")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

-- ---------------------------------------------------------------------------
-- Colour palette
-- ---------------------------------------------------------------------------

local C_BG       = Blitbuffer.COLOR_WHITE
local C_SEL      = Blitbuffer.COLOR_GRAY_D
local C_WRONG    = Blitbuffer.COLOR_GRAY_B
local C_LINE     = Blitbuffer.COLOR_BLACK
local C_USER_FG  = Blitbuffer.COLOR_GRAY_2
local C_CLUE_FG  = Blitbuffer.COLOR_BLACK

-- ---------------------------------------------------------------------------
-- SkyscraperBoardWidget
--
-- The widget reserves one extra "clue cell" on each of the four sides.
-- Total painted area: (n+2) x (n+2) cells, but the grid itself is n x n
-- starting at offset (cell_size, cell_size).
-- ---------------------------------------------------------------------------

local SkyscraperBoardWidget = GridWidgetBase:extend{
    board = nil,
}

function SkyscraperBoardWidget:init()
    local n       = self.board and self.board.n or 5
    -- We pass n+2 cols/rows so that GridWidgetBase sizes cells to fit the full
    -- (n+2)×(n+2) area; the actual game grid sits in the inner n×n region.
    self.cols       = n + 2
    self.rows       = n + 2
    self.size_ratio = 0.82
    GridWidgetBase.init(self)

    -- Cache derived values
    self._n       = n
    self._cell    = self.cell_w   -- cell_w == cell_h for square grids
end

-- ---------------------------------------------------------------------------
-- Tap handling: only react to cells inside the n×n game grid
-- ---------------------------------------------------------------------------

function SkyscraperBoardWidget:onCellTap(row, col)
    local n = self._n
    -- Grid cells are at rows 2..(n+1), cols 2..(n+1) (1-based in the n+2 grid)
    local gr = row - 1   -- game row  1..n
    local gc = col - 1   -- game col  1..n
    if gr >= 1 and gr <= n and gc >= 1 and gc <= n then
        if self.onCellSelected then
            self.onCellSelected(gr, gc)
        end
    end
end

-- ---------------------------------------------------------------------------
-- paintTo
-- ---------------------------------------------------------------------------

function SkyscraperBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local n    = self._n
    local cell = self._cell

    -- White background for entire widget
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    -- Grid origin (top-left of the inner n×n area)
    local gx = x + math.floor(cell)     -- offset by one clue cell
    local gy = y + math.floor(cell)

    -- -----------------------------------------------------------------------
    -- Cell backgrounds for the game grid
    -- -----------------------------------------------------------------------
    for r = 1, n do
        for c = 1, n do
            local cx = gx + math.floor((c - 1) * cell)
            local cy = gy + math.floor((r - 1) * cell)
            local cw = math.ceil(cell)
            local ch = math.ceil(cell)

            if self.selected and self.selected.r == r and self.selected.c == c then
                bb:paintRect(cx, cy, cw, ch, C_SEL)
            elseif self.board.wrong_marks[r][c] then
                bb:paintRect(cx, cy, cw, ch, C_WRONG)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Game grid lines
    -- -----------------------------------------------------------------------
    local thin  = Size.line.thin  or 1
    local thick = Size.line.thick or 2
    local gw    = math.ceil(n * cell)
    local gh    = math.ceil(n * cell)

    for i = 0, n do
        local lw = (i == 0 or i == n) and thick or thin
        drawLine(bb, gx + math.floor(i * cell), gy, lw, gh, C_LINE)
        drawLine(bb, gx, gy + math.floor(i * cell), gw, lw, C_LINE)
    end

    -- -----------------------------------------------------------------------
    -- Cell values (user input)
    -- -----------------------------------------------------------------------
    local cell_padding = self.number_padding or 2
    local cell_inner   = math.max(1, math.floor(cell - 2 * cell_padding))

    for r = 1, n do
        for c = 1, n do
            local v = self.board:getDisplayValue(r, c)
            if v ~= 0 then
                local cx   = gx + math.floor((c - 1) * cell)
                local cy   = gy + math.floor((r - 1) * cell)
                local text = tostring(v)
                local m    = RenderText:sizeUtf8Text(0, cell_inner, self.number_face, text, true, false)
                local base = cy + cell_padding + math.floor((cell_inner + m.y_top - m.y_bottom) / 2)
                local tx   = cx + cell_padding + math.floor((cell_inner - m.x) / 2)
                RenderText:renderUtf8Text(bb, tx, base, self.number_face, text, true, false, C_USER_FG)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Clue numbers around the grid
    -- -----------------------------------------------------------------------
    local clue_padding = 2
    local clue_inner   = math.max(1, math.floor(cell - 2 * clue_padding))
    local clue_size    = math.max(8, math.floor(cell * 0.55))
    local clue_face    = Font:getFace("cfont", clue_size)

    local function drawClue(cx, cy, val)
        local text = tostring(val)
        local m    = RenderText:sizeUtf8Text(0, clue_inner, clue_face, text, true, false)
        local base = cy + clue_padding + math.floor((clue_inner + m.y_top - m.y_bottom) / 2)
        local tx   = cx + clue_padding + math.floor((clue_inner - m.x) / 2)
        RenderText:renderUtf8Text(bb, tx, base, clue_face, text, true, false, C_CLUE_FG)
    end

    local clues = self.board.clues

    -- Top clues: drawn in row 0 (above the grid)
    for c = 1, n do
        if clues.top[c] then
            local cx = gx + math.floor((c - 1) * cell)
            local cy = y   -- the clue cell row above the grid starts at y
            drawClue(cx, cy, clues.top[c])
        end
    end

    -- Bottom clues: drawn below the grid
    for c = 1, n do
        if clues.bottom[c] then
            local cx = gx + math.floor((c - 1) * cell)
            local cy = gy + math.floor(n * cell)
            drawClue(cx, cy, clues.bottom[c])
        end
    end

    -- Left clues: drawn to the left of the grid
    for r = 1, n do
        if clues.left[r] then
            local cx = x  -- first clue-cell column starts at x
            local cy = gy + math.floor((r - 1) * cell)
            drawClue(cx, cy, clues.left[r])
        end
    end

    -- Right clues: drawn to the right of the grid
    for r = 1, n do
        if clues.right[r] then
            local cx = gx + math.floor(n * cell)
            local cy = gy + math.floor((r - 1) * cell)
            drawClue(cx, cy, clues.right[r])
        end
    end
end

-- ---------------------------------------------------------------------------
-- Expose selection for highlight
-- ---------------------------------------------------------------------------

function SkyscraperBoardWidget:setSelected(r, c)
    self.selected = r and c and { r = r, c = c } or nil
end

return SkyscraperBoardWidget
