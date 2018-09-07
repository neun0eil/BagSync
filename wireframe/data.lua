--[[
	data.lua
		Handles all the data elements for BagSync
--]]

local BSYC = select(2, ...) --grab the addon namespace
local Data = BSYC:NewModule("Data")
local Unit = BSYC:GetModule("Unit")
local L = LibStub("AceLocale-3.0"):GetLocale("BagSync", true)

----------------------
--   DB Functions   --
----------------------

function Data:OnEnable()

	--get player information from Unit
	local player = Unit:GetUnitInfo()

	--initiate global db variable
	BagSyncDB = BagSyncDB or {}
	BagSyncDB["options§"] = BagSyncDB["options§"] or {}
	BagSyncDB["blacklist§"] = BagSyncDB["blacklist§"] or {}
	
	--main DB call
	BSYC.db = BSYC.db or {}
	BSYC.db.global = BagSyncDB
	
	--realm DB
	BagSyncDB[player.realm] = BagSyncDB[player.realm] or {}
	BSYC.db.realm = BagSyncDB[player.realm]
	
	--player DB
	BSYC.db.realm[player.name] = BSYC.db.realm[player.name] or {}
	BSYC.db.player = BSYC.db.realm[player.name]
	BSYC.db.player.currency = BSYC.db.player.currency or {}
	BSYC.db.player.profession = BSYC.db.player.profession or {}
	
	--blacklist DB
	BSYC.db.blacklist = BagSyncDB["blacklist§"]
	
	--options DB
	BSYC.db.options = BagSyncDB["options§"]
	if BSYC.db.options.showTotal == nil then BSYC.db.options.showTotal = true end
	if BSYC.db.options.showGuildNames == nil then BSYC.db.options.showGuildNames = false end
	if BSYC.db.options.enableGuild == nil then BSYC.db.options.enableGuild = true end
	if BSYC.db.options.enableMailbox == nil then BSYC.db.options.enableMailbox = true end
	if BSYC.db.options.enableUnitClass == nil then BSYC.db.options.enableUnitClass = false end
	if BSYC.db.options.enableMinimap == nil then BSYC.db.options.enableMinimap = true end
	if BSYC.db.options.enableFaction == nil then BSYC.db.options.enableFaction = true end
	if BSYC.db.options.enableAuction == nil then BSYC.db.options.enableAuction = true end
	if BSYC.db.options.tooltipOnlySearch == nil then BSYC.db.options.tooltipOnlySearch = false end
	if BSYC.db.options.enableTooltips == nil then BSYC.db.options.enableTooltips = true end
	if BSYC.db.options.enableTooltipSeperator == nil then BSYC.db.options.enableTooltipSeperator = true end
	if BSYC.db.options.enableCrossRealmsItems == nil then BSYC.db.options.enableCrossRealmsItems = true end
	if BSYC.db.options.enableBNetAccountItems == nil then BSYC.db.options.enableBNetAccountItems = false end
	if BSYC.db.options.enableTooltipItemID == nil then BSYC.db.options.enableTooltipItemID = false end
	if BSYC.db.options.enableTooltipGreenCheck == nil then BSYC.db.options.enableTooltipGreenCheck = true end
	if BSYC.db.options.enableRealmIDTags == nil then BSYC.db.options.enableRealmIDTags = true end
	if BSYC.db.options.enableRealmAstrickName == nil then BSYC.db.options.enableRealmAstrickName = false end
	if BSYC.db.options.enableRealmShortName == nil then BSYC.db.options.enableRealmShortName = false end
	if BSYC.db.options.enableLoginVersionInfo == nil then BSYC.db.options.enableLoginVersionInfo = true end
	if BSYC.db.options.enableFactionIcons == nil then BSYC.db.options.enableFactionIcons = true end
	if BSYC.db.options.enableShowUniqueItemsTotals == nil then BSYC.db.options.enableShowUniqueItemsTotals = true end

	--setup the default colors
	if BSYC.db.options.colors == nil then BSYC.db.options.colors = {} end
	if BSYC.db.options.colors.first == nil then BSYC.db.options.colors.first = { r = 128/255, g = 1, b = 0 }  end
	if BSYC.db.options.colors.second == nil then BSYC.db.options.colors.second = { r = 1, g = 1, b = 1 }  end
	if BSYC.db.options.colors.total == nil then BSYC.db.options.colors.total = { r = 244/255, g = 164/255, b = 96/255 }  end
	if BSYC.db.options.colors.guild == nil then BSYC.db.options.colors.guild = { r = 101/255, g = 184/255, b = 192/255 }  end
	if BSYC.db.options.colors.cross == nil then BSYC.db.options.colors.cross = { r = 1, g = 125/255, b = 10/255 }  end
	if BSYC.db.options.colors.bnet == nil then BSYC.db.options.colors.bnet = { r = 53/255, g = 136/255, b = 1 }  end
	if BSYC.db.options.colors.itemid == nil then BSYC.db.options.colors.itemid = { r = 82/255, g = 211/255, b = 134/255 }  end

	--do DB cleanup check by version number
	if not BSYC.db.options.dbversion or BSYC.db.options.dbversion ~= ver then	
		--self:FixDB()
		BSYC.db.options.dbversion = ver
	end

	--player info
	BSYC.db.player.money = player.money
	BSYC.db.player.class = player.class
	BSYC.db.player.race = player.race
	BSYC.db.player.gender = player.gender
	BSYC.db.player.faction = player.faction
	--we cannot store guild as on login the guild name returns nil
	--https://wow.gamepedia.com/API_GetGuildInfo

	--load the slash commands
	self:LoadSlashCommand()
	
	local ver = GetAddOnMetadata("BagSync","Version") or 0
	
	if BSYC.db.options.enableLoginVersionInfo then
		BSYC:Print("[v|cFF20ff20"..ver.."|r] /bgs, /bagsync")
	end

end

function Data:FixDB(onlyChkGuild)
	BSYC:Print("|cFFFF9900"..L.FixDBComplete.."|r")
end

function Data:LoadSlashCommand()
	--load the keybinding locale information
	BINDING_HEADER_BAGSYNC = "BagSync"
	BINDING_NAME_BAGSYNCBLACKLIST = L.KeybindBlacklist
	BINDING_NAME_BAGSYNCCURRENCY = L.KeybindCurrency
	BINDING_NAME_BAGSYNCGOLD = L.KeybindGold
	BINDING_NAME_BAGSYNCPROFESSIONS = L.KeybindProfessions
	BINDING_NAME_BAGSYNCPROFILES = L.KeybindProfiles
	BINDING_NAME_BAGSYNCSEARCH = L.KeybindSearch
	
	local function ChatCommand(input)
	
		local parts = { (" "):split(input) }
		local cmd, args = strlower(parts[1] or ""), table.concat(parts, " ", 2)

		if string.len(cmd) > 0 then

			if cmd == L.SlashSearch then
				BSYC:GetModule("Search"):StartSearch()
				return true
			elseif cmd == L.SlashGold then
				BSYC:GetModule("Tooltip"):MoneyTooltip()
				return true
			elseif cmd == L.SlashCurrency then
				BSYC:GetModule("Currency").frame:Show()
				return true
			elseif cmd == L.SlashProfiles then
				BSYC:GetModule("Profiles").frame:Show()
				return true
			elseif cmd == L.SlashProfessions then
				BSYC:GetModule("Professions").frame:Show()
				return true
			elseif cmd == L.SlashBlacklist then
				BSYC:GetModule("Blacklist").frame:Show()
				return true
			elseif cmd == L.SlashFixDB then
				self:FixDB()
				return true
			elseif cmd == L.SlashConfig then
				InterfaceOptionsFrame:Show() --has to be here to load the about frame onLoad
				InterfaceOptionsFrame_OpenToCategory(BSYC.aboutPanel) --force the panel to show
				return true
			else
				--do an item search, use the full command to search
				BSYC:GetModule("Search"):StartSearch(input)
				return true
			end

		end
		
		BSYC:Print(L.HelpSearchItemName)
		BSYC:Print(L.HelpSearchWindow)
		BSYC:Print(L.HelpGoldTooltip)
		BSYC:Print(L.HelpCurrencyWindow)
		BSYC:Print(L.HelpProfilesWindow)
		BSYC:Print(L.HelpProfessionsWindow)
		BSYC:Print(L.HelpBlacklistWindow)
		BSYC:Print(L.HelpFixDB)
		BSYC:Print(L.HelpConfigWindow)
	end
	
	BSYC:RegisterChatCommand("bgs", ChatCommand)
	BSYC:RegisterChatCommand("bagsync", ChatCommand)
	
end

function Data:CheckExpiredAuctions()
	--this function will remove expired auctions for all characters in every realm
	local timestampChk = { 30*60, 2*60*60, 12*60*60, 48*60*60 }
	
	local slotItems = {}

	for unitObj in self:IterateUnits(true) do
		if not unitObj.isGuild and unitObj.data.auction then
		
			for x = 1, unitObj.data.auction.count do
				if unitObj.data.auction.bag[x] then
					--check for expired and remove if necessary
					--it's okay if the auction count is showing more then actually stored, it's just used as a means
					--to scan through all our items.  Even if we have only 3 and the count is 6 it will just skip the last 3.
					local link, count, timeleft = strsplit(";", unitObj.data.auction.bag[x])
					
					--only proceed if we have everything to work with, otherwise this auction data is corrupt
					if link and timeleft then
						if tonumber(timeleft) < 1 or tonumber(timeleft) > 4 then timeleft = 4 end --just in case
						--now do the time checks
						local diff = time() - unitObj.data.auction.lastscan
						if diff < timestampChk[tonumber(timeleft)] then
							table.insert(slotItems, unitObj.data.auction.bag[x])
						end
					end
				end
			end
			
			unitObj.data.auction.bag = slotItems
			unitObj.data.auction.count = #slotItems
			
		end
	end
	
end

function Data:IterateUnits(dumpAll)

	local count = BSYC:TableLength(BagSyncDB)
	if not count or count <= 0 then return end

	local player = Unit:GetUnitInfo()
	local previousGuilds = {}
	local argKey, argValue = next(BagSyncDB)
	local i, k, v = 1

	return function()
		while argKey or i <= count do

			if argKey and string.match(argKey, '§*') then
				i = i + 1
				argKey, argValue = next(BagSyncDB, argKey)
			elseif argKey then
				k, v = next(argValue, k)

				if k then
					if v.faction and (v.faction == BSYC.db.player.faction or BSYC.db.options.enableFaction) then
						local isGuild = (k:find('©*') and true) or false
						local isConnectedRealm = (Unit:isConnectedRealm(argKey) and true) or false
						
						--return everything regardless of user settings
						if dumpAll then
							return {realm=argKey, name=k, data=v, isGuild=isGuild, isConnectedRealm=isConnectedRealm}
							
						elseif (argKey == player.realm) or (isConnectedRealm and BSYC.db.options.enableCrossRealmsItems) or (BSYC.db.options.enableBNetAccountItems) then
							
							local skipChk = false
							
							--check for previous listed guilds just in case, because of connected realms (can have same guild on multiple connected realms)
							if isGuild and v.realmKey then
								local XRName = k .. v.realmKey
								if not previousGuilds[XRName] then
									previousGuilds[XRName] = true
								else
									skipChk = true
								end
							end
							
							if not skipChk then
								return {realm=argKey, name=k, data=v, isGuild=isGuild, isConnectedRealm=isConnectedRealm}
							end
						end
					end
				else
					i = i + 1
					argKey, argValue = next(BagSyncDB, argKey)
				end
			else
				--escape clause JUST IN CASE, we don't want an infinite loop
				i = count
			end
			
		end
	end

end