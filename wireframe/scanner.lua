--[[
	scanner.lua
		Scanner module for BagSync, scans bags, bank, currency, etc...
--]]

local BSYC = select(2, ...) --grab the addon namespace
local Scanner = BSYC:NewModule("Scanner")
local Unit = BSYC:GetModule("Unit")

local debugf = tekDebug and tekDebug:GetFrame("BagSync")
local function Debug(...)
    if debugf then
		local debugStr = string.join(", ", tostringall(...))
		local moduleName = string.format("|cFFffff00[%s]|r: ", "Scanner")
		debugStr = moduleName..debugStr
		debugf:AddMessage(debugStr)
	end
end

--https://github.com/tomrus88/BlizzardInterfaceCode/blob/master/Interface/AddOns/Blizzard_VoidStorageUI/Blizzard_VoidStorageUI.lua
local VOID_DEPOSIT_MAX = 9
local VOID_WITHDRAW_MAX = 9
local VOID_STORAGE_MAX = 80
local VOID_STORAGE_PAGES = 2

local MAX_GUILDBANK_SLOTS_PER_TAB = 98
local NUM_SLOTS_PER_GUILDBANK_GROUP = 14
local NUM_GUILDBANK_ICONS_SHOWN = 0
local NUM_GUILDBANK_ICONS_PER_ROW = 10
local NUM_GUILDBANK_ICON_ROWS = 9
local NUM_GUILDBANK_COLUMNS = 7
local MAX_TRANSACTIONS_SHOWN = 21

local FirstEquipped = INVSLOT_FIRST_EQUIPPED
local LastEquipped = INVSLOT_LAST_EQUIPPED

local scannerTooltip = CreateFrame("GameTooltip", "BagSyncScannerTooltip", UIParent, "GameTooltipTemplate")
scannerTooltip:Hide()

--https://wowpedia.fandom.com/wiki/BagID
function Scanner:GetBagSlots(bagType)
	if bagType == "bag" then
		if BSYC.IsRetail then
			return BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS 
		else
			return BACKPACK_CONTAINER, BACKPACK_CONTAINER + NUM_BAG_SLOTS
		end

	elseif bagType == "bank" then
		if BSYC.IsRetail then
			return NUM_TOTAL_EQUIPPED_BAG_SLOTS + 1, NUM_TOTAL_EQUIPPED_BAG_SLOTS + NUM_BANKBAGSLOTS
		else
			return NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS
		end
	end
end

function Scanner:IsBackpack(bagid)
	return bagid == BACKPACK_CONTAINER
end

function Scanner:IsBackpackBag(bagid)
	local minCnt, maxCnt = self:GetBagSlots("bag")
	return bagid >= minCnt and bagid <= maxCnt
end

function Scanner:IsKeyring(bagid)
	return bagid == KEYRING
end

function Scanner:IsBank(bagid)
	return bagid == BANK_CONTAINER
end

function Scanner:IsBankBag(bagid)
	local minCnt, maxCnt = self:GetBagSlots("bank")
	return bagid >= minCnt and bagid <= maxCnt
end

function Scanner:IsReagentBag(bagid)
	return bagid == REAGENTBANK_CONTAINER
end

function Scanner:StartupScans()

	self:SaveEquipment()
	
	local minCnt, maxCnt = self:GetBagSlots("bag")
	for i = minCnt, maxCnt do
		self:SaveBag("bag", i)
	end
	
	self:SaveCurrency()
	
	--cleanup the auction DB
	BSYC:GetModule("Data"):CheckExpiredAuctions()
	
	--cleanup any unlearned tradeskills
	self:CleanupProfessions()
end

function Scanner:SaveBag(bagtype, bagid)
	if not bagtype or not bagid then return end
	if not BSYC.db.player[bagtype] then BSYC.db.player[bagtype] = {} end

	local xGetNumSlots = BSYC.IsRetail and C_Container.GetContainerNumSlots or GetContainerNumSlots
	local xGetContainerInfo = BSYC.IsRetail and C_Container.GetContainerItemInfo or GetContainerItemInfo
	
	if xGetNumSlots(bagid) > 0 then
		
		local slotItems = {}
		
		for slot = 1, xGetNumSlots(bagid) do
			if BSYC.IsRetail then
				local containerInfo = xGetContainerInfo(bagid, slot)
				if containerInfo and containerInfo.hyperlink then
					table.insert(slotItems,  BSYC:ParseItemLink(containerInfo.hyperlink, containerInfo.stackCount or 1))
				end
			else
				local _, count, _,_,_,_, link = xGetContainerInfo(bagid, slot)
				if link then
					table.insert(slotItems,  BSYC:ParseItemLink(link, count))
				end
			end
		end
		
		BSYC.db.player[bagtype][bagid] = slotItems
	else
		BSYC.db.player[bagtype][bagid] = nil
	end
end

function Scanner:SaveEquipment()
	if not BSYC.db.player.equip then BSYC.db.player.equip = {} end
	
	local slotItems = {}
	
	for slot = FirstEquipped, LastEquipped do
		local link = GetInventoryItemLink("player", slot)
		local count =  GetInventoryItemCount("player", slot)
		if link then
			table.insert(slotItems,  BSYC:ParseItemLink(link, count))
		end
	end
	
	BSYC.db.player.equip = slotItems
end

function Scanner:SaveBank(rootOnly)
	if not Unit.atBank then return end
	
	--force scan of bank bag -1, since blizzard never sends updates for it
	self:SaveBag("bank", BANK_CONTAINER)
	
	if not rootOnly then
		local minCnt, maxCnt = self:GetBagSlots("bank")

		for i = minCnt, maxCnt do
			self:SaveBag("bank", i)
		end
		--scan the reagents as part of the bank scan
		self:SaveReagents()
	end
end

function Scanner:SaveReagents()
	if not Unit.atBank or not BSYC.IsRetail then return end
	
	if IsReagentBankUnlocked() then 
		self:SaveBag("reagents", REAGENTBANK_CONTAINER)
	end
end

function Scanner:SaveVoidBank()
	if not Unit.atVoidBank or not BSYC.IsRetail then return end
	if not BSYC.db.player.void then BSYC.db.player.void = {} end
	
	local slotItems = {}
	
	for tab = 1, VOID_STORAGE_PAGES do
		for i = 1, VOID_STORAGE_MAX do
			local link, textureName, locked, recentDeposit, isFiltered = GetVoidItemInfo(tab, i)
			if link then
				table.insert(slotItems, BSYC:ParseItemLink(link))
			end
		end
	end
	
	BSYC.db.player.void = slotItems
end

function Scanner:GetXRGuild()
	if not IsInGuild() then return end
	
	--only return one guild stored from a connected realm list, otherwise we will have multiple entries of the same guild on several connected realms
	local realms = {strsplit(';', Unit:GetRealmKey())}
	local player = Unit:GetUnitInfo()
	
	if #realms > 0 then
		for i = 1, #realms do
			if player.guild and BagSyncDB[realms[i]] and BagSyncDB[realms[i]][player.guild] then
				return BagSyncDB[realms[i]][player.guild]
			end
		end
	end
	
	if not BSYC.db.realm[player.guild] then BSYC.db.realm[player.guild] = {} end
	return BSYC.db.realm[player.guild]
end

function Scanner:SaveGuildBank()
	if not Unit.atGuildBank or BSYC.IsClassic then return end
	if Scanner.isScanningGuild then return end

	local numTabs = GetNumGuildBankTabs()
	local slotItems = {}
	Scanner.isScanningGuild = true
	
	for tab = 1, numTabs do
		local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = GetGuildBankTabInfo(tab)
		--if we don't check for isViewable we get a weirdo permissions error for the player when they attempt it
		if isViewable then
			for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
				local link = GetGuildBankItemLink(tab, slot)
				if link then
					local speciesID
					local shortID = BSYC:GetShortItemID(link)
					local _, count = GetGuildBankItemInfo(tab, slot)
					
					--check if it's a battle pet cage or something, pet cage is 82800.  This is the placeholder for battle pets
					--if it's a battlepet link it will be parsed anyways in ParseItemLink
					if shortID and tonumber(shortID) == 82800 then
						speciesID = scannerTooltip:SetGuildBankItem(tab, slot)
						scannerTooltip:Hide()
					end
					if speciesID then
						link = BSYC:CreateFakeBattlePetID(nil, nil, speciesID)
					else
						link = BSYC:ParseItemLink(link, count)
					end
					table.insert(slotItems, link)
				end
			end
		end
	end

	local guildDB = self:GetXRGuild()
	if guildDB then
		guildDB.bag = slotItems
		guildDB.money = GetGuildBankMoney()
		guildDB.faction = Unit:GetUnitInfo().faction
		guildDB.realmKey = Unit:GetRealmKey()
	end
	
	Scanner.isScanningGuild = false
end

function Scanner:SaveMailbox(isShow)
	if not Unit.atMailbox or not BSYC.options.enableMailbox then return end
	if not BSYC.db.player.mailbox then BSYC.db.player.mailbox = {} end
	
	if self.isCheckingMail then return end --prevent overflow from CheckInbox()
	self.isCheckingMail = true

	--used to initiate mail check from server, for some reason GetInboxNumItems() returns zero sometimes
	--even though the user has mail in the mailbox.  This can be attributed to lag.
	if isShow then
		--only do this once it causes a continously mail spam loop in Classic and we can avoid spam as well in Retail
		CheckInbox()
	end
	
	local slotItems = {}
	local numInbox = GetInboxNumItems()

	--scan the inbox
	if (numInbox > 0) then
		for mailIndex = 1, numInbox do
			for i = 1, ATTACHMENTS_MAX_RECEIVE do
				local name, itemID, itemTexture, count, quality, canUse = GetInboxItem(mailIndex, i)
				local link = GetInboxItemLink(mailIndex, i)
				local byPass = false
				if name and link then
					--check for battle pet cages
					if BSYC.IsRetail and itemID and itemID == 82800 then
						local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = scannerTooltip:SetInboxItem(mailIndex)
						scannerTooltip:Hide()
						
						if speciesID then
							link = BSYC:CreateFakeBattlePetID(nil, nil, speciesID)
							byPass = true
						end
					end
					if not byPass then
						link = BSYC:ParseItemLink(link, count)
					end
					table.insert(slotItems, link)
				end
			end
		end
	end
	
	BSYC.db.player.mailbox = slotItems

	self.isCheckingMail = false
end

function Scanner:SaveAuctionHouse()
	if not Unit.atAuction or not BSYC.options.enableAuction then return end
	if not BSYC.db.player.auction then BSYC.db.player.auction = {} end

	local slotItems = {}
	
	if BSYC.IsRetail then
		local numActiveAuctions = C_AuctionHouse.GetNumOwnedAuctions()
			
		--scan the auction house
		if (numActiveAuctions > 0) then
			for ahIndex = 1, numActiveAuctions do
			
				--https://wow.gamepedia.com/API_C_AuctionHouse.GetOwnedAuctionInfo
				local itemObj = C_AuctionHouse.GetOwnedAuctionInfo(ahIndex)
				
				--we only want active auctions not sold one.  So check itemObj.status
				if itemObj and itemObj.timeLeftSeconds and itemObj.status == 0 then

					local expTime = time() + itemObj.timeLeftSeconds -- current Time + advance time in seconds to get expiration time and date
					local itemCount = itemObj.quantity or 1
					local parseLink = ""
					
					if itemObj.itemLink then
						parseLink = BSYC:ParseItemLink(itemObj.itemLink, itemCount)
					elseif itemObj.itemKey and itemObj.itemKey.itemID then
						parseLink = BSYC:ParseItemLink(itemObj.itemKey.itemID, itemCount)
					end
					
					--we are going to make the third field an identifier field, so we can know what it is for future reference
					--for now auction house will be 1, with 4th field being expTime
					if itemCount <= 1 then
						parseLink = parseLink..";1;1;"..expTime
					else
						parseLink = parseLink..";1;"..expTime
					end

					table.insert(slotItems, parseLink)
				end
			end
		end
		
	else
		--this is for WOW Classic Auction House
		local numActiveAuctions = GetNumAuctionItems("owner")
		local timestampChk = { 30*60, 2*60*60, 12*60*60, 48*60*60 }
		
		--scan the auction house
		if (numActiveAuctions > 0) then
			for ahIndex = 1, numActiveAuctions do
				local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner, saleStatus  = GetAuctionItemInfo("owner", ahIndex)
				if name then
					local link = GetAuctionItemLink("owner", ahIndex)
					local timeLeft = GetAuctionItemTimeLeft("owner", ahIndex)
					if link and timeLeft and tonumber(timeLeft) then
						count = (count or 1)
						timeLeft = tonumber(timeLeft)
						if not timeLeft or timeLeft < 1 or timeLeft > 4 then timeLeft = 4 end --just in case				
						--since classic doesn't return the exact time on old auction house, we got to add it manually
						--it only does short, long and very long
						local expireTime = time() + timestampChk[timeLeft]
						local parseLink = BSYC:ParseItemLink(link, count)
						--we are going to make the third field an identifier field, so we can know what it is for future reference
						--for now auction house will be 1, with 4th field being expTime
						if count <= 1 then
							parseLink = parseLink..";1;1;"..expireTime
						else
							parseLink = parseLink..";1;"..expireTime
						end
						
						table.insert(slotItems, parseLink)
					end
				end
			end
		end
		
	end
	
	BSYC.db.player.auction.bag = slotItems
	BSYC.db.player.auction.count = #slotItems or 0
	BSYC.db.player.auction.lastscan = time()
end

function Scanner:SaveCurrency()
	if not BSYC.IsRetail then return end
	if Unit:InCombatLockdown() then return end
	
	local lastHeader
	local slotItems = {}
	
	--first lets expand everything just in case
	local whileChk = true
	local exitCount = 0
	
	while whileChk do
		whileChk = false -- turn the while loop off, it will only continue if we found an unexpanded header until all are expanded
		exitCount = exitCount + 1 --catch all to prevent endless loop
		
		for k=1, C_CurrencyInfo.GetCurrencyListSize() do
			local headerCheck = C_CurrencyInfo.GetCurrencyListInfo(k)
			if headerCheck.isHeader and not headerCheck.isHeaderExpanded then
				C_CurrencyInfo.ExpandCurrencyList(k, true)
				whileChk = true
			end
		end
		
		--this is a catch all in case something happens above and for some reason it's always true
		if exitCount >= 50 then
			whileChk = false --just in case
			break
		end
	end
	
	for i=1, C_CurrencyInfo.GetCurrencyListSize() do
		local currencyinfo = C_CurrencyInfo.GetCurrencyListInfo(i)
		local link = C_CurrencyInfo.GetCurrencyListLink(i)
		local currencyID = BSYC:GetShortCurrencyID(link)
		
		if currencyinfo.name then
			if currencyinfo.isHeader then
				lastHeader = currencyinfo.name
			elseif not currencyinfo.isHeader and currencyID then
				slotItems[currencyID] = slotItems[currencyID] or {}
				slotItems[currencyID].name = currencyinfo.name
				slotItems[currencyID].header = lastHeader
				slotItems[currencyID].count = currencyinfo.quantity
				slotItems[currencyID].icon = currencyinfo.iconFileID
			end
		end
	end
	
	BSYC.db.player.currency = slotItems
end
	
function Scanner:SaveProfessions()
	if not BSYC.IsRetail then return end
	
	--we don't want to do linked tradeskills, guild tradeskills, or a tradeskill from an NPC
	if _G.C_TradeSkillUI.IsTradeSkillLinked() or _G.C_TradeSkillUI.IsTradeSkillGuild() or _G.C_TradeSkillUI.IsNPCCrafting() then return end
	
	local recipeData = {}
	local tmpRecipe = {}
	local catCheck, catCleanup = {}, {}
	local orderIndex = 0
	
	Scanner.recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
	--invert the table, forcing the value to be the key and the key the value, inverted[v] = k  (see TableUtil.lua)
	Scanner.invertedRecipeIDs = tInvert(Scanner.recipeIDs)
	
	--https://wowpedia.fandom.com/wiki/API_C_TradeSkillUI.GetBaseProfessionInfo
	--https://wowpedia.fandom.com/wiki/API_C_TradeSkillUI.GetTradeSkillLineInfoByID
	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo()
	
	local parentSkillLineID, parentSkillLineName

	if not baseInfo or not baseInfo.professionID then
		local professionInfo = C_TradeSkillUI.GetChildProfessionInfo()
		if not professionInfo or not professionInfo.parentProfessionID then return end
		
		parentSkillLineID = professionInfo.parentProfessionID
		parentSkillLineName = professionInfo.parentProfessionName
	else
		parentSkillLineID = baseInfo.professionID
		parentSkillLineName = baseInfo.professionName
	end
	
	--https://wowpedia.fandom.com/wiki/API_C_TradeSkillUI.GetTradeSkillLineInfoByID
	--info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)

	if parentSkillLineID and parentSkillLineName then
	
		--create the categories, sometimes we have professions with no recipes.  We want to store this anyways
		local categories = {C_TradeSkillUI.GetCategories()}
		
		for i, categoryID in ipairs(categories) do
			local categoryData = C_TradeSkillUI.GetCategoryInfo(categoryID)

			if categoryData and categoryData.categoryID and categoryData.skillLineCurrentLevel and categoryData.skillLineCurrentLevel > 0 then

				if not BSYC.db.player.professions[parentSkillLineID] then
					BSYC.db.player.professions[parentSkillLineID] = BSYC.db.player.professions[parentSkillLineID] or {}
					BSYC.db.player.professions[parentSkillLineID].name = parentSkillLineName
				end
				
				local parentIDSlot = BSYC.db.player.professions[parentSkillLineID]
				parentIDSlot.categories = parentIDSlot.categories or {}
				
				--Legion Engineering, Cateclysm Engineering, etc...
				parentIDSlot.categories[categoryID] = parentIDSlot.categories[categoryID] or {}
				local subCatSlot = parentIDSlot.categories[categoryID]

				--always overwrite because we can have a different level or name then last time
				subCatSlot.name = categoryData.name
				subCatSlot.skillLineCurrentLevel = categoryData.skillLineCurrentLevel
				subCatSlot.skillLineMaxLevel = categoryData.skillLineMaxLevel

				if not catCheck[categoryID] then
					catCheck[categoryID] = true
					orderIndex = orderIndex + 1
					subCatSlot.orderIndex = orderIndex
				end
						
			end
		end
	
		--store the recipes
		for i = 1, #Scanner.recipeIDs do
		
			if C_TradeSkillUI.GetRecipeInfo(Scanner.recipeIDs[i]) then
			
				--grab the info in a table
				recipeData = C_TradeSkillUI.GetRecipeInfo(Scanner.recipeIDs[i])
				
				local categoryID = recipeData.categoryID
				local categoryData = C_TradeSkillUI.GetCategoryInfo(categoryID)

				--grab the parent name, Engineering, Herbalism, Blacksmithing, etc...
				if recipeData.learned and categoryData and categoryData.categoryID == categoryID and categoryData.parentCategoryID then

					--grab categories, Legion Engineering, Cateclysm Engineering, etc...
					local subCatData = C_TradeSkillUI.GetCategoryInfo(categoryData.parentCategoryID)
					
					--make sure we have something to work with, we don't want to store stuff that doesn't have levels
					if subCatData and subCatData.categoryID == categoryData.parentCategoryID then

						if not BSYC.db.player.professions[parentSkillLineID] then
							BSYC.db.player.professions[parentSkillLineID] = BSYC.db.player.professions[parentSkillLineID] or {}
							BSYC.db.player.professions[parentSkillLineID].name = parentSkillLineName
						end

						local parentIDSlot = BSYC.db.player.professions[parentSkillLineID]
						parentIDSlot.categories = parentIDSlot.categories or {}
						
						--store the sub category information, Legion Engineering, Cateclysm Engineering, etc...
						parentIDSlot.categories[subCatData.categoryID] = parentIDSlot.categories[subCatData.categoryID] or {}
						local subCatSlot = parentIDSlot.categories[subCatData.categoryID]

						--always overwrite because we can have a different level or name then last time
						subCatSlot.name = subCatData.name
						subCatSlot.skillLineCurrentLevel = subCatData.skillLineCurrentLevel
						subCatSlot.skillLineMaxLevel = subCatData.skillLineMaxLevel
						
						--cleanout the recipe list first time entering the category, otherwise it will constantly have repeats
						if not catCleanup[subCatData.categoryID] then
							catCleanup[subCatData.categoryID] = true
							subCatSlot.recipes = nil
						end
						if not subCatSlot.orderIndex then
							orderIndex = orderIndex + 1
							subCatSlot.orderIndex = orderIndex
						end
						
						--now store the recipe information, but make sure we don't already have the recipe stored
						--we have to do this as sometimes the recipe is scanned multiple times.  It will get refreshed once the profession is saved again though.
						--so technically it will always be up to date
						if not tmpRecipe[recipeData.recipeID] then
							subCatSlot.recipes = (subCatSlot.recipes or "").."|"..recipeData.recipeID
							tmpRecipe[recipeData.recipeID] = true
						end
						
					end
				
				end
				
			end
			
		end
		
	end

	--grab archaeology, fishing
	--first aid was removed in battle for azeroth
	local prof1, prof2, archaeology, fishing, cooking, firstAid = GetProfessions()
	
	if archaeology then
		local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(archaeology)
		BSYC.db.player.professions[skillLine] = BSYC.db.player.professions[skillLine] or {}
		BSYC.db.player.professions[skillLine].name = name
		BSYC.db.player.professions[skillLine].skillLineCurrentLevel = rank
		BSYC.db.player.professions[skillLine].skillLineMaxLevel = maxRank
		BSYC.db.player.professions[skillLine].secondary = true --mark is as a secondary profession
	end
	
	if fishing then
		local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(fishing)
		BSYC.db.player.professions[skillLine] = BSYC.db.player.professions[skillLine] or {}
		BSYC.db.player.professions[skillLine].name = name
		BSYC.db.player.professions[skillLine].skillLineCurrentLevel = rank
		BSYC.db.player.professions[skillLine].skillLineMaxLevel = maxRank
		BSYC.db.player.professions[skillLine].secondary = true --mark is as a secondary profession
	end
	
	--as a precaution lets do a tradeskill cleanup just in case
	self:CleanupProfessions()
end

function Scanner:CleanupProfessions()
	if not BSYC.IsRetail then return end
	
	--lets remove unlearned tradeskills
	local tmpList = {}

	for i = 1, select("#", GetProfessions()) do
		local prof = select(i, GetProfessions())
		if prof then
			local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(prof)
			if name and skillLine then
				tmpList[skillLine] = name
			end
		end
	end
	
	for k, v in pairs(BSYC.db.player.professions) do
		if not tmpList[k] then
			--it's an unlearned or unused tradeskill, lets remove it
			BSYC.db.player.professions[k] = nil
		end
	end
end

function Scanner:ParseCraftedInfo(unitTarget, castGUID, spellID)
	if not BSYC.IsRetail then return end
	--only do this when they are not at a bank
	if Unit.atBank then return end
	if unitTarget ~= "player" then return end --only do the player crafted stuff
	if not Scanner.recipeIDs or not Scanner.invertedRecipeIDs then return end
	
	--reset
	Scanner.reagentCount = {}

	--use the inverted since the spellID is the key
    if Scanner.invertedRecipeIDs[spellID] then
	
		local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(spellID, false)
		
		if recipeSchematic then
			for slotIndex, reagentSlotSchematic in ipairs(recipeSchematic.reagentSlotSchematics) do
				if reagentSlotSchematic.itemID then
					Scanner.reagentCount[reagentSlotSchematic.itemID] = 0
				elseif reagentSlotSchematic.reagents then
					for reagentIndex, reagentInfo in ipairs(reagentSlotSchematic.reagents) do
						if reagentInfo.itemID then
							Scanner.reagentCount[reagentInfo.itemID] = 0
						end
					end
				end
			end
		end
		
    end
	
	if BSYC:GetHashTableLen(Scanner.reagentCount) < 1 then Scanner.reagentCount = nil end
end

function Scanner:SaveCraftedReagents()
	if not BSYC.IsRetail then return end
	--only do this when they are not at a bank
	if Unit.atBank then return end

	--don't do anything if we have nothing to work with
	if not Scanner.reagentCount or BSYC:GetHashTableLen(Scanner.reagentCount) < 1 then return end

	---------------------------------------------------
	--First lets remove the stored count in both Bank and Reagents
	---------------------------------------------------
	local bagtype = "bank"
	local rootItems = {}
	local slotItems = {}
	local bankCount = 0
	
	--BANK
	if not BSYC.db.player[bagtype] then BSYC.db.player[bagtype] = {} end
	
	for bagID, bagData in pairs(BSYC.db.player[bagtype]) do
	
		slotItems = {}
	
		--search individual bank bags
		for i=1, #bagData do
			--do we even have something to work with?
			if bagData[i] then
				local itemID, count, identifier = strsplit(";", bagData[i])
				itemID = tonumber(itemID)
				
				--only save if it's not one of the reagents that was used
				if itemID and not Scanner.reagentCount[itemID] then
					table.insert(slotItems, bagData[i])
				end
			end
		end
		BSYC.db.player[bagtype][bagID] = slotItems
	end
	
	--REAGENTS
	if IsReagentBankUnlocked() then
		bagtype = "reagents"
		
		if not BSYC.db.player[bagtype] then BSYC.db.player[bagtype] = {} end
		
		for bagID, bagData in pairs(BSYC.db.player[bagtype]) do
		
			slotItems = {}
		
			--search individual reagents bags
			for i=1, #bagData do
				--do we even have something to work with?
				if bagData[i] then
					local itemID, count, identifier = strsplit(";", bagData[i])
					itemID = tonumber(itemID)
					
					--only save if it's not one of the reagents that was used
					if itemID and not Scanner.reagentCount[itemID] then
						table.insert(slotItems, bagData[i])
					end
				end
			end
			BSYC.db.player[bagtype][bagID] = slotItems
		end
	end
	
	---------------------------------------------------
	--NOW lets add them back in with new counts at the root of each BagType
	---------------------------------------------------
	
	--BANK
	bagtype = "bank"
	
	--now lets add them manually to the root bank location (BANK_CONTAINER), create it if it's not found
	rootItems = BSYC.db.player[bagtype][BANK_CONTAINER] or {}
	
	for k, v in pairs(Scanner.reagentCount) do
	
		--for some reason even if you turn off useReagent, it still calculates it in the total bank amount
		--so we have to subtract it to get the true bank amount
		
		--check for reagentBank count
		local regCount = GetItemCount(k, false, false, true)
		bankCount = GetItemCount(k, true, false, false) --only search the bank and not reagent bank

		if bankCount and bankCount > 0 then
		
			--now compensate if we have reagents to work with
			if regCount and regCount > 0 then
				bankCount = bankCount - regCount

				--check for negative and adjust
				if bankCount < 0 then
					bankCount = bankCount * -1
				end
			end
			
			--only store if after computations its still above 0
			if bankCount and bankCount > 0 then
				table.insert(rootItems,  BSYC:ParseItemLink(k, bankCount))
			end
		end
	end
	
	--now save it back to the bank root
	BSYC.db.player[bagtype][BANK_CONTAINER] = rootItems
	

	--REAGENTS
	bagtype = "reagents"
	
	--now lets add them manually to the root bank location (REAGENTBANK_CONTAINER), create it if it's not found
	rootItems = BSYC.db.player[bagtype][REAGENTBANK_CONTAINER] or {}
	
	for k, v in pairs(Scanner.reagentCount) do
	
		bankCount = GetItemCount(k, false, false, true) --only search reagent bank
		
		if bankCount and bankCount > 0 then
			table.insert(rootItems,  BSYC:ParseItemLink(k, bankCount))
		end
	end
	
	--now save it back to the bank root
	BSYC.db.player[bagtype][REAGENTBANK_CONTAINER] = rootItems
	
	--reset our stored reagent count so that it doesn't mess up the regular bank scans
	Scanner.reagentCount = nil
	
	--set the tooltip to be refreshed so that it displays the new values
	BSYC.refreshTooltip = true
	
end
