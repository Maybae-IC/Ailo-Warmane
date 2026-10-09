local ADDON_NAME, ADDON_TABLE = ...

-- locals, helperfunctions 
local string_gsub, string_format, tinsert = string.gsub, string.format, table.insert
local wipe = wipe

local questWeeklyFlag = false
local reset_wday = 4 -- 4:Wednesday

-- LibDataBroker
local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
local LDBIcon = ldb and LibStub("LibDBIcon-1.0",true)
local LibQTip = LibStub('LibQTip-1.0')
local Ailo = LibStub("AceAddon-3.0"):NewAddon("Ailo", "AceConsole-3.0", "AceEvent-3.0") --, "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Ailo", false)
local DB_VERSION = 3
local currentChar, currentRealm, currentCharRealm, currentMaxLevel, currentCharLevel

local AceTimer = LibStub("AceTimer-3.0")
AceTimer:Embed(Ailo)

local TC = ADDON_TABLE.Constants

-- Sorting
local sortRealms = {}
local sortRealmsPlayer = {}

local function setColor(info, r, g, b, a)
    Ailo.db.profile[info[#info]] = { r = r, g = g, b = b, a = a }
end

local function getColor(info)
    return Ailo.db.profile[info[#info]].r, Ailo.db.profile[info[#info]].g, Ailo.db.profile[info[#info]].b, Ailo.db.profile[info[#info]].a
end

local defaults = {
    profile = {
        savedraid = { r=1, g=0, b=0, a=1 },
        freeraid  = { r=0, g=1, b=0, a=1 },
        hc = "hc",
        nhc = "nhc",
		dynamic = "dyn",
		dailySH = "2",
		event = "x",
		heroic = "x",
		weeklyR = "5",
		quest = "x",
		dailyP = "25",
		pvpD = "x",
		weeklyP = "10",
		pvpW = "x",		
        show5Man = false,
        showAllChars = true,
        showCharacterRealm = false,
        showDailyHeroic = true,
        showOnlyWrathRaids = false,
        showMessages = true,
        showRealmHeaderLines = false,
        showWeeklyRaid = true,
        showWGVictory = false,
        showDailyPVP = false,
        showSeasonal = true,
        useClassColors = true,
        useCustomClassColors = true,
        instanceAbbr = {},
        minimapIcon = {
            hide = false,
            minimapPos = 220,
            radius = 80,
        },
    },
    global = {
        chars = {},
        charClass = {},
        raids = {},
        nextPurge = 0,
        version = 0,
    },
}

local Seasonal = TC.Seasonal

function Ailo:OnInitialize()
	currentMaxLevel = 80 -- we can get ids from lvl 50 onwards (ZG, AQ)
	currentCharLevel = UnitLevel("player")
    currentChar = UnitName("player")
    currentRealm = GetRealmName()
    currentCharRealm = currentChar..' - '..currentRealm

    --if currentMaxLevel <= currentCharLevel then 
    if currentMaxLevel <= currentCharLevel then 
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        self:RegisterEvent("UPDATE_INSTANCE_INFO")
        self:RegisterEvent("LFG_COMPLETION_REWARD")
        self:RegisterEvent("LFG_UPDATE_RANDOM_INFO")
		self:RegisterEvent("QUEST_COMPLETE")
        self:RegisterEvent("QUEST_FINISHED")
    end
    
    self.db = LibStub("AceDB-3.0"):New("AiloDB", defaults, true)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("Ailo", self.GenerateOptions)

    if not self.db.global.version or DB_VERSION > self.db.global.version then
        self:Output(L["DB_VERSION_UPGRADE_PURGE"])
        Ailo:WipeDB()
        self.db.global.version = DB_VERSION 
    end

    local AiloLDB = ldb:NewDataObject("Ailo", {
        type = "data source",
        text = "Ailo",
        icon = "Interface\\Icons\\Achievement_Dungeon_UlduarRaid_Archway_01.png",
        OnClick = function(clickedframe, button)
            if button == "RightButton" then 
                InterfaceOptionsFrame_OpenToCategory(Ailo.optionsFrame) 
            else 
                if IsShiftKeyDown() then
                    Ailo:ManualPlayerUpdate() 
                else
                    ToggleFriendsFrame(5)
                end
            end
        end,
        OnEnter = function(tt)
            local tooltip = LibQTip:Acquire("AiloTooltip", 1, "LEFT") 
            Ailo.tooltip = tooltip
            Ailo:PrepareTooltip(tooltip) 
            tooltip:SmartAnchorTo(tt)
            tooltip:Show()
        end,
        OnLeave = function(tt)
            LibQTip:Release(Ailo.tooltip)
            Ailo.tooltip = nil
        end,
    })

    LDBIcon:Register("Ailo", AiloLDB, self.db.profile.minimapIcon)
    -- Request saved raidID's for this char
    -- Will trigger UPDATE_INSTANCE_INFO when after the data is recieved
    RequestRaidInfo()
    self:SetupClasscoloredFonts()
    if CUSTOM_CLASS_COLORS then
        CUSTOM_CLASS_COLORS:RegisterCallback("SetupClasscoloredFonts", self)
    end
end

function Ailo:OnEnable()
	OpenCalendar()
	self:ScheduleTimer("CheckSeasonActive", 2) -- wait 3 secs 
	self:ScheduleTimer("CheckCharGear", 5) -- wait 3 secs 
end

local RAID_CLASS_COLORS_FONTS = {}

function Ailo:SetupClasscoloredFonts()
    local class, color, CHOOSEN_CLASS_COLORS

    if self.db.profile.useCustomClassColors and CUSTOM_CLASS_COLORS then
        CHOOSEN_CLASS_COLORS = CUSTOM_CLASS_COLORS
    else
        CHOOSEN_CLASS_COLORS = RAID_CLASS_COLORS
    end
    for class,color in pairs(CHOOSEN_CLASS_COLORS) do
        if not RAID_CLASS_COLORS_FONTS[class] then 
            RAID_CLASS_COLORS_FONTS[class] = CreateFont("ClassFont"..class)
            RAID_CLASS_COLORS_FONTS[class]:CopyFontObject(GameTooltipText)
        end
        RAID_CLASS_COLORS_FONTS[class]:SetTextColor(color.r, color.g, color.b)
    end
end

function Ailo:GenerateOptions()
    Ailo.options = {
        name = "Ailo",
        type = 'group',
        args = {
            genconfig = {
                name = L["General Settings"],
                type = 'group',
                order = 1,
                get = function(info) return Ailo.db.profile[info[#info]] end,
                set = function(info, value) Ailo.db.profile[info[#info]] = value end,
                args = {
                    savedraid = {
                        name = L["Saved raid color"],
                        desc = L["SAVED_RAID_DESC"],
                        type = 'color',
                        order = 1,
                        get  = getColor,
                        set  = setColor,
                        hasAlpha = true,
                    },
                    freeraid = {
                        name = L["Free raid color"],
                        desc = L["FREE_RAID_DESC"],
                        type = 'color',
                        order = 2,
                        get  = getColor,
                        set  = setColor,
                        hasAlpha = true,
                    },
                    useClassColors = {
                        type = "toggle",
                        order = 3,
                        name = L["Color names by class"],
                    },
                    useCustomClassColors = {
                        type = "toggle",
                        order = 4,
                        name = L["Use !ClassColors"],
                        desc = L["Use !ClassColors addon for class colors used to color the names in the tooltip"],
                        get = function(info) return Ailo.db.profile[info[#info]] end,
                        set = function(info, value) 
                            Ailo.db.profile[info[#info]] = value 
                            Ailo:SetupClasscoloredFonts()
                        end,
                        disabled = function() return not Ailo.db.profile.useClassColors or not CUSTOM_CLASS_COLORS end,
                    },
                    showCharacterRealm = {
                        name = L["Show character realms"],
                        type = "toggle",
                        order = 5,
                    },
                    minimapIcon = {
                        type = "toggle",
                        name = L["Show minimap button"],
                        desc = L["Show the Ailo minimap button"],
                        order = 6,
                        get = function(info) return not Ailo.db.profile.minimapIcon.hide end,
                        set = function(info, value)
                            Ailo.db.profile.minimapIcon.hide = not value
                            if value then LDBIcon:Show("Ailo") else LDBIcon:Hide("Ailo") end
                        end,
                    },

					description_spacer_1 = {
						name =  "",
						type = "description",
						order = 7
					},					

					header_0 = {
                        type = "header",
                        order = 8,
                        name = "",
                    },
                    hc = {
                        type = "input",
                        order = 9,
                        name = L["Tooltip abbreviation used for heroic raids"],
                        width = "double",
                    },
                    nhc = {
                        type = "input",
                        order = 10,
                        name = L["Tooltip abbreviation used for nonheroic raids"],
                        width = "double",
                    },
					dynamic = {
						type = "input",
						order = 11,
						name = L["Tooltip abbreviation used for dynamic raids"],
						width = "double",
					},
					
					description_spacer_2 = {
						name =  "",
						type = "description",
						order = 12
					},
                    
					header_1 = {
                        type = "header",
                        order = 13,
                        name = L["Tooltip abbreviations for Daily Seasonal and Heroic"],
                    },
                    dailySH = {
                        type = "input",
                        order = 14,
                        name = L["Daily"],
                        width = "normal",
                    },
                    event = {
                        type = "input",
                        order = 15,
                        name = L["Seasonal Event"],
                        width = "half",
                    },
                    heroic = {
                        type = "input",
                        order = 16,
                        name = L["Heroic"],
                        width = "half",
                    },
					header_2 = {
                        type = "header",
                        order = 17,
                        name = L["Tooltip abbreviations for Weekly Raid Quest"],
                    },
                    weeklyR = {
                        type = "input",
                        order = 18,
                        name = L["Weekly"],
                        width = "normal",
                    },
					quest = {
						type = "input",
						order = 19,
						name = L["Raid Quest"],
						width = "normal",
					},
					header_3 = {
                        type = "header",
                        order = 20,
                        name = L["Tooltip abbreviations for PvP Daily and Weekly"],
                    },
                    dailyP = {
                        type = "input",
                        order = 21,
                        name = L["Daily"],
                        width = "half",
                    },
					pvpD = {
						type = "input",
						order = 22,
						name = L["PvP Daily"],
						width = "half",
					},
                    weeklyP = {
                        type = "input",
                        order = 23,
                        name = L["Weekly"],
                        width = "half",
                    },
					pvpW = {
						type = "input",
						order = 24,
						name = L["PvP Weekly"],
						width = "half",
					},
					header_4 = {
                        type = "header",
                        order = 25,
                        name = ""
                    },
					
					description_spacer_3 = {
						name =  "",
						type = "description",
						order = 26
					},
					
                    showOnlyWrathRaids = {
                        type = "toggle",
                        order = 30,
                        name = L["showOnlyWrathRaids"],
                        desc = L["showOnlyWrathRaids_DESC"],
                    },
                    show5Man = {
                        type = "toggle",
                        order = 31,
                        name = L["Show 5-man instances"],
                    },
                    showDailyHeroic = {
                        type = "toggle",
                        order = 32,
                        name = L["Track 'Daily Heroic'"],
                        desc = L["TRACK_DAILY_HEROIC_DESC"],
                    },
                    showWeeklyRaid  = {
                        type = "toggle",
                        order = 33,
                        name = L["Track 'Weekly Raid'"],
                        desc = L["If the character has done the 'Weekly Raid' you get in Dalaran"],
                    },
                    showWGVictory  = {
                        type = "toggle",
                        order = 34,
                        name = L["Track 'WG Victory'"],
                        desc = L["If the character has done the 'Victory in Wintergrasp' weekly pvp quest"],
                    },
                    showDailyPVP  = {
                        type = "toggle",
                        order = 35,
                        name = L["Track PvP daily"],
                    },
                    showSeasonal  = {
                        type = "toggle",
                        order = 36,
                        name = L["Track 'Event boss'"],
                        desc = L["TRACK_DAILY_EVENT_BOSS_DESC"],
                    },
                    showRealmHeaderLines  = {
                        type = "toggle",
                        order = -11,
                        name = L["Show Realm Headers"],
                        desc = L["SHOW_REALMLINES_DESC"],
                    },                    
                    showAllChars  = {
                        type = "toggle",
                        order = -10,
                        name = L["Show all chars"],
                        desc = L["Regardles of any saved instances"],
                    },
					
					description_spacer_end = {
						name =  "\n",
						type = "description",
						order = -3
					},
					
                    wipeDB = {
                        type = "execute",
                        name = L["Wipe Database"],
                        order = -2,
                        confirm = true,
                        func = function() Ailo:WipeDB() end,
                    },
                    showMessages = {
                        type = "toggle",
                        order = -1,
                        name = L["Chatframe Messages"],
                    },
                },
            },
            instanceAbbr = { 
                type = 'group',
                name = L["Instance Abbreviations"],
                get = function(info) return Ailo.db.profile.instanceAbbr[info[#info]] end,
                set = function(info, value) Ailo.db.profile.instanceAbbr[info[#info]] = value end,
                args = {
                    header = {
                        type = "header",
                        order = 1,
                        name = L["Change the abbreviations used in the tooltip"]
                    },
                },
            },
        },
    }
    local instance, abbr
    for instance, abbr in pairs(Ailo.db.profile.instanceAbbr) do
        Ailo.options.args.instanceAbbr.args[instance] = {
            type = "input",
            name = instance,
        }
    end
    Ailo.options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(Ailo.db)
    return Ailo.options
end

function Ailo:Output(...)
    if self.db.profile.showMessages then
        Ailo:Print(...)
    end
end 

function Ailo:PrepareTooltip(tooltip)
    local raidorder = {}
    -- Cell are just colored green/red
               -- ToC       VoA
            -- 10     25   10  25
          -- hc nhc hc nhc nhc nhc
    -- Char1 [] [ ] [] [ ] [ ] [ ]
    -- Char2 [] [ ] [] [ ] [ ] [ ]
    -- Char3 [] [ ] [] [ ] [ ] [ ]
	
    local charsdb = self.db.global.chars
    local raidsdb = self.db.global.raids
    local raidPrio = {}
    local raidorder_used = {}
	local raid_other = {}
	local raid_dungeon = {}
	
	wipe(raid_other)
	wipe(raid_dungeon)
	wipe(raidorder_used)	-- table clean up
    
    local nextPurge = self.db.global.nextPurge
    if nextPurge > 0 and time() > (nextPurge + 60) then
        -- Only search 
        self:PurgeOldRaidIDs()
        self:TrimRaidTable()
        self:CheckDailyHeroicLockouts()
        self.db.global.nextPurge = self:GetNextPurge()
    end
	
	for _, raidName in pairs(TC.RaidOrderLfgId) do -- check for high priority raids
		if self.db.global.raids[raidName] then
			tinsert(raidPrio, raidName)
			raidorder_used[raidName] = true
		end
	end
	if not self.db.profile.showOnlyWrathRaids then
		for raidName, raidTable in pairs(self.db.global.raids) do 
			if not raidorder_used[raidName] then
				for size,_ in pairs(raidTable) do
					if size > 5 then  -- sort between raids and dungeons
						tinsert(raid_other, raidName)
					else
						tinsert(raid_dungeon, raidName)
					end
					break
				end
			end
		end
		sort(raid_other)	-- sort other raids by name
		sort(raid_dungeon)	-- sort dungeons by name
		for _, n in pairs(raid_other) do	-- add other raids to raid order
			tinsert(raidPrio, n)
		end
		for _, n in pairs(raid_dungeon) do	-- add dungeons to raid order
			tinsert(raidPrio, n)
		end
	end

    if next(raidsdb) or self.db.profile.showAllChars or 
       self.db.profile.showDailyHeroic or self.db.profile.showWeeklyRaid or 
       self.db.profile.showWGVictory or self.db.profile.showDailyPVP or self.db.profile.showSeasonal then
        -- At least one char is saved to some 
        tooltip:AddHeader(L["Raid"]) -- Raid
        tooltip:AddHeader(L["Size"]) -- Size
        tooltip:AddHeader(L["Diff"]) -- Heroic

        local raid, size, difficulties,  difficulty, colcount, numdifficulties, lastcolumn, dailyHeroicColum, weeklyRaidColumn, wgVictoryColumn, dailyPVPColumn
		local seasonDailyColumn
        -- Daily Seasonal Instacne Boss column
        if self.db.profile.showSeasonal and Seasonal.ActiveHoliday ~= nil then
            seasonDailyColumn = tooltip:AddColumn("CENTER")
            tooltip:SetCell(1, seasonDailyColumn, self.db.profile.dailySH)
            tooltip:SetCell(2, seasonDailyColumn, self.db.profile.event)
            tooltip:SetCell(3, seasonDailyColumn, Seasonal.ActiveHoliday.icon)
        end
        -- Daily Heroic column
        if self.db.profile.showDailyHeroic then
            dailyHeroicColum = tooltip:AddColumn("CENTER")
            tooltip:SetCell(1, dailyHeroicColum, self.db.profile.dailySH)
            tooltip:SetCell(2, dailyHeroicColum, self.db.profile.heroic)
            tooltip:SetCell(3, dailyHeroicColum, "|TInterface\\Icons\\inv_misc_frostemblem_01:20|t")
        end
        -- Weekly Raid column
        if self.db.profile.showWeeklyRaid then
            weeklyRaidColumn = tooltip:AddColumn("CENTER")
            tooltip:SetCell(1, weeklyRaidColumn, self.db.profile.weeklyR)
            tooltip:SetCell(2, weeklyRaidColumn, self.db.profile.quest)
            tooltip:SetCell(3, weeklyRaidColumn, "|TInterface\\Icons\\inv_misc_frostemblem_01:20|t")
        end
        -- PvP Daily column
        if self.db.profile.showDailyPVP then
            dailyPVPColumn = tooltip:AddColumn("CENTER")
            tooltip:SetCell(1, dailyPVPColumn, self.db.profile.dailyP)
            tooltip:SetCell(2, dailyPVPColumn, self.db.profile.pvpD)
            tooltip:SetCell(3, dailyPVPColumn, "|TInterface\\PVPFrame\\PVP-ArenaPoints-Icon:20|t")
        end
        -- Wintergrasp Victory column
        if self.db.profile.showWGVictory then
            wgVictoryColumn = tooltip:AddColumn("CENTER")
            tooltip:SetCell(1, wgVictoryColumn, self.db.profile.weeklyP)
            tooltip:SetCell(2, wgVictoryColumn, self.db.profile.pvpW)
            tooltip:SetCell(3, wgVictoryColumn, "|TInterface\\Icons\\inv_misc_platnumdisks:20|t")
        end
        -- Instances with lockouts
        local raidabbr, sizes
        for _, raid in pairs(raidPrio) do
			sizes = raidsdb[raid]
            colcount = 0 -- Span needed for the 'Raid' cell above the 'Size' cells
            raidabbr = self:GetInstanceAbbr(raid)
            if raidabbr then
                for size, difficulties in pairs(sizes) do
                    numdifficulties = 0 -- Span needed for the 'Size' cell above the 'Difficulty' cells
    
                    if size > 5 or self.db.profile.show5Man then
                        for difficulty, _ in pairs(difficulties) do
                            colcount = colcount +1
                            numdifficulties = numdifficulties +1
            
                            lastcolumn = tooltip:AddColumn("CENTER")
							
							if raid == L["Raid ICC"] then
								tooltip:SetCell(3, lastcolumn, self.db.profile.dynamic)
							else
								tooltip:SetCell(3, lastcolumn, (difficulty > 2 or size==5) and self.db.profile.hc or self.db.profile.nhc)
							end
        
                            raidorder[(string_format("%s.%d.%s", raid, size, difficulty))] = lastcolumn
                        end
                        tooltip:SetCell(2, lastcolumn - numdifficulties+1, size, numdifficulties)
                    end
                end
                if colcount > 0 then
                    tooltip:SetCell(1, lastcolumn - colcount+1, raidabbr, colcount)
                end
            end
        end
		tooltip:AddSeparator(1,1,1,1,1)
        self:BuildSortedKeyTables()
        local iterateRealm, iteratePlayer, nameString, instances, currentInstance, lastline, realmSepPosition, displayedName
		local tnow = time()
        for _,iterateRealm in ipairs(sortRealms) do
            if self.db.profile.showRealmHeaderLines then
				lastline = tooltip:AddLine("")
                tooltip:SetCell(lastline, 1, iterateRealm, nil, "CENTER", tooltip:GetColumnCount())
                tooltip:AddSeparator(1,1,1,1,1)
            end
			char_rows = 0
            for _,iteratePlayer in ipairs(sortRealmsPlayer[iterateRealm]) do
                instances = charsdb[iterateRealm][iteratePlayer]
                if self.db.profile.showAllChars or (instances.lockouts and next(instances.lockouts)) or instances.dailyheroic or instances.weeklydone or instances.wgvictory or instances.dailypvp or instances.dailyseason then
					lastline = tooltip:AddLine("")
					nameString = iteratePlayer
					-- if instances.level then
						-- nameString = "["..tostring(instances.level) .."] ".. iteratePlayer
					-- end
                    if self.db.profile.showCharacterRealm then
                      nameString = nameString.." - "..iterateRealm
                    end
                    if self.db.profile.useClassColors then
                        tooltip:SetCell(lastline, 1, nameString, RAID_CLASS_COLORS_FONTS[self.db.global.charClass[iteratePlayer.." - "..iterateRealm]])
                    else
                        tooltip:SetCell(lastline, 1, nameString )
                    end
                    for i = tooltip:GetColumnCount(),2,-1 do
                        tooltip:SetCell(lastline, i, "") 
                        tooltip:SetCellColor(lastline, i, self.db.profile.freeraid.r, self.db.profile.freeraid.g, self.db.profile.freeraid.b, self.db.profile.freeraid.a)
                    end
                    if dailyHeroicColum and type(instances.dailyheroic) == "number" then
						local expire_text = ""
						local remaining = instances.dailyheroic - tnow
						if remaining >= 3600 then
							local h_time = math.floor(remaining / 3600)
							expire_text = tostring(h_time) .. L["hours"]
						elseif remaining > 0 then
							local m_time = math.ceil(remaining / 60)
							expire_text = tostring(m_time) .. L["minutes"]
						end									
						tooltip:SetCell(lastline, dailyHeroicColum, expire_text) -- change
                        tooltip:SetCellColor(lastline, dailyHeroicColum, self.db.profile.savedraid.r, self.db.profile.savedraid.g, self.db.profile.savedraid.b, self.db.profile.savedraid.a)
                    end
                    if seasonDailyColumn and type(instances.dailyseason) == "number" then
						local expire_text = ""
						local remaining = instances.dailyseason - tnow
						if remaining >= 3600 then
							local h_time = math.floor(remaining / 3600)
							expire_text = tostring(h_time) .. L["hours"]
						elseif remaining > 0 then
							local m_time = math.ceil(remaining / 60)
							expire_text = tostring(m_time) .. L["minutes"]
						end									
						tooltip:SetCell(lastline, seasonDailyColumn, expire_text) -- change
                        tooltip:SetCellColor(lastline, seasonDailyColumn, self.db.profile.savedraid.r, self.db.profile.savedraid.g, self.db.profile.savedraid.b, self.db.profile.savedraid.a)
                    end
                    if weeklyRaidColumn and type(instances.weeklydone) == "number" then
						local expire_text = ""
						local remaining = instances.weeklydone - tnow
						if remaining >= 24 * 3600 then
							local d_time = math.floor(remaining / (3600 * 24))
							expire_text = tostring(d_time) .. L["days"]
						elseif remaining >= 3600 then
							local h_time = math.floor(remaining / 3600)
							expire_text = tostring(h_time) .. L["hours"]
						elseif remaining > 0 then
							local m_time = math.ceil(remaining / 60)
							expire_text = tostring(m_time) .. L["minutes"]
						end
						tooltip:SetCell(lastline, weeklyRaidColumn, expire_text) -- change
                        tooltip:SetCellColor(lastline, weeklyRaidColumn, self.db.profile.savedraid.r, self.db.profile.savedraid.g, self.db.profile.savedraid.b, self.db.profile.savedraid.a)
                    end
                    if dailyPVPColumn and instances.dailypvp then
						local expire_text = ""
						local remaining = instances.dailypvp - tnow
						if remaining >= 3600 then
							local h_time = math.floor(remaining / 3600)
							expire_text = tostring(h_time) .. L["hours"]
						elseif remaining > 0 then
							local m_time = math.ceil(remaining / 60)
							expire_text = tostring(m_time) .. L["minutes"]
						end									
						tooltip:SetCell(lastline, dailyPVPColumn, expire_text) -- change
                        tooltip:SetCellColor(lastline, dailyPVPColumn, self.db.profile.savedraid.r, self.db.profile.savedraid.g, self.db.profile.savedraid.b, self.db.profile.savedraid.a)
                    end
                    if wgVictoryColumn and type(instances.wgvictory) == "number" then
						local expire_text = ""
						local remaining = instances.wgvictory - tnow
						if remaining >= 24 * 3600 then
							local d_time = math.floor(remaining / (3600 * 24))
							expire_text = tostring(d_time) .. L["days"]
						elseif remaining >= 3600 then
							local h_time = math.floor(remaining / 3600)
							expire_text = tostring(h_time) .. L["hours"]
						elseif remaining > 0 then
							local m_time = math.ceil(remaining / 60)
							expire_text = tostring(m_time) .. L["minutes"]
						end
						tooltip:SetCell(lastline, wgVictoryColumn, expire_text) -- change
                        tooltip:SetCellColor(lastline, wgVictoryColumn, self.db.profile.savedraid.r, self.db.profile.savedraid.g, self.db.profile.savedraid.b, self.db.profile.savedraid.a)
                    end
                    if instances.lockouts then
                        for currentInstance, expireTime in pairs(instances.lockouts) do
                            if raidorder[currentInstance] then
								local expire_text = ""
								local remaining = expireTime - tnow
								if string.find(currentInstance, "%.5%.") then
									-- 5-Mann-Dungeon: Stunden
									if remaining >= 3600 then
										local h_time = math.floor(remaining / 3600)
										expire_text = tostring(h_time) .. L["hours"]
									elseif remaining > 0 then
										local m_time = math.ceil(remaining / 60)
										expire_text = tostring(m_time) .. L["minutes"]
									end									
								else
									-- Raid: Tage
									if remaining >= 24 * 3600 then
										local d_time = math.floor(remaining / (3600 * 24))
										expire_text = tostring(d_time) .. L["days"]
									elseif remaining >= 3600 then
										local h_time = math.floor(remaining / 3600)
										expire_text = tostring(h_time) .. L["hours"]
									elseif remaining > 0 then
										local m_time = math.ceil(remaining / 60)
										expire_text = tostring(m_time) .. L["minutes"]
									end
								end
								tooltip:SetCell(lastline, raidorder[currentInstance], expire_text) -- change
                                tooltip:SetCellColor(lastline, raidorder[currentInstance], self.db.profile.savedraid.r, self.db.profile.savedraid.g, self.db.profile.savedraid.b, self.db.profile.savedraid.a)
                            end
                        end
                    end
                end
            end
        end
    else
        -- No saved raids at all
        tooltip:AddHeader(L["No saved raids found"])
    end
end

function Ailo:BuildSortedKeyTables()
    local c, r, tempSortRealmsPlayer
    wipe(sortRealms)
    sortRealms = {}
    wipe(sortRealmsPlayer)
    sortRealmsPlayer = {}
	tempSortRealmsPlayer = {}
    for r,_ in pairs(self.db.global.chars) do
        tinsert(sortRealms, r)
        sortRealmsPlayer[r] = {}
        tempSortRealmsPlayer[r] = {}
        for c,_ in pairs(self.db.global.chars[r]) do
            tinsert(tempSortRealmsPlayer[r], {name = c, iLevel = self.db.global.chars[r][c].iLevel or 0} )
        end
        table.sort(tempSortRealmsPlayer[r], function(c1, c2) 
			if c1.iLevel and c2.iLevel then 
				return c1.iLevel > c2.iLevel
			else
				return c1.name < c2.name
			end
		end)
		for k,v in ipairs(tempSortRealmsPlayer[r]) do
			table.insert(sortRealmsPlayer[r], v.name)
		end
    end
    table.sort(sortRealms)
end

function Ailo:GetInstanceAbbr(instanceName)
    if not self.db.profile.instanceAbbr[instanceName] then
		-- Has no abbreviation yet, try it with a somewhat good guess
		-- Tries to get the first char of every word, does not go well with utf-8 chars
		self.db.profile.instanceAbbr[instanceName] = string_gsub(instanceName, "(%a)[%l%p]*[%s%-]*", "%1")
    end
    return ( self.db.profile.instanceAbbr[instanceName] ~= "" and self.db.profile.instanceAbbr[instanceName] or nil )
end

function Ailo:GetNextPurge()
    local charsdb = self.db.global.chars
    local realm, charscurrentPlayer, instances, currentInstance, expireTime
    local nextPurge = 0
    for realm, chars in pairs(charsdb) do 
        for currentPlayer, instances in pairs(chars) do 
            if instances.lockouts then
                for currentInstance, expireTime in pairs(instances.lockouts) do
                    if nextPurge == 0 or nextPurge > expireTime then
                        nextPurge = expireTime
                    end
                end
            end
            -- Ignore invalid saved values; these fields must contain timestamps.
            if type(instances.dailyheroic) == "number" and (nextPurge == 0 or nextPurge > instances.dailyheroic) then
                nextPurge = instances.dailyheroic
            end
            if type(instances.dailyseason) == "number" and (nextPurge == 0 or nextPurge > instances.dailyseason) then
                nextPurge = instances.dailyseason
            end
            if type(instances.weeklydone) == "number" and (nextPurge == 0 or nextPurge > instances.weeklydone) then
                nextPurge = instances.weeklydone
            end
            if type(instances.wgvictory) == "number" and (nextPurge == 0 or nextPurge > instances.wgvictory) then
                nextPurge = instances.wgvictory
            end
        end
    end
	local qResetTime = time() + GetQuestResetTime() + 60
	if qResetTime < nextPurge then
		nextPurge = qResetTime
	end
	if nextPurge > 100 then nextPurge = nextPurge + 60 end -- add 60 sec to ensure that the purge is after the expire time
    return nextPurge
end

function Ailo:PurgeOldRaidIDs()
    local charsdb = self.db.global.chars
    local realm, currentPlayer, instances, currentInstance, expireTime
    local now = time()
    for realm, chars in pairs(charsdb) do 
        for currentPlayer, instances in pairs(chars) do 
            if instances.lockouts then 
                for currentInstance, expireTime in pairs(instances.lockouts) do
                    if now > expireTime then
                        self.db.global.chars[realm][currentPlayer].lockouts[currentInstance] = nil
                    end
                end
                if not next(charsdb[realm][currentPlayer].lockouts) then 
                    self.db.global.chars[realm][currentPlayer].lockouts = nil
                end
            end
        end
    end
end

function Ailo:ExtendRaidTable(instanceName, size, difficulty)
    -- Save it for the tooltip
    self.db.global.raids[instanceName] = self.db.global.raids[instanceName] or {}
    self.db.global.raids[instanceName][size] =  self.db.global.raids[instanceName][size] or {}
    self.db.global.raids[instanceName][size][difficulty] = true
end

function Ailo:TrimRaidTable()
    local charsdb = self.db.global.chars
    local raidsdb = self.db.global.raids
    local currentPlayer, raids, currentInstance
    local raid, sizes, size, difficulties, difficulty, realm, chars, currentPlayer, instances
    local isUsed, raidString = false
    for raid, sizes in pairs(raidsdb) do
        for size, difficulties in pairs(sizes) do
            for difficulty, _ in pairs(difficulties) do
                isUsed = false
                raidString = string_format("%s.%d.%s", raid, size, difficulty)
                for realm, chars in pairs(charsdb) do 
                    for currentPlayer,instances in pairs(chars) do
                        if instances.lockouts and instances.lockouts[raidString] then
                            isUsed = true
                            break
                        end
                    end
                end
                if not isUsed then
                    self:DeleteFromRaidTable(raid, size, difficulty)
                end
            end
        end
    end
end

function Ailo:DeleteFromRaidTable(instanceName, size, difficulty)
    self.db.global.raids[instanceName][size][difficulty] = nil
    if not next(self.db.global.raids[instanceName][size]) then
        self.db.global.raids[instanceName][size] = nil
    end
    if not next(self.db.global.raids[instanceName]) then
        self.db.global.raids[instanceName] = nil
    end
end

function Ailo:ManualPlayerUpdate()
    if currentMaxLevel > currentCharLevel then return end
    self:Output(L["Updating data for current player."])
    if not self.db.global.chars[currentRealm] then 
        self.db.global.chars[currentRealm] = {}
    else
        wipe(self.db.global.chars[currentRealm][currentChar])
        self.db.global.chars[currentRealm][currentChar] = nil
    end
    self:TrimRaidTable()
    self:UpdatePlayer()
end

function Ailo:SaveRaidForChar(instance, expireTime, character, realm)
    character = character or currentChar
    realm = realm or currentRealm
    if not self.db.global.chars[realm] then
        self.db.global.chars[realm] = {}
    end
    if not self.db.global.chars[realm][character] then
        self.db.global.chars[realm][character] = {}
    end
    if not self.db.global.chars[realm][character].lockouts then
        self.db.global.chars[realm][character].lockouts = {}
    end
    self.db.global.chars[realm][character].lockouts[instance] = expireTime
    if expireTime < self.db.global.nextPurge or self.db.global.nextPurge <= 100 then
        self.db.global.nextPurge = expireTime
    end
end

function Ailo:WipeDB()
    if type(self.db.global.chars) == "table" then 
        wipe(self.db.global.chars)
    end
    if type(self.db.global.raids) == "table" then 
        wipe(self.db.global.raids)
    end
    if type(self.db.global.charClass) == "table" then 
        wipe(self.db.global.charClass)
    end
end

function Ailo:UpdatePlayer()
    if currentMaxLevel > currentCharLevel then return end
    self.db.global.charClass[currentCharRealm] = select(2,UnitClass('player'))
    local now, index = time()
    local instanceName, instanceReset, instanceDifficulty, locked, isRaid, maxPlayers
    local instanceNameAbbr, instanceString
    for index=1,GetNumSavedInstances() do
        instanceName, _, instanceReset, instanceDifficulty, locked, _, _, isRaid, maxPlayers, _ = GetSavedInstanceInfo(index)
        if locked then
            instanceString   = string_format("%s.%d.%s", instanceName, maxPlayers, instanceDifficulty)
            self:ExtendRaidTable(instanceName, maxPlayers, instanceDifficulty)
            self:SaveRaidForChar(instanceString, now+instanceReset)
        end
    end
    self:UpdateDailyHeroicForChar()
    -- Daily
    self.db.global.chars[currentRealm][currentChar].dailypvp = nil
    self.db.global.chars[currentRealm][currentChar].dailypvp = (GetRandomBGHonorCurrencyBonuses())
end


Ailo.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Ailo")
function Ailo:UPDATE_INSTANCE_INFO()
    self:UpdatePlayer()
end

local INSTANCE_SAVED = _G["INSTANCE_SAVED"]
function Ailo:CHAT_MSG_SYSTEM(event, msg)
    -- You are now saved to this instances.
    -- Refresh RaidInfo
    if tostring(msg) == INSTANCE_SAVED then
        RequestRaidInfo()
    end
end

function Ailo:CheckDailyHeroicLockouts()
    local charsdb = self.db.global.chars
    local iterateRealm, iteratePlayer, instances, expireTime
    local now = time()
    for iterateRealm, _ in pairs(charsdb) do
        for iteratePlayer, instances in pairs(charsdb[iterateRealm]) do 
            -- These fields are expiration timestamps. Remove invalid saved values
            -- instead of comparing booleans or other unexpected types with numbers.
            if type(instances.dailyheroic) ~= "number" or now > instances.dailyheroic then
                instances.dailyheroic = nil
            end
            if type(instances.dailyseason) ~= "number" or now > instances.dailyseason then
                instances.dailyseason = nil
            end
            if type(instances.weeklydone) ~= "number" or now > instances.weeklydone then
                instances.weeklydone = nil
            end
            if type(instances.wgvictory) ~= "number" or now > instances.wgvictory then
                instances.wgvictory = nil
            end
        end
    end
end

function Ailo:UpdateDailyHeroicForChar()
    if not self.db.global.chars[currentRealm] then
        self.db.global.chars[currentRealm] = {}
    end
    if not self.db.global.chars[currentRealm][currentChar] then
        self.db.global.chars[currentRealm][currentChar] = {}
    end
    -- GetLFGDungeonRewards(type)
    -- first return value: true if it was already done in this "Daily Quests"-lockout, false else
    -- type: 261 WotLK-nhc, 262 WotLK-hc
    if (GetLFGDungeonRewards(262)) then
        local expireTime = time()+GetQuestResetTime()
        self.db.global.chars[currentRealm][currentChar].dailyheroic = expireTime
        if expireTime < self.db.global.nextPurge or self.db.global.nextPurge <= 100 then
            self.db.global.nextPurge = expireTime 
        end
    else
        self.db.global.chars[currentRealm][currentChar].dailyheroic = nil
    end
	-- code for holidays
	if (Seasonal.ActiveHoliday) then -- if we have an active holiday
		local LFG_doneToday, LFG_moneyBase = GetLFGDungeonRewards(Seasonal.ActiveHoliday.dungeon_id)
		if ( LFG_doneToday or LFG_moneyBase == 0 ) then -- if the current holiday has an asociated dungeon_id
			local expireTime = time()+GetQuestResetTime() -- get reset time for daily quests
			self.db.global.chars[currentRealm][currentChar].dailyseason = expireTime
			if expireTime < self.db.global.nextPurge or self.db.global.nextPurge <= 100 then
				self.db.global.nextPurge = expireTime
			end
		else
			self.db.global.chars[currentRealm][currentChar].dailyseason = nil
			if Seasonal.ActiveHoliday.CheckForLFG and (Seasonal.ActiveHoliday.CheckForLFG < 2) then
				Seasonal.ActiveHoliday.CheckForLFG = 2
				LFDQueueFrame_SetType(Seasonal.ActiveHoliday.dungeon_id)
			end
		end
	end
end

local currentWeeklyQuestID = nil
local questWeeklyFlag = false
function Ailo:LFG_UPDATE_RANDOM_INFO()
    -- See below why we update here
    self:UpdateDailyHeroicForChar()
end

function Ailo:LFG_COMPLETION_REWARD()
    --[[
    Fires when a random dungeon is completed and the achievement-like
    alert window pops up. The problem is that this DOES NOT update
    the return values of GetLFGDungeonRewards(x), those are updated
    when LFG_UPDATE_RANDOM_INFO is recieved, so force the client to
    call for an update
    ]]--
    RequestLFDPlayerLockInfo()
end

function Ailo:QUEST_COMPLETE(...)
    questWeeklyFlag = false
    currentWeeklyQuestID = nil

    if not QuestIsWeekly() then
        return
    end

    questWeeklyFlag = true

    local currentTitle = GetTitleText()

    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)

        if not isHeader
            and title
            and title == currentTitle
            and questID
            and isComplete == 1 then

            -- Wintergrasp Weekly
            if questID == 13181 or questID == 13183 then
                currentWeeklyQuestID = questID
                break
            end

            -- Raid Weekly
            if questID >= 24579 and questID <= 24590 then
                currentWeeklyQuestID = questID
                break
            end
        end
    end
end

function Ailo:QUEST_FINISHED(...)
    if questWeeklyFlag ~= true then
        return
    end

    questWeeklyFlag = false

    if not currentWeeklyQuestID then
        return
    end

    local next_reset = time() + GetQuestResetTime()
    local wday = date("*t", next_reset).wday

    if wday > reset_wday then
        next_reset = next_reset + 3600 * 24 * (reset_wday - wday + 7)
    else
        next_reset = next_reset + 3600 * 24 * (reset_wday - wday)
    end

    -- Wintergrasp Weekly
    if currentWeeklyQuestID == 13181 or currentWeeklyQuestID == 13183 then
        self.db.global.chars[currentRealm][currentChar].wgvictory = next_reset

    -- Raid Weekly
    elseif currentWeeklyQuestID >= 24579 and currentWeeklyQuestID <= 24590 then
        self.db.global.chars[currentRealm][currentChar].weeklydone = next_reset
    end

    currentWeeklyQuestID = nil
end

function Ailo:CheckSeasonActive()
	local eventName, eventTexture, month, day, numEvents
	Seasonal.ActiveHoliday = nil -- resets local variable

	_, month, day, _ = CalendarGetDate(); -- get current date
	CalendarSetAbsMonth(month) -- set the Calender to be at the current month, current year (absolute)
	numEvents = CalendarGetNumDayEvents(0, day) -- get the number of events on the current day

	if numEvents > 0 then
		for i=1,numEvents do   
			eventName,_,eventTexture = CalendarGetHolidayInfo(0,day,i) -- get the name and texture of the season holiday
			if eventTexture ~= nil then -- if there is a season holiday texture
				for k,v in pairs(Seasonal.Events) do
					if eventTexture == v.texture_name then
						Seasonal.ActiveHoliday = Seasonal.Events[k] -- stores to local variable
						Seasonal.ActiveHoliday.CheckForLFG = 1
					end
				end
			end
		end
	end
end

function Ailo:CheckCharGear()
	local invSlot, itemRarity, itemLevel, itemID, accumLevel, numSlots
	-- itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID) 
	if not self.db.global.chars[currentRealm] then return end
	local thisCharDB = self.db.global.chars[currentRealm][currentChar]
	if not thisCharDB then return end
	accumLevel = 0
	numSlots = 0
	for _,invSlot in ipairs({1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18}) do		-- head to main hand
		itemID = GetInventoryItemID("player", invSlot)
		if itemID then 
			_, _, itemRarity, itemLevel = GetItemInfo(itemID) 
			if itemLevel then
				accumLevel = accumLevel + itemLevel*itemRarity/4
				numSlots = numSlots + 1
			end
		elseif (invSlot < 17) then
			numSlots = numSlots + 1
		end
	end
	if numSlots > 0 then
		accumLevel = math.floor( accumLevel / numSlots * 10 ) / 10	-- avg item level
	end
	if (not thisCharDB.iLevel) or (accumLevel > thisCharDB.iLevel) then
		thisCharDB.iLevel = accumLevel
	end
	thisCharDB.level = currentCharLevel
end
