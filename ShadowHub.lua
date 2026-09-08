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
    AutoRotate = false,
    FPSBooster = false,
    Disable3D = false,
    ClearWater = false,
    Limit30FPS = false,
    AutoRAM = false,
    AntiAFK = true,
    WebhookURL = "",
    WebhookPlayer = false,
    UsePCProxy = false, -- [UPDATE] Konfigurasi baru untuk Proxy PC
    UISizeX = 520,
    UISizeY = 320
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
local rotateInterval = 3600

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
-- 3. ENGINE WEBHOOK & PLAYER TRACKER (AKURASI MAP DIPERBARUI)
-- ========================================================
local trackedPlayers = {}
local UIStatus_PlayerMon
local trackerUIPaused = false

local function GetPlayerLocation(targetPlayer)
    local char = targetPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    
    if not hrp then return "Loading/Mati" end

    local closestName = nil
    local minDist = math.huge

    -- 1. Metode Utama: Deteksi Koordinat Horizontal (Kebal Map Bawah Tanah)
    local mapFolders = {"Zones", "Islands", "Map", "World", "Locations"}
    for _, folderName in ipairs(mapFolders) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                local pos = nil
                if child:IsA("Model") then
                    pos = child:GetPivot().Position
                elseif child:IsA("BasePart") then
                    pos = child.Position
                end

                if pos then
                    -- Mengabaikan sumbu Y agar Crystalline Passage tidak membajak Ancient Ruin
                    local dist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
                    if dist < minDist then 
                        minDist = dist 
                        closestName = child.Name 
                    end
                end
            end
        end
    end

    if closestName and minDist <= 3500 then 
        return closestName 
    end

    -- 2. Fallback: Raycast Klasik
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {char}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local rayResult = workspace:Raycast(hrp.Position, Vector3.new(0, -1000, 0), raycastParams)
    if rayResult and rayResult.Instance then
        local current = rayResult.Instance
        local blacklist = {["!!! DEPENDENCIES"] = true, ["Terrain"] = true, ["Workspace"] = true, ["Water"] = true, ["Baseplate"] = true}
        
        while current and current ~= workspace do
            local parentObj = current.Parent
            if parentObj then
                local pName = parentObj.Name:lower()
                if pName == "workspace" or pName:find("islands") or pName:find("zones") or pName:find("map") or pName:find("world") then
                    if (current:IsA("Model") or current:IsA("Folder")) and not Players:GetPlayerFromCharacter(current) and not blacklist[current.Name] then
                        return current.Name
                    end
                end
            end
            current = current.Parent
        end
    end

    return "Lautan Luas (Ocean)"
end

local function UpdatePlayerTracker()
    local currentOnlineMap = {}
    for _, p in ipairs(Players:GetPlayers()) do
        currentOnlineMap[p.UserId] = true
        local currentLocation = GetPlayerLocation(p)
        if trackedPlayers[p.UserId] then
            trackedPlayers[p.UserId].IsOnline = true; trackedPlayers[p.UserId].Location = currentLocation
        else
            trackedPlayers[p.UserId] = {Name = p.Name, DisplayName = p.DisplayName, IsOnline = true, Location = currentLocation}
        end
    end
    for userId, data in pairs(trackedPlayers) do
        if not currentOnlineMap[userId] then data.IsOnline = false end
    end
end

local function SendPlayerList(isManual)
    local url = ConfigData.WebhookURL
    
    -- [UPDATE] Implementasi sistem Bypass Proxy PC
    if ConfigData.UsePCProxy and url then
        url = string.gsub(url, "discord%.com", "webhook.lewisakura.moe")
        url = string.gsub(url, "discordapp%.com", "webhook.lewisakura.moe")
    end
    
    -- [UPDATE] Pengecualian deteksi agar proxy lolos sistem filter
    if not url or url == "" or (not string.find(url, "discord") and not string.find(url, "lewisakura")) then
        if UIStatus_PlayerMon then
            task.spawn(function()
                trackerUIPaused = true
                UIStatus_PlayerMon.Text = "Status: Link Webhook Kosong/Salah!"
                UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(255, 100, 100)
                task.wait(3)
                trackerUIPaused = false
            end)
        end
        return
    end

    if isManual and UIStatus_PlayerMon then
        UIStatus_PlayerMon.Text = "Status: Mengumpulkan Data..."
        UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(255, 200, 50)
    end

    UpdatePlayerTracker()

    local onlineCount = 0; local totalTracked = 0; local sortedList = {}
    for userId, data in pairs(trackedPlayers) do table.insert(sortedList, data) end
    table.sort(sortedList, function(a, b)
        if a.IsOnline ~= b.IsOnline then return a.IsOnline end
        return a.DisplayName:lower() < b.DisplayName:lower()
    end)

    local playerLines = {}
    for i, data in ipairs(sortedList) do
        totalTracked = totalTracked + 1
        if data.IsOnline then onlineCount = onlineCount + 1 end
        local icon = data.IsOnline and "🟢" or "🔴"
        local locInfo = data.IsOnline and ("📍 " .. data.Location) or ("👻 Last Location: " .. data.Location)
        table.insert(playerLines, string.format("%s %d. %s (@%s) | %s", icon, i, data.DisplayName, data.Name, locInfo))
    end

    local maxPlayer = Players.MaxPlayers; local disconnectedCount = totalTracked - onlineCount
    local listText = table.concat(playerLines, "\n")
    if #listText > 1800 then listText = string.sub(listText, 1, 1800) .. "\n... (Daftar dipotong)" end

    local wibTime = os.time() + (7 * 3600)
    local tanggalWIB = os.date("!%d/%m/%y", wibTime); local jamWIB = os.date("!%H:%M:%S", wibTime)     

    local payload = {
        username = "Server Player Monitor",
        embeds = {{
            title = isManual and "🛠️ [MANUAL TEST] Server Player Tracker" or "🌐 Server Player Tracker",
            color = (disconnectedCount > 0) and 15158332 or 3066993,
            fields = {
                {name = "🕒 Waktu Pengiriman (WIB)", value = string.format("📅 **Tanggal:** %s\n⏰ **Jam:** %s WIB", tanggalWIB, jamWIB), inline = false},
                {name = "📊 Ringkasan Populasi", value = string.format("🟢 **Online:** %d / %d\n🔴 **Disconnected:** %d\n📌 **Total Terdeteksi:** %d", onlineCount, maxPlayer, disconnectedCount, totalTracked), inline = false},
                {name = "👤 Daftar Player & Lokasi Map", value = totalTracked > 0 and ("```\n" .. listText .. "\n```") or "```\nTidak ada player\n```", inline = false}
            },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if requestFunc then
        task.spawn(function()
            pcall(function()
                requestFunc({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload)})
            end)
        end)
        
        if UIStatus_PlayerMon then
            task.spawn(function()
                trackerUIPaused = true
                local statusTeks = isManual and "Test Manual Terkirim!" or "Auto Data Terkirim!"
                UIStatus_PlayerMon.Text = "Status: " .. statusTeks
                UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(100, 255, 100)
                task.wait(3)
                trackerUIPaused = false
            end)
        end
    else
        if UIStatus_PlayerMon then
            task.spawn(function()
                trackerUIPaused = true
                UIStatus_PlayerMon.Text = "Status: Executor Tidak Support!"
                UIStatus_PlayerMon.TextColor3 = Color3.fromRGB(255, 100, 100)
                task.wait(3)
                trackerUIPaused = false
            end)
        end
    end
end

-- ========================================================
-- 4. UI SYSTEM (SHADOW PANEL V8)
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
LogoBtn.Size = UDim2.new(0, 45, 0, 45); LogoBtn.Position = UDim2.new(0, 15, 0.35, 0)
LogoBtn.BackgroundColor3 = c_sidebar; LogoBtn.Text = "S"; LogoBtn.TextColor3 = c_accent
LogoBtn.Font = Enum.Font.GothamBlack; LogoBtn.TextSize = 22; LogoBtn.Active = true; LogoBtn.Draggable = true
LogoBtn.Visible = false
Instance.new("UICorner", LogoBtn).CornerRadius = UDim.new(0, 10)

local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 40); Header.BackgroundTransparency = 1

local TitleLabel = Instance.new("TextLabel", Header)
TitleLabel.Size = UDim2.new(0.4, 0, 1, 0); TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "SHADOW HUB V8"; TitleLabel.TextColor3 = c_accent
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
local TabConfig     = CreateTab("⚙️ Config Manager", false)

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

-- ========================================================
-- 5. MENU SETUP
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

local DropRotate = CreateDropdown(TabAutomation, "Auto Rotate Fishing")
local UIStatus_Rotate = CreateStatusLabel(DropRotate)
CreateToggle(DropRotate, "Enable Auto Rotate (1 Jam)", "AutoRotate", function(state)
    if not state then UIStatus_Rotate.Text = "AUTO ROTATE: OFF"; UIStatus_Rotate.TextColor3 = c_subtext end
end)

local DropBooster = CreateDropdown(TabBooster, "Graphic & Performance Booster")
CreateToggle(DropBooster, "FPS Booster (Nuke Visuals)", "FPSBooster", function(state) end)
CreateToggle(DropBooster, "Disable 3D Rendering", "Disable3D", function(state) RunService:Set3dRenderingEnabled(not state) end)
CreateToggle(DropBooster, "Clear Water (Hilangkan Air)", "ClearWater", function(state) end)
CreateToggle(DropBooster, "Limit 30 FPS", "Limit30FPS", function(state) if setfpscap then setfpscap(state and 30 or 60) end end)
CreateToggle(DropBooster, "Auto Clean RAM", "AutoRAM", function(state) end)

local DropGlobalWeb = CreateDropdown(TabWebhooks, "🔗 Global Webhook Configuration")
CreateTextBox(DropGlobalWeb, "Paste Webhook URL Discord Di Sini...", "WebhookURL", function(txt) end)
-- [UPDATE] Toggle diletakkan pada menu Webhooks untuk mengaktifkan Proxy PC
CreateToggle(DropGlobalWeb, "Proxy Webhook Discord (Khusus PC)", "UsePCProxy", function(state) end) 

local DropWebToggles = CreateDropdown(TabWebhooks, "⚙️ Active Webhook Features")
UIStatus_PlayerMon = CreateStatusLabel(DropWebToggles)

local trackerInterval = 1500
local trackerRemaining = 0
local isTrackerActive = false

CreateToggle(DropWebToggles, "Enable Player Tracker", "WebhookPlayer", function(state)
    isTrackerActive = state
    if not state then
        trackerRemaining = 0
        task.spawn(function()
            trackerUIPaused = true
            UIStatus_PlayerMon.Text = "TRACKER : DISABLED"
            UIStatus_PlayerMon.TextColor3 = c_subtext
            task.wait(1)
            trackerUIPaused = false
        end)
    else
        trackerRemaining = trackerInterval
    end
end)

local DropWebTest = CreateDropdown(TabWebhooks, "🧪 Test Webhook Triggers")
CreateButton(DropWebTest, "🚀 Kirim Test Player Tracker Manual", function() SendPlayerList(true) end)

local DropConfigSystem = CreateDropdown(TabConfig, "Configuration Manager")
CreateButton(DropConfigSystem, "💾 Save UI Settings Manual", function() SaveConfig() end)
local BtnReset = CreateButton(DropConfigSystem, "⚠️ Reset Settingan (Tanpa DC)", function() end)
BtnReset.MouseButton1Click:Connect(function()
    ResetConfig(); BtnReset.Text = "✅ Reset Berhasil! UI Diperbarui."; BtnReset.TextColor3 = Color3.fromRGB(100, 255, 100)
    task.wait(2); BtnReset.Text = "⚠️ Reset Settingan (Tanpa DC)"; BtnReset.TextColor3 = c_text
end)

-- ==========================================================
-- 6. BACKGROUND ENGINES & THREADS
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
        if ConfigData.AutoRotate then
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
                while elapsed < rotateInterval and ConfigData.AutoRotate do
                    local sisaDetik = rotateInterval - elapsed
                    UIStatus_Rotate.Text = "NEXT ROTATE: " .. formatSecondsToText(sisaDetik)
                    UIStatus_Rotate.TextColor3 = Color3.fromRGB(50, 255, 100)
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
