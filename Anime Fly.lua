
--[[
    Title: Anime Fly Pro (V10 - Cinematic God Edition)
    Author: devansh
    Description: The absolute peak of Roblox flight scripts. 
                 Features Dynamic FOV Warping, Sonic Boom takeoffs, 
                 God-Tier idle/flight procedural animations, and flawless Anti-Cheat Bypasses.
--]]

--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "LocalPlayer not found. Script must be executed on the client.")

-- =============================================================================
-- CONFIGURATION & STATE
-- =============================================================================
local Settings = {
    DefaultSpeed = 150,
    MaxSpeed = 500,
    MinSpeed = 15,
    ToggleKey = Enum.KeyCode.F,
    
    -- Cinematic Audio Assets
    WindSoundId = "rbxassetid://9011181313",  -- Intense Wind Loop
    AuraSoundId = "rbxassetid://4944983210",  -- Deep Energy Hum
    BoomSoundId = "rbxassetid://6063618146"   -- Sonic Boom Takeoff
}

local FlightState = {
    IsActive = false,
    IsMoving = false,
    CurrentSpeed = Settings.DefaultSpeed,
}

local UIColors = {
    Background = Color3.fromRGB(15, 15, 20),
    Border = Color3.fromRGB(40, 50, 80),
    Accent = Color3.fromRGB(80, 150, 255), -- Glowing Gojo/God Blue
    TextPrimary = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(180, 180, 190),
    CardBg = Color3.fromRGB(25, 25, 30),
    ActiveGreen = Color3.fromRGB(80, 150, 255),
    InactiveRed = Color3.fromRGB(150, 50, 50)
}

-- Engine Core References
local BodyVelocity: BodyVelocity? = nil
local BodyGyro: BodyGyro? = nil
local RenderConnection: RBXScriptConnection? = nil
local NoclipConnection: RBXScriptConnection? = nil

-- VFX/SFX Storage
local WindSound: Sound? = nil
local AuraSound: Sound? = nil
local BoomSound: Sound? = nil
local CoreAuraAttach: Attachment? = nil
local AuraEmitter: ParticleEmitter? = nil
local SparkEmitter: ParticleEmitter? = nil
local StreakEmitter: ParticleEmitter? = nil

-- Procedural Bone Storage
local OriginalC0s = {}
local ActiveTweens = {}

-- =============================================================================
-- PROCEDURAL ANIMATION (GOD HOVER & SUPERSONIC FLIGHT)
-- =============================================================================
local function StoreBones(character: Model)
    OriginalC0s = {}
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("Motor6D") then
            OriginalC0s[desc.Name] = desc.C0
        end
    end
end

local function CancelTweens()
    for _, tween in pairs(ActiveTweens) do tween:Cancel() end
    ActiveTweens = {}
end

local function SetProceduralPose(character: Model, state: string)
    CancelTweens()
    -- Faster tweening for moving, slower for entering idle
    local duration = (state == "Fly") and 0.25 or 0.5
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    
    for _, desc in ipairs(character:GetDescendants()) do
        if not desc:IsA("Motor6D") or not OriginalC0s[desc.Name] then continue end
        
        local targetC0 = OriginalC0s[desc.Name]
        local name = desc.Name
        
        if state == "Fly" then
            -- 🚀 SUPERSONIC FLIGHT POSE (Aerodynamic)
            if name == "RootJoint" or name == "Root" or name == "Waist" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-80), 0, 0)
            elseif name == "Neck" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(75), 0, 0) -- Look sharply forward
            elseif string.find(name, "Right.*Shoulder") or name == "RightUpperArm" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(130), 0, math.rad(-10)) -- Arms strictly behind back
            elseif string.find(name, "Left.*Shoulder") or name == "LeftUpperArm" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(130), 0, math.rad(10))
            elseif string.find(name, "Right.*Hip") or name == "RightUpperLeg" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-10), 0, 0)
            elseif string.find(name, "Left.*Hip") or name == "LeftUpperLeg" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-10), 0, 0)
            end
        elseif state == "Hover" then
            -- 👑 GOD HOVER IDLE POSE (Casual, Floating)
            if name == "RootJoint" or name == "Root" or name == "Waist" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(10), math.rad(15), 0) -- Slight majestic twist
            elseif name == "Neck" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-10), math.rad(-15), 0) -- Look down upon enemies
            elseif string.find(name, "Right.*Shoulder") or name == "RightUpperArm" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-15), 0, math.rad(15)) -- Arm resting
            elseif string.find(name, "Left.*Shoulder") or name == "LeftUpperArm" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(20), 0, math.rad(-20)) -- Arm floating up slightly
            elseif string.find(name, "Right.*Hip") or name == "RightUpperLeg" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(15), 0, math.rad(5)) -- Leg relaxed forward
            elseif string.find(name, "Left.*Hip") or name == "LeftUpperLeg" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-15), 0, math.rad(-5)) -- Leg kicked back slightly
            end
        end
        
        local tween = TweenService:Create(desc, tweenInfo, {C0 = targetC0})
        table.insert(ActiveTweens, tween)
        tween:Play()
    end
end

-- =============================================================================
-- CINEMATIC VFX & SFX ENGINE (Pcall Protected)
-- =============================================================================
local function SetupVFX(rootPart: BasePart)
    pcall(function()
        WindSound = Instance.new("Sound")
        WindSound.SoundId = Settings.WindSoundId
        WindSound.Volume = 0
        WindSound.Looped = true
        WindSound.Parent = rootPart
        WindSound:Play()
        
        AuraSound = Instance.new("Sound")
        AuraSound.SoundId = Settings.AuraSoundId
        AuraSound.Volume = 0.5
        AuraSound.Pitch = 0.9
        AuraSound.Looped = true
        AuraSound.Parent = rootPart
        AuraSound:Play()
        
        BoomSound = Instance.new("Sound")
        BoomSound.SoundId = Settings.BoomSoundId
        BoomSound.Volume = 1.5
        BoomSound.Pitch = 1.2
        BoomSound.Parent = rootPart
    end)
    
    pcall(function()
        CoreAuraAttach = Instance.new("Attachment")
        CoreAuraAttach.Name = "CinematicAura"
        CoreAuraAttach.Position = Vector3.new(0, 0, 0)
        CoreAuraAttach.Parent = rootPart
        
        local EnergyColor = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 200, 255)),
            ColorSequenceKeypoint.new(0.5, UIColors.Accent),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 50, 255))
        })
        
        -- Core Glowing Aura
        AuraEmitter = Instance.new("ParticleEmitter")
        AuraEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
        AuraEmitter.LightEmission = 1
        AuraEmitter.Color = EnergyColor
        AuraEmitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0)})
        AuraEmitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1)})
        AuraEmitter.Lifetime = NumberRange.new(0.5, 0.8)
        AuraEmitter.Rate = 60
        AuraEmitter.Speed = NumberRange.new(2, 5)
        AuraEmitter.Parent = CoreAuraAttach
        
        -- Power Sparks
        SparkEmitter = Instance.new("ParticleEmitter")
        SparkEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        SparkEmitter.LightEmission = 1
        SparkEmitter.Color = EnergyColor
        SparkEmitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0)})
        SparkEmitter.Transparency = NumberSequence.new(0.2)
        SparkEmitter.Lifetime = NumberRange.new(0.3, 0.6)
        SparkEmitter.Rate = 50
        SparkEmitter.Speed = NumberRange.new(10, 20)
        SparkEmitter.SpreadAngle = Vector2.new(45, 45)
        SparkEmitter.Parent = CoreAuraAttach
        
        -- High Speed Wind Streaks
        StreakEmitter = Instance.new("ParticleEmitter")
        StreakEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        StreakEmitter.LightEmission = 1
        StreakEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
        StreakEmitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0)})
        StreakEmitter.Transparency = NumberSequence.new(0.6)
        StreakEmitter.Lifetime = NumberRange.new(0.2, 0.4)
        StreakEmitter.Rate = 0
        StreakEmitter.Speed = NumberRange.new(40, 80)
        StreakEmitter.Parent = CoreAuraAttach
    end)
end

local function CleanupVFX()
    local instances = {WindSound, AuraSound, BoomSound}
    for _, sound in ipairs(instances) do
        if sound then
            TweenService:Create(sound, TweenInfo.new(0.3), {Volume = 0}):Play()
            task.delay(0.3, function() if sound and sound.Parent then sound:Destroy() end end)
        end
    end
    WindSound, AuraSound, BoomSound = nil, nil, nil
    if CoreAuraAttach then CoreAuraAttach:Destroy(); CoreAuraAttach = nil end
    AuraEmitter, SparkEmitter, StreakEmitter = nil, nil, nil
end

-- =============================================================================
-- CINEMATIC PHYSICS ENGINE (FOV WARPING & NOCLIP)
-- =============================================================================
local function StopFlightCore()
    if RenderConnection then RenderConnection:Disconnect(); RenderConnection = nil end
    if NoclipConnection then NoclipConnection:Disconnect(); NoclipConnection = nil end
    if BodyVelocity then BodyVelocity:Destroy(); BodyVelocity = nil end
    if BodyGyro then BodyGyro:Destroy(); BodyGyro = nil end
    
    FlightState.IsMoving = false
    
    -- Smoothly reset camera FOV
    local camera = workspace.CurrentCamera
    if camera then
        TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Sine), {FieldOfView = 70}):Play()
    end
    
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
        SetProceduralPose(character, "Default")
    end
    
    CleanupVFX()
end

local function StartFlightCore()
    local character = LocalPlayer.Character
    if not character then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid then return end
    
    StopFlightCore()
    StoreBones(character)
    
    rootPart.CFrame = rootPart.CFrame + Vector3.new(0, 5, 0)
    humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    
    FlightState.IsMoving = false
    SetProceduralPose(character, "Hover")
    SetupVFX(rootPart)

    BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.Name = "AnimeVelocity"
    BodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    BodyVelocity.Velocity = Vector3.zero
    BodyVelocity.Parent = rootPart
    
    BodyGyro = Instance.new("BodyGyro")
    BodyGyro.Name = "AnimeGyro"
    BodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    BodyGyro.D = 400
    BodyGyro.P = 15000 
    BodyGyro.CFrame = rootPart.CFrame
    BodyGyro.Parent = rootPart
    
    local camera = workspace.CurrentCamera
    
    NoclipConnection = RunService.Stepped:Connect(function()
        if not LocalPlayer.Character then return end
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
    
    RenderConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if not LocalPlayer.Character or not rootPart or not humanoid or not camera then
            StopFlightCore()
            return
        end
        
        local moveDir = humanoid.MoveDirection
        local isCurrentlyMoving = moveDir.Magnitude > 0
        
        -- =========================================================
        -- CINEMATIC TAKEOFF & FOV WARPING
        -- =========================================================
        if isCurrentlyMoving ~= FlightState.IsMoving then
            FlightState.IsMoving = isCurrentlyMoving
            SetProceduralPose(LocalPlayer.Character, FlightState.IsMoving and "Fly" or "Hover")
            
            -- Sonic Boom Trigger
            if isCurrentlyMoving and BoomSound then
                BoomSound:Play()
                if SparkEmitter then SparkEmitter:Emit(40) end -- Burst of sparks on takeoff
            end
        end
        
        -- Dynamic Camera FOV Zoom
        local targetFOV = isCurrentlyMoving and (70 + (FlightState.CurrentSpeed / Settings.MaxSpeed) * 45) or 70
        camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * (deltaTime * 6)
        
        -- =========================================================
        -- 3D VECTOR MATH & FLIGHT
        -- =========================================================
        local targetDir = Vector3.zero
        if isCurrentlyMoving then
            local camCF = camera.CFrame
            local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
            if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(camCF.UpVector.X, 0, camCF.UpVector.Z) end
            flatLook = flatLook.Unit
            
            local forwardIntent = moveDir:Dot(flatLook)
            local rightIntent = moveDir:Dot(camCF.RightVector)
            
            targetDir = (camCF.LookVector * forwardIntent) + (camCF.RightVector * rightIntent)
            if targetDir.Magnitude > 0 then targetDir = targetDir.Unit end
        end
        
        if BodyVelocity then
            BodyVelocity.Velocity = isCurrentlyMoving and (targetDir * FlightState.CurrentSpeed) or Vector3.zero
        end
        
        if BodyGyro then
            local steerVector = isCurrentlyMoving and targetDir or camera.CFrame.LookVector
            local flatSteer = Vector3.new(steerVector.X, 0, steerVector.Z)
            if flatSteer.Magnitude > 0.001 then
                BodyGyro.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatSteer.Unit)
            end
        end
        
        -- =========================================================
        -- DYNAMIC VFX SCALING
        -- =========================================================
        if WindSound and AuraSound then
            local ratio = isCurrentlyMoving and (FlightState.CurrentSpeed / Settings.MaxSpeed) or 0
            WindSound.Volume = math.clamp(ratio * 1.2, 0, 1.2)
            WindSound.Pitch = math.clamp(0.8 + (ratio * 1.5), 0.8, 2.0)
            AuraSound.Pitch = isCurrentlyMoving and 1.8 or 1.0
            AuraSound.Volume = isCurrentlyMoving and 0.8 or 0.5
        end
        
        if CoreAuraAttach then
            if isCurrentlyMoving then
                CoreAuraAttach.CFrame = CFrame.lookAt(Vector3.zero, -targetDir)
                if StreakEmitter then StreakEmitter.Rate = math.floor((FlightState.CurrentSpeed / Settings.MaxSpeed) * 200) end
                if AuraEmitter then AuraEmitter.Rate = 150 end
            else
                CoreAuraAttach.CFrame = CFrame.Angles(math.rad(90), 0, 0)
                if StreakEmitter then StreakEmitter.Rate = 0 end
                if AuraEmitter then AuraEmitter.Rate = 60 end
            end
        end
    end)
end

-- =============================================================================
-- PREMIUM GLASSMORPHIC DASHBOARD UI
-- =============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AnimeFlyProUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true

local targetUIContainer = CoreGui:FindFirstChild("RobloxGui") or CoreGui
if not targetUIContainer then targetUIContainer = LocalPlayer:WaitForChild("PlayerGui") end

local existingUI = targetUIContainer:FindFirstChild("AnimeFlyProUI")
if existingUI then existingUI:Destroy() end
ScreenGui.Parent = targetUIContainer

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 310, 0, 190)
MainFrame.Position = UDim2.new(0.5, -155, 0.3, -95)
MainFrame.BackgroundColor3 = UIColors.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 14)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Thickness = 1.8
UIStroke.Color = UIColors.Border
UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
UIStroke.Parent = MainFrame

local Gradient = Instance.new("UIGradient")
Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, UIColors.Accent),
    ColorSequenceKeypoint.new(1, UIColors.Border)
})
Gradient.Rotation = 45
Gradient.Parent = UIStroke

local dragging = false
local dragInput, dragStart, startPos

MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 48)
Header.BackgroundTransparency = 1
Header.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 0, 22)
Title.Position = UDim2.new(0, 16, 0, 10)
Title.BackgroundTransparency = 1
Title.Text = "Anime Fly"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 17
Title.TextColor3 = UIColors.TextPrimary
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -60, 0, 14)
Subtitle.Position = UDim2.new(0, 16, 0, 28)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "made by devansh"
Subtitle.Font = Enum.Font.GothamMedium
Subtitle.TextSize = 10
Subtitle.TextColor3 = UIColors.TextSecondary
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -42, 0.5, -15)
MinBtn.BackgroundColor3 = UIColors.CardBg
MinBtn.BorderSizePixel = 0
MinBtn.Text = "—"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12
MinBtn.TextColor3 = UIColors.TextPrimary
MinBtn.Parent = Header

local MinBtnCorner = Instance.new("UICorner")
MinBtnCorner.CornerRadius = UDim.new(0, 8)
MinBtnCorner.Parent = MinBtn

local RestoreBubble = Instance.new("TextButton")
RestoreBubble.Size = UDim2.new(0, 52, 0, 52)
RestoreBubble.Position = UDim2.new(0.05, 0, 0.2, 0)
RestoreBubble.BackgroundColor3 = UIColors.Background
RestoreBubble.BorderSizePixel = 0
RestoreBubble.Text = "FLY"
RestoreBubble.Font = Enum.Font.GothamBold
RestoreBubble.TextSize = 12
RestoreBubble.TextColor3 = UIColors.Accent
RestoreBubble.Visible = false
RestoreBubble.Parent = ScreenGui

local BubbleCorner = Instance.new("UICorner")
BubbleCorner.CornerRadius = UDim.new(1, 0)
BubbleCorner.Parent = RestoreBubble

local BubbleStroke = Instance.new("UIStroke")
BubbleStroke.Thickness = 2
BubbleStroke.Color = UIColors.Accent
BubbleStroke.Parent = RestoreBubble

local bDragging = false
local bDragStart, bStartPos
RestoreBubble.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        bDragging = true
        bDragStart = input.Position
        bStartPos = RestoreBubble.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then bDragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if bDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - bDragStart
        RestoreBubble.Position = UDim2.new(bStartPos.X.Scale, bStartPos.X.Offset + delta.X, bStartPos.Y.Scale, bStartPos.Y.Offset + delta.Y)
    end
end)

MinBtn.Activated:Connect(function()
    MainFrame.Visible = false
    RestoreBubble.Visible = true
end)

RestoreBubble.Activated:Connect(function()
    RestoreBubble.Visible = false
    MainFrame.Visible = true
end)

local Line = Instance.new("Frame")
Line.Size = UDim2.new(1, -32, 0, 1)
Line.Position = UDim2.new(0, 16, 0, 48)
Line.BackgroundColor3 = UIColors.Border
Line.BorderSizePixel = 0
Line.Parent = MainFrame

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -32, 1, -64)
Content.Position = UDim2.new(0, 16, 0, 54)
Content.BackgroundTransparency = 1
Content.Parent = MainFrame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, 0, 0, 40)
ToggleButton.Position = UDim2.new(0, 0, 0, 4)
ToggleButton.BackgroundColor3 = UIColors.CardBg
ToggleButton.BorderSizePixel = 0
ToggleButton.AutoButtonColor = false
ToggleButton.Text = ""
ToggleButton.Parent = Content

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 8)
ToggleCorner.Parent = ToggleButton

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Thickness = 1
ToggleStroke.Color = UIColors.Border
ToggleStroke.Parent = ToggleButton

local ToggleLabel = Instance.new("TextLabel")
ToggleLabel.Size = UDim2.new(0.6, 0, 1, 0)
ToggleLabel.Position = UDim2.new(0, 14, 0, 0)
ToggleLabel.BackgroundTransparency = 1
ToggleLabel.Text = "God Flight [F]"
ToggleLabel.Font = Enum.Font.GothamMedium
ToggleLabel.TextSize = 12
ToggleLabel.TextColor3 = UIColors.TextPrimary
ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
ToggleLabel.Parent = ToggleButton

local SwitchBg = Instance.new("Frame")
SwitchBg.Size = UDim2.new(0, 36, 0, 18)
SwitchBg.Position = UDim2.new(1, -50, 0.5, -9)
SwitchBg.BackgroundColor3 = UIColors.InactiveRed
SwitchBg.BorderSizePixel = 0
SwitchBg.Parent = ToggleButton

local SwitchBgCorner = Instance.new("UICorner")
SwitchBgCorner.CornerRadius = UDim.new(1, 0)
SwitchBgCorner.Parent = SwitchBg

local SwitchDot = Instance.new("Frame")
SwitchDot.Size = UDim2.new(0, 14, 0, 14)
SwitchDot.Position = UDim2.new(0, 2, 0.5, -7)
SwitchDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
SwitchDot.BorderSizePixel = 0
SwitchDot.Parent = SwitchBg

local SwitchDotCorner = Instance.new("UICorner")
SwitchDotCorner.CornerRadius = UDim.new(1, 0)
SwitchDotCorner.Parent = SwitchDot

local SpeedContainer = Instance.new("Frame")
SpeedContainer.Size = UDim2.new(1, 0, 0, 70)
SpeedContainer.Position = UDim2.new(0, 0, 0, 52)
SpeedContainer.BackgroundColor3 = UIColors.CardBg
SpeedContainer.BorderSizePixel = 0
SpeedContainer.Parent = Content

local SpeedCorner = Instance.new("UICorner")
SpeedCorner.CornerRadius = UDim.new(0, 8)
SpeedCorner.Parent = SpeedContainer

local SpeedStroke = Instance.new("UIStroke")
SpeedStroke.Thickness = 1
SpeedStroke.Color = UIColors.Border
SpeedStroke.Parent = SpeedContainer

local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(0.5, 0, 0, 24)
SpeedLabel.Position = UDim2.new(0, 14, 0, 6)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "Aura Velocity"
SpeedLabel.Font = Enum.Font.GothamMedium
SpeedLabel.TextSize = 11
SpeedLabel.TextColor3 = UIColors.TextPrimary
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Parent = SpeedContainer

local SpeedValue = Instance.new("TextLabel")
SpeedValue.Size = UDim2.new(0.4, 0, 0, 24)
SpeedValue.Position = UDim2.new(1, -114, 0, 6)
SpeedValue.BackgroundTransparency = 1
SpeedValue.Text = tostring(Settings.DefaultSpeed) .. " Studs/s"
SpeedValue.Font = Enum.Font.GothamBold
SpeedValue.TextSize = 11
SpeedValue.TextColor3 = UIColors.Accent
SpeedValue.TextXAlignment = Enum.TextXAlignment.Right
SpeedValue.Parent = SpeedContainer

local SliderTrack = Instance.new("TextButton")
SliderTrack.Size = UDim2.new(1, -28, 0, 6)
SliderTrack.Position = UDim2.new(0, 14, 0, 42)
SliderTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
SliderTrack.BorderSizePixel = 0
SliderTrack.Text = ""
SliderTrack.Parent = SpeedContainer

local SliderTrackCorner = Instance.new("UICorner")
SliderTrackCorner.CornerRadius = UDim.new(1, 0)
SliderTrackCorner.Parent = SliderTrack

local SliderFill = Instance.new("Frame")
SliderFill.Size = UDim2.new((Settings.DefaultSpeed - Settings.MinSpeed) / (Settings.MaxSpeed - Settings.MinSpeed), 0, 1, 0)
SliderFill.BackgroundColor3 = UIColors.Accent
SliderFill.BorderSizePixel = 0
SliderFill.Parent = SliderTrack

local SliderFillCorner = Instance.new("UICorner")
SliderFillCorner.CornerRadius = UDim.new(1, 0)
SliderFillCorner.Parent = SliderFill

local SliderHandle = Instance.new("Frame")
SliderHandle.Size = UDim2.new(0, 14, 0, 14)
SliderHandle.Position = UDim2.new((Settings.DefaultSpeed - Settings.MinSpeed) / (Settings.MaxSpeed - Settings.MinSpeed), -7, 0.5, -7)
SliderHandle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
SliderHandle.BorderSizePixel = 0
SliderHandle.Parent = SliderTrack

local SliderHandleCorner = Instance.new("UICorner")
SliderHandleCorner.CornerRadius = UDim.new(1, 0)
SliderHandleCorner.Parent = SliderHandle

local function AdjustSliderPosition(input: InputObject)
    local width = SliderTrack.AbsoluteSize.X
    local offset = math.clamp(input.Position.X - SliderTrack.AbsolutePosition.X, 0, width)
    local rawPercentage = offset / width
    
    local calculatedSpeed = math.floor(Settings.MinSpeed + (rawPercentage * (Settings.MaxSpeed - Settings.MinSpeed)))
    FlightState.CurrentSpeed = calculatedSpeed
    SpeedValue.Text = tostring(calculatedSpeed) .. " Studs/s"
    
    SliderFill.Size = UDim2.new(rawPercentage, 0, 1, 0)
    SliderHandle.Position = UDim2.new(rawPercentage, -7, 0.5, -7)
end

local sliderActive = false
SliderTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliderActive = true
        AdjustSliderPosition(input)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if sliderActive and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        AdjustSliderPosition(input)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliderActive = false
    end
end)

local function ToggleLogic()
    FlightState.IsActive = not FlightState.IsActive
    
    local dotTargetPosition = FlightState.IsActive and UDim2.new(0, 20, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    local bgTargetColor = FlightState.IsActive and UIColors.ActiveGreen or UIColors.InactiveRed
    local strokeTargetColor = FlightState.IsActive and UIColors.ActiveGreen or UIColors.Border
    
    TweenService:Create(SwitchDot, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = dotTargetPosition}):Play()
    TweenService:Create(SwitchBg, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = bgTargetColor}):Play()
    TweenService:Create(ToggleStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Color = strokeTargetColor}):Play()
    
    if FlightState.IsActive then
        StartFlightCore()
    else
        StopFlightCore()
    end
end

ToggleButton.Activated:Connect(ToggleLogic)

InputBeganConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Settings.ToggleKey then ToggleLogic() end
end)

local function OnDeath()
    if FlightState.IsActive then ToggleLogic() end
end

if LocalPlayer.Character then
    local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.Died:Connect(OnDeath) end
end
CharacterAddedConn = LocalPlayer.CharacterAdded:Connect(function(char)
    if FlightState.IsActive then ToggleLogic() end
    local hum = char:WaitForChild("Humanoid", 3)
    if hum then hum.Died:Connect(OnDeath) end
end)

print("[Anime Fly Cinematic God] V10 Loaded. FOV Warping & Sonic Boom Active.")


