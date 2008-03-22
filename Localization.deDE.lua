--Localization.deDE.lua
if GetLocale() ~= "deDE" then return end

LootTrackerLocals = setmetatable({
	["Sets"] = "Sätze",
}, {__index = LootTrackerLocals})
