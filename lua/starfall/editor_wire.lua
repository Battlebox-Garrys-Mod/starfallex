--[[
Modified version of Wire Editor, you can find original code and it's licence on link below.
https://github.com/wiremod/wire
File in use: https://github.com/wiremod/wire/blob/master/lua/wire/client/text_editor/wire_expression2_editor.lua
]]

local Editor = {}

-- ----------------------------------------------------------------------
-- Fonts
-- ----------------------------------------------------------------------

local defaultFont

if system.IsWindows() then
  defaultFont = "Courier New"
elseif system.IsOSX() then
  defaultFont = "Monaco"
else
  defaultFont = "DejaVu Sans Mono"
end

Editor.FontConVar = CreateClientConVar("wire_expression2_editor_font", defaultFont, true, false)
Editor.FontSizeConVar = CreateClientConVar("wire_expression2_editor_font_size", 16, true, false)
Editor.BlockCommentStyleConVar = CreateClientConVar("wire_expression2_editor_block_comment_style", 1, true, false)
Editor.NewTabOnOpen = CreateClientConVar("wire_expression2_new_tab_on_open", "1", true, false)
Editor.ops_sync_subscribe = CreateClientConVar("wire_expression_ops_sync_subscribe",0,true,false)

Editor.Fonts = {}
-- Font Description

-- Windows
Editor.Fonts["Courier New"] = "Windows standard font"
Editor.Fonts["DejaVu Sans Mono"] = "Default font on Linux"
Editor.Fonts["Consolas"] = ""
Editor.Fonts["Fixedsys"] = ""
Editor.Fonts["Lucida Console"] = ""

-- Mac
Editor.Fonts["Monaco"] = "Mac standard font"

surface.CreateFont("SFEditorDefault", {
    font = "default",
    size = 18,
    weight = 500,
    antialias = true,
    additive = false,
  })

Editor.CreatedFonts = {}

function Editor:SetEditorFont(editor)
  if not self.CurrentFont then
    self:ChangeFont(self.FontConVar:GetString(), self.FontSizeConVar:GetInt())
    return
  end

  editor.CurrentFont = self.CurrentFont
  editor.FontWidth = self.FontWidth
  editor.FontHeight = self.FontHeight
end

function Editor:ChangeFont(FontName, Size)
  if not FontName or FontName == "" or not Size then return end

  -- If font is not already created, create it.
  if not self.CreatedFonts[FontName .. "_" .. Size] then
    local fontTable =
    {
      font = FontName,
      size = Size,
      weight = 400,
      antialias = false,
      additive = false,
    }
    surface.CreateFont("Expression2_" .. FontName .. "_" .. Size, fontTable)
    fontTable.weight = 700
    surface.CreateFont("Expression2_" .. FontName .. "_" .. Size .. "_Bold", fontTable)
    self.CreatedFonts[FontName .. "_" .. Size] = true
  end

  self.CurrentFont = "Expression2_" .. FontName .. "_" .. Size
  surface.SetFont(self.CurrentFont)
  self.FontWidth, self.FontHeight = surface.GetTextSize(" ")

  for i = 1, self:GetNumTabs() do
    self:SetEditorFont(self:GetEditor(i))
  end
end

------------------------------------------------------------------------
-- Colors
------------------------------------------------------------------------

local colors = {
  ["keyword"] = Color(142,192,124),
  ["directive"] = Color(142, 192, 124),
  ["comment"] = Color(146, 131, 116),
  ["string"] = Color(184, 187, 38),
  ["number"] = Color(211, 134, 155),
  ["function"] = Color(184, 187, 38),
  ["library"] = Color(184, 187, 38),
  ["operator"] = Color(211, 134, 155),
  ["notfound"] = Color(251, 241, 199),
  ["userfunction"] = Color(251, 241, 199),
  ["constant"] = Color(211, 134, 155),
}

local colors_defaults = {}

local colors_convars = {}
for k, v in pairs(colors) do
  colors_defaults[k] = Color(v.r, v.g, v.b) -- Copy to save defaults
  colors_convars[k] = CreateClientConVar("sf_editor_syntaxcolor_" .. k, v.r .. "_" .. v.g .. "_" .. v.b, true, false)
end

function Editor:LoadSyntaxColors()
  for k, v in pairs(colors_convars) do
    local r, g, b = v:GetString():match("(%d+)_(%d+)_(%d+)")
    local def = colors_defaults[k]
    colors[k] = Color(tonumber(r) or def.r, tonumber(g) or def.g, tonumber(b) or def.b)
  end

  for i = 1, self:GetNumTabs() do
    self:GetEditor(i):SetSyntaxColors(colors)
  end
end

function Editor:SetSyntaxColor(colorname, colr)
  if not colors[colorname] then return end
  colors[colorname] = colr
  RunConsoleCommand("sf_editor_syntaxcolor_" .. colorname, colr.r .. "_" .. colr.g .. "_" .. colr.b)

  for i = 1, self:GetNumTabs() do
    self:GetEditor(i):SetSyntaxColor(colorname, colr)
  end
end

------------------------------------------------------------------------

local invalid_filename_chars = {
  ["*"] = "",
  ["?"] = "",
  [">"] = "",
  ["<"] = "",
  ["|"] = "",
  ["\\"] = "",
  ['"'] = "",
  [" "] = "_",
}

-- overwritten commands
function Editor:Init()
  -- don't use any of the default DFrame UI components
  for _, v in pairs(self:GetChildren()) do v:Remove() end
  self.Title = ""
  self.subTitle = ""
  self.LastClick = 0
  self.GuiClick = 0
  self.SimpleGUI = false
  self.Location = ""

  self.C = {}
  self.Components = {}

  -- Load border colors, position, & size
  self:LoadEditorSettings()

  local fontTable = {
    font = "default",
    size = 11,
    weight = 300,
    antialias = false,
    additive = false,
  }
  surface.CreateFont("E2SmallFont", fontTable)
  self.logo = surface.GetTextureID("radon/starfall2")

  self:InitComponents()
  self:LoadSyntaxColors()

  -- This turns off the engine drawing
  self:SetPaintBackgroundEnabled(false)
  self:SetPaintBorderEnabled(false)

  self:SetV(false)

  self:InitShutdownHook()
end

local size = CreateClientConVar("wire_expression2_editor_size", "800_600", true, false)
local pos = CreateClientConVar("wire_expression2_editor_pos", "-1_-1", true, false)

function Editor:LoadEditorSettings()

  -- Position & Size
  local w, h = size:GetString():match("(%d+)_(%d+)")
  w = tonumber(w)
  h = tonumber(h)

  self:SetSize(w, h)

  local x, y = pos:GetString():match("(%-?%d+)_(%-?%d+)")
  x = tonumber(x)
  y = tonumber(y)

  if x == -1 and y == -1 then
    self:Center()
  else
    self:SetPos(x, y)
  end

  if x < 0 or y < 0 or x + w > ScrW() or y + h > ScrH() then -- If the editor is outside the screen, reset it
    local width, height = math.min(surface.ScreenWidth() - 200, 800), math.min(surface.ScreenHeight() - 200, 620)
    self:SetPos((surface.ScreenWidth() - width) / 2, (surface.ScreenHeight() - height) / 2)
    self:SetSize(width, height)

    self:SaveEditorSettings()
  end
end

function Editor:SaveEditorSettings()

  -- Position & Size
  local w, h = self:GetSize()
  RunConsoleCommand("wire_expression2_editor_size", w .. "_" .. h)

  local x, y = self:GetPos()
  RunConsoleCommand("wire_expression2_editor_pos", x .. "_" .. y)
end
function Editor:Paint(w,h)
  draw.RoundedBox( 0, 0, 0, w, h, SF.Editor.colors.dark )
end
function Editor:PaintOver()
  local w, h = self:GetSize()

  surface.SetFont("SFEditorDefault")
  surface.SetTextColor(255, 255, 255, 255)
  surface.SetTextPos(10, 6)
  surface.DrawText(self.Title .. self.subTitle)

--  surface.SetTexture(self.logo)
--  surface.SetDrawColor( 255, 255, 255, 128 )
--  surface.DrawTexturedRect( w-148, h-158, 128, 128)

  surface.SetDrawColor(255, 255, 255, 255)
  surface.SetTextPos(0, 0)
  surface.SetFont("Default")
  return true
end

function Editor:PerformLayout()
  local w, h = self:GetSize()

  for i = 1, #self.Components do
    local c = self.Components[i]
    local c_x, c_y, c_w, c_h = c.Bounds.x, c.Bounds.y, c.Bounds.w, c.Bounds.h
    if (c_x < 0) then c_x = w + c_x end
    if (c_y < 0) then c_y = h + c_y end
    if (c_w < 0) then c_w = w + c_w - c_x end
    if (c_h < 0) then c_h = h + c_h - c_y end
    c:SetPos(c_x, c_y)
    c:SetSize(c_w, c_h)
  end
end

function Editor:OnMousePressed(mousecode)
  if mousecode ~= 107 then return end -- do nothing if mouseclick is other than left-click
  if not self.pressed then
    self.pressed = true
    self.p_x, self.p_y = self:GetPos()
    self.p_w, self.p_h = self:GetSize()
    self.p_mx = gui.MouseX()
    self.p_my = gui.MouseY()
    self.p_mode = self:getMode()
    if self.p_mode == "drag" then
      if self.GuiClick > CurTime() - 0.2 then
        self:fullscreen()
        self.pressed = false
        self.GuiClick = 0
      else
        self.GuiClick = CurTime()
      end
    end
  end
end

function Editor:OnMouseReleased(mousecode)
  if mousecode ~= 107 then return end -- do nothing if mouseclick is other than left-click
  self.pressed = false
end

function Editor:Think()
  if self.fs then return end
  if self.pressed then
    if not input.IsMouseDown(MOUSE_LEFT) then -- needs this if you let go of the mouse outside the panel
      self.pressed = false
    end
    local movedX = gui.MouseX() - self.p_mx
    local movedY = gui.MouseY() - self.p_my
    if self.p_mode == "drag" then
      local x = self.p_x + movedX
      local y = self.p_y + movedY
      if (x < 10 and x > -10) then x = 0 end
      if (y < 10 and y > -10) then y = 0 end
      if (x + self.p_w < surface.ScreenWidth() + 10 and x + self.p_w > surface.ScreenWidth() - 10) then x = surface.ScreenWidth() - self.p_w end
      if (y + self.p_h < surface.ScreenHeight() + 10 and y + self.p_h > surface.ScreenHeight() - 10) then y = surface.ScreenHeight() - self.p_h end
      self:SetPos(x, y)
    end
    if self.p_mode == "sizeBR" then
      local w = self.p_w + movedX
      local h = self.p_h + movedY
      if (self.p_x + w < surface.ScreenWidth() + 10 and self.p_x + w > surface.ScreenWidth() - 10) then w = surface.ScreenWidth() - self.p_x end
      if (self.p_y + h < surface.ScreenHeight() + 10 and self.p_y + h > surface.ScreenHeight() - 10) then h = surface.ScreenHeight() - self.p_y end
      if (w < 300) then w = 300 end
      if (h < 200) then h = 200 end
      self:SetSize(w, h)
    end
    if self.p_mode == "sizeR" then
      local w = self.p_w + movedX
      if (w < 300) then w = 300 end
      self:SetWide(w)
    end
    if self.p_mode == "sizeB" then
      local h = self.p_h + movedY
      if (h < 200) then h = 200 end
      self:SetTall(h)
    end
  end
  if not self.pressed then
    local cursor = "arrow"
    local mode = self:getMode()
    if (mode == "sizeBR") then cursor = "sizenwse"
    elseif (mode == "sizeR") then cursor = "sizewe"
    elseif (mode == "sizeB") then cursor = "sizens"
    end
    if cursor ~= self.cursor then
      self.cursor = cursor
      self:SetCursor(self.cursor)
    end
  end

  local x, y = self:GetPos()
  local w, h = self:GetSize()

  if w < 518 then w = 518 end
  if h < 200 then h = 200 end
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  if x + w > surface.ScreenWidth() then x = surface.ScreenWidth() - w end
  if y + h > surface.ScreenHeight() then y = surface.ScreenHeight() - h end
  if y < 0 then y = 0 end
  if x < 0 then x = 0 end
  if w > surface.ScreenWidth() then w = surface.ScreenWidth() end
  if h > surface.ScreenHeight() then h = surface.ScreenHeight() end

  self:SetPos(x, y)
  self:SetSize(w, h)
end

-- special functions

function Editor:fullscreen()
  if self.fs then
    self:SetPos(self.preX, self.preY)
    self:SetSize(self.preW, self.preH)
    self.fs = false
  else
    self.preX, self.preY = self:GetPos()
    self.preW, self.preH = self:GetSize()
    self:SetPos(0, 0)
    self:SetSize(surface.ScreenWidth(), surface.ScreenHeight())
    self.fs = true
  end
end

function Editor:getMode()
  local x, y = self:GetPos()
  local w, h = self:GetSize()
  local ix = gui.MouseX() - x
  local iy = gui.MouseY() - y

  if (ix < 0 or ix > w or iy < 0 or iy > h) then return end -- if the mouse is outside the box
  if (iy < 22) then
    return "drag"
  end
  if (iy > h - 10) then
    if (ix > w - 20) then return "sizeBR" end
    return "sizeB"
  end
  if (ix > w - 10) then
    if (iy > h - 20) then return "sizeBR" end
    return "sizeR"
  end
end

function Editor:addComponent(panel, x, y, w, h)
  assert(not panel.Bounds)
  panel.Bounds = { x = x, y = y, w = w, h = h }
  self.Components[#self.Components + 1] = panel
  return panel
end

-- TODO: Fix this function
local function extractNameFromCode(str)
  return str:match("@name ([^\r\n]+)")
end

local function getPreferredTitles(Line, code)
  local title
  local tabtext

  local str = Line
  if str and str ~= "" then
    title = str
    tabtext = str
  end

  local str = extractNameFromCode(code)
  if str and str ~= "" then
    if not title then
      title = str
    end
    tabtext = str
  end

  return title, tabtext
end

function Editor:GetLastTab() return self.LastTab end

function Editor:SetLastTab(Tab) self.LastTab = Tab end

function Editor:GetActiveTab() return self.C.TabHolder:GetActiveTab() end

function Editor:GetNumTabs() return #self.C.TabHolder.Items end

function Editor:SetActiveTab(val)
  if self:GetActiveTab() == val then
    val:GetPanel():RequestFocus()
    return
  end
  self:SetLastTab(self:GetActiveTab())
  if isnumber(val) then
    self.C.TabHolder:SetActiveTab(self.C.TabHolder.Items[val].Tab)
    self:GetCurrentEditor():RequestFocus()
  elseif val and val:IsValid() then
    self.C.TabHolder:SetActiveTab(val)
    val:GetPanel():RequestFocus()
  end
  if self.E2 then self:Validate() end

  -- Editor subtitle and tab text
  local title, tabtext = getPreferredTitles(self:GetChosenFile(), self:GetCode())

  if title then self:SubTitle("Editing: " .. title) else self:SubTitle() end
  if tabtext then
    if self:GetActiveTab():GetText() ~= tabtext then
      self:GetActiveTab():SetText(tabtext)
      self.C.TabHolder.tabScroller:InvalidateLayout()
    end
  end
end

function Editor:GetActiveTabIndex()
  local tab = self:GetActiveTab()
  for k, v in pairs(self.C.TabHolder.Items) do
    if tab == v.Tab then
      return k
    end
  end
  return -1
end

function Editor:SetActiveTabIndex(index)
  local tab = self.C.TabHolder.Items[index].Tab

  if not tab then return end

  self:SetActiveTab(tab)
end

local function extractNameFromFilePath(str)
  local found = str:reverse():find("/", 1, true)
  if found then
    return str:Right(found - 1)
  else
    return str
  end
end

function Editor:SetEditorMode(mode_name)
  self.EditorMode = mode_name
  for i = 1, self:GetNumTabs() do
    self:GetEditor(i):SetMode(mode_name)
  end
end

function Editor:GetEditorMode() return self.EditorMode end

local old
function Editor:FixTabFadeTime()
  if old ~= nil then return end -- It's already being fixed
  local old = self.C.TabHolder:GetFadeTime()
  self.C.TabHolder:SetFadeTime(0)
  timer.Simple(old, function() self.C.TabHolder:SetFadeTime(old) old = nil end)
end

function Editor:CreateTab(chosenfile)
  local editor = vgui.Create("Expression2Editor")
  editor.parentpanel = self

  local sheet = self.C.TabHolder:AddSheet(extractNameFromFilePath(chosenfile), editor)
  self:SetEditorFont(editor)
  editor.chosenfile = chosenfile
  sheet.Tab.Paint = function(button,w,h)

    if button.Hovered then
      draw.RoundedBox( 0, 0, 0, w-1, h, button.backgroundHoverCol or SF.Editor.colors.med )
    else
      draw.RoundedBox( 0, 0, 0, w-1, h, button.backgroundCol or SF.Editor.colors.meddark )
    end
  end
  sheet.Tab.OnMousePressed = function(pnl, keycode, ...)

    if keycode == MOUSE_MIDDLE then
      --self:FixTabFadeTime()
      self:CloseTab(pnl)
      return
    elseif keycode == MOUSE_RIGHT then
      local menu = DermaMenu()
      menu:AddOption("Close", function()
          --self:FixTabFadeTime()
          self:CloseTab(pnl)
        end)
      menu:AddOption("Close all others", function()
          self:FixTabFadeTime()
          self:SetActiveTab(pnl)
          for i = self:GetNumTabs(), 1, -1 do
            if self.C.TabHolder.Items[i] ~= sheet then
              self:CloseTab(i)
            end
          end
        end)
      menu:AddSpacer()
      menu:AddOption("Save", function()
          self:FixTabFadeTime()
          local old = self:GetLastTab()
          self:SetActiveTab(pnl)
          self:SaveFile(self:GetChosenFile(), true)
          self:SetActiveTab(self:GetLastTab())
          self:SetLastTab(old)
        end)
      menu:AddOption("Save As", function()
          self:FixTabFadeTime()
          local old = self:GetLastTab()
          self:SetActiveTab(pnl)
          self:SaveFile(self:GetChosenFile(), false, true)
          self:SetActiveTab(self:GetLastTab())
          self:SetLastTab(old)
        end)
      menu:AddOption("Reload", function()
          self:FixTabFadeTime()
          local old = self:GetLastTab()
          self:SetActiveTab(pnl)
          self:LoadFile(editor.chosenfile, false)
          self:SetActiveTab(self:GetLastTab())
          self:SetLastTab(old)
        end)
      menu:AddSpacer()
      menu:AddOption("Copy file path to clipboard", function()
          if editor.chosenfile and editor.chosenfile ~= "" then
            SetClipboardText(editor.chosenfile)
          end
        end)
      menu:AddOption("Copy all file paths to clipboard", function()
          local str = ""
          for i = 1, self:GetNumTabs() do
            local chosenfile = self:GetEditor(i).chosenfile
            if chosenfile and chosenfile ~= "" then
              str = str .. chosenfile .. ";"
            end
          end
          str = str:sub(1, -2)
          SetClipboardText(str)
        end)
      menu:Open()
      return
    end

    self:SetActiveTab(pnl)
  end

  editor.OnTextChanged = function(panel)
    timer.Create("e2autosave", 5, 1, function()
        self:AutoSave()
      end)
  end
  editor.OnShortcut = function(_, code)
    if code == KEY_S then
      self:SaveFile(self:GetChosenFile())
      if self.E2 then self:Validate() end
    else
      local mode = GetConVar("wire_expression2_autocomplete_controlstyle"):GetInt()
      local enabled = GetConVar("wire_expression2_autocomplete"):GetBool()
      if mode == 1 and enabled then
        if code == KEY_B then
          self:Validate(true)
        elseif code == KEY_SPACE then
          local ed = self:GetCurrentEditor()
          if (ed.AC_Panel and ed.AC_Panel:IsVisible()) then
            ed:AC_Use(ed.AC_Suggestions[1])
          end
        end
      elseif code == KEY_SPACE then
        self:Validate(true)
      end
    end
  end
  editor:RequestFocus()

  editor:SetMode(self:GetEditorMode())

  self:OnTabCreated(sheet) -- Call a function that you can override to do custom stuff to each tab.

  return sheet
end

function Editor:OnTabCreated(sheet) end

-- This function is made to be overwritten

function Editor:GetNextAvailableTab()
  local activetab = self:GetActiveTab()
  for k, v in pairs(self.C.TabHolder.Items) do
    if v.Tab and v.Tab:IsValid() and v.Tab ~= activetab then
      return v.Tab
    end
  end
end

function Editor:NewTab()
  local sheet = self:CreateTab("generic")
  self:SetActiveTab(sheet.Tab)
  if self.E2 then
    self:NewScript(true)
  end
end

function Editor:CloseTab(_tab)
  local activetab, sheetindex
  if _tab then
    if isnumber(_tab) then
      local temp = self.C.TabHolder.Items[_tab]
      if temp then
        activetab = temp.Tab
        sheetindex = _tab
      else
        return
      end
    else
      activetab = _tab
      -- Find the sheet index
      for k, v in pairs(self.C.TabHolder.Items) do
        if activetab == v.Tab then
          sheetindex = k
          break
        end
      end
    end
  else
    activetab = self:GetActiveTab()
    -- Find the sheet index
    for k, v in pairs(self.C.TabHolder.Items) do
      if activetab == v.Tab then
        sheetindex = k
        break
      end
    end
  end

  self:AutoSave()

  -- There's only one tab open, no need to actually close any tabs
  if self:GetNumTabs() == 1 then
    activetab:SetText("generic")
    self.C.TabHolder:InvalidateLayout()
    self:NewScript(true)
    return
  end

  -- Find the panel (for the scroller)
  local tabscroller_sheetindex
  for k, v in pairs(self.C.TabHolder.tabScroller.Panels) do
    if v == activetab then
      tabscroller_sheetindex = k
      break
    end
  end

  self:FixTabFadeTime()

  if activetab == self:GetActiveTab() then -- We're about to close the current tab
    if self:GetLastTab() and self:GetLastTab():IsValid() then -- If the previous tab was saved
      if activetab == self:GetLastTab() then -- If the previous tab is equal to the current tab
        local othertab = self:GetNextAvailableTab() -- Find another tab
        if othertab and othertab:IsValid() then -- If that other tab is valid, use it
          self:SetActiveTab(othertab)
          self:SetLastTab()
        else -- Reset the current tab (backup)
          self:GetActiveTab():SetText("generic")
          self.C.TabHolder:InvalidateLayout()
          self:NewScript(true)
          return
        end
      else -- Change to the previous tab
        self:SetActiveTab(self:GetLastTab())
        self:SetLastTab()
      end
    else -- If the previous tab wasn't saved
      local othertab = self:GetNextAvailableTab() -- Find another tab
      if othertab and othertab:IsValid() then -- If that other tab is valid, use it
        self:SetActiveTab(othertab)
      else -- Reset the current tab (backup)
        self:GetActiveTab():SetText("generic")
        self.C.TabHolder:InvalidateLayout()
        self:NewScript(true)
        return
      end
    end
  end

  self:OnTabClosed(activetab) -- Call a function that you can override to do custom stuff to each tab.

  activetab:GetPanel():Remove()
  activetab:Remove()
  table.remove(self.C.TabHolder.Items, sheetindex)
  table.remove(self.C.TabHolder.tabScroller.Panels, tabscroller_sheetindex)

  self.C.TabHolder.tabScroller:InvalidateLayout()
  local w, h = self.C.TabHolder:GetSize()
  self.C.TabHolder:SetSize(w + 1, h) -- +1 so it updates
end

function Editor:OnTabClosed(sheet) end

-- This function is made to be overwritten

-- initialization commands
function Editor:InitComponents()
  self.Components = {}
  self.C = {}

  local function PaintFlatButton(panel, w, h)
    if not (panel:IsHovered() or panel:IsDown()) then return end
    derma.SkinHook("Paint", "Button", panel, w, h)
  end

  local DMenuButton = vgui.RegisterTable({
      Init = function(panel)
        panel:SetText("")
        panel:SetSize(24, 20)
        panel:Dock(LEFT)
      end,
      Paint = PaintFlatButton,
      DoClick = function(panel)
        local name = panel:GetName()
        local f = name and name ~= "" and self[name] or nil
        if f then f(self) end
      end
    }, "DButton")

	self.C.ButtonHolder = self:addComponent(vgui.Create("DPanel", self), -430-4, 4, 430, 22) -- Upper menu
	self.C.ButtonHolder.Paint = function() end
  -- addComponent( panel, x, y, w, h )
  -- if x, y, w, h is minus, it will stay relative to right or buttom border
  self.C.Close = vgui.Create("StarfallButton", self.C.ButtonHolder) -- Close button
  -- self.C.Inf = self:addComponent(vgui.CreateFromTable(DMenuButton, self), -45-4-26, 0, 24, 22) -- Info button
  -- self.C.ConBut = self:addComponent(vgui.CreateFromTable(DMenuButton, self), -45-4-24-26, 0, 24, 22) -- Control panel open/close

  self.C.Divider = vgui.Create("DHorizontalDivider", self)

  self.C.Browser = vgui.Create("wire_expression2_browser", self.C.Divider) -- Expression browser

  self.C.MainPane = vgui.Create("DPanel", self.C.Divider)
  self.C.Menu = vgui.Create("DPanel", self.C.MainPane)
  self.C.Val = vgui.Create("Button", self.C.MainPane) -- Validation line
  self.C.TabHolder = vgui.Create("DPropertySheet", self.C.MainPane)

  self.C.Btoggle = vgui.CreateFromTable(DMenuButton, self.C.Menu) -- Toggle Browser being shown
  self.C.Sav = vgui.CreateFromTable(DMenuButton, self.C.Menu) -- Save button
  self.C.NewTab = vgui.CreateFromTable(DMenuButton, self.C.Menu, "NewTab") -- New tab button
  self.C.CloseTab = vgui.CreateFromTable(DMenuButton, self.C.Menu, "CloseTab") -- Close tab button
  self.C.Reload = vgui.CreateFromTable(DMenuButton, self.C.Menu) -- Reload tab button

  self.C.SaE = vgui.Create("StarfallButton", self.C.ButtonHolder) -- Save & Exit button
  self.C.SavAs = vgui.Create("StarfallButton", self.C.ButtonHolder) -- Save As button

	self.C.Inf = vgui.CreateFromTable(DMenuButton, self.C.Menu) -- Info button
  self.C.ConBut = vgui.CreateFromTable(DMenuButton, self.C.Menu) -- Control panel button


  self.C.Control = self:addComponent(vgui.Create("Panel", self), -350, 52, 342, -32) -- Control Panel
  self.C.Credit = self:addComponent(vgui.Create("DTextEntry", self), -160, 52, 150, 150) -- Credit box

  self:CreateTab("generic")

  -- extra component options

  self.C.Divider:SetLeft(self.C.Browser)
  self.C.Divider:SetRight(self.C.MainPane)
  self.C.Divider:Dock(FILL)
  self.C.Divider:SetDividerWidth(4)
  self.C.Divider:SetCookieName("wire_expression2_editor_divider")
  self.C.Divider:SetLeftMin(0)

  local DoNothing = function() end
  self.C.MainPane.Paint = DoNothing
  --self.C.Menu.Paint = DoNothing

  self.C.Menu:Dock(TOP)
  self.C.TabHolder:Dock(FILL)
	self.C.TabHolder.tabScroller:DockMargin( 0, 0, 3, 0 ) -- We dont want default offset
	self.C.TabHolder:SetPadding(0)
	self.C.Menu.Paint = function(_, w, h)
		draw.RoundedBox( 0, 0, 0, w, h, Color(234, 234, 234) ) 
	end

  self.C.Val:Dock(BOTTOM)

  self.C.Menu:SetHeight(24)
  self.C.Menu:DockPadding(2,2,2,2)
  self.C.Val:SetHeight(22)

  self.C.SaE:SetSize(80, 20)
	self.C.SaE:DockMargin(2, 0, 0, 0)	
  self.C.SaE:Dock(RIGHT)
  
	self.C.SavAs:SetSize(51, 20)
	self.C.SavAs:DockMargin(2, 0, 0, 0)	
  self.C.SavAs:Dock(RIGHT)

  self.C.Close:SetText("Close")
	self.C.Close:DockMargin(10, 0, 0, 0)
	self.C.Close:Dock(RIGHT)
  self.C.Close.DoClick = function(btn) self:Close() end

  self.C.ConBut:SetImage("icon16/wrench.png")
  self.C.ConBut:Dock(RIGHT)
  self.C.ConBut:SetText("")
  self.C.ConBut.Paint = PaintFlatButton
  self.C.ConBut.DoClick = function() self.C.Control:SetVisible(not self.C.Control:IsVisible()) end

  self.C.Inf:SetImage("icon16/information.png")
  self.C.Inf:Dock(RIGHT)
  self.C.Inf.Paint = PaintFlatButton
  self.C.Inf.DoClick = function(btn)
    self.C.Credit:SetVisible(not self.C.Credit:IsVisible())
  end

  self.C.Sav:SetImage("icon16/disk.png")
  self.C.Sav.DoClick = function(button) self:SaveFile(self:GetChosenFile()) end
  self.C.Sav:SetToolTip( "Save" )

  self.C.NewTab:SetImage("icon16/page_white_add.png")
  self.C.NewTab.DoClick = function(button) self:NewTab() end
  self.C.NewTab:SetToolTip( "New tab" )

  self.C.CloseTab:SetImage("icon16/page_white_delete.png")
  self.C.CloseTab.DoClick = function(button) self:CloseTab() end
  self.C.CloseTab:SetToolTip( "Close tab" )

  self.C.Reload:SetImage("icon16/page_refresh.png")
  self.C.Reload:SetToolTip( "Refresh file" )
  self.C.Reload.DoClick = function(button)
    self:LoadFile(self:GetChosenFile(), false)
  end

  self.C.SaE:SetText("Save and Exit")
  self.C.SaE.DoClick = function(button) self:SaveFile(self:GetChosenFile(), true) end

  self.C.SavAs:SetText("Save As")
  self.C.SavAs.DoClick = function(button) self:SaveFile(self:GetChosenFile(), false, true) end

  self.C.Browser:AddRightClick(self.C.Browser.filemenu, 4, "Save to", function()
      Derma_Query("Overwrite this file?", "Save To",
        "Overwrite", function()
          self:SaveFile(self.C.Browser.File.FileDir)
        end,
      "Cancel")
    end)
  self.C.Browser.OnFileOpen = function(_, filepath, newtab)
    self:Open(filepath, nil, newtab)
  end
	self.C.Browser.Folders.Paint = function(_, w, h) --Fix for offset
		draw.RoundedBox( 0, 1, 0, w-2, h, Color(255, 255, 255) ) 
	end

  self.C.Val:SetText(" Click to validate...")
  self.C.Val.UpdateColours = function(button, skin)
    return button:SetTextStyleColor(skin.Colours.Button.Down)
  end
  self.C.Val.SetBGColor = function(button, r, g, b, a)
    self.C.Val.bgcolor = Color(r, g, b, a)
  end
  self.C.Val.bgcolor = Color(255, 255, 255)
  self.C.Val.Paint = function(button)
    local w, h = button:GetSize()
    draw.RoundedBox(1, 0, 0, w, h, button.bgcolor)
    if button.Hovered then draw.RoundedBox(0, 1, 1, w - 2, h - 2, Color(0, 0, 0, 128)) end
  end
  self.C.Val.OnMousePressed = function(panel, btn)
    if btn == MOUSE_RIGHT then
      local menu = DermaMenu()
      menu:AddOption("Copy to clipboard", function()
          SetClipboardText(self.C.Val:GetValue():sub(4))
        end)
      menu:Open()
    else
      self:Validate(true)
    end
  end
  self.C.Btoggle:SetImage("icon16/application_side_contract.png")
  function self.C.Btoggle.DoClick(button)
    if button.hide then
      self.C.Divider:LoadCookies()
    else
      self.C.Divider:SetLeftWidth(0)
    end
    self.C.Divider:InvalidateLayout()
    button:InvalidateLayout()
  end

  local oldBtoggleLayout = self.C.Btoggle.PerformLayout
  function self.C.Btoggle.PerformLayout(button)
    oldBtoggleLayout(button)
    if self.C.Divider:GetLeftWidth() > 0 then
      button.hide = false
      button:SetImage("icon16/application_side_contract.png")
    else
      button.hide = true
      button:SetImage("icon16/application_side_expand.png")
    end
  end

  self.C.Credit:SetTextColor(Color(0, 0, 0, 255))
  self.C.Credit:SetText("\t\tCREDITS\n\n\tEditor by: \tSyranide and Shandolum\n\n\tTabs (and more) added by Divran.\n\n\tFixed for GMod13 By Ninja101") -- Sure why not ;)
  self.C.Credit:SetMultiline(true)
  self.C.Credit:SetVisible(false)

  self:InitControlPanel(self.C.Control) -- making it seperate for better overview
  self.C.Control:SetVisible(false)
  if self.E2 then self:Validate() end
end

function Editor:AutoSave()
  local buffer = self:GetCode()
  if self.savebuffer == buffer or buffer == defaultCode or buffer == "" then return end
  self.savebuffer = buffer
  file.Write(self.Location .. "/_autosave_.txt", buffer)
end

function Editor:AddControlPanelTab(label, icon, tooltip)
  local frame = self.C.Control
  local panel = vgui.Create("DPanel")
  local ret = frame.TabHolder:AddSheet(label, panel, icon, false, false, tooltip)
  local old = ret.Tab.OnMousePressed
  function ret.Tab.OnMousePressed(...)
    timer.Simple(0.1,function() frame:ResizeAll() end) -- timers solve everything
    old(...)
  end

  ret.Panel:SetBackgroundColor(Color(96, 96, 96, 255))

  return ret
end

function Editor:InitControlPanel(frame)
  local C = self.C.Control

  -- Add a property sheet to hold the tabs
  local tabholder = vgui.Create("DPropertySheet", frame)
  tabholder:SetPos(2, 4)
  frame.TabHolder = tabholder

  -- They need to be resized one at a time... dirty fix incoming (If you know of a nicer way to do this, don't hesitate to fix it.)
  local function callNext(t, n)
    local obj = t[n]
    local pnl = obj[1]
    if pnl and pnl:IsValid() then
      local x, y = obj[2], obj[3]
      pnl:SetPos(x, y)
      local w, h = pnl:GetParent():GetSize()
      local wofs, hofs = w - x * 2, h - y * 2
      pnl:SetSize(wofs, hofs)
    end
    n = n + 1
    if n <= #t then
      timer.Simple(0, function() callNext(t, n) end)
    end
  end

  function frame:ResizeAll()
    timer.Simple(0, function()
        callNext(self.ResizeObjects, 1)
      end)
  end

  -- Resize them at the right times
  local old = frame.SetSize
  function frame:SetSize(...)
    self:ResizeAll()
    old(self, ...)
  end

  local old = frame.SetVisible
  function frame:SetVisible(...)
    self:ResizeAll()
    old(self, ...)
  end

  -- Function to add more objects to resize automatically
  frame.ResizeObjects = {}
  function frame:AddResizeObject(...)
    self.ResizeObjects[#self.ResizeObjects + 1] = { ... }
  end

  -- Our first object to auto resize is the tabholder. This sets it to position 2,4 and with a width and height offset of w-4, h-8.
  frame:AddResizeObject(tabholder, 2, 4)

  -- ------------------------------------------- EDITOR TAB
  local sheet = self:AddControlPanelTab("Editor", "icon16/wrench.png", "Options for the editor itself.")

  -- WINDOW BORDER COLORS

  local dlist = vgui.Create("DPanelList", sheet.Panel)
  dlist.Paint = function() end
  frame:AddResizeObject(dlist, 4, 4)
  dlist:EnableVerticalScrollbar(true)

  -- Color Mixer PANEL - Houses label, combobox, mixer, reset button & reset all button.
  local mixPanel = vgui.Create( "panel" )
  mixPanel:SetTall( 240 )
  dlist:AddItem( mixPanel )

  do
    -- Label
    local label = vgui.Create( "DLabel", mixPanel )
    label:Dock( TOP )
    label:SetText( "Syntax Colors" )
    label:SizeToContents()

    -- Dropdown box of convars to change ( affects editor colors )
    local box = vgui.Create( "DComboBox", mixPanel )
    box:Dock( TOP )
    box:SetValue( "Color feature" )
    local active = nil

    -- Mixer
    local mixer = vgui.Create( "DColorMixer", mixPanel )
    mixer:Dock( FILL )
    mixer:SetPalette( true )
    mixer:SetAlphaBar( true )
    mixer:SetWangs( true )
    mixer.ValueChanged = function ( _, clr )
      self:SetSyntaxColor( active, clr )
    end

    for k, _ in pairs( colors_convars ) do
      box:AddChoice( k )
    end

    box.OnSelect = function ( self, index, value, data )
      -- DComboBox doesn't have a method for getting active value ( to my knowledge )
      -- Therefore, cache it, we're in a local scope so we're fine.
      active = value
      mixer:SetColor( colors[ active ] or Color( 255, 255, 255 ) )
    end

    -- Reset ALL button
    local rAll = vgui.Create( "DButton", mixPanel )
    rAll:Dock( BOTTOM )
    rAll:SetText( "Reset ALL to Default" )

    rAll.DoClick = function ()
      for k, v in pairs( colors_defaults ) do
        self:SetSyntaxColor( k, v )
      end
      mixer:SetColor( colors_defaults[ active ] )
    end

    -- Reset to default button
    local reset = vgui.Create( "DButton", mixPanel )
    reset:Dock( BOTTOM )
    reset:SetText( "Set to Default" )

    reset.DoClick = function ()
      self:SetSyntaxColor( active, colors_defaults[ active ] )
      mixer:SetColor( colors_defaults[ active ] )
    end

    -- Select a convar to be displayed automatically
    box:ChooseOptionID( 1 )
  end

  --- - FONTS

  local FontLabel = vgui.Create("DLabel")
  dlist:AddItem(FontLabel)
  FontLabel:SetText("Font: Font Size:")
  FontLabel:SizeToContents()
  FontLabel:SetPos(10, 0)

  local temp = vgui.Create("Panel")
  temp:SetTall(25)
  dlist:AddItem(temp)

  local FontSelect = vgui.Create("DComboBox", temp)
  -- dlist:AddItem( FontSelect )
  FontSelect.OnSelect = function(panel, index, value)
    if value == "Custom..." then
      Derma_StringRequestNoBlur("Enter custom font:", "", "", function(value)
          self:ChangeFont(value, self.FontSizeConVar:GetInt())
          RunConsoleCommand("wire_expression2_editor_font", value)
        end)
    else
      value = value:gsub(" %b()", "") -- Remove description
      self:ChangeFont(value, self.FontSizeConVar:GetInt())
      RunConsoleCommand("wire_expression2_editor_font", value)
    end
  end
  for k, v in pairs(self.Fonts) do
    FontSelect:AddChoice(k .. (v ~= "" and " (" .. v .. ")" or ""))
  end
  FontSelect:AddChoice("Custom...")
  FontSelect:SetSize(240 - 50 - 4, 20)

  local FontSizeSelect = vgui.Create("DComboBox", temp)
  FontSizeSelect.OnSelect = function(panel, index, value)
    value = value:gsub(" %b()", "")
    self:ChangeFont(self.FontConVar:GetString(), tonumber(value))
    RunConsoleCommand("wire_expression2_editor_font_size", value)
  end
  for i = 11, 26 do
    FontSizeSelect:AddChoice(i .. (i == 16 and " (Default)" or ""))
  end
  FontSizeSelect:SetPos(FontSelect:GetWide() + 4, 0)
  FontSizeSelect:SetSize(50, 20)

  local label = vgui.Create("DLabel")
  dlist:AddItem(label)
  label:SetText("Auto completion options")
  label:SizeToContents()

  local AutoComplete = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(AutoComplete)
  AutoComplete:SetConVar("wire_expression2_autocomplete")
  AutoComplete:SetText("Auto Completion")
  AutoComplete:SizeToContents()
  AutoComplete:SetTooltip("Enable/disable auto completion in the E2 editor.")

  local AutoCompleteExtra = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(AutoCompleteExtra)
  AutoCompleteExtra:SetConVar("wire_expression2_autocomplete_moreinfo")
  AutoCompleteExtra:SetText("More Info (for AC)")
  AutoCompleteExtra:SizeToContents()
  AutoCompleteExtra:SetTooltip("Enable/disable additional information for auto completion.")

  local label = vgui.Create("DLabel")
  dlist:AddItem(label)
  label:SetText("Auto completion control style")
  label:SizeToContents()

  local AutoCompleteControlOptions = vgui.Create("DComboBox")
  dlist:AddItem(AutoCompleteControlOptions)

  local modes = {}
  modes["Default"] = { 0, "Current mode:\nTab/CTRL+Tab to choose item;\nEnter/Space to use;\nArrow keys to abort." }
  modes["Visual C# Style"] = { 1, "Current mode:\nCtrl+Space to use the top match;\nArrow keys to choose item;\nTab/Enter/Space to use;\nCode validation hotkey (ctrl+space) moved to ctrl+b." }
  modes["Scroller"] = { 2, "Current mode:\nMouse scroller to choose item;\nMiddle mouse to use." }
  modes["Scroller w/ Enter"] = { 3, "Current mode:\nMouse scroller to choose item;\nEnter to use." }
  modes["Eclipse Style"] = { 4, "Current mode:\nEnter to use top match;\nTab to enter auto completion menu;\nArrow keys to choose item;\nEnter to use;\nSpace to abort." }
  -- modes["Qt Creator Style"] = { 6, "Current mode:\nCtrl+Space to enter auto completion menu;\nSpace to abort; Enter to use top match." } <-- probably wrong. I'll check about adding Qt style later.

  for k, v in pairs(modes) do
    AutoCompleteControlOptions:AddChoice(k)
  end

  modes[0] = modes["Default"][2]
  modes[1] = modes["Visual C# Style"][2]
  modes[2] = modes["Scroller"][2]
  modes[3] = modes["Scroller w/ Enter"][2]
  modes[4] = modes["Eclipse Style"][2]
  AutoCompleteControlOptions:SetToolTip(modes[GetConVar("wire_expression2_autocomplete_controlstyle"):GetInt()])

  AutoCompleteControlOptions.OnSelect = function(panel, index, value)
    panel:SetToolTip(modes[value][2])
    RunConsoleCommand("wire_expression2_autocomplete_controlstyle", modes[value][1])
  end

  local HighightOnUse = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(HighightOnUse)
  HighightOnUse:SetConVar("wire_expression2_autocomplete_highlight_after_use")
  HighightOnUse:SetText("Highlight word after AC use.")
  HighightOnUse:SizeToContents()
  HighightOnUse:SetTooltip("Enable/Disable highlighting of the entire word after using auto completion.\nIn E2, this is only for variables/constants, not functions.")

  local label = vgui.Create("DLabel")
  dlist:AddItem(label)
  label:SetText("Other options")
  label:SizeToContents()

  local NewTabOnOpen = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(NewTabOnOpen)
  NewTabOnOpen:SetConVar("wire_expression2_new_tab_on_open")
  NewTabOnOpen:SetText("New tab on open")
  NewTabOnOpen:SizeToContents()
  NewTabOnOpen:SetTooltip("Enable/disable loaded files opening in a new tab.\nIf disabled, loaded files will be opened in the current tab.")

  local SaveTabsOnClose = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(SaveTabsOnClose)
  SaveTabsOnClose:SetConVar("wire_expression2_editor_savetabs")
  SaveTabsOnClose:SetText("Save tabs on close")
  SaveTabsOnClose:SizeToContents()
  SaveTabsOnClose:SetTooltip("Save the currently opened tab file paths on shutdown.\nOnly saves tabs whose files are saved.")

  local OpenOldTabs = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(OpenOldTabs)
  OpenOldTabs:SetConVar("wire_expression2_editor_openoldtabs")
  OpenOldTabs:SetText("Open old tabs on load")
  OpenOldTabs:SizeToContents()
  OpenOldTabs:SetTooltip("Open the tabs from the last session on load.\nOnly tabs whose files were saved before disconnecting from the server are stored.")

  local DisplayCaretPos = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(DisplayCaretPos)
  DisplayCaretPos:SetConVar("wire_expression2_editor_display_caret_pos")
  DisplayCaretPos:SetText("Show Caret Position")
  DisplayCaretPos:SizeToContents()
  DisplayCaretPos:SetTooltip("Shows the position of the caret.")

  local HighlightOnDoubleClick = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(HighlightOnDoubleClick)
  HighlightOnDoubleClick:SetConVar("wire_expression2_editor_highlight_on_double_click")
  HighlightOnDoubleClick:SetText("Highlight copies of selected word")
  HighlightOnDoubleClick:SizeToContents()
  HighlightOnDoubleClick:SetTooltip("Find all identical words and highlight them after a double-click.")

  local WorldClicker = vgui.Create("DCheckBoxLabel")
  dlist:AddItem(WorldClicker)
  WorldClicker:SetConVar("wire_expression2_editor_worldclicker")
  WorldClicker:SetText("Enable Clicking Outside Editor")
  WorldClicker:SizeToContents()
  function WorldClicker.OnChange(pnl, bVal)
    self:GetParent():SetWorldClicker(bVal)
  end
end

-- used with color-circles
function Editor:TranslateValues(panel, x, y)
  x = x - 0.5
  y = y - 0.5
  local angle = math.atan2(x, y)
  local length = math.sqrt(x * x + y * y)
  length = math.Clamp(length, 0, 0.5)
  x = 0.5 + math.sin(angle) * length
  y = 0.5 + math.cos(angle) * length
  panel:SetHue(math.deg(angle) + 270)
  panel:SetSaturation(length * 2)
  panel:SetRGB(HSVToColor(panel:GetHue(), panel:GetSaturation(), 1))
  panel:SetFrameColor()
  return x, y
end

local defaultCode = [=[--@name
--@author
--@shared

--[[
Starfall Scripting Environment

Github: https://github.com/thegrb93/StarfallEx
Reference Page: http://thegrb93.github.io/Starfall/

Default Keyboard shortcuts: https://github.com/ajaxorg/ace/wiki/Default-Keyboard-Shortcuts
]]]=]

function Editor:NewScript(incurrent)
  if not incurrent and self.NewTabOnOpen:GetBool() then
    self:NewTab()
  else
    self:AutoSave()
    self:ChosenFile()
    -- Set title
    self:GetActiveTab():SetText("generic")
    self.C.TabHolder:InvalidateLayout()

    self:SetCode(defaultCode)
  end
end

local wire_expression2_editor_savetabs = CreateClientConVar("wire_expression2_editor_savetabs", "1", true, false)

local id = 0
function Editor:InitShutdownHook()
  id = id + 1

  -- save code when shutting down
  hook.Add("ShutDown", "wire_expression2_ShutDown" .. id, function()
      -- if wire_expression2_editor == nil then return end
      local buffer = self:GetCode()
      if buffer == defaultcode then return end
      file.Write(self.Location .. "/_shutdown_.txt", buffer)

      if wire_expression2_editor_savetabs:GetBool() then
        self:SaveTabs()
      end
    end)
end

function Editor:SaveTabs()
  local strtabs = ""
  local tabs = {}
  for i=1, self:GetNumTabs() do
    local chosenfile = self:GetEditor(i).chosenfile
    if chosenfile and chosenfile ~= "" and not tabs[chosenfile] then
      strtabs = strtabs .. chosenfile .. ";"
      tabs[chosenfile] = true -- Prevent duplicates
    end
  end

  strtabs = strtabs:sub(1, -2)

  file.Write(self.Location .. "/_tabs_.txt", strtabs)
end

local wire_expression2_editor_openoldtabs = CreateClientConVar("wire_expression2_editor_openoldtabs", "1", true, false)

function Editor:OpenOldTabs()
  if not file.Exists(self.Location .. "/_tabs_.txt", "DATA") then return end

  -- Read file
  local tabs = file.Read(self.Location .. "/_tabs_.txt")
  if not tabs or tabs == "" then return end

  -- Explode around ;
  tabs = string.Explode(";", tabs)
  if not tabs or #tabs == 0 then return end

  -- Temporarily remove fade time
  self:FixTabFadeTime()

  local is_first = true
  for k, v in pairs(tabs) do
    if v and v ~= "" then
      if (file.Exists(v, "DATA")) then
        -- Open it in a new tab
        self:LoadFile(v, true)

        -- If this is the first loop, close the initial tab.
        if (is_first) then
          timer.Simple(0, function()
              self:CloseTab(1)
            end)
          is_first = false
        end
      end
    end
  end
end

function Editor:Validate(gotoerror)

  local err = CompileString( self:GetCode(), "Validation", false )
  if type( err ) != "string" then
    self:SetValidatorStatus("Validation successful!", 0, 110, 20, 255)
    return
  end
  local row = tonumber( err:match( "%d+" ) ) - 1 or 0
  local message = err:match( ": .+$" ):sub( 3 ) or "Unknown"
  message = "Line "..row..":"..message
  if gotoerror then
    if row then self:GetCurrentEditor():SetCaret({ tonumber(row), 0 }) end
  end
  self.C.Val:SetBGColor(110, 0, 20, 255)
  self.C.Val:SetText(" " .. message)

  return true
end

function Editor:SetValidatorStatus(text, r, g, b, a)
  self.C.Val:SetBGColor(r or 0, g or 180, b or 0, a or 180)
  self.C.Val:SetText(" " .. text)
end

function Editor:SubTitle(sub)
  if not sub then self.subTitle = ""
  else self.subTitle = " - " .. sub
  end
end

local wire_expression2_editor_worldclicker = CreateClientConVar("wire_expression2_editor_worldclicker", "0", true, false)
function Editor:SetV(bool)
  if bool then
    self:MakePopup()
    self:InvalidateLayout(true)
    if self.E2 then self:Validate() end
  end
  self:SetVisible(bool)
  self:SetKeyBoardInputEnabled(bool)
  self:GetParent():SetWorldClicker(wire_expression2_editor_worldclicker:GetBool() and bool) -- Enable this on the background so we can update E2's without closing the editor
  if CanRunConsoleCommand() then
    RunConsoleCommand("wire_expression2_event", bool and "editor_open" or "editor_close")
    if not e2_function_data_received and bool then -- Request the E2 functions
      RunConsoleCommand("wire_expression2_sendfunctions")
    end
  end
end

function Editor:GetChosenFile()
  return self:GetCurrentEditor().chosenfile
end

function Editor:ChosenFile(Line)
  self:GetCurrentEditor().chosenfile = Line
  if Line then
    self:SubTitle("Editing: " .. Line)
  else
    self:SubTitle()
  end
end

function Editor:FindOpenFile(FilePath)
  for i = 1, self:GetNumTabs() do
    local ed = self:GetEditor(i)
    if ed.chosenfile == FilePath then
      return ed
    end
  end
end

function Editor:ExtractName()
  if not self.E2 then self.savefilefn = "filename" return end
  local code = self:GetCode()
  local name = extractNameFromCode(code)
  if name and name ~= "" then
    Expression2SetName(name)
    self.savefilefn = name
  else
    Expression2SetName(nil)
    self.savefilefn = "filename"
  end
end

function Editor:SetCode(code)
  self:GetCurrentEditor():SetText(code)
  self.savebuffer = self:GetCode()
  if self.E2 then self:Validate() end
  self:ExtractName()
end

function Editor:GetEditor(n)
  if self.C.TabHolder.Items[n] then
    return self.C.TabHolder.Items[n].Panel
  end
end

function Editor:GetCurrentEditor()
  return self:GetActiveTab():GetPanel()
end

function Editor:GetCode()
  return self:GetCurrentEditor():GetValue()
end

function Editor:Open(Line, code, forcenewtab)
  if self:IsVisible() and not Line and not code then self:Close() end
  self:SetV(true)
  if self.chip then
    self.C.SaE:SetText("Upload & Exit")
  else
    self.C.SaE:SetText("Save and Exit")
  end
  if code then
    if not forcenewtab then
      for i = 1, self:GetNumTabs() do
        if self:GetEditor(i).chosenfile == Line then
          self:SetActiveTab(i)
          self:SetCode(code)
          return
        elseif self:GetEditor(i):GetValue() == code then
          self:SetActiveTab(i)
          return
        end
      end
    end
    local title, tabtext = getPreferredTitles(Line, code)
    local tab
    if self.NewTabOnOpen:GetBool() or forcenewtab then
      tab = self:CreateTab(tabtext).Tab
    else
      tab = self:GetActiveTab()
      tab:SetText(tabtext)
      self.C.TabHolder:InvalidateLayout()
    end
    self:SetActiveTab(tab)

    self:ChosenFile()
    self:SetCode(code)
    if Line then self:SubTitle("Editing: " .. Line) end
    return
  end
  if Line then self:LoadFile(Line, forcenewtab) return end
end

function Editor:SaveFile(Line, close, SaveAs)
  self:ExtractName()
  if close and self.chip then
    if not self:Validate(true) then return end
    WireLib.Expression2Upload(self.chip, self:GetCode())
    self:Close()
    return
  end
  if not Line or SaveAs or Line == self.Location .. "/" .. ".txt" then
    local str
    if self.C.Browser.File then
      str = self.C.Browser.File.FileDir -- Get FileDir
      if str and str ~= "" then -- Check if not nil

        -- Remove "expression2/" or "cpuchip/" etc
        local n, _ = str:find("/", 1, true)
        str = str:sub(n + 1, -1)

        if str and str ~= "" then -- Check if not nil
          if str:Right(4) == ".txt" then -- If it's a file
            str = string.GetPathFromFilename(str):Left(-2) -- Get the file path instead
            if not str or str == "" then
              str = nil
            end
          end
        else
          str = nil
        end
      else
        str = nil
      end
    end
    Derma_StringRequestNoBlur("Save to New File", "", (str ~= nil and str .. "/" or "") .. self.savefilefn,
      function(strTextOut)
        strTextOut = string.gsub(strTextOut, ".", invalid_filename_chars)
        self:SaveFile(self.Location .. "/" .. strTextOut .. ".txt", close)
      end)
    return
  end

  file.Write(Line, self:GetCode())

  local panel = self.C.Val
  timer.Simple(0, function() panel.SetText(panel, " Saved as " .. Line) end)
  surface.PlaySound("ambient/water/drip3.wav")

  if not self.chip then self:ChosenFile(Line) end
  if close then
    if self.E2 then
      GAMEMODE:AddNotify("Expression saved as " .. Line .. ".", NOTIFY_GENERIC, 7)
    else
      GAMEMODE:AddNotify("Source code saved as " .. Line .. ".", NOTIFY_GENERIC, 7)
    end
    self:Close()
  end
end

function Editor:LoadFile(Line, forcenewtab)
  if not Line or file.IsDir(Line, "DATA") then return end

  local f = file.Open(Line, "r", "DATA")
  if not f then
    ErrorNoHalt("Erroring opening file: " .. Line)
  else
    local str = f:Read(f:Size()) or ""
    f:Close()
    self:AutoSave()
    if not forcenewtab then
      for i = 1, self:GetNumTabs() do
        if self:GetEditor(i).chosenfile == Line then
          self:SetActiveTab(i)
          if forcenewtab ~= nil then self:SetCode(str) end
          return
        elseif self:GetEditor(i):GetValue() == str then
          self:SetActiveTab(i)
          return
        end
      end
    end
    if not self.chip then
      local title, tabtext = getPreferredTitles(Line, str)
      local tab
      if self.NewTabOnOpen:GetBool() or forcenewtab then
        tab = self:CreateTab(tabtext).Tab
      else
        tab = self:GetActiveTab()
        tab:SetText(tabtext)
        self.C.TabHolder:InvalidateLayout()
      end
      self:SetActiveTab(tab)
      self:ChosenFile(Line)
    end
    self:SetCode(str)
  end
end

function Editor:Close()
  timer.Stop("e2autosave")
  self:AutoSave()

  self:Validate()
  self:ExtractName()
  self:SetV(false)
  self.chip = false

  self:SaveEditorSettings()
end

function Editor:Setup(nTitle, nLocation, nEditorType)
  self.Title = nTitle
  self.Location = nLocation
  self.EditorType = nEditorType
  self.C.Browser:Setup(nLocation)

  self:SetEditorMode(nEditorType)

  local SFHelp = vgui.Create("StarfallButton", self.C.ButtonHolder)
  SFHelp:SetSize(58, 20)
	SFHelp:DockMargin(2, 0, 0, 0)	
  SFHelp:Dock(RIGHT)
  SFHelp:SetText("SFHelper")
  SFHelp.DoClick = function()
    if SF.Helper.Frame and SF.Helper.Frame:IsVisible() then
      SF.Helper.Frame:close()
    else
      SF.Helper.show()
    end
  end
  self.C.SFHelp = SFHelp

  -- Add "Sound Browser" button
  local SoundBrw = vgui.Create("StarfallButton", self.C.ButtonHolder)
  SoundBrw:SetSize(85, 20)
	SoundBrw:DockMargin(2, 0, 0, 0)	
  SoundBrw:Dock(RIGHT)
  SoundBrw:SetText("Sound Browser")
  SoundBrw.DoClick = function() RunConsoleCommand("wire_sound_browser_open") end
  self.C.SoundBrw = SoundBrw
  self:OpenOldTabs()

  --Add "Model Viewer" button
  local ModelViewer = vgui.Create("StarfallButton", self.C.ButtonHolder)
  ModelViewer:SetSize(85, 20)
	ModelViewer:DockMargin(2, 0, 0, 0)	
  ModelViewer:Dock(RIGHT)
  ModelViewer:SetText("Movel Viewer")
  ModelViewer.DoClick = function()
    if SF.Editor.modelViewer:IsVisible() then
      SF.Editor.modelViewer:close()
    else
      SF.Editor.modelViewer:open()
    end
  end
  self.C.ModelViewer = ModelViewer
  self:OpenOldTabs()

  self:InvalidateLayout()
end

vgui.Register("StarfallEditorFrame", Editor, "Expression2EditorFrame")
