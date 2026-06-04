
--[[
    Title: Anime Fly Pro (V3 Ultimate - Bug Fix Edition)
    Author: devansh
    Description: High-fidelity, universal Roblox Luau flight script.
                 Features Look-Direction 3D Vector Flight, dynamic sound/VFX layers,
                 and utilizes universal Roblox core animations to bypass asset blocks.
                 [FIXED] Ground-clipping/dragging physics bug eliminated.
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
    
    -- Using Core Roblox Animations (Guaranteed to load in ANY game, bypasses privacy blocks)
    -- Fall Animation (Perfect for floating/hovering)
    HoverAnimId = "rbxassetid://507767968",
    -- Swim Animation (Automatically tilts body horizontally into a Superman/Fly pose)
    FlyAnimId = "rbxassetid://913384386",
    
    WindSoundId = "rbxassetid://9011181313"
}

local FlightState = {
    IsActive = false,
    CurrentSpeed = Settings.DefaultSpeed,
}

-- Modern Design Tokens / Color Palette
local UIColors = {
    Background = Color3.fromRGB(15, 15, 20),
    Border = Color3.fromRGB(45, 45, 55),
    Accent = Color3.fromRGB(240, 75, 75), -- Bold Anime Crimson Accent
    TextPrimary = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(150, 150, 160),
    CardBg = Color3.fromRGB(25, 25, 30),
    ActiveGreen = Color3.fromRGB(60, 210, 120),
    InactiveRed = Color3.fromRGB(220, 70, 70)
}

-- References to active instances for cleanup
local BodyVelocity: BodyVelocity? = nil
local BodyGyro: BodyGyro? = nil
local RenderConnection: RBXScriptConnection? = nil
local CharacterAddedConn: RBXScriptConnection? = nil
local InputBeganConn: RBXScriptConnection? = nil

-- Animation Tracks
local HoverTrack: AnimationTrack? = nil
local FlyTrack: AnimationTrack? = nil

-- Audio & Visual Assets
local FlightSound: Sound? = nil
local CoreAura: Attachment? = nil
local WindParticles: ParticleEmitter? = nil

-- =============================================================================
-- VFX & SFX MANAGEMENT
-- =============================================================================
local function SetupVFXAndSFX(rootPart: BasePart)
    FlightSound = Instance.new("Sound")
    FlightSound.Name = "AnimeFlightWind"
    FlightSound.SoundId = Settings.WindSoundId
    FlightSound.Volume = 0
    FlightSound.Looped = true
    FlightSound.Pitch = 1.0
    FlightSound.Parent = rootPart
    FlightSound:Play()
    
    CoreAura = Instance.new("Attachment")
    CoreAura.Name = "AnimeFlightAura"
    CoreAura.Position = Vector3.new(0, 0, 0)
    CoreAura.Parent = rootPart
    
    WindParticles = Instance.new("ParticleEmitter")
    WindParticles.Name = "WindStreaks"
    WindParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    WindParticles.LightEmission = 0.8
    WindParticles.LightInfluence = 0
    WindParticles.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, UIColors.Accent),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 0, 0))
    })
    WindParticles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(0.8, 1.2),
        NumberSequenceKeypoint.new(1, 0)
    })
    WindParticles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.2, 0.4),
        NumberSequenceKeypoint.new(0.8, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    })
    WindParticles.Lifetime = NumberRange.new(0.4, 0.8)
    WindParticles.Rate = 0
    WindParticles.Speed = NumberRange.new(15, 30)
    WindParticles.SpreadAngle = Vector2.new(10, 10)
    WindParticles.Orientation = Enum.ParticleOrientation.VelocityAligned
    WindParticles.Parent = CoreAura
end

local function CleanupVFXAndSFX()
    if FlightSound then
        local soundToDestroy = FlightSound
        TweenService:Create(soundToDestroy, TweenInfo.new(0.3), {Volume = 0}):Play()
        task.delay(0.3, function() soundToDestroy:Destroy() end)
        FlightSound = nil
    end
    if CoreAura then
        CoreAura:Destroy()
        CoreAura = nil
    end
    WindParticles = nil
end

-- =============================================================================
-- ANIMATION PIPELINE
-- =============================================================================
local function StopFlightAnimations()
    if HoverTrack then HoverTrack:Stop() end
    if FlyTrack then FlyTrack:Stop() end
end

local function LoadFlightAnimations(humanoid: Humanoid)
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local hoverAnim = Instance.new("Animation")
    hoverAnim.AnimationId = Settings.HoverAnimId
    local flyAnim = Instance.new("Animation")
    flyAnim.AnimationId = Settings.FlyAnimId

    pcall(function()
        HoverTrack = animator:LoadAnimation(hoverAnim)
        if HoverTrack then 
            HoverTrack.Priority = Enum.AnimationPriority.Movement
            HoverTrack.Looped = true
        end
    end)
    
    pcall(function()
        FlyTrack = animator:LoadAnimation(flyAnim)
        if FlyTrack then 
            FlyTrack.Priority = Enum.AnimationPriority.Movement
            FlyTrack.Looped = true
        end
    end)
end

-- =============================================================================
-- UNIVERSAL 3D FLIGHT LOGIC
-- =============================================================================
local function CleanupFlight()
    FlightState.IsActive = false
    
    if RenderConnection then
        RenderConnection:Disconnect()
        RenderConnection = nil
    end
    
    if BodyVelocity then
        BodyVelocity:Destroy()
        BodyVelocity = nil
    end
    
    if BodyGyro then
        BodyGyro:Destroy()
        BodyGyro = nil
    end
    
    local character = LocalPlayer.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            humanoid.PlatformStand = false
        end
    end
    
    StopFlightAnimations()
    CleanupVFXAndSFX()
end

local function StartFlight()
    local character = LocalPlayer.Character
    if not character then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid then return end
    
    CleanupFlight() -- Safety reset
    FlightState.IsActive = true
    
    -- Instant altitude bump to prevent taking off into floor geometry
    rootPart.CFrame = rootPart.CFrame + Vector3.new(0, 4, 0)
    
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoid.PlatformStand = true
    
    LoadFlightAnimations(humanoid)
    if HoverTrack then HoverTrack:Play() end
    
    SetupVFXAndSFX(rootPart)

    -- Setup Physics
    BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.Name = "AnimeVelocityEngine"
    BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    BodyVelocity.Velocity = Vector3.zero
    BodyVelocity.Parent = rootPart
    
    BodyGyro = Instance.new("BodyGyro")
    BodyGyro.Name = "AnimeGyroEngine"
    BodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    BodyGyro.D = 400
    BodyGyro.P = 12000
    BodyGyro.CFrame = rootPart.CFrame
    BodyGyro.Parent = rootPart
    
    local camera = workspace.CurrentCamera
    
    RenderConnection = RunService.RenderStepped:Connect(function()
        if not LocalPlayer.Character or not rootPart or not humanoid or not camera then
            CleanupFlight()
            return
        end
        
        -- Get universal mobile/PC directional input
        local moveDirHorizontal = humanoid.MoveDirection
        local isMoving = moveDirHorizontal.Magnitude > 0
        
        -- 3D Look-Direction Projection (Pitch up to fly up, down to fly down)
        local target3DVector = Vector3.zero
        if isMoving then
            local flatCamCF = CFrame.lookAt(Vector3.zero, camera.CFrame.LookVector * Vector3.new(1, 0, 1))
            local localMoveDir = flatCamCF:VectorToObjectSpace(moveDirHorizontal)
            target3DVector = camera.CFrame:VectorToWorldSpace(localMoveDir)
        end
        
        -- Apply Movement Velocity
        assert(BodyVelocity, "Physics: Velocity engine missing.")
        if isMoving then
            BodyVelocity.Velocity = target3DVector.Unit * FlightState.CurrentSpeed
        else
            BodyVelocity.Velocity = Vector3.zero
        end
        
        -- Apply UPRIGHT Gyro (Crucial Fix: Eliminates ground clipping entirely)
        assert(BodyGyro, "Physics: Gyro engine missing.")
        if isMoving then
            local flatDir = Vector3.new(target3DVector.X, 0, target3DVector.Z)
            if flatDir.Magnitude > 0.01 then
                BodyGyro.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDir.Unit)
            end
        else
            local flatCamDir = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
            if flatCamDir.Magnitude > 0.01 then
                BodyGyro.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatCamDir.Unit)
            end
        end
        
        -- Animation State Controller (Swim anim natively tilts the body horizontally)
        if isMoving then
            if HoverTrack and HoverTrack.IsPlaying then HoverTrack:Stop() end
            if FlyTrack and not FlyTrack.IsPlaying then FlyTrack:Play() end
            if FlyTrack then
                FlyTrack:AdjustSpeed(math.clamp(FlightState.CurrentSpeed / 80, 0.8, 2.5))
            end
        else
            if FlyTrack and FlyTrack.IsPlaying then FlyTrack:Stop() end
            if HoverTrack and not HoverTrack.IsPlaying then HoverTrack:Play() end
        end
        
        -- Dynamic Audio & VFX
        if FlightSound then
            local currentRatio = isMoving and (FlightState.CurrentSpeed / Settings.MaxSpeed) or 0
            FlightSound.Volume = math.clamp(currentRatio * 0.8, 0, 0.8)
            FlightSound.Pitch = math.clamp(0.8 + (currentRatio * 0.7), 0.8, 1.5)
        end
        
        if WindParticles then
            if isMoving then
                WindParticles.Rate = math.floor((FlightState.CurrentSpeed / Settings.MaxSpeed) * 120)
                WindParticles.Speed = NumberRange.new(FlightState.CurrentSpeed * 0.15, FlightState.CurrentSpeed * 0.3)
                CoreAura.CFrame = CFrame.lookAt(Vector3.zero, -target3DVector.Unit)
            else
                WindParticles.Rate = 0
            end
        end
    end)
end

local function ToggleFlight()
    if FlightState.IsActive then
        CleanupFlight()
    else
        StartFlight()
    end
end

-- =============================================================================
-- PREMIUM GLASSMORPHIC DASHBOARD UI
-- =============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AnimeFlyProUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true

local targetUIContainer: Instance? = nil
pcall(function()
    targetUIContainer = CoreGui:FindFirstChild("RobloxGui") or CoreGui
end)
if not targetUIContainer then
    targetUIContainer = LocalPlayer:WaitForChild("PlayerGui")
end

local existingUI = targetUIContainer:FindFirstChild("AnimeFlyProUI")
if existingUI then existingUI:Destroy() end
ScreenGui.Parent = targetUIContainer

-- Main Frame UI Glassmorphic Box
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

-- Drag Logic (Touch and Mouse Compliant)
local dragging = false
local dragInput: InputObject? = nil
local dragStart: Vector3 = Vector3.zero
local startPos: UDim2 = UDim2.new()

MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
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

-- Header Frame Construction
local Header = Instance.new("Frame")
Header.Name = "Header"
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

-- Premium Minimize Button
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

-- Bubble Restore Button
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
local bDragStart = Vector3.zero
local bStartPos = UDim2.new()
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

MinBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    RestoreBubble.Visible = true
end)

RestoreBubble.MouseButton1Click:Connect(function()
    RestoreBubble.Visible = false
    MainFrame.Visible = true
end)

-- Structural Separation Line
local Line = Instance.new("Frame")
Line.Size = UDim2.new(1, -32, 0, 1)
Line.Position = UDim2.new(0, 16, 0, 48)
Line.BackgroundColor3 = UIColors.Border
Line.BorderSizePixel = 0
Line.Parent = MainFrame

-- Interactive Content Frame
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -32, 1, -64)
Content.Position = UDim2.new(0, 16, 0, 54)
Content.BackgroundTransparency = 1
Content.Parent = MainFrame

-- Toggle Control Module (RENAMED TO FLY)
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

-- Toggle Visual Switch
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

-- Velocity Scale Slider Container
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

-- Slider Visual Component Track
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

local SliderHandleStroke = Instance.new("UIStroke")
SliderHandleStroke.Thickness = 1.5
SliderHandleStroke.Color = UIColors.Accent
SliderHandleStroke.Parent = SliderHandle

-- Touch and Mouse Compliant Slider Logic
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

-- UI Interactive Synchronization Loop
local function SetGUIVisualActiveState()
    local dotTargetPosition = FlightState.IsActive and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    local bgTargetColor = FlightState.IsActive and UIColors.ActiveGreen or UIColors.InactiveRed
    
    TweenService:Create(SwitchDot, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = dotTargetPosition
    }):Play()
    
    TweenService:Create(SwitchBg, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundColor3 = bgTargetColor
    }):Play()
    
    local strokeTargetColor = FlightState.IsActive and UIColors.ActiveGreen or UIColors.Border
    TweenService:Create(ToggleStroke, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Color = strokeTargetColor
    }):Play()
end

ToggleButton.MouseButton1Click:Connect(function()
    ToggleFlight()
    SetGUIVisualActiveState()
end)

InputBeganConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Settings.ToggleKey then
        ToggleFlight()
        SetGUIVisualActiveState()
    end
end)

CharacterAddedConn = LocalPlayer.CharacterAdded:Connect(function()
    CleanupFlight()
    SetGUIVisualActiveState()
end)

print("[Anime Fly Fixed] Upright Engine Loaded. Animations Overridden. Clipping impossible.")


