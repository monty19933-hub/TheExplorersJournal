local addonName, TEJ = ...

local ADDON_TITLE = "The Explorer's Journal"
local DB_VERSION = 1
local UPDATE_INTERVAL = 0.15
local MAP_PANEL_SIZE = 224
local MAX_ROUTE_BUTTONS = 48
local MINIMAP_ROUTE_SCALE = 1350

local CONTINENTS = {
    { id = "eastern-kingdoms", label = "Eastern Kingdoms" },
    { id = "kalimdor", label = "Kalimdor" },
}

local DIFFICULTIES = {
    {
        id = "easy",
        label = "Easy",
        description = "These are easier explorations, any class/race combo can do these with no special exploration methods.",
    },
    {
        id = "intermediate",
        label = "Intermediate",
        description = "These explorations require a little more thinking. They may require some methods that are only available to certain races/classes, or require specific items/spells.",
    },
    {
        id = "advanced",
        label = "Advanced",
        description = "These explorations are for the most advanced explorers. They may require difficult to perform jumps, require items that are no longer available to players, off-line mode exploration, etc.",
    },
}

local defaults = {
    version = DB_VERSION,
    activeRouteID = nil,
    mainVisible = false,
    hudVisible = true,
    worldMapVisible = true,
    minimapVisible = true,
    locked = false,
    scale = 1,
    minimapButtonAngle = 225,
    expandedContinents = {
        ["eastern-kingdoms"] = true,
        kalimdor = false,
    },
    expandedDifficulties = {
        ["eastern-kingdoms"] = {
            easy = true,
            intermediate = false,
            advanced = false,
        },
        kalimdor = {
            easy = true,
            intermediate = false,
            advanced = false,
        },
    },
    customRoutes = {},
    routeItems = {},
    positions = {
        main = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        hud = { point = "CENTER", relativePoint = "CENTER", x = 330, y = 40 },
    },
}

local state = {
    routeButtons = {},
    hudPins = {},
    hudLines = {},
    worldMapPins = {},
    worldMapLines = {},
    worldMapLabels = {},
    minimapPins = {},
    minimapLines = {},
    minimapLabels = {},
    waypointRows = {},
    itemRows = {},
    elapsed = 0,
    mapElapsed = 0,
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then
        dst = {}
    end

    for key, value in pairs(src) do
        if type(value) == "table" then
            dst[key] = CopyDefaults(value, dst[key])
        elseif dst[key] == nil then
            dst[key] = value
        end
    end

    return dst
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66d9efTEJ|r " .. tostring(message))
end

local function CreatePanel(name, parent)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", name, parent or UIParent, template)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.04, 0.045, 0.05, 0.95)
        frame:SetBackdropBorderColor(0.42, 0.33, 0.18, 0.95)
    end
    return frame
end

local function MakeButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    return button
end

local function MakeFont(parent, size, color)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    font:SetTextColor(color.r, color.g, color.b)
    font:SetFont(STANDARD_TEXT_FONT, size, "")
    return font
end

local function FormatCoord(value)
    if not value then
        return "--"
    end
    return string.format("%.1f", value * 100)
end

local function Trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function Slugify(value)
    value = string.lower(Trim(value or "route"))
    value = string.gsub(value, "[^%w]+", "-")
    value = string.gsub(value, "^-+", "")
    value = string.gsub(value, "-+$", "")
    if value == "" then
        value = "route"
    end
    return value
end

local function SaveFramePosition(frame, key)
    if not TEJ.db or not TEJ.db.positions or not frame then
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    TEJ.db.positions[key] = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

local function RestoreFramePosition(frame, key)
    local pos = TEJ.db.positions[key] or defaults.positions[key]
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

local function GetPlayerPosition()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
        return nil
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        return nil
    end

    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return nil
    end

    local x, y = position:GetXY()
    if not x or not y or x <= 0 or y <= 0 then
        return nil
    end

    return mapID, x, y
end

local function GetWorldMapID()
    if WorldMapFrame and WorldMapFrame.GetMapID then
        return WorldMapFrame:GetMapID()
    end

    if C_Map and C_Map.GetBestMapForUnit then
        return C_Map.GetBestMapForUnit("player")
    end

    return nil
end

local function GetWorldMapCanvas()
    if not WorldMapFrame then
        return nil
    end

    if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetCanvas then
        local canvas = WorldMapFrame.ScrollContainer:GetCanvas()
        if canvas then
            return canvas
        end
    end

    if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child then
        return WorldMapFrame.ScrollContainer.Child
    end

    if WorldMapDetailFrame then
        return WorldMapDetailFrame
    end

    if WorldMapButton then
        return WorldMapButton
    end

    return WorldMapFrame.ScrollContainer or WorldMapFrame
end

local function DistanceSquared(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end

local function Atan2(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end

    return 0
end

local function BearingLabel(dx, dy)
    local degrees = math.deg(Atan2(dx, -dy))
    if degrees < 0 then
        degrees = degrees + 360
    end

    local directions = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
    local index = math.floor((degrees + 22.5) / 45) + 1
    if index > #directions then
        index = 1
    end

    return directions[index], degrees
end

local function GetMapName(mapID)
    if C_Map and C_Map.GetMapInfo and mapID then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then
            return info.name
        end
    end

    return "Map " .. tostring(mapID or "?")
end

local function GetWaypointMapID(route, waypoint)
    return waypoint and (waypoint.mapID or route.mapID) or route.mapID
end

local function RouteHasMap(route, mapID)
    if not route or not mapID then
        return false
    end

    for _, waypoint in ipairs(route.waypoints or {}) do
        if GetWaypointMapID(route, waypoint) == mapID then
            return true
        end
    end

    return route.mapID == mapID
end

local function GetRouteMapSummary(route)
    local names = {}
    local seen = {}

    for _, waypoint in ipairs(route.waypoints or {}) do
        local mapID = GetWaypointMapID(route, waypoint)
        if mapID and not seen[mapID] then
            table.insert(names, GetMapName(mapID))
            seen[mapID] = true
        end
    end

    if #names == 0 and route.mapID then
        table.insert(names, GetMapName(route.mapID))
    end

    if #names == 0 then
        return "No map yet"
    end

    return table.concat(names, " -> ")
end

local function GetRouteMapBounds(route, mapID)
    local firstIndex, lastIndex

    for index, waypoint in ipairs(route.waypoints or {}) do
        if GetWaypointMapID(route, waypoint) == mapID then
            firstIndex = firstIndex or index
            lastIndex = index
        end
    end

    return firstIndex, lastIndex
end

local function GetDifficultyInfo(difficultyID)
    difficultyID = string.lower(difficultyID or "easy")
    for _, difficulty in ipairs(DIFFICULTIES) do
        if difficulty.id == difficultyID then
            return difficulty
        end
    end

    return DIFFICULTIES[1]
end

local function GetContinentInfo(continentID)
    continentID = string.lower(continentID or "eastern-kingdoms")
    for _, continent in ipairs(CONTINENTS) do
        if continent.id == continentID then
            return continent
        end
    end

    return CONTINENTS[1]
end

local function GetContinentSortIndex(continentID)
    continentID = string.lower(continentID or "eastern-kingdoms")
    for index, continent in ipairs(CONTINENTS) do
        if continent.id == continentID then
            return index
        end
    end

    return 1
end

local function GetDifficultySortIndex(difficultyID)
    difficultyID = string.lower(difficultyID or "easy")
    for index, difficulty in ipairs(DIFFICULTIES) do
        if difficulty.id == difficultyID then
            return index
        end
    end

    return 1
end

local function GetRouteDifficulty(route)
    return GetDifficultyInfo(route and route.difficulty or "easy")
end

local function GetRouteContinent(route)
    return GetContinentInfo(route and route.continent or "eastern-kingdoms")
end

local function FormatWaypointNumber(index)
    if index < 10 then
        return tostring(index)
    end

    return tostring(index)
end

local function ResolveItem(input)
    input = Trim(input)
    if input == "" then
        return nil
    end

    local itemID = tonumber(input) or tonumber(string.match(input, "item:(%d+)") or "")
    local query = itemID or input
    local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(query)

    if (not name or not icon) and GetItemInfoInstant then
        local instantID, _, _, _, instantIcon = GetItemInfoInstant(query)
        itemID = itemID or instantID
        icon = icon or instantIcon
    end

    if not itemID and link then
        itemID = tonumber(string.match(link, "item:(%d+)") or "")
    end

    if not name and itemID then
        name = "Item " .. tostring(itemID)
    end

    if not icon then
        icon = "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    if not name then
        return nil
    end

    return {
        type = "item",
        id = itemID,
        name = name,
        link = link,
        quality = quality,
        icon = icon,
    }
end

local function ResolveSpell(input)
    input = Trim(input)
    if input == "" then
        return nil
    end

    local spellID = tonumber(string.match(input, "spell:(%d+)") or "") or tonumber(input)
    local query = spellID or input
    local name, _, icon = GetSpellInfo(query)

    if not spellID and input then
        spellID = select(7, GetSpellInfo(input))
    end

    if not name then
        return nil
    end

    return {
        type = "spell",
        id = spellID,
        name = name,
        link = spellID and ("spell:" .. tostring(spellID)) or nil,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
    }
end

local function ResolveNeededThing(input, entryType)
    input = Trim(input)
    if input == "" then
        return nil
    end

    if entryType == "spell" then
        return ResolveSpell(input)
    end

    if entryType == "item" then
        return ResolveItem(input)
    end

    if string.find(input, "spell:") then
        return ResolveSpell(input)
    end

    if string.find(input, "item:") then
        return ResolveItem(input)
    end

    return ResolveItem(input) or ResolveSpell(input)
end

StaticPopupDialogs["TEJ_DELETE_WAYPOINT"] = {
    text = "Delete waypoint %s?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, data)
        TEJ:DeleteWaypoint(data.routeID, data.index)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TEJ_DELETE_ROUTE"] = {
    text = "Delete route %s?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, data)
        TEJ:DeleteRoute(data.routeID)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function TEJ:GetAllRoutes()
    local routes = {}

    for _, route in ipairs(self.Routes or {}) do
        table.insert(routes, route)
    end

    for _, route in ipairs(self.db.customRoutes or {}) do
        table.insert(routes, route)
    end

    table.sort(routes, function(a, b)
        local aContinent = GetContinentSortIndex(a.continent)
        local bContinent = GetContinentSortIndex(b.continent)
        if aContinent ~= bContinent then
            return aContinent < bContinent
        end

        local aDifficulty = GetDifficultySortIndex(a.difficulty)
        local bDifficulty = GetDifficultySortIndex(b.difficulty)
        if aDifficulty == bDifficulty then
            return a.name < b.name
        end
        return aDifficulty < bDifficulty
    end)

    return routes
end

function TEJ:GetRouteByID(routeID)
    if not routeID then
        return nil
    end

    for _, route in ipairs(self:GetAllRoutes()) do
        if route.id == routeID then
            return route
        end
    end

    return nil
end

function TEJ:SetActiveRoute(routeID)
    self.db.activeRouteID = routeID
    self:Refresh()

    local route = self:GetRouteByID(routeID)
    if route then
        Print("Loaded route: " .. route.name)
    else
        Print("Route cleared.")
    end
end

function TEJ:GetActiveRoute()
    return self:GetRouteByID(self.db.activeRouteID)
end

function TEJ:GetRouteItems(route)
    if not route then
        return {}
    end

    self.db.routeItems = self.db.routeItems or {}
    self.db.routeItems[route.id] = self.db.routeItems[route.id] or {}
    return self.db.routeItems[route.id]
end

function TEJ:IsCustomRoute(route)
    if not route then
        return false
    end

    for _, customRoute in ipairs(self.db.customRoutes or {}) do
        if customRoute == route or customRoute.id == route.id then
            return true
        end
    end

    return false
end

function TEJ:MakeUniqueRouteID(name)
    local base = "custom-" .. Slugify(name)
    local routeID = base
    local suffix = 2

    while self:GetRouteByID(routeID) do
        routeID = base .. "-" .. suffix
        suffix = suffix + 1
    end

    return routeID
end

function TEJ:FindNextWaypoint(route, playerMapID, playerX, playerY)
    if not route or not route.waypoints or not playerX then
        return nil, nil
    end

    local closestIndex = nil
    local closestDistance = nil

    for index, waypoint in ipairs(route.waypoints) do
        if not playerMapID or GetWaypointMapID(route, waypoint) == playerMapID then
            local distance = DistanceSquared(playerX, playerY, waypoint.x, waypoint.y)
            if not closestDistance or distance < closestDistance then
                closestIndex = index
                closestDistance = distance
            end
        end
    end

    if not closestIndex then
        return route.waypoints[1], 1
    end

    local nextIndex = closestIndex
    if closestDistance and closestDistance < 0.00008 and closestIndex < #route.waypoints then
        nextIndex = closestIndex + 1
    end

    return route.waypoints[nextIndex], nextIndex
end

function TEJ:CreateMainFrame()
    local frame = CreatePanel("TheExplorersJournalFrame", UIParent)
    frame:SetSize(720, 560)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition(self, "main")
    end)
    frame:SetScript("OnHide", function()
        TEJ.db.mainVisible = false
    end)
    frame:SetScript("OnShow", function()
        TEJ.db.mainVisible = true
    end)

    local title = MakeFont(frame, 18, { r = 1, g = 0.82, b = 0.42 })
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText(ADDON_TITLE)

    local subtitle = MakeFont(frame, 11, { r = 0.72, g = 0.72, b = 0.68 })
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Pick a route, load the overlay, and follow the waypoint panel.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local listTitle = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    listTitle:SetPoint("TOPLEFT", 20, -64)
    listTitle:SetText("Routes")

    local scrollFrame = CreateFrame("ScrollFrame", "TheExplorersJournalRouteScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -84)
    scrollFrame:SetSize(232, 392)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(208, 392)
    scrollFrame:SetScrollChild(scrollChild)
    frame.routeList = scrollChild

    local detailTitle = MakeFont(frame, 16, { r = 1, g = 0.86, b = 0.48 })
    detailTitle:SetPoint("TOPLEFT", 280, -66)
    detailTitle:SetWidth(390)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetText("No route selected")
    frame.detailTitle = detailTitle

    local detailMeta = MakeFont(frame, 11, { r = 0.7, g = 0.7, b = 0.68 })
    detailMeta:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -6)
    detailMeta:SetWidth(390)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetText("")
    frame.detailMeta = detailMeta

    local detailText = MakeFont(frame, 12, { r = 0.88, g = 0.86, b = 0.78 })
    detailText:SetPoint("TOPLEFT", detailMeta, "BOTTOMLEFT", 0, -12)
    detailText:SetSize(390, 44)
    detailText:SetJustifyH("LEFT")
    detailText:SetJustifyV("TOP")
    detailText:SetText("")
    frame.detailText = detailText

    local itemsTitle = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    itemsTitle:SetPoint("TOPLEFT", 280, -148)
    itemsTitle:SetText("Items and Spells needed before you head out:")
    frame.itemsTitle = itemsTitle

    local addItem = MakeButton(frame, "Add", 60, 22)
    addItem:SetPoint("LEFT", itemsTitle, "RIGHT", 12, 0)
    addItem:SetScript("OnClick", function()
        TEJ:OpenItemEditor()
    end)
    frame.addItem = addItem

    for index = 1, 8 do
        local item = CreateFrame("Button", nil, frame)
        item:SetSize(32, 32)
        item:SetPoint("TOPLEFT", itemsTitle, "BOTTOMLEFT", (index - 1) * 42, -8)
        item:EnableMouse(true)
        item:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(item)
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        item.icon = icon

        item:Hide()
        state.itemRows[index] = item
    end

    local waypointTitle = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    waypointTitle:SetPoint("TOPLEFT", 280, -206)
    waypointTitle:SetText("Waypoints and Notes")

    local waypointScroll = CreateFrame("ScrollFrame", "TheExplorersJournalWaypointScroll", frame, "UIPanelScrollFrameTemplate")
    waypointScroll:SetPoint("TOPLEFT", 280, -224)
    waypointScroll:SetSize(390, 228)

    local waypointChild = CreateFrame("Frame", nil, waypointScroll)
    waypointChild:SetSize(360, 228)
    waypointScroll:SetScrollChild(waypointChild)
    frame.waypointList = waypointChild

    for index = 1, 40 do
        local row = CreateFrame("Button", nil, waypointChild)
        row:SetSize(352, 34)
        row:EnableMouse(true)

        local text = MakeFont(row, 11, { r = 0.8, g = 0.8, b = 0.76 })
        text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        text:SetWidth(352)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        row.text = text

        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints(row)
        highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
        highlight:SetVertexColor(1, 0.82, 0.34, 0.08)
        row:SetHighlightTexture(highlight)

        state.waypointRows[index] = row
    end

    local load = MakeButton(frame, "Load Overlay", 116, 24)
    load:SetPoint("BOTTOMLEFT", 280, 20)
    load:SetScript("OnClick", function()
        local route = TEJ:GetActiveRoute()
        if route then
            TEJ.db.hudVisible = true
            TEJ.db.worldMapVisible = true
            TEJ.db.minimapVisible = true
            TEJ.hud:Show()
            TEJ:Refresh()
        else
            Print("Choose a route first.")
        end
    end)

    local clear = MakeButton(frame, "Clear", 72, 24)
    clear:SetPoint("LEFT", load, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        TEJ:SetActiveRoute(nil)
    end)

    local pos = MakeButton(frame, "Print Pos", 82, 24)
    pos:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    pos:SetScript("OnClick", function()
        TEJ:PrintPosition()
    end)

    local newRoute = MakeButton(frame, "New Route", 104, 24)
    newRoute:SetPoint("BOTTOMLEFT", 20, 48)
    newRoute:SetScript("OnClick", function()
        TEJ:OpenRouteEditor()
    end)

    local addWaypoint = MakeButton(frame, "Add GPS Waypoint", 138, 24)
    addWaypoint:SetPoint("BOTTOMLEFT", 20, 20)
    addWaypoint:SetScript("OnClick", function()
        TEJ:OpenWaypointEditor()
    end)

    local toggleHud = MakeButton(frame, "HUD", 72, 24)
    toggleHud:SetPoint("BOTTOMLEFT", 280, 48)
    toggleHud:SetScript("OnClick", function()
        TEJ.db.hudVisible = not TEJ.db.hudVisible
        TEJ:Refresh()
    end)

    local toggleMap = MakeButton(frame, "Map", 72, 24)
    toggleMap:SetPoint("LEFT", toggleHud, "RIGHT", 8, 0)
    toggleMap:SetScript("OnClick", function()
        TEJ.db.worldMapVisible = not TEJ.db.worldMapVisible
        TEJ:Refresh()
    end)

    local toggleMini = MakeButton(frame, "Minimap", 82, 24)
    toggleMini:SetPoint("LEFT", toggleMap, "RIGHT", 8, 0)
    toggleMini:SetScript("OnClick", function()
        TEJ.db.minimapVisible = not TEJ.db.minimapVisible
        TEJ:Refresh()
    end)

    self.main = frame
    RestoreFramePosition(frame, "main")

    if UISpecialFrames then
        tinsert(UISpecialFrames, "TheExplorersJournalFrame")
    end
end

function TEJ:CreateRouteEditor()
    if self.routeEditor then
        return
    end

    local frame = CreatePanel("TheExplorersJournalRouteEditor", UIParent)
    frame:SetSize(440, 360)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetPoint("CENTER")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    local title = MakeFont(frame, 16, { r = 1, g = 0.82, b = 0.42 })
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("Route Editor")
    frame.title = title

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local routeNameLabel = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    routeNameLabel:SetPoint("TOPLEFT", 22, -58)
    routeNameLabel:SetText("Route Name")
    frame.routeNameLabel = routeNameLabel

    local routeName = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    routeName:SetSize(360, 24)
    routeName:SetPoint("TOPLEFT", routeNameLabel, "BOTTOMLEFT", 0, -6)
    routeName:SetAutoFocus(false)
    frame.routeName = routeName

    local waypointLabel = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    waypointLabel:SetPoint("TOPLEFT", 22, -58)
    waypointLabel:SetText("Waypoint Label")
    frame.waypointLabel = waypointLabel

    local waypointName = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    waypointName:SetSize(360, 24)
    waypointName:SetPoint("TOPLEFT", waypointLabel, "BOTTOMLEFT", 0, -6)
    waypointName:SetAutoFocus(false)
    frame.waypointName = waypointName

    local noteLabel = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    noteLabel:SetPoint("TOPLEFT", waypointName, "BOTTOMLEFT", 0, -16)
    noteLabel:SetText("Waypoint Note")
    frame.noteLabel = noteLabel

    local noteBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    noteBox:SetSize(360, 86)
    noteBox:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -6)
    noteBox:SetAutoFocus(false)
    noteBox:SetMultiLine(true)
    noteBox:SetMaxLetters(500)
    if noteBox.SetTextInsets then
        noteBox:SetTextInsets(0, 0, 4, 4)
    end
    frame.noteBox = noteBox

    local continentLabel = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    continentLabel:SetPoint("TOPLEFT", routeName, "BOTTOMLEFT", 0, -18)
    continentLabel:SetText("Continent")
    frame.continentLabel = continentLabel

    frame.continentButtons = {}
    for index, continent in ipairs(CONTINENTS) do
        local button = MakeButton(frame, continent.label, 132, 24)
        button:SetPoint("TOPLEFT", continentLabel, "BOTTOMLEFT", (index - 1) * 142, -6)
        button:SetScript("OnClick", function()
            frame.selectedContinent = continent.id
            TEJ:RefreshRouteEditorChoices()
        end)
        frame.continentButtons[continent.id] = button
    end

    local difficultyLabel = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    difficultyLabel:SetPoint("TOPLEFT", continentLabel, "BOTTOMLEFT", 0, -44)
    difficultyLabel:SetText("Difficulty")
    frame.difficultyLabel = difficultyLabel

    frame.difficultyButtons = {}
    for index, difficulty in ipairs(DIFFICULTIES) do
        local button = MakeButton(frame, difficulty.label, 110, 24)
        button:SetPoint("TOPLEFT", difficultyLabel, "BOTTOMLEFT", (index - 1) * 118, -6)
        button:SetScript("OnClick", function()
            frame.selectedDifficulty = difficulty.id
            TEJ:RefreshRouteEditorChoices()
        end)
        frame.difficultyButtons[difficulty.id] = button
    end

    local save = MakeButton(frame, "Save", 88, 24)
    save:SetPoint("BOTTOMRIGHT", -112, 18)
    save:SetScript("OnClick", function()
        TEJ:SaveRouteEditor()
    end)
    frame.save = save

    local cancel = MakeButton(frame, "Cancel", 88, 24)
    cancel:SetPoint("LEFT", save, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.routeEditor = frame

    if UISpecialFrames then
        tinsert(UISpecialFrames, "TheExplorersJournalRouteEditor")
    end
end

function TEJ:RefreshRouteEditorChoices()
    local frame = self.routeEditor
    if not frame then
        return
    end

    for _, continent in ipairs(CONTINENTS) do
        local button = frame.continentButtons[continent.id]
        button:SetText((frame.selectedContinent == continent.id and "* " or "") .. continent.label)
    end

    for _, difficulty in ipairs(DIFFICULTIES) do
        local button = frame.difficultyButtons[difficulty.id]
        button:SetText((frame.selectedDifficulty == difficulty.id and "* " or "") .. difficulty.label)
    end
end

function TEJ:OpenRouteEditor()
    self:CreateRouteEditor()

    local frame = self.routeEditor
    frame.mode = "route"
    frame.selectedContinent = "eastern-kingdoms"
    frame.selectedDifficulty = "easy"
    frame.title:SetText("Create New Route")
    frame.routeName:SetText("")

    frame.routeNameLabel:Show()
    frame.routeName:Show()
    frame.continentLabel:Show()
    frame.difficultyLabel:Show()
    for _, button in pairs(frame.continentButtons) do button:Show() end
    for _, button in pairs(frame.difficultyButtons) do button:Show() end

    frame.waypointLabel:Hide()
    frame.waypointName:Hide()
    frame.noteLabel:Hide()
    frame.noteBox:Hide()

    self:RefreshRouteEditorChoices()
    frame:Show()
    frame.routeName:SetFocus()
end

function TEJ:OpenWaypointEditor()
    local route = self:GetActiveRoute()
    if not route then
        Print("Choose a route before adding a waypoint.")
        return
    end

    if not self:IsCustomRoute(route) then
        Print("Waypoints can be added to custom routes. Create or select a custom route first.")
        return
    end

    self:CreateRouteEditor()

    local frame = self.routeEditor
    frame.mode = "waypoint"
    frame.title:SetText("Add GPS Waypoint")
    frame.waypointName:SetText("")
    frame.noteBox:SetText("")

    frame.routeNameLabel:Hide()
    frame.routeName:Hide()
    frame.continentLabel:Hide()
    frame.difficultyLabel:Hide()
    for _, button in pairs(frame.continentButtons) do button:Hide() end
    for _, button in pairs(frame.difficultyButtons) do button:Hide() end

    frame.waypointLabel:Show()
    frame.waypointName:Show()
    frame.noteLabel:Show()
    frame.noteBox:Show()

    frame:Show()
    frame.waypointName:SetFocus()
end

function TEJ:SaveRouteEditor()
    local frame = self.routeEditor
    if not frame then
        return
    end

    if frame.mode == "route" then
        self:CreateCustomRoute(frame.routeName:GetText(), frame.selectedContinent, frame.selectedDifficulty)
    elseif frame.mode == "waypoint" then
        self:AddWaypointToActiveRoute(frame.waypointName:GetText(), frame.noteBox:GetText())
    end
end

function TEJ:CreateItemEditor()
    if self.itemEditor then
        return
    end

    local frame = CreatePanel("TheExplorersJournalItemEditor", UIParent)
    frame:SetSize(420, 180)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetPoint("CENTER")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    local title = MakeFont(frame, 16, { r = 1, g = 0.82, b = 0.42 })
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("Add Needed Item/Spell")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    frame.selectedEntryType = "item"

    local typeLabel = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    typeLabel:SetPoint("TOPLEFT", 22, -58)
    typeLabel:SetText("Type")

    local itemType = MakeButton(frame, "Item ID", 92, 24)
    itemType:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -6)
    itemType:SetScript("OnClick", function()
        frame.selectedEntryType = "item"
        TEJ:RefreshItemEditorType()
    end)
    frame.itemType = itemType

    local spellType = MakeButton(frame, "Spell ID", 92, 24)
    spellType:SetPoint("LEFT", itemType, "RIGHT", 8, 0)
    spellType:SetScript("OnClick", function()
        frame.selectedEntryType = "spell"
        TEJ:RefreshItemEditorType()
    end)
    frame.spellType = spellType

    local label = MakeFont(frame, 12, { r = 0.95, g = 0.83, b = 0.55 })
    label:SetPoint("TOPLEFT", itemType, "BOTTOMLEFT", 0, -14)
    label:SetText("Item link, item ID, or exact item name")
    frame.itemInputLabel = label

    local itemInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    itemInput:SetSize(360, 24)
    itemInput:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    itemInput:SetAutoFocus(false)
    frame.itemInput = itemInput

    local help = MakeFont(frame, 11, { r = 0.72, g = 0.72, b = 0.68 })
    help:SetPoint("TOPLEFT", itemInput, "BOTTOMLEFT", 0, -8)
    help:SetWidth(360)
    help:SetJustifyH("LEFT")
    help:SetText("Tip: switch to Spell ID before entering spell IDs.")
    frame.itemInputHelp = help

    local add = MakeButton(frame, "Add", 82, 24)
    add:SetPoint("BOTTOMRIGHT", -108, 18)
    add:SetScript("OnClick", function()
        TEJ:AddNeededItem(frame.itemInput:GetText(), frame.selectedEntryType)
    end)

    local cancel = MakeButton(frame, "Cancel", 82, 24)
    cancel:SetPoint("LEFT", add, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.itemEditor = frame
    if UISpecialFrames then
        tinsert(UISpecialFrames, "TheExplorersJournalItemEditor")
    end
end

function TEJ:OpenItemEditor()
    local route = self:GetActiveRoute()
    if not route then
        Print("Choose a route before adding an item.")
        return
    end

    self:CreateItemEditor()
    self.itemEditor.selectedEntryType = "item"
    self.itemEditor.itemInput:SetText("")
    self:RefreshItemEditorType()
    self.itemEditor:Show()
    self.itemEditor.itemInput:SetFocus()
end

function TEJ:RefreshItemEditorType()
    local frame = self.itemEditor
    if not frame then
        return
    end

    local isSpell = frame.selectedEntryType == "spell"
    frame.itemType:SetText(isSpell and "Item ID" or "* Item ID")
    frame.spellType:SetText(isSpell and "* Spell ID" or "Spell ID")

    if isSpell then
        frame.itemInputLabel:SetText("Spell link, spell ID, or exact spell name")
        frame.itemInputHelp:SetText("Spell IDs are resolved as spells. Links and exact spell names also work when available.")
    else
        frame.itemInputLabel:SetText("Item link, item ID, or exact item name")
        frame.itemInputHelp:SetText("Item IDs are resolved as items. Shift-click item links from bags/chat when possible.")
    end
end

function TEJ:CreateHUD()
    local hud = CreatePanel("TheExplorersJournalHUD", UIParent)
    hud:SetSize(292, 336)
    hud:SetFrameStrata("HIGH")
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetClampedToScreen(true)
    hud:SetScript("OnDragStart", function(self)
        if not TEJ.db.locked then
            self:StartMoving()
        end
    end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition(self, "hud")
    end)
    hud:SetScript("OnUpdate", function(_, elapsed)
        state.elapsed = state.elapsed + elapsed
        if state.elapsed >= UPDATE_INTERVAL then
            state.elapsed = 0
            TEJ:UpdateHUD()
        end
    end)

    local title = MakeFont(hud, 13, { r = 1, g = 0.82, b = 0.42 })
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetWidth(224)
    title:SetJustifyH("LEFT")
    title:SetText("No route loaded")
    hud.title = title

    local lock = MakeButton(hud, "L", 24, 22)
    lock:SetPoint("TOPRIGHT", -34, -8)
    lock:SetScript("OnClick", function()
        TEJ.db.locked = not TEJ.db.locked
        TEJ:Refresh()
    end)
    hud.lockButton = lock

    local close = MakeButton(hud, "X", 24, 22)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function()
        TEJ.db.hudVisible = false
        TEJ:Refresh()
    end)

    local meta = MakeFont(hud, 11, { r = 0.72, g = 0.72, b = 0.68 })
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    meta:SetWidth(266)
    meta:SetJustifyH("LEFT")
    meta:SetText("")
    hud.meta = meta

    local map = CreatePanel(nil, hud)
    map:SetPoint("TOP", 0, -54)
    map:SetSize(MAP_PANEL_SIZE, MAP_PANEL_SIZE)
    if map.SetBackdropColor then
        map:SetBackdropColor(0.025, 0.03, 0.035, 0.85)
    end
    hud.map = map

    local player = map:CreateTexture(nil, "OVERLAY")
    player:SetTexture("Interface\\Buttons\\WHITE8X8")
    player:SetVertexColor(0.45, 0.85, 1, 1)
    player:SetSize(10, 10)
    player:Hide()
    hud.player = player

    local arrowLine
    if hud.CreateLine then
        arrowLine = hud:CreateLine(nil, "OVERLAY")
        arrowLine:SetThickness(3)
        arrowLine:SetColorTexture(0.45, 0.85, 1, 0.95)
        hud.arrowLine = arrowLine
    end

    local nextText = MakeFont(hud, 12, { r = 0.9, g = 0.9, b = 0.84 })
    nextText:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -9)
    nextText:SetWidth(224)
    nextText:SetJustifyH("LEFT")
    nextText:SetText("")
    hud.nextText = nextText

    local direction = MakeFont(hud, 18, { r = 0.45, g = 0.85, b = 1 })
    direction:SetPoint("LEFT", nextText, "RIGHT", 8, 0)
    direction:SetWidth(44)
    direction:SetJustifyH("CENTER")
    direction:SetText("")
    hud.direction = direction

    self.hud = hud
    RestoreFramePosition(hud, "hud")
end

function TEJ:CreateWorldMapOverlay()
    if self.worldMapOverlay or not WorldMapFrame then
        return
    end

    local canvas = GetWorldMapCanvas()
    if not canvas then
        return
    end

    local overlay = CreateFrame("Frame", "TheExplorersJournalWorldMapOverlay", canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel((canvas.GetFrameLevel and canvas:GetFrameLevel() or 1) + 25)
    overlay:EnableMouse(false)
    overlay:SetScript("OnUpdate", function(_, elapsed)
        state.mapElapsed = state.mapElapsed + elapsed
        if state.mapElapsed >= UPDATE_INTERVAL then
            state.mapElapsed = 0
            TEJ:UpdateWorldMapOverlay()
        end
    end)

    if WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", function()
            TEJ:UpdateWorldMapOverlay()
        end)
        WorldMapFrame:HookScript("OnHide", function()
            TEJ:UpdateWorldMapOverlay()
        end)
    end

    self.worldMapOverlay = overlay

    local status = WorldMapFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", WorldMapFrame, "TOP", 0, -84)
    status:SetTextColor(1, 0.82, 0.34)
    status:SetShadowOffset(1, -1)
    status:Hide()
    self.worldMapStatus = status
end

function TEJ:CreateMinimapOverlay()
    if not Minimap then
        return
    end

    local overlay = CreateFrame("Frame", "TheExplorersJournalMinimapOverlay", Minimap)
    overlay:SetAllPoints(Minimap)
    overlay:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 8)
    overlay:EnableMouse(false)
    overlay:SetScript("OnUpdate", function()
        TEJ:UpdateMinimapOverlay()
    end)

    self.minimapOverlay = overlay
end

function TEJ:PositionMinimapButton()
    if not self.minimapButton or not self.db then
        return
    end

    local angle = math.rad(self.db.minimapButtonAngle or 225)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius

    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function TEJ:UpdateMinimapButtonDrag()
    if not self.minimapButton or not self.minimapButton.dragging then
        return
    end

    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    local angle = math.deg(Atan2(cursorY - centerY, cursorX - centerX))
    self.db.minimapButtonAngle = angle
    self:PositionMinimapButton()
end

function TEJ:CreateMinimapButton()
    if self.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "TheExplorersJournalMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 12)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetSize(31, 31)
    highlight:SetPoint("CENTER", button, "CENTER", 0, 0)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            TEJ.db.hudVisible = not TEJ.db.hudVisible
            TEJ:Refresh()
        else
            TEJ:ToggleMain()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ADDON_TITLE, 1, 0.82, 0.34)
        GameTooltip:AddLine("Left-click to open the journal.", 1, 1, 1)
        GameTooltip:AddLine("Right-click to toggle the HUD overlay.", 0.72, 0.72, 0.68)
        GameTooltip:AddLine("Drag to move this button.", 0.72, 0.72, 0.68)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
    end)
    button:SetScript("OnUpdate", function()
        TEJ:UpdateMinimapButtonDrag()
    end)

    self.minimapButton = button
    self:PositionMinimapButton()
end

function TEJ:EnsureRouteButton(index)
    if state.routeButtons[index] then
        return state.routeButtons[index]
    end

    local button = CreateFrame("Button", nil, self.main.routeList)
    button:SetSize(202, 24)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    button.text = text

    local largeText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    largeText:SetPoint("LEFT", 8, 0)
    largeText:SetPoint("RIGHT", -8, 0)
    largeText:SetJustifyH("LEFT")
    largeText:Hide()
    button.largeText = largeText

    state.routeButtons[index] = button
    return button
end

function TEJ:SetRouteButtonText(button, text, color, large)
    button.text:Hide()
    button.largeText:Hide()

    local fontString = large and button.largeText or button.text
    fontString:SetText(text)
    fontString:SetTextColor(color.r, color.g, color.b)
    fontString:Show()
end

function TEJ:RefreshRouteList()
    local routes = self:GetAllRoutes()
    local rowIndex = 1

    for _, continent in ipairs(CONTINENTS) do
        local continentHeader = self:EnsureRouteButton(rowIndex)
        local continentExpanded = self.db.expandedContinents[continent.id]

        continentHeader:SetPoint("TOPLEFT", 0, -((rowIndex - 1) * 28))
        self:SetRouteButtonText(continentHeader, (continentExpanded and "- " or "+ ") .. continent.label, { r = 1, g = 0.86, b = 0.48 }, true)
        continentHeader:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                return
            end

            TEJ.db.expandedContinents[continent.id] = not TEJ.db.expandedContinents[continent.id]
            TEJ:RefreshRouteList()
        end)
        continentHeader:SetScript("OnEnter", nil)
        continentHeader:SetScript("OnLeave", nil)
        continentHeader:Show()
        rowIndex = rowIndex + 1

        if continentExpanded then
            for _, difficulty in ipairs(DIFFICULTIES) do
                local header = self:EnsureRouteButton(rowIndex)
                local expanded = self.db.expandedDifficulties[continent.id][difficulty.id]

                header:SetPoint("TOPLEFT", 10, -((rowIndex - 1) * 28))
                self:SetRouteButtonText(header, (expanded and "- " or "+ ") .. difficulty.label, { r = 1, g = 0.82, b = 0.34 }, false)
                header:SetScript("OnClick", function(_, mouseButton)
                    if mouseButton == "RightButton" then
                        return
                    end

                    TEJ.db.expandedDifficulties[continent.id][difficulty.id] = not TEJ.db.expandedDifficulties[continent.id][difficulty.id]
                    TEJ:RefreshRouteList()
                end)
                header:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(difficulty.label, 1, 0.82, 0.34)
                    GameTooltip:AddLine(difficulty.description, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                header:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                header:Show()
                rowIndex = rowIndex + 1

                if expanded then
                    local hasRoutes = false
                    for _, route in ipairs(routes) do
                        if GetRouteContinent(route).id == continent.id and GetRouteDifficulty(route).id == difficulty.id then
                            local button = self:EnsureRouteButton(rowIndex)
                            button:SetPoint("TOPLEFT", 22, -((rowIndex - 1) * 28))
                            self:SetRouteButtonText(button, route.name, route.id == self.db.activeRouteID and { r = 0.45, g = 0.85, b = 1 } or { r = 0.95, g = 0.82, b = 0.5 }, false)
                            button:SetScript("OnClick", function(_, mouseButton)
                                if mouseButton == "RightButton" then
                                    TEJ:ConfirmDeleteRoute(route)
                                    return
                                end

                                TEJ:SetActiveRoute(route.id)
                            end)
                            button:SetScript("OnEnter", function(self)
                                if TEJ:IsCustomRoute(route) then
                                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                    GameTooltip:SetText(route.name, 1, 0.82, 0.34)
                                    GameTooltip:AddLine("Left-click to load this route.", 1, 1, 1, true)
                                    GameTooltip:AddLine("Right-click to delete this route.", 0.9, 0.35, 0.28, true)
                                    GameTooltip:Show()
                                end
                            end)
                            button:SetScript("OnLeave", function()
                                GameTooltip:Hide()
                            end)
                            button:Show()
                            hasRoutes = true
                            rowIndex = rowIndex + 1
                        end
                    end

                    if not hasRoutes then
                        local empty = self:EnsureRouteButton(rowIndex)
                        empty:SetPoint("TOPLEFT", 22, -((rowIndex - 1) * 28))
                        self:SetRouteButtonText(empty, "No routes yet", { r = 0.45, g = 0.45, b = 0.42 }, false)
                        empty:SetScript("OnClick", nil)
                        empty:SetScript("OnEnter", nil)
                        empty:SetScript("OnLeave", nil)
                        empty:Show()
                        rowIndex = rowIndex + 1
                    end
                end
            end
        end
    end

    for index = rowIndex, MAX_ROUTE_BUTTONS do
        local button = self:EnsureRouteButton(index)
        button:Hide()
        button.text:Hide()
        button.largeText:Hide()
        button:SetScript("OnClick", nil)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
    end

    self.main.routeList:SetHeight(math.max(392, (rowIndex - 1) * 28))
end

function TEJ:ShowWaypointTooltip(owner, route, waypoint, index)
    if not route or not waypoint then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(string.format("%02d. %s", index, waypoint.label or "Waypoint"), 1, 0.82, 0.34)
    GameTooltip:AddLine(string.format("%s (%s, %s)", GetMapName(GetWaypointMapID(route, waypoint)), FormatCoord(waypoint.x), FormatCoord(waypoint.y)), 0.72, 0.72, 0.68)
    GameTooltip:AddLine(waypoint.note or waypoint.label or "", 1, 1, 1, true)
    if self:IsCustomRoute(route) then
        GameTooltip:AddLine("Right-click to delete this waypoint.", 0.9, 0.35, 0.28)
    end
    GameTooltip:Show()
end

function TEJ:HideTooltip()
    GameTooltip:Hide()
end

function TEJ:ConfirmDeleteWaypoint(route, waypointIndex)
    if not route or not waypointIndex then
        return
    end

    if not self:IsCustomRoute(route) then
        Print("Built-in route waypoints cannot be deleted.")
        return
    end

    local waypoint = route.waypoints and route.waypoints[waypointIndex]
    if not waypoint then
        return
    end

    StaticPopup_Show("TEJ_DELETE_WAYPOINT", string.format("%02d. %s", waypointIndex, waypoint.label or "Waypoint"), nil, {
        routeID = route.id,
        index = waypointIndex,
    })
end

function TEJ:DeleteWaypoint(routeID, waypointIndex)
    local route = self:GetRouteByID(routeID)
    if not route or not self:IsCustomRoute(route) or not route.waypoints or not route.waypoints[waypointIndex] then
        return
    end

    local label = route.waypoints[waypointIndex].label or "Waypoint"
    table.remove(route.waypoints, waypointIndex)
    self:SetActiveRoute(route.id)
    Print("Deleted waypoint: " .. label)
end

function TEJ:ConfirmDeleteRoute(route)
    if not route then
        return
    end

    if not self:IsCustomRoute(route) then
        Print("Built-in routes cannot be deleted.")
        return
    end

    StaticPopup_Show("TEJ_DELETE_ROUTE", route.name or "this route", nil, {
        routeID = route.id,
    })
end

function TEJ:DeleteRoute(routeID)
    if not routeID then
        return
    end

    self.db.customRoutes = self.db.customRoutes or {}
    for index, route in ipairs(self.db.customRoutes) do
        if route.id == routeID then
            local name = route.name or "Route"
            table.remove(self.db.customRoutes, index)

            if self.db.routeItems then
                self.db.routeItems[routeID] = nil
            end

            if self.db.activeRouteID == routeID then
                self:SetActiveRoute(nil)
            else
                self:Refresh()
            end

            Print("Deleted route: " .. name)
            return
        end
    end
end

function TEJ:RefreshItems()
    local route = self:GetActiveRoute()
    local items = self:GetRouteItems(route)

    for index, row in ipairs(state.itemRows) do
        local item = items[index]
        if item then
            row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if item.type == "spell" and item.id and GameTooltip.SetSpellByID then
                    GameTooltip:SetSpellByID(item.id)
                elseif item.type == "spell" and item.link then
                    GameTooltip:SetHyperlink(item.link)
                elseif item.link then
                    GameTooltip:SetHyperlink(item.link)
                else
                    GameTooltip:SetText(item.name or "Needed Item/Spell", 1, 0.82, 0.34)
                end
                GameTooltip:AddLine("Right-click to remove from this route.", 0.9, 0.35, 0.28)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "RightButton" then
                    TEJ:RemoveNeededItem(route.id, index)
                end
            end)
            row:Show()
        else
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:SetScript("OnClick", nil)
            row:Hide()
        end
    end
end

function TEJ:AddNeededItem(input, entryType)
    local route = self:GetActiveRoute()
    if not route then
        Print("Choose a route before adding an item.")
        return
    end

    local item = ResolveNeededThing(input, entryType)
    if not item then
        if entryType == "spell" then
            Print("Spell not found. Try a spell link, spell ID, or exact spell name.")
        else
            Print("Item not found. Try an item link, item ID, or exact item name after the client has seen it.")
        end
        return
    end

    local items = self:GetRouteItems(route)
    table.insert(items, item)

    if self.itemEditor then
        self.itemEditor:Hide()
    end

    self:Refresh()
    Print("Added needed " .. (item.type or "entry") .. ": " .. (item.link or item.name))
end

function TEJ:RemoveNeededItem(routeID, itemIndex)
    local route = self:GetRouteByID(routeID)
    if not route then
        return
    end

    local items = self:GetRouteItems(route)
    local item = items[itemIndex]
    if not item then
        return
    end

    table.remove(items, itemIndex)
    self:Refresh()
    Print("Removed needed " .. (item.type or "entry") .. ": " .. (item.name or "entry"))
end

function TEJ:NormalizeSettings()
    self.db.routeItems = self.db.routeItems or {}
    self.db.expandedContinents = self.db.expandedContinents or {}
    for _, continent in ipairs(CONTINENTS) do
        if self.db.expandedContinents[continent.id] == nil then
            self.db.expandedContinents[continent.id] = continent.id == "eastern-kingdoms"
        end
    end

    local oldDifficulties = self.db.expandedDifficulties or {}
    if type(oldDifficulties.easy) == "boolean" then
        self.db.expandedDifficulties = {
            ["eastern-kingdoms"] = {
                easy = oldDifficulties.easy,
                intermediate = oldDifficulties.intermediate or false,
                advanced = oldDifficulties.advanced or false,
            },
            kalimdor = {
                easy = true,
                intermediate = false,
                advanced = false,
            },
        }
    end

    self.db.expandedDifficulties = self.db.expandedDifficulties or {}
    for _, continent in ipairs(CONTINENTS) do
        self.db.expandedDifficulties[continent.id] = self.db.expandedDifficulties[continent.id] or {}
        for _, difficulty in ipairs(DIFFICULTIES) do
            if self.db.expandedDifficulties[continent.id][difficulty.id] == nil then
                self.db.expandedDifficulties[continent.id][difficulty.id] = difficulty.id == "easy"
            end
        end
    end
end

function TEJ:RefreshDetails()
    local route = self:GetActiveRoute()

    if not route then
        self.main.detailTitle:SetText("No route selected")
        self.main.detailMeta:SetText("")
        self.main.detailText:SetText("Select a route on the left, then load its overlay.")
        self:RefreshItems()
        for _, row in ipairs(state.waypointRows) do
            row.text:SetText("")
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:Hide()
        end
        return
    end

    self.main.detailTitle:SetText(route.name)
    self.main.detailMeta:SetText(string.format("%s - %s - %d waypoints", GetRouteDifficulty(route).label, GetRouteMapSummary(route), #(route.waypoints or {})))
    self.main.detailText:SetText(route.description or "")
    self:RefreshItems()

    local offsetY = 0
    for index, row in ipairs(state.waypointRows) do
        local waypoint = route.waypoints and route.waypoints[index]
        if waypoint then
            local note = waypoint.note or waypoint.label or ""
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.main.waypointList, "TOPLEFT", 0, -offsetY)
            row.text:SetText(string.format("%02d. %s - %s (%s, %s)\n%s", index, waypoint.label or "Waypoint", GetMapName(GetWaypointMapID(route, waypoint)), FormatCoord(waypoint.x), FormatCoord(waypoint.y), note))
            row:SetHeight(row.text:GetStringHeight() + 4)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "RightButton" then
                    TEJ:ConfirmDeleteWaypoint(route, index)
                end
            end)
            row:SetScript("OnEnter", function(self)
                TEJ:ShowWaypointTooltip(self, route, waypoint, index)
            end)
            row:SetScript("OnLeave", function()
                TEJ:HideTooltip()
            end)
            row:Show()
            offsetY = offsetY + row.text:GetStringHeight() + 12
        elseif index == #state.waypointRows and route.waypoints and #route.waypoints > #state.waypointRows then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.main.waypointList, "TOPLEFT", 0, -offsetY)
            row.text:SetText("More waypoints are defined than this panel can show.")
            row:SetScript("OnClick", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:Show()
            offsetY = offsetY + row.text:GetStringHeight() + 12
        else
            row.text:SetText("")
            row:SetScript("OnClick", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
            row:Hide()
        end
    end

    self.main.waypointList:SetHeight(math.max(276, offsetY + 8))
end

function TEJ:EnsurePin(index)
    if state.hudPins[index] then
        return state.hudPins[index]
    end

    local pin = self.hud.map:CreateTexture(nil, "ARTWORK")
    pin:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    pin:SetSize(13, 13)
    state.hudPins[index] = pin
    return pin
end

function TEJ:EnsureLine(index)
    if state.hudLines[index] then
        return state.hudLines[index]
    end

    if not self.hud.map.CreateLine then
        return nil
    end

    local line = self.hud.map:CreateLine(nil, "BACKGROUND")
    line:SetThickness(2)
    line:SetColorTexture(1, 0.82, 0.34, 0.72)
    state.hudLines[index] = line
    return line
end

function TEJ:EnsureWorldMapPin(index)
    if state.worldMapPins[index] then
        return state.worldMapPins[index]
    end

    local pin = CreateFrame("Button", nil, self.worldMapOverlay)
    pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(pin)
    icon:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    pin.icon = icon

    pin:SetAlpha(0.92)
    state.worldMapPins[index] = pin
    return pin
end

function TEJ:EnsureWorldMapLine(index)
    if state.worldMapLines[index] then
        return state.worldMapLines[index]
    end

    if not self.worldMapOverlay or not self.worldMapOverlay.CreateLine then
        return nil
    end

    local line = self.worldMapOverlay:CreateLine(nil, "ARTWORK")
    line:SetThickness(5)
    line:SetColorTexture(0.95, 0.68, 0.24, 0.78)
    state.worldMapLines[index] = line
    return line
end

function TEJ:EnsureWorldMapLabel(index)
    if state.worldMapLabels[index] then
        return state.worldMapLabels[index]
    end

    local label = self.worldMapOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetTextColor(1, 0.94, 0.72)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    state.worldMapLabels[index] = label
    return label
end

function TEJ:EnsureMinimapPin(index)
    if state.minimapPins[index] then
        return state.minimapPins[index]
    end

    local pin = CreateFrame("Button", nil, self.minimapOverlay)
    pin:EnableMouse(true)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(pin)
    icon:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    pin.icon = icon

    pin:SetAlpha(0.92)
    state.minimapPins[index] = pin
    return pin
end

function TEJ:EnsureMinimapLine(index)
    if state.minimapLines[index] then
        return state.minimapLines[index]
    end

    if not self.minimapOverlay or not self.minimapOverlay.CreateLine then
        return nil
    end

    local line = self.minimapOverlay:CreateLine(nil, "ARTWORK")
    line:SetThickness(3)
    line:SetColorTexture(0.95, 0.68, 0.24, 0.9)
    state.minimapLines[index] = line
    return line
end

function TEJ:EnsureMinimapLabel(index)
    if state.minimapLabels[index] then
        return state.minimapLabels[index]
    end

    local label = self.minimapOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetTextColor(1, 0.94, 0.72)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    state.minimapLabels[index] = label
    return label
end

function TEJ:HideWorldMapOverlay()
    for _, pin in pairs(state.worldMapPins) do
        pin:Hide()
    end

    for _, line in pairs(state.worldMapLines) do
        line:Hide()
    end

    for _, label in pairs(state.worldMapLabels) do
        label:Hide()
    end
end

function TEJ:HideMinimapOverlay()
    for _, pin in pairs(state.minimapPins) do
        pin:Hide()
    end

    for _, line in pairs(state.minimapLines) do
        line:Hide()
    end

    for _, label in pairs(state.minimapLabels) do
        label:Hide()
    end
end

function TEJ:WaypointToPanel(x, y)
    local inset = 12
    local usable = MAP_PANEL_SIZE - (inset * 2)
    return inset + (x * usable), -inset - (y * usable)
end

function TEJ:DrawRouteMap(route, playerMapID, playerX, playerY, nextIndex)
    for _, pin in pairs(state.hudPins) do
        pin:Hide()
    end

    for _, line in pairs(state.hudLines) do
        line:Hide()
    end

    if not route or not route.waypoints then
        self.hud.player:Hide()
        return
    end

    local drawMapID = RouteHasMap(route, playerMapID) and playerMapID or route.mapID
    local firstMapIndex, lastMapIndex = GetRouteMapBounds(route, drawMapID)

    for index, waypoint in ipairs(route.waypoints) do
        if GetWaypointMapID(route, waypoint) == drawMapID then
        local pin = self:EnsurePin(index)
        local px, py = self:WaypointToPanel(waypoint.x, waypoint.y)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", self.hud.map, "TOPLEFT", px, py)
        if index == firstMapIndex then
            pin:SetVertexColor(0.2, 1, 0.35, 1)
            pin:SetSize(14, 14)
        elseif index == lastMapIndex then
            pin:SetVertexColor(1, 0.24, 0.2, 1)
            pin:SetSize(14, 14)
        elseif index == nextIndex then
            pin:SetVertexColor(0.45, 0.85, 1, 1)
            pin:SetSize(16, 16)
        else
            pin:SetVertexColor(1, 0.82, 0.34, 0.9)
            pin:SetSize(13, 13)
        end
        pin:Show()

        local previous = route.waypoints[index - 1]
        if previous and GetWaypointMapID(route, previous) == drawMapID then
            local line = self:EnsureLine(index - 1)
            if line then
                local ax, ay = self:WaypointToPanel(previous.x, previous.y)
                line:ClearAllPoints()
                line:SetStartPoint("TOPLEFT", self.hud.map, ax, ay)
                line:SetEndPoint("TOPLEFT", self.hud.map, px, py)
                line:Show()
            end
        end
        end
    end

    if RouteHasMap(route, playerMapID) and playerX and playerY then
        local px, py = self:WaypointToPanel(playerX, playerY)
        self.hud.player:ClearAllPoints()
        self.hud.player:SetPoint("CENTER", self.hud.map, "TOPLEFT", px, py)
        self.hud.player:Show()
    else
        self.hud.player:Hide()
    end
end

function TEJ:UpdateWorldMapOverlay()
    if not self.worldMapOverlay then
        self:CreateWorldMapOverlay()
    end

    if not self.worldMapOverlay or not WorldMapFrame then
        return
    end

    local canvas = GetWorldMapCanvas()
    if canvas and self.worldMapOverlay:GetParent() ~= canvas then
        self.worldMapOverlay:SetParent(canvas)
        self.worldMapOverlay:ClearAllPoints()
        self.worldMapOverlay:SetAllPoints(canvas)
    end

    local route = self:GetActiveRoute()
    local mapID = GetWorldMapID()

    if self.worldMapStatus then
        self.worldMapStatus:Hide()
    end

    if not self.db.worldMapVisible or not route or not route.waypoints or not WorldMapFrame:IsShown() then
        self:HideWorldMapOverlay()
        return
    end

    if not RouteHasMap(route, mapID) then
        self:HideWorldMapOverlay()
        if self.worldMapStatus then
            self.worldMapStatus:SetText(string.format("TEJ: active route is for %s. Open one of those zone maps to show the path.", GetRouteMapSummary(route)))
            self.worldMapStatus:Show()
        end
        return
    end

    local width = self.worldMapOverlay:GetWidth()
    local height = self.worldMapOverlay:GetHeight()
    if not width or width <= 0 or not height or height <= 0 then
        self:HideWorldMapOverlay()
        if self.worldMapStatus then
            self.worldMapStatus:SetText("TEJ: waiting for the World Map canvas...")
            self.worldMapStatus:Show()
        end
        return
    end

    local playerMapID, playerX, playerY = GetPlayerPosition()
    local nextIndex
    if RouteHasMap(route, playerMapID) then
        _, nextIndex = self:FindNextWaypoint(route, playerMapID, playerX, playerY)
    end

    self:HideWorldMapOverlay()
    self.worldMapOverlay:Show()

    if self.worldMapStatus then
        self.worldMapStatus:SetText("TEJ: showing " .. route.name)
        self.worldMapStatus:Show()
    end

    local firstMapIndex, lastMapIndex = GetRouteMapBounds(route, mapID)

    for index, waypoint in ipairs(route.waypoints) do
        if GetWaypointMapID(route, waypoint) == mapID then
        local x = waypoint.x * width
        local y = -(waypoint.y * height)
        local pin = self:EnsureWorldMapPin(index)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", self.worldMapOverlay, "TOPLEFT", x, y)

        if index == firstMapIndex then
            pin.icon:SetVertexColor(0.28, 0.78, 0.24, 0.95)
            pin:SetSize(22, 22)
        elseif index == lastMapIndex then
            pin.icon:SetVertexColor(0.78, 0.18, 0.12, 0.95)
            pin:SetSize(22, 22)
        elseif index == nextIndex then
            pin.icon:SetVertexColor(0.36, 0.72, 1, 1)
            pin:SetSize(23, 23)
        else
            pin.icon:SetVertexColor(0.92, 0.66, 0.24, 0.92)
            pin:SetSize(19, 19)
        end
        local tooltipRoute, tooltipWaypoint, tooltipIndex = route, waypoint, index
        pin:SetScript("OnEnter", function(self)
            TEJ:ShowWaypointTooltip(self, tooltipRoute, tooltipWaypoint, tooltipIndex)
        end)
        pin:SetScript("OnLeave", function()
            TEJ:HideTooltip()
        end)
        pin:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                TEJ:ConfirmDeleteWaypoint(tooltipRoute, tooltipIndex)
            end
        end)
        pin:Show()

        local label = self:EnsureWorldMapLabel(index)
        label:ClearAllPoints()
        label:SetPoint("CENTER", pin, "CENTER", 0, 0)
        label:SetText(FormatWaypointNumber(index))
        label:SetTextColor(1, 0.94, 0.72)
        label:Show()

        local previous = route.waypoints[index - 1]
        if previous and GetWaypointMapID(route, previous) == mapID then
            local line = self:EnsureWorldMapLine(index - 1)
            if line then
                line:ClearAllPoints()
                line:SetStartPoint("TOPLEFT", self.worldMapOverlay, previous.x * width, -(previous.y * height))
                line:SetEndPoint("TOPLEFT", self.worldMapOverlay, x, y)
                line:Show()
            end
        end
        end
    end
end

function TEJ:RotateMinimapPoint(x, y)
    if not GetCVar or GetCVar("rotateMinimap") ~= "1" then
        return x, y
    end

    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    local cosFacing = math.cos(facing)
    local sinFacing = math.sin(facing)

    return (x * cosFacing) - (y * sinFacing), (x * sinFacing) + (y * cosFacing)
end

function TEJ:UpdateMinimapOverlay()
    if not self.minimapOverlay or not Minimap then
        return
    end

    local route = self:GetActiveRoute()
    local playerMapID, playerX, playerY = GetPlayerPosition()

    if not self.db.minimapVisible or not route or not route.waypoints or not RouteHasMap(route, playerMapID) or not playerX then
        self:HideMinimapOverlay()
        return
    end

    local width = self.minimapOverlay:GetWidth()
    local height = self.minimapOverlay:GetHeight()
    local radius = math.min(width or 0, height or 0) * 0.48
    if radius <= 0 then
        self:HideMinimapOverlay()
        return
    end

    local _, nextIndex = self:FindNextWaypoint(route, playerMapID, playerX, playerY)
    local visiblePoints = {}
    local firstMapIndex, lastMapIndex = GetRouteMapBounds(route, playerMapID)

    self:HideMinimapOverlay()
    self.minimapOverlay:Show()

    for index, waypoint in ipairs(route.waypoints) do
        if GetWaypointMapID(route, waypoint) == playerMapID then
        local dx = (waypoint.x - playerX) * MINIMAP_ROUTE_SCALE
        local dy = (playerY - waypoint.y) * MINIMAP_ROUTE_SCALE
        dx, dy = self:RotateMinimapPoint(dx, dy)

        local distance = math.sqrt((dx * dx) + (dy * dy))
        local drawX, drawY = dx, dy
        local clamped = false

        if distance > radius then
            local clampScale = radius / distance
            drawX = dx * clampScale
            drawY = dy * clampScale
            clamped = true
        end

        visiblePoints[index] = { x = drawX, y = drawY, clamped = clamped }

        if not clamped or index == firstMapIndex or index == lastMapIndex or index == nextIndex then
            local pin = self:EnsureMinimapPin(index)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", self.minimapOverlay, "CENTER", drawX, drawY)

            if index == firstMapIndex then
                pin.icon:SetVertexColor(0.28, 0.78, 0.24, 0.95)
                pin:SetSize(16, 16)
            elseif index == lastMapIndex then
                pin.icon:SetVertexColor(0.78, 0.18, 0.12, 0.95)
                pin:SetSize(16, 16)
            elseif index == nextIndex then
                pin.icon:SetVertexColor(0.36, 0.72, 1, 1)
                pin:SetSize(17, 17)
            else
                pin.icon:SetVertexColor(0.92, 0.66, 0.24, 0.9)
                pin:SetSize(14, 14)
            end
            local tooltipRoute, tooltipWaypoint, tooltipIndex = route, waypoint, index
            pin:SetScript("OnEnter", function(self)
                TEJ:ShowWaypointTooltip(self, tooltipRoute, tooltipWaypoint, tooltipIndex)
            end)
            pin:SetScript("OnLeave", function()
                TEJ:HideTooltip()
            end)
            pin:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "RightButton" then
                    TEJ:ConfirmDeleteWaypoint(tooltipRoute, tooltipIndex)
                end
            end)
            pin:Show()

            local label = self:EnsureMinimapLabel(index)
            label:ClearAllPoints()
            label:SetPoint("CENTER", pin, "CENTER", 0, 0)
            label:SetText(FormatWaypointNumber(index))
            label:SetTextColor(1, 0.94, 0.72)
            label:Show()
        end
        end
    end

    for index = 2, #route.waypoints do
        local currentWaypoint = route.waypoints[index]
        local previousWaypoint = route.waypoints[index - 1]
        if currentWaypoint and previousWaypoint and GetWaypointMapID(route, currentWaypoint) == playerMapID and GetWaypointMapID(route, previousWaypoint) == playerMapID then
        local previous = visiblePoints[index - 1]
        local current = visiblePoints[index]
        if previous and current and (not previous.clamped or not current.clamped or index == nextIndex or index - 1 == nextIndex) then
            local line = self:EnsureMinimapLine(index - 1)
            if line then
                line:ClearAllPoints()
                line:SetStartPoint("CENTER", self.minimapOverlay, previous.x, previous.y)
                line:SetEndPoint("CENTER", self.minimapOverlay, current.x, current.y)
                local activeSegment = index == nextIndex or index - 1 == nextIndex
                if activeSegment then
                    line:SetColorTexture(0.45, 0.85, 1, 0.92)
                else
                    line:SetColorTexture(1, 0.82, 0.34, 0.88)
                end
                line:Show()
            end
        end
        end
    end
end

function TEJ:UpdateHUD()
    if not self.hud or not self.hud:IsShown() then
        return
    end

    local route = self:GetActiveRoute()
    local playerMapID, playerX, playerY = GetPlayerPosition()

    if not route then
        self.hud.title:SetText("No route loaded")
        self.hud.meta:SetText("Open /tej and choose a path.")
        self.hud.nextText:SetText("")
        self.hud.direction:SetText("")
        if self.hud.arrowLine then
            self.hud.arrowLine:Hide()
        end
        self:DrawRouteMap(nil)
        return
    end

    if not route.waypoints or #route.waypoints == 0 then
        self.hud.title:SetText(route.name)
        self.hud.meta:SetText(GetRouteMapSummary(route))
        self.hud.nextText:SetText("Add a GPS waypoint to begin this route.")
        self.hud.direction:SetText("")
        if self.hud.arrowLine then
            self.hud.arrowLine:Hide()
        end
        self:DrawRouteMap(nil)
        return
    end

    local nextWaypoint, nextIndex = nil, nil
    if RouteHasMap(route, playerMapID) then
        nextWaypoint, nextIndex = self:FindNextWaypoint(route, playerMapID, playerX, playerY)
    else
        nextWaypoint = route.waypoints and route.waypoints[1]
        nextIndex = 1
    end

    self.hud.title:SetText(route.name)
    self.hud.meta:SetText(GetRouteMapSummary(route))
    self:DrawRouteMap(route, playerMapID, playerX, playerY, nextIndex)

    if not RouteHasMap(route, playerMapID) then
        self.hud.nextText:SetText("Travel to " .. GetRouteMapSummary(route))
        self.hud.direction:SetText("")
        if self.hud.arrowLine then
            self.hud.arrowLine:Hide()
        end
        return
    end

    if not nextWaypoint then
        self.hud.nextText:SetText("Route has no waypoints.")
        self.hud.direction:SetText("")
        if self.hud.arrowLine then
            self.hud.arrowLine:Hide()
        end
        return
    end

    if GetWaypointMapID(route, nextWaypoint) ~= playerMapID then
        self.hud.nextText:SetText(string.format("%02d. Continue into %s", nextIndex, GetMapName(GetWaypointMapID(route, nextWaypoint))))
        self.hud.direction:SetText("")
        if self.hud.arrowLine then
            self.hud.arrowLine:Hide()
        end
        return
    end

    local dx = nextWaypoint.x - playerX
    local dy = nextWaypoint.y - playerY
    local direction, degrees = BearingLabel(dx, dy)
    local distance = math.sqrt(DistanceSquared(playerX, playerY, nextWaypoint.x, nextWaypoint.y)) * 100

    self.hud.nextText:SetText(string.format("%02d. %s\n%s%% zone distance", nextIndex, nextWaypoint.label or "Waypoint", string.format("%.1f", distance)))
    self.hud.direction:SetText(direction)

    if self.hud.arrowLine then
        local centerX, centerY = 252, -292
        local length = 30
        local radians = math.rad(degrees - 90)
        self.hud.arrowLine:ClearAllPoints()
        self.hud.arrowLine:SetStartPoint("TOPLEFT", self.hud, centerX, centerY)
        self.hud.arrowLine:SetEndPoint("TOPLEFT", self.hud, centerX + math.cos(radians) * length, centerY + math.sin(radians) * length)
        self.hud.arrowLine:Show()
    end
end

function TEJ:Refresh()
    if not self.main or not self.hud then
        return
    end

    self:RefreshRouteList()
    self:RefreshDetails()

    self.hud.lockButton:SetText(self.db.locked and "U" or "L")
    self.hud:SetScale(self.db.scale or 1)

    if self.db.hudVisible and self:GetActiveRoute() then
        self.hud:Show()
    else
        self.hud:Hide()
    end

    self:UpdateHUD()
    self:UpdateWorldMapOverlay()
    self:UpdateMinimapOverlay()
end

function TEJ:ToggleMain()
    if self.main:IsShown() then
        self.main:Hide()
    else
        self.main:Show()
        self:Refresh()
    end
end

function TEJ:PrintPosition()
    local mapID, x, y = GetPlayerPosition()
    if not mapID then
        Print("No player map position is available here.")
        return
    end

    Print(string.format("%s mapID=%d x=%.4f y=%.4f", GetMapName(mapID), mapID, x, y))
end

function TEJ:CreateCustomRoute(name, continentID, difficultyID)
    name = Trim(name)
    if name == "" then
        Print("Enter a route name.")
        return
    end

    local continent = GetContinentInfo(continentID)
    local difficulty = GetDifficultyInfo(difficultyID)
    local route = {
        id = self:MakeUniqueRouteID(name),
        name = name,
        category = "Custom",
        continent = continent.id,
        difficulty = difficulty.id,
        description = "",
        waypoints = {},
    }

    table.insert(self.db.customRoutes, route)
    self.db.expandedContinents[continent.id] = true
    self.db.expandedDifficulties[continent.id][difficulty.id] = true
    self:SetActiveRoute(route.id)

    if self.routeEditor then
        self.routeEditor:Hide()
    end

    Print("Created route: " .. route.name)
end

function TEJ:AddWaypointToActiveRoute(label, note)
    local route = self:GetActiveRoute()
    if not route then
        Print("Choose a route before adding a waypoint.")
        return
    end

    if not self:IsCustomRoute(route) then
        Print("Waypoints can be added to custom routes. Create or select a custom route first.")
        return
    end

    local mapID, x, y = GetPlayerPosition()
    if not mapID then
        Print("No player map position is available here.")
        return
    end

    label = Trim(label)
    note = Trim(note)
    if label == "" then
        label = "Waypoint " .. tostring(#(route.waypoints or {}) + 1)
    end

    route.mapID = route.mapID or mapID
    route.waypoints = route.waypoints or {}
    table.insert(route.waypoints, {
        mapID = mapID,
        x = x,
        y = y,
        label = label,
        note = note,
    })

    if self.routeEditor then
        self.routeEditor:Hide()
    end

    self:SetActiveRoute(route.id)
    Print(string.format("Added %s at %s %.4f, %.4f.", label, GetMapName(mapID), x, y))
end

function TEJ:AddCustomWaypoint(label)
    local mapID, x, y = GetPlayerPosition()
    if not mapID then
        Print("No player map position is available here.")
        return
    end

    label = Trim(label)
    if label == "" then
        label = "Waypoint " .. date("%H:%M")
    end

    local routeID = "custom-" .. tostring(mapID)
    local route

    for _, existing in ipairs(self.db.customRoutes) do
        if existing.id == routeID then
            route = existing
            break
        end
    end

    if not route then
        route = {
            id = routeID,
            name = GetMapName(mapID) .. " Scout Notes",
            category = "Custom",
            continent = "eastern-kingdoms",
            difficulty = "easy",
            mapID = mapID,
            description = "Waypoints captured with /tej add.",
            waypoints = {},
        }
        table.insert(self.db.customRoutes, route)
    end

    table.insert(route.waypoints, { x = x, y = y, label = label })
    self:SetActiveRoute(route.id)
    Print(string.format("Added %s at %.4f, %.4f.", label, x, y))
end

function TEJ:ExportActiveRoute()
    local route = self:GetActiveRoute()
    if not route then
        Print("Choose a route before exporting.")
        return
    end

    Print("Route export for " .. route.name .. ":")
    Print(string.format("{ id = %q, name = %q, category = %q, mapID = %d, waypoints = {", route.id, route.name, route.category or "Custom", route.mapID or 0))
    for _, waypoint in ipairs(route.waypoints or {}) do
        Print(string.format("  { mapID = %d, x = %.4f, y = %.4f, label = %q, note = %q },", GetWaypointMapID(route, waypoint), waypoint.x, waypoint.y, waypoint.label or "Waypoint", waypoint.note or waypoint.label or ""))
    end
    Print("} }")
end

function TEJ:OpenActiveRouteMap()
    local route = self:GetActiveRoute()
    if not route then
        Print("Choose a route before opening its map.")
        return
    end

    if C_Map and C_Map.OpenWorldMap then
        C_Map.OpenWorldMap(route.mapID)
    elseif WorldMapFrame then
        ShowUIPanel(WorldMapFrame)
        if WorldMapFrame.SetMapID then
            WorldMapFrame:SetMapID(route.mapID)
        end
    end

    self:UpdateWorldMapOverlay()
end

function TEJ:PrintOverlayStatus()
    local route = self:GetActiveRoute()
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local worldMapID = GetWorldMapID()

    Print("Overlay status:")
    Print("Route: " .. (route and string.format("%s mapID=%s", route.name, tostring(route.mapID)) or "none"))
    Print("Player mapID: " .. tostring(playerMapID))
    Print("World mapID: " .. tostring(worldMapID))
    Print("World map overlay: " .. tostring(self.worldMapOverlay ~= nil))
    Print("Minimap overlay: " .. tostring(self.minimapOverlay ~= nil))
    Print("Map layer enabled: " .. tostring(self.db.worldMapVisible))
    Print("Minimap layer enabled: " .. tostring(self.db.minimapVisible))
end

function TEJ:HandleSlash(input)
    input = input or ""
    local command, rest = input:match("^(%S*)%s*(.-)$")
    command = string.lower(command or "")

    if command == "" or command == "show" or command == "open" then
        self:ToggleMain()
    elseif command == "hide" then
        self.main:Hide()
    elseif command == "hud" then
        self.db.hudVisible = not self.db.hudVisible
        self:Refresh()
    elseif command == "map" then
        self.db.worldMapVisible = not self.db.worldMapVisible
        self:Refresh()
    elseif command == "openmap" then
        self:OpenActiveRouteMap()
    elseif command == "status" then
        self:PrintOverlayStatus()
    elseif command == "minimap" or command == "mini" then
        self.db.minimapVisible = not self.db.minimapVisible
        self:Refresh()
    elseif command == "pos" then
        self:PrintPosition()
    elseif command == "add" then
        self:AddCustomWaypoint(rest)
    elseif command == "export" then
        self:ExportActiveRoute()
    elseif command == "clear" then
        self:SetActiveRoute(nil)
    elseif command == "reset" then
        self.db.positions = CopyDefaults(defaults.positions, {})
        RestoreFramePosition(self.main, "main")
        RestoreFramePosition(self.hud, "hud")
        self:Refresh()
    else
        Print("/tej - open journal")
        Print("/tej pos - print current map coordinates")
        Print("/tej add <label> - add current position to custom route")
        Print("/tej export - print active route as Lua data")
        Print("/tej hud - toggle overlay")
        Print("/tej map - toggle world map route")
        Print("/tej minimap - toggle minimap route")
        Print("/tej openmap - open the active route's zone map")
        Print("/tej status - print overlay diagnostics")
    end
end

function TEJ:Initialize()
    TheExplorersJournalDB = CopyDefaults(defaults, TheExplorersJournalDB)
    self.db = TheExplorersJournalDB
    self:NormalizeSettings()

    self:CreateMainFrame()
    self:CreateHUD()
    self:CreateMinimapOverlay()
    self:CreateMinimapButton()
    self:CreateWorldMapOverlay()

    SLASH_THEEXPLORERSJOURNAL1 = "/tej"
    SLASH_THEEXPLORERSJOURNAL2 = "/explorersjournal"
    SlashCmdList.THEEXPLORERSJOURNAL = function(input)
        TEJ:HandleSlash(input)
    end

    if self.db.mainVisible then
        self.main:Show()
    else
        self.main:Hide()
    end

    self:Refresh()
    Print("Loaded. Type /tej to open the journal.")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" then
        TEJ:Initialize()
    elseif event == "ADDON_LOADED" and addon == "Blizzard_WorldMap" and TEJ.db then
        TEJ:CreateWorldMapOverlay()
        TEJ:UpdateWorldMapOverlay()
    end
end)
