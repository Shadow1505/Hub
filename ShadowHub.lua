local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MaterialService = game:GetService("MaterialService")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ========================================================
-- 1. CONFIG SYSTEM & ANTI-DC RESET
-- ========================================================
local ConfigFileName = "ShadowHub_Config.json"
local UI_Updaters = {}

local DefaultConfig = {
    AutoTP = false,
    AutoFishingToggle = false,
    SelectedFarmingMode = "Map 1 (Rotate)",
    AutoRotate = false,
    AutoMap2 = false,
    AutoDualMap = false,
    FPSBooster = false,
    ClayPotato = false,
    Disable3D = false,
    ClearWater = false,
    Limit30FPS = false,
    AutoRAM = false,
    AntiAFK = true,
    WebhookURL = "",
    WebhookPlayer = false,
    WebhookJoinLeave = false,
    UISizeX = 520,
    UISizeY = 320,
    AutoTeleportSpawn = false -- [UPDATE]: Added new config for Auto Teleport
}

local ConfigData = {}
for k, v in pairs(DefaultConfig) do ConfigData[k] = v end

local function SaveConfig()
    if writefile then
        pcall(function() writefile(ConfigFileName, HttpService:JSONEncode(ConfigData)) end)
    end
end

local function LoadConfig()
    if isfile and isfile(ConfigFileName) and readfile then
        pcall(function()
            local decoded = HttpService:JSONDecode(readfile(ConfigFileName))
            for k, v in pairs(decoded) do ConfigData[k] = v end
        end)
    end
end

local function ResetConfig()
    for k, v in pairs(DefaultConfig) do 
        ConfigData[k] = v 
        if UI_Updaters[k] then UI_Updaters[k](v) end
    end
    SaveConfig()
end

LoadConfig()

-- ========================================================
-- 2. DATA KOORDINAT, DETEKSI MAP & HELPERS
-- ========================================================
local spotKordinat = {
    Board = CFrame.lookAt(Vector3.new(-855.63, 44.43, 5187.01), Vector3.new(-855.63, 44.43, 5187.01) + Vector3.new(0, 0, 1)),
    Volcano = CFrame.lookAt(Vector3.new(-813.46, 59.37, 5271.69), Vector3.new(-813.46, 59.37, 5271.69) + Vector3.new(1, 0, 1)),
    Storm = CFrame.lookAt(Vector3.new(-864.27, 56.06, 5309.37), Vector3.new(-864.27, 56.06, 5309.37) + Vector3.new(-1, 0, 1)),
    Blizzard = CFrame.lookAt(Vector3.new(-968.19, 45.83, 5345.58), Vector3.new(-968.19, 45.83, 5345.58) + Vector3.new(-1, 0, -1))
}
local DatabaseIconCuaca = {["118379404229807"] = "Blizzard", ["105076841543450"] = "Storm", ["76632496002371"] = "Volcano"}
local posisiSimpanan = nil

local standPositionRot = Vector3.new(-1290.24, -855.68, 5596.16)
local poolAngles = {-103.43, 135.57, 15.08}
local currentPoolIndex = 1

local map2Pos = Vector3.new(-4014.58, -543.00, 564.95)
local map2Degree = 46.85
local map2CFrame = CFrame.new(map2Pos) * CFrame.Angles(0, math.rad(map2Degree), 0)

-- Timer Updated: 58 Menit Total & 3x Rotate
local rotateInterval = 1160
local dualMapInterval = 3480

local function GetEventScheduleWIB()
    local utc_time = os.time()
    local wib_time = utc_time + (7 * 3600)
    local date = os.date("!*t", wib_time)
    local h = date.hour; local m = date.min; local s = date.sec
    
    if h % 3 == 1 then
        local sisaDetik = 3600 - ((m * 60) + s)
        return { state = "ACTIVE", timeLeft = sisaDetik }
    else
        local nextHour = h + 1
        while nextHour % 3 ~= 1 do nextHour = nextHour + 1 end
        local jamSisa = nextHour - h - 1; local menitSisa = 59 - m; local detikSisa = 60 - s
        return { state = "COOLDOWN", timeLeft = (jamSisa * 3600) + (menitSisa * 60) + detikSisa }
    end
end

local function formatSecondsToText(seconds)
    local h = math.floor(seconds / 3600); local m = math.floor((seconds % 3600) / 60); local s = seconds % 60
    if h > 0 then return string.format("%02dh %02dm %02ds", h, m, s) else return string.format("%02dm %02ds", m, s) end
end

local function GetWeatherIconOnly()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local boardPos = spotKordinat.Board.Position
    
    for _, gui in ipairs(workspace:GetDescendants()) do
        if gui:IsA("SurfaceGui") then
            local part = gui.Parent
            if gui.Adornee then part = gui.Adornee end
            if part and part:IsA("BasePart") then
                if (part.Position - boardPos).Magnitude <= 10 then
                    for _, obj in ipairs(gui:GetDescendants()) do
                        if (obj:IsA("ImageLabel") or obj:IsA("ImageButton") or obj:IsA("Decal") or obj:IsA("Texture")) then
                            local img = (obj:IsA("Decal") or obj:IsA("Texture")) and tostring(obj.Texture) or tostring(obj.Image)
                            local pureId = string.match(img, "%d+")
                            local imgLower = string.lower(img)
                            local isVisible = (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and (obj.Visible and obj.ImageTransparency < 0.9) or (obj.Transparency < 0.9)

                            if isVisible and pureId and img ~= "" and not string.find(imgLower, "shadow") then
                                if DatabaseIconCuaca[pureId] then return DatabaseIconCuaca[pureId] end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function PulangKeSetPos()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp and posisiSimpanan then
        hrp.CFrame = posisiSimpanan
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end
end

-- ========================================================
-- 3. ENGINE WEBHOOK & PLAYER TRACKER
-- ========================================================
local MapDictionary = {
    ["Crystalline Passage"] = "Ancient Ruin (Runtuhan Kuno)",
    ["Underwater City"] = "Underwater City (Kota Atlantis)",
    ["Desolate Deep"] = "Desolate Deep (Palung Terdalam)",
    ["Roslit Bay"] = "Roslit Bay (Teluk Roslit)",
    ["Mushgrove Swamp"] = "Mushgrove Swamp (Rawa Jamur)",
    ["Terrapin Island"] = "Terrapin Island (Pulau Kura-kura)",
    ["Sunstone Island"] = "Sunstone Island (Pulau Matahari)",
    ["Statue of Sovereignty"] = "Statue of Sovereignty (Patung Raja)",
    ["Keepers Altar"] = "Keepers Altar (Altar Penjaga)",
    ["Snowcap Island"] = "Snowcap Island (Pulau Salju)",
    ["Forsaken Shores"] = "Forsaken Shores (Pantai Terabaikan)"
}

local BlacklistKeywords = {
    "crate", "teleport", "stand", "board", "shop", "vendor", "seller", 
    "buy", "leaderboard", "npc", "rod", "throne"
}

local function IsBlacklistedLocation(name)
    local lowerName = string.lower(name)
    for _, kw in ipairs(BlacklistKeywords) do
        if string.find(lowerName, kw) then return true end
    end
    return false
end

local trackedPlayers = {}
local UIStatus_PlayerMon
local trackerUIPaused = false
local isTrackerActive = ConfigData.WebhookPlayer or false

local function GetPlayerLocation(targetPlayer)
    local char = targetPlayer.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return "Loading/Mati" end

    local closestName = nil; local minDist = math.huge
    local mapFolders = {"Zones", "Islands", "Map", "World", "Locations"}
    
    for _, folderName in ipairs(mapFolders) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if not IsBlacklistedLocation(child.Name) then
                    local pos = child:IsA("Model") and child:GetPivot().Position or (child:IsA("BasePart") and child.Position or nil)
                    if pos then
                        local dist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
                        if dist < minDist then minDist = dist; closestName = child.Name end
                    end
                end
            end
        end
    end

    if closestName and minDist <= 3500 then 
        return MapDictionary[closestName] or closestName 
    end
    return "Lautan Luas (Ocean)"
end

local function SendPlayerList(isManual)
    local url = ConfigData.WebhookURL
    if not url or url == "" or not string.find(url, "discord") then
        if UIStatus_PlayerMon then
            task.spawn(function()
                trackerUIPaused = true
                UIStatus_PlayerMon.Text = "Status: Link Webhook Kosong!"
                UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(255, 100, 100)
                task.wait(3); trackerUIPaused = false
            end)
        end return
    end
    url = url:match("^%s*(.-)%s*$")

    if isManual and UIStatus_PlayerMon then 
        UIStatus_PlayerMon.Text = "Menyiapkan Data..."
        UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(255, 200, 50) 
    end

    local currentOnlineMap = {}
    for _, p in ipairs(Players:GetPlayers()) do
        currentOnlineMap[p.UserId] = true
        local loc = GetPlayerLocation(p)
        if trackedPlayers[p.UserId] then 
            trackedPlayers[p.UserId].IsOnline = true; trackedPlayers[p.UserId].Location = loc
        else 
            trackedPlayers[p.UserId] = {Name = p.Name, DisplayName = p.DisplayName, IsOnline = true, Location = loc} 
        end
    end
    for userId, data in pairs(trackedPlayers) do 
        if not currentOnlineMap[userId] then data.IsOnline = false end 
    end

    local onlineCount = 0; local totalTracked = 0; local sortedList = {}
    for _, data in pairs(trackedPlayers) do table.insert(sortedList, data) end
    table.sort(sortedList, function(a, b) 
        if a.IsOnline ~= b.IsOnline then return a.IsOnline end; 
        return a.DisplayName:lower() < b.DisplayName:lower() 
    end)

    local playerLines = {}
    for i, data in ipairs(sortedList) do
        totalTracked = totalTracked + 1; if data.IsOnline then onlineCount = onlineCount + 1 end
        local icon = data.IsOnline and "🟢" or "🔴"
        local locInfo = data.IsOnline and ("📍 " .. data.Location) or ("👻 Last Loc: " .. data.Location)
        table.insert(playerLines, string.format("%s %d. %s (@%s) | %s", icon, i, data.DisplayName, data.Name, locInfo))
    end

    local embedChunks = {}; local currentChunk = ""
    for _, line in ipairs(playerLines) do
        if #currentChunk + #line > 900 then
            table.insert(embedChunks, currentChunk); currentChunk = line .. "\n"
        else
            currentChunk = currentChunk .. line .. "\n"
        end
    end
    if currentChunk ~= "" then table.insert(embedChunks, currentChunk) end

    local maxPlayer = Players.MaxPlayers; local disconnectedCount = totalTracked - onlineCount
    local wibTime = os.time() + (7 * 3600); local tglWIB = os.date("!%d/%m/%y", wibTime); local jamWIB = os.date("!%H:%M:%S", wibTime)     

    local embedFields = {
        {["name"] = "🕒 Waktu Laporan (WIB)", ["value"] = string.format("📅 **Tanggal:** %s\n⏰ **Jam:** %s", tglWIB, jamWIB), ["inline"] = false},
        {["name"] = "📊 Ringkasan Server", ["value"] = string.format("🟢 **Online:** %d / %d\n🔴 **Disconnected:** %d", onlineCount, maxPlayer, disconnectedCount), ["inline"] = false}
    }

    if #embedChunks == 0 then
        table.insert(embedFields, {["name"] = "👤 Player Database", ["value"] = "```\n[ Data Kosong ]\n```", ["inline"] = false})
    else
        for idx, chunkText in ipairs(embedChunks) do
            local headerName = (idx == 1) and "👤 Player Database & Location Map" or ("👤 Player Database (Bagian " .. idx .. ")")
            table.insert(embedFields, {["name"] = headerName, ["value"] = "```\n" .. chunkText .. "```", ["inline"] = false})
        end
    end

    local payload = {
        ["username"] = "Shadow Tracker Premium",
        ["embeds"] = {{
            ["title"] = isManual and "🛠️ [TEST] SHADOW WEBHOOK TRACKER" or "🕸️ SHADOW WEBHOOK TRACKER",
            ["color"] = 9371895,
            ["fields"] = embedFields,
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ") 
        }}
    }

    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if requestFunc then
        task.spawn(function()
            local success, response = pcall(function()
                return requestFunc({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload)})
            end)
            if success and response and (response.StatusCode == 200 or response.StatusCode == 204) then
                if UIStatus_PlayerMon then
                    trackerUIPaused = true
                    UIStatus_PlayerMon.Text = "Status: TEMBUS (Sukses Kirim)!"
                    UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(100, 255, 100)
                    task.wait(3); trackerUIPaused = false
                end
            end
        end)
    end
end

-- ========================================================
-- 3.5. PLAYER JOIN / LEAVE ALERT 
-- ========================================================
local function SendJoinLeaveNotification(targetPlayer, isJoin)
    local url = ConfigData.WebhookURL
    if not url or url == "" or not string.find(url, "discord") then return end
    if not ConfigData.WebhookJoinLeave then return end

    url = url:match("^%s*(.-)%s*$")
    
    local statusText = isJoin and "🟢 JOINED THE SERVER" or "🔴 LEFT THE SERVER"
    local colorCode = isJoin and 3066993 or 15158332
    
    local function FireWebhook(locationText)
        local payload = {
            ["username"] = "Shadow Tracker Alerts",
            ["embeds"] = {{
                ["title"] = "🔔 PLAYER ACTIVITY ALERT",
                ["color"] = colorCode,
                ["fields"] = {
                    {["name"] = "👤 Player", ["value"] = string.format("**%s**\n(@%s)", targetPlayer.DisplayName, targetPlayer.Name), ["inline"] = true},
                    {["name"] = "📊 Action", ["value"] = statusText, ["inline"] = true},
                    {["name"] = "📍 Location", ["value"] = locationText, ["inline"] = false}
                },
                ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }
        
        local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
        if requestFunc then
            task.spawn(function()
                pcall(function()
                    requestFunc({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload)})
                end)
            end)
        end
    end

    if isJoin then
        task.delay(4, function()
            local loc = GetPlayerLocation(targetPlayer)
            FireWebhook(loc)
        end)
    else
        local loc = "Lautan Luas (Ocean)"
        if trackedPlayers[targetPlayer.UserId] then
            loc = "Last Loc: " .. trackedPlayers[targetPlayer.UserId].Location
        end
        FireWebhook(loc)
    end
end

Players.PlayerAdded:Connect(function(p) SendJoinLeaveNotification(p, true) end)
Players.PlayerRemoving:Connect(function(p) SendJoinLeaveNotification(p, false) end)

-- ========================================================
-- 4. ENGINE CLAY POTATO MODE + ALWAYS DAYLIGHT
-- ========================================================
local clayPotatoActive = false
local clayLightingConn = nil
local clayDescendantConn = nil

local function EnableClayPotato()
    if clayPotatoActive then return end
    clayPotatoActive = true
    if setfpscap then pcall(setfpscap, 60) end

    local GRAY_COLOR = Color3.fromRGB(140, 140, 140)

    local function forceDaylight()
        if not ConfigData.ClayPotato then return end
        pcall(function()
            Lighting.TimeOfDay = "12:00:00"
            Lighting.GlobalShadows = false
            Lighting.Brightness = 2
            Lighting.Ambient = Color3.fromRGB(255, 255, 255)
            Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
            Lighting.FogEnd = 9e9
        end)
    end

    forceDaylight()
    if not clayLightingConn then
        clayLightingConn = Lighting.Changed:Connect(function()
            if ConfigData.ClayPotato then forceDaylight() end
        end)
    end

    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("PostEffect") or effect:IsA("Atmosphere") then pcall(function() effect:Destroy() end) end
    end

    pcall(function()
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            terrain.Decoration = false; terrain.WaterWaveSize = 0; terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0; terrain.WaterTransparency = 0.8
        end
    end)

    local function isMyPlayerStuff(obj)
        if player.Character and (obj == player.Character or obj:IsDescendantOf(player.Character)) then return true end
        local backpack = player:FindFirstChild("Backpack")
        if backpack and (obj == backpack or obj:IsDescendantOf(backpack)) then return true end
        return false
    end

    local function superNuke(obj)
        if not obj or not ConfigData.ClayPotato then return end
        if isMyPlayerStuff(obj) then return end

        pcall(function()
            if obj:IsA("BasePart") then
                obj.Material = Enum.Material.SmoothPlastic
                obj.Reflectance = 0; obj.CastShadow = false; obj.Color = GRAY_COLOR
                if obj:IsA("MeshPart") then obj.TextureID = "" end
            elseif obj:IsA("SpecialMesh") then obj.TextureId = "" 
            elseif obj:IsA("Texture") or obj:IsA("Decal") or obj:IsA("SurfaceAppearance") then
                task.defer(function() pcall(function() obj:Destroy() end) end)
            elseif obj:IsA("Clothing") or obj:IsA("ShirtGraphic") then
                task.defer(function() pcall(function() obj:Destroy() end) end)
            elseif obj:IsA("PostEffect") or obj:IsA("Atmosphere") or obj:IsA("ParticleEmitter") 
                or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Sparkles") or obj:IsA("Fire") 
                or obj:IsA("Smoke") or obj:IsA("Highlight") then
                obj.Enabled = false
            elseif obj:IsA("Light") then obj.Enabled = false end
        end)
    end

    task.spawn(function()
        local allObjects = workspace:GetDescendants()
        for i = 1, #allObjects do
            if not ConfigData.ClayPotato then break end
            superNuke(allObjects[i])
            if i % 300 == 0 then task.wait() end
        end
    end)

    if not clayDescendantConn then
        clayDescendantConn = workspace.DescendantAdded:Connect(function(obj)
            if ConfigData.ClayPotato then task.defer(superNuke, obj) end
        end)
    end
end

-- ========================================================
-- 5. UI SYSTEM (SHADOW PANEL V8)
-- ========================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Shadow_Panel_V8"
ScreenGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") or player.PlayerGui

local c_bg = Color3.fromRGB(15, 15, 18); local c_sidebar = Color3.fromRGB(20, 20, 24)
local c_content = Color3.fromRGB(25, 25, 30); local c_accent = Color3.fromRGB(140, 60, 255)
local c_text = Color3.fromRGB(240, 240, 240); local c_subtext = Color3.fromRGB(170, 170, 170)

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, ConfigData.UISizeX or 520, 0, ConfigData.UISizeY or 320)
MainFrame.Position = UDim2.new(0.5, -(ConfigData.UISizeX or 520)/2, 0.5, -(ConfigData.UISizeY or 320)/2)
MainFrame.BackgroundColor3 = c_bg; MainFrame.Active = true; MainFrame.Draggable = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", MainFrame).Color = Color3.fromRGB(40, 40, 50); MainFrame.UIStroke.Thickness = 1

local LogoBtn = Instance.new("TextButton", ScreenGui)
LogoBtn.Size = UDim2.new(0, 45, 0, 45) 
LogoBtn.Position = UDim2.new(0, 15, 0.45, 0)
LogoBtn.BackgroundColor3 = c_sidebar; LogoBtn.Text = "SHDW\n🚀"; LogoBtn.TextColor3 = c_accent
LogoBtn.Font = Enum.Font.GothamBlack; LogoBtn.TextSize = 11; LogoBtn.Active = true; LogoBtn.Draggable = true
LogoBtn.Visible = false
Instance.new("UICorner", LogoBtn).CornerRadius = UDim.new(0, 10)

local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 40); Header.BackgroundTransparency = 1

local TitleLabel = Instance.new("TextLabel", Header)
TitleLabel.Size = UDim2.new(0.6, 0, 1, 0); TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "⚜️ SHADOW HUB 🚀"; TitleLabel.TextColor3 = c_accent
TitleLabel.Font = Enum.Font.GothamBold; TitleLabel.TextSize = 13; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 40, 0, 40); CloseBtn.Position = UDim2.new(1, -40, 0, 0)
CloseBtn.BackgroundTransparency = 1; CloseBtn.Text = "—"; CloseBtn.TextColor3 = c_accent
CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 16

LogoBtn.MouseButton1Click:Connect(function() MainFrame.Visible = true; LogoBtn.Visible = false end)
CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false; LogoBtn.Visible = true end)

local ResizeHandle = Instance.new("TextButton", MainFrame)
ResizeHandle.Size = UDim2.new(0, 20, 0, 20); ResizeHandle.Position = UDim2.new(1, -20, 1, -20)
ResizeHandle.BackgroundTransparency = 1; ResizeHandle.Text = "◢"; ResizeHandle.TextColor3 = c_subtext
ResizeHandle.TextSize = 14; ResizeHandle.Font = Enum.Font.GothamBold

local isDraggingResize = false; local dragStartPos, startSize

ResizeHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingResize = true; dragStartPos = input.Position; startSize = MainFrame.Size
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isDraggingResize and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartPos
        MainFrame.Size = UDim2.new(0, math.clamp(startSize.X.Offset + delta.X, 400, 900), 0, math.clamp(startSize.Y.Offset + delta.Y, 250, 600))
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if isDraggingResize and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        isDraggingResize = false
        ConfigData.UISizeX = MainFrame.Size.X.Offset
        ConfigData.UISizeY = MainFrame.Size.Y.Offset
        SaveConfig()
    end
end)

local Sidebar = Instance.new("Frame", MainFrame)
Sidebar.Size = UDim2.new(0, 160, 1, -40); Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = c_sidebar; Sidebar.BorderSizePixel = 0
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 10)
local SidebarList = Instance.new("UIListLayout", Sidebar)
SidebarList.Padding = UDim.new(0, 4); SidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center

local Pages = {}
local function CreateTab(name, active)
    local btn = Instance.new("TextButton", Sidebar)
    btn.Size = UDim2.new(0.92, 0, 0, 34); btn.BackgroundColor3 = active and Color3.fromRGB(35, 35, 45) or c_sidebar
    btn.Text = "  " .. name; btn.TextColor3 = active and c_text or c_subtext
    btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 10; btn.TextXAlignment = Enum.TextXAlignment.Left; btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local indicator = Instance.new("Frame", btn)
    indicator.Size = UDim2.new(0, 3, 0.6, 0); indicator.Position = UDim2.new(0, 2, 0.2, 0)
    indicator.BackgroundColor3 = c_accent; indicator.BorderSizePixel = 0; indicator.Visible = active
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

    local PageScroll = Instance.new("ScrollingFrame", MainFrame)
    PageScroll.Size = UDim2.new(1, -170, 1, -50); PageScroll.Position = UDim2.new(0, 170, 0, 40)
    PageScroll.BackgroundTransparency = 1; PageScroll.BorderSizePixel = 0
    PageScroll.ScrollBarThickness = 3; PageScroll.ScrollBarImageColor3 = c_accent; PageScroll.Visible = active
    local Layout = Instance.new("UIListLayout", PageScroll)
    Layout.Padding = UDim.new(0, 8); Layout.SortOrder = Enum.SortOrder.LayoutOrder

    Pages[name] = {Button = btn, Indicator = indicator, Frame = PageScroll}
    btn.MouseButton1Click:Connect(function()
        for pName, pData in pairs(Pages) do
            local isTarget = (pName == name)
            pData.Frame.Visible = isTarget; pData.Indicator.Visible = isTarget
            pData.Button.BackgroundColor3 = isTarget and Color3.fromRGB(35, 35, 45) or c_sidebar
            pData.Button.TextColor3 = isTarget and c_text or c_subtext
        end
    end)
    return PageScroll
end

local TabAutomation = CreateTab("⚡ Automation", true)
local TabBooster    = CreateTab("🚀 Booster & RAM", false)
local TabWebhooks   = CreateTab("📡 Discord Webhooks", false)
local TabTeleport   = CreateTab("🌍 Teleport Island", false)
local TabConfig     = CreateTab("⚙️ Config Manager", false)

-- Anti-mentok List Scrolling Fix untuk Semua Tab
TabTeleport.AutomaticCanvasSize = Enum.AutomaticSize.Y
TabTeleport.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UIPadding", TabTeleport).PaddingBottom = UDim.new(0, 25)

TabBooster.AutomaticCanvasSize = Enum.AutomaticSize.Y
TabBooster.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UIPadding", TabBooster).PaddingBottom = UDim.new(0, 25)

TabWebhooks.AutomaticCanvasSize = Enum.AutomaticSize.Y
TabWebhooks.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UIPadding", TabWebhooks).PaddingBottom = UDim.new(0, 25)

local function CreateDropdown(parent, titleText)
    local DropdownFrame = Instance.new("Frame", parent)
    DropdownFrame.Size = UDim2.new(1, -10, 0, 38); DropdownFrame.BackgroundColor3 = c_content
    DropdownFrame.ClipsDescendants = true; DropdownFrame.AutomaticSize = Enum.AutomaticSize.Y
    Instance.new("UICorner", DropdownFrame).CornerRadius = UDim.new(0, 8)
    
    local TopBtn = Instance.new("TextButton", DropdownFrame)
    TopBtn.Size = UDim2.new(1, 0, 0, 38); TopBtn.BackgroundTransparency = 1
    TopBtn.Text = "   " .. titleText; TopBtn.TextColor3 = c_text; TopBtn.Font = Enum.Font.GothamBold; TopBtn.TextSize = 11; TopBtn.TextXAlignment = Enum.TextXAlignment.Left
    
    local ItemsContainer = Instance.new("Frame", DropdownFrame)
    ItemsContainer.Size = UDim2.new(1, 0, 0, 0); ItemsContainer.Position = UDim2.new(0, 0, 0, 38)
    ItemsContainer.BackgroundTransparency = 1; ItemsContainer.AutomaticSize = Enum.AutomaticSize.Y
    local ItemLayout = Instance.new("UIListLayout", ItemsContainer)
    ItemLayout.Padding = UDim.new(0, 6); ItemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    Instance.new("UIPadding", ItemsContainer).PaddingBottom = UDim.new(0, 8)

    local isOpen = true
    TopBtn.MouseButton1Click:Connect(function() isOpen = not isOpen; ItemsContainer.Visible = isOpen end)
    return ItemsContainer
end

local function CreateToggle(parent, text, configKey, callback)
    local Frame = Instance.new("Frame", parent)
    Frame.Size = UDim2.new(0.95, 0, 0, 32); Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)
    
    local Label = Instance.new("TextLabel", Frame)
    Label.Size = UDim2.new(0.65, 0, 1, 0); Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1; Label.Text = text; Label.TextColor3 = c_text
    Label.Font = Enum.Font.GothamSemibold; Label.TextSize = 10; Label.TextXAlignment = Enum.TextXAlignment.Left
    
    local ToggleBtn = Instance.new("TextButton", Frame)
    ToggleBtn.Size = UDim2.new(0, 36, 0, 18); ToggleBtn.Position = UDim2.new(1, -45, 0.5, -9)
    ToggleBtn.BackgroundColor3 = ConfigData[configKey] and c_accent or Color3.fromRGB(60, 60, 70); ToggleBtn.Text = ""
    Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)
    
    local Circle = Instance.new("Frame", ToggleBtn)
    Circle.Size = UDim2.new(0, 14, 0, 14); Circle.Position = ConfigData[configKey] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    Circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Instance.new("UICorner", Circle).CornerRadius = UDim.new(1, 0)
    
    local state = ConfigData[configKey] or false

    UI_Updaters[configKey] = function(newState)
        state = newState
        local targetColor = state and c_accent or Color3.fromRGB(60, 60, 70)
        local targetPos = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        TweenService:Create(ToggleBtn, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play()
        TweenService:Create(Circle, TweenInfo.new(0.2), {Position = targetPos}):Play()
        if callback then callback(state) end
    end

    ToggleBtn.MouseButton1Click:Connect(function()
        state = not state; ConfigData[configKey] = state; SaveConfig(); UI_Updaters[configKey](state)
    end)
    if state and callback then callback(state) end
end

local function CreateButton(parent, text, callback)
    local Btn = Instance.new("TextButton", parent)
    Btn.Size = UDim2.new(0.95, 0, 0, 32); Btn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    Btn.Text = text; Btn.TextColor3 = c_text; Btn.Font = Enum.Font.GothamSemibold; Btn.TextSize = 10
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", Btn).Color = Color3.fromRGB(50, 50, 60); Btn.UIStroke.Thickness = 1
    Btn.MouseButton1Click:Connect(callback)
    return Btn
end

local function CreateTextBox(parent, placeholder, configKey, callback)
    local BoxFrame = Instance.new("Frame", parent)
    BoxFrame.Size = UDim2.new(0.95, 0, 0, 32); BoxFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    Instance.new("UICorner", BoxFrame).CornerRadius = UDim.new(0, 6)
    
    local Box = Instance.new("TextBox", BoxFrame)
    Box.Size = UDim2.new(1, -20, 1, 0); Box.Position = UDim2.new(0, 10, 0, 0)
    Box.BackgroundTransparency = 1; Box.PlaceholderText = placeholder
    Box.Text = tostring(ConfigData[configKey] or ""); Box.TextColor3 = c_text
    Box.PlaceholderColor3 = c_subtext; Box.Font = Enum.Font.GothamSemibold; Box.TextSize = 10; Box.TextXAlignment = Enum.TextXAlignment.Left; Box.ClearTextOnFocus = false
    
    UI_Updaters[configKey] = function(newState) Box.Text = tostring(newState) end
    Box.FocusLost:Connect(function() ConfigData[configKey] = Box.Text; SaveConfig(); if callback then callback(Box.Text) end end)
end

local function CreateStatusLabel(parent)
    local Label = Instance.new("TextLabel", parent)
    Label.Size = UDim2.new(0.95, 0, 0, 28); Label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    Label.Text = "Status: IDLE"; Label.TextColor3 = c_subtext
    Label.Font = Enum.Font.GothamBold; Label.TextSize = 10
    Instance.new("UICorner", Label).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", Label).Color = c_accent; Label.UIStroke.Thickness = 1
    return Label
end

-- ====== SELECTOR DROPDOWN HELPERS ======
local function CreateSelector(parent, titleText, items, onSelect)
    local Frame = Instance.new("Frame", parent)
    Frame.Size = UDim2.new(0.95, 0, 0, 32)
    Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

    local Label = Instance.new("TextLabel", Frame)
    Label.Size = UDim2.new(0.4, 0, 1, 0)
    Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = titleText
    Label.TextColor3 = c_text
    Label.Font = Enum.Font.GothamSemibold
    Label.TextSize = 10
    Label.TextXAlignment = Enum.TextXAlignment.Left

    local SelectBtn = Instance.new("TextButton", Frame)
    SelectBtn.Size = UDim2.new(0.55, -10, 0, 24)
    SelectBtn.Position = UDim2.new(0.45, 0, 0.5, -12)
    SelectBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    SelectBtn.Text = "Select Option"
    SelectBtn.TextColor3 = c_subtext
    SelectBtn.Font = Enum.Font.GothamSemibold
    SelectBtn.TextSize = 10
    Instance.new("UICorner", SelectBtn).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", SelectBtn).Color = Color3.fromRGB(50, 50, 60)

    local ListContainer = Instance.new("Frame", parent)
    ListContainer.Size = UDim2.new(0.95, 0, 0, 100)
    ListContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    ListContainer.Visible = false
    Instance.new("UICorner", ListContainer).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", ListContainer).Color = Color3.fromRGB(50, 50, 60)

    local Scroll = Instance.new("ScrollingFrame", ListContainer)
    Scroll.Size = UDim2.new(1, -4, 1, -4)
    Scroll.Position = UDim2.new(0, 2, 0, 2)
    Scroll.BackgroundTransparency = 1
    Scroll.BorderSizePixel = 0
    Scroll.ScrollBarThickness = 2
    Scroll.ScrollBarImageColor3 = c_accent

    local ScrollLayout = Instance.new("UIListLayout", Scroll)
    ScrollLayout.Padding = UDim.new(0, 2)
    ScrollLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    SelectBtn.MouseButton1Click:Connect(function()
        ListContainer.Visible = not ListContainer.Visible
    end)

    local function populate(newItems)
        for _, child in ipairs(Scroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        local ySize = 0
        for _, item in ipairs(newItems) do
            local btn = Instance.new("TextButton", Scroll)
            btn.Size = UDim2.new(1, -4, 0, 24)
            btn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
            btn.Text = " " .. item
            btn.TextColor3 = c_text
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 10
            btn.TextXAlignment = Enum.TextXAlignment.Left
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

            btn.MouseButton1Click:Connect(function()
                SelectBtn.Text = item
                SelectBtn.TextColor3 = c_text
                ListContainer.Visible = false
                if onSelect then onSelect(item) end
            end)
            ySize = ySize + 26
        end
        Scroll.CanvasSize = UDim2.new(0, 0, 0, ySize)
        local targetHeight = math.clamp(ySize + 4, 30, 120)
        ListContainer.Size = UDim2.new(0.95, 0, 0, targetHeight)
    end

    populate(items)
    return Frame, populate, SelectBtn
end

-- ========================================================
-- 6. MENU SETUP
-- ========================================================
local DropElemental = CreateDropdown(TabAutomation, "Event Elemental TP")
local UIStatus_Elemental = CreateStatusLabel(DropElemental)

CreateToggle(DropElemental, "Enable Auto TP Cuaca", "AutoTP", function(state)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if state then
        if hrp and not posisiSimpanan then posisiSimpanan = hrp.CFrame end
    else
        UIStatus_Elemental.Text = "SYSTEM PAUSED"; UIStatus_Elemental.TextColor3 = c_subtext
    end
end)

-- ====== AUTOMATION: AUTO FISHING MANAGER ======
local DropFishing = CreateDropdown(TabAutomation, "🎣 Auto Fishing Manager")

local fishingModes = {"Map 1 (Rotate)", "Map 2 (Canyon)", "Dual Map (Switch)"}
local FishingSelectorFrame, FishingPopulate, FishingSelectBtn = CreateSelector(DropFishing, "Farming Mode", fishingModes, function(sel)
    ConfigData.SelectedFarmingMode = sel
    SaveConfig()
    
    if ConfigData.AutoFishingToggle then
        ConfigData.AutoRotate = (sel == "Map 1 (Rotate)")
        ConfigData.AutoMap2 = (sel == "Map 2 (Canyon)")
        ConfigData.AutoDualMap = (sel == "Dual Map (Switch)")
    end
end)

UI_Updaters["SelectedFarmingMode"] = function(newState)
    FishingSelectBtn.Text = newState
    FishingSelectBtn.TextColor3 = c_text
end
if not ConfigData.SelectedFarmingMode then ConfigData.SelectedFarmingMode = "Map 1 (Rotate)" end
FishingSelectBtn.Text = ConfigData.SelectedFarmingMode
FishingSelectBtn.TextColor3 = c_text

CreateToggle(DropFishing, "Enable Auto Fishing", "AutoFishingToggle", function(state)
    if state then
        ConfigData.AutoRotate = (ConfigData.SelectedFarmingMode == "Map 1 (Rotate)")
        ConfigData.AutoMap2 = (ConfigData.SelectedFarmingMode == "Map 2 (Canyon)")
        ConfigData.AutoDualMap = (ConfigData.SelectedFarmingMode == "Dual Map (Switch)")
    else
        ConfigData.AutoRotate = false
        ConfigData.AutoMap2 = false
        ConfigData.AutoDualMap = false
    end
end)

local UIStatus_Fishing = CreateStatusLabel(DropFishing)
if not ConfigData.AutoFishingToggle then
    UIStatus_Fishing.Text = "AUTO FISHING: OFF"
    UIStatus_Fishing.TextColor3 = c_subtext
end

-- ====== BOOSTER & RAM (INDIVIDUAL TOGGLES IN LIST) ======
local DropBooster = CreateDropdown(TabBooster, "🚀 Graphic & Performance Booster")
local UIStatus_Booster = CreateStatusLabel(DropBooster)
UIStatus_Booster.Text = "BOOSTER STATUS: ACTIVE"
UIStatus_Booster.TextColor3 = Color3.fromRGB(50, 255, 100)

CreateToggle(DropBooster, "FPS Booster (Nuke Visuals)", "FPSBooster", function(state)
    if UIStatus_Booster then
        UIStatus_Booster.Text = "FPS BOOSTER: " .. (state and "ON" or "OFF")
        UIStatus_Booster.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

CreateToggle(DropBooster, "Clay Potato Mode", "ClayPotato", function(state)
    if state then EnableClayPotato() end
    if UIStatus_Booster then
        UIStatus_Booster.Text = "CLAY POTATO: " .. (state and "ON" or "OFF")
        UIStatus_Booster.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

CreateToggle(DropBooster, "Disable 3D Rendering", "Disable3D", function(state)
    RunService:Set3dRenderingEnabled(not state)
    if UIStatus_Booster then
        UIStatus_Booster.Text = "3D RENDERING: " .. (state and "DISABLED" or "ENABLED")
        UIStatus_Booster.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

CreateToggle(DropBooster, "Clear Water", "ClearWater", function(state)
    if UIStatus_Booster then
        UIStatus_Booster.Text = "CLEAR WATER: " .. (state and "ON" or "OFF")
        UIStatus_Booster.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

CreateToggle(DropBooster, "Limit 30 FPS", "Limit30FPS", function(state)
    if setfpscap then setfpscap(state and 30 or 60) end
    if UIStatus_Booster then
        UIStatus_Booster.Text = "LIMIT 30 FPS: " .. (state and "ON" or "OFF")
        UIStatus_Booster.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

CreateToggle(DropBooster, "Auto Clean RAM", "AutoRAM", function(state)
    if UIStatus_Booster then
        UIStatus_Booster.Text = "AUTO RAM: " .. (state and "ON" or "OFF")
        UIStatus_Booster.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

-- ====== DISCORD WEBHOOKS (INDIVIDUAL TOGGLES IN LIST) ======
local DropGlobalWeb = CreateDropdown(TabWebhooks, "🔗 Global Webhook Configuration")
CreateTextBox(DropGlobalWeb, "Paste Webhook URL Discord Di Sini...", "WebhookURL", function(txt) end)

local DropWebToggles = CreateDropdown(TabWebhooks, "⚙️ Active Webhook Features")
UIStatus_PlayerMon = CreateStatusLabel(DropWebToggles)

local trackerInterval = 3600
local trackerRemaining = 0

CreateToggle(DropWebToggles, "Player Tracker Webhook", "WebhookPlayer", function(state)
    isTrackerActive = state
    if state then
        trackerRemaining = trackerInterval
    else
        trackerRemaining = 0
        trackerUIPaused = false
    end
    if UIStatus_PlayerMon then
        UIStatus_PlayerMon.Text = state and "TRACKER: ON" or "TRACKER: OFF"
        UIStatus_PlayerMon.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

CreateToggle(DropWebToggles, "Join / Leave Alert Webhook", "WebhookJoinLeave", function(state)
    if UIStatus_PlayerMon then
        UIStatus_PlayerMon.Text = state and "JOIN/LEAVE ALERT: ON" or "JOIN/LEAVE ALERT: OFF"
        UIStatus_PlayerMon.TextColor3 = state and Color3.fromRGB(50, 255, 100) or c_subtext
    end
end)

local DropWebTest = CreateDropdown(TabWebhooks, "🧪 Test Webhook Triggers")
CreateButton(DropWebTest, "🚀 Kirim Test Player Tracker Manual", function() SendPlayerList(true) end)

-- ========================================================
-- 6.5. MENU TELEPORT MAP & PLAYER
-- ========================================================
local DropMapTP = CreateDropdown(TabTeleport, "Teleport to Island")

local MapLocations = {
    {Name = "Hutan Kuno", Pos = Vector3.new(1482.70, 11.14, -300.65), Rot = -30.84},
    {Name = "Kedalaman Esoterik", Pos = Vector3.new(3210.66, -1302.86, 1407.32), Rot = 18.56},
    {Name = "Kedalaman Kristal", Pos = Vector3.new(5703.96, -905.21, 15328.31), Rot = -161.77},
    {Name = "Ngarai Tembaga (Spot 1)", Pos = Vector3.new(-4171.59, 3.23, 566.77), Rot = 148.32},
    {Name = "Ngarai Tembaga (Spot 2)", Pos = Vector3.new(-4164.58, 59.63, 409.79), Rot = 104.76},
    {Name = "Pulau Kawah", Pos = Vector3.new(978.88, 47.48, 5086.54), Rot = 127.91},
    {Name = "Runtuhan Kuno", Pos = Vector3.new(6089.14, -585.92, 4639.69), Rot = 142.21},
    {Name = "Tambang Canyon Tembaga", Pos = Vector3.new(-4031.78, -544.08, 577.91), Rot = 25.84},
    {Name = "Terumbu Karang", Pos = Vector3.new(-3028.41, 2.51, 2269.79), Rot = 84.12}
}

local selectedMap = nil
local mapNames = {}
for _, map in ipairs(MapLocations) do table.insert(mapNames, map.Name) end

local MapFrame, MapPopulate, MapSelectBtn = CreateSelector(DropMapTP, "Select Island", mapNames, function(sel)
    selectedMap = sel
end)

local BtnTeleportMap = CreateButton(DropMapTP, "Teleport", function()
    if not selectedMap then return end
    for _, map in ipairs(MapLocations) do
        if map.Name == selectedMap then
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(map.Pos) * CFrame.Angles(0, math.rad(map.Rot), 0)
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
            end
            break
        end
    end
end)
BtnTeleportMap.BackgroundColor3 = c_sidebar
BtnTeleportMap.TextColor3 = c_accent
BtnTeleportMap.Font = Enum.Font.GothamBold
local UIStrokeMap = Instance.new("UIStroke", BtnTeleportMap)
UIStrokeMap.Color = c_accent
UIStrokeMap.Thickness = 1

local DropPlayerTP = CreateDropdown(TabTeleport, "Teleport to Player")

local playerMap = {}
local selectedPlayerObj = nil
local PlayerFrame, PlayerPopulate, PlayerSelectBtn = CreateSelector(DropPlayerTP, "Select Player", {}, function(selText)
    selectedPlayerObj = playerMap[selText]
end)

local BtnTeleportPlayer = CreateButton(DropPlayerTP, "Teleport to selected Player", function()
    if not selectedPlayerObj then return end
    local myHrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local targetHrp = selectedPlayerObj.Character and selectedPlayerObj.Character:FindFirstChild("HumanoidRootPart")
    if myHrp and targetHrp then
        myHrp.CFrame = targetHrp.CFrame
        myHrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end
end)
BtnTeleportPlayer.BackgroundColor3 = c_sidebar
BtnTeleportPlayer.TextColor3 = c_accent
BtnTeleportPlayer.Font = Enum.Font.GothamBold
local UIStrokePlayer = Instance.new("UIStroke", BtnTeleportPlayer)
UIStrokePlayer.Color = c_accent
UIStrokePlayer.Thickness = 1

local function LoadPlayers()
    playerMap = {}
    local pDisplayNames = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local pText = p.DisplayName .. " (@" .. p.Name .. ")"
            table.insert(pDisplayNames, pText)
            playerMap[pText] = p
        end
    end
    PlayerPopulate(pDisplayNames)
    selectedPlayerObj = nil
    PlayerSelectBtn.Text = "Select Option"
    PlayerSelectBtn.TextColor3 = c_subtext
end

local BtnRefreshPlayer = CreateButton(DropPlayerTP, "Refresh Player List", LoadPlayers)
LoadPlayers() 

-- ========================================================
-- [UPDATE] FEATURE BARU: SAVED LOCATION TELEPORT 
-- ========================================================
local DropSavedTP = CreateDropdown(TabTeleport, "📌 Custom Saved Location")
local savedCustomLocation = nil

local BtnSaveLoc
BtnSaveLoc = CreateButton(DropSavedTP, "Save Current Location", function()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        savedCustomLocation = hrp.CFrame
        BtnSaveLoc.Text = "Location Saved!"
        BtnSaveLoc.TextColor3 = Color3.fromRGB(50, 255, 100)
    else
        BtnSaveLoc.Text = "Player Not Found!"
        BtnSaveLoc.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
    task.delay(2, function()
        BtnSaveLoc.Text = "Save Current Location"
        BtnSaveLoc.TextColor3 = c_text
    end)
end)

local BtnTeleportLoc
BtnTeleportLoc = CreateButton(DropSavedTP, "Teleport to Saved", function()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if savedCustomLocation and hrp then
        hrp.CFrame = savedCustomLocation
        hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
        BtnTeleportLoc.Text = "Teleported!"
        BtnTeleportLoc.TextColor3 = Color3.fromRGB(100, 200, 255)
    else
        BtnTeleportLoc.Text = "No Save Found!"
        BtnTeleportLoc.TextColor3 = Color3.fromRGB(255, 100, 100)
    end
    task.delay(2, function()
        BtnTeleportLoc.Text = "Teleport to Saved"
        BtnTeleportLoc.TextColor3 = c_text
    end)
end)

local BtnResetLoc
BtnResetLoc = CreateButton(DropSavedTP, "Reset Saved Location", function()
    savedCustomLocation = nil
    BtnResetLoc.Text = "Location Reset!"
    BtnResetLoc.TextColor3 = Color3.fromRGB(255, 200, 50)
    task.delay(2, function()
        BtnResetLoc.Text = "Reset Saved Location"
        BtnResetLoc.TextColor3 = c_text
    end)
end)

CreateToggle(DropSavedTP, "Auto Teleport on Spawn", "AutoTeleportSpawn", function(state)
    -- State sudah dihandle oleh SaveConfig dan listener dibawah
end)

-- Listener Event Auto Teleport On Spawn (Jika Toggle Nyala)
player.CharacterAdded:Connect(function(char)
    if ConfigData.AutoTeleportSpawn and savedCustomLocation then
        task.spawn(function()
            local hrp = char:WaitForChild("HumanoidRootPart", 5)
            if hrp then
                task.wait(0.5) -- Sedikit jeda agar logic map teleport in-game selesai
                hrp.CFrame = savedCustomLocation
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
            end
        end)
    end
end)

-- ========================================================
-- CONFIG MANAGER
-- ========================================================
local DropConfigSystem = CreateDropdown(TabConfig, "Configuration Manager")
CreateButton(DropConfigSystem, "💾 Save UI Settings Manual", function() SaveConfig() end)
local BtnReset = CreateButton(DropConfigSystem, "⚠️ Reset Settingan (Tanpa DC)", function() end)
BtnReset.MouseButton1Click:Connect(function()
    ResetConfig(); BtnReset.Text = "✅ Reset Berhasil! UI Diperbarui."; BtnReset.TextColor3 = Color3.fromRGB(100, 255, 100)
    task.wait(2); BtnReset.Text = "⚠️ Reset Settingan (Tanpa DC)"; BtnReset.TextColor3 = c_text
end)

-- ==========================================================
-- 7. BACKGROUND ENGINES & THREADS
-- ==========================================================
task.spawn(function()
    while true do
        task.wait(1)
        if isTrackerActive then
            if trackerRemaining <= 0 then
                SendPlayerList(false)
                trackerRemaining = trackerInterval
            else
                trackerRemaining = trackerRemaining - 1
                if not trackerUIPaused and UIStatus_PlayerMon then
                    local menit = math.floor(trackerRemaining / 60)
                    local detik = trackerRemaining % 60
                    UIStatus_PlayerMon.Text = string.format("TRACKER AKTIF : NEXT SEND %02d:%02d", menit, detik)
                    UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(50, 255, 100)
                end
            end
        end
    end
end)

player.Idled:Connect(function() if ConfigData.AntiAFK then VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end end)

task.spawn(function() while true do task.wait(60); if ConfigData.AutoRAM then collectgarbage("collect") end end end)

task.spawn(function()
    while true do
        task.wait(1)
        if ConfigData.AutoTP then
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local schedule = GetEventScheduleWIB()

            if schedule.state == "COOLDOWN" then
                PulangKeSetPos()
                while ConfigData.AutoTP do
                    local realTimeSchedule = GetEventScheduleWIB()
                    if realTimeSchedule.state == "ACTIVE" then break end 
                    UIStatus_Elemental.Text = "CD: " .. formatSecondsToText(realTimeSchedule.timeLeft)
                    UIStatus_Elemental.TextColor3 = Color3.fromRGB(255, 200, 50)
                    task.wait(1)
                end
            elseif schedule.state == "ACTIVE" then
                UIStatus_Elemental.Text = "MENUJU PAPAN..."
                UIStatus_Elemental.TextColor3 = Color3.fromRGB(100, 200, 255)
                hrp.CFrame = spotKordinat.Board; hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0); task.wait(1.5)
                
                local cuacaAktif = GetWeatherIconOnly()
                if cuacaAktif then
                    local targetCFrame = spotKordinat[cuacaAktif]
                    while ConfigData.AutoTP do
                        local realTimeSchedule = GetEventScheduleWIB()
                        if realTimeSchedule.state == "COOLDOWN" then break end 
                        UIStatus_Elemental.Text = string.upper(cuacaAktif) .. ": " .. formatSecondsToText(realTimeSchedule.timeLeft)
                        UIStatus_Elemental.TextColor3 = Color3.fromRGB(50, 255, 100)
                        
                        if hrp and targetCFrame and (hrp.Position - targetCFrame.Position).Magnitude > 25 then
                            hrp.CFrame = CFrame.new(targetCFrame.Position + Vector3.new(0, 3, 0)) * targetCFrame.Rotation
                            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        end
                        task.wait(1)
                    end
                else
                    UIStatus_Elemental.Text = "MENUNGGU ICON CUACA..."; UIStatus_Elemental.TextColor3 = c_subtext; task.wait(1)
                end
            end
        end
    end
end)

task.spawn(function()
    while true do
        if ConfigData.AutoRotate and not ConfigData.AutoDualMap then
            local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local targetAngle = math.rad(poolAngles[currentPoolIndex])
                local targetCFrame = CFrame.new(standPositionRot) * CFrame.Angles(0, targetAngle, 0)
                
                for i = 1, 6 do
                    if hrp and hrp.Parent then hrp.CFrame = targetCFrame; hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0); hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0) end
                    task.wait(0.05)
                end
                
                currentPoolIndex = currentPoolIndex + 1; if currentPoolIndex > #poolAngles then currentPoolIndex = 1 end
                
                local elapsed = 0
                while elapsed < rotateInterval and ConfigData.AutoRotate and not ConfigData.AutoDualMap do
                    local sisaDetik = rotateInterval - elapsed
                    if UIStatus_Fishing then
                        UIStatus_Fishing.Text = "MAP 1 ROTATE: " .. formatSecondsToText(sisaDetik)
                        UIStatus_Fishing.TextColor3 = Color3.fromRGB(50, 255, 100)
                    end
                    task.wait(1); elapsed = elapsed + 1
                end
            else
                task.wait(1)
            end
        else
            task.wait(1)
        end
    end
end)

task.spawn(function()
    while true do
        if ConfigData.AutoMap2 and not ConfigData.AutoDualMap then
            local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                if (hrp.Position - map2Pos).Magnitude > 5 then
                    hrp.CFrame = map2CFrame
                    hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
                end
                if UIStatus_Fishing then
                    UIStatus_Fishing.Text = "MAP 2 ACTIVE (STAY STAYING)"
                    UIStatus_Fishing.TextColor3 = Color3.fromRGB(50, 255, 100)
                end
            end
            task.wait(1)
        else
            task.wait(1)
        end
    end
end)

task.spawn(function()
    while true do
        if ConfigData.AutoDualMap then
            local char = player.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
            
            if ConfigData.AutoDualMap then
                local map1Timer = 0
                while map1Timer < dualMapInterval and ConfigData.AutoDualMap do
                    hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local targetAngle = math.rad(poolAngles[currentPoolIndex])
                        local targetCFrame = CFrame.new(standPositionRot) * CFrame.Angles(0, targetAngle, 0)
                        
                        for i = 1, 4 do
                            if hrp and hrp.Parent then hrp.CFrame = targetCFrame; hrp.AssemblyLinearVelocity = Vector3.new(0,0,0) end
                            task.wait(0.05)
                        end
                        
                        currentPoolIndex = currentPoolIndex + 1
                        if currentPoolIndex > #poolAngles then currentPoolIndex = 1 end
                    end

                    local subTimer = 0
                    while subTimer < rotateInterval and map1Timer < dualMapInterval and ConfigData.AutoDualMap do
                        local sisaPindah = dualMapInterval - map1Timer
                        if UIStatus_Fishing then
                            UIStatus_Fishing.Text = "MAP 1 (ROTATING) | SWITCH IN: " .. formatSecondsToText(sisaPindah)
                            UIStatus_Fishing.TextColor3 = Color3.fromRGB(100, 200, 255)
                        end
                        task.wait(1)
                        subTimer = subTimer + 1
                        map1Timer = map1Timer + 1
                    end
                end
            end

            if ConfigData.AutoDualMap then
                local map2Timer = 0
                hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    for i = 1, 6 do
                        hrp.CFrame = map2CFrame
                        hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                        hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
                        task.wait(0.05)
                    end
                end

                while map2Timer < dualMapInterval and ConfigData.AutoDualMap do
                    hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp and (hrp.Position - map2Pos).Magnitude > 5 then
                        hrp.CFrame = map2CFrame
                        hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    end

                    local sisaPindah = dualMapInterval - map2Timer
                    if UIStatus_Fishing then
                        UIStatus_Fishing.Text = "MAP 2 (ROTATE OFF) | SWITCH IN: " .. formatSecondsToText(sisaPindah)
                        UIStatus_Fishing.TextColor3 = Color3.fromRGB(255, 200, 50)
                    end
                    task.wait(1)
                    map2Timer = map2Timer + 1
                end
            end
        else
            task.wait(1)
        end
    end
end)
