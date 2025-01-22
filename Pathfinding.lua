-- Enhanced Pathfinding System v6.3
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--# Configuration
local Config = {
    Target = Vector3.new(100, 5, -50),
    Navigation = {
        NodeSpacing = 3.8,
        ReachThreshold = 1.2,
        MaxPathAttempts = 40,
        Jump = {
            Power = 46,
            Cooldown = 0.8,
            MinHeight = 1.8,
            MaxHeight = 5.2,
            ForwardBoost = 12
        }
    },
    Sensors = {
        GroundCheck = 5.5,
        CeilingCheck = 3.2,
        EdgeBuffer = 1.7
    },
    Visual = {
        PathEnabled = true,
        Beam = {
            Color = Color3.new(1, 0, 0),
            Width = 0.18,
            HeightOffset = 0.2
        }
    }
}

--# System Core
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")

local Path = {
    Waypoints = {},
    ActiveBeams = {},
    LastActionTime = 0,
    State = "Idle"
}

--# Precision Visualization
local function ClearPathVisuals()
    for _, beam in pairs(Path.ActiveBeams) do
        beam:Destroy()
    end
    Path.ActiveBeams = {}
end

local function CreateBeamSegment(startPos, endPos)
    local part = Instance.new("Part")
    part.Size = Vector3.new(Config.Visual.Beam.Width, Config.Visual.Beam.Width, 
                           (startPos - endPos).Magnitude)
    part.Color = Config.Visual.Beam.Color
    part.Material = Enum.Material.Neon
    part.Anchored = true
    part.CanCollide = false
    part.CFrame = CFrame.lookAt(startPos + Vector3.new(0,Config.Visual.Beam.HeightOffset,0), 
                              endPos + Vector3.new(0,Config.Visual.Beam.HeightOffset,0)) 
                 * CFrame.new(0,0,-part.Size.Z/2)
    part.Parent = workspace
    table.insert(Path.ActiveBeams, part)
end

--# Smart Environment Analysis
local function GetTerrainData()
    local data = {
        Ground = {
            Position = root.Position,
            Normal = Vector3.new(0,1,0)
        },
        Ceiling = math.huge,
        FrontObstacles = {}
    }

    -- Ground analysis
    local groundHit = workspace:Raycast(root.Position, Vector3.new(0,-Config.Sensors.GroundCheck,0))
    if groundHit then
        data.Ground.Position = groundHit.Position
        data.Ground.Normal = groundHit.Normal
    end

    -- Ceiling check
    local ceilingHit = workspace:Raycast(root.Position + Vector3.new(0,1,0), 
                                       root.CFrame.LookVector * Config.Sensors.CeilingCheck)
    data.Ceiling = ceilingHit and (ceilingHit.Position - root.Position).Magnitude or math.huge

    -- Frontal obstacle mapping
    local rightVec = root.CFrame.RightVector
    for i = -2, 2 do
        local rayOrigin = root.Position + Vector3.new(0,1 + math.abs(i*0.5),0)
        local rayDir = (root.CFrame.LookVector + rightVec * (i*0.15)).Unit * 6
        local hit = workspace:Raycast(rayOrigin, rayDir)
        if hit then
            table.insert(data.FrontObstacles, {
                Position = hit.Position,
                Normal = hit.Normal,
                Distance = (hit.Position - root.Position).Magnitude
            })
        end
    end

    return data
end

--# Intelligent Jump System
local function CalculateJumpRequired(terrainData)
    -- Vertical clearance check
    if terrainData.Ceiling < 3 then return false end

    -- Slope angle calculation
    local slopeAngle = math.deg(math.acos(terrainData.Ground.Normal:Dot(Vector3.new(0,1,0))))
    if slopeAngle > 45 then return true end

    -- Obstacle analysis
    for _, obstacle in pairs(terrainData.FrontObstacles) do
        local verticalDiff = obstacle.Position.Y - terrainData.Ground.Position.Y
        if obstacle.Distance < 3.5 
           and verticalDiff > Config.Navigation.Jump.MinHeight
           and verticalDiff < Config.Navigation.Jump.MaxHeight then
            return true
        end
    end
    return false
end

--# Enhanced Path Generation
local function GenerateSmartPath(target)
    ClearPathVisuals()
    local waypoints = {}
    local currentPos = root.Position
    local attempts = 0

    while attempts < Config.Navigation.MaxPathAttempts do
        local toTarget = (target - currentPos) * Vector3.new(1,0,1)
        if toTarget.Magnitude < Config.Navigation.NodeSpacing then break end

        local nextPos = currentPos + toTarget.Unit * Config.Navigation.NodeSpacing
        local idealHit = workspace:Raycast(currentPos + Vector3.new(0,0.5,0), toTarget)

        if idealHit then
            -- Adaptive path adjustment
            local avoidanceDir = (idealHit.Normal:Cross(Vector3.new(0,1,0))).Unit
            nextPos = currentPos + avoidanceDir * Config.Navigation.NodeSpacing * 1.2
            
            -- Height adjustment
            local verticalRay = workspace:Raycast(nextPos + Vector3.new(0,5,0), Vector3.new(0,-10,0))
            if verticalRay then
                nextPos = verticalRay.Position
            end
        end

        table.insert(waypoints, nextPos)
        currentPos = nextPos
        attempts += 1
    end

    table.insert(waypoints, target)
    return waypoints
end

--# Precision Movement Controller
local function Navigate()
    if Path.State == "Active" then return end
    Path.State = "Active"

    Path.Waypoints = GenerateSmartPath(Config.Target)
    if Config.Visual.PathEnabled then
        for i = 1, #Path.Waypoints-1 do
            CreateBeamSegment(Path.Waypoints[i], Path.Waypoints[i+1])
        end
    end

    local currentIndex = 1
    while currentIndex <= #Path.Waypoints and Path.State == "Active" do
        local targetPos = Path.Waypoints[currentIndex]
        local terrainData = GetTerrainData()

        -- Arrival verification
        if (targetPos - root.Position).Magnitude < Config.Navigation.ReachThreshold then
            currentIndex += 1
            continue
        end

        -- Jump logic
        if CalculateJumpRequired(terrainData) 
           and (os.clock() - Path.LastActionTime) > Config.Navigation.Jump.Cooldown then
            humanoid.Jump = true
            root.Velocity += Vector3.new(
                0,
                Config.Navigation.Jump.Power,
                0
            ) + root.CFrame.LookVector * Config.Navigation.Jump.ForwardBoost
            Path.LastActionTime = os.clock()
            task.wait(0.25)
        end

        -- Precision movement
        local moveDir = (targetPos - root.Position) * Vector3.new(1,0,1)
        humanoid:MoveTo(root.Position + moveDir.Unit * 2)

        -- Progress monitoring
        task.wait(0.1)
        if (targetPos - root.Position).Magnitude < Config.Navigation.ReachThreshold then
            currentIndex += 1
        else
            -- Stuck detection
            local newTerrainData = GetTerrainData()
            if (newTerrainData.Ground.Position - terrainData.Ground.Position).Magnitude < 0.3 then
                currentIndex += 1 -- Skip problematic waypoint
            end
        end
    end

    -- Final position alignment
    if (Config.Target - root.Position).Magnitude > Config.Navigation.ReachThreshold then
        humanoid:MoveTo(Config.Target)
        repeat task.wait(0.1) until (Config.Target - root.Position).Magnitude < 1.5
    end

    ClearPathVisuals()
    Path.State = "Idle"
end

--# Control System
RunService.Heartbeat:Connect(function()
    if Path.State == "Idle" 
       and (Config.Target - root.Position).Magnitude > Config.Navigation.ReachThreshold then
        Navigate()
    end
end)
