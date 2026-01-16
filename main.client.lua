local RunService = game:GetService("RunService")
--[[

    WindUI Glassmorphism Example
    Blade Ball Style UI Demo
    
]]


local cloneref = (cloneref or clonereference or function(instance) return instance end)
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))


local WindUI

do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)
    
    if ok then
        WindUI = result
    else 
        if cloneref(game:GetService("RunService")):IsStudio() then
            WindUI = require(cloneref(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init")))
        else
            WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/gabuskyun02-lang/roblox-windui/refs/heads/main/dist/main.lua"))()
        end
    end
end


-- */  Window - Blade Ball Style  /* --
local Window = WindUI:CreateWindow({
    Title = "wings",
    Author = "Blade Ball",
    Folder = "bladeball",
    Icon = "feather",
    NewElements = true,
    Acrylic = true, -- Enable acrylic for toggle to work
    Size = UDim2.fromOffset(540, 400), -- Compact glassmorphism size
    
    HideSearchBar = false,
    
    OpenButton = {
        Title = "Open wings UI",
        CornerRadius = UDim.new(1,0),
        StrokeThickness = 3,
        Enabled = true,
        Draggable = true,
        Scale = 0.5,
        Color = ColorSequence.new(
            Color3.fromHex("#4a9eff"), 
            Color3.fromHex("#30ff6a")
        )
    },
    Topbar = {
        Height = 44,
        ButtonsType = "Mac",
    },
    User = {
        Enabled = true,
        Anonymous = false,
    }
})

-- */  Tags  /* --
Window:Tag({
    Title = "v" .. WindUI.Version,
    Icon = "github",
    Color = Color3.fromHex("#1c1c1c"),
    Border = true,
})


-- ================================================================
-- SIDEBAR SECTIONS (Nested Structure)
-- ================================================================

-- "GENERAL" Section in sidebar
local GeneralSection = Window:Section({
    Title = "General",
    Icon = "layers",
    Opened = true,
})

-- "MISCELLANEOUS" Section in sidebar  
local MiscSection = Window:Section({
    Title = "Miscellaneous",
    Icon = "settings",
    Opened = true,
})


-- ================================================================
-- TABS UNDER GENERAL SECTION
-- ================================================================

-- General Tab (default selected)
local GeneralTab = GeneralSection:Tab({
    Title = "General",
    Icon = "home",
    Border = true,
})

-- Automatization Tab
local AutoTab = GeneralSection:Tab({
    Title = "Automatization",
    Icon = "cpu",
    Border = true,
})

-- Player Tab
local PlayerTab = GeneralSection:Tab({
    Title = "Player",
    Icon = "user",
    Border = true,
})


-- ================================================================
-- TABS UNDER MISCELLANEOUS SECTION
-- ================================================================

local MiscTab = MiscSection:Tab({
    Title = "Miscellaneous",
    Icon = "box",
    Border = true,
})

local SettingsTab = MiscSection:Tab({
    Title = "Settings",
    Icon = "settings-2",
    Border = true,
})


-- ================================================================
-- GENERAL TAB CONTENT - TWO COLUMN CARD LAYOUT
-- ================================================================

-- Dropdown at top
GeneralTab:Dropdown({
    Title = "",
    Icon = "square",
    Values = { "None", "Option 1", "Option 2" },
    Default = "None",
})

GeneralTab:Space()

-- Two-column card layout using Group
local CardRow1 = GeneralTab:Group({})

-- Left Card: AUTO-PARRY
local AutoParryCard = CardRow1:Section({
    Title = "Auto-Parry",
})

AutoParryCard:Toggle({
    Title = "Enable Auto-Parry",
    Value = false,
})

AutoParryCard:Dropdown({
    Title = "Target Selection",
    Values = { "Closest to Player", "Random", "Furthest" },
    Default = "Closest to Player",
})

AutoParryCard:Dropdown({
    Title = "Parry Direction",
    Values = { "Straight", "Curved", "Random" },
    Default = "Straight",
})

AutoParryCard:Toggle({
    Title = "Allow prediction",
    Value = false,
})

AutoParryCard:Toggle({
    Title = "On-Parry Visuals",
    Value = true,
})

CardRow1:Space()

-- Right Card: AI MODE
local AIModeCard = CardRow1:Section({
    Title = "AI Mode",
})

AIModeCard:Toggle({
    Title = "Enable AI Mode",
    Value = false,
})

AIModeCard:Slider({
    Title = "Stay Distance",
    Value = { Min = 0, Max = 30, Default = 15 },
    Step = 1,
})

AIModeCard:Slider({
    Title = "Wander Amount",
    Value = { Min = 0, Max = 20, Default = 8 },
    Step = 1,
})

AIModeCard:Toggle({
    Title = "Dynamic Distance",
    Value = false,
})

AIModeCard:Toggle({
    Title = "Visualise Path",
    Value = false,
})

GeneralTab:Space()

-- Second row of cards
local CardRow2 = GeneralTab:Group({})

-- Left Card: AUTO-SPAM
local AutoSpamCard = CardRow2:Section({
    Title = "Auto-Spam",
})

AutoSpamCard:Toggle({
    Title = "Enable Manual Spam",
    Value = false,
})

AutoSpamCard:Keybind({
    Title = "Manual Spam",
    Value = "RightShift",
})

AutoSpamCard:Dropdown({
    Title = "Mode",
    Icon = "hand",
    Values = { "Hold", "Toggle", "Always" },
    Default = "Hold",
})

AutoSpamCard:Slider({
    Title = "Delay",
    Value = { Min = 50, Max = 500, Default = 100 },
    Step = 10,
})

CardRow2:Space()

-- Right Card: MISCELLANEOUS
local MiscCard = CardRow2:Section({
    Title = "Miscellaneous",
})

MiscCard:Toggle({
    Title = "Auto-Claim",
    Value = false,
})

MiscCard:Toggle({
    Title = "Auto Wheel Spin",
    Value = false,
})

MiscCard:Dropdown({
    Title = "Auto-Crate",
    Values = { "None", "Common", "Rare", "Epic", "Legendary" },
    Default = "None",
})

MiscCard:Button({
    Title = "Claim all Codes",
    Icon = "",
    Justify = "Center",
    Callback = function()
        WindUI:Notify({
            Title = "Codes",
            Content = "Claiming all codes...",
            Duration = 3,
        })
    end
})


-- ================================================================
-- AUTOMATIZATION TAB CONTENT
-- ================================================================

local AutoSection1 = AutoTab:Section({
    Title = "Auto Farm",
})

AutoSection1:Toggle({
    Title = "Enable Auto Farm",
    Value = false,
})

AutoSection1:Slider({
    Title = "Farm Speed",
    Value = { Min = 1, Max = 10, Default = 5 },
    Step = 1,
})

AutoSection1:Toggle({
    Title = "Auto Collect Items",
    Value = true,
})

AutoTab:Space()

local AutoSection2 = AutoTab:Section({
    Title = "Auto Quest",
})

AutoSection2:Toggle({
    Title = "Enable Auto Quest",
    Value = false,
})

AutoSection2:Dropdown({
    Title = "Quest Type",
    Values = { "Daily", "Weekly", "All" },
    Default = "Daily",
})


-- ================================================================
-- PLAYER TAB CONTENT
-- ================================================================

local PlayerSection1 = PlayerTab:Section({
    Title = "Movement",
})

PlayerSection1:Slider({
    Title = "Walk Speed",
    Value = { Min = 16, Max = 100, Default = 16 },
    Step = 1,
})

PlayerSection1:Slider({
    Title = "Jump Power",
    Value = { Min = 50, Max = 200, Default = 50 },
    Step = 5,
})

PlayerSection1:Toggle({
    Title = "Infinite Jump",
    Value = false,
})

PlayerTab:Space()

local PlayerSection2 = PlayerTab:Section({
    Title = "Visuals",
})

PlayerSection2:Toggle({
    Title = "ESP",
    Value = false,
})

PlayerSection2:Toggle({
    Title = "Tracers",
    Value = false,
})

PlayerSection2:Colorpicker({
    Title = "ESP Color",
    Default = Color3.fromHex("#4a9eff"),
})


-- ================================================================
-- MISCELLANEOUS TAB CONTENT
-- ================================================================

local MiscSection1 = MiscTab:Section({
    Title = "Utilities",
})

MiscSection1:Button({
    Title = "Rejoin Server",
    Icon = "refresh-ccw",
    Callback = function()
        WindUI:Notify({
            Title = "Rejoining",
            Content = "Rejoining server...",
            Duration = 2,
        })
    end
})

MiscSection1:Button({
    Title = "Server Hop",
    Icon = "shuffle",
    Callback = function()
        WindUI:Notify({
            Title = "Server Hop",
            Content = "Finding new server...",
            Duration = 2,
        })
    end
})

MiscSection1:Button({
    Title = "Copy Server Link",
    Icon = "link",
    Callback = function()
        WindUI:Notify({
            Title = "Copied",
            Content = "Server link copied to clipboard!",
            Duration = 2,
        })
    end
})


-- ================================================================
-- SETTINGS TAB CONTENT
-- ================================================================

local SettingsSection1 = SettingsTab:Section({
    Title = "UI Settings",
})

SettingsSection1:Dropdown({
    Title = "Theme",
    Values = { "Dark", "Light", "Rose", "Indigo", "Sky" },
    Default = "Dark",
    Callback = function(theme)
        WindUI:SetTheme(theme)
    end
})

SettingsSection1:Toggle({
    Title = "Acrylic Effect",
    Value = false,
    Callback = function(value)
        WindUI:ToggleAcrylic(value)
    end
})

SettingsSection1:Keybind({
    Title = "Toggle UI",
    Value = "RightControl",
})

SettingsTab:Space()

local SettingsSection2 = SettingsTab:Section({
    Title = "About",
})

SettingsSection2:Paragraph({
    Title = "WindUI",
    Content = "Glassmorphism UI Library for Roblox\nVersion: " .. WindUI.Version,
})

SettingsSection2:Button({
    Title = "Destroy Window",
    Icon = "x",
    Color = Color3.fromHex("#ef4444"),
    Justify = "Center",
    Callback = function()
        Window:Destroy()
    end
})


-- Select General tab by default
GeneralTab:Select()
