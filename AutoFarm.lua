-- AutoFarm.lua - Deadly Delivery Auto Farm (Simple + Advanced Core)
if getgenv().AutoFarmStarted then
    return
end
getgenv().AutoFarmStarted = true

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LOCAL_PLAYER = Players.LocalPlayer

-- ================================
-- Auto-restart on teleport
-- ================================
pcall(function()
    if queue_on_teleport and isfile and readfile and isfile("AutoFarm.lua") then
        queue_on_teleport(readfile("AutoFarm.lua"))
    end
end)

-- ================================
-- Simple overlay (no GUI libs)
-- ================================
local Overlay = {}
do
    local screenGui, label
    local function init()
        if screenGui then return end
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "AutoFarmOverlay"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")

        label = Instance.new("TextLabel")
        label.Name = "StatusLabel"
        label.Size = UDim2.new(0, 420, 0, 28)
        label.Position = UDim2.new(0, 12, 0, 12)
        label.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        label.BackgroundTransparency = 0.2
        label.TextColor3 = Color3.fromRGB(220, 220, 220)
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = "AutoFarm: Initializing..."
        label.Parent = screenGui
    end

    function Overlay.set(text)
        pcall(function()
            if not screenGui then init() end
            if label then label.Text = text end
        end)
        print("[AutoFarm] " .. tostring(text))
    end
end

-- ================================
-- Webhook support
-- ================================
local function saveWebhook(url)
    if not url or type(url) ~= "string" or url == "" then return end
    pcall(function()
        if writefile then
            writefile("AutoFarmWH.txt", url)
        end
    end)
end

local function loadWebhook()
    if isfile and isfile("AutoFarmWH.txt") and readfile then
        local ok, content = pcall(readfile, "AutoFarmWH.txt")
        if ok and content and content ~= "" then
            return content
        end
    end
    return nil
end

local WEBHOOK_URL = ""
saveWebhook(getgenv().WebhookURL)
WEBHOOK_URL = loadWebhook() or getgenv().WebhookURL or ""

local function sendWebhook(payload)
    if WEBHOOK_URL == "" then return end
    local body = HttpService:JSONEncode(payload)
    local request = http_request or request or syn and syn.request
    if not request then return end
    pcall(function()
        request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body
        })
    end)
end

-- ================================
-- Constants (from PremiumCore)
-- ================================
local CONSTANTS = {
    MONSTER_IDS = {
        "TheForsaken", "Worms", "FlameTurkey", "InfernoTurkey", "Mimic",
        "Bloomaw", "Sneakrat", "Guest666", "SantaMK2", "FridgeMonster",
        "CrocodileMama", "CrocodilePapa", "TheBurden", "TheFaceless",
        "TheForsakenUnfinished", "SneakRatCave", "SantaMK2House",
        "TheFacelessStar", "VecnaBOSS", "TheFacelessBOSS",
        "The Forsaken", "Pit Worm", "Flame Turkey", "Inferno Turkey",
        "Crocodile Mama", "Crocodile Papa", "The Burden", "The Faceless",
        "Meat Fridge", "Santa MK-II", "Guest 666", "Legged Food",
        "Echo", "Umbra", "Vecna", "Fake Food", "Fridge", "Turkey"
    },
    MONSTER_DATA = {
        [120001] = { name = "Bloomaw",         damage = 39, alertRange = 200 },
        [120002] = { name = "The Forsaken",    damage = 40, alertRange = 60 },
        [120003] = { name = "Pit Worm",        damage = 30, alertRange = 80 },
        [120004] = { name = "Flame Turkey",    damage = 3,  alertRange = 200 },
        [120005] = { name = "Meat Fridge",     damage = 40, alertRange = 80 },
        [120006] = { name = "Inferno Turkey",  damage = 4,  alertRange = 200 },
        [120011] = { name = "Crocodile Mama",  damage = 35, alertRange = 80 },
        [120012] = { name = "Mimic",           damage = 15, alertRange = 80 },
        [120014] = { name = "Guest 666",       damage = 40, alertRange = 80 },
        [120015] = { name = "Sneakrat",        damage = 9,  alertRange = 80 },
        [120016] = { name = "Crocodile Papa",  damage = 35, alertRange = 80 },
        [120017] = { name = "Santa MK-II",     damage = 30, alertRange = 80 },
        [120019] = { name = "Umbra",           damage = 40, alertRange = 80 },
        [120020] = { name = "The Burden",      damage = 0,  alertRange = 80 },
        [120021] = { name = "The Faceless",    damage = 40, alertRange = 80 },
        [120022] = { name = "Vecna",           damage = 0,  alertRange = 120 }
    },
    CONTAINER_IDS = {
        "ItemOnFloor", "Oilbucket", "WoodenBucket", "Crate", "Cabinet",
        "WoodenCabinet", "LabBucket", "LabCrate", "LabCabinet", "Fridge",
        "ItemOnFloorRatCave", "ItemOnFloorUnfinishedMap"
    },
    RATE_LIMIT = {
        MAX_PER_MINUTE = 35,
        MIN_INTERVAL = 0.15,
        JITTER = 0.08
    },
    ELEVATOR_POS = Vector3.new(-310.421204, 323.808197, 406.190948)
}

local LootFolder = Workspace:WaitForChild("GameSystem"):WaitForChild("Loots"):WaitForChild("World")
local ChestFolder = Workspace.GameSystem:WaitForChild("InteractiveItem")
local NPCFolder = Workspace.GameSystem:WaitForChild("NPCModels")

-- ================================
-- Simple feature toggles
-- ================================
local CONFIG = {
    VacuumLoot = true,
    VacuumInterval = 0.5,
    AutoBankLoop = true,
    AutoBankInterval = 2.0
}

-- ================================
-- State Manager
-- ================================
local State = {}
do
    local internal = {}
    local listeners = {}
    local types = {}

    function State.define(schema)
        for key, def in pairs(schema) do
            internal[key] = def.default
            types[key] = def.type
            listeners[key] = {}
        end
    end

    function State.get(key)
        return internal[key]
    end

    function State.set(key, value, silent)
        if types[key] and typeof(value) ~= types[key] then
            warn(string.format("[State] Type mismatch for '%s'", key))
            return false
        end
        local old = internal[key]
        internal[key] = value
        if not silent then
            for _, cb in ipairs(listeners[key] or {}) do
                task.spawn(cb, value, old)
            end
        end
        return true
    end

    function State.subscribe(key, cb)
        table.insert(listeners[key], cb)
        return function()
            local idx = table.find(listeners[key], cb)
            if idx then table.remove(listeners[key], idx) end
        end
    end
end

State.define({
    alive = { default = true, type = "boolean" },
    farmActive = { default = true, type = "boolean" },
    safeMode = { default = true, type = "boolean" },
    currentFloor = { default = 0, type = "number" },
    itemsCollected = { default = 0, type = "number" },
    status = { default = "Starting...", type = "string" }
})

State.subscribe("status", function(text)
    Overlay.set(text)
end)

-- ================================
-- Rate Limiter + Remote Handler
-- ================================
local RateLimiter = {}
do
    local lastFireTimes = {}
    local COOLDOWN = 60 / CONSTANTS.RATE_LIMIT.MAX_PER_MINUTE
    function RateLimiter.canFire(remoteName)
        local now = tick()
        local last = lastFireTimes[remoteName] or 0
        if (now - last) < COOLDOWN or (now - last) < CONSTANTS.RATE_LIMIT.MIN_INTERVAL then
            return false
        end
        return true
    end
    function RateLimiter.recordFire(remoteName)
        lastFireTimes[remoteName] = tick()
    end
end

local function getTEvent()
    local ok, result = pcall(function()
        return require(ReplicatedStorage.Shared.Core.TEvent)
    end)
    if ok and result then return result end
    return nil
end

local function fireRemote(remoteName, ...)
    if not RateLimiter.canFire(remoteName) then
        return false, "Rate limited"
    end
    local event = getTEvent()
    if not event then return false, "TEvent missing" end
    if CONSTANTS.RATE_LIMIT.JITTER > 0 then
        task.wait(math.random() * CONSTANTS.RATE_LIMIT.JITTER)
    end
    local args = { ... }
    local ok, err = pcall(function()
        if typeof(event) == "table" and event.FireRemote then
            event.FireRemote(remoteName, unpack(args))
        elseif typeof(event) == "Instance" then
            event:FireServer(remoteName, unpack(args))
        end
    end)
    if ok then
        RateLimiter.recordFire(remoteName)
        return true
    end
    return false, err
end

-- ================================
-- Entity Detector
-- ================================
local EntityDetector = {}
do
    local monsterSet, containerSet = {}, {}
    local cache = setmetatable({}, { __mode = "k" })
    for _, id in ipairs(CONSTANTS.MONSTER_IDS) do
        monsterSet[id] = true
    end
    for _, id in ipairs(CONSTANTS.CONTAINER_IDS) do
        containerSet[id] = true
    end

    function EntityDetector.isMonster(entity)
        if not entity then return false end
        if cache[entity] then return unpack(cache[entity]) end
        local name = entity.Name
        local function returnCached(isMon, typeName, data)
            if isMon then cache[entity] = { isMon, typeName, data } end
            return isMon, typeName, data
        end
        for id in pairs(monsterSet) do
            if name:find(id) then
                return returnCached(true, id)
            end
        end
        local attrId = entity:GetAttribute("id")
        if attrId and CONSTANTS.MONSTER_DATA[attrId] then
            return returnCached(true, CONSTANTS.MONSTER_DATA[attrId].name, CONSTANTS.MONSTER_DATA[attrId])
        end
        local humanoid = entity:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            return returnCached(true, name, { health = humanoid.Health, maxHealth = humanoid.MaxHealth })
        end
        return false, nil
    end

    function EntityDetector.isContainer(entity)
        if not entity then return false end
        for id in pairs(containerSet) do
            if entity.Name:find(id) then return true end
        end
        return false
    end

    function EntityDetector.isOpened(entity)
        if not entity then return true end
        local openAttr = entity:GetAttribute("Open")
        local itemDropped = entity:GetAttribute("ItemDropped")
        local enabled = entity:GetAttribute("en")
        if openAttr == true or itemDropped == true or enabled == false then
            return true
        end
        return false
    end

    function EntityDetector.getPosition(entity)
        if not entity then return nil end
        if entity:IsA("Model") then
            if entity.PrimaryPart then return entity.PrimaryPart.Position end
            local part = entity:FindFirstChildWhichIsA("BasePart")
            if part then return part.Position end
        elseif entity:IsA("BasePart") then
            return entity.Position
        end
        return nil
    end

    function EntityDetector.getCFrame(entity)
        if not entity then return nil end
        if entity:IsA("Model") then
            if entity.PrimaryPart then return entity.PrimaryPart.CFrame end
            local part = entity:FindFirstChildWhichIsA("BasePart")
            if part then return part.CFrame end
        elseif entity:IsA("BasePart") then
            return entity.CFrame
        end
        return nil
    end
end

-- ================================
-- Movement Engine (anti-stuck)
-- ================================
local Movement = {}
do
    local lastPos = Vector3.new(0, 0, 0)
    local stuckTimer = 0
    function Movement.teleport(targetCFrame, smooth)
        local char = LOCAL_PLAYER.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        if smooth == nil then smooth = true end
        if smooth then
            local distance = (root.Position - targetCFrame.Position).Magnitude
            local duration = math.clamp(distance / 100, 0.1, 1.2)
            local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = targetCFrame })
            tween:Play()
        else
            char:PivotTo(targetCFrame)
        end
        return true
    end
    function Movement.checkStuck()
        local char = LOCAL_PLAYER.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local currentPos = root.Position
        local distance = (currentPos - lastPos).Magnitude
        if distance < 1 then
            stuckTimer = stuckTimer + 0.5
            if stuckTimer >= 5 then
                stuckTimer = 0
                root.CFrame = root.CFrame * CFrame.new(math.random(-10, 10), 0, math.random(-10, 10))
                return true
            end
        else
            stuckTimer = 0
        end
        lastPos = currentPos
        return false
    end
end

-- ================================
-- Inventory Manager (full detection)
-- ================================
local Inventory = {}
do
    function Inventory.getSlotCount()
        local count = 0
        pcall(function()
            local gui = LOCAL_PLAYER.PlayerGui:FindFirstChild("Main")
            local home = gui and gui:FindFirstChild("HomePage")
            if not home then return end
            local handsFull = home:FindFirstChild("HandsFull")
            if handsFull and handsFull.Visible then
                count = 4
                return
            end
            local bottom = home:FindFirstChild("Bottom")
            if bottom then
                for _, slot in pairs(bottom:GetChildren()) do
                    if slot:IsA("Frame") then
                        local details = slot:FindFirstChild("ItemDetails")
                        local itemName = details and details:FindFirstChild("ItemName")
                        if itemName and itemName.Text ~= "" then
                            count = count + 1
                        end
                    end
                end
            end
        end)
        return count
    end
    function Inventory.isFull()
        return Inventory.getSlotCount() >= 4
    end
end

-- ================================
-- Anti-AFK
-- ================================
pcall(function()
    if getconnections then
        for _, v in pairs(getconnections(LOCAL_PLAYER.Idled)) do
            v:Disable()
        end
    else
        LOCAL_PLAYER.Idled:Connect(function()
            pcall(function()
                VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
                task.wait(1)
                VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
            end)
        end)
    end
end)

-- ================================
-- Infinite stamina buff
-- ================================
pcall(function()
    local BuffModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Features"):WaitForChild("Buff")
    local Buff = require(BuffModule)
    Buff.AddBuffs(LOCAL_PLAYER, {
        { name = "RoleStamina", type = "StaminaRegenRate", value = math.huge, tags = { "PersistOnDeath", "Multi" } },
        { name = "RoleStamina", type = "StaminaLimit", value = math.huge, tags = { "PersistOnDeath", "Multi" } }
    })
end)

-- ================================
-- World Check: Lobby Join
-- ================================
local AssetId = require(ReplicatedStorage.Shared.Core.AssetId)
if AssetId.world == "Lobby" then
    Overlay.set("Lobby: Selling items + joining match")
    fireRemote("BackpackSellAll")
    local ValueMod = require(ReplicatedStorage.Shared.Core.Value)
    local lobbyName = ""
    repeat task.wait(0.5)
        for name, lobby in pairs(ValueMod.GetAllValue().MatchInfo) do
            if lobby.matchState == "Idle" then
                fireRemote("JoinMatch", name)
                lobbyName = name
                break
            end
        end
    until lobbyName ~= ""
    repeat task.wait() until ValueMod.GetAllValue().MatchInfo[lobbyName].matchState == "Creating"
    fireRemote("UploadSetting", { size = 1, onlyFriends = true })
    repeat task.wait() until ValueMod.GetAllValue().MatchInfo[lobbyName].matchState == "Reseting"
    return
end

if AssetId.world ~= "Dungeon" then
    Overlay.set("Not in Dungeon. Stopping.")
    return
end

-- ================================
-- Auto-reconnect on teleport failures
-- ================================
pcall(function()
    TeleportService.TeleportInitFailed:Connect(function(_, result)
        warn("[AutoFarm] Teleport failed:", result)
        task.wait(2)
        pcall(function()
            TeleportService:Teleport(game.PlaceId, LOCAL_PLAYER)
        end)
    end)
end)

-- ================================
-- Helper: Target selection
-- ================================
local function isValidLoot(item)
    if not item or not item:GetAttribute("en") then return false end
    if item:IsA("Tool") then
        local folder = item:FindFirstChild("Folder")
        local lootUI = folder and folder:FindFirstChild("Interactable") and folder.Interactable:FindFirstChild("LootUI")
        local frame = lootUI and lootUI:FindFirstChild("Frame")
        local nameLabel = frame and frame:FindFirstChild("ItemName")
        if not nameLabel or nameLabel.Text == "" or nameLabel.Text == "Bloxy Cola" then return false end
        return true
    elseif item:IsA("Model") then
        local interactable = item:FindFirstChild("Interactable")
        local lootUI = interactable and interactable:FindFirstChild("LootUI")
        local frame = lootUI and lootUI:FindFirstChild("Frame")
        local nameLabel = frame and frame:FindFirstChild("ItemName")
        if not nameLabel or nameLabel.Text == "" then return false end
        return true
    end
    return false
end

local function getTargets()
    local targets = {}
    local char = LOCAL_PLAYER.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return targets end

    for _, item in pairs(LootFolder:GetChildren()) do
        if isValidLoot(item) then
            local pos = EntityDetector.getPosition(item)
            if pos then
                table.insert(targets, {
                    object = item,
                    position = pos,
                    distance = (root.Position - pos).Magnitude,
                    priority = 10,
                    type = "Loot"
                })
            end
        end
    end

    for _, container in pairs(ChestFolder:GetChildren()) do
        if container:IsA("Model") and not EntityDetector.isOpened(container) then
            local pos = EntityDetector.getPosition(container)
            if pos then
                table.insert(targets, {
                    object = container,
                    position = pos,
                    distance = (root.Position - pos).Magnitude,
                    priority = 20,
                    type = "Container"
                })
            end
        end
    end

    for _, npc in pairs(NPCFolder:GetChildren()) do
        local pos = EntityDetector.getPosition(npc)
        if pos and npc:FindFirstChild("Interactable") then
            table.insert(targets, {
                object = npc,
                position = pos,
                distance = (root.Position - pos).Magnitude,
                priority = 30,
                type = "NPC"
            })
        end
    end

    table.sort(targets, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.distance < b.distance
    end)
    return targets
end

local function isMonsterNearby()
    local monsters = Workspace.GameSystem:FindFirstChild("Monsters")
    if not monsters then return false end
    local char = LOCAL_PLAYER.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    for _, monster in pairs(monsters:GetChildren()) do
        local isMon, name, data = EntityDetector.isMonster(monster)
        if isMon then
            local pos = EntityDetector.getPosition(monster)
            if pos then
                local radius = (data and data.alertRange) or 60
                if (root.Position - pos).Magnitude <= radius then
                    return true, name or monster.Name
                end
            end
        end
    end
    return false
end

-- ================================
-- Always In Elevator Spoof
-- ================================
task.spawn(function()
    while State.get("farmActive") do
        local char = LOCAL_PLAYER.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local ok, tEvent = pcall(getTEvent)
            if ok and tEvent and tEvent.UnixTimeMillis then
                fireRemote("PlayerInElevator", true, root.CFrame.Position, tEvent.UnixTimeMillis())
            end
        end
        task.wait(0.3)
    end
end)

-- ================================
-- Vacuum Loot (safe, rate-limited)
-- ================================
task.spawn(function()
    while State.get("farmActive") and CONFIG.VacuumLoot do
        task.wait(CONFIG.VacuumInterval)
        pcall(function()
            local char = LOCAL_PLAYER.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then return end

            for _, item in pairs(LootFolder:GetChildren()) do
                if isValidLoot(item) then
                    local pos = EntityDetector.getPosition(item)
                    if pos then
                        local distToElev = (pos - CONSTANTS.ELEVATOR_POS).Magnitude
                        if distToElev > 8 then
                            fireRemote("Interactable", item)
                            task.wait(CONSTANTS.RATE_LIMIT.MIN_INTERVAL)
                        end
                    end
                end
            end
        end)
    end
end)

-- ================================
-- Auto-Bank Loop (deposit anywhere)
-- ================================
task.spawn(function()
    while State.get("farmActive") and CONFIG.AutoBankLoop do
        task.wait(CONFIG.AutoBankInterval)
        pcall(function()
            fireRemote("PlayerEnterCollectPart", true)
        end)
    end
end)

-- ================================
-- Auto-vote logic
-- ================================
task.spawn(function()
    local ValueMod = require(ReplicatedStorage.Shared.Core.Value)
    while State.get("farmActive") do
        task.wait(0.5)
        local stats = ValueMod.GetAllValue().DungeonStats
        if stats and stats.canVote then
            local floor = stats.level or 0
            State.set("currentFloor", floor, true)
            if floor >= 30 then
                Overlay.set("Floor " .. floor .. " | Voting Retreat")
                fireRemote("SubmitVote", "retreat")
                sendWebhook({
                    username = "AutoFarm",
                    content = "Evacuated at floor " .. tostring(floor)
                })
            else
                Overlay.set("Floor " .. floor .. " | Voting Continue")
                fireRemote("SubmitVote", "continue")
            end
        end
    end
end)

-- ================================
-- Main Auto Farm Loop
-- ================================
Overlay.set("Dungeon: Auto farm running")
local lastTargetTime = tick()

while State.get("farmActive") do
    task.wait(0.2)

    local char = LOCAL_PLAYER.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        task.wait(1)
        continue
    end

    -- Safe zone logic (avoid monsters)
    local danger, monsterName = isMonsterNearby()
    if danger then
        Overlay.set("Monster nearby: " .. tostring(monsterName) .. " | Moving to elevator")
        Movement.teleport(CFrame.new(CONSTANTS.ELEVATOR_POS) * CFrame.new(0, 4, 0))
        task.wait(1)
        continue
    end

    -- Full inventory logic
    if Inventory.isFull() then
        Overlay.set("Inventory full | Returning to lobby to sell")
        fireRemote("ReturnToLobby")
        task.wait(2)
        continue
    end

    local targets = getTargets()
    if #targets == 0 then
        if tick() - lastTargetTime > 3 then
            Overlay.set("No items nearby | Returning to elevator")
            Movement.teleport(CFrame.new(CONSTANTS.ELEVATOR_POS) * CFrame.new(0, 4, 0))
        end
        task.wait(0.5)
        continue
    end

    local target = targets[1]
    lastTargetTime = tick()

    local targetCFrame = EntityDetector.getCFrame(target.object)
    if targetCFrame then
        Overlay.set("Interacting: " .. target.type)
        Movement.teleport(CFrame.new(targetCFrame.Position) * CFrame.new(0, 3, 0))
        task.wait(0.1)
        fireRemote("Interactable", target.object)
        State.set("itemsCollected", State.get("itemsCollected") + 1, true)
    end

    Movement.checkStuck()
end
