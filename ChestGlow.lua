-- ChestGlow: a yellow halo and orbiting sparks on each cache you can afford.
-- WoW 1.12 / Lua 5.0. Needs Azeroth Survivors world anchors (0.139.2+).
-- The glow sits on the same point as SurvivorsDragonUi's cache icon (five yards
-- up). When that icon is on, this addon draws only the glow behind it, and tells
-- DragonUI to draw the icon at half strength when the cache costs more than you have.
-- A minimap button opens the control panel.

local QUERY = { kinds = { "cache" }, states = { "present" } }
local OFFSET = { z = 5 }
local HALO = 64
local RING = 46
local SPARK = 14
local SPARK_COUNT = 4
local ORBIT = 20

local ICON_PATHS = {
  { path = "Interface\\AddOns\\SurvivorsDragonUi\\media\\tex\\waypoint\\Chest", crop = false },
  { path = "Interface\\AddOns\\LuckyOdds\\chest", crop = false },
  { path = "Interface\\Icons\\INV_Box_02", crop = true },
}

local function DefaultDB()
  if not ChestGlowDB then ChestGlowDB = {} end
  if ChestGlowDB.on == nil then ChestGlowDB.on = true end
  if ChestGlowDB.affordableOnly == nil then ChestGlowDB.affordableOnly = true end
  if ChestGlowDB.dimIcons == nil then ChestGlowDB.dimIcons = true end
  if ChestGlowDB.announce == nil then ChestGlowDB.announce = true end
  if type(ChestGlowDB.nearby) ~= "number" then ChestGlowDB.nearby = 0 end
  if ChestGlowDB.scale ~= 1 and ChestGlowDB.scale ~= 2 and ChestGlowDB.scale ~= 3 then ChestGlowDB.scale = 2 end
  if ChestGlowDB.shown == nil then ChestGlowDB.shown = false end
  if type(ChestGlowDB.btnAngle) ~= "number" then ChestGlowDB.btnAngle = 200 end
end
DefaultDB()

local active, byId, pool = {}, {}, {}

local function Rot(x, y, s, c)
  x, y = x - 0.5, y - 0.5
  return 0.5 + x * c - y * s, 0.5 + x * s + y * c
end

local function Spin(tex, angle)
  local s, c = math.sin(angle), math.cos(angle)
  local ulx, uly = Rot(0, 0, s, c)
  local llx, lly = Rot(0, 1, s, c)
  local urx, ury = Rot(1, 0, s, c)
  local lrx, lry = Rot(1, 1, s, c)
  tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local function Call(fn, a, b)
  if type(fn) ~= "function" then return end
  local ok, value, err
  if b == nil then
    ok, value, err = pcall(fn, a)
  else
    ok, value, err = pcall(fn, a, b)
  end
  if ok and err == nil and type(value) == "table" then return value end
end

-- DragonUI's own cache icon is drawn above this frame. Hide ours while it is on
-- so the two pictures do not stack.
local function DragonCacheIcons()
  if type(DFRL) ~= "table" or type(DFRL.display) ~= "table" or type(DFRL.display.Get) ~= "function" then
    return false
  end
  local ok, on = pcall(DFRL.display.Get, "worldCacheIcons")
  return ok and on and true or false
end

local function CanAfford()
  local run = AZS_RUN
  if type(run) ~= "table" then return false end
  local gold, cost = tonumber(run.gold), tonumber(run.chest)
  if not gold or not cost then return false end
  return gold >= cost
end

local function GlowScale()
  if ChestGlowDB.scale == 1 then return 0.75 end
  if ChestGlowDB.scale == 3 then return 1.35 end
  return 1
end

-- DragonUI calls this while it draws a cache icon. Full strength unless the
-- dim option is on and the next cache costs more gold than you have.
function ChestGlow_IconAlpha()
  if not ChestGlowDB.on or not ChestGlowDB.dimIcons or CanAfford() then return 1 end
  return 0.5
end

local function ApplyIcon(tex)
  for i = 1, table.getn(ICON_PATHS) do
    local choice = ICON_PATHS[i]
    local ok, found = pcall(tex.SetTexture, tex, choice.path)
    if ok and found then
      if choice.crop then
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      else
        tex:SetTexCoord(0, 1, 0, 1)
      end
      return
    end
  end
end

local function NewMarker()
  local frame = CreateFrame("Frame", nil, WorldFrame)
  frame:SetWidth(HALO)
  frame:SetHeight(HALO)
  frame:SetFrameStrata("BACKGROUND")
  frame:EnableMouse(false)
  frame:Hide()

  local halo = frame:CreateTexture(nil, "ARTWORK")
  halo:SetTexture("Interface\\Cooldown\\star4")
  halo:SetBlendMode("ADD")
  halo:SetVertexColor(1, 0.92, 0.15)
  halo:SetWidth(HALO)
  halo:SetHeight(HALO)
  halo:SetPoint("CENTER", frame, "CENTER", 0, 0)
  frame.halo = halo

  local ring = frame:CreateTexture(nil, "ARTWORK")
  ring:SetTexture("Interface\\Cooldown\\ping4")
  ring:SetBlendMode("ADD")
  ring:SetVertexColor(1, 1, 0.4)
  ring:SetWidth(RING)
  ring:SetHeight(RING)
  ring:SetPoint("CENTER", frame, "CENTER", 0, 0)
  frame.ring = ring

  local icon = frame:CreateTexture(nil, "OVERLAY")
  icon:SetWidth(22)
  icon:SetHeight(22)
  icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
  ApplyIcon(icon)
  frame.icon = icon

  frame.sparks = {}
  for i = 1, SPARK_COUNT do
    local spark = frame:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\Cooldown\\star4")
    spark:SetBlendMode("ADD")
    spark:SetVertexColor(1, 0.98, 0.45)
    spark:SetWidth(SPARK)
    spark:SetHeight(SPARK)
    frame.sparks[i] = spark
  end
  return frame
end

local function Acquire()
  local frame = table.remove(pool)
  if not frame then frame = NewMarker() end
  return frame
end

local function Release(entry)
  entry.frame:Hide()
  entry.drop = nil
  table.insert(pool, entry.frame)
end

local function HideAll()
  for i = 1, table.getn(active) do
    active[i].frame:Hide()
  end
end

local function SetShown(tex, on)
  local shown = tex:IsShown()
  if on then
    if not shown then tex:Show() end
  elseif shown then
    tex:Hide()
  end
end

local function Animate(frame, clock, showIcon, glow, canAfford)
  if glow then
    local scale = GlowScale()
    local pulse = 0.5 + 0.5 * math.sin(clock * 2.4)
    SetShown(frame.halo, true)
    frame.halo:SetAlpha(0.22 + 0.38 * pulse)
    local haloSize = (56 + 10 * pulse) * scale
    if frame.haloSize ~= haloSize then
      frame.halo:SetWidth(haloSize)
      frame.halo:SetHeight(haloSize)
      frame.haloSize = haloSize
    end
    Spin(frame.halo, clock * 0.45)

    SetShown(frame.ring, true)
    frame.ring:SetAlpha(0.18 + 0.32 * (0.5 + 0.5 * math.sin(clock * 2.4 + 1.1)))
    local ringSize = (40 + 8 * (1 - pulse)) * scale
    if frame.ringSize ~= ringSize then
      frame.ring:SetWidth(ringSize)
      frame.ring:SetHeight(ringSize)
      frame.ringSize = ringSize
    end

    local sparkSize = SPARK * scale
    local orbit = ORBIT * scale
    for i = 1, SPARK_COUNT do
      local spark = frame.sparks[i]
      local angle = clock * 2.5 + (i - 1) * (6.28318 / SPARK_COUNT)
      if spark.drawn ~= sparkSize then
        spark:SetWidth(sparkSize)
        spark:SetHeight(sparkSize)
        spark.drawn = sparkSize
      end
      spark:ClearAllPoints()
      spark:SetPoint("CENTER", frame, "CENTER", math.cos(angle) * orbit, math.sin(angle) * orbit)
      spark:SetAlpha(0.3 + 0.7 * (0.5 + 0.5 * math.sin(clock * 7 + i * 1.7)))
      SetShown(spark, true)
    end
  else
    SetShown(frame.halo, false)
    SetShown(frame.ring, false)
    for i = 1, SPARK_COUNT do
      SetShown(frame.sparks[i], false)
    end
  end

  if showIcon then
    SetShown(frame.icon, true)
    local alpha = (ChestGlowDB.dimIcons and not canAfford) and 0.5 or 1
    if frame.iconAlpha ~= alpha then
      frame.icon:SetAlpha(alpha)
      frame.iconAlpha = alpha
    end
  else
    SetShown(frame.icon, false)
  end
end

-- Read the whole cache catalog from the start. A cursor from an older catalog
-- is rejected, so this never resumes a previous page.
local function Scan()
  local cursor, seen
  seen = {}
  repeat
    local page = Call(AZS_GetWorldAnchors, QUERY, cursor)
    if not page or type(page.entries) ~= "table" then return false end
    for i = 1, table.getn(page.entries) do
      local entry = page.entries[i]
      local id = type(entry) == "table" and entry.anchorId
      if type(id) == "string" and id ~= "" then
        seen[id] = true
        if not byId[id] then
          local frame = Acquire()
          local kept = { id = id, frame = frame, request = { anchorId = id, attachment = "position", offset = OFFSET } }
          byId[id] = kept
          table.insert(active, kept)
        end
      end
    end
    if page.hasMore and (type(page.nextCursor) ~= "string" or page.nextCursor == cursor) then
      return false
    end
    cursor = page.nextCursor
  until not page.hasMore

  local i = 1
  while i <= table.getn(active) do
    if not seen[active[i].id] then
      local entry = active[i]
      byId[entry.id] = nil
      Release(entry)
      table.remove(active, i)
    else
      i = i + 1
    end
  end
  return true
end

local function InRange(point)
  local limit = ChestGlowDB.nearby
  if type(limit) ~= "number" or limit <= 0 then return true end
  if type(point.playerDistance) ~= "number" then return true end
  return point.playerDistance <= limit
end

-- First sample only remembers the state, so loading in already able to buy
-- does not announce. Crossing from short to enough does.
local sawAfford
local function WatchAfford(canAfford)
  if sawAfford == nil then
    sawAfford = canAfford
    return
  end
  if canAfford and not sawAfford and ChestGlowDB.announce then
    local phase = AZS_GetPhase and AZS_GetPhase()
    if phase == "playing" or phase == "choosing" then
      UIErrorsFrame:AddMessage("You can open a cache", 1, 0.92, 0.15, 1, 3)
      pcall(PlaySound, "MONEYFRAMEOPEN")
    end
  end
  sawAfford = canAfford
end

local function Place()
  local canAfford = CanAfford()
  WatchAfford(canAfford)
  if not ChestGlowDB.on then
    HideAll()
    return
  end

  Scan()

  local showIcon = not DragonCacheIcons()
  local glow = canAfford or not ChestGlowDB.affordableOnly
  -- DragonUI draws the icon in that case. With no glow and no icon of our own,
  -- there is nothing for this frame to show.
  if not glow and not showIcon then
    HideAll()
    return
  end

  local count = table.getn(active)
  if count == 0 then return end

  local requests = {}
  for i = 1, count do
    requests[i] = active[i].request
  end
  local projection = Call(AZS_ProjectWorldAnchors, requests)
  if not projection or not projection.frameCurrent or type(projection.entries) ~= "table" then return end

  local clock = projection.clockSeconds or GetTime()
  local n = table.getn(projection.entries)
  if n > count then n = count end
  for i = n + 1, count do
    if active[i].frame:IsShown() then active[i].frame:Hide() end
  end
  for i = 1, n do
    local point, entry = projection.entries[i], active[i]
    local frame = entry.frame
    if point.state == "onScreen" and type(point.x) == "number" and type(point.y) == "number" and InRange(point) then
      entry.drop = nil
      if frame.px ~= point.x or frame.py ~= point.y then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", WorldFrame, "BOTTOMLEFT", point.x, point.y)
        frame.px, frame.py = point.x, point.y
      end
      Animate(frame, clock, showIcon, glow, canAfford)
      if not frame:IsShown() then frame:Show() end
    else
      if frame:IsShown() then frame:Hide() end
      if point.state == "expired" or point.state == "unknownAnchor" or point.state == "worldChanged" then
        entry.drop = true
      end
    end
  end

  for i = table.getn(active), 1, -1 do
    if active[i].drop then
      local entry = active[i]
      byId[entry.id] = nil
      Release(entry)
      table.remove(active, i)
    end
  end
end

if AZS_RegisterWorldAnchorFrameHandler then
  AZS_RegisterWorldAnchorFrameHandler(Place)
end

local function Say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ChestGlow|r " .. text)
end

local function NearestDist()
  if not (AZS_GetPhase and AZS_GetPhase()) then return end
  local hx, hy, space
  if AZS_GetPlayerPosition then
    local pos = AZS_GetPlayerPosition()
    if type(pos) == "table" then
      hx, hy, space = tonumber(pos.x), tonumber(pos.y), pos.spaceId
    end
  end
  if not hx or not hy then
    local run = AZS_RUN
    if type(run) == "table" then hx, hy = tonumber(run.px), tonumber(run.py) end
  end
  if not hx or not hy or type(AZS_CHESTS) ~= "table" then return end
  local best
  for i = 1, table.getn(AZS_CHESTS) do
    local chest = AZS_CHESTS[i]
    if type(chest) == "table" then
      local x, y = tonumber(chest.x), tonumber(chest.y)
      if x and y and (not space or not chest.spaceId or chest.spaceId == space) then
        local dx, dy = x - hx, y - hy
        local dist = math.sqrt(dx * dx + dy * dy)
        if not best or dist < best then best = dist end
      end
    end
  end
  return best
end

local function SquareMinimap()
  if type(GetMinimapShape) == "function" then
    local ok, shape = pcall(GetMinimapShape)
    if ok and shape then return shape == "SQUARE" end
  end
  return DFRL ~= nil
end

local RANGES = { 0, 30, 45, 60, 90 }
local SIZES = { "Small", "Medium", "Large" }
local checks = {}
local panel, btn, btnIcon
local rangeValue, sizeValue

local function RangeText()
  if not ChestGlowDB.nearby or ChestGlowDB.nearby == 0 then return "All" end
  return ChestGlowDB.nearby .. " yd"
end

local function RefreshButton()
  if not btnIcon then return end
  if ChestGlowDB.on then
    btnIcon:SetVertexColor(1, 0.92, 0.35)
  else
    btnIcon:SetVertexColor(0.4, 0.4, 0.4)
  end
end

local function RefreshChecks()
  for i = 1, table.getn(checks) do
    local row = checks[i]
    if ChestGlowDB[row.key] then row:SetChecked(1) else row:SetChecked(nil) end
  end
end

local function RefreshSteppers()
  if rangeValue then rangeValue:SetText(RangeText()) end
  if sizeValue then sizeValue:SetText(SIZES[ChestGlowDB.scale] or "Medium") end
end

local function ShowPanel(show)
  ChestGlowDB.shown = show and true or false
  if ChestGlowDB.shown then
    RefreshChecks()
    RefreshSteppers()
    panel:Show()
  else
    panel:Hide()
  end
end

local function SetGlow(on)
  ChestGlowDB.on = on and true or false
  if not ChestGlowDB.on then HideAll() end
  RefreshButton()
  RefreshChecks()
  Say(ChestGlowDB.on and "on." or "off.")
end

panel = CreateFrame("Frame", "ChestGlowPanel", UIParent)
panel:SetWidth(360)
panel:SetHeight(320)
panel:SetFrameStrata("HIGH")
panel:EnableMouse(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
panel:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
if type(ChestGlowDB.point) == "table" then
  panel:SetPoint(ChestGlowDB.point[1], UIParent, ChestGlowDB.point[2], ChestGlowDB.point[3], ChestGlowDB.point[4])
else
  panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
end
panel:SetScript("OnDragStart", function() this:StartMoving() end)
panel:SetScript("OnDragStop", function()
  this:StopMovingOrSizing()
  local point, _, rel, x, y = this:GetPoint(1)
  if point and rel and x and y then
    ChestGlowDB.point = { point, rel, x, y }
  end
end)
panel:Hide()

local header = panel:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetWidth(256)
header:SetHeight(64)
header:SetPoint("TOP", panel, "TOP", 0, 12)
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText("ChestGlow")

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
close:SetScript("OnClick", function() ShowPanel(false) end)

-- Stacked from the header down. Each block is a title plus a gray description.
local cursor = -34

local function Note(parent, point, rel, x, y, text)
  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", parent, point, x, y)
  note:SetWidth(300)
  note:SetJustifyH("LEFT")
  note:SetTextColor(0.78, 0.72, 0.58)
  note:SetText(text)
  local height = note:GetHeight()
  if not height or height < 26 then height = 26 end
  return note, height
end

local function AddCheck(name, label, about, key)
  local row = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
  row:SetWidth(26)
  row:SetHeight(26)
  row:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, cursor)
  row:SetHitRectInsets(0, -300, 0, 0)
  row.key = key
  local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", row, "RIGHT", 2, 1)
  text:SetText(label)
  local _, height = Note(text, "BOTTOMLEFT", "TOPLEFT", 0, -1, about)
  cursor = cursor - 24 - height - 12
  row:SetScript("OnClick", function()
    local checked = this:GetChecked()
    ChestGlowDB[this.key] = checked == 1 or checked == true
    if this.key == "on" then
      if not ChestGlowDB.on then HideAll() end
      RefreshButton()
      Say(ChestGlowDB.on and "on." or "off.")
    end
  end)
  table.insert(checks, row)
end

AddCheck("ChestGlowCheckOn", "Glow", "Shows a yellow glow and sparks on caches in the world.", "on")
AddCheck("ChestGlowCheckAfford", "Only when you can afford it", "The glow stays off until you have enough gold to open a cache.", "affordableOnly")
AddCheck("ChestGlowCheckDim", "Dim icons you can't afford", "A cache you cannot buy yet is drawn fainter, at about half strength.", "dimIcons")
AddCheck("ChestGlowCheckAnnounce", "Announce when you can buy one", "A notice appears on screen the moment you have enough gold.", "announce")

local rule = panel:CreateTexture(nil, "ARTWORK")
rule:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
rule:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, cursor)
rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, cursor)
rule:SetHeight(1)
rule:SetVertexColor(1, 0.82, 0.35, 0.45)
cursor = cursor - 14

local function AddStepper(caption, about)
  local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, cursor)
  label:SetText(caption)
  local plus = CreateFrame("Button", "ChestGlow" .. caption .. "Plus", panel, "UIPanelButtonTemplate")
  plus:SetWidth(28)
  plus:SetHeight(22)
  plus:SetText(">")
  plus:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, cursor + 4)
  local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  value:SetWidth(72)
  value:SetJustifyH("CENTER")
  value:SetPoint("RIGHT", plus, "LEFT", -2, 0)
  local minus = CreateFrame("Button", "ChestGlow" .. caption .. "Minus", panel, "UIPanelButtonTemplate")
  minus:SetWidth(28)
  minus:SetHeight(22)
  minus:SetText("<")
  minus:SetPoint("RIGHT", value, "LEFT", -2, 0)
  local _, height = Note(label, "BOTTOMLEFT", "TOPLEFT", 0, -8, about)
  cursor = cursor - 22 - height - 12
  return value, minus, plus
end

local rangeMinus, rangePlus, sizeMinus, sizePlus
rangeValue, rangeMinus, rangePlus = AddStepper("Range", "How far a cache can be and still glow. All means every cache.")
sizeValue, sizeMinus, sizePlus = AddStepper("Size", "How large the glow and sparks appear on screen.")
panel:SetHeight(-cursor + 22)

local function ShiftRange(dir)
  local index = 1
  for i = 1, table.getn(RANGES) do
    if RANGES[i] == ChestGlowDB.nearby then index = i end
  end
  index = index + dir
  if index < 1 then index = 1 end
  if index > table.getn(RANGES) then index = table.getn(RANGES) end
  ChestGlowDB.nearby = RANGES[index]
  rangeValue:SetText(RangeText())
end

local function ShiftScale(dir)
  local index = ChestGlowDB.scale or 2
  index = index + dir
  if index < 1 then index = 1 end
  if index > 3 then index = 3 end
  ChestGlowDB.scale = index
  sizeValue:SetText(SIZES[index])
end

rangeMinus:SetScript("OnClick", function() ShiftRange(-1) end)
rangePlus:SetScript("OnClick", function() ShiftRange(1) end)
sizeMinus:SetScript("OnClick", function() ShiftScale(-1) end)
sizePlus:SetScript("OnClick", function() ShiftScale(1) end)

local function DropBelowCards()
  if AZS_SetOnTopOfScreens then
    pcall(AZS_SetOnTopOfScreens, panel, false)
  end
end

btn = CreateFrame("Button", "ChestGlowMinimapButton", Minimap)
btn:SetWidth(31)
btn:SetHeight(31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
btnIcon = btn:CreateTexture(nil, "BACKGROUND")
btnIcon:SetWidth(20)
btnIcon:SetHeight(20)
btnIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
do
  local ok, found = pcall(btnIcon.SetTexture, btnIcon, "Interface\\AddOns\\SurvivorsDragonUi\\media\\tex\\waypoint\\Chest")
  if not ok or not found then
    btnIcon:SetTexture("Interface\\Icons\\INV_Box_02")
    btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
end
local btnRing = btn:CreateTexture(nil, "OVERLAY")
btnRing:SetWidth(53)
btnRing:SetHeight(53)
btnRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
btnRing:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

local function PlaceButton()
  local angle = math.rad(ChestGlowDB.btnAngle or 200)
  local x, y = math.cos(angle), math.sin(angle)
  if SquareMinimap() then
    local reach = math.max(math.abs(x), math.abs(y))
    x, y = x / reach, y / reach
  end
  local radius = (Minimap:GetWidth() or 140) / 2 + 8
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetScript("OnClick", function()
  if arg1 == "RightButton" then
    SetGlow(not ChestGlowDB.on)
  else
    ShowPanel(not panel:IsShown())
  end
end)
btn:SetScript("OnDragStart", function()
  this:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ChestGlowDB.btnAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    PlaceButton()
  end)
end)
btn:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
btn:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:AddLine("ChestGlow", 1, 0.82, 0)
  GameTooltip:AddLine("Left-click: open the panel", 1, 1, 1)
  GameTooltip:AddLine("Right-click: glow on or off", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
  if CanAfford() then
    GameTooltip:AddLine("You can open a cache", 0.3, 1, 0.35)
  else
    local run = AZS_RUN
    local gold = type(run) == "table" and tonumber(run.gold)
    local cost = type(run) == "table" and tonumber(run.chest)
    if gold and cost and cost > gold then
      GameTooltip:AddLine(string.format("Need %d more gold", cost - gold), 1, 0.45, 0.25)
    end
  end
  local dist = NearestDist()
  if dist then
    GameTooltip:AddLine(string.format("Nearest cache  %d yd", math.floor(dist + 0.5)), 0.9, 0.9, 0.9)
  end
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

SLASH_CHESTGLOW1 = "/chestglow"
SlashCmdList["CHESTGLOW"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "on" then
    SetGlow(true)
  elseif msg == "off" then
    SetGlow(false)
  elseif msg == "toggle" then
    SetGlow(not ChestGlowDB.on)
  else
    ShowPanel(not panel:IsShown())
  end
end

RefreshButton()
RefreshChecks()
RefreshSteppers()
DropBelowCards()
PlaceButton()
if ChestGlowDB.shown then panel:Show() end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("VARIABLES_LOADED")
boot:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    DefaultDB()
    RefreshButton()
    RefreshChecks()
    RefreshSteppers()
    PlaceButton()
    DropBelowCards()
    if ChestGlowDB.shown then panel:Show() else panel:Hide() end
    return
  end
  PlaceButton()
  if this.said then return end
  this.said = true
  if not AZS_GetWorldAnchorCapabilities then
    Say("needs game 0.139.2 or newer for world anchors.")
    return
  end
  Say("minimap button opens the panel. Right-click it to turn the glow on or off.")
end)
