
--[[
    Title: Anime Fly Pro (V8 - Crash-Proof Edition)
    Author: devansh
    Description: Guaranteed stable flight engine. 
                 VFX and Audio wrapped in strict pcalls to prevent all console crashes.
                 Uses Procedural Motor6D animation to force Superman pose (Zero Anim IDs needed).
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
    DefaultSpeed = 120,
    MaxSpeed = 500,
    MinSpeed = 15,
    ToggleKey = Enum.KeyCode.F,
    WindSoundId = "rbxassetid://9011181313"
}

local FlightState = {
    IsActive = false,
    CurrentSpeed = Settings.DefaultSpeed,
}

local UIColors = {
    Background = Color3.fromRGB(15, 15, 20),
    Border = Color3.fromRGB(45, 45, 55),
    Accent = Color3.fromRGB(240, 75, 75), 
    TextPrimary = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(150, 150, 160),
    CardBg = Color3.fromRGB(25, 25, 30),
    ActiveGreen = Color3.fromRGB(60, 210, 120),
    InactiveRed = Color3.fromRGB(220, 70, 70)
}

-- Engine Core References
local BodyVelocity: BodyVelocity? = nil
local BodyGyro: BodyGyro? = nil
local RenderConnection: RBXScriptConnection? = nil
local NoclipConnection: RBXScriptConnection? = nil

-- VFX Storage
local FlightSound: Sound? = nil
local CoreAura: Attachment? = nil
local WindParticles: ParticleEmitter? = nil

-- Procedural Bone Storage
local OriginalC0s = {}

-- =============================================================================
-- PROCEDURAL ANIMATION (Forces Superman Pose without Animation IDs)
-- =============================================================================
local function StoreBones(character: Model)
    OriginalC0s = {}
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("Motor6D") then
            OriginalC0s[desc.Name] = desc.C0
        end
    end
end

local function SetProceduralPose(character: Model, isFlying: boolean)
    local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    if isFlying then
        for _, desc in ipairs(character:GetDescendants()) do
            if not desc:IsA("Motor6D") or not OriginalC0s[desc.Name] then continue end
            
            local targetC0 = OriginalC0s[desc.Name]
            local name = desc.Name
            
            -- Mathematically morph character into a flying posture
            if name == "RootJoint" or name == "Root" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-75), 0, 0)
            elseif name == "Neck" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(65), 0, 0)
            elseif name == "Right Shoulder" or name == "RightShoulder" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(150), 0, math.rad(15))
            elseif name == "Left Shoulder" or name == "LeftShoulder" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(150), 0, math.rad(-15))
            elseif name == "Right Hip" or name == "RightHip" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-15), 0, 0)
            elseif name == "Left Hip" or name == "LeftHip" then
                targetC0 = targetC0 * CFrame.Angles(math.rad(-15), 0, 0)
            end
            
            TweenService:Create(desc, tweenInfo, {C0 = targetC0}):Play()
        end
    else
        -- Restore to standing
        for _, desc in ipairs(character:GetDescendants()) do
            if desc:IsA("Motor6D") and OriginalC0s[desc.Name] then
                TweenService:Create(desc, tweenInfo, {C0 = OriginalC0s[desc.Name]}):Play()
            end
        end
    end
end

-- =============================================================================
-- VFX & SFX MANAGEMENT (100% CRASH-PROOF WRAPPERS)
-- =============================================================================
local function SetupVFX(rootPart: BasePart)
    -- Protect Sound Initialization
    pcall(function()
        FlightSound = Instance.new("Sound")
        FlightSound.Name = "AnimeFlightWind"
        FlightSound.SoundId = Settings.WindSoundId
        FlightSound.Volume = 0
        FlightSound.Looped = true
        FlightSound.Parent = rootPart
        FlightSound:Play()
    end)
    
    -- Protect Particle Initialization (Removed all dangerous Enums)
    pcall(function()
        CoreAura = Instance.new("Attachment")
        CoreAura.Name = "AnimeFlightAura"
        CoreAura.Position = Vector3.new(0, 0, 0)
        CoreAura.Parent = rootPart
        
        WindParticles = Instance.new("ParticleEmitter")
        WindParticles.Name = "WindStreaks"
        WindParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        WindParticles.LightEmission = 0.8
        WindParticles.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.5, UIColors.Accent),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 0, 0))
        })
        WindParticles.Size = NumberSequence.new(0.5)
        WindParticles.Transparency = NumberSequence.new(0.5)
        WindParticles.Lifetime = NumberRange.new(0.4, 0.8)
        WindParticles.Rate = 0
        WindParticles.Speed = NumberRange.new(15, 30)
        WindParticles.Parent = CoreAura
    end)
end

local function CleanupVFX()
    if FlightSound then
        local soundToDestroy = FlightSound
        TweenService:Create(soundToDestroy, TweenInfo.new(0.3), {Volume = 0}):Play()
        task.delay(0.3, function() soundToDestroy:Destroy() end)
        FlightSound = nil
    end
    if CoreAura then CoreAura:Destroy(); CoreAura = nil end
    WindParticles = nil
end

-- =============================================================================
-- FLIGHT PHYSICS ENGINE
-- =============================================================================
local function StopFlightCore()
    if RenderConnection then RenderConnection:Disconnect(); RenderConnection = nil end
    if NoclipConnection then NoclipConnection:Disconnect(); NoclipConnection = nil end
    if BodyVelocity then BodyVelocity:Destroy(); BodyVelocity = nil end
    if BodyGyro then BodyGyro:Destroy(); BodyGyro = nil end
    
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
        SetProceduralPose(character, false)
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
    
    -- Lift character 5 studs to guarantee no ground collision on start
    rootPart.CFrame = rootPart.CFrame + Vector3.new(0, 5, 0)
    
    -- Keep state in Freefall so mobile joystick doesn't break
    humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    
    -- Force Superman visual pose
    SetProceduralPose(character, true)
    
    SetupVFX(rootPart)

    -- Movement Engine
    BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.Name = "AnimeVelocity"
    BodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9) -- Safe infinity to prevent NaN crashes
    BodyVelocity.Velocity = Vector3.zero
    BodyVelocity.Parent = rootPart
    
    -- Hitbox Upright Engine (Prevents clipping the ground)
    BodyGyro = Instance.new("BodyGyro")
    BodyGyro.Name = "AnimeGyro"
    BodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    BodyGyro.D = 400
    BodyGyro.P = 15000 
    BodyGyro.CFrame = rootPart.CFrame
    BodyGyro.Parent = rootPart
    
    local camera = workspace.CurrentCamera
    
    -- Constant Noclip Injection
    NoclipConnection = RunService.Stepped:Connect(function()
        if not LocalPlayer.Character then return end
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end)
    
    -- Physics Vector Loop
    RenderConnection = RunService.RenderStepped:Connect(function()
        if not LocalPlayer.Character or not rootPart or not humanoid or not camera then
            StopFlightCore()
            return
        end
        
        local moveDir = humanoid.MoveDirection
        local isMoving = moveDir.Magnitude > 0
        
        local targetDir = Vector3.zero
        if isMoving then
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
            BodyVelocity.Velocity = isMoving and (targetDir * FlightState.CurrentSpeed) or Vector3.zero
        end
        
        -- Gyro steering (Only rotates left/right. Pitch stays 0)
        if BodyGyro then
            local steerVector = isMoving and targetDir or camera.CFrame.LookVector
            local flatSteer = Vector3.new(steerVector.X, 0, steerVector.Z)
            if flatSteer.Magnitude > 0.001 then
                BodyGyro.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatSteer.Unit)
            end
        end
        
        -- Safe Particle Updating
        if FlightSound then
            local ratio = isMoving and (FlightState.CurrentSpeed / Settings.MaxSpeed) or 0
            FlightSound.Volume = math.clamp(ratio * 0.8, 0, 0.8)
            FlightSound.Pitch = math.clamp(0.8 + (ratio * 0.7), 0.8, 1.5)
        end
        
        if WindParticles and CoreAura then
            if isMoving then
                WindParticles.Rate = math.floor((FlightState.CurrentSpeed / Settings.MaxSpeed) * 120)
                WindParticles.Speed = NumberRange.new(FlightState.CurrentSpeed * 0.15, FlightState.CurrentSpeed * 0.3)
                -- Avoids complex Enums
                CoreAura.CFrame = CFrame.lookAt(Vector3.zero, -targetDir)
            else
                WindParticles.Rate = 0
            end
        end
    end)
end

-- =============================================================================
-- PREMIUM DASHBOARD UI (MOBILE FRIENDLY)
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

local MinBtnStroke = Instance.new("UIStroke")
MinBtnStroke.Thickness = 1
MinBtnStroke.Color = UIColors.Border
MinBtnStroke.Parent = MinBtn

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
ToggleLabel.Text = "Fly [F]"
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
SpeedLabel.Text = "Engine Velocity"
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

print("[Anime Fly V8 Crash-Proof] Activated. Console crashes eliminated. Procedural Superman Pose engaged.")


