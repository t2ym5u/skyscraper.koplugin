local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase             = require("screen_base")
local MenuHelper             = require("menu_helper")
local GenProgress            = require("gen_progress")
local SkyscraperBoard        = lrequire("board")
local SkyscraperBoardWidget  = lrequire("board_widget")

local GRID_SIZES = { 4, 5 }

-- ---------------------------------------------------------------------------
-- SkyscraperScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Skyscraper — Rules

Place building heights 1 to N in each row and column (one of each, like Sudoku).

Visibility clues:
• Numbers on the edges show how many buildings are visible when looking along that row or column from that side.
• A taller building blocks all shorter buildings behind it.
• A clue of 1 means the tallest building (height N) is closest to that edge.
• A clue of N means all buildings are visible (heights must be in increasing order from that edge).

Tap a cell to select it, then tap a digit to enter a height.
]])

local GAME_RULES_FR = [[
Gratte-Ciel — Règles

Placez des hauteurs de bâtiments de 1 à N dans chaque ligne et colonne (une de chaque, comme au Sudoku).

Indices de visibilité :
• Les nombres sur les bords indiquent combien de bâtiments sont visibles en regardant depuis ce côté.
• Un bâtiment plus grand cache tous les bâtiments plus petits derrière lui.
• Un indice de 1 signifie que le bâtiment le plus grand (hauteur N) est le plus proche de ce bord.
• Un indice de N signifie que tous les bâtiments sont visibles (les hauteurs doivent être en ordre croissant depuis ce bord).

Appuyez sur une case pour la sélectionner, puis sur un chiffre pour entrer une hauteur.
]]

local SkyscraperScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function SkyscraperScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", 5)
    self.board  = SkyscraperBoard:new{ n = n, empty = true }
    if not self.board:load(state) then
        local diff = self.plugin:getSetting("difficulty", "easy")
        GenProgress.run(function(on_progress) self.board:generate(diff, on_progress) end)
    end
    self.selected = nil
    ScreenBase.init(self)
end

function SkyscraperScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function SkyscraperScreen:buildLayout()
    local n            = self.board.n
    local is_landscape = self:isLandscape()

    -- Top action bar
    local title_bar = self:buildTitleBar(_("Skyscraper"), function()
        return {
            { text = _("New game"),            callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = self:getGridButtonText(), callback = function() self:openGridMenu() end },
            { text = self:getDiffButtonText(), callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Digit pad 1..n
    local keys = {}
    for d = 1, n do
        local dv = d
        keys[#keys + 1] = { id = "digit_" .. d, text = tostring(d),
                            callback = function() self:onDigit(dv) end }
    end
    local number_pad = self:buildNumberPad(keys)

    -- Bottom bar
    local action_bar = self:buildActionBar({
        { text = _("Erase"), callback = function() self:onErase() end },
        { text = _("Check"), callback = function() self:onCheck() end },
        { text = _("Hint"),  callback = function() self:onHint() end },
    })

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        number_pad,
        VerticalSpan:new{ width = Size.span.vertical_default },
        action_bar,
    }

    -- The widget draws its own outer border, so the frame only pads.
    local frame_pad = Size.padding.large
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = SkyscraperBoardWidget:new{
        max_size       = math.min(budget_w, budget_h) - 2 * frame_pad,
        board          = self.board,
        onCellSelected = function(r, c) self:onCellSelected(r, c) end,
    }
    if self.selected then
        self.board_widget:setSelected(self.selected.r, self.selected.c)
    end
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function SkyscraperScreen:onCellSelected(r, c)
    self.selected = { r = r, c = c }
    self.board_widget:setSelected(r, c)
    self.board_widget:refresh()
    self:updateStatus()
end

function SkyscraperScreen:onDigit(d)
    if not self.selected then return end
    local r, c = self.selected.r, self.selected.c
    -- Toggle off if same digit entered twice
    if self.board.grid[r][c] == d then
        self.board:clearCell(r, c)
    else
        self.board:setCell(r, c, d)
    end
    self.plugin:saveState(self.board:serialize())
    if self.board:isSolved() then
        self:updateStatus(_("Congratulations! Puzzle solved!"))
    else
        self:updateStatus()
    end
    self.board_widget:refresh()
end

function SkyscraperScreen:onErase()
    if not self.selected then return end
    local r, c = self.selected.r, self.selected.c
    self.board:clearCell(r, c)
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Game actions
-- ---------------------------------------------------------------------------

function SkyscraperScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    local n    = self.plugin:getSetting("grid_n", 5)
    self.board = SkyscraperBoard:new{ n = n, empty = true }
    GenProgress.run(function(on_progress) self.board:generate(diff, on_progress) end)
    self.selected = nil
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function SkyscraperScreen:onCheck()
    self.board:checkConflicts()
    self.board_widget:refresh()
    local remaining = self.board:getRemainingCells()
    if remaining > 0 then
        self:updateStatus(T(_("Check done. %1 cell(s) remaining."), remaining))
    elseif self.board:isSolved() then
        self:updateStatus(_("Congratulations! Puzzle solved!"))
    else
        self:updateStatus(_("Some cells are incorrect."))
    end
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function SkyscraperScreen:openGridMenu()
    local sizes = {}
    for _, sz in ipairs(GRID_SIZES) do
        sizes[#sizes + 1] = {
            id   = sz,
            text = sz .. "\xC3\x97" .. sz,
        }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.plugin:getSetting("grid_n", 5),
        parent    = self,
        on_select = function(sz)
            if sz ~= self.board.n then
                self.plugin:saveSetting("grid_n", sz)
                self:onNewGame()
            end
        end,
    }
end

function SkyscraperScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDiffButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function SkyscraperScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board:isSolved() then
        status = _("Congratulations! Puzzle solved!")
    else
        local remaining = self.board:getRemainingCells()
        local diff      = self.plugin:getSetting("difficulty", "easy")
        local label     = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        status = self:joinStatus(T("%1×%2", self.board.n, self.board.n), label, T(_("Empty: %1"), remaining))
    end
    ScreenBase.updateStatus(self, status)
    -- Every move, hint, undo and reveal ends with a status update, so this
    -- is where the bar learns that the round ended (or was undone).
    self:refreshActionBar()
end

-- ---------------------------------------------------------------------------
-- Button text helpers
-- ---------------------------------------------------------------------------

function SkyscraperScreen:getGridButtonText()
    return T(_("Size: %1"), self.board.n .. "\xC3\x97" .. self.board.n)
end

function SkyscraperScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Difficulty: %1"), label)
end

function SkyscraperScreen:isRoundOver()
    return self.board:isSolved()
end

return SkyscraperScreen
