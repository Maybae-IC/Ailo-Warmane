local ADDON_NAME, ADDON_TABLE = ...

local BZ = LibStub("LibBabble-Zone-3.0"):GetLookupTable()


ADDON_TABLE.Constants = {}
local TC = ADDON_TABLE.Constants

TC.Seasonal = {}
TC.Seasonal.ActiveHoliday = nil -- resets local variable
TC.Seasonal.Events = {
	LoveInTheAir = { 
		icon = "|TInterface\\Icons\\inv_valentinesboxofchocolates02:20|t", 
		texture_name = "Calendar_LoveInTheAir",
		dungeon_id = 288
	},
	Midsummer = { 
		icon = "|TInterface\\Icons\\inv_summerfest_fireflower:20|t", 
		texture_name = "Calendar_Midsummer",
		dungeon_id = 286
	},
	Brewfest = { 
		icon = "|TInterface\\Icons\\inv_holiday_brewfestbuff_01:20|t", 
		texture_name = "Calendar_Brewfest",
		dungeon_id = 287
	},
	HallowsEnd = { 
		icon = "|TInterface\\Icons\\Inv_misc_food_59:20|t", 
		texture_name = "Calendar_HallowsEnd",
		dungeon_id = 285
	},
    -- WinterVeil = { icon = "|TInterface\\Icons\\inv_holiday_christmas_present_01:20|t",
					-- texture_name = "Calendar_WinterVeil",
					-- quest_ids = { 6983, 7043 }, },
}

TC.RaidOrderLfgId = {
	BZ["Vault of Archavon"],
	BZ["The Ruby Sanctum"],
	BZ["Icecrown Citadel"],
	BZ["Trial of the Crusader"],
	BZ["Onyxia's Lair"],
	BZ["Ulduar"],
	BZ["Naxxramas"],
	BZ["The Obsidian Sanctum"],
	BZ["The Eye of Eternity"],
}




