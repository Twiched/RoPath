-- Autonomous Pathfinding System v3.4
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--# Enhanced Configuration
local Config = {
    Navigation = {
        Target = Vector3.new(100, 5, -50), -- Set target position
        RefreshRate = 0.15,
        NodeDistance = 6,
        MaxAttempts = 25
    },
    Agent = {
        JumpPower = 52,
        WallClimbHeight = 6.5,
        LedgeGrabRange = 3.2,
        FallTolerance = 9.5
    },
    Sensors = {
        FrontCast = {
            Rays = 7,
            Spread = 2.5,
            HeightOffset = 1.2
        },
        Predictive = {
            Steps = 3,
            LookAhead = 1.5
        }
    },
    Visual = {
        PathEnabled = true,
        BeamColor = Color3.fromHSV(math.random(), 0.8, 0.9),
        BeamWidth = 0.35
    }
}

--# System Core
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

local Path = {
    Waypoints = {},
    ActiveBeams = {},
    CurrentIndex = 1,
    StuckFrames = 0
}

--# Advanced Sensing Module
local function GetEnvironmentData()
    local data = {
        FrontObstacles = {},
        Ground = {
            Distance = math.huge,
            Normal = Vector3.new()
        },
        Predictive = {}
    }

    -- Multi-directional front scanning
    local basePos = root.Position + Vector3.new(0, Config.Sensors.FrontCast.HeightOffset, 0)
    for i = -Config.Sensors.FrontCast.Rays, Config.Sensors.FrontCast.Rays do
        local offset = root.CFrame.RightVector * (i * Config.Sensors.FrontCast.Spread)
        local ray = Ray.new(basePos + offset, root.CFrame.LookVector * 8)
        local hit = workspace:Raycast(ray.Origin, ray.Direction)
        if hit then
            table.insert(data.FrontObstacles, {
                Position = hit.Position,
                Distance = (hit.Position - basePos).Magnitude,
                Normal = hit.Normal
            })
        end
    end

    -- Ground analysis
    local groundRay = Ray.new(root.Position, Vector3.new(0, -12, 0))
    local groundHit = workspace:Raycast(groundRay.Origin, groundRay.Direction)
    if groundHit then
        data.Ground.Distance = (root.Position - groundHit.Position).Magnitude
        data.Ground.Normal = groundHit.Normal
    end

    -- Predictive path checking
    local lookAheadPos = root.Position + (root.CFrame.LookVector * Config.Sensors.Predictive.LookAhead)
    for i = 1, Config.Sensors.Predictive.Steps do
        local checkPos = lookAheadPos + Vector3.new(0, -i*2, 0)
        local hit = workspace:Raycast(checkPos + Vector3.new(0,1,0), Vector3.new(0,-2,0))
        table.insert(data.Predictive, hit and hit.Position or checkPos)
    end

    return data
end

--# Intelligent Movement Controller
local function AdaptiveMove(targetPosition)
    local env = GetEnvironmentData()
    local moveDir = (targetPosition - root.Position) * Vector3.new(1,0,1)
    
    -- Automatic jump conditions
    local shouldJump = false
    
    -- Front obstacle handling
    if #env.FrontObstacles > 0 then
        local closestObstacle = env.FrontObstacles[1]
        for _, obs in pairs(env.FrontObstacles) do
            if obs.Distance < closestObstacle.Distance then
                closestObstacle = obs
            end
        end
        
        if closestObstacle.Distance < 3.5 then
            local obstacleHeight = closestObstacle.Position.Y - root.Position.Y
            if obstacleHeight < Config.Agent.WallClimbHeight then
                shouldJump = true
                moveDir = moveDir + (Vector3.new(0, Config.Agent.JumpPower * 0.6, 0))
            end
        end
    end

    -- Predictive ledge handling
    local pathClear = true
    for _, predPos in pairs(env.Predictive) do
        if (predPos.Y - root.Position.Y) < -Config.Agent.FallTolerance then
            pathClear = false
            break
        end
    end
    
    if not pathClear then
        moveDir = moveDir:Lerp(-moveDir, 0.3)
        shouldJump = true
    end

    -- Execute movement
    if shouldJump then
        humanoid.Jump = true
        root.Velocity = Vector3.new(
            moveDir.X * 1.2,
            Config.Agent.JumpPower,
            moveDir.Z * 1.2
        )
    else
        humanoid:MoveTo(root.Position + moveDir.Unit * 3)
    end
end

--# Path Visualization System
local function UpdatePathDisplay()
    if not Config.Visual.PathEnabled then return end
    
    -- Clear old beams
    for _, beam in pairs(Path.ActiveBeams) do
        beam:Destroy()
    end
    Path.ActiveBeams = {}

    -- Create new path visualization
    local lastPoint = root.Position
    for _, waypoint in pairs(Path.Waypoints) do
        local beam = Instance.new("Part")
        beam.Size = Vector3.new(0.2, 0.2, (lastPoint - waypoint).Magnitude)
        beam.Color = Config.Visual.BeamColor
        beam.Material = Enum.Material.Neon
        beam.Anchored = true
        beam.CanCollide = false
        beam.CFrame = CFrame.lookAt(lastPoint, waypoint) * CFrame.new(0,0,-beam.Size.Z/2)
        beam.Parent = workspace
        
        table.insert(Path.ActiveBeams, beam)
        lastPoint = waypoint
    end
end

--# Path Generation Engine
local function GenerateWaypoints(target)
    local waypoints = {}
    local currentPos = root.Position
    local attempts = 0
    
    while attempts < Config.Navigation.MaxAttempts do
        local dir = (target - currentPos) * Vector3.new(1,0,1)
        if dir.Magnitude < Config.Navigation.NodeDistance then break end
        
        local nextPos = currentPos + dir.Unit * Config.Navigation.NodeDistance
        local hit = workspace:Raycast(currentPos + Vector3.new(0,1,0), 
                                    (nextPos - currentPos) * Vector3.new(1,0,1))
        
        if hit then
            -- Obstacle avoidance
            nextPos = currentPos + (dir:Cross(Vector3.new(0,1,0))).Unit * Config.Navigation.NodeDistance
        end
        
        table.insert(waypoints, nextPos)
        currentPos = nextPos
        attempts += 1
    end
    
    table.insert(waypoints, target)
    return waypoints
end

--# Autonomous Navigation Core
local function NavigateToTarget()
    Path.Waypoints = GenerateWaypoints(Config.Navigation.Target)
    if #Path.Waypoints == 0 then return end
    
    Path.CurrentIndex = 1
    UpdatePathDisplay()

    while Path.CurrentIndex <= #Path.Waypoints do
        local currentTarget = Path.Waypoints[Path.CurrentIndex]
        
        -- Movement execution
        AdaptiveMove(currentTarget)
        
        -- Progress check
        if (root.Position - currentTarget).Magnitude < 3 then
            Path.CurrentIndex += 1
        end

        -- Stuck detection
        if Path.CurrentIndex > 1 then
            local prevTarget = Path.Waypoints[Path.CurrentIndex-1]
            if (root.Position - prevTarget).Magnitude < 1.5 then
                Path.StuckFrames += 1
                if Path.StuckFrames > 8 then
                    -- Path recalculation
                    Path.Waypoints = GenerateWaypoints(Config.Navigation.Target)
                    Path.CurrentIndex = 1
                    Path.StuckFrames = 0
                    UpdatePathDisplay()
                end
            else
                Path.StuckFrames = 0
            end
        end

        task.wait(Config.Navigation.RefreshRate)
    end

    -- Cleanup on arrival
    for _, beam in pairs(Path.ActiveBeams) do
        beam:Destroy()
    end
end

--# Initialization
task.spawn(function()
    while true do
        NavigateToTarget()
        task.wait(1.5) -- Re-path interval
    end
end)
