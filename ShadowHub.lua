local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MaterialService = game:GetService("MaterialService")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ========================================================
-- 1. DATA KOORDINAT & VARIABEL SISTEM
-- ========================================================
local spotKordinat = {
    Board = CFrame.lookAt(Vector3.new(-855.63, 44.43, 5187.01), Vector3.new(-855.63, 44.43, 5187.01) + Vector3.new(0, 0, 1)),
    Volcano = CFrame.lookAt(Vector3.new(-813.46, 59.37, 5271.69), Vector3.new(-813.46, 59.37, 5271.69) + Vector3.new(1, 0, 1)),
    Storm = CFrame.lookAt(Vector3.new(-864.27, 56.06, 5309.37), Vector3.new(-864.27, 56.06, 5309.37) + Vector3.new(-1, 0, 1)),
    Blizzard = CFrame.lookAt(Vector3.new(-968.19, 45.83, 5345.58), Vector3.new(-968.19, 45.83, 5345.58) + Vector3.new(-1, 0, -1))
}

local DatabaseIconCuaca = {
    ["118379404229807"] = "Blizzard",
    ["105076841543450"] = "Storm",
    ["76632496002371"]  = "Volcano",
}

-- STATE CONTROL
local autoTeleportAktif = false
local posisiSimpanan = nil

local autoRotateAktif = false
local standPositionRot = Vector3.new(-1290.24, -855.68, 5596.16)
local poolAngles = {-103.43, 135.57, 15.08}
local currentPoolIndex = 1
local rotateInterval = 3600

local autoShakeAktif = false
local autoSellAktif = false
local autoRAMCleaner = false
local antiAfKAktif = true

local webhookURL = ""

-- ========================================================
-- 2. ALGORITMA CORE & OPTIMIZERS
-- ========================================================
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

local function FireDirectAutoSell()
    pcall(function()
        local net = ReplicatedStorage:FindFirstChild("packages") and ReplicatedStorage.packages:FindFirstChild("Net")
        if net and net:FindFirstChild("RE/Merchant/SellAll") then
            net["RE/Merchant/SellAll"]:FireServer()
        elseif ReplicatedStorage:FindFirstChild("events") and ReplicatedStorage.events:FindFirstChild("selleverything") then
            ReplicatedStorage.events.selleverything:InvokeServer()
        end
    end)
end

local function SendDiscordWebhook(msg)
    if webhookURL == "" then return end
    pcall(function()
        local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
        if req then
            req({
                Url = webhookURL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode({
                    username = "Shadow Hub Tracker",
                    content = "```" .. msg .. "```"
                })
            })
        end
    end)
end

-- ========================================================
-- 3. UI SYSTEM & MODERN SIDEBAR
-- ========================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Shadow_Panel_V6"
local targetGui = (gethui and gethui()) or game:GetService("CoreGui") or player.PlayerGui
ScreenGui.Parent = targetGui

local c_bg = Color3.fromRGB(15, 15, 18)
local c_sidebar = Color3.fromRGB(20, 20, 24)
local c_content = Color3.fromRGB(25, 25, 30)
local c_accent = Color3.fromRGB(140, 60, 255)
local c_text = Color3.fromRGB(240, 240, 240)
local c_subtext = Color3.fromRGB(170, 170, 170)

local LogoBtn = Instance.new("TextButton", ScreenGui)
LogoBtn.Size = UDim2.new(0, 45, 0, 45); LogoBtn.Position = UDim2.new(0, 15, 0.35, 0)
LogoBtn.BackgroundColor3 = c_sidebar; LogoBtn.Text = "S"; LogoBtn.TextColor3 = c_accent
LogoBtn.Font = Enum.Font.GothamBlack; LogoBtn.TextSize = 22; LogoBtn.Active = true; LogoBtn.Draggable = true
Instance.new("UICorner", LogoBtn).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", LogoBtn).Color = c_accent; LogoBtn.UIStroke.Thickness = 2

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 540, 0, 330); MainFrame.Position = UDim2.new(0.5, -270, 0.5, -165)
MainFrame.BackgroundColor3 = c_bg; MainFrame.Active = true; MainFrame.Draggable = true
MainFrame.Visible = false; MainFrame.ClipsDescendants = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", MainFrame).Color = Color3.fromRGB(40, 40, 50); MainFrame.UIStroke.Thickness = 1

local ResizeGrip = Instance.new("TextButton", MainFrame)
ResizeGrip.Size = UDim2.new(0, 18, 0, 18); ResizeGrip.Position = UDim2.new(1, -18, 1, -18)
ResizeGrip.BackgroundTransparency = 1; ResizeGrip.Text = "◢"; ResizeGrip.TextColor3 = c_subtext
ResizeGrip.Font = Enum.Font.GothamBold; ResizeGrip.TextSize = 12; ResizeGrip.ZIndex = 10

local isResizing, dragStartPos, startSize
ResizeGrip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isResizing = true; dragStartPos = input.Position; startSize = MainFrame.Size
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then isResizing = false end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isResizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartPos
        MainFrame.Size = UDim2.new(0, math.max(420, startSize.X.Offset + delta.X), 0, math.max(240, startSize.Y.Offset + delta.Y))
    end
end)

local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 40); Header.BackgroundTransparency = 1

local TitleLabel = Instance.new("TextLabel", Header)
TitleLabel.Size = UDim2.new(0.4, 0, 1, 0); TitleLabel.Position = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "SHADOW HUB V6"
TitleLabel.TextColor3 = c_accent; TitleLabel.Font = Enum.Font.GothamBold; TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

local DiscordBtn = Instance.new("TextButton", Header)
DiscordBtn.Size = UDim2.new(0, 130, 0, 24); DiscordBtn.Position = UDim2.new(1, -180, 0.5, -12)
DiscordBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 32); DiscordBtn.Text = "discord.gg/shadow"
DiscordBtn.TextColor3 = Color3.fromRGB(180, 180, 190); DiscordBtn.Font = Enum.Font.GothamSemibold; DiscordBtn.TextSize = 10
Instance.new("UICorner", DiscordBtn).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", DiscordBtn).Color = Color3.fromRGB(50, 50, 65)

DiscordBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard("https://discord.gg/u7fSg6JGn")
        DiscordBtn.Text = "COPIED LINK!"; DiscordBtn.TextColor3 = c_accent
        task.wait(1.5)
        DiscordBtn.Text = "discord.gg/shadow"; DiscordBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
    end
end)

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 40, 0, 40); CloseBtn.Position = UDim2.new(1, -40, 0, 0)
CloseBtn.BackgroundTransparency = 1; CloseBtn.Text = "—"; CloseBtn.TextColor3 = c_accent
CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 16

LogoBtn.MouseButton1Click:Connect(function() MainFrame.Visible = true; LogoBtn.Visible = false end)
CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false; LogoBtn.Visible = true end)

-- SIDEBAR SYSTEM
local Sidebar = Instance.new("Frame", MainFrame)
Sidebar.Size = UDim2.new(0, 140, 1, -40); Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = c_sidebar; Sidebar.BorderSizePixel = 0
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 10)
local SidebarList = Instance.new("UIListLayout", Sidebar)
SidebarList.Padding = UDim.new(0, 4); SidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center

local Pages = {}

local function CreateTab(name, active)
    local btn = Instance.new("TextButton", Sidebar)
    btn.Size = UDim2.new(0.92, 0, 0, 34); btn.BackgroundColor3 = active and Color3.fromRGB(35, 35, 45) or c_sidebar
    btn.Text = "  " .. name; btn.TextColor3 = active and c_text or c_subtext
    btn.Font = Enum.Font.GothamSemibold; btn.TextSize = 11; btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false; btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local indicator = Instance.new("Frame", btn)
    indicator.Size = UDim2.new(0, 3, 0.6, 0); indicator.Position = UDim2.new(0, 2, 0.2, 0)
    indicator.BackgroundColor3 = c_accent; indicator.BorderSizePixel = 0; indicator.Visible = active
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

    local PageScroll = Instance.new("ScrollingFrame", MainFrame)
    PageScroll.Size = UDim2.new(1, -150, 1, -50); PageScroll.Position = UDim2.new(0, 150, 0, 40)
    PageScroll.BackgroundTransparency = 1; PageScroll.BorderSizePixel = 0
    PageScroll.ScrollBarThickness = 3; PageScroll.ScrollBarImageColor3 = c_accent; PageScroll.Visible = active
    local Layout = Instance.new("UIListLayout", PageScroll)
    Layout.Padding = UDim.new(0, 8); Layout.SortOrder = Enum.SortOrder.LayoutOrder

    Pages[name] = {Button = btn, Indicator = indicator, Frame = PageScroll}

    btn.MouseButton1Click:Connect(function()
        for pName, pData in pairs(Pages) do
            local isTarget = (pName == name)
            pData.Frame.Visible = isTarget
            pData.Indicator.Visible = isTarget
            pData.Button.BackgroundColor3 = isTarget and Color3.fromRGB(35, 35, 45) or c_sidebar
            pData.Button.TextColor3 = isTarget and c_text or c_subtext
        end
    end)
    return PageScroll
end

-- PAGE CREATION
local TabAutomation = CreateTab("⚡ Automation", true)
local TabFishing    = CreateTab("🎣 Fishing Core", false)
local TabBooster    = CreateTab("🚀 Booster & RAM", false)
local TabUtility    = CreateTab("🛡️ Utility", false)

-- UI BUILDER HELPERS
local function CreateDropdown(parent, titleText)
    local DropdownFrame = Instance.new("Frame", parent)
    DropdownFrame.Size = UDim2.new(1, -10, 0, 38); DropdownFrame.BackgroundColor3 = c_content
    DropdownFrame.ClipsDescendants = true; DropdownFrame.AutomaticSize = Enum.AutomaticSize.Y
    Instance.new("UICorner", DropdownFrame).CornerRadius = UDim.new(0, 8)
    
    local TopBtn = Instance.new("TextButton", DropdownFrame)
    TopBtn.Size = UDim2.new(1, 0, 0, 38); TopBtn.BackgroundTransparency = 1
    TopBtn.Text = "   " .. titleText; TopBtn.TextColor3 = c_text; TopBtn.Font = Enum.Font.GothamBold; TopBtn.TextSize = 11
    TopBtn.TextXAlignment = Enum.TextXAlignment.Left
    
    local Arrow = Instance.new("TextLabel", TopBtn)
    Arrow.Size = UDim2.new(0, 40, 1, 0); Arrow.Position = UDim2.new(1, -40, 0, 0)
    Arrow.BackgroundTransparency = 1; Arrow.Text = "▼"; Arrow.TextColor3 = c_accent; Arrow.Font = Enum.Font.GothamBold; Arrow.TextSize = 11
    
    local ItemsContainer = Instance.new("Frame", DropdownFrame)
    ItemsContainer.Size = UDim2.new(1, 0, 0, 0); ItemsContainer.Position = UDim2.new(0, 0, 0, 38)
    ItemsContainer.BackgroundTransparency = 1; ItemsContainer.AutomaticSize = Enum.AutomaticSize.Y
    local ItemLayout = Instance.new("UIListLayout", ItemsContainer)
    ItemLayout.Padding = UDim.new(0, 6); ItemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    Instance.new("UIPadding", ItemsContainer).PaddingBottom = UDim.new(0, 8)

    local isOpen = false
    TopBtn.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        Arrow.Rotation = isOpen and 180 or 0
        ItemsContainer.Visible = isOpen
    end)
    ItemsContainer.Visible = false
    return ItemsContainer
end

local function CreateToggle(parent, text, callback)
    local Frame = Instance.new("Frame", parent)
    Frame.Size = UDim2.new(0.95, 0, 0, 32); Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)
    
    local Label = Instance.new("TextLabel", Frame)
    Label.Size = UDim2.new(0.65, 0, 1, 0); Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1; Label.Text = text; Label.TextColor3 = c_text
    Label.Font = Enum.Font.GothamSemibold; Label.TextSize = 10; Label.TextXAlignment = Enum.TextXAlignment.Left
    
    local ToggleBtn = Instance.new("TextButton", Frame)
    ToggleBtn.Size = UDim2.new(0, 36, 0, 18); ToggleBtn.Position = UDim2.new(1, -45, 0.5, -9)
    ToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70); ToggleBtn.Text = ""
    Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)
    
    local Circle = Instance.new("Frame", ToggleBtn)
    Circle.Size = UDim2.new(0, 14, 0, 14); Circle.Position = UDim2.new(0, 2, 0.5, -7)
    Circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Instance.new("UICorner", Circle).CornerRadius = UDim.new(1, 0)
    
    local state = false
    ToggleBtn.MouseButton1Click:Connect(function()
        state = not state
        local targetColor = state and c_accent or Color3.fromRGB(60, 60, 70)
        local targetPos = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        TweenService:Create(ToggleBtn, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play()
        TweenService:Create(Circle, TweenInfo.new(0.2), {Position = targetPos}):Play()
        callback(state)
    end)
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

local function CreateTextBox(parent, placeholder, callback)
    local BoxFrame = Instance.new("Frame", parent)
    BoxFrame.Size = UDim2.new(0.95, 0, 0, 32); BoxFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    Instance.new("UICorner", BoxFrame).CornerRadius = UDim.new(0, 6)
    
    local Box = Instance.new("TextBox", BoxFrame)
    Box.Size = UDim2.new(1, -20, 1, 0); Box.Position = UDim2.new(0, 10, 0, 0)
    Box.BackgroundTransparency = 1; Box.PlaceholderText = placeholder; Box.Text = ""
    Box.TextColor3 = c_text; Box.PlaceholderColor3 = c_subtext; Box.Font = Enum.Font.GothamSemibold; Box.TextSize = 10
    Box.TextXAlignment = Enum.TextXAlignment.Left; Box.ClearTextOnFocus = false
    
    Box.FocusLost:Connect(function() callback(Box.Text) end)
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
-- 4. PENGISIAN MENU DI TIGA TAB UTAMA
-- ========================================================

-- TAB 1: AUTOMATION
local DropElemental = CreateDropdown(TabAutomation, "Event Elemental TP")
local UIStatus_Elemental = CreateStatusLabel(DropElemental)

CreateToggle(DropElemental, "Enable Auto TP Cuaca", function(state)
    autoTeleportAktif = state
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if state then
        if hrp and not posisiSimpanan then posisiSimpanan = hrp.CFrame end
    else
        UIStatus_Elemental.Text = "SYSTEM PAUSED"
        UIStatus_Elemental.TextColor3 = c_subtext
    end
end)

local DropRotate = CreateDropdown(TabAutomation, "Auto Rotate Fishing")
local UIStatus_Rotate = CreateStatusLabel(DropRotate)

CreateToggle(DropRotate, "Enable Auto Rotate (1 Jam)", function(state)
    autoRotateAktif = state
    if not state then
        UIStatus_Rotate.Text = "AUTO ROTATE: OFF"
        UIStatus_Rotate.TextColor3 = c_subtext
    end
end)

-- TAB 2: FISHING CORE
local DropMechanics = CreateDropdown(TabFishing, "Core Fishing Mechanics")

CreateToggle(DropMechanics, "Instant Shake Bypass", function(state)
    autoShakeAktif = state
end)

CreateToggle(DropMechanics, "Direct Remote Auto Sell", function(state)
    autoSellAktif = state
end)

CreateButton(DropMechanics, "Sell All Now (Instant)", function()
    FireDirectAutoSell()
end)

-- TAB 3: BOOSTER & RAM
local DropBooster = CreateDropdown(TabBooster, "Graphic & Performance Booster")

local function nukeVisuals(obj)
    if player.Character and (obj == player.Character or obj:IsDescendantOf(player.Character)) then return end
    pcall(function()
        if obj:IsA("BasePart") then
            obj.Material = Enum.Material.SmoothPlastic
            obj.Reflectance = 0; obj.CastShadow = false
            if obj:IsA("MeshPart") then obj.TextureID = "" end
        elseif obj:IsA("SurfaceAppearance") or obj:IsA("Texture") or obj:IsA("Decal") then
            obj:Destroy()
        elseif obj:IsA("PostEffect") or obj:IsA("Atmosphere") or obj:IsA("ParticleEmitter") then
            obj:Destroy()
        end
    end)
end

CreateToggle(DropBooster, "FPS Booster (Nuke Visuals)", function(state)
    if state then
        pcall(function()
            if setfpscap then setfpscap(60) end
            if sethiddenproperty then sethiddenproperty(Lighting, "Technology", 2) end
            settings().Rendering.QualityLevel = 1
            Lighting.GlobalShadows = false
            MaterialService.Use2022Materials = false
        end)
        for _, mat in pairs(Enum.Material:GetEnumItems()) do
            pcall(function()
                local variant = Instance.new("MaterialVariant")
                variant.Name = "Nuke_" .. mat.Name
                variant.BaseMaterial = mat
                variant.ColorMap = ""
                variant.Parent = MaterialService
                MaterialService:SetMaterialOverride(mat, variant.Name)
            end)
        end
        for _, obj in pairs(workspace:GetDescendants()) do nukeVisuals(obj) end
        for _, obj in pairs(Lighting:GetDescendants()) do nukeVisuals(obj) end
        workspace.DescendantAdded:Connect(nukeVisuals)
        Lighting.DescendantAdded:Connect(nukeVisuals)
    end
end)

CreateToggle(DropBooster, "Disable 3D Rendering (GPU Saver)", function(state)
    RunService:Set3dRenderingEnabled(not state)
end)

CreateToggle(DropBooster, "Clear Water & Fog Effects", function(state)
    pcall(function()
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            terrain.WaterWaveSize = state and 0 or 0.15
            terrain.WaterWaveSpeed = state and 0 or 10
            terrain.WaterReflectance = state and 0 or 1
            terrain.WaterTransparency = state and 1 or 0.8
        end
        Lighting.FogEnd = state and 9e9 or 1000
    end)
end)

CreateToggle(DropBooster, "Limit 30 FPS (Cold AFK)", function(state)
    if setfpscap then setfpscap(state and 30 or 60) end
end)

CreateToggle(DropBooster, "Auto RAM Cleaner (60s)", function(state)
    autoRAMCleaner = state
end)

-- TAB 4: UTILITY & WEBHOOK
local DropUtility = CreateDropdown(TabUtility, "System & Protection")

CreateToggle(DropUtility, "Engine Anti-AFK (VirtualUser)", function(state)
    antiAfKAktif = state
end)

CreateButton(DropUtility, "Set Save Position", function()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then posisiSimpanan = hrp.CFrame end
end)

CreateButton(DropUtility, "Force Return Position", function() PulangKeSetPos() end)

local DropWebhook = CreateDropdown(TabUtility, "Discord Webhook Tracker")

CreateTextBox(DropWebhook, "Paste Discord Webhook URL...", function(txt)
    webhookURL = txt
end)

CreateButton(DropWebhook, "Send Manual Test Report", function()
    local leaderstats = player:FindFirstChild("leaderstats")
    local cVal = leaderstats and leaderstats:FindFirstChild("C$") and leaderstats["C$"].Value or "N/A"
    SendDiscordWebhook("👤 User: " .. player.Name .. "\n💰 Balance: C$ " .. tostring(cVal) .. "\n🟢 Status: ONLINE & ACTIVE")
end)

-- ==========================================================
-- 5. ASYNCHRONOUS BACKGROUND THREADS (OPTIMIZED LOW-CPU)
-- ==========================================================

-- Anti-AFK Signal Hook
player.Idled:Connect(function()
    if antiAfKAktif then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

-- Auto RAM Memory Cleaner Loop
task.spawn(function()
    while true do
        task.wait(60)
        if autoRAMCleaner then
            collectgarbage("collect")
        end
    end
end)

-- Auto Shake Bypass Engine
task.spawn(function()
    while true do
        task.wait(0.1)
        if autoShakeAktif then
            pcall(function()
                local pGui = player:FindFirstChild("PlayerGui")
                local shakeUI = pGui and pGui:FindFirstChild("shakeui")
                if shakeUI and shakeUI:FindFirstChild("safezone") then
                    local btn = shakeUI.safezone:FindFirstChild("button")
                    if btn and btn.Visible then
                        local px = btn.AbsolutePosition.X + (btn.AbsoluteSize.X / 2)
                        local py = btn.AbsolutePosition.Y + (btn.AbsoluteSize.Y / 2)
                        VirtualInputManager:SendMouseButtonEvent(px, py, 0, true, game, 0)
                        VirtualInputManager:SendMouseButtonEvent(px, py, 0, false, game, 0)
                    end
                end
            end)
        end
    end
end)

-- Auto Sell Interval Loop (Every 2 Minutes)
task.spawn(function()
    while true do
        task.wait(120)
        if autoSellAktif then
            FireDirectAutoSell()
        end
    end
end)

-- Loop Auto TP Elemental
task.spawn(function()
    while true do
        task.wait(1)
        if autoTeleportAktif then
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local schedule = GetEventScheduleWIB()

            if schedule.state == "COOLDOWN" then
                PulangKeSetPos()
                while autoTeleportAktif do
                    local realTimeSchedule = GetEventScheduleWIB()
                    if realTimeSchedule.state == "ACTIVE" then break end 
                    UIStatus_Elemental.Text = "CD: " .. formatSecondsToText(realTimeSchedule.timeLeft)
                    UIStatus_Elemental.TextColor3 = Color3.fromRGB(255, 200, 50)
                    task.wait(1)
                end
            elseif schedule.state == "ACTIVE" then
                UIStatus_Elemental.Text = "MENUJU PAPAN..."
                UIStatus_Elemental.TextColor3 = Color3.fromRGB(100, 200, 255)
                hrp.CFrame = spotKordinat.Board
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                task.wait(1.5)
                
                local cuacaAktif = GetWeatherIconOnly()
                if cuacaAktif then
                    local targetCFrame = spotKordinat[cuacaAktif]
                    while autoTeleportAktif do
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
                    UIStatus_Elemental.Text = "MENUNGGU ICON CUACA..."
                    UIStatus_Elemental.TextColor3 = c_subtext
                    task.wait(1)
                end
            end
        end
    end
end)

-- Loop Auto Rotate 1 Jam (3600 Detik)
task.spawn(function()
    while true do
        if autoRotateAktif then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            
            if hrp then
                local targetAngle = math.rad(poolAngles[currentPoolIndex])
                local targetCFrame = CFrame.new(standPositionRot) * CFrame.Angles(0, targetAngle, 0)
                
                for i = 1, 6 do
                    if hrp and hrp.Parent then
                        hrp.CFrame = targetCFrame
                        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                    end
                    task.wait(0.05)
                end
                
                currentPoolIndex = currentPoolIndex + 1
                if currentPoolIndex > #poolAngles then currentPoolIndex = 1 end
                
                local elapsed = 0
                while elapsed < rotateInterval and autoRotateAktif do
                    local sisaDetik = rotateInterval - elapsed
                    UIStatus_Rotate.Text = "NEXT ROTATE: " .. formatSecondsToText(sisaDetik)
                    UIStatus_Rotate.TextColor3 = Color3.fromRGB(50, 255, 100)
                    task.wait(1)
                    elapsed = elapsed + 1
                end
            else
                task.wait(1)
            end
        else
            task.wait(1)
        end
    end
end)
