local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local ScreenBase             = require("screen_base")
local MenuHelper             = require("menu_helper")
local SkyscraperBoard        = lrequire("board")
local SkyscraperBoardWidget  = lrequire("board_widget")

local DeviceScreen = Device.screen

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
    self.board  = SkyscraperBoard:new{ n = n }
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
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
    local n  = self.board.n
    local sw = DeviceScreen:getWidth()
    local is_landscape = self:isLandscape()

    self.board_widget = SkyscraperBoardWidget:new{
        board          = self.board,
        onCellSelected = function(r, c) self:onCellSelected(r, c) end,
    }
    if self.selected then
        self.board_widget:setSelected(self.selected.r, self.selected.c)
    end

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_frame_size  = self.board_widget.size + (Size.padding.large + Size.margin.default) * 2
    local right_panel_width = sw - board_frame_size - Size.span.horizontal_default
    local button_width = is_landscape
        and math.max(right_panel_width - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)

    -- Top action bar
    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("New"),        callback = function() self:onNewGame() end },
            { id = "grid_button",     text = self:getGridButtonText(),
              callback = function() self:openGridMenu() end },
            { id = "diff_button",     text = self:getDiffButtonText(),
              callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.grid_button = top_buttons:getButtonById("grid_button")
    self.diff_button = top_buttons:getButtonById("diff_button")

    -- Digit buttons 1..n
    local digit_row = {}
    for d = 1, n do
        local dv = d
        digit_row[#digit_row + 1] = {
            id       = "digit_" .. dv,
            text     = tostring(dv),
            callback = function() self:onDigit(dv) end,
        }
    end
    local digit_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = { digit_row },
    }

    -- Bottom action bar
    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("Erase"),  callback = function() self:onErase() end },
            { text = _("Check"),  callback = function() self:onCheck() end },
        }},
    }

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            digit_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            digit_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
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
    self.board = SkyscraperBoard:new{ n = n }
    self.board:generate(diff)
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
        title     = _("Select grid size"),
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
        status = T(_("%1\xC3\x97%2 \xC2\xB7 %3 \xC2\xB7 Empty: %4"),
            self.board.n, self.board.n, label, remaining)
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Button text helpers
-- ---------------------------------------------------------------------------

function SkyscraperScreen:getGridButtonText()
    return T(_("Grid: %1"), self.board.n .. "\xC3\x97" .. self.board.n)
end

function SkyscraperScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Diff: %1"), label)
end

return SkyscraperScreen
