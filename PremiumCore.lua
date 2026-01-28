--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║               PREMIUM CORE — Deadly Delivery                  ║
    ║                                                               ║
    ║  Enterprise-grade Lua script with WindUI                      ║
    ║  Version: 1.0.0                                               ║
    ║  Author: xxdayssheus                                          ║
    ║                                                               ║
    ║  Architecture: Modular, Event-Driven, State-Managed           ║
    ╚═══════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 1: SERVICES LAYER
-- Frozen, cached service references for performance
-- ═══════════════════════════════════════════════════════════════════

local cloneref = cloneref or clonereference or function(i) return i end

local Services = setmetatable({}, {
    __index = function(self, name)
        local success, service = pcall(function()
            return cloneref(game:GetService(name))
        end)
        if success and service then
            rawset(self, name, service)
            return service
        end
        return nil
    end,
    __newindex = function()
        error("[PremiumCore] Services table is read-only", 2)
    end,
    __metatable = "locked"
})

-- Pre-cache critical services
local Players = Services.Players
local RunService = Services.RunService
local TweenService = Services.TweenService
local HttpService = Services.HttpService
local UserInputService = Services.UserInputService
local CollectionService = Services.CollectionService
local ReplicatedStorage = Services.ReplicatedStorage

-- Game Modules (loaded synchronously to avoid race condition)
local ValueModule = nil
local ItemLoot = nil
local modulesLoaded = false

local function ensureModulesLoaded()
    if modulesLoaded then return end
    -- FIX: Set modulesLoaded only on successful load (prevents false-positive)
    local s1, v1 = pcall(function() return require(ReplicatedStorage.Shared.Core.Value) end)
    local s2, v2 = pcall(function() return require(ReplicatedStorage.Shared.Data.item_loot) end)
    if s1 then ValueModule = v1 end
    if s2 then ItemLoot = v2 end
    modulesLoaded = s1 and s2
end

-- Defer loading to first use (lazy but safe)
task.defer(ensureModulesLoaded)

-- Helper: Format Number
local function FormatNumber(n)
    if not n then return "0" end
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fk", n / 1e3) end
    return tostring(n)
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 2: CONSTANTS
-- Immutable configuration values
-- ═══════════════════════════════════════════════════════════════════

local CONSTANTS = table.freeze({
    VERSION = "1.0.0",
    SESSION_ID = (function()
        -- FIX: Add randomseed for unpredictable session IDs (Security Hardening)
        math.randomseed(os.clock() * 1000000 + tick() % 1000)
        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        local len = #chars
        local id = {}
        for i = 1, 16 do
            local rand = math.random(1, len)
            id[i] = chars:sub(rand, rand)
        end
        return table.concat(id)
    end)(),
    
    -- Entity Classification IDs (both spaced and non-spaced for compatibility)
    MONSTER_IDS = table.freeze({
        -- Non-spaced (original)
        "TheForsaken", "Worms", "FlameTurkey", "InfernoTurkey", "Mimic",
        "Bloomaw", "Sneakrat", "Guest666", "SantaMK2", "FridgeMonster",
        "CrocodileMama", "CrocodilePapa", "TheBurden", "TheFaceless",
        "TheForsakenUnfinished", "SneakRatCave", "SantaMK2House",
        "TheFacelessStar", "VecnaBOSS", "TheFacelessBOSS",
        -- Spaced (from game config)
        "The Forsaken", "Pit Worm", "Flame Turkey", "Inferno Turkey",
        "Crocodile Mama", "Crocodile Papa", "The Burden", "The Faceless",
        "Meat Fridge", "Santa MK-II", "Guest 666", "Legged Food",
        -- Additional types
        "Echo", "Umbra", "Vecna", "Fake Food", "Fridge", "Turkey"
    }),
    
    -- Monster Detection Data (id, health, damage, speed, alertRange, fieldOfView)
    -- Data from game config for Kill Aura damage calc and Safe Zone Logic
    MONSTER_DATA = table.freeze({
        [120001] = { name = "Bloomaw",         health = 300,  damage = 39, speed = 10,   alertRange = 200, fieldOfView = 100 },
        [120002] = { name = "The Forsaken",    health = 300,  damage = 40, speed = 0,    alertRange = 60,  fieldOfView = 80 },
        [120003] = { name = "Pit Worm",        health = 100,  damage = 30, speed = 0,    alertRange = nil, fieldOfView = nil },
        [120004] = { name = "Flame Turkey",    health = 120,  damage = 3,  speed = 7,    alertRange = 200, fieldOfView = 100 },
        [120005] = { name = "Meat Fridge",     health = 200,  damage = 40, speed = 0,    alertRange = nil, fieldOfView = nil },
        [120006] = { name = "Inferno Turkey",  health = 150,  damage = 4,  speed = 9,    alertRange = 200, fieldOfView = 100 },
        [120011] = { name = "Crocodile Mama",  health = 250,  damage = 35, speed = 18.5, alertRange = nil, fieldOfView = 30 },
        [120012] = { name = "Mimic",           health = 100,  damage = 15, speed = 12,   alertRange = nil, fieldOfView = 100 },
        [120013] = { name = "Legged Food",     health = 100,  damage = 0,  speed = 12,   alertRange = nil, fieldOfView = nil },
        [120014] = { name = "Guest 666",       health = 525,  damage = 40, speed = 10,   alertRange = nil, fieldOfView = nil }, -- Blind
        [120015] = { name = "Sneakrat",        health = 75,   damage = 9,  speed = 12,   alertRange = nil, fieldOfView = nil },
        [120016] = { name = "Crocodile Papa",  health = 325,  damage = 35, speed = 20,   alertRange = nil, fieldOfView = nil },
        [120017] = { name = "Santa MK-II",     health = 200,  damage = 30, speed = 12,   alertRange = nil, fieldOfView = nil },
        [120018] = { name = "The Forsaken",    health = 300,  damage = 39, speed = 0,    alertRange = 60,  fieldOfView = 80 }, -- Variant
        [120019] = { name = "Umbra",           health = 0,    damage = 40, speed = 0,    alertRange = nil, fieldOfView = nil }, -- Invincible
        [120020] = { name = "The Burden",      health = 50,   damage = 0,  speed = 0,    alertRange = nil, fieldOfView = nil },
        [120021] = { name = "The Faceless",    health = 450,  damage = 40, speed = 8,    alertRange = nil, fieldOfView = nil }, -- Uses sound
        [120022] = { name = "Vecna",           health = 2500, damage = 0,  speed = 18,   alertRange = nil, fieldOfView = nil }, -- BOSS
    }),
    
    CONTAINER_IDS = table.freeze({
        "ItemOnFloor", "Oilbucket", "WoodenBucket", "Crate", "Cabinet",
        "WoodenCabinet", "LabBucket", "LabCrate", "LabCabinet", "Fridge",
        "ItemOnFloorRatCave", "ItemOnFloorUnfinishedMap"
    }),
    
    -- Rate limiting defaults (with Gaussian jitter support)
    RATE_LIMIT = table.freeze({
        MAX_PER_MINUTE = 35,
        JITTER_MEAN = 0.08,      -- 80ms mean delay
        JITTER_STDDEV = 0.05,    -- 50ms standard deviation
        JITTER_MIN = 0.02,       -- 20ms minimum
        JITTER_MAX = 0.20        -- 200ms maximum
    }),
    
    -- Elevator safe zone position
    ELEVATOR_POS = Vector3.new(-310.421, 323.808, 406.191),
    
    -- Timing
    LOOP_INTERVALS = table.freeze({
        FAST = 0.1,
        NORMAL = 0.5,
        SLOW = 1.0,
        VERY_SLOW = 2.0
    }),
    
    -- Thresholds (formerly magic numbers)
    THRESHOLDS = table.freeze({
        STUCK_DISTANCE = 1,           -- Minimum movement to not be "stuck" (studs)
        STUCK_TIMEOUT = 5,            -- Seconds before anti-stuck triggers
        ELEVATOR_EXCLUSION = 5,       -- Studs from elevator to ignore loot
        VACUUM_SAFE_RADIUS = 8,       -- Studs from elevator for vacuum safety
        VOTE_IDLE_THRESHOLD = 5,      -- Seconds idle before auto-voting
        VOTE_COOLDOWN = 30,           -- Seconds between votes
        BANKING_WAIT = 1.5,           -- Seconds to wait for banking
        MONSTER_SAFE_RETREAT = 50,    -- Studs range for safe mode retreat
        KILL_AURA_RANGE = 15          -- Studs range for kill aura
    })
})

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 3: STATE MANAGEMENT
-- Reactive state with subscription pattern
-- ═══════════════════════════════════════════════════════════════════

local StateManager = {}
do
    local internal = {}
    local listeners = {}
    local typeValidators = {}
    
    function StateManager.define(schema)
        for key, definition in pairs(schema) do
            internal[key] = definition.default
            typeValidators[key] = definition.type
            listeners[key] = {}
        end
    end
    
    function StateManager.get(key)
        return internal[key]
    end
    
    function StateManager.set(key, value, silent)
        -- Type validation
        if typeValidators[key] and typeof(value) ~= typeValidators[key] then
            warn(string.format("[State] Type mismatch for '%s': expected %s, got %s", 
                key, typeValidators[key], typeof(value)))
            return false
        end
        
        local oldValue = internal[key]
        internal[key] = value
        
        if not silent and listeners[key] then
            for _, callback in ipairs(listeners[key]) do
                task.spawn(callback, value, oldValue)
            end
        end
        
        return true
    end
    
    function StateManager.subscribe(key, callback)
        if not listeners[key] then
            listeners[key] = {}
        end
        table.insert(listeners[key], callback)
        
        -- Return unsubscribe function
        return function()
            local idx = table.find(listeners[key], callback)
            if idx then
                table.remove(listeners[key], idx)
            end
        end
    end
    
    function StateManager.getAll()
        return table.clone(internal)
    end
end

-- Define application state schema
StateManager.define({
    -- Lifecycle
    alive = { default = true, type = "boolean" },
    
    -- Farm
    farmActive = { default = false, type = "boolean" },
    farmSpeed = { default = 1.0, type = "number" },
    lootRadius = { default = 50, type = "number" },
    safeMode = { default = false, type = "boolean" },
    priorityLoot = { default = false, type = "boolean" }, -- Default FALSE -> Focus Distance Pathing
    antiStuck = { default = true, type = "boolean" },
    antiAFK = { default = false, type = "boolean" },
    smartPathing = { default = false, type = "boolean" },
    safeZoneLogic = { default = true, type = "boolean" },
    noLimitRadius = { default = false, type = "boolean" },
    -- FIX: Changed default from true to false to match UI toggle Default
    -- This prevents state desync where internal state = true but UI shows false
    farmNPCs = { default = false, type = "boolean" },
    elevatorSafety = { default = false, type = "boolean" },
    
    -- Movement
    useTween = { default = true, type = "boolean" },
    walkSpeed = { default = 16, type = "number" },
    speedHack = { default = false, type = "boolean" },
    
    -- ESP
    espMonsters = { default = false, type = "boolean" },
    espLoot = { default = false, type = "boolean" },
    espContainers = { default = false, type = "boolean" },
    espNPCs = { default = false, type = "boolean" },
    espPlayers = { default = false, type = "boolean" },
    espGhosts = { default = false, type = "boolean" },
    espNoLimit = { default = false, type = "boolean" },
    espHideOpened = { default = false, type = "boolean" },
    espHideElevator = { default = false, type = "boolean" },
    highlightElevator = { default = false, type = "boolean" },
    
    -- Monster Tracker
    monsterTracker = { default = false, type = "boolean" },
    trackerDistance = { default = 50, type = "number" },
    
    -- Combat
    killAura = { default = false, type = "boolean" },
    infiniteStamina = { default = false, type = "boolean" },
    
    -- Dungeon
    autoElevator = { default = false, type = "boolean" },
    godModeElevator = { default = false, type = "boolean" },
    maxFloorTarget = { default = 30, type = "number" },
    alwaysInElevator = { default = false, type = "boolean" },
    smartElevatorSpoof = { default = false, type = "boolean" }, -- Auto-pauses near elevator
    elevatorPauseDistance = { default = 15, type = "number" },   -- Distance to pause spoof
    instantEvacAuto = { default = false, type = "boolean" },
    autoJuicer = { default = false, type = "boolean" },
    safeEvacuate = { default = false, type = "boolean" },
    safeEvacTime = { default = 5, type = "number" },
    showCountdown = { default = false, type = "boolean" },
    showInternalHUD = { default = false, type = "boolean" },
    autoToolSpam = { default = false, type = "boolean" },
    remoteDropMode = { default = false, type = "boolean" },
    interactDistance = { default = 25, type = "number" },
    vacuumLoot = { default = false, type = "boolean" },
    autoOpenChests = { default = false, type = "boolean" },
    autoOpenGiftBox = { default = false, type = "boolean" },
    
    -- Auto Dungeon
    autoDungeon = { default = false, type = "boolean" },     -- Master Switch
    autoGoDeep = { default = false, type = "boolean" },      -- Auto Vote Continue
    autoEvacuate = { default = false, type = "boolean" },    -- Auto Vote Retreat
    autoEvacuateFloor = { default = 30, type = "number" },   -- Floor to Evacuate
    autoDungeonIdleTime = { default = 0, type = "number" },  -- Internal tracking
    lastVoteTime = { default = 0, type = "number" },         -- Internal tracking
    autoDungeonHasVoted = { default = false, type = "boolean" }, -- KILO Fix: Prevent vote spam
    
    -- Visuals
    fullbright = { default = false, type = "boolean" },
    
    -- Stats (read-only tracking)
    itemsCollected = { default = 0, type = "number" },
    currentFloor = { default = 0, type = "number" },
    startTime = { default = os.clock(), type = "number" },
    
    -- Notifications
    notifications = { default = true, type = "boolean" },
    
    -- Keybind
    toggleKey = { default = Enum.KeyCode.RightShift, type = "EnumItem" }
})

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 4: PLAYER REFERENCES
-- Dynamic player/character references with auto-refresh
-- ═══════════════════════════════════════════════════════════════════

local PlayerRefs = {}
do
    local refs = {
        player = nil,
        character = nil,
        humanoid = nil,
        rootPart = nil
    }
    
    local function refresh()
        refs.player = Players.LocalPlayer
        refs.character = refs.player and refs.player.Character
        refs.humanoid = refs.character and refs.character:FindFirstChildOfClass("Humanoid")
        refs.rootPart = refs.character and refs.character:FindFirstChild("HumanoidRootPart")
    end
    
    refresh()
    
    if refs.player then
        refs.player.CharacterAdded:Connect(function(char)
            refs.character = char
            refs.humanoid = char:WaitForChild("Humanoid", 5)
            refs.rootPart = char:WaitForChild("HumanoidRootPart", 5)
        end)
    end
    
    setmetatable(PlayerRefs, {
        __index = function(_, key)
            if not refs[key] or (key ~= "player" and refs.player and refs.character ~= refs.player.Character) then
                refresh()
            end
            return refs[key]
        end,
        __newindex = function()
            error("[PlayerRefs] Read-only table", 2)
        end
    })
    
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 5: RATE LIMITER
-- Token bucket algorithm with jitter for anti-detection
-- ═══════════════════════════════════════════════════════════════════

local RateLimiter = {}
do
    local lastFireTimes = {}
    -- Calculate strict cooldown to stay safely within limits
    -- 60s / 35 = ~1.71s per request to avoid "rolling window" detection
    local COOLDOWN = 60 / CONSTANTS.RATE_LIMIT.MAX_PER_MINUTE 

    function RateLimiter.canFire(remoteName)
        local now = os.clock()
        local last = lastFireTimes[remoteName] or 0
        
        -- Enforce strict spacing to prevent server-side flags
        if (now - last) < COOLDOWN then
            return false
        end
        return true
    end
    
    function RateLimiter.recordFire(remoteName)
        lastFireTimes[remoteName] = os.clock()
    end
    
    function RateLimiter.getStats()
        local stats = {}
        for name, time in pairs(lastFireTimes) do
            stats[name] = { lastFire = time }
        end
        return stats
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 5.5: UNIFIED HOOK MANAGER (KILO-ZERO Fix #2)
-- Prevents hook conflicts by centralizing all __namecall hooks
-- ═══════════════════════════════════════════════════════════════════

local HookManager = {}
do
    local hooks = {}  -- { name -> { condition = fn, handler = fn } }
    local originalNamecall = nil
    local installed = false
    
    -- Register a hook handler
    function HookManager.register(name, conditionFn, handlerFn)
        hooks[name] = { condition = conditionFn, handler = handlerFn }
        
        -- Auto-install on first registration
        if not installed then
            HookManager.install()
        end
    end
    
    -- Unregister a hook handler
    function HookManager.unregister(name)
        hooks[name] = nil
    end
    
    -- Install the unified hook
    function HookManager.install()
        if installed then return true end
        
        local success = pcall(function()
            if hookmetamethod and type(hookmetamethod) == "function" then
                originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                    local method = getnamecallmethod()
                    local args = {...}
                    
                    -- Dispatch to all registered hooks
                    for name, hook in pairs(hooks) do
                        if hook.condition(method, self, args) then
                            local result = hook.handler(self, method, args)
                            if result ~= nil then
                                return result
                            end
                        end
                    end
                    
                    return originalNamecall(self, ...)
                end)
            else
                -- Legacy fallback
                local mt = getrawmetatable(game)
                originalNamecall = mt.__namecall
                setreadonly(mt, false)
                
                mt.__namecall = newcclosure(function(self, ...)
                    local method = getnamecallmethod()
                    local args = {...}
                    
                    for name, hook in pairs(hooks) do
                        if hook.condition(method, self, args) then
                            local result = hook.handler(self, method, args)
                            if result ~= nil then
                                return result
                            end
                        end
                    end
                    
                    return originalNamecall(self, ...)
                end)
                setreadonly(mt, true)
            end
        end)
        
        installed = success
        return success
    end
    
    function HookManager.isInstalled()
        return installed
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 6: REMOTE HANDLER
-- Centralized, rate-limited remote firing
-- ═══════════════════════════════════════════════════════════════════

local RemoteHandler = {}
do
    local TEvent = nil
    
    -- Lazy-load TEvent
    local function getTEvent()
        if TEvent then return TEvent end
        
        local success, result = pcall(function()
            return require(ReplicatedStorage.Shared.Core.TEvent)
        end)
        
        if success and result then
            TEvent = result
            return TEvent
        end
        
        -- Fallback: Find TEvent in GameSystem
        local gs = workspace:FindFirstChild("GameSystem")
        if gs then
            TEvent = gs:FindFirstChild("TEvent")
        end
        
        return TEvent
    end
    
    function RemoteHandler.fire(remoteName, ...)
        if not RateLimiter.canFire(remoteName) then
            return false, "Rate limited"
        end
        
        local event = getTEvent()
        if not event then
            return false, "TEvent not found"
        end
        
        -- Add jitter for anti-detection (Gaussian distribution for human-like timing)
        local function gaussianJitter()
            -- Box-Muller transform for Gaussian distribution
            local u1, u2 = math.random(), math.random()
            local gaussian = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
            local jitter = gaussian * CONSTANTS.RATE_LIMIT.JITTER_STDDEV + CONSTANTS.RATE_LIMIT.JITTER_MEAN
            return math.clamp(jitter, CONSTANTS.RATE_LIMIT.JITTER_MIN, CONSTANTS.RATE_LIMIT.JITTER_MAX)
        end
        
        task.wait(gaussianJitter())
        
        local args = {...}
        local success, err = pcall(function()
            if typeof(event) == "table" and event.FireRemote then
                if #args > 0 then
                    event.FireRemote(remoteName, unpack(args))
                else
                    event.FireRemote(remoteName)
                end
            elseif typeof(event) == "Instance" then
                if #args > 0 then
                    event:FireServer(remoteName, unpack(args))
                else
                    event:FireServer(remoteName)
                end
            end
        end)
        
        if success then
            RateLimiter.recordFire(remoteName)
            return true
        end
        
        return false, err
    end
    
    function RemoteHandler.fireFast(remoteName, ...)
        -- SAFETY OVERRIDE: If Safe Mode is enabled, force all remotes (even "Fast" ones)
        -- through the strict RateLimiter to prevent bans.
        if StateManager.get("safeMode") then
            return RemoteHandler.fire(remoteName, ...)
        end

        local event = getTEvent()
        if not event then return false end
        
        local args = {...}
        local success, err = pcall(function()
            if typeof(event) == "table" and event.FireRemote then
                event.FireRemote(remoteName, unpack(args))
            elseif typeof(event) == "Instance" then
                event:FireServer(remoteName, unpack(args))
            end
        end)
        return success
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 7: ENTITY DETECTOR
-- Entity classification and detection system
-- ═══════════════════════════════════════════════════════════════════

local EntityDetector = {}
do
    local monsterSet = {}
    local containerSet = {}
    
    -- Cache results to avoid expensive string matching every frame
    -- Weak keys ensure garbage collection when instances are destroyed
    local cache = setmetatable({}, {__mode = "k"})
    
    -- Build lookup sets for O(1) detection
    for _, id in ipairs(CONSTANTS.MONSTER_IDS) do
        monsterSet[id] = true
    end
    for _, id in ipairs(CONSTANTS.CONTAINER_IDS) do
        containerSet[id] = true
    end
    
    -- Structural fingerprints for obfuscated entities (from bdf2fa3b941518e3.lua)
    local FINGERPRINTS = {
        -- Primary monsters
        CrocodileMama = {"Bubble", "Mouth"},
        TheBurden = {"VFX", "Eye"},
        FridgeMonster = {"AttackVFX", "1C1"},
        SneakRatCave = {"AttachmentPoint", "WB1", "Torso"},
        TheForsaken = {"Waist1", "Waist2", "Neck"},
        Bloomaw = {"Tail", "WB2", "Torso"},
        Mimic = {"Pants", "Shirt", "CollisionPart"},
        TheFaceless = {"Feets", "Model"},
        SantaMK2 = {"bag", "Asset"},
        
        -- Turkey variants (InfernoTurkey has Hat)
        FlameTurkey = {"Body", "Head", "Trail"},
        InfernoTurkey = {"Body", "Head", "Trail", "Hat"},
        
        -- Special Guest
        Guest666 = {"Body", "Head", "Tail", "Humanoid"},
        
        -- Other monsters
        Worms = {"Y0"}, -- Can also check Y1, RN
        LeggedFood = {"LeLower_Leg", "Torso"},
        HumanoidMonster = {"LowerTorso", "UpperTorso"},
    }
    
    function EntityDetector.isMonster(entity)
        if not entity then return false end
        
        -- 1. Check Cache First
        if cache[entity] then
            return unpack(cache[entity])
        end
        
        local name = entity.Name
        
        -- Helper to save to cache and return
        local function returnCached(isMon, type, data)
            -- IMPORTANT: Only cache POSITIVE results.
            -- Caching negative results (false) breaks detection for entities that are still loading (streaming in).
            if isMon then
                cache[entity] = {isMon, type, data}
            end
            return isMon, type, data
        end
        
        -- 2. Direct name match - OPTIMIZED: O(1) exact match first, then O(n) pattern match
        -- Step A: Exact match (fastest, O(1))
        if monsterSet[name] then
            return returnCached(true, name)
        end
        
        -- Step B: Pattern match only if exact match fails (slower, O(n))
        for id in pairs(monsterSet) do
            if name:find(id, 1, true) then  -- plain match, no regex overhead
                return returnCached(true, id)
            end
        end
        
        -- 3. Attribute-based ID check (monster:GetAttribute("id"))
        local attrId = entity:GetAttribute("id")
        if attrId and CONSTANTS.MONSTER_DATA[attrId] then
            return returnCached(true, CONSTANTS.MONSTER_DATA[attrId].name)
        end
        
        -- 4. Direct ID as name (like "120019" for Umbra)
        local idAsNumber = tonumber(name)
        if idAsNumber and CONSTANTS.MONSTER_DATA[idAsNumber] then
            return returnCached(true, CONSTANTS.MONSTER_DATA[idAsNumber].name)
        end
        
        -- 5. Fingerprint detection for obfuscated hex names
        if name:match("^%x+$") and #name >= 8 then
            for monsterType, parts in pairs(FINGERPRINTS) do
                local allFound = true
                for _, partName in ipairs(parts) do
                    if not entity:FindFirstChild(partName) then
                        allFound = false
                        break
                    end
                end
                if allFound then
                    return returnCached(true, monsterType)
                end
            end
        end
        
        -- 6. Structural fallback (Humanoid with health = likely monster)
        local humanoid = entity:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            local hasAnimations = entity:FindFirstChild("Animations") or entity:FindFirstChild("AnimSaves")
            
            -- If has animations and not a container, treat as monster
            if hasAnimations and not containerSet[name] then
                return returnCached(true, name, { health = humanoid.Health, maxHealth = humanoid.MaxHealth })
            end
            
            -- Final fallback: any humanoid in unknown structure
            if not containerSet[name] then
                return returnCached(true, name, { health = humanoid.Health, maxHealth = humanoid.MaxHealth })
            end
        end
        
        return false, nil
    end
    
    function EntityDetector.isContainer(entity)
        if not entity then return false end
        
        local name = entity.Name
        for id in pairs(containerSet) do
            if name:find(id, 1, true) then  -- FIX: Plain text match (faster, no regex overhead)
                return true
            end
        end
        
        return false
    end
    
    function EntityDetector.isOpened(entity)
        if not entity then return true end
        
        -- Check game's actual attributes (from Deadly Delivery decompiled)
        -- Open == true means container IS opened
        -- Open == false means container is NOT opened (closed)
        -- en = enabled/active container
        -- ItemDropped = item already dropped from container
        
        local openAttr = entity:GetAttribute("Open")
        local itemDropped = entity:GetAttribute("ItemDropped")
        local enabled = entity:GetAttribute("en")
        local isIgnored = entity:GetAttribute("Ignore")
        
        -- If Open == true, container is opened
        if openAttr == true then
            return true
        end
        
        -- If item already dropped, consider it opened
        if itemDropped == true then
            return true
        end
        
        -- If ignored/blacklisted, consider it opened/unusable
        if isIgnored == true then
            return true
        end
        
        -- If not enabled, consider it opened/unusable
        if enabled == false then
            return true
        end
        
        -- Legacy checks for other games
        local attrs = entity:GetAttributes()
        if attrs then
            if attrs.opened == true or attrs.IsOpen == true or attrs.isOpen == true then
                return true
            end
        end
        
        return false
    end
    
    function EntityDetector.getPosition(entity)
        if not entity then return nil end
        
        if entity:IsA("Model") then
            if entity.PrimaryPart then
                return entity.PrimaryPart.Position
            end
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
            if entity.PrimaryPart then
                return entity.PrimaryPart.CFrame
            end
            local part = entity:FindFirstChildWhichIsA("BasePart")
            if part then return part.CFrame end
        elseif entity:IsA("BasePart") then
            return entity.CFrame
        end
        
        return nil
    end
    
    function EntityDetector.getEntityName(entity)
        if not entity then return "Unknown" end
        
        local isMonster, monsterType = EntityDetector.isMonster(entity)
        if isMonster and monsterType then
            local humanoid = entity:FindFirstChildOfClass("Humanoid")
            if humanoid then
                return string.format("%s [%d/%d]", 
                    monsterType, 
                    math.floor(humanoid.Health), 
                    math.floor(humanoid.MaxHealth))
            end
            return monsterType
        end
        
        return entity.Name
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 8: MOVEMENT ENGINE
-- Smooth teleportation with anti-stuck
-- ═══════════════════════════════════════════════════════════════════

local MovementEngine = {}
do
    local lastPos = Vector3.new(0, 0, 0)
    local stuckTimer = 0
    
    function MovementEngine.teleport(targetCFrame, useSmooth)
        local root = PlayerRefs.rootPart
        if not root then return false end
        
        if useSmooth == nil then
            useSmooth = StateManager.get("useTween")
        end
        
        if useSmooth then
            local distance = (root.Position - targetCFrame.Position).Magnitude
            local duration = math.clamp(distance / 100, 0.1, 1.5)
            
            local tween = TweenService:Create(root, TweenInfo.new(
                duration,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out
            ), {CFrame = targetCFrame})
            
            -- Cancel previous tween if exists to prevent stuttering/conflict
            if MovementEngine._currentTween then
                MovementEngine._currentTween:Cancel()
            end
            MovementEngine._currentTween = tween
            
            local completed = false
            local conn = tween.Completed:Connect(function() 
                completed = true 
                MovementEngine._currentTween = nil
            end)
            tween:Play()
            
            local start = os.clock()
            while not completed and os.clock() - start < (duration + 0.5) do
                task.wait()
            end
            if conn then conn:Disconnect() end
        else
            local char = PlayerRefs.character
            if char then
                char:PivotTo(targetCFrame)
            end
        end
        
        return true
    end
    
    function MovementEngine.resetStuck()
        stuckTimer = 0
        local root = PlayerRefs.rootPart
        if root then lastPos = root.Position end
    end
    
    function MovementEngine.checkStuck()
        local root = PlayerRefs.rootPart
        if not root then return false end
        
        local currentPos = root.Position
        local distance = (currentPos - lastPos).Magnitude
        
        if distance < CONSTANTS.THRESHOLDS.STUCK_DISTANCE then
            stuckTimer = stuckTimer + CONSTANTS.LOOP_INTERVALS.NORMAL
            if stuckTimer >= CONSTANTS.THRESHOLDS.STUCK_TIMEOUT then
                stuckTimer = 0
                -- Random offset to unstuck
                local offset = CFrame.new(
                    math.random(-10, 10),
                    0,
                    math.random(-10, 10)
                )
                root.CFrame = root.CFrame * offset
                return true
            end
        else
            stuckTimer = 0
        end
        
        lastPos = currentPos
        return false
    end
    
    function MovementEngine.getDistanceTo(position)
        local root = PlayerRefs.rootPart
        if not root or not position then return math.huge end
        return (root.Position - position).Magnitude
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 9: INVENTORY MANAGER
-- Slot tracking and auto-sell logic
-- ═══════════════════════════════════════════════════════════════════

local InventoryManager = {}
do
    function InventoryManager.getSlotCount()
        local count = 0
        
        local success = pcall(function()
            local player = PlayerRefs.player
            if not player then return end
            
            local gui = player.PlayerGui
            local main = gui and gui:FindFirstChild("Main")
            local home = main and main:FindFirstChild("HomePage")
            
            if not home then return end
            
            -- FIX: Always count actual filled slots FIRST, not HandsFull indicator
            -- HandsFull UI can bug out and show even when inventory is empty
            local bottom = home:FindFirstChild("Bottom")
            if bottom then
                for _, slot in pairs(bottom:GetChildren()) do
                    if slot:IsA("Frame") then
                        local details = slot:FindFirstChild("ItemDetails")
                        if details then
                            local itemName = details:FindFirstChild("ItemName")
                            if itemName and itemName.Text ~= "" then
                                count = count + 1
                            end
                        end
                    end
                end
            end
            
            -- Only use HandsFull as secondary check if slot counting somehow failed
            -- but we know UI is showing full warning
            if count == 0 then
                local handsFull = home:FindFirstChild("HandsFull")
                if handsFull and handsFull.Visible then
                    -- Don't force 4, just log this discrepancy
                    warn("[InventoryManager] HandsFull visible but slots empty - UI bug detected")
                end
            end
        end)
        
        return count
    end
    

    
    function InventoryManager.getFilledSlots()
        local slots = {}
        local success = pcall(function()
            local player = PlayerRefs.player
            if not player then return end
            
            local gui = player.PlayerGui
            local main = gui and gui:FindFirstChild("Main")
            local home = main and main:FindFirstChild("HomePage")
            
            if not home then return end
            
            local bottom = home:FindFirstChild("Bottom")
            if bottom then
                for i, slot in pairs(bottom:GetChildren()) do
                    if slot:IsA("Frame") then
                        local details = slot:FindFirstChild("ItemDetails")
                        if details then
                            local itemName = details:FindFirstChild("ItemName")
                            if itemName and itemName.Text ~= "" then
                                -- Slot numbering
                                local slotNum = tonumber(slot.Name) or i
                                table.insert(slots, slotNum)
                            end
                        end
                    end
                end
            end
        end)
        
        -- If UI fails or is empty, return actual result (empty table is safer than 1-4)
        if not success or #slots == 0 then
             return {}
        end
        
        return slots
    end

    function InventoryManager.isFull()
        return InventoryManager.getSlotCount() >= 4
    end
    
    function InventoryManager.sellAll()
        return RemoteHandler.fire("BackpackSellAll")
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 10: LOOT BLACKLIST (EMPTY)
-- User requested empty blacklist
-- ═══════════════════════════════════════════════════════════════════

local LootBlacklist = {}
-- Empty as per user request
-- Add items here to skip during auto-farm:
-- LootBlacklist["ItemName"] = true

local function isBlacklisted(itemName)
    return LootBlacklist[itemName] == true
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 11: CONNECTION POOL
-- Track and manage all event connections
-- ═══════════════════════════════════════════════════════════════════

local ConnectionPool = {}
do
    local connections = {}
    local threads = {}
    
    function ConnectionPool.add(connection)
        if connection then
            table.insert(connections, connection)
        end
        return connection
    end
    
    function ConnectionPool.addThread(thread)
        if thread then
            table.insert(threads, thread)
        end
        return thread
    end
    
    function ConnectionPool.spawn(func)
        local thread = task.spawn(func)
        table.insert(threads, thread)
        return thread
    end
    
    function ConnectionPool.disconnectAll()
        for _, conn in ipairs(connections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        connections = {}
        
        for _, thread in ipairs(threads) do
            pcall(function()
                task.cancel(thread)
            end)
        end
        threads = {}
    end
    
    function ConnectionPool.count()
        return #connections, #threads
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 12: ESP SYSTEM
-- Billboard-based entity visualization
-- ═══════════════════════════════════════════════════════════════════

local ESPSystem = {}
do
    -- Fix: Use weak keys so data is automatically GC'd when entity is destroyed
    local espObjects = setmetatable({}, {__mode = "k"})
    local espFolder = Instance.new("Folder")
    espFolder.Name = "PremiumCore_ESP"
    espFolder.Parent = workspace.CurrentCamera
    
    local COLORS = {
        Monster = Color3.fromRGB(255, 50, 50),
        Loot = Color3.fromRGB(50, 255, 50),
        LootFood = Color3.fromRGB(100, 255, 100),     -- Food items
        LootTool = Color3.fromRGB(100, 150, 255),     -- Tools (blue)
        LootMoney = Color3.fromRGB(255, 215, 0),      -- Money (gold)
        LootRecipe = Color3.fromRGB(255, 150, 255),   -- Recipes (pink)
        Container = Color3.fromRGB(255, 255, 50),
        NPC = Color3.fromRGB(50, 200, 255),
        Player = Color3.fromRGB(200, 50, 255),
        Ghost = Color3.fromRGB(180, 180, 255)
    }
    
    function ESPSystem.create(entity, text, color, entityType)
        -- Fix: Check if object exists in weak table directly
        if espObjects[entity] then
            -- Update existing
            if espObjects[entity].nameLabel then
                espObjects[entity].nameLabel.Text = text
            end
            return espObjects[entity]
        end
        
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESP_Entity"
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(120, 50)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.Parent = espFolder
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.Size = UDim2.new(1, 0, 0, 18)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = text
        nameLabel.TextColor3 = color
        nameLabel.TextStrokeTransparency = 0.3
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 13
        nameLabel.Parent = billboard
        
        local distLabel = Instance.new("TextLabel")
        distLabel.Name = "Distance"
        distLabel.Size = UDim2.new(1, 0, 0, 14)
        distLabel.Position = UDim2.fromOffset(0, 18)
        distLabel.BackgroundTransparency = 1
        distLabel.Text = "0m"
        distLabel.TextColor3 = Color3.new(1, 1, 1)
        distLabel.TextStrokeTransparency = 0.5
        distLabel.Font = Enum.Font.Gotham
        distLabel.TextSize = 11
        distLabel.Parent = billboard
        
        -- Adornee setup
        local part = entity:IsA("Model") and (entity.PrimaryPart or entity:FindFirstChildWhichIsA("BasePart")) or entity
        if part then
            billboard.Adornee = part
        end
        

        
        -- Fix: Store by object reference
        espObjects[entity] = {
            gui = billboard,
            nameLabel = nameLabel,
            distLabel = distLabel,
            entity = entity,
            entityType = entityType
        }
        
        return espObjects[entity]
    end
    
    function ESPSystem.remove(entity)
        if espObjects[entity] then
            if espObjects[entity].gui then
                espObjects[entity].gui:Destroy()
            end
            espObjects[entity] = nil
        end
    end
    
    function ESPSystem.clearByType(entityType)
        for entity, data in pairs(espObjects) do
            if data.entityType == entityType then
                if data.gui then
                    data.gui:Destroy()
                end
                espObjects[entity] = nil
            end
        end
    end
    
    function ESPSystem.clearAll()
        for entity, data in pairs(espObjects) do
            if data.gui then
                data.gui:Destroy()
            end
        end
        espObjects = setmetatable({}, {__mode = "k"})
    end
    
    function ESPSystem.update()
        -- Ensure folder exists and is in current camera
        -- FIX: Destroy orphaned folder before creating new one
        if espFolder and espFolder.Parent and espFolder.Parent ~= workspace.CurrentCamera then
            espFolder:Destroy()
            espFolder = nil
        end
        if not espFolder then
            espFolder = Instance.new("Folder")
            espFolder.Name = "PremiumCore_ESP"
            espFolder.Parent = workspace.CurrentCamera
        end

        local root = PlayerRefs.rootPart
        if not root then return end
        
        local noLimit = StateManager.get("espNoLimit")
        
        -- FIX: Collect entities to remove BEFORE modifying table (prevents undefined behavior)
        local toRemove = {}
        for entity, data in pairs(espObjects) do
            -- Weak table auto-handling: keys (entities) that are destroyed 
            -- might still persist until GC runs. We double check Parent.
            if not entity or not entity.Parent then
                table.insert(toRemove, entity)
            else
                local pos = EntityDetector.getPosition(entity)
                if pos then
                    local dist = (root.Position - pos).Magnitude
                    data.distLabel.Text = string.format("%dm", math.floor(dist))
                    data.gui.Enabled = noLimit or dist < 500
                end
            end
        end
        
        -- Now safely remove dead entities
        for _, entity in ipairs(toRemove) do
            if espObjects[entity] and espObjects[entity].gui then
                espObjects[entity].gui:Destroy()
            end
            espObjects[entity] = nil
        end
    end
    
    function ESPSystem.scan()
        local gs = workspace:FindFirstChild("GameSystem")
        if not gs then return end
        
        -- Monster ESP
        if StateManager.get("espMonsters") then
            local monstersFolder = gs:FindFirstChild("Monsters")
            if monstersFolder then
                for _, monster in pairs(monstersFolder:GetChildren()) do
                    local isMonster, monsterType, extraData = EntityDetector.isMonster(monster)
                    if isMonster then
                        -- Build display name directly (avoid double call to isMonster via getEntityName)
                        local displayName = monsterType or monster.Name
                        local humanoid = monster:FindFirstChildOfClass("Humanoid")
                        if humanoid and humanoid.Health > 0 then
                            displayName = string.format("%s [%d/%d]", 
                                displayName, 
                                math.floor(humanoid.Health), 
                                math.floor(humanoid.MaxHealth))
                        end
                        ESPSystem.create(monster, displayName, COLORS.Monster, "Monster")
                    end
                end
            end
        else
            -- Clear monster ESP when disabled
            ESPSystem.clearByType("Monster")
        end
        
        -- Loot ESP (Enhanced with GetAttribute detection)
        if StateManager.get("espLoot") then
            local loots = gs:FindFirstChild("Loots")
            local world = loots and loots:FindFirstChild("World")
            if world then
                for _, loot in pairs(world:GetChildren()) do
                    -- Get item data from attributes
                    local itemId = loot:GetAttribute("id")
                    local itemScale = loot:GetAttribute("scale") or 1
                    local itemSkin = loot:GetAttribute("skin")
                    
                    -- Try to get item name from ConstFunc or fallback
                    local itemName = loot.Name
                    local itemType = "Loot"
                    local itemColor = COLORS.Loot
                    
                    if itemId then
                        -- Try to get proper name from game module
                        pcall(function()
                            local ConstFunc = require(ReplicatedStorage.Shared.Core.ConstFunc)
                            if ConstFunc and ConstFunc.GetName then
                                itemName = ConstFunc.GetName(itemId)
                            end
                            if ConstFunc and ConstFunc.GetType then
                                itemType = ConstFunc.GetType(itemId)
                                -- Color by type
                                if itemType == "Food" then
                                    itemColor = COLORS.LootFood
                                elseif itemType == "Tool" then
                                    itemColor = COLORS.LootTool
                                elseif itemType == "Money" then
                                    itemColor = COLORS.LootMoney
                                elseif itemType == "Recipe" then
                                    itemColor = COLORS.LootRecipe
                                end
                            end
                        end)
                    end
                    
                    -- Add scale indicator if oversized
                    local displayName = itemName
                    if itemScale and itemScale > 1.1 then
                        displayName = string.format("%s (×%.1f)", itemName, itemScale)
                    end
                    
                    ESPSystem.create(loot, displayName, itemColor, "Loot")
                end
            end
        else
            -- Clear loot ESP when disabled
            ESPSystem.clearByType("Loot")
        end
        
        -- Container ESP
        if StateManager.get("espContainers") then
            local containers = gs:FindFirstChild("InteractiveItem")
            if containers then
                local hideOpened = StateManager.get("espHideOpened")
                for _, container in pairs(containers:GetChildren()) do
                    if container:IsA("Model") then
                        local isOpened = EntityDetector.isOpened(container)
                        if hideOpened and isOpened then
                            -- Remove ESP for opened containers
                            ESPSystem.remove(container)
                        else
                            ESPSystem.create(container, container.Name, COLORS.Container, "Container")
                        end
                    end
                end
            end
        else
            -- Clear container ESP when disabled
            ESPSystem.clearByType("Container")
        end
        
        -- NPC ESP
        if StateManager.get("espNPCs") then
            local npcs = gs:FindFirstChild("NPCModels")
            if npcs then
                for _, npc in pairs(npcs:GetChildren()) do
                    -- Try to resolve real name (handles Guest 666 / Hex names)
                    local displayName = npc.Name
                    
                    -- Check if it matches a known fingerprint
                    local isKnown, knownName = EntityDetector.isMonster(npc)
                    if isKnown and knownName then
                        displayName = knownName
                    end
                    
                    ESPSystem.create(npc, displayName, COLORS.NPC, "NPC")
                end
            end
        else
            -- Clear NPC ESP when disabled
            ESPSystem.clearByType("NPC")
        end
        
        -- Player ESP
        if StateManager.get("espPlayers") then
            local localPlayer = PlayerRefs.player
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Character then
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        ESPSystem.create(player.Character, player.Name, COLORS.Player, "Player")
                    end
                end
            end
        else
            -- Clear player ESP when disabled
            ESPSystem.clearByType("Player")
        end
        
        -- Ghost ESP
        if StateManager.get("espGhosts") then
            local ghostsFolder = gs:FindFirstChild("Ghosts") or gs:FindFirstChild("GhostModels")
            if ghostsFolder then
                for _, ghost in pairs(ghostsFolder:GetChildren()) do
                    if ghost:IsA("Model") then
                        ESPSystem.create(ghost, "👻 " .. ghost.Name, COLORS.Ghost, "Ghost")
                    end
                end
            end
            -- Also check for ghost players (spectators)
            for _, player in pairs(Players:GetPlayers()) do
                if player.Character then
                    local isGhost = player.Character:GetAttribute("Ghost") or player.Character:GetAttribute("Spectating")
                    if isGhost then
                        ESPSystem.create(player.Character, "👻 " .. player.Name, COLORS.Ghost, "Ghost")
                    end
                end
            end
        else
            -- Clear ghost ESP when disabled
            ESPSystem.clearByType("Ghost")
        end
    end
    
    function ESPSystem.cleanup()
        for entity, data in pairs(espObjects) do
            if data.gui then data.gui:Destroy() end
        end
        espObjects = setmetatable({}, {__mode = "k"})
        espFolder:ClearAllChildren()
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 13: AUTO FARM SYSTEM
-- Priority-based loot collection
-- ═══════════════════════════════════════════════════════════════════

local AutoFarmSystem = {}
do
    local PRIORITY_KEYWORDS = {
        Key = 100,
        Rare = 90,
        Epic = 80,
        Legendary = 95,
        Crocodile = 85,
        Egg = 85
    }
    
    -- Fix: Use weak keys so destroyed items are auto-removed from blacklist (Memory Leak Fix)
    -- Defined UPVALUE (Shared across all AutoFarmSystem functions)
    local processedItems = setmetatable({}, {__mode = "k"})
    local currentTarget = nil
    
    -- FIX: Local declaration for lastNPCWarnTime (was undeclared global)
    local lastNPCWarnTime = 0

    function AutoFarmSystem.getElevatorPosition()
        local gs = workspace:FindFirstChild("GameSystem")
        local loots = gs and gs:FindFirstChild("Loots")
        
        -- 1. Try explicit ElevatorCollect (Best)
        local elevCollect = loots and loots:FindFirstChild("ElevatorCollect")
        if elevCollect then
            local part = elevCollect:IsA("BasePart") and elevCollect or 
                         (elevCollect:IsA("Model") and elevCollect.PrimaryPart) or
                         elevCollect:FindFirstChildWhichIsA("BasePart", true)
            if part then return part.Position end
        end
        
        -- 2. Fallback to CollectionService tags
        for _, elev in ipairs(CollectionService:GetTagged("Elevator")) do
            if elev:FindFirstChild("Check") then return elev.Check.Position end
            if elev:IsA("BasePart") then return elev.Position end
        end

        -- 3. Fallback to Constant (Only if sane)
        -- Sanity check: If constant is 0,0,0 (invalid), return nil or warn
        if CONSTANTS.ELEVATOR_POS.Magnitude > 10 then
            return CONSTANTS.ELEVATOR_POS
        end
        
        return nil -- Return nil if no safe position found (Caller handles fallback)
    end
    
    local function getPriority(itemName)
        for keyword, priority in pairs(PRIORITY_KEYWORDS) do
            if itemName:find(keyword) then
                return priority
            end
        end
        return 0
    end
    
    local function isValidLoot(item)
        if not item then return false end
        
        -- Anti-Ghost / Structure Check
        if item:IsA("Tool") then
            -- Check for Folder/Interactable structure
            local folder = item:FindFirstChild("Folder")
            local interactable = folder and folder:FindFirstChild("Interactable")
            
            -- Stricter Validation: Must have LootUI fully loaded
            if interactable then
                local ui = interactable:FindFirstChild("LootUI")
                local frame = ui and ui:FindFirstChild("Frame")
                local name = frame and frame:FindFirstChild("ItemName")
                
                if name and name.Text ~= "" then
                     -- Mimic Check (Safety)
                    if (item:FindFirstChild("LeLower_Leg") or item:FindFirstChild("LeftUpper_Leg")) and item:FindFirstChild("Torso") then
                        return false -- It's a trap!
                    end
                    return true
                end
            end
            
            return false
        elseif item:IsA("Model") then
             local interactable = item:FindFirstChild("Interactable")
             if interactable then return true end
        end
        return false
    end
    
    local function sortByPriority(targets)
        table.sort(targets, function(a, b)
            -- Primary: Priority (High value items first)
            if a.priority ~= b.priority then
                return a.priority > b.priority
            end
            -- Secondary: Distance (Nearest first - Efficient Pathing)
            return a.distance < b.distance
        end)
        return targets
    end
    
    function AutoFarmSystem.getTargets()
        local targets = {}
        local root = PlayerRefs.rootPart
        if not root then return targets end
        
        local gs = workspace:FindFirstChild("GameSystem")
        if not gs then return targets end
        
        -- Resolve Dynamic Elevator Position (for Exclusion)
        local elevatorPos = AutoFarmSystem.getElevatorPosition()

        local radius = StateManager.get("noLimitRadius") and 9999 or StateManager.get("lootRadius")
        local usePriority = StateManager.get("priorityLoot")
        
        -- Collect loot items
        local loots = gs:FindFirstChild("Loots")
        local world = loots and loots:FindFirstChild("World")
        if world then
            for _, item in pairs(world:GetChildren()) do
                if not processedItems[item] and not isBlacklisted(item.Name) and item:GetAttribute("ItemDropped") ~= true and isValidLoot(item) then
                    local pos = EntityDetector.getPosition(item)
                    if pos and root then
                        -- Check Elevator Zone Exclusion (uses CONSTANTS.THRESHOLDS)
                        local distToElev = (elevatorPos) and (pos - elevatorPos).Magnitude or 9999
                        if distToElev <= CONSTANTS.THRESHOLDS.ELEVATOR_EXCLUSION then continue end
                        
                        local dist = (root.Position - pos).Magnitude
                        if dist <= radius then
                            table.insert(targets, {
                                object = item,
                                name = item.Name,
                                position = pos,
                                distance = dist,
                                priority = usePriority and getPriority(item.Name) or 0,
                                type = "Loot"
                            })
                        end
                    end
                end
            end
        end
        
        -- Collect containers
        local containers = gs:FindFirstChild("InteractiveItem")
        if containers then
            for _, container in pairs(containers:GetChildren()) do
                if container:IsA("Model") and not processedItems[container] then
                    if not EntityDetector.isOpened(container) then
                        local pos = EntityDetector.getPosition(container)
                        if pos and root then
                            local dist = (root.Position - pos).Magnitude
                            if dist <= radius then
                                table.insert(targets, {
                                    object = container,
                                    name = container.Name,
                                    position = pos,
                                    distance = dist,
                                    priority = 50, -- Containers have medium priority
                                    type = "Container"
                                })
                            end
                        end
                    end
                end
            end
        end
        
        -- Collect NPCs (Auto Save)
        if StateManager.get("farmNPCs") then
            local npcFolder = nil
            local gameSys = workspace:FindFirstChild("GameSystem")
            if gameSys then
                npcFolder = gameSys:FindFirstChild("NPCModels")
            end
            
            if npcFolder then
                local foundCount = 0
                for _, npc in pairs(npcFolder:GetChildren()) do
                    -- DEBUG: Check every child
                    -- warn("DEBUG NPC: Checking " .. npc.Name)
                    
                    if npc:IsA("Model") then
                         if processedItems[npc] then
                             -- warn("DEBUG NPC: Skipped " .. npc.Name .. " (Already Processed)")
                         else
                            local rootPart = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart")
                            if rootPart then
                                -- Check Interactable (Deep Scan)
                                local interactable = npc:FindFirstChild("Interactable")
                                
                                if not interactable then
                                    local folder = npc:FindFirstChild("Folder")
                                    if folder then
                                        interactable = folder:FindFirstChild("Interactable")
                                    end
                                end
                                
                                if interactable then
                                        foundCount = foundCount + 1
                                        table.insert(targets, {
                                        object = npc,
                                        name = npc.Name,
                                        position = rootPart.Position,
                                        distance = (root.Position - rootPart.Position).Magnitude,
                                        priority = 100,
                                        type = "NPC"
                                    })
                                else
                                    warn("[PremiumCore] NPC IGNORED: " .. npc.Name .. " has NO 'Interactable' child!") 
                                end
                            else
                                warn("[PremiumCore] NPC IGNORED: " .. npc.Name .. " has NO RootPart!")
                            end
                         end
                    end
                end

                
                if foundCount > 0 and os.clock() - (lastNPCWarnTime or 0) > 5 then
                    warn("[PremiumCore] Found " .. foundCount .. " active NPCs to save!")
                    lastNPCWarnTime = os.clock()
                end
            else
                -- WARN ONCE per 5 seconds to avoid spam
                if os.clock() % 5 < 1 then
                    warn("[PremiumCore] 'NPCModels' folder not found in Workspace!")
                end
            end
        end
        
        if usePriority then
            sortByPriority(targets)
        else
            -- Sort by distance
            table.sort(targets, function(a, b)
                return a.distance < b.distance
            end)
        end
        
        return targets
    end
    

    
    function AutoFarmSystem.interact(target)
        if not target or not target.object then return false end
        
        local targetCFrame = EntityDetector.getCFrame(target.object)
        if not targetCFrame then return false end
        
        -- SPECIAL LOGIC: NPC Delivery
        if target.type == "NPC" then
             -- Check if NPC is still valid and enabled
             if not target.object or not target.object.Parent then
                 return false
             end
             
             -- FIX: Only skip if 'en' is EXPLICITLY false (not nil/missing)
             -- Original bug: `if not GetAttribute("en")` was true when en=nil, blocking ALL NPCs
             if target.object:GetAttribute("en") == false then
                 warn("[PremiumCore] NPC not enabled (en=false): " .. tostring(target.name))
                 processedItems[target.object] = true
                 return false
             end
             
             Notify({
                 Title = "Auto Save NPC",
                 Content = "Picking up: " .. tostring(target.name),
                 Duration = 2
             })
             
             -- 1. Teleport to NPC
             local rootPart = target.object.PrimaryPart or target.object:FindFirstChild("HumanoidRootPart")
             if not rootPart then
                 processedItems[target.object] = true
                 return false
             end
             
             local offset = CFrame.new(rootPart.Position + Vector3.new(0, 10, 0))
             MovementEngine.teleport(offset)
             task.wait(0.2)
             
             -- 2. Interact (Pickup) using RemoteHandler
             -- FIX: TEvent.FireRemote already wraps args in table
             -- DO NOT double-wrap: pass raw npc, TEvent will make it {npc}
             RemoteHandler.fireFast("Interactable", target.object)
             task.wait(0.5) -- Wait for attach/pickup
             
             -- 3. Teleport to Elevator (Delivery)
             local elevatorPos = AutoFarmSystem.getElevatorPosition()
             if elevatorPos then
                 MovementEngine.teleport(CFrame.new(elevatorPos) * CFrame.new(0, 3, 0))
                 safeSetStatus("Status: <font color='#00FFFF'>Delivering NPC...</font>")
                 Notify({
                     Title = "Auto Save NPC",
                     Content = "Delivering to Elevator...",
                     Duration = 1
                 })
                 task.wait(1.0) -- Wait for drop/save
             end
             
             -- 4. Check if NPC was saved
             if not target.object.Parent or not target.object:GetAttribute("en") then
                 Notify({
                     Title = "Auto Save NPC",
                     Content = "NPC Saved: " .. tostring(target.name),
                     Duration = 1
                 })
             end
             
             processedItems[target.object] = true
             currentTarget = nil
             return true
        end
        
        local offset = CFrame.new(targetCFrame.Position) * CFrame.new(0, 3, 0)
        
        -- Teleport immediately
        MovementEngine.teleport(offset)
        
        -- Mark as processed IMMEDIATELY to prevent main loop from picking it again
        processedItems[target.object] = true
        StateManager.set("itemsCollected", StateManager.get("itemsCollected") + 1)
        
        -- Non-blocking interaction spam
        task.spawn(function()
            for i = 1, 3 do
                if not target.object or not target.object.Parent then break end
                RemoteHandler.fireFast("Interactable", target.object)
                task.wait(0.05)
            end
        end)
        
        -- Reset current target after successful interaction logic initiation (hit and run)
        -- This allows the next loop iteration to pick a new target immediately
        currentTarget = nil
        
        return true
    end
    
    function AutoFarmSystem.isMonsterNearby(radius)
        radius = radius or 50
        local root = PlayerRefs.rootPart
        if not root then return false end
        
        local gs = workspace:FindFirstChild("GameSystem")
        if not gs then return false end
        
        local monsters = gs:FindFirstChild("Monsters")
        if not monsters then return false end
        
        for _, monster in pairs(monsters:GetChildren()) do
            local isMonster = EntityDetector.isMonster(monster)
            if isMonster then
                local pos = EntityDetector.getPosition(monster)
                if pos and (root.Position - pos).Magnitude < radius then
                    return true, monster
                end
            end
        end
        
        return false
    end
    
    function AutoFarmSystem.clearProcessed()
        processedItems = setmetatable({}, {__mode = "k"})
        currentTarget = nil
    end
    
    -- Expose internal state for Main Loop
    function AutoFarmSystem.getCurrentTarget()
        return currentTarget
    end
    
    function AutoFarmSystem.setCurrentTarget(target)
        currentTarget = target
    end
    
    function AutoFarmSystem.isProcessed(obj)
        return processedItems[obj]
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 14: BUFF EXPLOITS
-- Stamina and speed manipulation
-- ═══════════════════════════════════════════════════════════════════

local BuffExploits = {}
do
    local staminaActive = false
    
    function BuffExploits.toggleInfiniteStamina(enabled)
        staminaActive = enabled
        
        task.spawn(function()
            local success = pcall(function()
                local BuffModule = ReplicatedStorage:WaitForChild("Shared", 5)
                    :WaitForChild("Features", 5)
                    :WaitForChild("Buff", 5)
                
                if BuffModule then
                    local Buff = require(BuffModule)
                    local Manager = Buff.GetManager(PlayerRefs.player)
                    
                    if enabled then
                        -- Remove existing stamina buffs
                        Manager:RemoveName("RoleStamina")
                        
                        -- Add god buffs
                        Manager:AddBuff({
                            name = "PremiumStaminaLimit",
                            type = "StaminaLimit",
                            value = 999999,
                            duration = 999999,
                            tags = {"Add", "PersistOnDeath"}
                        })
                        Manager:AddBuff({
                            name = "PremiumStaminaRegen",
                            type = "StaminaRegenRate",
                            value = 999999,
                            duration = 999999,
                            tags = {"Multi", "PersistOnDeath"}
                        })
                    else
                        Manager:RemoveName("PremiumStaminaLimit")
                        Manager:RemoveName("PremiumStaminaRegen")
                    end
                end
            end)
        end)
    end
    
    function BuffExploits.toggleSpeedBoost(enabled)
        task.spawn(function()
            local success = pcall(function()
                local BuffModule = ReplicatedStorage:WaitForChild("Shared", 5)
                    :WaitForChild("Features", 5)
                    :WaitForChild("Buff", 5)
                
                if BuffModule then
                    local Buff = require(BuffModule)
                    local Manager = Buff.GetManager(PlayerRefs.player)
                    
                    if enabled then
                        Manager:AddBuff({
                            name = "PremiumSpeedWalk",
                            type = "WalkSpeed",
                            value = 2.0,
                            duration = 999999,
                            tags = {"Multi", "PersistOnDeath"}
                        })
                        Manager:AddBuff({
                            name = "PremiumSpeedRun",
                            type = "RunSpeed",
                            value = 2.0,
                            duration = 999999,
                            tags = {"Multi", "PersistOnDeath"}
                        })
                    else
                        Manager:RemoveName("PremiumSpeedWalk")
                        Manager:RemoveName("PremiumSpeedRun")
                    end
                end
            end)
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 15: ADVANCED STAMINA EXPLOITS
-- Remote Blocking, Upvalue Manipulation, Logic Bypass
-- ═══════════════════════════════════════════════════════════════════

local AdvancedStaminaExploits = {}
do
    local remoteBlockActive = false
    local zeroDrainActive = false
    local freezeLoopActive = false
    local hookInstalled = false
    local oldNamecall = nil
    
    -- Method 1: Remote Blocking via HookManager (Block 'SyncStaminaConsume')
    function AdvancedStaminaExploits.installRemoteBlock()
        if hookInstalled then return true end
        
        -- Use unified HookManager instead of installing separate hook
        HookManager.register("StaminaBlock", 
            -- Condition: Check if this is a stamina consume remote
            function(method, self, args)
                if method == "FireServer" and remoteBlockActive then
                    if tostring(self.Name) == "SyncStaminaConsume" then return true end
                    if args[1] and args[1] == "SyncStaminaConsume" then return true end
                end
                return false
            end,
            -- Handler: Block by returning nil
            function(self, method, args)
                return nil
            end
        )
        
        hookInstalled = true
        return true
    end
    
    function AdvancedStaminaExploits.setRemoteBlock(enabled)
        remoteBlockActive = enabled
        if enabled and not hookInstalled then
            AdvancedStaminaExploits.installRemoteBlock()
        end
    end
    
    -- Method 2: Upvalue Manipulation (Set drain rate = 0)
    function AdvancedStaminaExploits.setZeroDrain(enabled)
        zeroDrainActive = enabled
        
        if enabled then
            ConnectionPool.spawn(function()
                while zeroDrainActive and StateManager.get("alive") do
                    pcall(function()
                        for _, conn in pairs(getconnections(RunService.PreRender)) do
                            local func = conn.Function
                            if func then
                                local s = rawget(getfenv(func), "script")
                                if s and (s:GetFullName():find("StaminaHandle") or s.Name == "StaminaHandle") then
                                    local upvalues = debug.getupvalues(func)
                                    for i, v in pairs(upvalues) do
                                        if type(v) == "number" then
                                            -- Force drain rates (18 Normal, 0.9 Lobby) to 0
                                            if math.abs(v - 18) < 0.01 or math.abs(v - 0.9) < 0.01 then
                                                debug.setupvalue(func, i, 0)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(1)
                end
            end)
        end
    end
    
    -- Method 3: Logic Bypass (Freeze/Disable PreRender loop)
    function AdvancedStaminaExploits.setFreezeLoop(enabled)
        freezeLoopActive = enabled
        local count = 0
        
        pcall(function()
            for _, conn in pairs(getconnections(RunService.PreRender)) do
                local func = conn.Function
                if func then
                    local s = rawget(getfenv(func), "script")
                    if s and (s:GetFullName():find("StaminaHandle") or s.Name == "StaminaHandle") then
                        if enabled then
                            conn:Disable()
                        else
                            conn:Enable()
                        end
                        count = count + 1
                    end
                end
            end
        end)
        
        return count
    end
    
    -- Status getters
    function AdvancedStaminaExploits.isRemoteBlockActive()
        return remoteBlockActive
    end
    
    function AdvancedStaminaExploits.isZeroDrainActive()
        return zeroDrainActive
    end
    
    function AdvancedStaminaExploits.isFreezeLoopActive()
        return freezeLoopActive
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 16: ALWAYS IN ELEVATOR
-- Anti-kick protection
-- ═══════════════════════════════════════════════════════════════════

local ElevatorProtection = {}
do
    function ElevatorProtection.spoof()
        local success = pcall(function()
            local TEvent = require(ReplicatedStorage.Shared.Core.TEvent)
            local root = PlayerRefs.rootPart
            if root then
                TEvent.FireRemote(
                    "PlayerInElevator", 
                    true, 
                    root.CFrame.Position, 
                    TEvent.UnixTimeMillis()
                )
            end
        end)
        return success
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 16: LIGHTING CONTROL
-- Fullbright toggle
-- ═══════════════════════════════════════════════════════════════════

local LightingControl = {}
do
    local savedLighting = {}
    
    function LightingControl.setFullbright(enabled)
        local lighting = Services.Lighting
        
        if enabled then
            -- Save current values
            savedLighting = {
                Ambient = lighting.Ambient,
                OutdoorAmbient = lighting.OutdoorAmbient,
                Brightness = lighting.Brightness
            }
            
            -- Apply fullbright
            lighting.Ambient = Color3.new(1, 1, 1)
            lighting.OutdoorAmbient = Color3.new(1, 1, 1)
            lighting.Brightness = 2
        else
            -- Restore saved values
            lighting.Ambient = savedLighting.Ambient or Color3.new(0, 0, 0)
            lighting.OutdoorAmbient = savedLighting.OutdoorAmbient or Color3.new(0, 0, 0)
            lighting.Brightness = savedLighting.Brightness or 1
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 17: NPC MODULE
-- NPC detection and teleportation functions
-- ═══════════════════════════════════════════════════════════════════

local NPCModule = {}
do
    function NPCModule.getAll()
        local npcs = {}
        local gs = workspace:FindFirstChild("GameSystem")
        if not gs then return npcs end
        
        local npcFolder = gs:FindFirstChild("NPCModels")
        if npcFolder then
            for _, npc in pairs(npcFolder:GetChildren()) do
                if npc:IsA("Model") then
                    table.insert(npcs, npc)
                end
            end
        end
        
        return npcs
    end
    
    function NPCModule.getNearest()
        local root = PlayerRefs.rootPart
        if not root then return nil end
        
        local npcs = NPCModule.getAll()
        local nearest, nearestDist = nil, math.huge
        
        for _, npc in ipairs(npcs) do
            local pos = EntityDetector.getPosition(npc)
            if pos then
                local dist = (root.Position - pos).Magnitude
                if dist < nearestDist then
                    nearest = npc
                    nearestDist = dist
                end
            end
        end
        
        return nearest, nearestDist
    end
    
    function NPCModule.teleportToNearest()
        local npc, dist = NPCModule.getNearest()
        if npc then
            local cf = EntityDetector.getCFrame(npc)
            if cf then
                MovementEngine.teleport(cf * CFrame.new(0, 3, 5))
                return true, npc.Name, dist
            end
        end
        return false
    end
    
    function NPCModule.teleportToRandom()
        local npcs = NPCModule.getAll()
        if #npcs == 0 then return false end
        
        local randomNPC = npcs[math.random(1, #npcs)]
        local cf = EntityDetector.getCFrame(randomNPC)
        if cf then
            MovementEngine.teleport(cf * CFrame.new(0, 3, 5))
            return true, randomNPC.Name
        end
        return false
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 18: MONSTER TRACKER ALERT
-- Visual alert when monster is nearby
-- ═══════════════════════════════════════════════════════════════════

local MonsterTrackerAlert = {}
do
    local alertGui = nil
    local alertLabel = nil
    
    function MonsterTrackerAlert.create()
        if alertGui then return end
        
        alertGui = Instance.new("ScreenGui")
        alertGui.Name = "PC_MonsterAlert_" .. CONSTANTS.SESSION_ID:sub(1, 4)
        local player = PlayerRefs.player
        if not player then return end
        alertGui.Parent = player:WaitForChild("PlayerGui")
        alertGui.ResetOnSpawn = false
        
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 300, 0, 60)
        frame.Position = UDim2.new(0.5, -150, 0, 120)
        frame.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
        frame.BackgroundTransparency = 0.2
        frame.Visible = false
        frame.Parent = alertGui
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = frame
        
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 50, 50)
        stroke.Thickness = 2
        stroke.Parent = frame
        
        alertLabel = Instance.new("TextLabel")
        alertLabel.Size = UDim2.new(1, -20, 1, 0)
        alertLabel.Position = UDim2.fromOffset(10, 0)
        alertLabel.BackgroundTransparency = 1
        alertLabel.Font = Enum.Font.GothamBold
        alertLabel.TextSize = 18
        alertLabel.TextColor3 = Color3.new(1, 1, 1)
        alertLabel.Text = "⚠️ DANGER: Monster Nearby!"
        alertLabel.TextXAlignment = Enum.TextXAlignment.Center
        alertLabel.Parent = frame
        
        return frame
    end
    
    function MonsterTrackerAlert.show(monsterName, distance)
        if not alertGui then MonsterTrackerAlert.create() end
        
        local frame = alertGui:FindFirstChildOfClass("Frame")
        if frame then
            frame.Visible = true
            alertLabel.Text = string.format("⚠️ %s - %dm away!", monsterName or "Monster", math.floor(distance or 0))
        end
    end
    
    function MonsterTrackerAlert.hide()
        if alertGui then
            local frame = alertGui:FindFirstChildOfClass("Frame")
            if frame then
                frame.Visible = false
            end
        end
    end
    
    function MonsterTrackerAlert.destroy()
        if alertGui then
            alertGui:Destroy()
            alertGui = nil
            alertLabel = nil
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 19: DUNGEON EXPLOITS
-- Evacuate, Tool Spam, Hotbar control
-- ═══════════════════════════════════════════════════════════════════

local DungeonExploits = {}
do
    local bankingActive = false
    
    function DungeonExploits.instantEvacuate()
        local evacs = CollectionService:GetTagged("Evacuation")
        if #evacs > 0 then
            local target = evacs[1]
            local interact = target:FindFirstChild("Interactable", true)
            if interact then
                local root = PlayerRefs.rootPart
                local dist = root and (root.Position - target.Position).Magnitude or 0
                RemoteHandler.fire("EvacuateAlone", target.Position)
                return true, dist
            end
        end
        return false
    end
    
    -- Instant Banking (CollectPart Spoof) - Forces inventory deposit ANYWHERE
    function DungeonExploits.forceBank()
        return RemoteHandler.fire("PlayerEnterCollectPart", true)
    end
    
    function DungeonExploits.stopBank()
        return RemoteHandler.fire("PlayerEnterCollectPart", false)
    end
    
    function DungeonExploits.setBankingLoop(enabled)
        bankingActive = enabled
        if enabled then
            ConnectionPool.spawn(function()
                while bankingActive and StateManager.get("alive") do
                    RemoteHandler.fire("PlayerEnterCollectPart", true)
                    task.wait(2) -- Don't spam too hard, banking takes time
                end
                RemoteHandler.fire("PlayerEnterCollectPart", false)
            end)
        end
    end
    
    function DungeonExploits.isBankingActive()
        return bankingActive
    end
    
    function DungeonExploits.dropAllItems()
        local slots = InventoryManager.getFilledSlots()
        local success = true
        
        for _, slot in ipairs(slots) do
            -- 1. Switch
            RemoteHandler.fire("Hotbar_Switch", slot)
            task.wait(0.1)
            -- 2. Drop
            if not RemoteHandler.fire("Hotbar_Drop", slot) then
                success = false
            end
            task.wait(0.15)
        end
        return success
    end
    
    function DungeonExploits.useTool()
        return RemoteHandler.fire("UseTool", 1)  -- KILO Fix: Correct remote name
    end
    
    function DungeonExploits.switchSlot(slot)
        return RemoteHandler.fire("Hotbar_Switch", slot)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 20: HIGHLIGHT ELEVATOR
-- Visual highlight for elevator
-- ═══════════════════════════════════════════════════════════════════

local ElevatorHighlight = {}
do
    local highlights = {}
    
    function ElevatorHighlight.toggle(enabled)
        local hlName = "PC_Highlight_" .. CONSTANTS.SESSION_ID:sub(1, 4)
        
        if enabled then
            for _, v in pairs(workspace:GetDescendants()) do
                if (v.Name == "Ground" or v.Name:find("Elevator") or v.Name:find("Lift")) and v.Parent then
                    local existing = v.Parent:FindFirstChild(hlName)
                    if not existing then
                        local hl = Instance.new("Highlight")
                        hl.Name = hlName
                        hl.FillColor = Color3.fromRGB(0, 255, 0)
                        hl.OutlineColor = Color3.fromRGB(0, 200, 0)
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.Parent = v.Parent
                        table.insert(highlights, hl)
                    end
                end
            end
        else
            for _, hl in ipairs(highlights) do
                if hl and hl.Parent then
                    hl:Destroy()
                end
            end
            highlights = {}
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 21: ANTI-AFK
-- Prevent idle kick
-- ═══════════════════════════════════════════════════════════════════

local AntiAFKSystem = {}
do
    function AntiAFKSystem.pulse()
        local player = PlayerRefs.player
        if player then
            local vu = game:GetService("VirtualUser")
            pcall(function()
                vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 22: SANITY PROTECTION (Anti-Drain)
-- Blocks 'SeeSomething' remote to prevent sanity drain from monsters
-- ═══════════════════════════════════════════════════════════════════

local SanityProtection = {}
do
    local blockSight = false
    local hookInstalled = false
    local oldNamecall = nil
    
    function SanityProtection.install()
        if hookInstalled then return true end
        
        -- Use unified HookManager instead of installing separate hook
        HookManager.register("SanityBlock", 
            -- Condition: Check if this is a sanity sight remote
            function(method, self, args)
                if method == "FireServer" and blockSight then
                    if tostring(self.Name) == "SeeSomething" then return true end
                    for _, arg in pairs(args) do
                        if type(arg) == "string" and arg == "SeeSomething" then return true end
                    end
                end
                return false
            end,
            -- Handler: Block by returning nil
            function(self, method, args)
                return nil
            end
        )
        
        hookInstalled = true
        return true
    end
    
    function SanityProtection.setEnabled(enabled)
        blockSight = enabled
        if enabled and not hookInstalled then
            SanityProtection.install()
        end
    end
    
    function SanityProtection.isEnabled()
        return blockSight
    end
    
    function SanityProtection.isInstalled()
        return hookInstalled
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 23: DUNGEON STATS READER
-- Reads game's DungeonStats Value for realtime data
-- Structure: { level, isRunning, event, countdown: { isActive, time } }
-- ═══════════════════════════════════════════════════════════════════

local DungeonStats = {}
do
    local valueModule = nil
    local statsValue = nil
    local mapValue = nil
    local bossValue = nil
    local connection = nil
    
    -- Try to get the Value module from game
    function DungeonStats.init()
        pcall(function()
            valueModule = require(ReplicatedStorage.Shared.Core.Value)
            if valueModule then
                statsValue = valueModule.DungeonStats
                mapValue = valueModule.Map
                bossValue = valueModule.BossFightRunning
            end
        end)
        return valueModule ~= nil
    end
    
    -- Get current stats
    function DungeonStats.get()
        if not statsValue then
            DungeonStats.init()
        end
        
        local stats = {
            level = 0,
            isRunning = false,
            event = "null",
            state = "Unknown",
            countdown = { isActive = false, time = 0 },
            map = "Unknown",
            bossActive = false
        }
        
        pcall(function()
            if statsValue and statsValue.Value then
                local val = statsValue.Value
                stats.level = val.level or 0
                stats.isRunning = val.isRunning or false
                stats.event = val.event or "null"
                stats.state = val.state or "Unknown"
                
                if val.countdown then
                    stats.countdown.isActive = val.countdown.isActive or false
                    stats.countdown.time = val.countdown.time or 0
                end
            end
            
            if mapValue and mapValue.Value then
                stats.map = mapValue.Value
            end
            
            if bossValue then
                stats.bossActive = bossValue.Value or false
            end
        end)
        
        return stats
    end
    
    -- Connect to Changed event for realtime updates
    function DungeonStats.connect(callback)
        DungeonStats.init()
        
        if statsValue and statsValue.Changed then
            connection = ConnectionPool.add(statsValue.Changed:Connect(function(newValue)
                local stats = DungeonStats.get()
                callback(stats)
            end))
        end
        
        return connection
    end
    
    -- Disconnect listener
    function DungeonStats.disconnect()
        if connection then
            pcall(function() connection:Disconnect() end)
            connection = nil
        end
    end
    
    -- Get floor level
    function DungeonStats.getFloor()
        local stats = DungeonStats.get()
        return stats.level
    end
    
    -- Get countdown time
    function DungeonStats.getCountdown()
        local stats = DungeonStats.get()
        return stats.countdown.time, stats.countdown.isActive
    end
    
    -- Check if dungeon is running
    function DungeonStats.isRunning()
        local stats = DungeonStats.get()
        return stats.isRunning
    end
    
    -- Check if boss fight active
    function DungeonStats.isBossFight()
        local stats = DungeonStats.get()
        return stats.bossActive
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 23: INTERNAL DUNGEON HUD
-- Time, Floor, State display
-- ═══════════════════════════════════════════════════════════════════

local InternalHUD = {}
do
    local hudGui = nil
    local coinsStart = -1
    
    function InternalHUD.create()
        if hudGui then return end
        
        hudGui = Instance.new("ScreenGui")
        hudGui.Name = "PC_HUD_" .. CONSTANTS.SESSION_ID:sub(1, 4)
        hudGui.Parent = PlayerRefs.player:WaitForChild("PlayerGui")
        hudGui.ResetOnSpawn = false
        
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 220, 0, 210) -- Increased height
        frame.Position = UDim2.new(0.5, -110, 0, 80)
        frame.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
        frame.BackgroundTransparency = 0.2
        frame.Parent = hudGui
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame
        
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 217, 255)
        stroke.Thickness = 2
        stroke.Parent = frame
        
        -- Labels
        local function createLabel(name, posY, text, color)
            local lbl = Instance.new("TextLabel")
            lbl.Name = name
            lbl.Size = UDim2.new(1, -20, 0, 20)
            lbl.Position = UDim2.new(0, 10, 0, posY)
            lbl.BackgroundTransparency = 1
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 14
            lbl.TextColor3 = color or Color3.new(1, 1, 1)
            lbl.Text = text
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = frame
            return lbl
        end
        
        createLabel("User", 10, "User: " .. PlayerRefs.player.Name, Color3.fromRGB(200, 200, 255))
        createLabel("Time", 35, "Time: --:--", Color3.fromRGB(255, 255, 0))
        createLabel("Floor", 60, "Floor: --", Color3.fromRGB(0, 255, 0))
        createLabel("State", 85, "State: Waiting...", Color3.fromRGB(200, 200, 200))
        createLabel("Boss", 110, "Boss: None", Color3.fromRGB(255, 100, 100))
        
        -- Separator
        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, -20, 0, 1)
        sep.Position = UDim2.new(0, 10, 0, 135)
        sep.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        sep.BorderSizePixel = 0
        sep.Parent = frame
        
        createLabel("Coins", 140, "Coins: 0 (+0)", Color3.fromRGB(255, 215, 0))
        createLabel("SellVal", 165, "Sell Value: $0", Color3.fromRGB(0, 255, 127))
        createLabel("BestFood", 190, "Best Food: None", Color3.fromRGB(255, 160, 122))
    end
    
    function InternalHUD.update(time, floor, state, bossActive)
        if not hudGui then return end
        local frame = hudGui:FindFirstChildOfClass("Frame")
        if not frame then return end
        
        -- Helper
        local function setText(name, text, color)
            local lbl = frame:FindFirstChild(name)
            if lbl then 
                lbl.Text = text 
                if color then lbl.TextColor3 = color end
            end
        end
        
        -- Core Stats
        if time then
            local minutes = math.floor(time / 60)
            local seconds = math.floor(time % 60)
            setText("Time", string.format("Time: %02d:%02d", minutes, seconds), time < 10 and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 0))
        end
        if floor then setText("Floor", "Floor: " .. tostring(floor)) end
        if state then setText("State", "State: " .. tostring(state)) end
        setText("Boss", bossActive and "Boss: ACTIVE!" or "Boss: None", bossActive and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(100, 255, 100))
        
        -- Economy Stats
        local currentCoins = 0
        if ValueModule and ValueModule.Coins then
             currentCoins = ValueModule.Coins.Value or 0
        elseif PlayerRefs.player and PlayerRefs.player.leaderstats and PlayerRefs.player.leaderstats:FindFirstChild("Coins") then
             currentCoins = PlayerRefs.player.leaderstats.Coins.Value
        end
        
        if coinsStart == -1 then coinsStart = currentCoins end
        local pickedUp = math.max(0, currentCoins - coinsStart)
        
        setText("Coins", "Coins: " .. FormatNumber(currentCoins) .. " (+" .. FormatNumber(pickedUp) .. ")")
        
        -- Inventory Stats
        local sellValue = 0
        local bestFood = "None"
        local bestCals = -1
        
        if PlayerRefs.player then
            local bp = PlayerRefs.player:FindFirstChild("Backpack")
            if bp then
                for _, item in pairs(bp:GetChildren()) do
                    if item:IsA("Tool") and ItemLoot then
                        local data = ItemLoot[item.Name]
                        if data then
                            if data.SellValue then sellValue = sellValue + data.SellValue end
                            if data.feed and data.feed > bestCals then
                                bestCals = data.feed
                                bestFood = item.Name .. " (+" .. data.feed .. ")"
                            end
                        end
                    end
                end
            end
        end
        
        setText("SellVal", "Sell Value: $" .. FormatNumber(sellValue))
        setText("BestFood", "Best Food: " .. bestFood)
    end
    
    function InternalHUD.destroy()
        if hudGui then
            hudGui:Destroy()
            hudGui = nil
        end
    end    
    function InternalHUD.isVisible()
        return hudGui ~= nil
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 23: WINDUI INITIALIZATION
-- Load WindUI library
-- ═══════════════════════════════════════════════════════════════════

local WindUI
local success, result = pcall(function()
    return loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/gabuskyun02-lang/roblox-windui/refs/heads/main/dist/main.lua"
    ))()
end)

if success and result then
    WindUI = result
else
    warn("[PremiumCore] Failed to load WindUI. Check network connection.")
    -- Optionally fallback or error out safely
    -- Inserting dummy WindUI to prevent crash if logic continues (though Window creation will fail)
    WindUI = {
        CreateWindow = function() error("WindUI Failed to Load") end
    }
end

local Window = nil
local Notify = function(config)
    if StateManager.get("notifications") and WindUI then
        task.spawn(function()
            pcall(function() 
                WindUI:Notify(config)
            end)
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 18: UI CONSTRUCTION
-- Build WindUI interface
-- ═══════════════════════════════════════════════════════════════════

Window = WindUI:CreateWindow({
    Title = "PREMIUM CORE",
    Icon = "skull",
    Size = UDim2.fromOffset(880, 560),
    Acrylic = true,
    Theme = "Dark"
})

-- ─────────────────────────────────────────────────────────────────
-- TAB: HOME
-- ─────────────────────────────────────────────────────────────────

local HomeTab = Window:Tab({ Title = "Home", Icon = "home", Prefix = Window.TabPrefix })

local StatsSection = HomeTab:Section({ Title = "STATISTICS" })

local StatusParagraph = StatsSection:Paragraph({
    Title = "Status: <font color='#FFD700'>Initializing...</font>"
})

local StatsParagraph = StatsSection:Paragraph({
    Title = "Items: 0 | IPM: 0.0 | Floor: 0"
})

-- Safe UI update wrappers to prevent WindUI chain errors (KILO Fix)
local lastStatusUpdate = 0
local function safeSetStatus(title)
    if not StatusParagraph then return end
    if os.clock() - lastStatusUpdate < 0.5 then return end  -- Throttle: max 2 updates/sec
    
    local success = pcall(function()
        StatusParagraph:SetTitle(title)
    end)
    
    if success then
        lastStatusUpdate = os.clock()
    end
end

local lastStatsUpdate = 0
local function safeSetStats(title)
    if not StatsParagraph then return end
    if os.clock() - lastStatsUpdate < 0.3 then return end  -- Throttle stats updates
    
    local success = pcall(function()
        StatsParagraph:SetTitle(title)
    end)
    
    if success then
        lastStatsUpdate = os.clock()
    end
end

StatsSection:Button({
    Title = "🚨 PANIC (Emergency Stop)",
    Callback = function()
        StateManager.set("alive", false)
        ConnectionPool.disconnectAll()
        ESPSystem.cleanup()
        Window:Destroy()
    end
})

StatsSection:Toggle({
    Title = "Notifications",
    Default = true,
    Callback = function(value)
        StateManager.set("notifications", value)
    end
})

-- Farm Settings Section
local FarmSection = HomeTab:Section({ Title = "AUTO FARM" })

FarmSection:Toggle({
    Title = "Enable Auto-Farm",
    Default = false,
    Callback = function(value)
        StateManager.set("farmActive", value)
        Notify({
            Title = "Farm",
            Content = value and "Auto-Farm ENABLED" or "Auto-Farm DISABLED",
            Duration = 3
        })
    end
})

FarmSection:Toggle({
    Title = "Safe Mode (Pause near monsters)",
    Default = false,
    Callback = function(value)
        StateManager.set("safeMode", value)
        Notify({Title = "Safe Mode", Content = value and "Safety ON" or "Safety OFF", Duration = 1})
    end
})

FarmSection:Toggle({
    Title = "Priority Loot Mode",
    Desc = "Prioritize valuable items first",
    Default = true,
    Callback = function(val)
        StateManager.set("priorityLoot", val)
    end
})

FarmSection:Toggle({
    Title = "Auto Farm NPCs",
    Default = false,
    Callback = function(val)
        pcall(function()
            StateManager.set("farmNPCs", val)
        end)
    end
})

FarmSection:Button({
    Title = "Clear Ignored Items",
    Callback = function()
        AutoFarmSystem.clearProcessed()
        Notify({Title = "System", Content = "Cache Cleared! Retrying...", Duration = 1})
    end
})

FarmSection:Toggle({
    Title = "Anti-Stuck",
    Default = true,
    Callback = function(value)
        StateManager.set("antiStuck", value)
    end
})

FarmSection:Slider({
    Title = "Loot Radius",
    Value = { Min = 20, Max = 200, Default = 50 },
    Callback = function(value)
        StateManager.set("lootRadius", value)
    end
})

FarmSection:Slider({
    Title = "Farm Speed",
    Value = { Min = 50, Max = 200, Default = 100 },
    Callback = function(value)
        StateManager.set("farmSpeed", value / 100)
    end
})

-- Farm Improvements Section
local FarmImpSection = HomeTab:Section({ Title = "FARM IMPROVEMENTS" })

FarmImpSection:Toggle({
    Title = "🛡️ Anti-AFK",
    Default = false,
    Callback = function(value)
        StateManager.set("antiAFK", value)
        Notify({Title = "Farm", Content = value and "Anti-AFK ENABLED" or "Anti-AFK DISABLED", Duration = 2})
    end
})

FarmImpSection:Toggle({
    Title = "🧭 Smart Pathing",
    Default = false,
    Callback = function(value)
        StateManager.set("smartPathing", value)
        Notify({Title = "Farm", Content = value and "Smart Pathing ON" or "Smart Pathing OFF", Duration = 2})
    end
})

-- Thread tracking for True Safety
local trueSafetyThread = nil

FarmImpSection:Toggle({
    Title = "True Safety (Elevator Spoof)",
    Default = false,
    Callback = function(state)
        StateManager.set("elevatorSafety", state)
        
        -- Cancel existing thread if disabling
        if not state and trueSafetyThread then
            pcall(function() task.cancel(trueSafetyThread) end)
            trueSafetyThread = nil
        end
        
        if state then
            trueSafetyThread = task.spawn(function()
                local success, TEvent = pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Core.TEvent) end)
                if not success then 
                    warn("Failed to require TEvent") 
                    return 
                end
                
                local safePos = AutoFarmSystem.getElevatorPosition()
                while StateManager.get("elevatorSafety") do
                    -- Packet Structure: (true, Pos, TimeMillis)
                    pcall(function()
                        TEvent.FireRemote("PlayerInElevator", true, safePos, TEvent.UnixTimeMillis())
                    end)
                    task.wait(0.5) -- Keep alive
                end
                
                -- Send exit packet when loop ends
                local char = Players.LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local exitPos = root and root.Position or safePos
                pcall(function()
                     TEvent.FireRemote("PlayerInElevator", false, exitPos, TEvent.UnixTimeMillis())
                end)
                Notify({Title = "System", Content = "Elevator Safety: DISABLED", Duration = 2})
            end)
            Notify({Title = "System", Content = "Elevator Safety: ACTIVE", Duration = 2})
        end
    end
})

FarmImpSection:Toggle({
    Title = "🔒 Safe Zone Logic",
    Default = true,
    Callback = function(value)
        StateManager.set("safeZoneLogic", value)
        Notify({Title = "Farm", Content = value and "Safe Zone Logic ON" or "Safe Zone Logic OFF", Duration = 2})
    end
})

FarmImpSection:Toggle({
    Title = "♾️ No Limit Radius",
    Default = false,
    Callback = function(value)
        StateManager.set("noLimitRadius", value)
        Notify({Title = "Farm", Content = value and "Loot Radius UNLIMITED!" or "Loot Radius Normal", Duration = 2})
    end
})

FarmImpSection:Toggle({
    Title = "🎁 Auto Open GiftBox",
    Default = false,
    Callback = function(value)
        StateManager.set("autoOpenGiftBox", value)
        Notify({Title = "Farm", Content = value and "Auto GiftBox ON" or "Auto GiftBox OFF", Duration = 2})
    end
})



FarmImpSection:Slider({
    Title = "Interact Distance",
    Value = { Min = 10, Max = 100, Default = 25 },
    Callback = function(value)
        StateManager.set("interactDistance", value)
    end
})

-- ─────────────────────────────────────────────────────────────────
-- TAB: COMBAT
-- ─────────────────────────────────────────────────────────────────

local CombatTab = Window:Tab({ Title = "Combat", Icon = "sword", Prefix = Window.TabPrefix })

local CombatSection = CombatTab:Section({ Title = "COMBAT EXPLOITS" })

CombatSection:Toggle({
    Title = "Kill Aura (Melee)",
    Default = false,
    Callback = function(value)
        StateManager.set("killAura", value)
        Notify({
            Title = "Combat",
            Content = value and "Kill Aura ENABLED" or "Kill Aura DISABLED",
            Duration = 3
        })
    end
})

CombatSection:Toggle({
    Title = "⚡ Infinite Stamina",
    Default = false,
    Callback = function(value)
        StateManager.set("infiniteStamina", value)
        BuffExploits.toggleInfiniteStamina(value)
        Notify({
            Title = "Combat",
            Content = value and "Infinite Stamina ACTIVATED" or "Infinite Stamina DEACTIVATED",
            Duration = 3
        })
    end
})

CombatSection:Toggle({
    Title = "🧠 Anti-Drain (Block Monster Vision)",
    Desc = "Blocks 'SeeSomething' remote - Prevents sanity drain",
    Default = false,
    Callback = function(value)
        SanityProtection.setEnabled(value)
        local installed = SanityProtection.isInstalled()
        Notify({
            Title = "Sanity",
            Content = value 
                and (installed and "Anti-Drain ACTIVE (Hook Installed)" or "Anti-Drain ENABLED") 
                or "Anti-Drain DISABLED",
            Duration = 3
        })
    end
})

-- Advanced Stamina Section
local StaminaSection = CombatTab:Section({ Title = "ADVANCED STAMINA" })

StaminaSection:Toggle({
    Title = "⏹️ Block Stamina Sync",
    Desc = "Blocks 'SyncStaminaConsume' remote",
    Default = false,
    Callback = function(value)
        AdvancedStaminaExploits.setRemoteBlock(value)
        Notify({
            Title = "Stamina",
            Content = value and "Remote Block ACTIVE" or "Remote Block DISABLED",
            Duration = 2
        })
    end
})

StaminaSection:Toggle({
    Title = "0️⃣ Zero Drain (Memory)",
    Desc = "Sets drain rate to 0 via upvalue manipulation",
    Default = false,
    Callback = function(value)
        AdvancedStaminaExploits.setZeroDrain(value)
        Notify({
            Title = "Stamina",
            Content = value and "Zero Drain ACTIVE (Looping)" or "Zero Drain STOPPED",
            Duration = 2
        })
    end
})

StaminaSection:Toggle({
    Title = "❄️ Freeze Stamina Logic",
    Desc = "Disables PreRender loop entirely",
    Default = false,
    Callback = function(value)
        local count = AdvancedStaminaExploits.setFreezeLoop(value)
        Notify({
            Title = "Stamina",
            Content = value 
                and string.format("Loop FROZEN (%d connections)", count) 
                or "Loop RESUMED",
            Duration = 2
        })
    end
})

-- Speed Section
local SpeedSection = CombatTab:Section({ Title = "SPEED & MOVEMENT" })

SpeedSection:Toggle({
    Title = "⚡ Speed Boost (Buff Method)",
    Default = false,
    Callback = function(value)
        BuffExploits.toggleSpeedBoost(value)
        Notify({
            Title = "Speed",
            Content = value and "Speed Boost ACTIVE" or "Speed Boost DISABLED",
            Duration = 3
        })
    end
})

SpeedSection:Toggle({
    Title = "Use Tween (Smooth Movement)",
    Default = true,
    Callback = function(value)
        StateManager.set("useTween", value)
    end
})

-- ─────────────────────────────────────────────────────────────────
-- TAB: DUNGEON
-- ─────────────────────────────────────────────────────────────────

local DungeonTab = Window:Tab({ Title = "Dungeon", Icon = "map", Prefix = Window.TabPrefix })


-- Auto Progress Section
local AutoDungeonSection = DungeonTab:Section({ Title = "AUTO PROGRESSION" })

AutoDungeonSection:Toggle({
    Title = "Enable Auto Dungeon",
    Desc = "Master switch for Auto Vote features",
    Default = false,
    Callback = function(val)
        warn("[DEBUG] AutoDungeon Toggle Callback: val =", val)
        StateManager.set("autoDungeon", val)
        warn("[DEBUG] AutoDungeon State after set:", StateManager.get("autoDungeon"))
    end
})

AutoDungeonSection:Toggle({
    Title = "Auto Go Deep (Continue)",
    Desc = "Automatically votes to continue when floor is cleared",
    Default = false,
    Callback = function(val)
        StateManager.set("autoGoDeep", val)
    end
})

AutoDungeonSection:Toggle({
    Title = "Auto Evacuate (Retreat)",
    Desc = "Automatically votes to retreat at Max Floor",
    Default = false,
    Callback = function(val)
        StateManager.set("autoEvacuate", val)
    end
})

AutoDungeonSection:Slider({
    Title = "🚨 Evacuation Floor",
    Desc = "Auto-evacuate when reaching this floor",
    Value = {
        Min = 1,
        Max = 35,
        Default = 35
    },
    Callback = function(val)
        StateManager.set("autoEvacuateFloor", val)
    end
})


local ElevatorSection = DungeonTab:Section({ Title = "ELEVATOR EXPLOITS" })

ElevatorSection:Toggle({
    Title = "Always In Elevator (Spoof)",
    Desc = "Tricks server thinking you are in elevator",
    Default = false,
    Callback = function(value)
        StateManager.set("alwaysInElevator", value)
        Notify({
            Title = "Dungeon",
            Content = value and "Elevator Spoof ACTIVE" or "Elevator Spoof DISABLED",
            Duration = 3
        })
    end
})

ElevatorSection:Toggle({
    Title = "🧠 Smart Elevator (Auto-Pause)",
    Desc = "Pauses spoof when near elevator for proper banking",
    Default = false,
    Callback = function(value)
        StateManager.set("smartElevatorSpoof", value)
        Notify({
            Title = "Smart Elevator",
            Content = value 
                and "Auto-pause ENABLED (Will pause near elevator)" 
                or "Auto-pause DISABLED (Constant spoof)",
            Duration = 3
        })
    end
})

ElevatorSection:Slider({
    Title = "Pause Distance (studs)",
    Desc = "Distance from elevator to pause spoof",
    Value = { Min = 5, Max = 30, Default = 15 },
    Callback = function(value)
        StateManager.set("elevatorPauseDistance", value)
    end
})

ElevatorSection:Toggle({
    Title = "God Mode Elevator (Stay at Elevator)",
    Default = false,
    Callback = function(value)
        StateManager.set("godModeElevator", value)
    end
})

ElevatorSection:Slider({
    Title = "🛗 Safety Floor Limit",
    Desc = "Max floor for elevator safety features",
    Value = { Min = 1, Max = 50, Default = 30 },
    Callback = function(value)
        StateManager.set("maxFloorTarget", value)
    end
})

ElevatorSection:Button({
    Title = "🛗 Teleport to Elevator",
    Callback = function()
        MovementEngine.teleport(CFrame.new(CONSTANTS.ELEVATOR_POS) * CFrame.new(0, 5, 0))
        Notify({Title = "Teleport", Content = "Teleported to Elevator", Duration = 3})
    end
})

-- Actions Section
local ActionsSection = DungeonTab:Section({ Title = "QUICK ACTIONS" })

ActionsSection:Button({
    Title = "💵 Sell All Items",
    Callback = function()
        InventoryManager.sellAll()
        Notify({Title = "Inventory", Content = "Sold all items!", Duration = 3})
    end
})

ActionsSection:Button({
    Title = "🔄 Clear Processed Items Cache",
    Callback = function()
        AutoFarmSystem.clearProcessed()
        Notify({Title = "Farm", Content = "Processed cache cleared", Duration = 3})
    end
})

ActionsSection:Button({
    Title = "🚪 Instant Evacuate",
    Callback = function()
        local success, dist = DungeonExploits.instantEvacuate()
        if success then
            Notify({Title = "Dungeon", Content = string.format("Evacuated from %dm away!", math.floor(dist or 0)), Duration = 3})
        else
            Notify({Title = "Error", Content = "No exit found", Duration = 3})
        end
    end
})

ActionsSection:Button({
    Title = "📦 Drop All Items (Remote)",
    Callback = function()
        DungeonExploits.dropAllItems()
        Notify({Title = "Dungeon", Content = "Dropped all items", Duration = 3})
    end
})

ActionsSection:Button({
    Title = "🏦 Force Bank (Instant)",
    Callback = function()
        DungeonExploits.forceBank()
        Notify({Title = "Banking", Content = "Forced inventory deposit!", Duration = 2})
    end
})

ActionsSection:Toggle({
    Title = "🔄 Auto-Bank Loop",
    Desc = "Spams 'PlayerEnterCollectPart' - Forces deposit ANYWHERE",
    Default = false,
    Callback = function(value)
        DungeonExploits.setBankingLoop(value)
        Notify({
            Title = "Banking", 
            Content = value and "Auto-Bank ENABLED (Every 2s)" or "Auto-Bank DISABLED", 
            Duration = 3
        })
    end
})

ActionsSection:Toggle({
    Title = "🧲 Vacuum Loot (Nearby)",
    Desc = "Claims all items in range - Safe remote spam",
    Default = false,
    Callback = function(value)
        StateManager.set("vacuumLoot", value)
        if value then
            ConnectionPool.spawn(function()
                while StateManager.get("vacuumLoot") and StateManager.get("alive") do
                    pcall(function()
                        local elevatorPos = AutoFarmSystem.getElevatorPosition()
                        local gs = workspace:FindFirstChild("GameSystem")
                        local loots = gs and gs:FindFirstChild("Loots")

                        local lootFolder = loots and loots:FindFirstChild("World")
                        
                        if lootFolder then
                            for _, item in ipairs(lootFolder:GetChildren()) do
                                if not StateManager.get("vacuumLoot") then break end
                                if item:GetAttribute("en") ~= false then
                                    -- Ignore items near elevator (Banking zone)
                                    local pos = EntityDetector.getPosition(item)
                                    local distToElev = (pos and elevatorPos) and (pos - elevatorPos).Magnitude or 9999
                                    
                                    -- FIX: Use CONSTANTS.THRESHOLDS for vacuum safe radius
                                    if distToElev > CONSTANTS.THRESHOLDS.VACUUM_SAFE_RADIUS then
                                        RemoteHandler.fireFast("Interactable", item)
                                        -- Throttling to prevent instant disconnection
                                        task.wait(CONSTANTS.LOOP_INTERVALS.FAST) 
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(0.5)
                end
            end)
        end
        Notify({
            Title = "Vacuum Loot",
            Content = value and "Vacuum ACTIVE - Claiming items..." or "Vacuum STOPPED",
            Duration = 2
        })
    end
})

-- Hotbar Section
ActionsSection:Toggle({
    Title = "📦 Auto Open Chests",
    Desc = "Spams 'Interactable' on Chests/Cabinets in range",
    Default = false,
    Callback = function(value)
        StateManager.set("autoOpenChests", value)
        if value then
            ConnectionPool.spawn(function()
                while StateManager.get("autoOpenChests") and StateManager.get("alive") do
                    pcall(function()
                        local gs = workspace:FindFirstChild("GameSystem")
                        local chestFolder = gs and gs:FindFirstChild("InteractiveItem")
                        
                        if chestFolder then
                            for _, chest in ipairs(chestFolder:GetChildren()) do
                                if not StateManager.get("autoOpenChests") then break end
                                if chest:GetAttribute("Open") == false then
                                    RemoteHandler.fireFast("Interactable", chest)
                                    -- Throttling to prevent instant disconnection
                                    task.wait(CONSTANTS.LOOP_INTERVALS.FAST)
                                end
                            end
                        end
                    end)
                    task.wait(1)
                end
            end)
        end
        Notify({
            Title = "Auto Chests",
            Content = value and "Auto-Open Chests ENABLED" or "Auto-Open Chests DISABLED",
            Duration = 2
        })
    end
})

-- Hotbar Section
local HotbarSection = DungeonTab:Section({ Title = "HOTBAR CONTROL" })

HotbarSection:Button({
    Title = "1️⃣ Switch Slot 1",
    Callback = function()
        DungeonExploits.switchSlot(1)
    end
})

HotbarSection:Button({
    Title = "2️⃣ Switch Slot 2",
    Callback = function()
        DungeonExploits.switchSlot(2)
    end
})

HotbarSection:Button({
    Title = "⚡ Use Tool (Remote)",
    Callback = function()
        DungeonExploits.useTool()
        Notify({Title = "Tool", Content = "Tool used via remote", Duration = 2})
    end
})

HotbarSection:Toggle({
    Title = "Auto Tool Spam",
    Default = false,
    Callback = function(value)
        StateManager.set("autoToolSpam", value)
        Notify({Title = "Exploit", Content = value and "Auto Tool Spam ON" or "Auto Tool Spam OFF", Duration = 2})
    end
})

HotbarSection:Toggle({
    Title = "Remote Drop Mode",
    Default = false,
    Callback = function(value)
        StateManager.set("remoteDropMode", value)
        Notify({Title = "Farm", Content = value and "Remote Drop Mode ON" or "Remote Drop Mode OFF", Duration = 2})
    end
})

-- HUD Section
local HUDSection = DungeonTab:Section({ Title = "DUNGEON HUD" })

HUDSection:Toggle({
    Title = "🖥️ Show Internal HUD",
    Default = false,
    Callback = function(value)
        StateManager.set("showInternalHUD", value)
        if value then
            InternalHUD.create()
        else
            InternalHUD.destroy()
        end
        Notify({Title = "HUD", Content = value and "Internal HUD ON" or "Internal HUD OFF", Duration = 2})
    end
})

HUDSection:Toggle({
    Title = "Safe Evacuate (Auto)",
    Default = false,
    Callback = function(value)
        StateManager.set("safeEvacuate", value)
        Notify({Title = "Countdown", Content = value and "Safe Evacuate ON" or "Safe Evacuate OFF", Duration = 2})
    end
})

HUDSection:Slider({
    Title = "Evacuate Timer (sec)",
    Value = { Min = 1, Max = 30, Default = 5 },
    Callback = function(value)
        StateManager.set("safeEvacTime", value)
    end
})

-- ─────────────────────────────────────────────────────────────────
-- TAB: VISUALS
-- ─────────────────────────────────────────────────────────────────

local VisualsTab = Window:Tab({ Title = "Visuals", Icon = "eye", Prefix = Window.TabPrefix })

local ESPSection = VisualsTab:Section({ Title = "ESP" })

ESPSection:Toggle({
    Title = "Monster ESP",
    Default = false,
    Callback = function(value)
        StateManager.set("espMonsters", value)
    end
})

ESPSection:Toggle({
    Title = "Loot ESP",
    Default = false,
    Callback = function(value)
        StateManager.set("espLoot", value)
    end
})

ESPSection:Toggle({
    Title = "Container ESP",
    Default = false,
    Callback = function(value)
        StateManager.set("espContainers", value)
    end
})

ESPSection:Toggle({
    Title = "NPC ESP",
    Default = false,
    Callback = function(value)
        StateManager.set("espNPCs", value)
    end
})

ESPSection:Toggle({
    Title = "Player ESP",
    Default = false,
    Callback = function(value)
        StateManager.set("espPlayers", value)
    end
})

ESPSection:Toggle({
    Title = "Ghost ESP",
    Default = false,
    Callback = function(value)
        StateManager.set("espGhosts", value)
    end
})

ESPSection:Toggle({
    Title = "Unlimited Distance",
    Default = false,
    Callback = function(value)
        StateManager.set("espNoLimit", value)
    end
})

ESPSection:Toggle({
    Title = "Hide Opened Containers",
    Default = false,
    Callback = function(value)
        StateManager.set("espHideOpened", value)
    end
})

ESPSection:Toggle({
    Title = "Hide Elevator Items",
    Default = false,
    Callback = function(value)
        StateManager.set("espHideElevator", value)
    end
})

ESPSection:Toggle({
    Title = "🟢 Highlight Elevator",
    Default = false,
    Callback = function(value)
        StateManager.set("highlightElevator", value)
        ElevatorHighlight.toggle(value)
        Notify({
            Title = "ESP",
            Content = value and "Elevator Highlight ON" or "Elevator Highlight OFF",
            Duration = 2
        })
    end
})

-- Monster Tracker Section
local TrackerSection = VisualsTab:Section({ Title = "MONSTER TRACKER" })

TrackerSection:Toggle({
    Title = "⚠️ Monster Tracker Alert",
    Default = false,
    Callback = function(value)
        StateManager.set("monsterTracker", value)
        if value then
            MonsterTrackerAlert.create()
        else
            MonsterTrackerAlert.hide()
        end
        Notify({
            Title = "Tracker",
            Content = value and "Monster Tracker ENABLED" or "Monster Tracker DISABLED",
            Duration = 2
        })
    end
})

TrackerSection:Slider({
    Title = "Tracker Distance",
    Value = { Min = 20, Max = 100, Default = 50 },
    Callback = function(value)
        StateManager.set("trackerDistance", value)
    end
})

-- Lighting Section
local LightingSection = VisualsTab:Section({ Title = "LIGHTING" })

LightingSection:Toggle({
    Title = "💡 Fullbright",
    Default = false,
    Callback = function(value)
        StateManager.set("fullbright", value)
        LightingControl.setFullbright(value)
        Notify({
            Title = "Visuals",
            Content = value and "Fullbright ENABLED" or "Fullbright DISABLED",
            Duration = 3
        })
    end
})

-- ─────────────────────────────────────────────────────────────────
-- TAB: MISC
-- ─────────────────────────────────────────────────────────────────

local MiscTab = Window:Tab({ Title = "Misc", Icon = "wrench", Prefix = Window.TabPrefix })

-- NPC Section
local NPCSection = MiscTab:Section({ Title = "👤 NPC TELEPORT" })

NPCSection:Button({
    Title = "📍 Teleport to Nearest NPC",
    Callback = function()
        local success, name, dist = NPCModule.teleportToNearest()
        if success then
            Notify({Title = "NPC", Content = string.format("Teleported to %s (%dm)", name or "NPC", math.floor(dist or 0)), Duration = 3})
        else
            Notify({Title = "Error", Content = "No NPCs found", Duration = 3})
        end
    end
})

NPCSection:Button({
    Title = "🎲 Teleport to Random NPC",
    Callback = function()
        local success, name = NPCModule.teleportToRandom()
        if success then
            Notify({Title = "NPC", Content = "Teleported to " .. (name or "NPC"), Duration = 3})
        else
            Notify({Title = "Error", Content = "No NPCs found", Duration = 3})
        end
    end
})

NPCSection:Button({
    Title = "📊 Show NPC Count",
    Callback = function()
        local npcs = NPCModule.getAll()
        if #npcs == 0 then
            Notify({Title = "NPC", Content = "No NPCs found!", Duration = 2})
        else
            local names = {}
            for i, npc in ipairs(npcs) do
                if i <= 5 then
                    table.insert(names, npc.Name)
                end
            end
            local preview = table.concat(names, ", ")
            if #npcs > 5 then preview = preview .. "..." end
            Notify({Title = "NPC", Content = string.format("Found %d NPCs: %s", #npcs, preview), Duration = 4})
        end
    end
})

-- Speed Section
local MiscSpeedSection = MiscTab:Section({ Title = "⚡ SPEED" })

MiscSpeedSection:Toggle({
    Title = "Speed Hack (Walk Speed)",
    Default = false,
    Callback = function(value)
        StateManager.set("speedHack", value)
        local humanoid = PlayerRefs.humanoid
        if humanoid then
            if value then
                humanoid.WalkSpeed = StateManager.get("walkSpeed")
            else
                humanoid.WalkSpeed = 16
            end
        end
        Notify({Title = "Speed", Content = value and "Speed Hack ON" or "Speed Hack OFF", Duration = 2})
    end
})

MiscSpeedSection:Slider({
    Title = "Walk Speed",
    Value = { Min = 16, Max = 200, Default = 16 },
    Callback = function(value)
        local numValue = tonumber(value) or 16
        StateManager.set("walkSpeed", numValue)
        
        -- Apply immediately if speed hack is enabled
        if StateManager.get("speedHack") then
            local char = game.Players.LocalPlayer.Character
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then
                hum.WalkSpeed = numValue
            end
        end
    end
})


-- ─────────────────────────────────────────────────────────────────
-- TAB: SETTINGS
-- ─────────────────────────────────────────────────────────────────

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "sliders-horizontal", Prefix = Window.TabPrefix })

local InfoSection = SettingsTab:Section({ Title = "INFORMATION" })

InfoSection:Paragraph({
    Title = "Version: " .. CONSTANTS.VERSION
})

InfoSection:Paragraph({
    Title = "Session: " .. string.sub(CONSTANTS.SESSION_ID, 1, 8) .. "..."
})

local StatsInfo = InfoSection:Paragraph({
    Title = "Rate Limiter: Active"
})

InfoSection:Button({
    Title = "🔄 Check Rate Limit Stats",
    Callback = function()
        local stats = RateLimiter.getStats()
        local count = 0
        for _ in pairs(stats) do count = count + 1 end
        Notify({
            Title = "Rate Limiter",
            Content = string.format("Tracking %d remotes", count),
            Duration = 3
        })
    end
})

-- Unload Section
local UnloadSection = SettingsTab:Section({ Title = "SCRIPT CONTROL" })

UnloadSection:Button({
    Title = "🛑 Unload Script",
    Callback = function()
        StateManager.set("alive", false)
        
        -- Cleanup
        ConnectionPool.disconnectAll()
        ESPSystem.cleanup()
        LightingControl.setFullbright(false)
        
        -- Disable exploits
        BuffExploits.toggleInfiniteStamina(false)
        BuffExploits.toggleSpeedBoost(false)
        
        Notify({Title = "Script", Content = "Unloading...", Duration = 2})
        task.wait(2)
        Window:Destroy()
    end
})

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 19: EVENT LOOPS
-- Main game loops
-- ═══════════════════════════════════════════════════════════════════

-- ESP Update Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(CONSTANTS.LOOP_INTERVALS.NORMAL)
        
        pcall(function()
            ESPSystem.scan()
            ESPSystem.update()
        end)
    end
end)

-- Elevator Spoof Loop (Server Trick)
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(0.2) -- Tick rate matching Deadly Delivery safety
        if StateManager.get("alwaysInElevator") or StateManager.get("autoDungeon") then
            -- Requirements: Player must actually exist
            local root = PlayerRefs.rootPart
            if root then
                -- Spoof being in Elevator area
                local TEvent = nil
                local success = pcall(function()
                   TEvent = require(ReplicatedStorage.Shared.Core.TEvent)
                end)
                
                if success and TEvent then
                     local elevatorPos = AutoFarmSystem.getElevatorPosition()
                     if elevatorPos then
                          -- Fire Remote: PlayerInElevator(isIn, position, timestamp)
                          pcall(function()
                              TEvent.FireRemote("PlayerInElevator", true, elevatorPos, TEvent.UnixTimeMillis())
                          end)
                     end
                end
            end
        end
    end
end)

-- Auto Farm Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        local speed = StateManager.get("farmSpeed") or 1
        local interval = CONSTANTS.LOOP_INTERVALS.NORMAL / speed
        task.wait(interval)
        
        if not StateManager.get("farmActive") then continue end
        
        pcall(function()
            -- Safe mode check
            if StateManager.get("safeMode") then
                local monsterNearby = AutoFarmSystem.isMonsterNearby(CONSTANTS.THRESHOLDS.MONSTER_SAFE_RETREAT)
                if monsterNearby then
                    safeSetStatus("Status: <font color='#FF0000'>⚠️ Retreating (Monster)</font>")
                    -- Retreat to Elevator
                    MovementEngine.teleport(CFrame.new(AutoFarmSystem.getElevatorPosition()) * CFrame.new(0, 5, 0))
                    task.wait(3) -- Stay safe at elevator for a moment
                    return
                end
            end
            
            -- Anti-stuck check
            if StateManager.get("antiStuck") then
                MovementEngine.checkStuck()
            end
            
            -- Auto-sell when full
            if InventoryManager.isFull() then
                safeSetStatus("Status: <font color='#8A2BE2'>Banking Items...</font>")
                
                -- Teleport to Elevator (Banking Zone)
                MovementEngine.teleport(CFrame.new(AutoFarmSystem.getElevatorPosition()) * CFrame.new(0, 3, 0))
                task.wait(1.5)
                
                -- Drop All Items (Slots 1-4)
                -- Drop Actual Items Only
                local filledSlots = InventoryManager.getFilledSlots()
                
                -- SANITY CHECK: Double check if we actually have items
                if #filledSlots > 0 then
                    safeSetStatus("Status: <font color='#8A2BE2'>Banking " .. #filledSlots .. " items...</font>")
                    for _, slot in ipairs(filledSlots) do
                        RemoteHandler.fireFast("Hotbar_Switch", slot)
                        task.wait(0.15)
                        RemoteHandler.fireFast("Hotbar_Drop", slot)
                        task.wait(0.2)
                    end
                else
                     -- False Positive from 'isFull' (likely 'HandsFull' UI bug)
                     -- Do NOT force drop. Just log and return to farming.
                     warn("[AutoFarm] Banking triggered but inventory empty. Ignoring.")
                     safeSetStatus("Status: <font color='#FFA500'>Inventory Empty (False Alarm)</font>")
                     task.wait(1)
                end
                
                safeSetStatus("Status: <font color='#00FF00'>Banking Complete</font>")
                task.wait(0.5)
                return
            end
            
            -- Get and interact with targets
            local target = AutoFarmSystem.getCurrentTarget()
            
            -- Validate current target
            if target and (not target.object or not target.object.Parent or AutoFarmSystem.isProcessed(target.object)) then
                target = nil
                AutoFarmSystem.setCurrentTarget(nil)
            end
            
            -- FIX: Invalidate NPC target if farmNPCs toggle is now OFF
            -- This prevents cached NPC targets from persisting when user disables the toggle
            if target and target.type == "NPC" and not StateManager.get("farmNPCs") then
                target = nil
                AutoFarmSystem.setCurrentTarget(nil)
            end
            
            -- Resets Idle Timer when working
            -- REMOVED: StateManager.set("autoDungeonIdleTime", 0) from here
            
            -- If no valid cached target, scan for new ones
            if not target then
                local targets = AutoFarmSystem.getTargets()
                if #targets > 0 then
                    target = targets[1]
                    AutoFarmSystem.setCurrentTarget(target)
                end
            end
            
            if target then
                -- Resets Idle Timer when working (CORRECT PLACE)
                StateManager.set("autoDungeonIdleTime", 0)

                safeSetStatus(string.format(
                    "Status: <font color='#00FF00'>Farming %s</font>", 
                    target.name
                ))
                AutoFarmSystem.interact(target)
            else
                safeSetStatus("Status: <font color='#892be2'>Searching... (Safe)</font>")
                MovementEngine.resetStuck()
                
                -- SAFETY: Retreat to Elevator while waiting for spawns
                local elevatorPos = AutoFarmSystem.getElevatorPosition()
                if elevatorPos then
                    local root = PlayerRefs.rootPart
                    if root and (root.Position - elevatorPos).Magnitude > 10 then
                        MovementEngine.teleport(CFrame.new(elevatorPos) * CFrame.new(0, 3, 0))
                    end
                end
                
                -- AUTO DUNGEON: Vote Logic
                local idleStart = StateManager.get("autoDungeonIdleTime")
                local elapsed = 0
                if idleStart > 0 then
                    elapsed = os.clock() - idleStart
                end
                
                -- Update Status with Countdown if Auto Dungeon is On
                if StateManager.get("autoDungeon") then
                     safeSetStatus(string.format("Status: <font color='#892be2'>Searching... (%.1fs / 5.0s)</font>", elapsed))
                else
                     safeSetStatus("Status: <font color='#892be2'>Searching... (Safe)</font>")
                end


                if StateManager.get("autoDungeon") then
                    if idleStart == 0 then
                        StateManager.set("autoDungeonIdleTime", os.clock())
                        StateManager.set("autoDungeonHasVoted", false)  -- KILO Fix: Reset on new idle
                    elseif elapsed > CONSTANTS.THRESHOLDS.VOTE_IDLE_THRESHOLD and not StateManager.get("autoDungeonHasVoted") then
                        -- Check for Vote Cooldown (30s - increased from 10s)
                        local lastVote = StateManager.get("lastVoteTime") or 0
                        if (os.clock() - lastVote) > CONSTANTS.THRESHOLDS.VOTE_COOLDOWN then
                            -- Get Floor Data
                            local currentFloor = 0
                            pcall(function()
                                local ValueMod = require(ReplicatedStorage.Shared.Core.Value)
                                if ValueMod and ValueMod.DungeonStats and ValueMod.DungeonStats._value then
                                    currentFloor = ValueMod.DungeonStats._value.level or 0
                                end
                            end)
                            
                            local targetFloor = StateManager.get("autoEvacuateFloor")
                            
                            -- DECISION: Evacuate or Continue?
                            if StateManager.get("autoEvacuate") and currentFloor >= targetFloor then
                                safeSetStatus("Status: <font color='#FF0000'>AUTO DUNGEON: Evacuating...</font>")
                                RemoteHandler.fire("SubmitVote", "retreat")
                                Notify({Title = "Auto Dungeon", Content = "Goal Reached! Evacuating...", Duration = 5})
                                StateManager.set("lastVoteTime", os.clock())
                                StateManager.set("autoDungeonHasVoted", true)  -- KILO Fix: Mark as voted
                            elseif StateManager.get("autoGoDeep") then
                                safeSetStatus("Status: <font color='#00FF00'>AUTO DUNGEON: Going Deep...</font>")
                                RemoteHandler.fire("SubmitVote", "continue")
                                StateManager.set("lastVoteTime", os.clock())
                                StateManager.set("autoDungeonHasVoted", true)  -- KILO Fix: Mark as voted
                            end
                        end
                    end
                end
            end
        end)
    end
end)

-- Kill Aura Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(CONSTANTS.LOOP_INTERVALS.FAST * 2)
        
        if not StateManager.get("killAura") then continue end
        
        pcall(function()
            local root = PlayerRefs.rootPart
            if not root then return end
            
            local gs = workspace:FindFirstChild("GameSystem")
            if not gs then return end
            
            local monsters = gs:FindFirstChild("Monsters")
            if not monsters then return end
            
            for _, monster in pairs(monsters:GetChildren()) do
                local isMonster = EntityDetector.isMonster(monster)
                if isMonster then
                    local pos = EntityDetector.getPosition(monster)
                    if pos and (root.Position - pos).Magnitude < CONSTANTS.THRESHOLDS.KILL_AURA_RANGE then
                        RemoteHandler.fire("Interactable", monster)
                    end
                end
            end
        end)
    end
end)

-- Always In Elevator Loop (with Smart Mode support)
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(CONSTANTS.LOOP_INTERVALS.FAST)
        
        if StateManager.get("alwaysInElevator") then
            local shouldSpoof = true
            
            -- Smart Mode: Pause when near actual elevator for proper banking
            if StateManager.get("smartElevatorSpoof") then
                local root = PlayerRefs.rootPart
                if root then
                    local elevatorPos = CONSTANTS.ELEVATOR_POS
                    local distance = (root.Position - elevatorPos).Magnitude
                    local pauseDistance = StateManager.get("elevatorPauseDistance") or 15
                    
                    if distance < pauseDistance then
                        shouldSpoof = false -- Let normal elevator logic handle banking
                    end
                end
            end
            
            if shouldSpoof then
                ElevatorProtection.spoof()
            end
        end
    end
end)

-- God Mode Elevator Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(CONSTANTS.LOOP_INTERVALS.FAST)
        
        if StateManager.get("godModeElevator") then
            local root = PlayerRefs.rootPart
            if root then
                root.CFrame = CFrame.new(CONSTANTS.ELEVATOR_POS) * CFrame.new(0, 3, 0)
            end
        end
    end
end)

-- Stats Update Loop (integrates DungeonStats for realtime data)
ConnectionPool.spawn(function()
    -- Initialize DungeonStats connection
    DungeonStats.init()
    
    while StateManager.get("alive") do
        task.wait(CONSTANTS.LOOP_INTERVALS.SLOW)
        
        pcall(function()
            local items = StateManager.get("itemsCollected")
            local elapsed = os.clock() - StateManager.get("startTime")
            local ipm = items / math.max(elapsed / 60, 1)
            
            -- Get floor from DungeonStats (realtime)
            local dungeonData = DungeonStats.get()
            local floor = dungeonData.level or StateManager.get("currentFloor")
            StateManager.set("currentFloor", floor)
            
            safeSetStats(string.format(
                "Items: %d | IPM: %.1f | Floor: %d",
                items, ipm, floor
            ))
            
            if not StateManager.get("farmActive") then
                safeSetStatus("Status: <font color='#FFD700'>Idle</font>")
            end
            
            -- Update Internal HUD if visible
            if StateManager.get("showInternalHUD") then
                local countdown = dungeonData.countdown.time
                InternalHUD.update(
                    countdown,
                    floor,
                    dungeonData.state,
                    dungeonData.bossActive
                )
            end
        end)
    end
end)

-- Monster Tracker Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(CONSTANTS.LOOP_INTERVALS.NORMAL)
        
        if not StateManager.get("monsterTracker") then continue end
        
        pcall(function()
            local trackerDist = StateManager.get("trackerDistance")
            local isNear, monster = AutoFarmSystem.isMonsterNearby(trackerDist)
            
            if isNear then
                local root = PlayerRefs.rootPart
                local pos = monster and EntityDetector.getPosition(monster)
                local dist = (root and pos) and (root.Position - pos).Magnitude or 0
                local name = monster and EntityDetector.getEntityName(monster) or "Monster"
                MonsterTrackerAlert.show(name, dist)
            else
                MonsterTrackerAlert.hide()
            end
        end)
    end
end)

-- Anti-AFK Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(60) -- Every minute
        
        if StateManager.get("antiAFK") then
            AntiAFKSystem.pulse()
        end
    end
end)

-- Auto Tool Spam Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(0.15)
        
        if StateManager.get("autoToolSpam") then
            DungeonExploits.useTool()
        end
    end
end)

-- Auto GiftBox Loop
ConnectionPool.spawn(function()
    while StateManager.get("alive") do
        task.wait(1.5) -- Check every 1.5s
        
        if StateManager.get("autoOpenGiftBox") then
            local success, err = pcall(function()
                local player = Players.LocalPlayer
                local gui = player and player:FindFirstChild("PlayerGui")
                local main = gui and gui:FindFirstChild("Main")
                local home = main and main:FindFirstChild("HomePage")
                local bottom = home and home:FindFirstChild("Bottom")
                
                if not bottom then
                    warn("[AutoGiftBox] Bottom UI not found")
                    return
                end
                
                for _, slot in pairs(bottom:GetChildren()) do
                    if slot:IsA("Frame") then
                        local details = slot:FindFirstChild("ItemDetails")
                        local nameLabel = details and details:FindFirstChild("ItemName")
                        
                        if nameLabel then
                            -- FIXED: Case-insensitive, space-tolerant matching
                            local itemName = nameLabel.Text:lower():gsub("%s+", "")
                            
                            if itemName:find("giftbox") or itemName:find("gift_box") then
                                local slotNum = tonumber(slot.Name)
                                if slotNum then
                                    -- FIXED: Use fireFast for immediate response
                                    RemoteHandler.fireFast("Hotbar_Switch", slotNum)
                                    task.wait(0.3)
                                    
                                    -- KILO Fix: UseTool (ID 472) is correct remote, not Hotbar_Use
                                    RemoteHandler.fireFast("UseTool", slotNum)
                                    task.wait(1.0) -- Wait for open animation
                                    return -- Open one at a time
                                end
                            end
                        end
                    end
                end
            end)
            
            if not success then
                warn("[AutoGiftBox] Critical Error: " .. tostring(err))
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- § SECTION 25: INITIALIZATION COMPLETE
-- ═══════════════════════════════════════════════════════════════════

-- Add unload cleanup to include new modules
StateManager.subscribe("alive", function(value)
    if not value then
        MonsterTrackerAlert.destroy()
        InternalHUD.destroy()
        ElevatorHighlight.toggle(false)
    end
end)

-- FIX: Reset vote state on floor change to prevent stale voting (Logic Fix)
StateManager.subscribe("currentFloor", function(newFloor, oldFloor)
    if newFloor ~= oldFloor then
        StateManager.set("autoDungeonHasVoted", false, true)  -- Silent reset
        StateManager.set("autoDungeonIdleTime", 0, true)
    end
end)

Notify({
    Title = "Premium Core",
    Content = string.format("v%s loaded successfully | %d features", CONSTANTS.VERSION, 35),
    Duration = 5
})

-- Set window toggle key
Window.ToggleKey = StateManager.get("toggleKey") or Enum.KeyCode.RightShift
