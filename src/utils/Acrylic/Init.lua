-- Credits: Fluent - Dawid

local cloneref = (cloneref or clonereference or function(instance) return instance end)


local Acrylic = {
	AcrylicBlur = require("./Blur"),
	--CreateAcrylic = require("./"),
	AcrylicPaint = require("./Paint"),
}

function Acrylic.init()
	-- DepthOfFieldEffect DISABLED - was affecting game world and player nametags
	-- Only Glass Part and UI transparency are used for glassmorphism effect
	
	-- local baseEffect = Instance.new("DepthOfFieldEffect")
	-- baseEffect.FarIntensity = 0
	-- baseEffect.InFocusRadius = 10
	-- baseEffect.NearIntensity = 0.3

	local depthOfFieldDefaults = {}

	function Acrylic.Enable()
		-- Disabled: no longer using DepthOfField
	end

	function Acrylic.Disable()
		-- Disabled: no longer using DepthOfField
	end

	local function registerDefaults()
		local function register(object)
			if object:IsA("DepthOfFieldEffect") then
				depthOfFieldDefaults[object] = { enabled = object.Enabled }
			end
		end

		for _, child in pairs(cloneref(game:GetService("Lighting")):GetChildren()) do
			register(child)
		end

		if cloneref(game:GetService("Workspace")).CurrentCamera then
			for _, child in pairs(cloneref(game:GetService("Workspace")).CurrentCamera:GetChildren()) do
				register(child)
			end
		end
	end

	registerDefaults()
end

return Acrylic
