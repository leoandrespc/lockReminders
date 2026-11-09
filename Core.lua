local ADDON = ...

local WARLOCK = "WARLOCK"
local CREATE_HEALTHSTONE = 6201
local SACRIFICE = 108503
local HEALTHSTONES = {
	5512, 5511, 5509, 5510, 9421,
	22103, 22104, 22105,
	36889, 36890, 36891, 36892, 36893, 36894,
	224464,
}
local BROWSER_LIMIT = 80

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

local GENERIC_USE = {
	comer = true,
	beber = true,
	eating = true,
	drinking = true,
	eat = true,
	drink = true,
}

local db
local frame
local rows = {}
local panel
local minimapButton
local searchBox
local scroll
local scrollChild
local scrollBar
local emptyLabel
local footer
local modeHint
local raidCheck
local tabs
local rowPool = {}
local headerPool = {}
local usedRows = 0
local usedHeaders = 0
local currentEntries = {}
local currentSignature
local activeTab = "powers"
local addScope = "always"
local syncingScroll = false
local listTicker
local spellbookCache
local spellbookCacheAt = 0
local spellbookAllCache
local spellbookAllCacheAt = 0
local linkHooked = false
local arranging = false
local dragKey
local layoutRoot
local orderPool = {}
local sizeValue
local colsValue
local lockButton
local frameButton
local talentFrame
local foodFrame
LockRemindersMiss = { moving = false, casts = {} }
LockRemindersCD = { moving = false, icons = {}, states = {}, order = {} }
LockRemindersMisc = { speedMoving = false }
LockRemindersSoul = { moving = false, trackMoving = false, missing = false, rows = {} }
LockRemindersPet = { moving = false, lockAt = 0, seduction = {} }
LockRemindersSoulCast = {
	[693] = true, [20752] = true, [20755] = true, [20756] = true, [20757] = true, [27238] = true, [47884] = true,
	[20707] = true, [20762] = true, [20763] = true, [20764] = true, [20765] = true, [27239] = true, [47883] = true,
}
LockRemindersSoulAura = {
	[20707] = true, [20762] = true, [20763] = true, [20764] = true, [20765] = true, [27239] = true, [47883] = true,
}
LockRemindersSoulItem = {
	[5232] = true, [16892] = true, [16893] = true, [16895] = true, [16896] = true, [22116] = true, [36895] = true,
}

function LockRemindersClassFile()
	if not UnitClass then
		return nil
	end
	local ok, _, class = pcall(UnitClass, "player")
	if not ok or not class or (LockRemindersSecret and LockRemindersSecret(class)) then
		return nil
	end
	return class
end

function LockRemindersIsWarlock()
	return LockRemindersClassFile() == "WARLOCK"
end

function LockRemindersHasClassPet()
	local class = LockRemindersClassFile()
	return class == "WARLOCK" or class == "HUNTER"
end
local talentBar
local talentSizeText
local talentHoldText
local talentMoveButton
local talentMoving = false
local talentSeen
local talentRecent = {}
local arrangeButton
local layoutEmpty

local UpdateListNow
local ShowLayout
local HideLayout
local SpellAliases

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9LockReminders|r " .. text)
end

local function Normalize(text)
	text = tostring(text or ""):lower()
	text = text:gsub("á", "a"):gsub("é", "e"):gsub("í", "i"):gsub("ó", "o"):gsub("ú", "u"):gsub("ü", "u"):gsub("ñ", "n")
	return text
end

local function Paint(widget, r, g, b, a, br, bg, bb, ba)
	widget:SetBackdrop(BACKDROP)
	widget:SetBackdropColor(r, g, b, a or 1)
	widget:SetBackdropBorderColor(br or r, bg or g, bb or b, ba or 1)
end

local function TryElvUI(widget)
	if ElvUI and widget.SetTemplate then
		return pcall(widget.SetTemplate, widget, "Transparent")
	end
	return false
end

function Blocked()
	if UnitIsDeadOrGhost("player") then
		return true
	end
	if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
		return true
	end
	if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
		return true
	end
	local _, instanceType = IsInInstance()
	return instanceType == "arena" or instanceType == "pvp"
end

local function Restricted()
	if InCombatLockdown() then
		return true
	end
	return Blocked()
end

local function KnowsSpell(spellID)
	local ok, known = pcall(function()
	if IsPlayerSpell and IsPlayerSpell(spellID) then
		return true
	end
	if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
			local inBook = C_SpellBook.IsSpellInSpellBook(spellID)
			if issecretvalue and issecretvalue(inBook) then
				return true
			end
			return inBook and true or false
	end
	return false
	end)
	if not ok or (issecretvalue and issecretvalue(known)) then
		return true
	end
	return known and true or false
end

local function HasAura(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return nil
	end
	local absent = false
	local function note(ok, aura)
		if not ok then
			return nil
		end
		-- Forever returns a sealed aura object while the buff is up.
		if aura ~= nil and aura ~= false then
			return true
		end
		absent = true
		return nil
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
		if note(ok, aura) then
			return true
		end
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", spellID, "HELPFUL")
		if note(ok, aura) then
			return true
		end
	end
	local wanted
	local aliases = SpellAliases(spellID)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		if ok and info and type(info.name) == "string" and info.name ~= "" and not (issecretvalue and issecretvalue(info.name)) then
			wanted = info.name:lower()
		end
	end
	if not wanted and GetSpellInfo then
		local ok, name = pcall(GetSpellInfo, spellID)
		if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
			wanted = name:lower()
		end
	end
	local function sameID(value)
		if value == nil then
			return false
		end
		if LockRemindersSameSpell then
			for index = 1, #aliases do
				if LockRemindersSameSpell(value, aliases[index]) then
					return true
				end
			end
		end
		if issecretvalue and issecretvalue(value) then
			return false
		end
		value = tonumber(value)
		return value == spellID and value > 0 and value < 1000000
	end
	local function scan(reader, filter)
		if type(reader) ~= "function" then
			return nil
		end
		local saw = false
		local secret = false
		for index = 1, 40 do
			local packed
			if filter then
				packed = { pcall(reader, "player", index, filter) }
			else
				packed = { pcall(reader, "player", index) }
			end
			if not packed[1] then
				return nil
			end
			local name = packed[2]
			if (name == nil or name == false or name == "") and not (issecretvalue and issecretvalue(name)) then
				if secret then
					return nil
				end
				return false
			end
			saw = true
			local nameSecret = issecretvalue and issecretvalue(name)
			if nameSecret then
				secret = true
			elseif wanted and type(name) == "string" and name:lower() == wanted then
				return true
			elseif wanted and LockRemindersTalentNameMatch and LockRemindersTalentNameMatch(name, wanted) then
				return true
			end
			for slot = 3, #packed do
				if sameID(packed[slot]) then
					return true
				end
				if issecretvalue and issecretvalue(packed[slot]) then
					secret = true
				end
			end
		end
		if secret or not saw then
			return nil
		end
		return false
	end
	local listHidden = false
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
			if not ok then
				listHidden = true
				break
			end
			if aura == nil or aura == false then
				break
			end
			local id, name
			pcall(function()
				id = aura.spellId or aura.spellID
				name = aura.name
			end)
			if sameID(id) then
				return true
			end
			if issecretvalue and issecretvalue(aura) then
				listHidden = true
			elseif issecretvalue and (issecretvalue(id) or issecretvalue(name)) then
				listHidden = true
			elseif wanted and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
				if name:lower() == wanted or (LockRemindersTalentNameMatch and LockRemindersTalentNameMatch(name, wanted)) then
					return true
				end
			end
		end
	end
	local found = scan(UnitBuff)
	if found == true then
		return true
	end
	if found == nil then
		found = scan(UnitAura, "HELPFUL")
	end
	if found == true then
		return true
	end
	if found == false then
		return false
	end
	if absent and not listHidden and not InCombatLockdown() then
		return false
	end
	return nil
end

local function Plain(value)
	if value == nil or value == false then
		return nil
	end
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	if type(value) ~= "string" and type(value) ~= "number" then
		return nil
	end
	if value == "" then
		return nil
	end
	return value
end

local function SpellName(spellID)
	local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	local name = ok and info and Plain(info.name)
	if name then
		return name
	end
	if C_Spell.RequestLoadSpellData then
		C_Spell.RequestLoadSpellData(spellID)
	end
	return "Spell " .. spellID
end

local function SpellDisplayName(spellID, fallback)
	if fallback and fallback ~= "" and not (issecretvalue and issecretvalue(fallback)) then
		return fallback
	end
	local info = C_Spell.GetSpellInfo(spellID)
	if info and info.name and info.name ~= "" then
		return info.name
	end
	return nil
end

local function PlainNumber(value)
	local ok, kind = pcall(type, value)
	if not ok or (kind ~= "number" and kind ~= "string") or value == "" then
		return nil
	end
	if issecretvalue then
		local secretOk, secret = pcall(issecretvalue, value)
		if not secretOk or secret then
			return nil
		end
	end
	return value
end

local function SpellIcon(spellID)
	if C_Spell and C_Spell.GetSpellTexture then
		local ok, value = pcall(C_Spell.GetSpellTexture, spellID)
		value = ok and PlainNumber(value)
		if value then
			return value
		end
	end
	if GetSpellTexture then
		local ok, value = pcall(GetSpellTexture, spellID)
		value = ok and PlainNumber(value)
		if value then
			return value
		end
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		if ok and type(info) == "table" then
			local iconID = PlainNumber(info.iconID) or PlainNumber(info.originalIconID)
			if iconID then
				return iconID
			end
		end
	end
	return 134400
end

local function ItemCount(itemID)
	local count = (C_Item.GetItemCount or GetItemCount)(itemID)
	return count or 0
end

local itemNameCache = {}

local function RememberItemName(itemID, name)
	local ok, plain = pcall(Plain, name)
	itemID = tonumber(itemID)
	if ok and itemID and plain then
		itemNameCache[itemID] = plain
	end
end

local function NameFromLink(link)
	local ok, name = pcall(function()
		if type(link) ~= "string" or link == "" then
			return nil
		end
		if issecretvalue and issecretvalue(link) then
			return nil
		end
		return link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
	end)
	if not ok then
		return nil
	end
	return Plain(name)
end

local RequestItem

local function ItemName(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	if itemNameCache[itemID] then
		return itemNameCache[itemID]
	end
	if C_Item.GetItemInfo then
		local ok, name, link = pcall(C_Item.GetItemInfo, itemID)
		if ok then
			RememberItemName(itemID, name)
			RememberItemName(itemID, NameFromLink(link))
		end
	end
	if not itemNameCache[itemID] and C_Item.GetItemNameByID then
		local ok, name = pcall(C_Item.GetItemNameByID, itemID)
		if ok then
			RememberItemName(itemID, name)
		end
	end
	if not itemNameCache[itemID] and C_Item.GetItemName then
		local ok, name = pcall(C_Item.GetItemName, itemID)
		if ok then
			RememberItemName(itemID, name)
		end
	end
	if not itemNameCache[itemID] and GetItemInfo then
		local ok, name, link = pcall(GetItemInfo, itemID)
		if ok then
			RememberItemName(itemID, name)
			RememberItemName(itemID, NameFromLink(link))
		end
	end
	if itemNameCache[itemID] then
		return itemNameCache[itemID]
	end
	RequestItem(itemID)
	return nil
end

local function ItemIcon(itemID)
	local getter = C_Item and C_Item.GetItemIconByID or GetItemIcon
	if not getter then
		return nil
	end
	local ok, icon = pcall(getter, itemID)
	return ok and PlainNumber(icon) or nil
end

local pendingItems = {}

RequestItem = function(itemID)
	itemID = tonumber(itemID)
	if not itemID or itemNameCache[itemID] or pendingItems[itemID] then
		return
	end
	pendingItems[itemID] = true
	if C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	if not (Item and Item.CreateFromItemID) then
		return
	end
	local ok, item = pcall(Item.CreateFromItemID, Item, itemID)
	if not ok or not item or not item.ContinueOnItemLoad then
		return
	end
	item:ContinueOnItemLoad(function()
		pendingItems[itemID] = nil
		local readOk, name = pcall(function()
			return item:GetItemName()
		end)
		if readOk then
			RememberItemName(itemID, name)
		end
		if itemNameCache[itemID] and UpdateListNow then
			pcall(UpdateListNow)
		end
	end)
end

local function HasHealthstone()
	for i = 1, #HEALTHSTONES do
		local ok, count = pcall(ItemCount, HEALTHSTONES[i])
		if ok and type(count) == "number" and count > 0 then
			return true
		end
	end
	if LockRemindersHasHealthstone then
		return LockRemindersHasHealthstone()
	end
	return false
end

local function HasLivePet()
	return UnitExists("pet") and not UnitIsDead("pet")
end

local function FoodAuraIDs()
	local seen = {}
	local list = {}
	local function add(spellID)
		spellID = tonumber(spellID)
		if spellID and spellID > 0 and not seen[spellID] then
			seen[spellID] = true
			list[#list + 1] = spellID
		end
	end
	for spellID in pairs(db.food) do
		add(spellID)
	end
	for _, value in pairs(db.foodItems) do
		add(value)
	end
	return list
end

local function FoodLabel()
	local icon, text
	local count = 0
	for itemID in pairs(db.foodItems) do
		count = count + 1
		icon = ItemIcon(itemID) or icon
		text = ItemName(itemID) or text
	end
	for spellID in pairs(db.food) do
		count = count + 1
		icon = icon or SpellIcon(spellID)
		text = text or SpellName(spellID)
	end
	if count == 1 and text then
		return icon or 134062, text
	end
	return icon or 134062, "Food"
end

local function NormalizeScope(where)
	where = type(where) == "string" and where:lower() or "always"
	if where == "raid" then
		return "raid"
	end
	if where == "party" then
		return "party"
	end
	if where == "instance" or where == "dungeon" then
		return "instance"
	end
	return "always"
end

function LockRemindersInContentInstance()
	if not IsInInstance then
		return false
	end
	local ok, inInstance, instanceType = pcall(IsInInstance)
	if not ok then
		return false
	end
	if LockRemindersSecret and (LockRemindersSecret(inInstance) or LockRemindersSecret(instanceType)) then
		return false
	end
	if inInstance ~= true then
		return false
	end
	return instanceType == "party" or instanceType == "raid"
end

local function ScopeFlags(where)
	if type(where) == "table" then
		return where.always and true or false, where.party and true or false, where.raid and true or false, where.instance and true or false
	end
	local mode = NormalizeScope(where)
	if mode == "raid" then
		return false, false, true, false
	end
	if mode == "party" then
		return false, true, false, false
	end
	if mode == "instance" then
		return false, false, false, true
	end
	return true, false, false, false
end

local function ScopeLabel(where)
	local always, party, raid, instance = ScopeFlags(where)
	local parts = {}
	if raid then
		parts[#parts + 1] = "Raid"
	end
	if party then
		parts[#parts + 1] = "Party"
	end
	if instance then
		parts[#parts + 1] = "Instance"
	end
	if always then
		parts[#parts + 1] = "Always"
	end
	if #parts == 0 then
		return "Off"
	end
	local label = table.concat(parts, ", ")
	if type(where) == "table" and where.combat then
		label = label .. ", Combat"
	end
	return label
end

local function NextScope(where)
	where = NormalizeScope(where)
	if where == "always" then
		return "party"
	end
	if where == "party" then
		return "raid"
	end
	if where == "raid" then
		return "instance"
	end
	return "always"
end

local function ScopeActive(where)
	local always, party, raid, instance = ScopeFlags(where)
	if always then
		return true
	end
	if raid and IsInRaid() then
		return true
	end
	if party and IsInGroup() and not IsInRaid() then
		return true
	end
	if instance and LockRemindersInContentInstance() then
		return true
	end
	return false
end

local function AuraScope(spellID)
	return db.auras[spellID] or db.auras[tostring(spellID)]
end

SpellAliases = function(spellID)
	local list = {}
	local seen = {}
	local function add(id)
		id = tonumber(id)
		if not id or id <= 0 or seen[id] then
			return
		end
		if issecretvalue and issecretvalue(id) then
			return
		end
		seen[id] = true
		list[#list + 1] = id
	end
	add(spellID)
	if C_Spell and C_Spell.GetBaseSpell then
		pcall(function()
			add(C_Spell.GetBaseSpell(spellID))
		end)
	end
	if C_Spell and C_Spell.GetOverrideSpell then
		pcall(function()
			add(C_Spell.GetOverrideSpell(spellID))
		end)
	end
	if FindBaseSpellByID then
		pcall(function()
			add(FindBaseSpellByID(spellID))
		end)
	end
	if FindSpellOverrideByID then
		pcall(function()
			add(FindSpellOverrideByID(spellID))
		end)
	end
	local skin = {
		[687] = true, [696] = true, [706] = true, [1086] = true,
		[11733] = true, [11734] = true, [11735] = true, [27260] = true,
		[47893] = true, [47894] = true,
	}
	if skin[tonumber(spellID)] then
		for id in pairs(skin) do
			add(id)
		end
	end
	local trance = {
		[17941] = true, [18094] = true, [18095] = true,
	}
	if trance[tonumber(spellID)] then
		for id in pairs(trance) do
			add(id)
		end
	end
	return list
end

local function SavedAuraKey(spellID)
	local aliases = SpellAliases(spellID)
	for index = 1, #aliases do
		if AuraScope(aliases[index]) ~= nil then
			return aliases[index]
		end
	end
	local wanted = Normalize(SpellName(spellID) or "")
	if wanted == "" or (wanted:find("^hechizo ", 1, true) or wanted:find("^spell ", 1, true)) then
		return nil
	end
	for key in pairs(db.auras) do
		local savedName = Normalize(SpellName(key) or "")
		if savedName ~= "" and savedName == wanted then
			return key
		end
	end
	return nil
end

local PlayerHasBuff

function LockRemindersAuraLeft(spellID)
	local function readExpires(expires)
		if type(expires) == "number" and expires > 0 and expires < GetTime() - 5 and not LockRemindersSecret(expires) then
			return nil
		end
		return LockRemindersSecretRemaining(expires)
	end
	local function fromTable(aura)
		if type(aura) ~= "table" or LockRemindersSecret(aura) then
			return nil
		end
		local ok, expires = pcall(function()
			return aura.expirationTime
		end)
		if not ok or (not LockRemindersSecret(expires) and expires == nil) then
			ok, expires = pcall(function()
				return aura.expiration
			end)
		end
		if not ok or (not LockRemindersSecret(expires) and expires == nil) then
			return nil
		end
		return readExpires(expires)
	end
	local aliases = SpellAliases(spellID)
	for index = 1, #aliases do
		local id = aliases[index]
		if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
			local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
			if ok then
				local left = fromTable(aura)
				if left then
					return left
				end
			end
		end
		if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
			local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", id, "HELPFUL")
			if ok then
				local left = fromTable(aura)
				if left then
					return left
				end
			end
		end
	end
	local wanted = Normalize(SpellName(spellID) or "")
	if wanted == "" or wanted:find("^spell ", 1, true) or wanted:find("^hechizo ", 1, true) then
		wanted = ""
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
			if not ok or aura == nil or aura == false or LockRemindersSecret(aura) then
				break
			end
			local id = aura.spellId or aura.spellID
			local name = aura.name
			local match = false
			if not LockRemindersSecret(id) then
				id = tonumber(id)
				for alias = 1, #aliases do
					if id == aliases[alias] then
						match = true
					end
				end
			end
			if not match and wanted ~= "" and type(name) == "string" and not LockRemindersSecret(name) and Normalize(name) == wanted then
				match = true
			end
			if match then
				local left = readExpires(aura.expirationTime)
				if left then
					return left
				end
			end
		end
	end
	if UnitBuff and wanted ~= "" then
		for index = 1, 40 do
			local ok, name, _, _, _, _, sixth, seventh = pcall(UnitBuff, "player", index)
			if not ok or name == nil or name == false or name == "" or LockRemindersSecret(name) then
				if not ok or name == nil or name == false or name == "" then
					break
				end
			elseif type(name) == "string" and Normalize(name) == wanted then
				local left = readExpires(seventh) or readExpires(sixth)
				if left then
					return left
				end
			end
		end
	end
	return nil
end

function LockRemindersSetSoonWatch(on)
	if on then
		if LockRemindersSoonTicker or not C_Timer or not C_Timer.NewTicker then
			return
		end
		LockRemindersSoonTicker = C_Timer.NewTicker(0.4, function()
			if LockRemindersRefresh then
				pcall(LockRemindersRefresh)
			end
		end)
		return
	end
	if LockRemindersSoonTicker then
		LockRemindersSoonTicker:Cancel()
		LockRemindersSoonTicker = nil
	end
end

local function Missing()
	if Blocked() then
		return nil
	end

	local list = {}
	local inCombat = InCombatLockdown()
	LockRemindersSoonPending = false

	local seenNames = {}
	for spellID, where in pairs(db.auras) do
		local show = ScopeActive(where)
		local name = SpellName(spellID)
		local nameKey = Normalize(name or "")
		if nameKey ~= "" and seenNames[nameKey] then
			show = false
		end
		if show and KnowsSpell(spellID) then
			local has = PlayerHasBuff(spellID)
			local now = GetTime()
			LockRemindersBuffUntil = LockRemindersBuffUntil or {}
			LockRemindersAuraSync = LockRemindersAuraSync or {}
			local left
			if has == false then
				LockRemindersBuffUntil[spellID] = nil
				LockRemindersAuraSync[spellID] = nil
			else
				local untilAt = LockRemindersBuffUntil[spellID]
				local synced = LockRemindersAuraSync[spellID]
				if untilAt and synced and now - synced < 1 then
					left = untilAt - now
					if left < 0 then
						left = 0
					end
				else
					left = LockRemindersAuraLeft(spellID)
					LockRemindersAuraSync[spellID] = now
					if left and left > 0 then
						LockRemindersBuffUntil[spellID] = now + left
					elseif untilAt then
						left = untilAt - now
						if left < 0 then
							left = 0
						end
					end
				end
				if left and left > 0 then
					has = true
				else
					left = nil
					if LockRemindersBuffUntil[spellID] and now >= LockRemindersBuffUntil[spellID] then
						LockRemindersBuffUntil[spellID] = nil
						LockRemindersAuraSync[spellID] = nil
					end
				end
			end
			if left and left > 15 and C_Timer and C_Timer.After then
				local due = now + left - 12
				LockRemindersSoonWake = LockRemindersSoonWake or {}
				local booked = LockRemindersSoonWake[spellID]
				if not booked or math.abs(booked - due) > 1 then
					LockRemindersSoonWake[spellID] = due
					C_Timer.After(left - 12, function()
						pcall(Refresh)
					end)
				end
			end
			local soon = has == true and left and left > 0 and left <= 10
			if left and left > 0 and left <= 15 then
				LockRemindersSoonPending = true
			end
			if soon or has == false then
				if nameKey ~= "" then
					seenNames[nameKey] = true
				end
				local number = nil
				if soon and db.buffRemind ~= "alert" then
					number = math.ceil(left)
				end
		list[#list + 1] = {
					key = "aura:" .. spellID,
					icon = SpellIcon(spellID),
					text = name,
					left = number,
				}
			end
		end
	end

	if type(db.pet) == "table" and ScopeActive(db.pet) and LockRemindersHasClassPet() then
		local showPet = true
		if inCombat and not db.pet.combat then
			showPet = false
		end
		if showPet and not HasLivePet() then
			local inVehicle = UnitHasVehicleUI and UnitHasVehicleUI("player")
		local sacrificed = HasAura(SACRIFICE)
			if not inVehicle and sacrificed ~= true then
				list[#list + 1] = {
					key = "pet",
					icon = 136216,
					text = "Pet",
				}
			end
		end
	end

	return list
end

local GAP = 8
local PAD = 10

function LockRemindersIconPad()
	local pad = tonumber(db and db.iconPad) or 8
	if pad < 0 then
		pad = 0
	elseif pad > 48 then
		pad = 48
	end
	return pad
end

local function IconSize()
	local size = tonumber(db and db.iconSize) or 40
	size = math.floor(size)
	if size < 20 then
		size = 20
	end
	if size > 80 then
		size = 80
	end
	return size
end

local function ColumnsFor(count)
	count = math.max(count or 1, 1)
	local cols = math.floor(tonumber(db and db.columns) or 0)
	if cols < 1 then
		return count
	end
	if cols > 12 then
		cols = 12
	end
	return math.min(cols, count)
end

local function ColumnsLabel()
	local cols = math.floor(tonumber(db and db.columns) or 0)
	if cols < 1 then
		return "one row"
	end
	return tostring(cols)
end

local function Tracked()
	local list = {}
	if type(db.pet) == "table" and LockRemindersHasClassPet() then
		list[#list + 1] = {
			key = "pet",
			icon = 136216,
			text = "Pet",
		}
	end
	local ids = {}
	for key in pairs(db.auras) do
		local spellID = tonumber(key)
		if spellID and spellID > 0 then
			ids[#ids + 1] = spellID
		end
	end
	table.sort(ids)
	for i = 1, #ids do
		local spellID = ids[i]
		list[#list + 1] = { key = "aura:" .. spellID, icon = SpellIcon(spellID), text = SpellName(spellID) }
	end
	return list
end

local function SyncOrder(list)
	if type(db.order) ~= "table" then
		db.order = {}
	end
	local known = {}
	for i = 1, #list do
		known[list[i].key] = true
	end
	local kept = {}
	local seen = {}
	for i = 1, #db.order do
		local key = db.order[i]
		if type(key) == "string" and known[key] and not seen[key] then
			seen[key] = true
			kept[#kept + 1] = key
		end
	end
	for i = 1, #list do
		if not seen[list[i].key] then
			kept[#kept + 1] = list[i].key
		end
	end
	db.order = kept
end

local function SortEntries(list)
	local rank = {}
	for i = 1, #db.order do
		rank[db.order[i]] = i
	end
	table.sort(list, function(a, b)
		local ra = rank[a.key] or 9999
		local rb = rank[b.key] or 9999
		if ra == rb then
			return tostring(a.key) < tostring(b.key)
		end
		return ra < rb
	end)
end

local function MoveKey(key, newIndex)
	SyncOrder(Tracked())
	local from
	for i = 1, #db.order do
		if db.order[i] == key then
			from = i
			break
		end
	end
	if not from then
		return
	end
	if newIndex < 1 then
		newIndex = 1
	end
	if newIndex > #db.order then
		newIndex = #db.order
	end
	if newIndex == from then
		return
	end
	table.insert(db.order, newIndex, table.remove(db.order, from))
end

local function ApplyPoint()
	frame:ClearAllPoints()
	local point = db.point
	frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
end

local function PlayGlow(row)
	if row.glow.ag and not row.glow.ag:IsPlaying() then
		row.glow.ag:Play()
	end
end

local function PointerInFrame()
	local scale = frame:GetEffectiveScale()
	if not scale or scale == 0 then
		scale = 1
	end
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	return x - (frame:GetLeft() or 0), (frame:GetTop() or 0) - y
end

local function IndexAt(px, py, count)
	local size = IconSize()
	local pad = LockRemindersIconPad()
	local step = size + LockRemindersGlowThick(size, "buffGlowSize") * 2 + pad
	local cols = ColumnsFor(count)
	local col = math.floor((px - pad) / step)
	local line = math.floor((py - pad) / step)
	if col < 0 then
		col = 0
	end
	if line < 0 then
		line = 0
	end
	if col >= cols then
		col = cols - 1
	end
	local index = line * cols + col + 1
	if index < 1 then
		index = 1
	end
	if index > count then
		index = count
	end
	return index
end

local function FitRow(row)
	local size = IconSize()
	local thick = LockRemindersPlaceAlertIcon(row.icon, row.glow, size, "CENTER", "buffGlowSize")
	row:SetSize(size + thick * 2, size + thick * 2)
	if row.count then
		local font = row.count:GetFont()
		if type(font) ~= "string" or font == "" then
			font = "Fonts\\FRIZQT__.TTF"
		end
		row.count:SetFont(font, math.max(14, math.floor(size * 0.62)), "OUTLINE")
	end
	LockRemindersTintEvenGlow(row.glow, LockRemindersReadGlow("buffGlow", 1, 0.82, 0.35))
end

local Refresh

function LockRemindersGlowThick(size, field)
	local thick = 2
	if field and db and type(db[field]) == "number" then
		thick = db[field]
	end
	if thick < 0 then
		thick = 0
	elseif thick > 16 then
		thick = 16
	end
	return math.floor(thick)
end

function LockRemindersMakeEvenGlow(parent)
	local glow = CreateFrame("Frame", nil, parent)
	glow:SetFrameLevel(parent:GetFrameLevel() or 1)
	glow.plate = parent:CreateTexture(nil, "BORDER", nil, 7)
	glow.plate:SetTexture("Interface\\Buttons\\WHITE8x8")
	glow.plate:SetBlendMode("ADD")
	if parent.CreateMaskTexture and glow.plate.AddMaskTexture then
		glow.mask = parent:CreateMaskTexture()
		glow.mask:SetTexture("Interface\\COMMON\\common-iconmask")
		glow.plate:AddMaskTexture(glow.mask)
	end
	glow:SetScript("OnShow", function(self)
		if self.plate then
			self.plate:Show()
		end
	end)
	glow:SetScript("OnHide", function(self)
		if self.plate then
			self.plate:Hide()
		end
	end)
	glow:SetScript("OnUpdate", function(self, elapsed)
		if not self.plate or not self:IsShown() or self.quiet then
			return
		end
		self.pulse = (self.pulse or 0) + (elapsed or 0)
		local wave = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(self.pulse * 6))
		self.plate:SetAlpha(wave)
	end)
	local ag = glow:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	glow.ag = ag
	return glow
end

function LockRemindersFitEvenGlow(glow, icon, size, field)
	if not glow or not glow.plate or not icon then
		return
	end
	local thick = LockRemindersGlowThick(size, field)
	if thick <= 0 then
		glow.quiet = true
		if glow.ag then
			glow.ag:Stop()
		end
		glow:Hide()
		glow.plate:Hide()
		return
	end
	glow:Show()
	glow.plate:Show()
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -thick, thick)
	glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", thick, -thick)
	glow.plate:ClearAllPoints()
	glow.plate:SetPoint("TOPLEFT", icon, "TOPLEFT", -thick, thick)
	glow.plate:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", thick, -thick)
	if glow.mask then
		glow.mask:ClearAllPoints()
		glow.mask:SetAllPoints(glow.plate)
	end
end

function LockRemindersPlaceAlertIcon(icon, glow, size, anchor, field)
	if not icon then
		return 0
	end
	local thick = LockRemindersGlowThick(size, field)
	icon:ClearAllPoints()
	if anchor == "TOP" then
		icon:SetPoint("TOP", 0, -thick)
	else
		icon:SetPoint("CENTER")
	end
	icon:SetSize(size, size)
	LockRemindersFitEvenGlow(glow, icon, size, field)
	return thick
end

function LockRemindersGlowBorderControl(parent, anchor, gap, field, onChange)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", anchor, "RIGHT", gap or 12, 0)
	label:SetText("Border")
	label:SetTextColor(0.9, 0.84, 1)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	local function write(delta)
		local nextValue = LockRemindersGlowThick(0, field) + delta
		if nextValue < 0 then
			nextValue = 0
		elseif nextValue > 16 then
			nextValue = 16
		end
		db[field] = nextValue
		text:SetText(tostring(nextValue))
		if onChange then
			onChange()
		end
	end
	local minus = LockRemindersStepButton(parent, "-")
	minus:SetPoint("LEFT", label, "RIGHT", 6, 0)
	minus:SetScript("OnClick", function()
		write(-1)
	end)
	text:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	text:SetWidth(20)
	text:SetJustifyH("CENTER")
	text:SetText(tostring(LockRemindersGlowThick(0, field)))
	local plus = LockRemindersStepButton(parent, "+")
	plus:SetPoint("LEFT", text, "RIGHT", 2, 0)
	plus:SetScript("OnClick", function()
		write(1)
	end)
	plus.borderText = text
	return plus
end

function LockRemindersTintEvenGlow(glow, red, green, blue, alpha)
	if not glow then
		return
	end
	alpha = alpha or 1
	if glow.plate then
		glow.plate:SetVertexColor(red, green, blue, alpha)
	end
end

function LockRemindersReadGlow(field, red, green, blue)
	local color = db and db[field]
	local savedRed = type(color) == "table" and tonumber(color.r) or nil
	local savedGreen = type(color) == "table" and tonumber(color.g) or nil
	local savedBlue = type(color) == "table" and tonumber(color.b) or nil
	if not savedRed or not savedGreen or not savedBlue then
		return red, green, blue
	end
	return savedRed, savedGreen, savedBlue
end

function LockRemindersPaintGlowButton(button, field, red, green, blue)
	if not button then
		return
	end
	local savedRed, savedGreen, savedBlue = LockRemindersReadGlow(field, red, green, blue)
	Paint(button, savedRed, savedGreen, savedBlue, 1, 0.95, 0.9, 1, 1)
end

function LockRemindersPickGlow(field, red, green, blue, onChange)
	if not ColorPickerFrame or not db then
		return
	end
	local currentRed, currentGreen, currentBlue = LockRemindersReadGlow(field, red, green, blue)
	local previous = { r = currentRed, g = currentGreen, b = currentBlue }
	local function apply(nextRed, nextGreen, nextBlue)
		if not nextRed or not db then
			return
		end
		db[field] = { r = nextRed, g = nextGreen, b = nextBlue }
		if onChange then
			onChange()
		end
	end
	local function read()
		if ColorPickerFrame.GetColorRGB then
			return ColorPickerFrame:GetColorRGB()
		end
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = currentRed,
			g = currentGreen,
			b = currentBlue,
			hasOpacity = false,
			swatchFunc = function()
				apply(read())
			end,
			cancelFunc = function()
				apply(previous.r, previous.g, previous.b)
			end,
		})
		return
	end
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.func = function()
		apply(read())
	end
	ColorPickerFrame.cancelFunc = function()
		apply(previous.r, previous.g, previous.b)
	end
	ColorPickerFrame.previousValues = { currentRed, currentGreen, currentBlue }
	if ColorPickerFrame.SetColorRGB then
		ColorPickerFrame:SetColorRGB(currentRed, currentGreen, currentBlue)
	end
	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()
end

function LockRemindersGlowSwatch(parent, anchor, gap, field, red, green, blue, onChange)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", anchor, "RIGHT", gap or 12, 0)
	label:SetText("Glow")
	label:SetTextColor(0.9, 0.84, 1)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(22, 22)
	button:SetPoint("LEFT", label, "RIGHT", 8, 0)
	button.caption = label
	button:SetScript("OnClick", function(self)
		LockRemindersPickGlow(field, red, green, blue, function()
			LockRemindersPaintGlowButton(self, field, red, green, blue)
			if onChange then
				onChange()
			end
		end)
	end)
	LockRemindersPaintGlowButton(button, field, red, green, blue)
	return button
end

function LockRemindersPickColor(read, write, onChange)
	if not ColorPickerFrame or not read or not write then
		return
	end
	local currentRed, currentGreen, currentBlue = read()
	local previous = { r = currentRed, g = currentGreen, b = currentBlue }
	local function apply(nextRed, nextGreen, nextBlue)
		if not nextRed then
			return
		end
		write(nextRed, nextGreen, nextBlue)
		if onChange then
			onChange()
		end
	end
	local function sample()
		if ColorPickerFrame.GetColorRGB then
			return ColorPickerFrame:GetColorRGB()
		end
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = currentRed,
			g = currentGreen,
			b = currentBlue,
			hasOpacity = false,
			swatchFunc = function()
				apply(sample())
			end,
			cancelFunc = function()
				apply(previous.r, previous.g, previous.b)
			end,
		})
		return
	end
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.func = function()
		apply(sample())
	end
	ColorPickerFrame.cancelFunc = function()
		apply(previous.r, previous.g, previous.b)
	end
	ColorPickerFrame.previousValues = { currentRed, currentGreen, currentBlue }
	if ColorPickerFrame.SetColorRGB then
		ColorPickerFrame:SetColorRGB(currentRed, currentGreen, currentBlue)
	end
	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()
end

function LockRemindersColorSwatch(parent, anchor, gap, caption, read, write, onChange)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", anchor, "RIGHT", gap or 12, 0)
	label:SetText(caption)
	label:SetTextColor(0.9, 0.84, 1)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(22, 22)
	button:SetPoint("LEFT", label, "RIGHT", 8, 0)
	button.caption = label
	local function paint()
		local red, green, blue = read()
		Paint(button, red, green, blue, 1, 0.95, 0.9, 1, 1)
	end
	button.refresh = paint
	button:SetScript("OnClick", function()
		LockRemindersPickColor(read, write, function()
			paint()
			if onChange then
				onChange()
			end
		end)
	end)
	paint()
	return button
end

function LockRemindersSmoothIcon(icon)
	if not icon then
		return
	end
	if icon.SetSnapToPixelGrid then
		icon:SetSnapToPixelGrid(false)
	end
	if icon.SetTexelSnappingBias then
		icon:SetTexelSnappingBias(0)
	end
end

function LockRemindersRoundIcon(icon)
	if not icon or icon.LockRemindersMask then
		return
	end
	if icon.SetMask then
		pcall(icon.SetMask, icon, "")
	end
	local parent = icon.GetParent and icon:GetParent()
	if not parent or not parent.CreateMaskTexture or not icon.AddMaskTexture then
		return
	end
	local mask = parent:CreateMaskTexture()
	mask:SetAllPoints(icon)
	mask:SetTexture("Interface\\COMMON\\common-iconmask")
	icon:AddMaskTexture(mask)
	icon.LockRemindersMask = mask
end

local function Row(index)
	local row = rows[index]
	if row then
		return row
	end

	row = CreateFrame("Frame", nil, frame)
	row:SetMovable(true)
	row:EnableMouse(false)
	row:RegisterForDrag("LeftButton")
	row:SetSize(IconSize(), IconSize())

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	LockRemindersRoundIcon(row.icon)

	row.glow = LockRemindersMakeEvenGlow(row)
	LockRemindersTintEvenGlow(row.glow, 1, 0.82, 0.35)
	LockRemindersFitEvenGlow(row.glow, row.icon, IconSize(), "buffGlowSize")

	row.count = row:CreateFontString(nil, "OVERLAY")
	row.count:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
	row.count:SetJustifyH("CENTER")
	row.count:SetJustifyV("MIDDLE")
	row.count:SetTextColor(1, 1, 1)
	row.count:Hide()

	row:SetScript("OnShow", function(self)
		if not self.quiet then
			PlayGlow(self)
		end
	end)
	row:SetScript("OnHide", function(self)
		self:SetScript("OnUpdate", nil)
		if dragKey == self.key then
			dragKey = nil
		end
	end)
	row:SetScript("OnEnter", function(self)
		if not arranging or not self.tip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.tip, 1, 0.95, 0.8)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnDragStart", function(self)
		if not arranging or not self.key then
			return
		end
		dragKey = self.key
		GameTooltip:Hide()
		self:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
		self:SetScript("OnUpdate", function(widget)
			local size = IconSize()
			local px, py = PointerInFrame()
			widget:ClearAllPoints()
			widget:SetPoint("TOPLEFT", frame, "TOPLEFT", px - size / 2, -(py - size / 2))
		end)
	end)
	row:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		local key = dragKey or self.key
		dragKey = nil
		if key then
			local px, py = PointerInFrame()
			MoveKey(key, IndexAt(px, py, #(db.order or {})))
		end
		Refresh()
		if activeTab == "alert" and ShowLayout then
			ShowLayout(false)
		end
	end)

	FitRow(row)
	rows[index] = row
	return row
end

local function ClassColor()
	local _, class = UnitClass("player")
	local color = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
	if color and color.r then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

local function ApplyFrameChrome()
	if not frame then
		return
	end
	local show = db and (db.showFrame or arranging)
	if not show then
		pcall(frame.SetBackdrop, frame, nil)
		return
	end
	local templated = ElvUI and frame.SetTemplate and pcall(frame.SetTemplate, frame, "Transparent")
	if not templated then
		Paint(frame, 0.06, 0.05, 0.08, 0.92, 1, 1, 1, 1)
	end
	local r, g, b = ClassColor()
	if arranging then
		r, g, b = 0.95, 0.78, 0.35
	end
	pcall(frame.SetBackdropBorderColor, frame, r, g, b, 1)
end

local function PlaceList(list, missingKeys)
	local size = IconSize()
	local pad = LockRemindersIconPad()
	local cell = size + LockRemindersGlowThick(size, "buffGlowSize") * 2
	local count = #list
	local cols = ColumnsFor(count)
	local lines = math.max(1, math.ceil(count / cols))
	local watching = false
	for i = 1, count do
		local row = Row(i)
		FitRow(row)
		row.key = list[i].key
		row.tip = list[i].text
		row.icon:SetTexture(list[i].icon)
		local col = (i - 1) % cols
		local line = math.floor((i - 1) / cols)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", pad + col * (cell + pad), -(pad + line * (cell + pad)))
		row:SetFrameLevel((frame:GetFrameLevel() or 1) + 2)
		row:EnableMouse(arranging)
		if arranging and missingKeys and not missingKeys[row.key] then
			row:SetAlpha(0.45)
		else
			row:SetAlpha(1)
		end
		row.quiet = list[i].left ~= nil
		if row.quiet then
			watching = true
			if row.icon.SetDesaturated then
				row.icon:SetDesaturated(true)
			end
			row.icon:SetVertexColor(0.55, 0.55, 0.55)
			if row.glow.ag then
				row.glow.ag:Stop()
			end
			row.glow:Hide()
			if row.glow.plate then
				row.glow.plate:Hide()
			end
			row.count:SetText(tostring(list[i].left))
			row.count:SetTextColor(1, 1, 1)
			row.count:Show()
		else
			if row.icon.SetDesaturated then
				row.icon:SetDesaturated(false)
			end
			row.icon:SetVertexColor(1, 1, 1)
			row.count:Hide()
			row.glow:Show()
			if row.glow.plate then
				row.glow.plate:Show()
			end
		end
		row:Show()
		if row.quiet then
			row.glow:Hide()
			if row.glow.plate then
				row.glow.plate:Hide()
			end
		else
			PlayGlow(row)
		end
	end
	LockRemindersSetSoonWatch(watching or LockRemindersSoonPending or LockRemindersFoodSoon)
	for i = count + 1, #rows do
		rows[i]:Hide()
		rows[i].key = nil
	end
	frame:SetSize(pad * 2 + cols * cell + (cols - 1) * pad, pad * 2 + lines * cell + (lines - 1) * pad)
	frame:SetFrameStrata(arranging and "DIALOG" or "MEDIUM")
	ApplyFrameChrome()
	if frame.hint then
		frame.hint:SetShown(arranging)
	end
	frame:Show()
end

Refresh = function()
	if db and RefreshFood then
		pcall(RefreshFood)
	end
	if dragKey and not arranging then
		dragKey = nil
	end
	if not frame or not db or dragKey then
		return
	end

	local preview = LockRemindersBuffPreview
	local previewing = preview and preview.at and GetTime() < preview.at and type(preview.list) == "table"
	if arranging and Restricted() and not previewing then
		frame:Hide()
		return
	end

	local list = previewing and preview.list or (arranging and Tracked() or Missing())
	if not list then
		frame:Hide()
		LockRemindersSetSoonWatch(LockRemindersFoodSoon and true or false)
		return
	end

	local catalog = Tracked()
	SyncOrder(catalog)
	SortEntries(list)
	if #list == 0 then
		frame:Hide()
		LockRemindersSetSoonWatch((LockRemindersSoonPending or LockRemindersFoodSoon) and true or false)
		return
	end

	local missingKeys
	if arranging and not previewing then
		missingKeys = {}
		local current = Missing() or {}
		for i = 1, #current do
			missingKeys[current[i].key] = true
		end
	end
	PlaceList(list, missingKeys)
end

LockRemindersRefresh = Refresh

local function ChangeSize(delta)
	local size = IconSize() + delta
	if size < 20 then
		size = 20
	end
	if size > 80 then
		size = 80
	end
	db.iconSize = size
	Refresh()
	if activeTab == "alert" and ShowLayout then
		ShowLayout(false)
	end
end

function LockRemindersChangePad(delta)
	local pad = LockRemindersIconPad() + delta
	if pad < 0 then
		pad = 0
	elseif pad > 48 then
		pad = 48
	end
	db.iconPad = pad
	Refresh()
	if activeTab == "alert" and ShowLayout then
		ShowLayout(false)
	end
end

local function ChangeColumns(delta)
	local count = math.max(#Tracked(), 1)
	local cols = math.floor(tonumber(db.columns) or 0)
	if cols < 1 then
		cols = count
	end
	cols = cols + delta
	if cols < 1 then
		cols = 1
	end
	if cols >= count then
		db.columns = 0
	else
		db.columns = cols
	end
	Refresh()
	if activeTab == "alert" and ShowLayout then
		ShowLayout(false)
	end
end

local function ToggleArrange()
	if not arranging and Restricted() then
		Print("Leave combat to arrange the icons.")
		return
	end
	if not arranging and #Tracked() == 0 then
		Print("Nothing to arrange yet.")
		return
	end
	arranging = not arranging
	if arranging then
		Print("Drag each icon inside the alert. Press Done when you finish.")
	end
	Refresh()
	if activeTab == "alert" and ShowLayout then
		ShowLayout(false)
	end
end

local function SavePoint()
	local point, _, relative, x, y = frame:GetPoint()
	db.point = { point, relative, x, y }
end

local function CreateUI()
	frame = CreateFrame("Frame", "LockRemindersFrame", UIParent, "BackdropTemplate")
	frame:SetSize(60, 60)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePoint()
	end)

	ApplyFrameChrome()

	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.hint:SetPoint("BOTTOM", frame, "TOP", 0, 6)
	frame.hint:SetText("Drag the icons")
	frame.hint:SetTextColor(1, 0.86, 0.45)
	frame.hint:Hide()

	for i = 1, #HEALTHSTONES do
		RequestItem(HEALTHSTONES[i])
	end
	for itemID in pairs(db.foodItems) do
		RequestItem(itemID)
	end
	if C_Spell.RequestLoadSpellData then
		for spellID in pairs(db.auras) do
			C_Spell.RequestLoadSpellData(spellID)
		end
		for spellID in pairs(db.food) do
			C_Spell.RequestLoadSpellData(spellID)
		end
	end

	ApplyPoint()
	frame:Hide()
end

local touchQueued

local function Touch()
	if touchQueued then
		return
	end
	touchQueued = true
	C_Timer.After(0, function()
		touchQueued = false
		pcall(Refresh)
		if UpdateListNow then
			pcall(UpdateListNow)
		end
	end)
end

local function AddAura(spellID, where)
	local info = C_Spell.GetSpellInfo(spellID)
	if not info or not info.name then
		Print("Spell " .. spellID .. " does not exist.")
		return
	end
	local always, party, raid, instance = ScopeFlags(where)
	db.auras[spellID] = { always = always, party = party, raid = raid, instance = instance }
	if KnowsSpell(spellID) then
		Print("Added: " .. info.name .. " (" .. ScopeLabel(where) .. ").")
	else
		Print(info.name .. " saved. It shows up once you learn it.")
	end
	Touch()
end

local function AddFood(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	if not info or not info.name then
		Print("Spell " .. spellID .. " does not exist.")
		return
	end
	db.food[spellID] = true
	local always, party, raid, instance = ScopeFlags(addScope)
	LockRemindersWriteFoodScope(nil, spellID, { always = always, party = party, raid = raid, instance = instance, combat = false })
	Print("Food added: " .. info.name .. ".")
	Touch()
end

local function ItemUseSpell(itemID)
	local ok, spellName, spellID = pcall(function()
		if C_Item.GetItemSpell then
			return C_Item.GetItemSpell(itemID)
		end
		if GetItemSpell then
			return GetItemSpell(itemID)
		end
	end)
	if not ok then
		return nil
	end
	spellID = tonumber(spellID)
	if not spellID or spellID <= 0 then
		return nil
	end
	if not spellName or spellName == "" then
		spellName = SpellDisplayName(spellID)
	end
	if spellName then
		local normalized = Normalize(spellName)
		if GENERIC_USE[normalized] or normalized:find("^comer ") or normalized:find("^beber ") or normalized:find("^eating ") or normalized:find("^drinking ") then
			return nil
		end
	end
	return spellID
end

function LockRemindersFoodJunkName(name)
	name = Normalize(name or "")
	if name == "" then
		return false
	end
	return name:find("tusk", 1, true)
		or name:find("fishing", 1, true)
		or name:find("pole", 1, true)
		or name:find("hide", 1, true)
		or name:find("leather", 1, true)
		or name:find("fang", 1, true)
		or name:find("claw", 1, true)
		or name:find("tooth", 1, true)
		or name:find("bone", 1, true)
		or name:find("scale", 1, true)
		or name:find("bristle", 1, true)
		or name:find("quill", 1, true)
		or name:find("hoof", 1, true)
		or name:find("pelt", 1, true)
		or name:find("scrap", 1, true)
end

function LockRemindersFoodCookedName(name)
	name = Normalize(name or "")
	if name == "" then
		return false
	end
	return name:find("roast", 1, true)
		or name:find("asado", 1, true)
		or name:find("cooked", 1, true)
		or name:find("smoked", 1, true)
		or name:find("grilled", 1, true)
		or name:find("baked", 1, true)
		or name:find("spiced", 1, true)
		or name:find("seasoned", 1, true)
		or name:find("fried", 1, true)
		or name:find("boiled", 1, true)
		or name:find("pickled", 1, true)
end

function LockRemindersFoodRawName(name)
	name = Normalize(name or "")
	if name == "" then
		return false
	end
	if LockRemindersFoodCookedName(name) then
		return false
	end
	-- Cooking reagents / vendor mats — not eat-food that grants Well Fed.
	if name:find("chunk of", 1, true) or name:find("piece of", 1, true) or name:find("slab of", 1, true) then
		return true
	end
	if name:find("^raw ", 1, true) or name:find(" raw ", 1, true) then
		return true
	end
	if name:find("ribs", 1, true) or name:find("costill", 1, true) then
		return true
	end
	if name:find("meat", 1, true) or name:find("carne", 1, true) then
		return true
	end
	return false
end

function LockRemindersFoodishName(name)
	name = Normalize(name or "")
	if name == "" or LockRemindersFoodJunkName(name) or LockRemindersFoodRawName(name) then
		return false
	end
	-- Ready-to-eat food names (or cooked meat like "Roasted Boar Meat").
	if LockRemindersFoodCookedName(name) then
		return true
	end
	return name:find("bread", 1, true)
		or name:find("pan ", 1, true)
		or name:find("pescado", 1, true)
		or name:find("feast", 1, true)
		or name:find("banquete", 1, true)
		or name:find("food", 1, true)
		or name:find("comida", 1, true)
		or name:find("steak", 1, true)
		or name:find("sausage", 1, true)
		or name:find("cheese", 1, true)
		or name:find("queso", 1, true)
		or name:find("apple", 1, true)
		or name:find("banana", 1, true)
		or name:find("well fed", 1, true)
		or name:find("alimentado", 1, true)
		or (name:find("fish", 1, true) and not name:find("fishing", 1, true) and (name:find("cooked", 1, true) or name:find("smoked", 1, true) or name:find("grilled", 1, true)))
end

function LockRemindersItemGrantsWellFed(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return false
	end
	LockRemindersWellFedItemCache = LockRemindersWellFedItemCache or {}
	local cached = LockRemindersWellFedItemCache[itemID]
	if cached ~= nil then
		return cached
	end
	local found = false
	local function note(text)
		if found or type(text) ~= "string" or text == "" then
			return
		end
		if LockRemindersSecret and LockRemindersSecret(text) then
			return
		end
		local n = Normalize(text)
		if n:find("well fed", 1, true) or n:find("bien alimentado", 1, true) then
			found = true
		end
	end
	if C_TooltipInfo and C_TooltipInfo.GetItemByID then
		local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
		if ok and type(data) == "table" and type(data.lines) == "table" then
			for index = 1, #data.lines do
				local line = data.lines[index]
				if type(line) == "table" then
					note(line.leftText)
					note(line.rightText)
				end
			end
		end
	end
	if not found then
		local tip = LockRemindersFoodTip
		if not tip and CreateFrame then
			tip = CreateFrame("GameTooltip", "LockRemindersFoodTip", nil, "GameTooltipTemplate")
			tip:SetOwner(UIParent, "ANCHOR_NONE")
			LockRemindersFoodTip = tip
		end
		if tip and tip.SetItemByID then
			tip:ClearLines()
			local ok = pcall(tip.SetItemByID, tip, itemID)
			if ok then
				local regions = { tip:GetRegions() }
				for index = 1, #regions do
					local region = regions[index]
					if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
						note(region:GetText())
					end
				end
			end
			tip:Hide()
		end
	end
	LockRemindersWellFedItemCache[itemID] = found
	return found
end

function LockRemindersIsEatFood(itemID, name)
	itemID = tonumber(itemID)
	name = name or (itemID and ItemName(itemID))
	if LockRemindersFoodJunkName(name) or LockRemindersFoodRawName(name) then
		return false
	end
	-- Tooltip "Well Fed" is the source of truth when readable.
	local ok, grants = pcall(LockRemindersItemGrantsWellFed, itemID)
	if ok and grants == true then
		return true
	end
	return LockRemindersFoodishName(name)
end

function LockRemindersIsWellFedName(name)
	name = Normalize(name or "")
	if name == "" then
		return false
	end
	return name == "well fed"
		or name == "bien alimentado"
		or name:find("well fed", 1, true)
		or name:find("bien alimentado", 1, true)
end

function LockRemindersStampWellFed(left)
	local now = GetTime()
	if type(left) == "number" and left > 0 then
		LockRemindersWellFedUntil = now + left
		LockRemindersWellFedKnown = true
		return left
	end
	LockRemindersWellFedKnown = true
	return nil
end

function LockRemindersClearWellFed()
	LockRemindersWellFedUntil = nil
	LockRemindersWellFedKnown = false
end

function LockRemindersCachedWellFedLeft()
	local untilAt = LockRemindersWellFedUntil
	if type(untilAt) ~= "number" then
		return nil
	end
	local left = untilAt - GetTime()
	if left > 0 then
		return left
	end
	LockRemindersWellFedUntil = nil
	return nil
end

function LockRemindersHasWellFed()
	local found = false
	local secret = false
	local complete = false
	local left
	local function readExpires(expires)
		if type(expires) ~= "number" or expires <= 0 then
			return nil
		end
		if LockRemindersSecret and LockRemindersSecret(expires) then
			return nil
		end
		local remain = expires - GetTime()
		if remain > 0 then
			return remain
		end
	end
	local function noteName(name, remain)
		if name == nil or name == false or name == "" then
			return "end"
		end
		if LockRemindersSecret and LockRemindersSecret(name) then
			secret = true
			return true
		end
		if type(name) ~= "string" then
			secret = true
			return true
		end
		if LockRemindersIsWellFedName(name) then
			found = true
			left = remain or left
			return true
		end
		return true
	end
	if UnitBuff then
		complete = true
		for index = 1, 40 do
			local ok, name, _, _, _, _, sixth, seventh = pcall(UnitBuff, "player", index)
			if not ok then
				secret = true
				complete = false
				break
			end
			local step = noteName(name, readExpires(seventh) or readExpires(sixth))
			if step == "end" then
				break
			end
		end
	end
	if not found and C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		complete = true
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
			if not ok then
				secret = true
				complete = false
				break
			end
			if aura == nil or aura == false then
				break
			end
			local step = noteName(aura.name, readExpires(aura.expirationTime))
			if step == "end" then
				break
			end
		end
	end
	if found then
		LockRemindersStampWellFed(left)
		return true
	end
	-- Forever can hide or omit combat buffs. Keep the last known Well Fed.
	local cached = LockRemindersCachedWellFedLeft()
	if cached and (secret or not complete or InCombatLockdown()) then
		return true
	end
	if InCombatLockdown() and LockRemindersWellFedKnown == true then
		return true
	end
	if LockRemindersWellFedKnown and (secret or not complete) then
		return nil
	end
	if complete and not secret then
		LockRemindersClearWellFed()
		return false
	end
	if secret or not complete then
		return nil
	end
	return false
end

function LockRemindersWellFedLeft()
	local function readExpires(expires)
		if type(expires) ~= "number" or expires <= 0 then
			return nil
		end
		if LockRemindersSecret and LockRemindersSecret(expires) then
			return nil
		end
		local left = expires - GetTime()
		if left > 0 then
			return left
		end
	end
	if UnitBuff then
		for index = 1, 40 do
			local ok, name, _, _, _, _, sixth, seventh = pcall(UnitBuff, "player", index)
			if not ok or name == nil or name == false or name == "" then
				break
			end
			if type(name) == "string" and not (LockRemindersSecret and LockRemindersSecret(name)) and LockRemindersIsWellFedName(name) then
				local left = readExpires(seventh) or readExpires(sixth)
				if left then
					LockRemindersStampWellFed(left)
					return left
				end
			end
		end
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
			if not ok or aura == nil or aura == false then
				break
			end
			local name = aura.name
			if type(name) == "string" and not (LockRemindersSecret and LockRemindersSecret(name)) and LockRemindersIsWellFedName(name) then
				local left = readExpires(aura.expirationTime)
				if left then
					LockRemindersStampWellFed(left)
					return left
				end
			end
		end
	end
	return LockRemindersCachedWellFedLeft()
end

function ConsumableKept(itemID)
	-- Eat-food first (does not need ConsumableGroup; that local is not visible here).
	if LockRemindersIsEatFood(itemID, ItemName(itemID)) then
		return true
	end
	local group = type(LockRemindersConsumableGroup) == "function" and LockRemindersConsumableGroup(itemID)
	if group == "Food" or group == "Flasks" or group == "Elixirs" then
		return true
	end
	if group ~= "Potions" then
		return false
	end
	local function restorative(name)
		name = Normalize(name or "")
		if name == "" then
			return false
		end
		if name:find("heal", 1, true) or name:find("salud", 1, true) or name:find("sanaci", 1, true) or name:find("curaci", 1, true) then
			return true
		end
		if name:find("mana", 1, true) or name:find("rejuven", 1, true) or name:find("restaur", 1, true) then
			return true
		end
		if name:find("bandage", 1, true) or name:find("venda", 1, true) or name:find("dreamless", 1, true) then
			return true
		end
		return false
	end
	if restorative(ItemName(itemID)) then
		return false
	end
	local spellID = ItemUseSpell(itemID)
	if spellID and restorative(SpellName(spellID)) then
		return false
	end
	return true
end

local function AddFoodItem(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return
	end
	local name = ItemName(itemID)
	if not name or name == "" then
		RequestItem(itemID)
		name = "Item " .. itemID
	end
	local spellID = ItemUseSpell(itemID)
	-- Eat-food (Well Fed) must track the buff by name, not the eat use-spell.
	if LockRemindersIsEatFood(itemID, name) then
		spellID = nil
	end
	db.foodItems[itemID] = spellID or true
	local always, party, raid, instance = ScopeFlags(addScope)
	LockRemindersWriteFoodScope(itemID, nil, { always = always, party = party, raid = raid, instance = instance, combat = false })
	if spellID then
		Print("Consumable added: " .. name .. ".")
	else
		Print(name .. " added. Alerts when Well Fed is missing.")
	end
	Touch()
end

local function DropAura(spellID)
	local removed = false
	local numberID = tonumber(spellID)
	local keys = { spellID }
	if numberID then
		keys[#keys + 1] = numberID
		keys[#keys + 1] = tostring(numberID)
	end
	for i = 1, #keys do
		local key = keys[i]
		if key ~= nil and db.auras[key] ~= nil then
			db.auras[key] = nil
			removed = true
		end
	end
	return removed
end

local function RemoveSpell(spellID, kind)
	local name = SpellName(spellID)
	local removed
	if kind == "food" then
		removed = db.food[spellID] ~= nil
	db.food[spellID] = nil
	elseif kind == "aura" then
		removed = DropAura(spellID)
	else
		removed = DropAura(spellID) or db.food[spellID] ~= nil
		db.food[spellID] = nil
	end
	Print(removed and ("Removed: " .. name .. ".") or "It was not on the list.")
	Touch()
end

local function RemoveFoodItem(itemID)
	if db.foodItems[itemID] == nil then
		Print("It was not on the list.")
		return
	end
	local name = ItemName(itemID) or ("Item " .. itemID)
	db.foodItems[itemID] = nil
	Print("Removed: " .. name .. ".")
	Touch()
end

local function SetScopeFlag(spellID, flag, enabled)
	local key = spellID
	if db.auras[key] == nil then
		key = tostring(spellID)
	end
	if db.auras[key] == nil then
		return
	end
	local always, party, raid, instance = ScopeFlags(db.auras[key])
	local combat = type(db.auras[key]) == "table" and db.auras[key].combat and true or false
	local scope = { always = always, party = party, raid = raid, instance = instance, combat = combat }
	if flag == "combat" then
		scope.combat = enabled and true or false
	else
		scope[flag] = enabled and true or false
	end
	db.auras[key] = scope
	Touch()
end

function FoodCombatKey(itemID, spellID)
	if itemID then
		return itemID
	end
	if spellID then
		return "spell" .. spellID
	end
end

function FoodInCombat(itemID, spellID)
	if type(db.foodCombat) ~= "table" then
		return false
	end
	local key = FoodCombatKey(itemID, spellID)
	return key ~= nil and db.foodCombat[key] and true or false
end

function SetFoodCombat(itemID, spellID, enabled)
	if type(db.foodCombat) ~= "table" then
		db.foodCombat = {}
	end
	local key = FoodCombatKey(itemID, spellID)
	if not key then
		return
	end
	db.foodCombat[key] = enabled and true or false
	Touch()
end

function AnyFoodInCombat()
	if type(db.foodCombat) ~= "table" then
		return false
	end
	for itemID in pairs(db.foodItems) do
		if db.foodCombat[itemID] then
			return true
		end
	end
	for spellID in pairs(db.food) do
		if db.foodCombat["spell" .. spellID] then
			return true
		end
	end
	return false
end

local function SavedCount()
	local count = 0
	for _ in pairs(db.auras) do
		count = count + 1
	end
	for _ in pairs(db.food) do
		count = count + 1
	end
	for _ in pairs(db.foodItems) do
		count = count + 1
	end
	return count
end

local function AuraAt(index)
	local ok, aura
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
	elseif C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
	else
		return "end"
	end
	if not ok or aura == nil or aura == false then
		return "end"
	end
	local readOk, spellID, name, icon = pcall(function()
		local id, auraName, auraIcon
		pcall(function()
			id = aura.spellId or aura.spellID
			auraName = aura.name
			auraIcon = aura.icon
		end)
		-- Resolve sealed ids against configured talent procs.
		if id ~= nil and db and type(db.talents) == "table" and LockRemindersSameSpell then
			for saved in pairs(db.talents) do
				local sid = tonumber(saved)
				if sid then
					local aliases = SpellAliases(sid)
					for aliasIndex = 1, #aliases do
						if LockRemindersSameSpell(id, aliases[aliasIndex]) then
							return sid, (type(auraName) == "string" and auraName) or SpellName(sid), auraIcon
						end
					end
				end
			end
		end
		if id ~= nil and issecretvalue and issecretvalue(id) then
			id = nil
		else
			id = tonumber(id)
			if id and id <= 0 then
				id = nil
			end
		end
		if auraName ~= nil and issecretvalue and issecretvalue(auraName) then
			auraName = nil
		elseif type(auraName) == "string" and auraName == "" then
			auraName = nil
		end
		if auraIcon ~= nil and issecretvalue and issecretvalue(auraIcon) then
			auraIcon = nil
		end
		if not id and not auraName then
			return nil
		end
		return id, auraName, auraIcon
	end)
	if not readOk then
		return "skip"
	end
	if not spellID and (type(name) ~= "string" or name == "") then
		return "skip"
	end
	return "ok", spellID, name, icon
end

local function UnitBuffAt(index)
	if type(UnitBuff) ~= "function" then
		return "end"
	end
	local packed = { pcall(UnitBuff, "player", index) }
	if not packed[1] then
		return "end"
	end
	local name = packed[2]
	if name == nil or name == false then
		if issecretvalue and issecretvalue(name) then
			return "skip"
		end
		return "end"
	end
	if issecretvalue and issecretvalue(name) then
		return "skip"
	end
	if type(name) ~= "string" or name == "" then
		return "skip"
	end
	local spellID, icon
	for slot = 3, #packed do
		local value = packed[slot]
		if value ~= nil and not (issecretvalue and issecretvalue(value)) then
			if type(value) == "number" then
				if value > 0 and value < 10000000 and not spellID then
					spellID = value
				elseif value > 10000000 and not icon then
					icon = value
				end
			elseif type(value) == "string" and value ~= "" and not icon then
				icon = value
			end
		end
	end
	return "ok", spellID, name, icon
end

local function EachAura(callback)
	local seen = {}
	local function emit(spellID, name, icon)
		local key = Normalize(name or "")
		if key == "" then
			key = tostring(spellID or "")
		end
		if key == "" or seen[key] then
			return
		end
		seen[key] = true
		callback(spellID, name, icon)
	end
	for index = 1, 40 do
		local status, spellID, name, icon = AuraAt(index)
		if status == "end" then
			break
		end
		if status == "ok" then
			emit(spellID, name, icon)
		end
	end
	for index = 1, 40 do
		local status, spellID, name, icon = UnitBuffAt(index)
		if status == "end" then
			return
		end
		if status == "ok" then
			emit(spellID, name, icon)
		end
	end
end

PlayerHasBuff = function(spellID)
	LockRemindersBuffKnown = LockRemindersBuffKnown or {}
	LockRemindersCastSeen = LockRemindersCastSeen or {}
	LockRemindersBuffGone = LockRemindersBuffGone or {}
	local aliases = SpellAliases(spellID)
	local function castFresh(id)
		local stamp = LockRemindersCastSeen[id]
		return type(stamp) == "number" and GetTime() - stamp < 2.5
	end
	local fresh = castFresh(spellID) and not LockRemindersBuffGone[spellID]
	if not fresh then
		for index = 1, #aliases do
			if castFresh(aliases[index]) and not LockRemindersBuffGone[spellID] and not LockRemindersBuffGone[aliases[index]] then
				fresh = true
			end
		end
	end
	if not fresh then
		local nameKeys = LockRemindersTalentAliasNames and LockRemindersTalentAliasNames(spellID) or {}
		if #nameKeys == 0 then
			local castName = Normalize(SpellName(spellID) or "")
			if castName ~= "" then
				nameKeys[1] = castName
			end
		end
		for nameIndex = 1, #nameKeys do
			local named = LockRemindersCastNames and LockRemindersCastNames[nameKeys[nameIndex]]
			if nameKeys[nameIndex] ~= "" and type(named) == "number" and GetTime() - named < 2.5 and not LockRemindersBuffGone[spellID] then
				fresh = true
				break
			end
		end
	end
	local unknown = false
	local function present()
		LockRemindersBuffGone[spellID] = nil
		LockRemindersBuffKnown[spellID] = true
		return true
	end
	if fresh then
		return present()
	end
	for index = 1, #aliases do
		local has = HasAura(aliases[index])
		if has then
			return present()
		end
		if has == nil then
			unknown = true
		end
	end
	local wantedNames = LockRemindersTalentAliasNames and LockRemindersTalentAliasNames(spellID) or {}
	if #wantedNames == 0 then
		local wanted = Normalize(SpellName(spellID) or "")
		if wanted ~= "" and not (wanted:find("^hechizo ", 1, true) or wanted:find("^spell ", 1, true)) then
			wantedNames[1] = wanted
		end
	end
	if #wantedNames > 0 then
		local matched = false
		EachAura(function(_, name)
			local auraKey = Normalize(name or "")
			for nameIndex = 1, #wantedNames do
				if auraKey == wantedNames[nameIndex] or (LockRemindersTalentNameMatch and LockRemindersTalentNameMatch(name, wantedNames[nameIndex])) then
					matched = true
				end
			end
		end)
		if matched then
			return present()
		end
	end
	if not unknown then
		LockRemindersBuffGone[spellID] = true
		LockRemindersBuffKnown[spellID] = false
		if LockRemindersBuffUntil then
			LockRemindersBuffUntil[spellID] = nil
		end
		return false
	end
	if LockRemindersBuffGone[spellID] then
		LockRemindersBuffKnown[spellID] = false
		return false
	end
	if LockRemindersBuffKnown[spellID] ~= nil then
		return LockRemindersBuffKnown[spellID]
	end
	return nil
end

local function InvalidateSpellbook()
	spellbookCache = nil
	spellbookAllCache = nil
end

local function CollectSpellbook(keepPassive)
	local now = GetTime()
	if keepPassive then
		if spellbookAllCache and now - spellbookAllCacheAt < 8 then
			return spellbookAllCache
		end
	elseif spellbookCache and now - spellbookCacheAt < 8 then
		return spellbookCache
	end

	local spells = {}
	local seen = {}
	local seenNames = {}
	local function Push(spellID, name, icon, passive, offspec)
		spellID = tonumber(spellID)
		if not spellID or spellID <= 0 or seen[spellID] or (passive and not keepPassive) then
			return
		end
		if issecretvalue and issecretvalue(spellID) then
			return
		end
		name = SpellDisplayName(spellID, name)
		if not name then
			return
		end
		local nameKey = Normalize(name)
		if nameKey ~= "" and seenNames[nameKey] then
			return
		end
		seen[spellID] = true
		if nameKey ~= "" then
			seenNames[nameKey] = true
		end
		spells[#spells + 1] = {
			spellID = spellID,
			name = name,
			icon = icon or SpellIcon(spellID),
			offspec = offspec and true or false,
		}
	end

	local scanned = false
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
		scanned = pcall(function()
			local bank = Enum.SpellBookSpellBank.Player
			local future = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
			local flyout = Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout
			local pet = Enum.SpellBookItemType and Enum.SpellBookItemType.PetAction
			local lines = C_SpellBook.GetNumSpellBookSkillLines()
			for line = 1, lines do
				local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
				if info and not info.shouldHide and info.numSpellBookItems and info.numSpellBookItems > 0 and info.itemIndexOffset then
					for index = 1, info.numSpellBookItems do
						local item = C_SpellBook.GetSpellBookItemInfo(info.itemIndexOffset + index, bank)
						if item and item.itemType ~= future and item.itemType ~= flyout and item.itemType ~= pet then
							Push(item.spellID, item.name, item.iconID, item.isPassive, item.isOffSpec)
						end
					end
				end
			end
		end)
	end

	if (not scanned or #spells == 0) and GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		pcall(function()
			local book = BOOKTYPE_SPELL or "spell"
			for tab = 1, GetNumSpellTabs() do
				local _, _, offset, numSlots = GetSpellTabInfo(tab)
				if offset and numSlots then
					for index = offset + 1, offset + numSlots do
						local spellType, spellID = GetSpellBookItemInfo(index, book)
						if spellType == "SPELL" and spellID then
							local passive = IsPassiveSpell and IsPassiveSpell(index, book)
							local name = GetSpellBookItemName and GetSpellBookItemName(index, book)
							Push(spellID, name, nil, passive, false)
						end
					end
				end
			end
		end)
	end

	if keepPassive then
		spellbookAllCache = spells
		spellbookAllCacheAt = now
	else
		spellbookCache = spells
		spellbookCacheAt = now
	end
	return spells
end

local function ItemClassAndSubclass(itemID)
	if not itemID or not C_Item.GetItemInfoInstant then
		return nil
	end
	local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
	if not ok or (issecretvalue and issecretvalue(classID)) then
		return nil
	end
	if issecretvalue and issecretvalue(subclassID) then
		subclassID = nil
	end
	return classID, subclassID
end

local function IsConsumableItem(itemID)
	local classID = ItemClassAndSubclass(itemID)
	local consumable = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
	return classID == consumable
end

local function ConsumableGroup(itemID)
	local _, subclassID = ItemClassAndSubclass(itemID)
	local sub = Enum and Enum.ItemConsumableSubclass
	if sub and subclassID ~= nil then
		if sub.Fooddrink and subclassID == sub.Fooddrink then
			return "Food"
		end
		if sub.Potion and subclassID == sub.Potion then
			return "Potions"
		end
		if sub.Flask and subclassID == sub.Flask then
			return "Flasks"
		end
		if sub.Elixir and subclassID == sub.Elixir then
			return "Elixirs"
		end
		return "Other"
	end
	if subclassID == 5 then
		return "Food"
	end
	if subclassID == 1 then
		return "Potions"
	end
	if subclassID == 3 then
		return "Flasks"
	end
	if subclassID == 2 then
		return "Elixirs"
	end
	return "Other"
end
LockRemindersConsumableGroup = ConsumableGroup

local function EachBagItem(callback)
	local maxBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, maxBag do
		pcall(function()
			local slots = 0
			if C_Container and C_Container.GetContainerNumSlots then
				slots = C_Container.GetContainerNumSlots(bag) or 0
			elseif GetContainerNumSlots then
				slots = GetContainerNumSlots(bag) or 0
			end
			for slot = 1, slots do
				local itemID, count, icon, bagName, link
				if C_Container and C_Container.GetContainerItemInfo then
					local info = C_Container.GetContainerItemInfo(bag, slot)
					if info then
						itemID = info.itemID
						count = info.stackCount or 1
						icon = info.iconFileID
						bagName = Plain(info.itemName)
						link = info.hyperlink
					end
				end
				if (not itemID or (issecretvalue and issecretvalue(itemID))) and C_Container and C_Container.GetContainerItemID then
					local ok, value = pcall(C_Container.GetContainerItemID, bag, slot)
					if ok and value and not (issecretvalue and issecretvalue(value)) then
						itemID = value
					end
				end
				if (not itemID or (issecretvalue and issecretvalue(itemID))) and GetContainerItemID then
					local ok, value = pcall(GetContainerItemID, bag, slot)
					if ok and value and not (issecretvalue and issecretvalue(value)) then
						itemID = value
					end
				end
				if not count and GetContainerItemInfo and not (C_Container and C_Container.GetContainerItemInfo) then
					local texture, itemCount, _, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
					count = itemCount or 1
					icon = icon or texture
					link = link or itemLink
				end
				if not link or (issecretvalue and issecretvalue(link)) then
					if C_Container and C_Container.GetContainerItemLink then
						local ok, value = pcall(C_Container.GetContainerItemLink, bag, slot)
						if ok and value and not (issecretvalue and issecretvalue(value)) then
							link = value
						end
					elseif GetContainerItemLink then
						local ok, value = pcall(GetContainerItemLink, bag, slot)
						if ok and value and not (issecretvalue and issecretvalue(value)) then
							link = value
						end
					end
				end
				-- Forever can secret bag itemIDs; recover from the item link.
				if (not itemID or (issecretvalue and issecretvalue(itemID))) and type(link) == "string" and not (issecretvalue and issecretvalue(link)) then
					local ok, value = pcall(function()
						return tonumber(link:match("item:(%d+)"))
					end)
					if ok then
						itemID = value
					end
				end
				if not bagName then
					bagName = NameFromLink(link)
				end
				if itemID and not (issecretvalue and issecretvalue(itemID)) then
					RememberItemName(itemID, bagName)
					RememberItemName(itemID, NameFromLink(link))
					if issecretvalue and issecretvalue(count) then
						count = 1
					end
					callback(itemID, tonumber(count) or 1, icon, bagName or ItemName(itemID))
				end
			end
		end)
	end
end

function LockRemindersHasHealthstone()
	local found = false
	EachBagItem(function(itemID)
		if found or not itemID then
			return
		end
		for index = 1, #HEALTHSTONES do
			if itemID == HEALTHSTONES[index] then
				found = true
				return
			end
		end
		local name = Normalize(ItemName(itemID) or "")
		if name:find("healthstone", 1, true) or name:find("piedra de salud", 1, true) then
			found = true
		end
	end)
	return found
end

local function BagContents()
	local counts = {}
	local icons = {}
	local names = {}
	EachBagItem(function(itemID, count, icon, name)
		counts[itemID] = (counts[itemID] or 0) + count
		if icon then
			icons[itemID] = icon
		end
		if type(name) == "string" and name ~= "" then
			names[itemID] = name
		end
	end)
	return counts, icons, names
end

local function NameMatches(name, query)
	if query == "" then
		return true
	end
	name = Plain(name)
	if not name then
		return false
	end
	return Normalize(name):find(query, 1, true) ~= nil
end

local function ParseSearch(raw)
	raw = raw or ""
	local spellLink = tonumber(raw:match("Hspell:(%d+)"))
	local itemLink = tonumber(raw:match("Hitem:(%d+)"))
	local plain = raw:gsub("|c%x%x%x%x%x%x%x%x", "")
	plain = plain:gsub("|r", "")
	plain = plain:gsub("|H.-|h(.-)|h", "%1")
	plain = plain:gsub("|", "")
	plain = plain:gsub("[%[%]]", "")
	plain = strtrim(plain)
	local typedID = nil
	if plain:match("^%d%d%d+$") then
		typedID = tonumber(plain)
	end
	return Normalize(plain), typedID, spellLink, itemLink
end

local function SortByName(list)
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then
			return (a.rank or 0) < (b.rank or 0)
		end
		return (a.sortName or "") < (b.sortName or "")
	end)
end

local function Sections(...)
	local out = {}
	for index = 1, select("#", ...) do
		local section = select(index, ...)
		if section and section.rows and #section.rows > 0 then
			out[#out + 1] = section
		end
	end
	return out
end

local function TalentKey(spellID)
	if not db or type(db.talents) ~= "table" then
		return nil
	end
	local aliases = SpellAliases(spellID)
	for index = 1, #aliases do
		local id = aliases[index]
		if db.talents[id] ~= nil or db.talents[tostring(id)] ~= nil then
			return id
		end
	end
	local wanted = Normalize(SpellName(spellID) or "")
	if wanted == "" or (wanted:find("^hechizo ", 1, true) or wanted:find("^spell ", 1, true)) then
		return nil
	end
	for key in pairs(db.talents) do
		local savedName = Normalize(SpellName(key) or "")
		if savedName ~= "" and (savedName == wanted or (LockRemindersTalentNameMatch and LockRemindersTalentNameMatch(savedName, wanted))) then
			return key
		end
	end
	return nil
end

local function AddTalent(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return
	end
	local ok, info
	if C_Spell and C_Spell.GetSpellInfo then
		ok, info = pcall(C_Spell.GetSpellInfo, spellID)
	end
	local known = ok and info
	if not known and GetSpellInfo then
		local got, name = pcall(GetSpellInfo, spellID)
		if got and name and not (issecretvalue and issecretvalue(name)) and name ~= "" then
			known = true
		end
	end
	if not known then
		Print("Spell " .. spellID .. " does not exist.")
		return
	end
	db.talents[spellID] = { untilEnd = false, style = "scythes", sound = "none" }
	LockRemindersSelectedTalent = spellID
	Print(SpellName(spellID) .. " plays an animation when it activates.")
	Touch()
end

local function RemoveTalent(spellID)
	local name = SpellName(spellID)
	local removed = false
	local numberID = tonumber(spellID)
	local keys = { spellID }
	if numberID then
		keys[#keys + 1] = numberID
		keys[#keys + 1] = tostring(numberID)
	end
	for index = 1, #keys do
		if db.talents[keys[index]] ~= nil then
			db.talents[keys[index]] = nil
			removed = true
		end
	end
	Print(removed and ("Removed: " .. name .. ".") or "It was not on the list.")
	Touch()
end

local function SpellEntry(spellID, name, icon, sub, kind)
	local savedKey
	if kind == "food" then
		if db.food[spellID] ~= nil then
			savedKey = spellID
		end
	elseif kind == "talent" then
		savedKey = TalentKey(spellID)
	else
		savedKey = SavedAuraKey(spellID)
	end
	local storedID = savedKey or spellID
	local entry = {
		kind = "spell",
		spellID = storedID,
		name = name,
		icon = icon or SpellIcon(storedID),
		sub = sub,
		saved = savedKey ~= nil,
		sortName = Normalize(name),
		rank = 0,
	}
	entry.action = function()
		if kind == "talent" then
			if savedKey then
				RemoveTalent(savedKey)
			else
				AddTalent(spellID)
			end
		elseif kind == "food" then
			if db.food[spellID] then
				RemoveSpell(spellID, "food")
			else
				AddFood(spellID)
			end
		elseif savedKey then
			RemoveSpell(savedKey, "aura")
		else
			AddAura(spellID, addScope)
		end
	end
	if kind == "talent" and savedKey then
		local stored = LockRemindersEnsureTalent(savedKey)
		local untilEnd = db.talentUntilEnd
		if untilEnd == nil then
			untilEnd = stored and stored.untilEnd
		end
		entry.extraLabel = untilEnd and "Until end" or "Seconds"
		entry.sub = LockRemindersLookLabel(stored and stored.style) .. " · " .. LockRemindersSoundLabel(stored and stored.sound)
		entry.select = function()
			LockRemindersSelectedTalent = savedKey
			if talentBar and talentBar.refresh then
				talentBar.refresh()
			end
			Touch()
		end
		entry.extra = function()
			local on = not (db.talentUntilEnd and true or false)
			if db.talentUntilEnd == nil then
				on = not (stored and stored.untilEnd)
			end
			db.talentUntilEnd = on and true or false
			stored = LockRemindersEnsureTalent(savedKey)
			if stored then
				stored.untilEnd = db.talentUntilEnd and true or false
			end
			Print(db.talentUntilEnd and "The alert stays until the buff ends." or "The alert lasts for the chosen seconds.")
			Touch()
		end
	end
	if kind == "food" and savedKey then
		entry.scopes = true
		entry.foodScope = true
		entry.sub = "On your list · " .. ScopeLabel(LockRemindersFoodScope(nil, savedKey))
	end
	if kind ~= "food" and kind ~= "talent" and savedKey then
		entry.scopes = true
	end
	return entry
end

local function ItemEntry(itemID, name, icon, sub, rank)
	local entry = {
		kind = "item",
		itemID = itemID,
		name = name or "Loading...",
		icon = PlainNumber(icon) or ItemIcon(itemID) or 134062,
		sub = sub,
		saved = db.foodItems[itemID] ~= nil,
		sortName = Normalize(name or ""),
		rank = rank or 0,
	}
	if entry.saved then
		entry.scopes = true
		entry.foodScope = true
		entry.sub = (sub or "On your list") .. " · " .. ScopeLabel(LockRemindersFoodScope(itemID, nil))
	end
	entry.action = function()
		if db.foodItems[itemID] then
			RemoveFoodItem(itemID)
		else
			AddFoodItem(itemID)
		end
	end
	return entry
end

local function AuraSub(spellID, kind, fallback)
	if kind == "food" then
		if db.food[spellID] then
			return "On your list · food"
		end
		return fallback
	end
	local key = SavedAuraKey(spellID)
	if key then
		local label = "On your list · " .. ScopeLabel(AuraScope(key))
		if not KnowsSpell(spellID) then
			return label .. " · once learned"
		end
		return label
	end
	return fallback
end

local function CollectPowers(query, typedID, spellLink)
	local seen = {}
	local seenNames = {}
	local pinned = {}
	local book = {}

	local function remember(spellID, name)
		seen[spellID] = true
		local aliases = SpellAliases(spellID)
		for index = 1, #aliases do
			seen[aliases[index]] = true
		end
		if name and name ~= "" then
			seenNames[Normalize(name)] = true
		end
	end

	local function known(spellID, name)
		if seen[spellID] then
			return true
		end
		local aliases = SpellAliases(spellID)
		for index = 1, #aliases do
			if seen[aliases[index]] then
				return true
			end
		end
		return name and name ~= "" and seenNames[Normalize(name)] or false
	end

	local saved = {}
	for spellID, where in pairs(db.auras) do
		local name = SpellDisplayName(spellID) or SpellName(spellID)
		if NameMatches(name, query) then
			remember(spellID, name)
			saved[#saved + 1] = SpellEntry(spellID, name, SpellIcon(spellID), ScopeLabel(where), "aura")
		end
	end
	SortByName(saved)

	if query ~= "" then
		local spells = CollectSpellbook()
		for index = 1, #spells do
			local info = spells[index]
			if not known(info.spellID, info.name) and NameMatches(info.name, query) then
				remember(info.spellID, info.name)
				local sub = info.offspec and "Other specialization" or "Spellbook"
				book[#book + 1] = SpellEntry(info.spellID, info.name, info.icon, AuraSub(info.spellID, "aura", sub), "aura")
			end
		end
		SortByName(book)
	end

	local function pin(spellID)
		if not spellID or known(spellID, nil) then
			return
		end
		local info = C_Spell.GetSpellInfo(spellID)
		if not info then
			if C_Spell.RequestLoadSpellData then
				C_Spell.RequestLoadSpellData(spellID)
			end
			return
		end
		seen[spellID] = true
		local name = info.name
		if not name or name == "" then
			name = "Loading..."
		end
		remember(spellID, name)
		pinned[#pinned + 1] = SpellEntry(spellID, name, info.iconID, AuraSub(spellID, "aura", "By ID"), "aura")
	end

	pin(spellLink)
	pin(typedID)
	local _, classFile = UnitClass("player")
	local petClass = classFile == "WARLOCK" or classFile == "HUNTER"
	local petWanted = petClass and (query == "" or NameMatches("Mascota", query) or NameMatches("Pet", query))
	if petWanted and type(db.pet) == "table" then
		local petRow = {
			pet = true,
			name = "Pet",
			icon = 136216,
			sub = "On your list · " .. ScopeLabel(db.pet),
			saved = true,
			scopes = true,
			sortName = "pet",
		}
		petRow.action = function()
			db.pet = nil
			Print("Pet alert turned off.")
			Touch()
		end
		table.insert(saved, 1, petRow)
	end
	local sections = Sections(
		{ title = "Your list", rows = saved },
		{ title = "That spell", rows = pinned },
		{ title = "Spellbook", rows = book }
	)
	if petWanted and type(db.pet) ~= "table" then
		local petRow = {
			pet = true,
			name = "Pet",
			icon = 136216,
			sub = "Alerts when you have no pet",
			saved = false,
			sortName = "pet",
		}
		petRow.action = function()
			local always, party, raid, instance = ScopeFlags(addScope)
			db.pet = { always = always, party = party, raid = raid, instance = instance, combat = false }
			Print("Pet alert turned on.")
			Touch()
		end
		table.insert(sections, 1, { title = "Pet", rows = { petRow } })
	end
	return sections
end

local function CollectTalents(query)
	local saved = {}
	local found = {}
	local seenNames = {}

	for spellID in pairs(db.talents) do
		local name = SpellDisplayName(spellID) or SpellName(spellID)
		local nameKey = Normalize(name or "")
		if NameMatches(name, query) and not (nameKey ~= "" and seenNames[nameKey]) then
			if nameKey ~= "" then
				seenNames[nameKey] = true
			end
			saved[#saved + 1] = SpellEntry(spellID, name, SpellIcon(spellID), "Plays when it activates", "talent")
		end
	end

	local function offer(spellID, name, icon, sub, talentName)
		spellID = tonumber(spellID)
		if not spellID or TalentKey(spellID) then
			return
		end
		local resolved
		local okName, display = pcall(SpellDisplayName, spellID)
		if okName then
			resolved = Plain(display)
		end
		if not resolved or (resolved:find("^Hechizo ", 1, true) or resolved:find("^Spell ", 1, true)) then
			resolved = nil
		end
		name = resolved or name
		if not name or (name:find("^Hechizo ", 1, true) or name:find("^Spell ", 1, true)) then
			return
		end
		if query ~= "" and not NameMatches(name, query) and not NameMatches(talentName, query) then
			return
		end
		local nameKey = Normalize(name)
		if nameKey ~= "" and seenNames[nameKey] then
			return
		end
		if nameKey ~= "" then
			seenNames[nameKey] = true
		end
		found[#found + 1] = SpellEntry(spellID, name, icon or SpellIcon(spellID), sub, "talent")
	end

	local function talentKey(name)
		local key = Normalize(name or "")
		key = key:gsub("'", ""):gsub("’", "")
		return key
	end

	local _, classFile = UnitClass("player")
	local byClass = {
		WARLOCK = {
			nightfall = { 17941, "Shadow Trance" },
			anochecer = { 17941, "Shadow Trance" },
			["caida de la noche"] = { 17941, "Shadow Trance" },
			["shadow trance"] = { 17941, "Shadow Trance" },
			["trance de las sombras"] = { 17941, "Shadow Trance" },
			backlash = { 34936, "Backlash" },
			contragolpe = { 34936, "Backlash" },
			decimation = { 440873, "Decimation" },
			decimacion = { 440873, "Decimation" },
			conflagrate = { 1293817, "Conflagrate" },
			conflagrar = { 1293817, "Conflagrate" },
			conflagracion = { 1293817, "Conflagrate" },
		},
		MAGE = {
			["arcane concentration"] = { 12536, "Clearcasting" },
			["concentracion arcana"] = { 12536, "Clearcasting" },
			["presence of mind"] = { 12043, "Presence of Mind" },
			["presencia de mente"] = { 12043, "Presence of Mind" },
		},
		PRIEST = {
			["spirit tap"] = { 15271, "Spirit Tap" },
			["toque de espiritu"] = { 15271, "Spirit Tap" },
			["inner focus"] = { 14751, "Inner Focus" },
			["enfoque interno"] = { 14751, "Inner Focus" },
		},
		SHAMAN = {
			["elemental focus"] = { 16246, "Elemental Focus" },
			["enfoque elemental"] = { 16246, "Elemental Focus" },
			["natures swiftness"] = { 16188, "Nature's Swiftness" },
			["rapidez de la naturaleza"] = { 16188, "Nature's Swiftness" },
			flurry = { 16257, "Flurry" },
			aluvion = { 16257, "Flurry" },
		},
		DRUID = {
			["natures grace"] = { 16886, "Nature's Grace" },
			["gracia de la naturaleza"] = { 16886, "Nature's Grace" },
			["omen of clarity"] = { 16870, "Clearcasting" },
			["augurio de claridad"] = { 16870, "Clearcasting" },
			["natures swiftness"] = { 17116, "Nature's Swiftness" },
			["rapidez de la naturaleza"] = { 17116, "Nature's Swiftness" },
		},
		WARRIOR = {
			enrage = { 12880, "Enrage" },
			enfurecer = { 12880, "Enrage" },
			flurry = { 12974, "Flurry" },
			aluvion = { 12974, "Flurry" },
			["sweeping strikes"] = { 12328, "Sweeping Strikes" },
			["golpes de barrido"] = { 12328, "Sweeping Strikes" },
		},
		ROGUE = {
			["blade flurry"] = { 13877, "Blade Flurry" },
			["rafaga de hojas"] = { 13877, "Blade Flurry" },
			["adrenaline rush"] = { 13750, "Adrenaline Rush" },
			["subidon de adrenalina"] = { 13750, "Adrenaline Rush" },
		},
		PALADIN = {
			vengeance = { 20053, "Vengeance" },
			venganza = { 20053, "Vengeance" },
		},
		HUNTER = {
			["trueshot aura"] = { 19506, "Trueshot Aura" },
			["aura de disparo certero"] = { 19506, "Trueshot Aura" },
			["rapid fire"] = { 3045, "Rapid Fire" },
			["fuego rapido"] = { 3045, "Rapid Fire" },
		},
	}
	local catalog = byClass[classFile] or {}

	local function takeLearned(name, icon)
		name = Plain(name)
		if not name then
			return
		end
		local buff = catalog[talentKey(name)]
		if buff then
			offer(buff[1], buff[2], icon, "From " .. name, name)
		end
	end

	-- Forever uses C_Traits. Classic GetTalentInfo is missing here.
	pcall(function()
		local configID
		if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
			local okGroup, group = pcall(C_SpecializationInfo.GetActiveSpecGroup)
			group = okGroup and PlainNumber(group)
			if group then
				local okConfig, id = pcall(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group)
				if okConfig then
					configID = PlainNumber(id)
				end
			end
		end
		if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
			local okConfig, id = pcall(C_ClassTalents.GetActiveConfigID)
			if okConfig then
				configID = PlainNumber(id)
			end
		end
		if not configID or not C_Traits or not C_Traits.GetConfigInfo or not C_Traits.GetTreeNodes or not C_Traits.GetNodeInfo then
			return
		end
		local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
		local trees = okInfo and configInfo and configInfo.treeIDs
		if type(trees) ~= "table" then
			return
		end
		for treeIndex = 1, #trees do
			local treeID = PlainNumber(trees[treeIndex]) or trees[treeIndex]
			local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
			if okNodes and type(nodes) == "table" then
				for nodeIndex = 1, #nodes do
					local nodeID = PlainNumber(nodes[nodeIndex]) or nodes[nodeIndex]
					local okNode, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
					local rank = okNode and node and (PlainNumber(node.currentRank) or PlainNumber(node.ranksPurchased) or PlainNumber(node.activeRank)) or 0
					if rank > 0 then
						local entryID
						if type(node.activeEntry) == "table" then
							entryID = PlainNumber(node.activeEntry.entryID)
						else
							entryID = PlainNumber(node.activeEntry)
						end
						if not entryID and type(node.entryIDs) == "table" then
							entryID = PlainNumber(node.entryIDs[1])
						end
						local talentName, talentIcon
						if entryID and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo then
							local okEntry, entry = pcall(C_Traits.GetEntryInfo, configID, entryID)
							local definitionID = okEntry and entry and PlainNumber(entry.definitionID)
							if definitionID then
								local okDef, definition = pcall(C_Traits.GetDefinitionInfo, definitionID)
								if okDef and definition then
									talentName = Plain(definition.overrideName)
									talentIcon = PlainNumber(definition.overrideIcon)
									if not talentName then
										local spellID = PlainNumber(definition.spellID) or PlainNumber(definition.overriddenSpellID)
										if spellID then
											talentName = SpellName(spellID)
											talentIcon = talentIcon or SpellIcon(spellID)
										end
									end
								end
							end
						end
						takeLearned(talentName, talentIcon)
					end
				end
			end
		end
	end)

	pcall(function()
		if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then
			return
		end
		local okTabs, tabCount = pcall(GetNumTalentTabs)
		tabCount = okTabs and PlainNumber(tabCount) or 0
		for tab = 1, tabCount do
			local okCount, count = pcall(GetNumTalents, tab)
			count = okCount and PlainNumber(count) or 0
			for index = 1, count do
				local okInfo, name, icon, _, _, rank = pcall(GetTalentInfo, tab, index)
				name = okInfo and Plain(name)
				rank = PlainNumber(rank) or 0
				if name and rank > 0 then
					takeLearned(name, icon)
				end
			end
		end
	end)

	-- Forever / Season spells that may not appear as classic talent rows.
	if classFile == "WARLOCK" then
		if KnowsSpell(440873) or KnowsSpell(440870) then
			offer(440873, "Decimation", SpellIcon(440873), "Soul Fire instant", "Decimation")
		end
		if KnowsSpell(1293817) or KnowsSpell(17962) then
			local confID = KnowsSpell(1293817) and 1293817 or 17962
			offer(confID, "Conflagrate", SpellIcon(confID), "Ready while Immolate", "Conflagrate")
		end
	end

	-- Search by talent or buff name even when the tree API did not surface it.
	if query ~= "" then
		for key, buff in pairs(catalog) do
			if key:find(query, 1, true) or NameMatches(buff[2], query) then
				offer(buff[1], buff[2], SpellIcon(buff[1]), "Talent buff", key)
			end
		end
	end

	SortByName(saved)
	SortByName(found)
	return Sections(
		{ title = "Plays when active", rows = saved },
		{ title = "Buffs from your talents", rows = found }
	)
end

local function HealthstoneSection(query)
	if not LockRemindersIsWarlock() then
		return nil
	end
	if query ~= "" and not NameMatches("Healthstone", query) then
		return nil
	end
	local added = type(db.healthstone) == "table"
	local sub = "Alerts when you have none in your bags"
	if added then
		local ok, label = pcall(ScopeLabel, db.healthstone)
		if ok and type(label) == "string" and label ~= "" then
			sub = "On your list · " .. label
		else
			sub = "On your list"
		end
	end
	local icon = SpellIcon(CREATE_HEALTHSTONE)
	if icon == nil or icon == 134400 then
		icon = ItemIcon(5512) or 135230
	end
	local stoneRow = {
		stone = true,
		name = "Healthstone",
		icon = icon,
		sub = sub,
		saved = added,
		scopes = added and true or false,
		sortName = "healthstone",
	}
	stoneRow.action = function()
		if type(db.healthstone) == "table" then
			db.healthstone = nil
			Print("Healthstone alert turned off.")
		else
			local always, party, raid, instance = ScopeFlags(addScope)
			db.healthstone = { always = always, party = party, raid = raid, instance = instance, combat = false }
			Print("Healthstone alert turned on.")
		end
		Touch()
	end
	return { title = "Healthstone", rows = { stoneRow } }
end

local function CollectFood(query, typedID, itemLink)
	local okScan, sections = pcall(function()
	local seen = {}
	local buckets = {}
	local counts, icons, names = BagContents()

	local function push(itemID, name, icon, sub, group)
		itemID = tonumber(itemID)
		if not itemID or seen[itemID] then
			return
		end
		seen[itemID] = true
		if not name or name == "" then
			RequestItem(itemID)
			name = "Loading..."
		end
		group = group or "Food"
		local rows = buckets[group]
		if not rows then
			rows = {}
			buckets[group] = rows
		end
		rows[#rows + 1] = ItemEntry(itemID, name, icon, sub, 0)
	end

	for itemID, count in pairs(counts) do
		pcall(function()
			local name = names[itemID] or ItemName(itemID)
			local nameHit = query ~= "" and NameMatches(name, query)
			local wanted = query == "" or itemID == itemLink or itemID == typedID or nameHit
			if not wanted then
				return
			end
			local saved = db.foodItems[itemID] ~= nil
			local eatFood = LockRemindersIsEatFood(itemID, name)
			local group = ConsumableGroup(itemID)
			local consumable = IsConsumableItem(itemID)
			-- Well Fed food (cooked meat, etc.) — primary path for this tab.
			if eatFood or saved then
				local sub = eatFood and "Well Fed" or (group or "Food")
				if saved then
					sub = "On your list · " .. sub
				else
					sub = sub .. " · x" .. tostring(count)
				end
				push(itemID, name, icons[itemID], sub, "Food")
				return
			end
			-- Flasks / elixirs / kept potions only when they are real consumables.
			if not consumable then
				return
			end
			if group ~= "Flasks" and group ~= "Elixirs" and group ~= "Potions" then
				return
			end
			if not ConsumableKept(itemID) then
				return
			end
			local sub = group .. " · x" .. tostring(count)
			push(itemID, name, icons[itemID], sub, group)
		end)
	end

	local function pin(itemID)
		if not itemID or seen[itemID] then
			return
		end
		local saved = db.foodItems[itemID] ~= nil
		local name = names[itemID] or ItemName(itemID)
		local eatFood = LockRemindersIsEatFood(itemID, name)
		if not saved and not eatFood and not ConsumableKept(itemID) then
			return
		end
		if query ~= "" and itemID ~= typedID and itemID ~= itemLink and not NameMatches(name, query) then
			return
		end
		local group = eatFood and "Food" or ConsumableGroup(itemID)
		local sub = eatFood and "Well Fed" or group
		if saved then
			sub = "On your list · " .. sub
		end
		push(itemID, name, icons[itemID] or ItemIcon(itemID), sub, group == "Food" and "Food" or group)
	end

	pcall(pin, itemLink)
	pcall(pin, typedID)
	for itemID in pairs(db.foodItems) do
		pcall(pin, itemID)
	end

	local order = { "Food", "Potions", "Flasks", "Elixirs", "Other" }
	local sections = {}
	for index = 1, #order do
		local title = order[index]
		local rows = buckets[title]
		if rows and #rows > 0 then
			SortByName(rows)
			sections[#sections + 1] = { title = title, rows = rows }
		end
	end
	local foodSpells = {}
	for spellID in pairs(db.food) do
		local name = SpellDisplayName(spellID) or SpellName(spellID)
		if NameMatches(name, query) then
			foodSpells[#foodSpells + 1] = SpellEntry(spellID, name, SpellIcon(spellID), "On your list", "food")
		end
	end
	if #foodSpells > 0 then
		SortByName(foodSpells)
		sections[#sections + 1] = { title = "On your list", rows = foodSpells }
	end
	return sections
	end)
	if not okScan or type(sections) ~= "table" then
		sections = {}
	end
	local stone = HealthstoneSection(query)
	if stone then
		table.insert(sections, 1, stone)
	end
	return sections
end

local function CollectSaved(query)
	local powers = {}
	local foods = {}

	local seenNames = {}
	for spellID, where in pairs(db.auras) do
		local name = SpellDisplayName(spellID) or SpellName(spellID)
		local nameKey = Normalize(name or "")
		if NameMatches(name, query) and not (nameKey ~= "" and seenNames[nameKey]) then
			if nameKey ~= "" then
				seenNames[nameKey] = true
			end
			local entry = SpellEntry(spellID, name, SpellIcon(spellID), ScopeLabel(where), "aura")
			powers[#powers + 1] = entry
		end
	end

	for spellID in pairs(db.food) do
		local name = SpellDisplayName(spellID) or SpellName(spellID)
		if NameMatches(name, query) then
			foods[#foods + 1] = SpellEntry(spellID, name, SpellIcon(spellID), "Food buff", "food")
		end
	end

	for itemID, value in pairs(db.foodItems) do
		local name = ItemName(itemID)
		if not name then
			RequestItem(itemID)
			name = "Item " .. itemID
		end
		if NameMatches(name, query) then
			local sub = type(value) == "number" and "Food item" or "Item · missing buff"
			foods[#foods + 1] = ItemEntry(itemID, name, ItemIcon(itemID), sub, 0)
		end
	end

	SortByName(powers)
	SortByName(foods)
	return Sections(
		{ title = "Buffs", rows = powers },
		{ title = "Items", rows = foods }
	)
end

function LockRemindersMissCoreName(name)
	name = Normalize(name or "")
	name = name:gsub("%s*%(rank %d+%)", ""):gsub("%s+rank %d+", "")
	name = name:gsub("^bane of ", ""):gsub("^curse of ", ""):gsub("^curse ", "")
	name = name:gsub("^hechizo ", ""):gsub("^spell ", "")
	return name
end

function LockRemindersMissNamesEqual(left, right)
	left = Normalize(left or ""):gsub("%s*%(rank %d+%)", ""):gsub("%s+rank %d+", "")
	right = Normalize(right or ""):gsub("%s*%(rank %d+%)", ""):gsub("%s+rank %d+", "")
	if left == "" or right == "" then
		return false
	end
	if left == right then
		return true
	end
	local a = LockRemindersMissCoreName(left)
	local b = LockRemindersMissCoreName(right)
	return a ~= "" and a == b
end

function LockRemindersCacheMissNames()
	if not db or type(db.missSpells) ~= "table" then
		return
	end
	local previous = type(db.missNames) == "table" and db.missNames or {}
	local nextNames = {}
	for key in pairs(db.missSpells) do
		local spellID = tonumber(key)
		if spellID then
			local idKey = tostring(spellID)
			local name = SpellName(spellID)
			local wanted = Normalize(name or "")
			if wanted ~= "" and not wanted:find("^spell ", 1, true) and not wanted:find("^hechizo ", 1, true) then
				nextNames[idKey] = name
			elseif previous[idKey] or previous[spellID] then
				nextNames[idKey] = previous[idKey] or previous[spellID]
			end
		end
	end
	db.missNames = nextNames
end

function LockRemindersMissSpellSaved(spellID, spellName)
	if not db or type(db.missSpells) ~= "table" then
		return false
	end
	if LockRemindersSecret(spellID) then
		for key in pairs(db.missSpells) do
			local saved = tonumber(key)
			if saved and LockRemindersSameSpell(spellID, saved) then
				return true
			end
			if saved then
				local aliases = SpellAliases(saved)
				for index = 1, #aliases do
					if LockRemindersSameSpell(spellID, aliases[index]) then
						return true
					end
				end
			end
		end
		local books = { CollectSpellbook(true), LockRemindersCollectPetSpells() }
		for bookIndex = 1, #books do
			local book = books[bookIndex]
			if type(book) == "table" then
				for index = 1, #book do
					local entry = book[index]
					if entry and LockRemindersSameSpell(spellID, entry.spellID) and LockRemindersMissSpellSaved(entry.spellID, entry.name) then
						return true
					end
				end
			end
		end
		return false
	end
	spellID = tonumber(spellID)
	if spellID and (db.missSpells[spellID] or db.missSpells[tostring(spellID)]) then
		return true
	end
	if spellID then
		for key in pairs(db.missSpells) do
			local saved = tonumber(key)
			if saved then
				local aliases = SpellAliases(saved)
				for index = 1, #aliases do
					if aliases[index] == spellID then
						return true
					end
				end
			end
		end
	end
	local wanted = Normalize(spellName or "")
	wanted = wanted:gsub("%s*%(rank %d+%)", ""):gsub("%s+rank %d+", "")
	if wanted == "" or wanted:find("^spell ", 1, true) or wanted:find("^hechizo ", 1, true) then
		return false
	end
	if type(db.missNames) == "table" then
		for _, name in pairs(db.missNames) do
			if LockRemindersMissNamesEqual(name, wanted) then
				return true
			end
		end
	end
	for key in pairs(db.missSpells) do
		local name = SpellName(key)
		if LockRemindersMissNamesEqual(name, wanted) then
			if type(db.missNames) ~= "table" then
				db.missNames = {}
			end
			db.missNames[tostring(tonumber(key) or key)] = name
			return true
		end
	end
	return false
end

function LockRemindersAddMissSpell(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return
	end
	db.missSpells[spellID] = true
	if type(db.missNames) ~= "table" then
		db.missNames = {}
	end
	local name = SpellName(spellID)
	if type(name) == "string" and name ~= "" then
		db.missNames[tostring(spellID)] = name
	end
	LockRemindersCacheMissNames()
	Print((name or SpellName(spellID) or "Spell") .. " will alert when it misses or resists.")
	Touch()
end

function LockRemindersRemoveMissSpell(spellID, spellName)
	local wanted = Normalize(spellName or SpellName(spellID) or "")
	wanted = wanted:gsub("%s*%(rank %d+%)", ""):gsub("%s+rank %d+", "")
	local numberID = tonumber(spellID)
	if numberID then
		db.missSpells[numberID] = nil
		db.missSpells[tostring(numberID)] = nil
	end
	if spellID ~= nil then
		db.missSpells[spellID] = nil
	end
	if wanted ~= "" then
		local drop = {}
		for key in pairs(db.missSpells) do
			local name = Normalize(SpellName(key) or ""):gsub("%s*%(rank %d+%)", ""):gsub("%s+rank %d+", "")
			if name ~= "" and name == wanted then
				drop[#drop + 1] = key
			end
		end
		for index = 1, #drop do
			db.missSpells[drop[index]] = nil
		end
	end
	LockRemindersCacheMissNames()
	Print("Removed from spell alerts.")
	Touch()
end

function LockRemindersCollectPetSpells()
	local spells = {}
	local seen = {}
	local function push(spellID, name, icon)
		spellID = tonumber(spellID)
		if not spellID or spellID <= 0 or seen[spellID] then
			return
		end
		if issecretvalue and issecretvalue(spellID) then
			return
		end
		name = SpellDisplayName(spellID, name) or name
		if type(name) ~= "string" or name == "" then
			return
		end
		seen[spellID] = true
		spells[#spells + 1] = {
			spellID = spellID,
			name = name,
			icon = icon or SpellIcon(spellID),
		}
	end

	if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet then
		pcall(function()
			local bank = Enum.SpellBookSpellBank.Pet
			local future = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
			local lines = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
			for line = 1, lines do
				local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
				if info and info.numSpellBookItems and info.itemIndexOffset then
					for index = 1, info.numSpellBookItems do
						local item = C_SpellBook.GetSpellBookItemInfo(info.itemIndexOffset + index, bank)
						if item and item.spellID and item.itemType ~= future and not item.isPassive then
							push(item.spellID, item.name, item.iconID)
						end
					end
				end
			end
		end)
	end

	if #spells == 0 and HasPetSpells and GetSpellBookItemInfo then
		pcall(function()
			local num = tonumber(HasPetSpells()) or 0
			local book = BOOKTYPE_PET or "pet"
			for index = 1, num do
				local spellType, spellID = GetSpellBookItemInfo(index, book)
				if spellID and spellType == "SPELL" then
					local passive = IsPassiveSpell and IsPassiveSpell(index, book)
					if not passive then
						local name = GetSpellBookItemName and GetSpellBookItemName(index, book)
						push(spellID, name)
					end
				end
			end
		end)
	end
	return spells
end

function LockRemindersMissSpellEntry(spellID, name, icon, fromPet)
	local saved = LockRemindersMissSpellSaved(spellID, name)
	local entry = {
		kind = "miss",
		spellID = spellID,
		name = name,
		icon = icon or SpellIcon(spellID),
		sub = saved and "On your list · miss and resist" or (fromPet and "Pet spell" or "Spellbook"),
		saved = saved,
		sortName = Normalize(name or ""),
		rank = 0,
	}
	entry.action = function()
		if LockRemindersMissSpellSaved(spellID, name) then
			LockRemindersRemoveMissSpell(spellID, name)
		else
			LockRemindersAddMissSpell(spellID)
		end
	end
	return entry
end

function LockRemindersRacialName(name)
	if type(name) ~= "string" or name == "" or LockRemindersSecret(name) then
		return false
	end
	local wanted = Normalize(name)
	local names = {
		"touch of the grave", "touch of the gravity", "toque de la tumba", "toque de la gravedad",
		"blood fury", "furia sangrienta",
		"war stomp", "pisoton de guerra",
		"berserking",
		"arcane torrent", "torrente arcano",
		"stoneform", "forma de piedra",
		"shadowmeld", "fusion de las sombras",
		"will of the forsaken", "voluntad de los renegados", "voluntad de los renacidos",
		"cannibalize", "canibalizar",
		"escape artist", "artista del escape",
		"gift of the naaru", "don de los naaru",
		"every man for himself", "salvese quien pueda",
	}
	for index = 1, #names do
		local racial = names[index]
		if wanted == racial or wanted:sub(1, #racial) == racial then
			return true
		end
	end
	return false
end

function LockRemindersRacialLine(name)
	if type(name) ~= "string" or name == "" or LockRemindersSecret(name) then
		return false
	end
	local wanted = Normalize(name)
	return wanted:find("racial", 1, true) or wanted:find("raza", 1, true)
end

function LockRemindersCollectRacials()
	local spells = {}
	local seen = {}
	local function push(spellID, name, icon)
		spellID = tonumber(spellID)
		if not spellID or spellID <= 0 or seen[spellID] then
			return
		end
		if issecretvalue and issecretvalue(spellID) then
			return
		end
		name = SpellDisplayName(spellID, name) or name
		if type(name) ~= "string" or name == "" or LockRemindersSecret(name) then
			return
		end
		seen[spellID] = true
		spells[#spells + 1] = {
			spellID = spellID,
			name = name,
			icon = icon or SpellIcon(spellID),
		}
	end
	local function want(lineName, spellName)
		return LockRemindersRacialLine(lineName) or LockRemindersRacialName(spellName)
	end
	if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetNumSpellBookSkillLines then
		pcall(function()
			local bank = Enum.SpellBookSpellBank.Player
			local future = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
			local flyout = Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout
			local lines = C_SpellBook.GetNumSpellBookSkillLines()
			for line = 1, lines do
				local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
				if info and info.numSpellBookItems and info.numSpellBookItems > 0 and info.itemIndexOffset then
					for index = 1, info.numSpellBookItems do
						local item = C_SpellBook.GetSpellBookItemInfo(info.itemIndexOffset + index, bank)
						if item and item.spellID and item.itemType ~= future and item.itemType ~= flyout and want(info.name, item.name) then
							push(item.spellID, item.name, item.iconID)
						end
					end
				end
			end
		end)
	end
	if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		pcall(function()
			local book = BOOKTYPE_SPELL or "spell"
			for tab = 1, GetNumSpellTabs() do
				local lineName, _, offset, numSlots = GetSpellTabInfo(tab)
				if offset and numSlots then
					for index = offset + 1, offset + numSlots do
						local spellType, spellID = GetSpellBookItemInfo(index, book)
						if spellType == "SPELL" and spellID then
							local name = GetSpellBookItemName and GetSpellBookItemName(index, book)
							if want(lineName, name) then
								push(spellID, name)
							end
						end
					end
				end
			end
		end)
	end
	return spells
end

function LockRemindersCollectSpellMiss(query, typedID, spellLink)
	local saved = {}
	local book = {}
	local pets = {}
	local racials = {}
	local seen = {}

	local function remember(spellID, name)
		spellID = tonumber(spellID)
		if spellID then
			seen[spellID] = true
		end
		if name and name ~= "" then
			seen[Normalize(name)] = true
		end
	end

	for spellID in pairs(db.missSpells) do
		local name = SpellDisplayName(spellID) or SpellName(spellID)
		if NameMatches(name, query) then
			remember(spellID, name)
			saved[#saved + 1] = LockRemindersMissSpellEntry(spellID, name, SpellIcon(spellID), false)
		end
	end
	SortByName(saved)

	local function offer(info, fromPet, into, sub)
		if not info or seen[info.spellID] or seen[Normalize(info.name or "")] then
			return
		end
		if query ~= "" and info.spellID ~= typedID and info.spellID ~= spellLink and not NameMatches(info.name, query) then
			return
		end
		remember(info.spellID, info.name)
		local entry = LockRemindersMissSpellEntry(info.spellID, info.name, info.icon, fromPet)
		if sub and not entry.saved then
			entry.sub = sub
		end
		into[#into + 1] = entry
	end

	local spells = CollectSpellbook(false)
	for index = 1, #spells do
		offer(spells[index], false, book)
	end
	local petSpells = LockRemindersCollectPetSpells()
	for index = 1, #petSpells do
		offer(petSpells[index], true, pets)
	end
	local racialSpells = LockRemindersCollectRacials()
	for index = 1, #racialSpells do
		offer(racialSpells[index], false, racials, "Racial")
	end
	if typedID or spellLink then
		local pinned = spellLink or typedID
		if pinned and not seen[pinned] then
			local name = SpellName(pinned)
			if query == "" or NameMatches(name, query) or pinned == typedID or pinned == spellLink then
				book[#book + 1] = LockRemindersMissSpellEntry(pinned, name, SpellIcon(pinned), false)
			end
		end
	end
	SortByName(book)
	SortByName(pets)
	SortByName(racials)
	return Sections(
		{ title = "Chosen", rows = saved },
		{ title = "Racials", rows = racials },
		{ title = "Pet spells", rows = pets },
		{ title = "Your spells", rows = book }
	)
end

function LockRemindersCDKey(kind, id)
	return tostring(kind or "spell") .. ":" .. tostring(tonumber(id) or id or "")
end

function LockRemindersCDSpellSaved(spellID)
	spellID = tonumber(spellID)
	if not spellID or not db or type(db.cdSpells) ~= "table" then
		return false
	end
	return db.cdSpells[spellID] == true or db.cdSpells[tostring(spellID)] == true
end

function LockRemindersCDItemSaved(itemID)
	itemID = tonumber(itemID)
	if not itemID or not db or type(db.cdItems) ~= "table" then
		return false
	end
	return db.cdItems[itemID] == true or db.cdItems[tostring(itemID)] == true
end

function LockRemindersAddCDSpell(spellID)
	spellID = tonumber(spellID)
	if not spellID or not db then
		return
	end
	if type(db.cdSpells) ~= "table" then
		db.cdSpells = {}
	end
	db.cdSpells[spellID] = true
	Print((SpellName(spellID) or "Spell") .. " added to CD Manager.")
	Touch()
	pcall(LockRemindersCDPollSpell, spellID)
end

function LockRemindersRemoveCDSpell(spellID)
	spellID = tonumber(spellID)
	if not spellID or not db or type(db.cdSpells) ~= "table" then
		return
	end
	db.cdSpells[spellID] = nil
	db.cdSpells[tostring(spellID)] = nil
	local key = LockRemindersCDKey("spell", spellID)
	if LockRemindersCD.states then
		LockRemindersCD.states[key] = nil
	end
	LockRemindersDropCDOrder(key)
	Print("Removed from CD Manager.")
	Touch()
	pcall(LockRemindersCDLayout)
end

function LockRemindersAddCDItem(itemID)
	itemID = tonumber(itemID)
	if not itemID or not db then
		return
	end
	if type(db.cdItems) ~= "table" then
		db.cdItems = {}
	end
	db.cdItems[itemID] = true
	Print((ItemName(itemID) or "Trinket") .. " added to CD Manager.")
	Touch()
	pcall(LockRemindersCDPollItem, itemID)
end

function LockRemindersRemoveCDItem(itemID)
	itemID = tonumber(itemID)
	if not itemID or not db or type(db.cdItems) ~= "table" then
		return
	end
	db.cdItems[itemID] = nil
	db.cdItems[tostring(itemID)] = nil
	local key = LockRemindersCDKey("item", itemID)
	if LockRemindersCD.states then
		LockRemindersCD.states[key] = nil
	end
	LockRemindersDropCDOrder(key)
	Print("Removed from CD Manager.")
	Touch()
	pcall(LockRemindersCDLayout)
end

function LockRemindersDropCDOrder(key)
	if not db or type(db.cdOrder) ~= "table" or not key then
		return
	end
	for index = #db.cdOrder, 1, -1 do
		if db.cdOrder[index] == key then
			table.remove(db.cdOrder, index)
		end
	end
end

function LockRemindersCDCatalog()
	local list = {}
	local seen = {}
	if not db then
		return list
	end
	if type(db.cdSpells) == "table" then
		for raw in pairs(db.cdSpells) do
			local spellID = tonumber(raw)
			if spellID and not seen[spellID] and LockRemindersCDSpellSaved(spellID) then
				seen[spellID] = true
				list[#list + 1] = {
					key = LockRemindersCDKey("spell", spellID),
					icon = SpellIcon(spellID),
					text = SpellName(spellID) or ("Spell " .. spellID),
					spellID = spellID,
				}
			end
		end
	end
	if type(db.cdItems) == "table" then
		local seenItem = {}
		for raw in pairs(db.cdItems) do
			local itemID = tonumber(raw)
			if itemID and not seenItem[itemID] and LockRemindersCDItemSaved(itemID) then
				seenItem[itemID] = true
				list[#list + 1] = {
					key = LockRemindersCDKey("item", itemID),
					icon = ItemIcon(itemID) or 134400,
					text = ItemName(itemID) or ("Item " .. itemID),
					itemID = itemID,
				}
			end
		end
	end
	return list
end

function LockRemindersSyncCDOrder(list)
	list = list or LockRemindersCDCatalog()
	if type(db.cdOrder) ~= "table" then
		db.cdOrder = {}
	end
	local known = {}
	for index = 1, #list do
		known[list[index].key] = true
	end
	local kept = {}
	local seen = {}
	for index = 1, #db.cdOrder do
		local key = db.cdOrder[index]
		if type(key) == "string" and known[key] and not seen[key] then
			seen[key] = true
			kept[#kept + 1] = key
		end
	end
	for index = 1, #list do
		if not seen[list[index].key] then
			kept[#kept + 1] = list[index].key
		end
	end
	db.cdOrder = kept
	return list
end

function LockRemindersSortedCDs()
	local list = LockRemindersSyncCDOrder()
	local rank = {}
	for index = 1, #db.cdOrder do
		rank[db.cdOrder[index]] = index
	end
	table.sort(list, function(a, b)
		local ra = rank[a.key] or 9999
		local rb = rank[b.key] or 9999
		if ra == rb then
			return tostring(a.text or "") < tostring(b.text or "")
		end
		return ra < rb
	end)
	return list
end

function LockRemindersMoveCD(key, newIndex)
	local list = LockRemindersSortedCDs()
	local order = db.cdOrder
	local old
	for index = 1, #order do
		if order[index] == key then
			old = index
			break
		end
	end
	if not old or newIndex < 1 or newIndex > #order or newIndex == old then
		return
	end
	table.remove(order, old)
	table.insert(order, newIndex, key)
	pcall(LockRemindersCDLayout)
	LockRemindersShowCDOrder(false)
end

function LockRemindersCDOrderRank()
	local rank = {}
	if not db then
		return rank
	end
	LockRemindersSyncCDOrder()
	for index = 1, #db.cdOrder do
		rank[db.cdOrder[index]] = index
	end
	return rank
end

function LockRemindersCDSpellWorth(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return false
	end
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, spellID)
		ms = ok and tonumber(ms) or nil
		if ms then
			return ms >= 3000
		end
	end
	local left, duration = LockRemindersCDReadSpell(spellID)
	if duration and duration >= 3 then
		return true
	end
	return LockRemindersCDSpellSaved(spellID)
end

function LockRemindersCDSpellEntry(spellID, name, icon, sub)
	local saved = LockRemindersCDSpellSaved(spellID)
	local entry = {
		kind = "cd",
		spellID = spellID,
		name = name,
		icon = icon or SpellIcon(spellID),
		sub = saved and "On your list · cooldown" or (sub or "Spellbook"),
		saved = saved,
		sortName = Normalize(name or ""),
		rank = 0,
	}
	entry.action = function()
		if LockRemindersCDSpellSaved(spellID) then
			LockRemindersRemoveCDSpell(spellID)
		else
			LockRemindersAddCDSpell(spellID)
		end
	end
	return entry
end

function LockRemindersCDItemEntry(itemID, name, icon, sub)
	local saved = LockRemindersCDItemSaved(itemID)
	local entry = {
		kind = "cd",
		itemID = itemID,
		name = name or ItemName(itemID) or "Trinket",
		icon = icon or ItemIcon(itemID) or 134400,
		sub = saved and "On your list · cooldown" or (sub or "Trinket"),
		saved = saved,
		sortName = Normalize(name or ""),
		rank = 0,
	}
	entry.action = function()
		if LockRemindersCDItemSaved(itemID) then
			LockRemindersRemoveCDItem(itemID)
		else
			LockRemindersAddCDItem(itemID)
		end
	end
	return entry
end

function LockRemindersCDTrinketName(name)
	if type(name) ~= "string" or name == "" or LockRemindersSecret(name) then
		return false
	end
	local wanted = Normalize(name)
	return wanted:find("insignia", 1, true)
		or wanted:find("medallion", 1, true)
		or wanted:find("battlemaster", 1, true)
		or wanted:find("emblema", 1, true)
		or wanted:find("medallon", 1, true)
		or wanted:find("trinket", 1, true)
		or wanted:find("abalorio", 1, true)
end

function LockRemindersCollectCDManager(query, typedID, spellLink)
	local saved = {}
	local racials = {}
	local trinkets = {}
	local book = {}
	local seenSpell = {}
	local seenItem = {}

	if type(db.cdSpells) == "table" then
		for key in pairs(db.cdSpells) do
			local spellID = tonumber(key)
			if spellID and not seenSpell[spellID] then
				local name = SpellName(spellID)
				if NameMatches(name, query) then
					seenSpell[spellID] = true
					saved[#saved + 1] = LockRemindersCDSpellEntry(spellID, name, SpellIcon(spellID), "Cooldown")
				end
			end
		end
	end
	if type(db.cdItems) == "table" then
		for key in pairs(db.cdItems) do
			local itemID = tonumber(key)
			if itemID and not seenItem[itemID] then
				local name = ItemName(itemID)
				if NameMatches(name, query) then
					seenItem[itemID] = true
					saved[#saved + 1] = LockRemindersCDItemEntry(itemID, name, ItemIcon(itemID), "Trinket")
				end
			end
		end
	end
	do
		local orderRank = LockRemindersCDOrderRank()
		table.sort(saved, function(a, b)
			local ka = a.spellID and LockRemindersCDKey("spell", a.spellID) or LockRemindersCDKey("item", a.itemID)
			local kb = b.spellID and LockRemindersCDKey("spell", b.spellID) or LockRemindersCDKey("item", b.itemID)
			local ra = orderRank[ka] or 9999
			local rb = orderRank[kb] or 9999
			if ra ~= rb then
				return ra < rb
			end
			return Normalize(a.name or "") < Normalize(b.name or "")
		end)
	end

	local function offerSpell(info, into, sub, force)
		if not info or not info.spellID or seenSpell[info.spellID] then
			return
		end
		if query ~= "" and info.spellID ~= typedID and info.spellID ~= spellLink and not NameMatches(info.name, query) then
			return
		end
		if not force and not LockRemindersCDSpellWorth(info.spellID) and not LockRemindersCDSpellSaved(info.spellID) then
			return
		end
		seenSpell[info.spellID] = true
		into[#into + 1] = LockRemindersCDSpellEntry(info.spellID, info.name, info.icon, sub)
	end

	local racialSpells = LockRemindersCollectRacials()
	for index = 1, #racialSpells do
		offerSpell(racialSpells[index], racials, "Racial", true)
	end
	SortByName(racials)

	local function pushTrinket(itemID, sub)
		itemID = tonumber(itemID)
		if not itemID or seenItem[itemID] then
			return
		end
		local name = ItemName(itemID)
		if query ~= "" and not NameMatches(name, query) and tostring(itemID) ~= tostring(typedID or "") then
			return
		end
		seenItem[itemID] = true
		trinkets[#trinkets + 1] = LockRemindersCDItemEntry(itemID, name, ItemIcon(itemID), sub or "Trinket")
	end

	if GetInventoryItemID then
		for slot = 13, 14 do
			local ok, itemID = pcall(GetInventoryItemID, "player", slot)
			if ok and itemID then
				pushTrinket(itemID, slot == 13 and "Trinket 1" or "Trinket 2")
			end
		end
	end
	EachBagItem(function(itemID)
		local name = ItemName(itemID)
		if LockRemindersCDTrinketName(name) or LockRemindersCDItemSaved(itemID) then
			pushTrinket(itemID, "PVP / trinket")
		end
	end)
	SortByName(trinkets)

	local spells = CollectSpellbook(false)
	for index = 1, #spells do
		offerSpell(spells[index], book, "Spellbook", false)
	end
	if typedID or spellLink then
		local pinned = spellLink or typedID
		if pinned and not seenSpell[pinned] then
			local name = SpellName(pinned)
			if query == "" or NameMatches(name, query) or pinned == typedID or pinned == spellLink then
				book[#book + 1] = LockRemindersCDSpellEntry(pinned, name, SpellIcon(pinned), "Spellbook")
			end
		end
	end
	SortByName(book)

	return Sections(
		{ title = "Chosen", rows = saved },
		{ title = "Racials", rows = racials },
		{ title = "Trinkets / PVP", rows = trinkets },
		{ title = "Your spells", rows = book }
	)
end

local function EmptyMessage(query)
	if activeTab == "food" then
		if query ~= "" then
			return "That consumable is not in your bags."
		end
		return "No food, flasks, or buff potions in your bags."
	end
	if activeTab == "talents" then
		if query ~= "" then
			return "No talent buff with that name."
		end
		return "Buffs from talents you have already learned.\nNightfall, for example, alerts with Shadow Trance."
	end
	if activeTab == "spells" then
		if query ~= "" then
			return "No spell with that name in your spellbook, racials, or your pet's."
		end
		return "No spells to choose yet.\nSummon your pet to list its spells."
	end
	if activeTab == "cds" then
		if query ~= "" then
			return "No cooldown with that name in your spells, racials, or trinkets."
		end
		return "Add spells, racials, or trinkets to track.\nIcons show while on cooldown and pulse when ready."
	end
	if query ~= "" then
		return "No powers with that name."
	end
	if db and db.auras and next(db.auras) then
		return "Your list is above.\nType a name to find another power."
	end
	return "You have not added any powers yet.\nType a name to search."
end

local function ScrollBy(delta)
	if not scroll then
		return
	end
	local range = scroll:GetVerticalScrollRange() or 0
	local value = scroll:GetVerticalScroll() - delta * 48
	if value < 0 then
		value = 0
	end
	if value > range then
		value = range
	end
	scroll:SetVerticalScroll(value)
	if scrollBar then
		syncingScroll = true
		scrollBar:SetValue(value)
		syncingScroll = false
	end
end

local function UpdateScrollMetrics()
	if not scroll or not scrollBar then
		return
	end
	local range = scroll:GetVerticalScrollRange() or 0
	syncingScroll = true
	scrollBar:SetMinMaxValues(0, math.max(range, 0))
	if range <= 1 then
		scrollBar:Hide()
		scroll:SetVerticalScroll(0)
		scrollBar:SetValue(0)
	else
		scrollBar:Show()
		local value = scroll:GetVerticalScroll()
		if value > range then
			value = range
			scroll:SetVerticalScroll(value)
		end
		scrollBar:SetValue(value)
	end
	syncingScroll = false
end

local function BindWheel(widget)
	widget:EnableMouseWheel(true)
	widget:SetScript("OnMouseWheel", function(_, delta)
		ScrollBy(delta)
	end)
end

local function Tint(button, r, g, b, br, bg, bb)
	button.tint = { r, g, b, br, bg, bb }
	button:SetBackdropColor(r, g, b, 1)
	button:SetBackdropBorderColor(br, bg, bb, 1)
end

local function StyleAction(button, kind)
	if kind == "remove" then
		Tint(button, 0.32, 0.12, 0.14, 0.78, 0.32, 0.36)
		button.label:SetText("Remove")
		button.label:SetTextColor(1, 0.84, 0.84)
	elseif kind == "scope" then
		Tint(button, 0.18, 0.14, 0.28, 0.58, 0.45, 0.82)
		button.label:SetTextColor(0.94, 0.9, 1)
	else
		Tint(button, 0.12, 0.26, 0.16, 0.38, 0.72, 0.46)
		button.label:SetText("Add")
		button.label:SetTextColor(0.86, 1, 0.9)
	end
end

local function ShowRowTip(row)
	if not row.spellID and not row.itemID then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local ok = false
	if row.itemID then
		ok = pcall(GameTooltip.SetItemByID, GameTooltip, row.itemID)
	elseif row.spellID then
		ok = pcall(GameTooltip.SetSpellByID, GameTooltip, row.spellID)
	end
	if not ok then
		GameTooltip:Hide()
	end
end

local function MakeActionButton(parent)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(78, 22)
	Paint(button, 0.16, 0.12, 0.22, 1, 0.58, 0.45, 0.82, 1)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("CENTER", 0, 0)
	button:SetScript("OnEnter", function(self)
		local tint = self.tint
		if not tint then
			return
		end
		self:SetBackdropColor(math.min(1, tint[1] + 0.08), math.min(1, tint[2] + 0.08), math.min(1, tint[3] + 0.08), 1)
		ShowRowTip(parent)
	end)
	button:SetScript("OnLeave", function(self)
		local tint = self.tint
		if not tint then
			return
		end
		self:SetBackdropColor(tint[1], tint[2], tint[3], 1)
		self:SetBackdropBorderColor(tint[4], tint[5], tint[6], 1)
		GameTooltip:Hide()
	end)
	BindWheel(button)
	return button
end

local function AcquireHeader()
	usedHeaders = usedHeaders + 1
	local header = headerPool[usedHeaders]
	if header then
		return header
	end
	header = CreateFrame("Frame", nil, scrollChild)
	header:SetHeight(22)
	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	header.text:SetPoint("BOTTOMLEFT", 4, 2)
	header.text:SetTextColor(0.78, 0.68, 0.96)
	BindWheel(header)
	headerPool[usedHeaders] = header
	return header
end

local function AcquireRow()
	usedRows = usedRows + 1
	local row = rowPool[usedRows]
	if row then
		return row
	end

	row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
	row:SetHeight(50)
	Paint(row, 1, 1, 1, 0.035, 1, 1, 1, 0.04)
	row:EnableMouse(true)
	BindWheel(row)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(32, 32)
	row.icon:SetPoint("LEFT", 8, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.main = MakeActionButton(row)
	row.main:SetPoint("RIGHT", -6, 0)
	row.main:SetFrameLevel(row:GetFrameLevel() + 8)
	row.main:SetScript("OnClick", function()
		if row.entry and row.entry.action then
			row.entry.action()
		end
	end)

	row.extra = MakeActionButton(row)
	row.extra:SetPoint("RIGHT", row.main, "LEFT", -4, 0)
	row.extra:SetFrameLevel(row:GetFrameLevel() + 3)
	row.extra:SetScript("OnClick", function()
		if row.entry and row.entry.extra then
			row.entry.extra()
		end
	end)

	row.scopes = CreateFrame("Frame", nil, row)
	row.scopes:SetHeight(22)
	row.scopes:SetPoint("RIGHT", row.main, "LEFT", -8, 0)
	row.scopes:SetFrameLevel(row:GetFrameLevel() + 2)
	row.scopes:EnableMouse(false)
	local function AddScopeBox(flag, label, x, gap)
		local box = CreateFrame("Button", nil, row.scopes, "BackdropTemplate")
		box:SetSize(14, 14)
		box:SetPoint("LEFT", row.scopes, "LEFT", x, 0)
		box:SetFrameLevel(row.scopes:GetFrameLevel() + 1)
		Paint(box, 0.08, 0.06, 0.1, 1, 0.58, 0.45, 0.82, 1)
		box.mark = box:CreateTexture(nil, "OVERLAY")
		box.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		box.mark:SetSize(16, 16)
		box.mark:SetPoint("CENTER", 0, 0)
		box.mark:Hide()
		box.caption = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.caption:SetPoint("LEFT", box, "RIGHT", 3, 0)
		box.caption:SetText(label)
		box.caption:SetTextColor(0.92, 0.88, 1)
		function box:SetChecked(on)
			self.checked = on and true or false
			self.mark:SetShown(self.checked)
			if self.checked then
				self:SetBackdropColor(0.32, 0.22, 0.48, 1)
			else
				self:SetBackdropColor(0.08, 0.06, 0.1, 1)
			end
		end
		box:SetScript("OnClick", function()
			local settings = row.entry and ((row.entry.pet and db.pet) or (row.entry.stone and db.healthstone))
			if row.entry and row.entry.foodScope then
				settings = LockRemindersFoodScope(row.entry.itemID, row.entry.spellID)
			end
			if type(settings) == "table" then
				local always, party, raid, instance = ScopeFlags(settings)
				local current = always
				if flag == "raid" then
					current = raid
				elseif flag == "party" then
					current = party
				elseif flag == "instance" then
					current = instance
				elseif flag == "combat" then
					current = settings.combat
				end
				local scope = {
					always = always,
					party = party,
					raid = raid,
					instance = instance,
					combat = settings.combat and true or false,
				}
				if flag == "combat" then
					scope.combat = not current and true or false
				else
					scope[flag] = not current and true or false
				end
				if row.entry.pet then
					db.pet = scope
				elseif row.entry.foodScope then
					LockRemindersWriteFoodScope(row.entry.itemID, row.entry.spellID, scope)
				else
					db.healthstone = scope
				end
				Touch()
				return
			end
			if flag == "combat" and row.itemID and db.foodItems[row.itemID] ~= nil then
				SetFoodCombat(row.itemID, nil, not FoodInCombat(row.itemID))
				return
			end
			if flag == "combat" and row.spellID and db.food[row.spellID] ~= nil and AuraScope(row.spellID) == nil then
				SetFoodCombat(nil, row.spellID, not FoodInCombat(nil, row.spellID))
				return
			end
			if not row.spellID or AuraScope(row.spellID) == nil then
				return
			end
			local always, party, raid, instance = ScopeFlags(AuraScope(row.spellID))
			local current = always
			if flag == "raid" then
				current = raid
			elseif flag == "party" then
				current = party
			elseif flag == "instance" then
				current = instance
			elseif flag == "combat" then
				current = type(AuraScope(row.spellID)) == "table" and AuraScope(row.spellID).combat
			end
			SetScopeFlag(row.spellID, flag, not current)
		end)
		box:SetScript("OnEnter", function(self)
			self:SetBackdropBorderColor(0.86, 0.74, 1, 1)
		end)
		box:SetScript("OnLeave", function(self)
			self:SetBackdropBorderColor(0.58, 0.45, 0.82, 1)
		end)
		BindWheel(box)
		local hit = CreateFrame("Button", nil, box)
		hit:SetPoint("LEFT", box, "LEFT", 0, 0)
		hit:SetSize(gap - 6, 20)
		hit:SetFrameLevel(box:GetFrameLevel() + 1)
		hit:SetScript("OnClick", function()
			box:Click()
		end)
		BindWheel(hit)
		row.scopes[flag] = box
		return x + gap
	end
	local nextX = AddScopeBox("raid", "Raid", 0, 52)
	nextX = AddScopeBox("party", "Party", nextX, 58)
	nextX = AddScopeBox("instance", "Instance", nextX, 78)
	nextX = AddScopeBox("always", "Always", nextX, 64)
	nextX = AddScopeBox("combat", "Combat", nextX, 78)
	row.scopes:SetWidth(nextX)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	row.sub:SetTextColor(0.62, 0.58, 0.72)
	if row.name.SetMaxLines then
		row.name:SetMaxLines(1)
		row.sub:SetMaxLines(1)
	end

	row.hit = CreateFrame("Button", nil, row)
	row.hit:SetFrameLevel(row:GetFrameLevel() + 2)
	row.hit:SetScript("OnEnter", function()
		ShowRowTip(row)
	end)
	row.hit:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row.hit:SetScript("OnClick", function()
		if row.entry and row.entry.select then
			row.entry.select()
		end
	end)
	local highlight = row.hit:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
	highlight:SetVertexColor(0.58, 0.45, 0.82, 0.16)
	row.hit:SetHighlightTexture(highlight)
	BindWheel(row.hit)

	rowPool[usedRows] = row
	return row
end

local function FillRow(row, entry)
	row.entry = entry
	row.spellID = entry.spellID
	row.itemID = entry.itemID
	row.icon:SetTexture(entry.icon or 134400)
	-- Same translucent row as Items (no opaque/gold selected card).
	Paint(row, 1, 1, 1, 0.035, 1, 1, 1, 0.04)
	row.name:SetText(entry.name or "")
	row.sub:SetText(entry.sub or "")
	row.extra:Hide()
	row.extra:EnableMouse(false)
	if row.scopes then
		row.scopes:Hide()
	end
	local showScopes = entry.scopes or entry.combatToggle
	if showScopes and row.scopes and row.scopes.combat then
		row.scopes:Show()
		local full = entry.scopes and true or false
		row.scopes.raid:SetShown(full)
		row.scopes.party:SetShown(full)
		if row.scopes.instance then
			row.scopes.instance:SetShown(full)
		end
		row.scopes.always:SetShown(full)
		row.scopes.combat:SetShown(true)
		row.scopes.combat:ClearAllPoints()
		if full then
			local where = (entry.pet and db.pet) or (entry.stone and db.healthstone) or (entry.foodScope and LockRemindersFoodScope(entry.itemID, entry.spellID)) or AuraScope(entry.spellID)
			local always, party, raid, instance = ScopeFlags(where)
			row.scopes.raid:SetChecked(raid)
			row.scopes.party:SetChecked(party)
			if row.scopes.instance then
				row.scopes.instance:SetChecked(instance)
			end
			row.scopes.always:SetChecked(always)
			row.scopes.combat:SetChecked(type(where) == "table" and where.combat)
			row.scopes.combat:SetPoint("LEFT", row.scopes, "LEFT", 252, 0)
			row.scopes:SetWidth(330)
		else
			row.scopes.combat:SetChecked(FoodInCombat(entry.itemID, entry.spellID))
			row.scopes.combat:SetPoint("LEFT", row.scopes, "LEFT", 0, 0)
			row.scopes:SetWidth(78)
		end
	elseif entry.extra then
		row.extra:Show()
		row.extra:EnableMouse(true)
		StyleAction(row.extra, "scope")
		row.extra.label:SetText(entry.extraLabel or "Always")
	end
	StyleAction(row.main, entry.saved and "remove" or "add")

	local anchor = row.main
	if showScopes and row.scopes then
		anchor = row.scopes
	elseif entry.extra then
		anchor = row.extra
	end
	row.name:ClearAllPoints()
	row.sub:ClearAllPoints()
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 7)
	row.name:SetPoint("RIGHT", anchor, "LEFT", -8, 7)
	row.sub:SetPoint("LEFT", row.icon, "RIGHT", 8, -8)
	row.sub:SetPoint("RIGHT", anchor, "LEFT", -8, -8)
	row.hit:ClearAllPoints()
	row.hit:SetPoint("TOPLEFT")
	row.hit:SetPoint("BOTTOMLEFT")
	row.hit:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
	row:Show()
end

local function ReleaseBrowser()
	for index = 1, #rowPool do
		rowPool[index]:Hide()
		rowPool[index].entry = nil
	end
	for index = 1, #headerPool do
		headerPool[index]:Hide()
	end
	usedRows = 0
	usedHeaders = 0
	currentEntries = {}
end

local function SignatureOf(sections, query)
	local parts = { activeTab, query }
	for index = 1, #sections do
		local section = sections[index]
		parts[#parts + 1] = section.title
		for rowIndex = 1, #section.rows do
			local entry = section.rows[rowIndex]
			parts[#parts + 1] = tostring(entry.itemID or entry.spellID or 0)
			parts[#parts + 1] = entry.name or ""
			parts[#parts + 1] = entry.saved and "1" or "0"
			parts[#parts + 1] = entry.sub or ""
			parts[#parts + 1] = entry.extraLabel or ""
		end
	end
	return table.concat(parts, "\31")
end

local function StyleTab(tab, selected)
	if selected then
		tab:SetBackdropColor(0.32, 0.24, 0.48, 1)
		tab:SetBackdropBorderColor(0.75, 0.62, 0.98, 1)
		tab.label:SetTextColor(1, 0.96, 1)
		tab.accent:Show()
	else
		tab:SetBackdropColor(0.12, 0.1, 0.16, 1)
		tab:SetBackdropBorderColor(0.35, 0.28, 0.48, 1)
		tab.label:SetTextColor(0.72, 0.66, 0.82)
		tab.accent:Hide()
	end
end

local function RefreshTabLabels()
	if not tabs or not tabs.list then
		return
	end
	local count = SavedCount()
	tabs.list.label:SetText(count > 0 and ("Your list (" .. count .. ")") or "Your list")
end

local function StepButton(parent, text)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(22, 22)
	Paint(button, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.label:SetPoint("CENTER", 0, 1)
	button.label:SetText(text)
	button:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	button:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	return button
end

LockRemindersStepButton = StepButton

local function EnsureLayout()
	if layoutRoot or not scrollChild then
		return
	end

	layoutRoot = CreateFrame("Frame", nil, scrollChild)
	layoutRoot:SetPoint("TOPLEFT")
	layoutRoot:SetPoint("TOPRIGHT")
	layoutRoot:SetHeight(140)
	BindWheel(layoutRoot)

	local function caption(text, y)
		local label = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 8, y)
		label:SetText(text)
		label:SetTextColor(0.9, 0.84, 1)
		return label
	end

	caption("Size", -8)
	local sizeMinus = StepButton(layoutRoot, "-")
	sizeMinus:SetPoint("TOPLEFT", 160, -4)
	sizeMinus:SetScript("OnClick", function()
		ChangeSize(-4)
	end)
	sizeValue = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sizeValue:SetPoint("LEFT", sizeMinus, "RIGHT", 6, 0)
	sizeValue:SetWidth(28)
	sizeValue:SetJustifyH("CENTER")
	local sizePlus = StepButton(layoutRoot, "+")
	sizePlus:SetPoint("LEFT", sizeValue, "RIGHT", 2, 0)
	sizePlus:SetScript("OnClick", function()
		ChangeSize(4)
	end)
	layoutRoot.buffGlow = LockRemindersGlowSwatch(layoutRoot, sizePlus, 18, "buffGlow", 1, 0.82, 0.35, Refresh)
	LockRemindersGlowBorderControl(layoutRoot, layoutRoot.buffGlow, 12, "buffGlowSize", Refresh)

	caption("Per row", -40)
	local colsMinus = StepButton(layoutRoot, "-")
	colsMinus:SetPoint("TOPLEFT", 160, -36)
	colsMinus:SetScript("OnClick", function()
		ChangeColumns(-1)
	end)
	colsValue = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	colsValue:SetPoint("LEFT", colsMinus, "RIGHT", 6, 0)
	colsValue:SetWidth(52)
	colsValue:SetJustifyH("CENTER")
	colsValue:SetTextColor(0.9, 0.84, 1)
	local colsPlus = StepButton(layoutRoot, "+")
	colsPlus:SetPoint("LEFT", colsValue, "RIGHT", 2, 0)
	colsPlus:SetScript("OnClick", function()
		ChangeColumns(1)
	end)
	local padLabel = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	padLabel:SetPoint("LEFT", colsPlus, "RIGHT", 18, 0)
	padLabel:SetText("Padding")
	padLabel:SetTextColor(0.9, 0.84, 1)
	local padMinus = StepButton(layoutRoot, "-")
	padMinus:SetPoint("LEFT", padLabel, "RIGHT", 8, 0)
	padMinus:SetScript("OnClick", function()
		LockRemindersChangePad(-2)
	end)
	layoutRoot.padValue = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	layoutRoot.padValue:SetPoint("LEFT", padMinus, "RIGHT", 6, 0)
	layoutRoot.padValue:SetWidth(28)
	layoutRoot.padValue:SetJustifyH("CENTER")
	local padPlus = StepButton(layoutRoot, "+")
	padPlus:SetPoint("LEFT", layoutRoot.padValue, "RIGHT", 2, 0)
	padPlus:SetScript("OnClick", function()
		LockRemindersChangePad(2)
	end)

	lockButton = CreateFrame("Button", nil, layoutRoot, "BackdropTemplate")
	lockButton:SetSize(108, 22)
	lockButton:SetPoint("TOPLEFT", 8, -70)
	Paint(lockButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	lockButton.label = lockButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lockButton.label:SetPoint("CENTER")
	lockButton:SetScript("OnClick", function()
		db.locked = not db.locked
		Print(db.locked and "Frame locked." or "Frame unlocked. Drag it from the border.")
		ShowLayout(false)
	end)
	lockButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	lockButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)

	frameButton = CreateFrame("Button", nil, layoutRoot, "BackdropTemplate")
	frameButton:SetSize(124, 22)
	frameButton:SetPoint("TOPLEFT", 8, -100)
	Paint(frameButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	frameButton.label = frameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frameButton.label:SetPoint("CENTER")
	frameButton:SetScript("OnClick", function()
		db.showFrame = not db.showFrame
		Print(db.showFrame and "Alert frame shown, in your class color." or "Alert frame hidden.")
	Refresh()
		ShowLayout(false)
	end)
	frameButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	frameButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
		if db.showFrame then
			local r, g, b = ClassColor()
			self:SetBackdropBorderColor(r, g, b, 1)
		end
	end)

	caption("Last 10s", -136)
	remindCount = CreateFrame("Button", nil, layoutRoot, "BackdropTemplate")
	remindCount:SetSize(72, 22)
	remindCount:SetPoint("TOPLEFT", 160, -132)
	Paint(remindCount, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	remindCount.label = remindCount:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	remindCount.label:SetPoint("CENTER")
	remindCount.label:SetText("Count")
	remindCount:SetScript("OnClick", function()
		db.buffRemind = "count"
		Refresh()
		ShowLayout(false)
	end)
	remindAlert = CreateFrame("Button", nil, layoutRoot, "BackdropTemplate")
	remindAlert:SetSize(88, 22)
	remindAlert:SetPoint("LEFT", remindCount, "RIGHT", 8, 0)
	Paint(remindAlert, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	remindAlert.label = remindAlert:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	remindAlert.label:SetPoint("CENTER")
	remindAlert.label:SetText("Reminder")
	remindAlert:SetScript("OnClick", function()
		db.buffRemind = "alert"
		Refresh()
		ShowLayout(false)
	end)
	remindTest = CreateFrame("Button", nil, layoutRoot, "BackdropTemplate")
	remindTest:SetSize(72, 22)
	remindTest:SetPoint("LEFT", remindAlert, "RIGHT", 8, 0)
	Paint(remindTest, 0.14, 0.1, 0.2, 1, 0.95, 0.45, 0.35, 1)
	remindTest.label = remindTest:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	remindTest.label:SetPoint("CENTER")
	remindTest.label:SetText("Test")
	remindTest:SetScript("OnClick", function()
		local icon, text = SpellIcon(687), "Demon Skin"
		local tracked = Tracked()
		for index = 1, #tracked do
			if tostring(tracked[index].key):find("^aura:") then
				icon = tracked[index].icon or icon
				text = tracked[index].text or text
				break
			end
		end
		local counting = db.buffRemind ~= "alert"
		local function show(left, seconds)
			LockRemindersBuffPreview = {
				at = GetTime() + seconds,
				list = {
					{
						key = "preview",
						icon = icon,
						text = text,
						left = left,
					},
				},
			}
			Refresh()
		end
		local function finish()
			LockRemindersBuffPreviewTimer = nil
			LockRemindersBuffPreview = nil
			Refresh()
		end
		if LockRemindersBuffPreviewTimer then
			LockRemindersBuffPreviewTimer:Cancel()
			LockRemindersBuffPreviewTimer = nil
		end
		if not counting then
			show(nil, 2.4)
			LockRemindersBuffPreviewTimer = C_Timer.NewTimer(2.4, finish)
		return
	end
		local number = 10
		local function step()
			if number >= 0 then
				show(number, 0.5)
				number = number - 1
				LockRemindersBuffPreviewTimer = C_Timer.NewTimer(0.4, step)
				return
			end
			show(nil, 1.6)
			LockRemindersBuffPreviewTimer = C_Timer.NewTimer(1.6, finish)
		end
		step()
	end)
	remindResult = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	remindResult:SetPoint("LEFT", remindTest, "RIGHT", 12, 0)
	remindResult:SetTextColor(0.9, 0.84, 1)
	remindCount:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	remindCount:SetScript("OnLeave", function()
		ShowLayout(false)
	end)
	remindAlert:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	remindAlert:SetScript("OnLeave", function()
		ShowLayout(false)
	end)
	remindTest:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	remindTest:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)

	arrangeButton = CreateFrame("Button", nil, layoutRoot, "BackdropTemplate")
	arrangeButton:SetSize(124, 22)
	arrangeButton:SetPoint("LEFT", lockButton, "RIGHT", 8, 0)
	Paint(arrangeButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	arrangeButton.label = arrangeButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	arrangeButton.label:SetPoint("CENTER")
	arrangeButton:SetScript("OnClick", ToggleArrange)
	arrangeButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	arrangeButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
		if arranging then
			self:SetBackdropBorderColor(0.95, 0.78, 0.35, 1)
		end
	end)

	local resetOrder = CreateFrame("Button", nil, layoutRoot, "BackdropTemplate")
	resetOrder:SetSize(108, 22)
	resetOrder:SetPoint("LEFT", arrangeButton, "RIGHT", 8, 0)
	Paint(resetOrder, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	resetOrder.label = resetOrder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resetOrder.label:SetPoint("CENTER")
	resetOrder.label:SetText("Reset order")
	resetOrder:SetScript("OnClick", function()
		db.order = {}
		Refresh()
		ShowLayout(false)
		Print("Order reset.")
	end)
	resetOrder:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	resetOrder:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)

	local orderTitle = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	orderTitle:SetPoint("TOPLEFT", 8, -172)
	orderTitle:SetText("Order inside the alert")
	orderTitle:SetTextColor(0.9, 0.82, 1)

	layoutEmpty = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	layoutEmpty:SetPoint("TOPLEFT", 8, -200)
	layoutEmpty:SetWidth(420)
	layoutEmpty:SetJustifyH("LEFT")
	layoutEmpty:SetText("Add a power and you can order it here.")
	layoutEmpty:SetTextColor(0.75, 0.7, 0.84)
	layoutEmpty:Hide()
end

local function OrderLabel(entry)
	local where
	if entry.key == "pet" then
		where = db.pet
	elseif entry.key == "healthstone" then
		where = db.healthstone
	else
		local spellID = tonumber(tostring(entry.key):match("^aura:(%d+)$"))
		where = spellID and (db.auras[spellID] or db.auras[tostring(spellID)])
	end
	if type(where) == "table" then
		return entry.text .. "  ·  " .. ScopeLabel(where)
	end
	return entry.text
end

local function CreateOrderRow()
	local row = CreateFrame("Frame", nil, layoutRoot)
	row:SetHeight(32)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.down = StepButton(row, "Bajar")
	row.down:SetSize(52, 22)
	row.down:SetPoint("RIGHT", -4, 0)
	row.up = StepButton(row, "Subir")
	row.up:SetSize(52, 22)
	row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.up:SetScript("OnClick", function()
		if not row.key or not row.index or row.index <= 1 then
			return
		end
		MoveKey(row.key, row.index - 1)
		Refresh()
		ShowLayout(false)
	end)
	row.down:SetScript("OnClick", function()
		if not row.key or not row.index then
			return
		end
		MoveKey(row.key, row.index + 1)
		Refresh()
		ShowLayout(false)
	end)
	return row
end

local function FillOrderRow(row, entry, index, count)
	row.key = entry.key
	row.index = index
	row.icon:SetTexture(entry.icon or 134400)
	row.name:SetText(OrderLabel(entry))
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", layoutRoot, "TOPLEFT", 0, -(200 + (index - 1) * 34))
	row:SetPoint("TOPRIGHT", layoutRoot, "TOPRIGHT", 0, -(200 + (index - 1) * 34))
	local canUp = index > 1
	local canDown = index < count
	row.up:SetAlpha(canUp and 1 or 0.35)
	row.down:SetAlpha(canDown and 1 or 0.35)
	row.up:EnableMouse(canUp)
	row.down:EnableMouse(canDown)
end

ShowLayout = function(resetScroll)
	if not scroll or not scrollChild then
		return
	end
	if LockRemindersItemLayout then
		LockRemindersItemLayout:Hide()
	end
	if LockRemindersCDOrderRoot then
		LockRemindersCDOrderRoot:Hide()
	end
	EnsureLayout()
	if not layoutRoot then
		return
	end
	layoutRoot:Show()
	layoutRoot:SetWidth(math.max(scroll:GetWidth(), 200))
	sizeValue:SetText(tostring(IconSize()))
	colsValue:SetText(ColumnsLabel())
	if layoutRoot and layoutRoot.padValue then
		layoutRoot.padValue:SetText(tostring(LockRemindersIconPad()))
	end
	lockButton.label:SetText(db.locked and "Unlock frame" or "Lock frame")
	frameButton.label:SetText(db.showFrame and "Hide frame" or "Show frame")
	if db.showFrame then
		local r, g, b = ClassColor()
		frameButton:SetBackdropBorderColor(r, g, b, 1)
	else
		frameButton:SetBackdropBorderColor(0.58, 0.45, 0.82, 1)
	end
	arrangeButton.label:SetText(arranging and "Done" or "Arrange")
	if remindCount and remindAlert then
		local counting = db.buffRemind ~= "alert"
		if remindResult then
			remindResult:SetText(counting and "Gray icon, 10 to 0" or "Glowing icon")
		end
		if counting then
			Paint(remindCount, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
			remindCount.label:SetTextColor(1, 0.93, 0.72)
			Paint(remindAlert, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
			remindAlert.label:SetTextColor(0.86, 0.82, 0.94)
		else
			Paint(remindAlert, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
			remindAlert.label:SetTextColor(1, 0.93, 0.72)
			Paint(remindCount, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
			remindCount.label:SetTextColor(0.86, 0.82, 0.94)
		end
	end
	if arranging then
		arrangeButton:SetBackdropBorderColor(0.95, 0.78, 0.35, 1)
	else
		arrangeButton:SetBackdropBorderColor(0.58, 0.45, 0.82, 1)
	end

	local list = Tracked()
	SyncOrder(list)
	SortEntries(list)
	for i = 1, #list do
		local row = orderPool[i]
		if not row then
			row = CreateOrderRow()
			orderPool[i] = row
		end
		FillOrderRow(row, list[i], i, #list)
		row:Show()
	end
	for i = #list + 1, #orderPool do
		orderPool[i]:Hide()
	end

	local height = 212 + #list * 34
	if #list == 0 then
		layoutEmpty:Show()
		height = 240
	else
		layoutEmpty:Hide()
	end
	layoutRoot:SetHeight(height)
	scrollChild:SetWidth(scroll:GetWidth())
	scrollChild:SetHeight(height)
	if resetScroll then
		scroll:SetVerticalScroll(0)
	end
	UpdateScrollMetrics()
	C_Timer.After(0, UpdateScrollMetrics)
end

HideLayout = function()
	if layoutRoot then
		layoutRoot:Hide()
	end
	if LockRemindersItemLayout then
		LockRemindersItemLayout:Hide()
	end
	if LockRemindersCDOrderRoot then
		LockRemindersCDOrderRoot:Hide()
	end
end

function LockRemindersFoodScope(itemID, spellID)
	local key = FoodCombatKey(itemID, spellID)
	if type(db.foodScope) == "table" and key and type(db.foodScope[key]) == "table" then
		local scope = db.foodScope[key]
		return {
			always = scope.always and true or false,
			party = scope.party and true or false,
			raid = scope.raid and true or false,
			instance = scope.instance and true or false,
			combat = scope.combat and true or false,
		}
	end
	return {
		always = false,
		party = false,
		raid = true,
		instance = false,
		combat = FoodInCombat(itemID, spellID),
	}
end

function LockRemindersWriteFoodScope(itemID, spellID, scope)
	if type(db.foodScope) ~= "table" then
		db.foodScope = {}
	end
	local key = FoodCombatKey(itemID, spellID)
	if not key or type(scope) ~= "table" then
		return
	end
	db.foodScope[key] = {
		always = scope.always and true or false,
		party = scope.party and true or false,
		raid = scope.raid and true or false,
		instance = scope.instance and true or false,
		combat = scope.combat and true or false,
	}
	SetFoodCombat(itemID, spellID, scope.combat)
end

function LockRemindersFoodScopeLabel()
	local label
	local function take(itemID, spellID)
		local text = ScopeLabel(LockRemindersFoodScope(itemID, spellID))
		if not label then
			label = text
		elseif label ~= text then
			label = "Mixed"
		end
	end
	if type(db.foodItems) == "table" then
		for itemID in pairs(db.foodItems) do
			take(itemID, nil)
		end
	end
	if type(db.food) == "table" then
		for spellID in pairs(db.food) do
			take(nil, spellID)
		end
	end
	return label or "Raid"
end

function LockRemindersFoodColumns()
	local cols = math.floor(tonumber(db and db.foodColumns) or 0)
	if cols < 0 then
		cols = 0
	elseif cols > 12 then
		cols = 12
	end
	return cols
end

function LockRemindersFoodColumnsLabel()
	local cols = LockRemindersFoodColumns()
	if cols < 1 then
		return "one row"
	end
	return tostring(cols)
end

function LockRemindersChangeFoodColumns(delta)
	local count = math.max(#LockRemindersItemCatalog(), 1)
	local cols = LockRemindersFoodColumns()
	if cols < 1 then
		cols = count
	end
	cols = cols + delta
	if cols < 1 then
		cols = 1
	end
	if cols >= count then
		db.foodColumns = 0
	else
		db.foodColumns = cols
	end
	ApplyFoodLook()
	LockRemindersShowItemLayout(false)
end

function LockRemindersFoodPad()
	local pad = tonumber(db and db.foodPad) or 8
	if pad < 0 then
		pad = 0
	elseif pad > 48 then
		pad = 48
	end
	return pad
end

function LockRemindersChangeFoodPad(delta)
	local pad = LockRemindersFoodPad() + delta
	if pad < 0 then
		pad = 0
	elseif pad > 48 then
		pad = 48
	end
	db.foodPad = pad
	ApplyFoodLook()
	LockRemindersShowItemLayout(false)
end

function LockRemindersToggleItemArrange()
	if not LockRemindersItemArranging and Restricted() then
		Print("Leave combat to arrange the icons.")
		return
	end
	if not LockRemindersItemArranging and #LockRemindersItemCatalog() == 0 then
		Print("Nothing to arrange yet.")
		return
	end
	LockRemindersItemArranging = not LockRemindersItemArranging
	if LockRemindersItemArranging then
		Print("Drag each icon inside the alert. Press Done when you finish.")
	end
	if RefreshFood then
		RefreshFood()
	end
	LockRemindersShowItemLayout(false)
end

function LockRemindersApplyFoodChrome()
	if not foodFrame then
		return
	end
	local show = db and (db.foodShowFrame or LockRemindersItemArranging)
	foodFrame:SetFrameStrata(LockRemindersItemArranging and "DIALOG" or "HIGH")
	if foodFrame.hint then
		if LockRemindersItemArranging then
			foodFrame.hint:SetText("Drag the icons")
			foodFrame.hint:Show()
		elseif foodFrame.moving then
			foodFrame.hint:SetText("Drag")
			foodFrame.hint:Show()
		else
			foodFrame.hint:Hide()
		end
	end
	if not show then
		pcall(foodFrame.SetBackdrop, foodFrame, nil)
		return
	end
	Paint(foodFrame, 0.06, 0.05, 0.08, 0.92, 1, 1, 1, 1)
	local red, green, blue = ClassColor()
	if LockRemindersItemArranging then
		red, green, blue = 0.95, 0.78, 0.35
	end
	pcall(foodFrame.SetBackdropBorderColor, foodFrame, red, green, blue, 1)
end

function LockRemindersStyleFoodIcon()
	if not foodFrame or not foodFrame.icon then
		return
	end
	local number = foodFrame.foodNumber
	local quiet = type(number) == "number"
	if foodFrame.icon.SetDesaturated then
		foodFrame.icon:SetDesaturated(quiet)
	end
	if quiet then
		foodFrame.icon:SetVertexColor(0.55, 0.55, 0.55)
		if foodFrame.glow then
			if foodFrame.glow.ag then
				foodFrame.glow.ag:Stop()
			end
			foodFrame.glow:Hide()
			if foodFrame.glow.plate then
				foodFrame.glow.plate:Hide()
			end
		end
		if foodFrame.count then
			local font = foodFrame.count:GetFont()
			if type(font) ~= "string" or font == "" then
				font = "Fonts\\FRIZQT__.TTF"
			end
			local size = tonumber(db and db.foodSize) or 48
			foodFrame.count:SetFont(font, math.max(14, math.floor(size * 0.62)), "OUTLINE")
			foodFrame.count:SetText(tostring(number))
			foodFrame.count:Show()
		end
	else
		foodFrame.icon:SetVertexColor(1, 1, 1)
		if foodFrame.count then
			foodFrame.count:Hide()
		end
	end
	local alpha = foodFrame.foodDim and 0.45 or 1
	foodFrame.icon:SetAlpha(alpha)
	if foodFrame.glow then
		foodFrame.glow:SetAlpha(alpha)
	end
	if foodFrame.stone then
		local stoneAlpha = foodFrame.stoneDim and 0.45 or 1
		foodFrame.stone:SetAlpha(stoneAlpha)
		if foodFrame.stoneGlow then
			foodFrame.stoneGlow:SetAlpha(stoneAlpha)
		end
	end
end

function LockRemindersDropItem(key)
	if not foodFrame or not db then
		return
	end
	local scale = foodFrame:GetEffectiveScale()
	if not scale or scale == 0 then
		scale = 1
	end
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	local px = x - (foodFrame:GetLeft() or 0)
	local py = (foodFrame:GetTop() or 0) - y
	local size = tonumber(db.foodSize) or 48
	local pad = LockRemindersFoodPad()
	local step = size + LockRemindersGlowThick(size, "foodGlowSize") * 2 + pad
	local count = #LockRemindersSortedItems()
	local cols = LockRemindersFoodColumns()
	if cols < 1 or cols > count then
		cols = math.max(count, 1)
	end
	local col = math.floor((px - pad) / step)
	local line = math.floor((py - pad) / step)
	if col < 0 then
		col = 0
	elseif col >= cols then
		col = cols - 1
	end
	if line < 0 then
		line = 0
	end
	local index = line * cols + col + 1
	if index < 1 then
		index = 1
	elseif index > count then
		index = count
	end
	LockRemindersMoveItem(key, index)
end

function LockRemindersBindItemDrag(hit, icon, glow, key)
	hit:RegisterForDrag("LeftButton")
	hit:SetScript("OnDragStart", function(self)
		if not LockRemindersItemArranging then
			return
		end
		self:SetScript("OnUpdate", function()
			local scale = foodFrame:GetEffectiveScale()
			if not scale or scale == 0 then
				scale = 1
			end
			local cursorX, cursorY = GetCursorPosition()
			cursorX, cursorY = cursorX / scale, cursorY / scale
			local px = cursorX - (foodFrame:GetLeft() or 0)
			local py = (foodFrame:GetTop() or 0) - cursorY
			icon:ClearAllPoints()
			icon:SetPoint("CENTER", foodFrame, "TOPLEFT", px, -py)
			LockRemindersFitEvenGlow(glow, icon, tonumber(db.foodSize) or 48, "foodGlowSize")
		end)
	end)
	hit:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		LockRemindersDropItem(key)
	end)
end

function LockRemindersItemCatalog()
	local list = {}
	if not db then
		return list
	end
	local hasFood = false
	if type(db.foodItems) == "table" then
		for _ in pairs(db.foodItems) do
			hasFood = true
			break
		end
	end
	if not hasFood and type(db.food) == "table" then
		for _ in pairs(db.food) do
			hasFood = true
			break
		end
	end
	if hasFood then
		local icon, text = FoodLabel()
		list[#list + 1] = { key = "food", icon = icon, text = (text or "Food") .. "  ·  " .. LockRemindersFoodScopeLabel() }
	end
	if type(db.healthstone) == "table" then
		local icon = SpellIcon(CREATE_HEALTHSTONE)
		if icon == nil or icon == 134400 then
			icon = ItemIcon(5512) or 135230
		end
		list[#list + 1] = {
			key = "healthstone",
			icon = icon,
			text = "Healthstone  ·  " .. ScopeLabel(db.healthstone),
		}
	end
	return list
end

function LockRemindersSyncItemOrder(list)
	if type(db.itemOrder) ~= "table" then
		db.itemOrder = {}
	end
	local known = {}
	for index = 1, #list do
		known[list[index].key] = true
	end
	local kept = {}
	local seen = {}
	for index = 1, #db.itemOrder do
		local key = db.itemOrder[index]
		if known[key] and not seen[key] then
			kept[#kept + 1] = key
			seen[key] = true
		end
	end
	for index = 1, #list do
		local key = list[index].key
		if not seen[key] then
			kept[#kept + 1] = key
			seen[key] = true
		end
	end
	db.itemOrder = kept
end

function LockRemindersSortedItems()
	local list = LockRemindersItemCatalog()
	LockRemindersSyncItemOrder(list)
	local rank = {}
	for index = 1, #db.itemOrder do
		rank[db.itemOrder[index]] = index
	end
	table.sort(list, function(a, b)
		return (rank[a.key] or 99) < (rank[b.key] or 99)
	end)
	return list
end

function LockRemindersMoveItem(key, newIndex)
	local list = LockRemindersSortedItems()
	local order = db.itemOrder
	local old
	for index = 1, #order do
		if order[index] == key then
			old = index
			break
		end
	end
	if not old or newIndex < 1 or newIndex > #order or newIndex == old then
		return
	end
	table.remove(order, old)
	table.insert(order, newIndex, key)
	ApplyFoodLook()
	if foodFrame and foodFrame:IsShown() then
		foodFrame:Show()
	end
	LockRemindersShowItemLayout(false)
end

function LockRemindersShowItemLayout(resetScroll)
	if not scroll or not scrollChild or not db then
		return
	end
	if activeTab ~= "alert" or not panel or (panel.alertModule or "powers") ~= "food" then
		return
	end
	local root = LockRemindersItemLayout
	if not root then
		root = CreateFrame("Frame", nil, scrollChild)
		root:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
		root:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
		root.rows = {}
		local perLabel = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		perLabel:SetPoint("TOPLEFT", 8, -8)
		perLabel:SetText("Per row")
		perLabel:SetTextColor(0.9, 0.84, 1)
		local colsMinus = StepButton(root, "-")
		colsMinus:SetPoint("TOPLEFT", 160, -4)
		colsMinus:SetScript("OnClick", function()
			LockRemindersChangeFoodColumns(-1)
		end)
		root.colsValue = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.colsValue:SetPoint("LEFT", colsMinus, "RIGHT", 6, 0)
		root.colsValue:SetWidth(52)
		root.colsValue:SetJustifyH("CENTER")
		root.colsValue:SetTextColor(0.9, 0.84, 1)
		local colsPlus = StepButton(root, "+")
		colsPlus:SetPoint("LEFT", root.colsValue, "RIGHT", 2, 0)
		colsPlus:SetScript("OnClick", function()
			LockRemindersChangeFoodColumns(1)
		end)
		local padLabel = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		padLabel:SetPoint("LEFT", colsPlus, "RIGHT", 18, 0)
		padLabel:SetText("Padding")
		padLabel:SetTextColor(0.9, 0.84, 1)
		local padMinus = StepButton(root, "-")
		padMinus:SetPoint("LEFT", padLabel, "RIGHT", 8, 0)
		padMinus:SetScript("OnClick", function()
			LockRemindersChangeFoodPad(-2)
		end)
		root.padValue = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		root.padValue:SetPoint("LEFT", padMinus, "RIGHT", 6, 0)
		root.padValue:SetWidth(28)
		root.padValue:SetJustifyH("CENTER")
		local padPlus = StepButton(root, "+")
		padPlus:SetPoint("LEFT", root.padValue, "RIGHT", 2, 0)
		padPlus:SetScript("OnClick", function()
			LockRemindersChangeFoodPad(2)
		end)
		root.lock = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.lock:SetSize(108, 22)
		root.lock:SetPoint("TOPLEFT", 8, -40)
		Paint(root.lock, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
		root.lock.label = root.lock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.lock.label:SetPoint("CENTER")
		root.lock:SetScript("OnClick", function()
			local open = foodFrame and foodFrame.moving or db.foodLocked == false
			Print(open and "Frame locked." or "Frame unlocked. Drag the alert.")
			ShowFoodPreview(not open)
		end)
		root.lock:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.lock:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.14, 0.1, 0.2, 1)
			local open = foodFrame and foodFrame.moving or db.foodLocked == false
			self:SetBackdropBorderColor(open and 0.95 or 0.58, open and 0.78 or 0.45, open and 0.35 or 0.82, 1)
		end)
		root.arrange = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.arrange:SetSize(124, 22)
		root.arrange:SetPoint("LEFT", root.lock, "RIGHT", 8, 0)
		Paint(root.arrange, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
		root.arrange.label = root.arrange:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.arrange.label:SetPoint("CENTER")
		root.arrange:SetScript("OnClick", LockRemindersToggleItemArrange)
		root.arrange:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.arrange:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.14, 0.1, 0.2, 1)
			if LockRemindersItemArranging then
				self:SetBackdropBorderColor(0.95, 0.78, 0.35, 1)
			end
		end)
		root.reset = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.reset:SetSize(108, 22)
		root.reset:SetPoint("LEFT", root.arrange, "RIGHT", 8, 0)
		Paint(root.reset, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
		root.reset.label = root.reset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.reset.label:SetPoint("CENTER")
		root.reset.label:SetText("Reset order")
		root.reset:SetScript("OnClick", function()
			db.itemOrder = {}
			ApplyFoodLook()
			LockRemindersShowItemLayout(false)
			Print("Order reset.")
		end)
		root.reset:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.reset:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.14, 0.1, 0.2, 1)
		end)
		root.frameButton = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.frameButton:SetSize(124, 22)
		root.frameButton:SetPoint("TOPLEFT", 8, -72)
		Paint(root.frameButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
		root.frameButton.label = root.frameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.frameButton.label:SetPoint("CENTER")
		root.frameButton:SetScript("OnClick", function()
			db.foodShowFrame = not db.foodShowFrame
			Print(db.foodShowFrame and "Alert frame shown, in your class color." or "Alert frame hidden.")
			ApplyFoodLook()
			LockRemindersShowItemLayout(false)
		end)
		root.frameButton:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.frameButton:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.14, 0.1, 0.2, 1)
			if db.foodShowFrame then
				local red, green, blue = ClassColor()
				self:SetBackdropBorderColor(red, green, blue, 1)
			end
		end)
		local lastLabel = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		lastLabel:SetPoint("TOPLEFT", 8, -108)
		lastLabel:SetText("Last 10s")
		lastLabel:SetTextColor(0.9, 0.84, 1)
		root.countButton = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.countButton:SetSize(72, 22)
		root.countButton:SetPoint("TOPLEFT", 160, -104)
		Paint(root.countButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
		root.countButton.label = root.countButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.countButton.label:SetPoint("CENTER")
		root.countButton.label:SetText("Count")
		root.countButton:SetScript("OnClick", function()
			db.foodRemind = "count"
			if RefreshFood then
				RefreshFood()
			end
			LockRemindersShowItemLayout(false)
		end)
		root.alertButton = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.alertButton:SetSize(88, 22)
		root.alertButton:SetPoint("LEFT", root.countButton, "RIGHT", 8, 0)
		Paint(root.alertButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
		root.alertButton.label = root.alertButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.alertButton.label:SetPoint("CENTER")
		root.alertButton.label:SetText("Reminder")
		root.alertButton:SetScript("OnClick", function()
			db.foodRemind = "alert"
			if RefreshFood then
				RefreshFood()
			end
			LockRemindersShowItemLayout(false)
		end)
		root.testButton = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.testButton:SetSize(72, 22)
		root.testButton:SetPoint("LEFT", root.alertButton, "RIGHT", 8, 0)
		Paint(root.testButton, 0.14, 0.1, 0.2, 1, 0.95, 0.45, 0.35, 1)
		root.testButton.label = root.testButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.testButton.label:SetPoint("CENTER")
		root.testButton.label:SetText("Test")
		root.testButton:SetScript("OnClick", function()
			local counting = db.foodRemind ~= "alert"
			local function show(left, seconds)
				LockRemindersFoodPreview = { at = GetTime() + seconds, left = left }
				if RefreshFood then
					RefreshFood()
				end
			end
			local function finish()
				LockRemindersFoodPreviewTimer = nil
				LockRemindersFoodPreview = nil
				if RefreshFood then
					RefreshFood()
				end
			end
			if LockRemindersFoodPreviewTimer then
				LockRemindersFoodPreviewTimer:Cancel()
				LockRemindersFoodPreviewTimer = nil
			end
			if not counting then
				show(nil, 2.4)
				LockRemindersFoodPreviewTimer = C_Timer.NewTimer(2.4, finish)
				return
			end
			local number = 10
			local function step()
				if number >= 0 then
					show(number, 0.5)
					number = number - 1
					LockRemindersFoodPreviewTimer = C_Timer.NewTimer(0.4, step)
					return
				end
				show(nil, 1.6)
				LockRemindersFoodPreviewTimer = C_Timer.NewTimer(1.6, finish)
			end
			step()
		end)
		root.result = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.result:SetPoint("LEFT", root.testButton, "RIGHT", 12, 0)
		root.result:SetTextColor(0.9, 0.84, 1)
		root.countButton:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.countButton:SetScript("OnLeave", function()
			LockRemindersShowItemLayout(false)
		end)
		root.alertButton:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.alertButton:SetScript("OnLeave", function()
			LockRemindersShowItemLayout(false)
		end)
		root.testButton:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.testButton:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.14, 0.1, 0.2, 1)
		end)
		root.title = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		root.title:SetPoint("TOPLEFT", 8, -144)
		root.title:SetText("Order inside the alert")
		root.title:SetTextColor(0.9, 0.82, 1)
		root.empty = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.empty:SetPoint("TOPLEFT", 8, -172)
		root.empty:SetWidth(420)
		root.empty:SetJustifyH("LEFT")
		root.empty:SetText("Add an item and you can order it here.")
		root.empty:SetTextColor(0.75, 0.7, 0.84)
		root.empty:Hide()
		LockRemindersItemLayout = root
	end
	root:Show()
	root:SetWidth(math.max(scroll:GetWidth(), 200))
	local open = foodFrame and foodFrame.moving or db.foodLocked == false
	root.lock.label:SetText(open and "Lock frame" or "Unlock frame")
	root.lock:SetBackdropBorderColor(open and 0.95 or 0.58, open and 0.78 or 0.45, open and 0.35 or 0.82, 1)
	if root.colsValue then
		root.colsValue:SetText(LockRemindersFoodColumnsLabel())
	end
	if root.padValue then
		root.padValue:SetText(tostring(LockRemindersFoodPad()))
	end
	if root.arrange then
		root.arrange.label:SetText(LockRemindersItemArranging and "Done" or "Arrange")
		root.arrange:SetBackdropBorderColor(LockRemindersItemArranging and 0.95 or 0.58, LockRemindersItemArranging and 0.78 or 0.45, LockRemindersItemArranging and 0.35 or 0.82, 1)
	end
	if root.frameButton then
		root.frameButton.label:SetText(db.foodShowFrame and "Hide frame" or "Show frame")
		if db.foodShowFrame then
			local red, green, blue = ClassColor()
			root.frameButton:SetBackdropBorderColor(red, green, blue, 1)
		else
			root.frameButton:SetBackdropBorderColor(0.58, 0.45, 0.82, 1)
		end
	end
	if root.countButton and root.alertButton then
		local counting = db.foodRemind ~= "alert"
		if root.result then
			root.result:SetText(counting and "Gray icon, 10 to 0" or "Glowing icon")
		end
		if counting then
			Paint(root.countButton, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
			root.countButton.label:SetTextColor(1, 0.93, 0.72)
			Paint(root.alertButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
			root.alertButton.label:SetTextColor(0.86, 0.82, 0.94)
		else
			Paint(root.alertButton, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
			root.alertButton.label:SetTextColor(1, 0.93, 0.72)
			Paint(root.countButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
			root.countButton.label:SetTextColor(0.86, 0.82, 0.94)
		end
	end
	local list = LockRemindersSortedItems()
	for index = 1, #list do
		local row = root.rows[index]
		if not row then
			row = CreateFrame("Frame", nil, root)
			row:SetHeight(32)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(24, 24)
			row.icon:SetPoint("LEFT", 4, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.down = StepButton(row, "Bajar")
			row.down:SetSize(52, 22)
			row.down:SetPoint("RIGHT", -4, 0)
			row.up = StepButton(row, "Subir")
			row.up:SetSize(52, 22)
			row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.name:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.up:SetScript("OnClick", function()
				if row.key and row.index and row.index > 1 then
					LockRemindersMoveItem(row.key, row.index - 1)
				end
			end)
			row.down:SetScript("OnClick", function()
				if row.key and row.index then
					LockRemindersMoveItem(row.key, row.index + 1)
				end
			end)
			root.rows[index] = row
		end
		local entry = list[index]
		row.key = entry.key
		row.index = index
		row.icon:SetTexture(entry.icon or 134400)
		row.name:SetText(entry.text)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(172 + (index - 1) * 34))
		row:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(172 + (index - 1) * 34))
		local canUp = index > 1
		local canDown = index < #list
		row.up:SetAlpha(canUp and 1 or 0.35)
		row.down:SetAlpha(canDown and 1 or 0.35)
		row.up:EnableMouse(canUp)
		row.down:EnableMouse(canDown)
		row:Show()
	end
	for index = #list + 1, #root.rows do
		root.rows[index]:Hide()
	end
	local height = 200 + #list * 34
	if #list == 0 then
		root.empty:Show()
		height = 220
	else
		root.empty:Hide()
	end
	root:SetHeight(height)
	scrollChild:SetWidth(scroll:GetWidth())
	scrollChild:SetHeight(height)
	if resetScroll then
		scroll:SetVerticalScroll(0)
	end
	UpdateScrollMetrics()
	C_Timer.After(0, UpdateScrollMetrics)
end

function LockRemindersShowCDOrder(resetScroll)
	if not scroll or not scrollChild or not db then
		return
	end
	if activeTab ~= "alert" or not panel or (panel.alertModule or "powers") ~= "cds" then
		return
	end
	if LockRemindersItemLayout then
		LockRemindersItemLayout:Hide()
	end
	if layoutRoot then
		layoutRoot:Hide()
	end
	local root = LockRemindersCDOrderRoot
	if not root then
		root = CreateFrame("Frame", nil, scrollChild)
		root:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
		root:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
		root.rows = {}
		local function makeSortChoice(label, mode, width)
			local button = CreateFrame("Button", nil, root, "BackdropTemplate")
			button:SetSize(width, 22)
			button.choiceId = mode
			button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			button.label:SetPoint("CENTER")
			button.label:SetText(label)
			button:SetScript("OnClick", function()
				db.cdSortMode = mode
				pcall(LockRemindersCDLayout)
				LockRemindersShowCDOrder(false)
			end)
			return button
		end
		root.byTime = makeSortChoice("By time", "time", 84)
		root.byTime:SetPoint("TOPLEFT", 8, -8)
		root.byManual = makeSortChoice("Manual", "manual", 84)
		root.byManual:SetPoint("LEFT", root.byTime, "RIGHT", 8, 0)
		root.sortChoices = { root.byTime, root.byManual }
		root.reset = CreateFrame("Button", nil, root, "BackdropTemplate")
		root.reset:SetSize(108, 22)
		root.reset:SetPoint("LEFT", root.byManual, "RIGHT", 8, 0)
		Paint(root.reset, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
		root.reset.label = root.reset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.reset.label:SetPoint("CENTER")
		root.reset.label:SetText("Reset order")
		root.reset:SetScript("OnClick", function()
			db.cdOrder = {}
			pcall(LockRemindersCDLayout)
			LockRemindersShowCDOrder(false)
			Print("Order reset.")
		end)
		root.reset:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.28, 0.2, 0.42, 1)
		end)
		root.reset:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.14, 0.1, 0.2, 1)
		end)
		root.title = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		root.title:SetPoint("TOPLEFT", 8, -40)
		root.title:SetText("Icon order")
		root.title:SetTextColor(0.9, 0.82, 1)
		root.hint = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.hint:SetPoint("TOPLEFT", 8, -60)
		root.hint:SetWidth(420)
		root.hint:SetJustifyH("LEFT")
		root.hint:SetTextColor(0.75, 0.7, 0.84)
		root.empty = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		root.empty:SetPoint("TOPLEFT", 8, -92)
		root.empty:SetWidth(420)
		root.empty:SetJustifyH("LEFT")
		root.empty:SetText("Add a cooldown and you can set the order here.")
		root.empty:SetTextColor(0.75, 0.7, 0.84)
		root.empty:Hide()
		LockRemindersCDOrderRoot = root
	end
	root:Show()
	root:SetWidth(math.max(scroll:GetWidth(), 200))
	local sortMode = db.cdSortMode == "manual" and "manual" or "time"
	if root.sortChoices then
		LockRemindersPaintChoiceRow(root.sortChoices, sortMode)
	end
	if root.hint then
		if sortMode == "manual" then
			root.hint:SetText("Icons follow this list exactly. Use Subir / Bajar to rearrange.")
		else
			root.hint:SetText("On cooldown, shortest time left shows first. This list breaks ties and ranks ready icons.")
		end
	end
	local list = LockRemindersSortedCDs()
	for index = 1, #list do
		local row = root.rows[index]
		if not row then
			row = CreateFrame("Frame", nil, root)
			row:SetHeight(32)
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(24, 24)
			row.icon:SetPoint("LEFT", 4, 0)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.down = StepButton(row, "Bajar")
			row.down:SetSize(52, 22)
			row.down:SetPoint("RIGHT", -4, 0)
			row.up = StepButton(row, "Subir")
			row.up:SetSize(52, 22)
			row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.name:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.up:SetScript("OnClick", function()
				if row.key and row.index and row.index > 1 then
					LockRemindersMoveCD(row.key, row.index - 1)
				end
			end)
			row.down:SetScript("OnClick", function()
				if row.key and row.index then
					LockRemindersMoveCD(row.key, row.index + 1)
				end
			end)
			root.rows[index] = row
		end
		local entry = list[index]
		row.key = entry.key
		row.index = index
		row.icon:SetTexture(entry.icon or 134400)
		row.name:SetText(entry.text)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(92 + (index - 1) * 34))
		row:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(92 + (index - 1) * 34))
		local canUp = index > 1
		local canDown = index < #list
		row.up:SetAlpha(canUp and 1 or 0.35)
		row.down:SetAlpha(canDown and 1 or 0.35)
		row.up:EnableMouse(canUp)
		row.down:EnableMouse(canDown)
		row:Show()
	end
	for index = #list + 1, #root.rows do
		root.rows[index]:Hide()
	end
	local height = 120 + #list * 34
	if #list == 0 then
		root.empty:Show()
		height = 140
	else
		root.empty:Hide()
	end
	root:SetHeight(height)
	scrollChild:SetWidth(scroll:GetWidth())
	scrollChild:SetHeight(height)
	if resetScroll then
		scroll:SetVerticalScroll(0)
	end
	UpdateScrollMetrics()
	C_Timer.After(0, UpdateScrollMetrics)
end

local function RebuildList(resetScroll)
	if not panel or not panel:IsShown() or not searchBox then
		return
	end

	if activeTab == "alert" then
		local module = panel.alertModule or "powers"
		if module == "food" then
			HideLayout()
			if LockRemindersCDOrderRoot then
				LockRemindersCDOrderRoot:Hide()
			end
			ReleaseBrowser()
			emptyLabel:Hide()
			scroll:Show()
			if scrollBar then
				scrollBar:Show()
			end
			LockRemindersShowItemLayout(resetScroll)
			return
		end
		if module == "cds" then
			HideLayout()
			if LockRemindersItemLayout then
				LockRemindersItemLayout:Hide()
			end
			ReleaseBrowser()
			emptyLabel:Hide()
			scroll:Show()
			if scrollBar then
				scrollBar:Show()
			end
			LockRemindersShowCDOrder(resetScroll)
			return
		end
		if module ~= "powers" then
			HideLayout()
			if LockRemindersItemLayout then
				LockRemindersItemLayout:Hide()
			end
			if LockRemindersCDOrderRoot then
				LockRemindersCDOrderRoot:Hide()
			end
			ReleaseBrowser()
			emptyLabel:Hide()
			scroll:Hide()
			if scrollBar then
				scrollBar:Hide()
			end
			return
		end
		if LockRemindersCDOrderRoot then
			LockRemindersCDOrderRoot:Hide()
		end
		ReleaseBrowser()
		emptyLabel:Hide()
		scroll:Show()
		if scrollBar then
			scrollBar:Show()
		end
		if scroll:GetWidth() < 10 then
			if (scroll.retries or 0) < 3 then
				scroll.retries = (scroll.retries or 0) + 1
				C_Timer.After(0, function()
					RebuildList(resetScroll)
				end)
			end
			return
		end
		scroll.retries = 0
		ShowLayout(resetScroll)
		return
	end

	if activeTab == "misc" or activeTab == "soul" or activeTab == "pets" or activeTab == "fun" then
		HideLayout()
		if emptyLabel then
			emptyLabel:Hide()
		end
		return
	end

	HideLayout()
	RefreshTabLabels()
	local raw = searchBox:GetText() or ""
	local query, typedID, spellLink, itemLink = ParseSearch(raw)
	local ok, sections = pcall(function()
		if activeTab == "food" then
			return CollectFood(query, typedID, itemLink)
		elseif activeTab == "list" then
			return CollectSaved(query)
		elseif activeTab == "talents" then
			return CollectTalents(query, typedID, spellLink)
		elseif activeTab == "spells" then
			return LockRemindersCollectSpellMiss(query, typedID, spellLink)
		elseif activeTab == "cds" then
			return LockRemindersCollectCDManager(query, typedID, spellLink)
		end
		return CollectPowers(query, typedID, spellLink)
	end)
	if not ok or type(sections) ~= "table" then
		sections = {}
	end
	if activeTab == "food" then
		local hasStone = false
		for index = 1, #sections do
			local rows = sections[index] and sections[index].rows
			if rows and rows[1] and rows[1].stone then
				hasStone = true
				break
			end
		end
		if not hasStone then
			local stoneOk, stone = pcall(HealthstoneSection, query)
			if stoneOk and type(stone) == "table" then
				table.insert(sections, 1, stone)
			end
		end
	end

	local sigOk, signature = pcall(SignatureOf, sections, query)
	if not sigOk or type(signature) ~= "string" then
		signature = activeTab .. "\31" .. query .. "\31" .. tostring(#sections)
	end
	if signature == currentSignature then
		if resetScroll then
			scroll:SetVerticalScroll(0)
			UpdateScrollMetrics()
		end
		return
	end

	if scroll:GetWidth() < 10 then
		if (scroll.retries or 0) < 3 then
			scroll.retries = (scroll.retries or 0) + 1
			C_Timer.After(0, function()
				RebuildList(resetScroll)
			end)
		end
		return
	end
	scroll.retries = 0

	currentSignature = signature
	ReleaseBrowser()
	scrollChild:SetWidth(scroll:GetWidth())
	emptyLabel:Hide()

	local y = 0
	local shown = 0
	local more = false
	for index = 1, #sections do
		if shown >= BROWSER_LIMIT then
			more = true
			break
		end
		local section = sections[index]
		if index > 1 then
			y = y + 8
		end
		local header = AcquireHeader()
		header.text:SetText(section.title)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
		header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
		header:Show()
		y = y + 22
		local rows = section.rows or {}
		for rowIndex = 1, #rows do
			if shown >= BROWSER_LIMIT then
				more = true
				break
			end
			local entry = section.rows[rowIndex]
			local row = AcquireRow()
			local filled = pcall(FillRow, row, entry)
			if not filled then
				row:Hide()
			else
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
				row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
				y = y + 54
				shown = shown + 1
				currentEntries[#currentEntries + 1] = entry
			end
		end
		if more then
			break
		end
	end

	if more then
		y = y + 6
		local header = AcquireHeader()
		header.text:SetText("More results. Type more of the name.")
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
		header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -y)
		header:Show()
		y = y + 22
	end

	local empty = shown == 0
	emptyLabel:SetText(empty and EmptyMessage(query) or "")
	emptyLabel:SetShown(empty)
	scrollChild:SetHeight(math.max(1, y))
	if resetScroll then
		scroll:SetVerticalScroll(0)
	end
	UpdateScrollMetrics()
	C_Timer.After(0, UpdateScrollMetrics)
end

local function QueueListRefresh()
	if not panel or not panel:IsShown() or listTicker then
		return
	end
	listTicker = C_Timer.NewTimer(0.6, function()
		listTicker = nil
		RebuildList(false)
	end)
end

UpdateListNow = function()
	if listTicker then
		listTicker:Cancel()
		listTicker = nil
	end
	currentSignature = nil
	RebuildList(false)
end

local function UpdateTalentChrome()
	if not scroll then
		return
	end
	local module = panel and panel.alertModule or "powers"
	local showTalent = activeTab == "alert" and module == "talents"
	local showFood = activeTab == "alert" and module == "food"
	local showSpells = activeTab == "alert" and module == "spells"
	local showCds = activeTab == "alert" and module == "cds"
	if talentBar then
		talentBar:SetShown(showTalent)
	end
	if panel and panel.foodBar then
		panel.foodBar:SetShown(showFood)
		if db and panel.foodBar.sizeText then
			panel.foodBar.sizeText:SetText(tostring(tonumber(db.foodSize) or 48))
		end
		if panel.foodBar.moveButton then
			panel.foodBar.moveButton.label:SetText(foodFrame and foodFrame.moving and "Done" or "Move")
		end
	end
	if panel and panel.spellBar then
		panel.spellBar:SetShown(showSpells)
		if db and panel.spellBar.sizeText then
			panel.spellBar.sizeText:SetText(tostring(tonumber(db.missSize) or 48))
		end
		if db and panel.spellBar.holdText then
			panel.spellBar.holdText:SetText(string.format("%.1f", tonumber(db.missHold) or 3))
		end
		if panel.spellBar.moveButton then
			panel.spellBar.moveButton.label:SetText(LockRemindersMiss.moving and "Done" or "Move")
		end
		if panel.spellBar.refresh then
			panel.spellBar.refresh()
		end
	end
	if panel and panel.cdBar then
		panel.cdBar:SetShown(showCds)
		if db and panel.cdBar.sizeText then
			panel.cdBar.sizeText:SetText(tostring(LockRemindersCDIconSize()))
		end
		if db and panel.cdBar.holdText then
			panel.cdBar.holdText:SetText(string.format("%.1f", LockRemindersCDHold()))
		end
		if db and panel.cdBar.padText then
			panel.cdBar.padText:SetText(tostring(LockRemindersCDPad()))
		end
		if db and panel.cdBar.textSizeText then
			panel.cdBar.textSizeText:SetText(tostring(LockRemindersCDTextSize()))
		end
		if panel.cdBar.moveButton then
			panel.cdBar.moveButton.label:SetText(LockRemindersCD.moving and "Done" or "Move")
		end
		if panel.cdBar.refresh then
			panel.cdBar.refresh()
		end
	end
	local showMisc = activeTab == "misc"
	local showSoul = activeTab == "soul"
	local showPets = activeTab == "pets"
	local showFun = activeTab == "fun"
	local hideList = (activeTab == "alert" and module ~= "powers" and module ~= "food" and module ~= "cds") or showMisc or showSoul or showPets or showFun
	if panel and panel.miscBar then
		panel.miscBar:SetShown(showMisc)
		if showMisc then
			LockRemindersRefreshMisc()
		end
	end
	if panel and panel.soulBar then
		panel.soulBar:SetShown(showSoul)
		if showSoul then
			LockRemindersRefreshSoul()
		end
	end
	if panel and panel.petBar then
		panel.petBar:SetShown(showPets)
		if showPets then
			LockRemindersRefreshPets()
		end
	end
	if panel and panel.funBar then
		panel.funBar:SetShown(showFun)
		if showFun then
			LockRemindersRefreshFun()
		end
	end
	if emptyLabel and (showMisc or showSoul or showPets or showFun) then
		emptyLabel:Hide()
	end
	-- Tabs: two compact rows end near -96. Search / tools / list sit below.
	local listTop = -176
	if activeTab == "alert" then
		if module == "food" then
			listTop = -160
		elseif module == "cds" then
			listTop = -330
		elseif module == "talents" or module == "spells" then
			listTop = -88
		else
			listTop = -88
		end
	end
	if searchBox and searchBox.searchChrome then
		searchBox.searchChrome:ClearAllPoints()
		searchBox.searchChrome:SetPoint("TOPLEFT", 14, -108)
		searchBox.searchChrome:SetPoint("TOPRIGHT", -16, -108)
		searchBox.searchChrome:SetHeight(26)
	end
	if panel and panel.alertButton then
		panel.alertButton:ClearAllPoints()
		panel.alertButton:SetPoint("TOPRIGHT", -16, -140)
	end
	if raidCheck then
		raidCheck:ClearAllPoints()
		raidCheck:SetPoint("TOPLEFT", 112, -140)
	end
	if raidCheck and raidCheck.labelButton then
		raidCheck.labelButton:ClearAllPoints()
		raidCheck.labelButton:SetPoint("TOPLEFT", 16, -140)
	end
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", 14, listTop)
	scroll:SetPoint("BOTTOMRIGHT", -24, 40)
	scroll:SetShown(not hideList)
	if scrollBar then
		scrollBar:SetShown(not hideList)
	end
	if talentSizeText and db then
		talentSizeText:SetText(tostring(LockRemindersTalentArtSize()))
	end
	if talentHoldText and db then
		talentHoldText:SetText(string.format("%.1f", tonumber(db.talentHold) or 2.2))
	end
	if talentMoveButton then
		talentMoveButton.label:SetText(talentMoving and "Done" or "Move")
	end
	if talentBar and talentBar.refresh then
		talentBar.refresh()
	end
end

local function SetTab(id)
	activeTab = id
	local configuring = id == "alert"
	for key, tab in pairs(tabs) do
		tab:SetShown(not configuring)
		StyleTab(tab, key == id)
	end
	if panel.backButton then
		panel.backButton:SetShown(configuring)
	end
	if panel.alertTitle then
		panel.alertTitle:SetShown(configuring)
		if configuring then
			local module = panel.alertModule or "powers"
			if module == "talents" then
				panel.alertTitle:SetText("Proc alert")
			elseif module == "food" then
				panel.alertTitle:SetText("Item alert")
			elseif module == "spells" then
				panel.alertTitle:SetText("Spell misses/resist")
			elseif module == "cds" then
				panel.alertTitle:SetText("CD Manager")
			else
				panel.alertTitle:SetText("Buff alert")
			end
		end
	end
	-- Items standard: tool row always uses the same slots.
	-- Left: When adding (Buffs/Items only). Right: Configure alert (all list modules).
	local picking = id == "powers" or id == "food"
	raidCheck:SetShown(picking)
	raidCheck.labelButton:SetShown(picking)
	modeHint:Hide()
	local showConfig = id == "powers" or id == "food" or id == "talents" or id == "spells" or id == "cds"
	if panel.alertButton then
		panel.alertButton:SetShown(showConfig and not configuring)
		panel.alertButton:ClearAllPoints()
		panel.alertButton:SetPoint("TOPRIGHT", -16, -140)
	end
	footer:SetText("")
	if searchBox then
		local showSearch = not configuring and id ~= "misc" and id ~= "soul" and id ~= "pets" and id ~= "fun"
		searchBox:SetShown(showSearch)
		if searchBox.searchChrome then
			searchBox.searchChrome:ClearAllPoints()
			searchBox.searchChrome:SetPoint("TOPLEFT", 14, -108)
			searchBox.searchChrome:SetPoint("TOPRIGHT", -16, -108)
			searchBox.searchChrome:SetHeight(26)
			searchBox.searchChrome:SetShown(showSearch)
		end
	end
	UpdateTalentChrome()
	currentSignature = nil
	if panel:IsShown() then
		RebuildList(true)
	end
end

local function HidePanel()
	if searchBox then
		searchBox:ClearFocus()
	end
	panel:Hide()
end

local function TogglePanel()
	if not panel then
		Print("Still loading.")
		return
	end
	if panel:IsShown() then
		HidePanel()
	else
		panel:Show()
	end
end

local function MakeTab(label, id)
	local count = 0
	for _ in pairs(tabs) do
		count = count + 1
	end
	-- 5 compact columns keep warlock tabs on two rows inside the 760px panel.
	local col = count % 5
	local row = math.floor(count / 5)
	local tab = CreateFrame("Button", nil, panel, "BackdropTemplate")
	tab:SetSize(140, 22)
	tab:SetPoint("TOPLEFT", 14 + col * 146, -48 - row * 26)
	Paint(tab, 0.12, 0.1, 0.16, 1, 0.35, 0.28, 0.48, 1)
	tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tab.label:SetPoint("CENTER")
	tab.label:SetJustifyH("CENTER")
	tab.label:SetText(label)
	if tab.label.SetWordWrap then
		tab.label:SetWordWrap(false)
	end
	if tab.label.SetTextScale then
		pcall(tab.label.SetTextScale, tab.label, 0.92)
	end
	tab.accent = tab:CreateTexture(nil, "OVERLAY")
	tab.accent:SetPoint("BOTTOMLEFT", 4, 1)
	tab.accent:SetPoint("BOTTOMRIGHT", -4, 1)
	tab.accent:SetHeight(2)
	tab.accent:SetTexture("Interface\\Buttons\\WHITE8x8")
	tab.accent:SetVertexColor(0.78, 0.66, 1, 1)
	tab.accent:Hide()
	tab:SetScript("OnClick", function()
		if searchBox then
			searchBox:ClearFocus()
		end
		SetTab(id)
	end)
	tab:SetScript("OnEnter", function(self)
		if activeTab ~= id then
			self:SetBackdropColor(0.2, 0.15, 0.28, 1)
		end
	end)
	tab:SetScript("OnLeave", function(self)
		StyleTab(self, activeTab == id)
	end)
	tabs[id] = tab
end

local function BindSearchBox(box, templated)
	local function changed()
		local raw = box:GetText() or ""
		if raw:find("Hitem:", 1, true) and activeTab ~= "food" then
			SetTab("food")
			return
		end
		if raw:find("Hspell:", 1, true) and activeTab ~= "powers" and activeTab ~= "talents" and activeTab ~= "spells" and activeTab ~= "cds" then
			SetTab("powers")
			return
		end
		RebuildList(true)
	end
	if templated then
		box:HookScript("OnTextChanged", changed)
	else
		box:SetScript("OnTextChanged", function(self)
			if self.placeholder then
				self.placeholder:SetShown(self:GetText() == "")
			end
			changed()
		end)
	end
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if #currentEntries == 1 and not currentEntries[1].saved and currentEntries[1].action then
			currentEntries[1].action()
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
end

local function CreateSearchBox()
	-- Items standard: full-width search chrome under the tabs (all list modules share this).
	local bg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	bg:SetHeight(28)
	bg:SetPoint("TOPLEFT", 14, -108)
	bg:SetPoint("TOPRIGHT", -16, -108)
	Paint(bg, 0.03, 0.02, 0.05, 1, 0.4, 0.32, 0.55, 1)
	bg:EnableMouse(true)

	local ok, box = pcall(CreateFrame, "EditBox", "LockRemindersSearchBox", bg, "SearchBoxTemplate")
	if ok and box then
		searchBox = box
		searchBox:ClearAllPoints()
		searchBox:SetPoint("TOPLEFT", bg, "TOPLEFT", 2, -2)
		searchBox:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -2, 2)
		searchBox:SetAutoFocus(false)
		if searchBox.SetTextInsets then
			searchBox:SetTextInsets(16, 8, 0, 0)
		end
		if searchBox.Instructions then
			searchBox.Instructions:SetText("Search by name")
		end
		BindSearchBox(searchBox, true)
	else
		searchBox = CreateFrame("EditBox", "LockRemindersSearchBox", bg)
		searchBox:SetPoint("LEFT", 8, 0)
		searchBox:SetPoint("RIGHT", -8, 0)
		searchBox:SetHeight(24)
		searchBox:SetAutoFocus(false)
		searchBox:SetFontObject(GameFontHighlight)
		searchBox:SetMaxLetters(80)
		searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		searchBox.placeholder:SetPoint("LEFT", 0, 0)
		searchBox.placeholder:SetText("Search by name")
		searchBox.placeholder:SetTextColor(0.55, 0.5, 0.62)
		BindSearchBox(searchBox, false)
	end
	bg:SetScript("OnMouseDown", function()
		if searchBox then
			searchBox:SetFocus()
		end
	end)
	local prevGain = searchBox:GetScript("OnEditFocusGained")
	searchBox:SetScript("OnEditFocusGained", function(self, ...)
		bg:SetBackdropBorderColor(0.75, 0.62, 0.98, 1)
		if prevGain then
			prevGain(self, ...)
		end
	end)
	local prevLost = searchBox:GetScript("OnEditFocusLost")
	searchBox:SetScript("OnEditFocusLost", function(self, ...)
		bg:SetBackdropBorderColor(0.4, 0.32, 0.55, 1)
		if prevLost then
			prevLost(self, ...)
		end
	end)
	searchBox.searchChrome = bg
end

local function HookItemLinks()
	if linkHooked then
		return
	end
	linkHooked = true
	local lastLink, lastAt
	local function onLink(link)
		if type(link) ~= "string" or link == "" or not searchBox or not panel or not panel:IsShown() then
			return
		end
		local now = GetTime and GetTime() or 0
		if link == lastLink and lastAt and (now - lastAt) < 0.05 then
			return
		end
		lastLink, lastAt = link, now
		local text = link
		C_Timer.After(0, function()
			if not searchBox or not panel or not panel:IsShown() then
				return
			end
			local chat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
			if chat and chat ~= searchBox then
				return
			end
			local item = text:find("Hitem:", 1, true)
			if not item and not searchBox:HasFocus() then
				return
			end
			if item then
				if activeTab ~= "food" then
					SetTab("food")
				end
				searchBox:SetText(NameFromLink(text) or text)
				searchBox:SetFocus()
				return
			end
			searchBox:Insert(text)
		end)
	end
	if type(ChatEdit_InsertLink) == "function" then
		hooksecurefunc("ChatEdit_InsertLink", onLink)
	end
	if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" then
		hooksecurefunc(ChatFrameUtil, "InsertLink", onLink)
	end
end

local function TalentSize(spellID)
	return LockRemindersTalentArtSize(spellID)
end

local function TalentHold()
	local hold = tonumber(db and db.talentHold) or 2.2
	if hold < 0.8 then
		hold = 0.8
	end
	if hold > 6 then
		hold = 6
	end
	return hold
end

local function ApplyTalentPoint()
	if not talentFrame or not db or type(db.talentPoint) ~= "table" then
		return
	end
	local point = db.talentPoint
	talentFrame:ClearAllPoints()
	talentFrame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
end

local function ApplyTalentLook()
	if not talentFrame then
		return
	end
	local size = TalentSize()
	local thick = LockRemindersPlaceAlertIcon(talentFrame.icon, talentFrame.glow, size, "CENTER", "talentGlowSize")
	talentFrame:SetSize(size + thick * 2, size + thick * 2)
	LockRemindersTintEvenGlow(talentFrame.glow, LockRemindersReadGlow("talentGlow", 1, 0.82, 0.35))
	talentFrame.burst:SetSize(size * 2.6, size * 2.6)
	talentFrame.burst:ClearAllPoints()
	talentFrame.burst:SetPoint("CENTER", 0, 0)
	if talentMoving then
		Paint(talentFrame, 0.06, 0.05, 0.08, 0.55, 0.95, 0.78, 0.35, 1)
		talentFrame.hint:Show()
		talentFrame:EnableMouse(true)
	else
		pcall(talentFrame.SetBackdrop, talentFrame, nil)
		talentFrame.hint:Hide()
		talentFrame:EnableMouse(false)
	end
end

local function SaveTalentPoint()
	if not talentFrame then
		return
	end
	local point, _, relative, x, y = talentFrame:GetPoint()
	db.talentPoint = { point, relative, x, y }
end

local function PreviewTalentIcon()
	if db and type(db.talents) == "table" then
		for spellID in pairs(db.talents) do
			return SpellIcon(spellID)
		end
	end
	if GetSpellInfo then
		local ok, _, _, icon = pcall(GetSpellInfo, 17941)
		if ok and icon then
			return icon
		end
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, 17941)
		if ok and info and info.iconID then
			return info.iconID
		end
	end
	return 136216
end

function TalentUntil(spellID)
	if db and db.talentUntilEnd then
		return true
	end
	if db and db.talentUntilEnd == false then
		return false
	end
	if not db or type(db.talents) ~= "table" then
		return false
	end
	local value = db.talents[spellID] or db.talents[tostring(spellID)]
	return type(value) == "table" and value.untilEnd and true or false
end

LockRemindersProcLooks = {
	{ "Icon", "icon" },
	{ "Scythes", "scythes" },
	{ "Umbra", "umbra" },
	{ "Stormcall", "stormcall" },
	{ "Runeblade", "runeblade" },
	{ "Storm", "storm" },
	{ "Water", "water" },
	{ "Tempest", "tempest" },
	{ "Rime", "rime" },
	{ "Pillar", "pillar" },
	{ "Frostbane", "frostbane" },
	{ "Razorice", "razor" },
	{ "Eclipse", "eclipse" },
	{ "Lunar", "lunar" },
	{ "Solar", "solar" },
	{ "Owlkin", "owlkin" },
	{ "Dagger", "dagger" },
	{ "Garrote", "garrote" },
	{ "Artery", "artery" },
}

LockRemindersProcChoices = {
	{ "None", "none" },
}

LockRemindersProcArt = {
	scythes = {
		{ "ScytheShadow_L", "BLEND", 0.3, 0, 0, 0, 208, 104, "BOTTOM", 0, 62 },
		{ "ScytheSpirit_L", "ADD", 1, 0.58, 0.42, 1, 208, 104, "BOTTOM", 0, 62 },
		{ "ScytheRunes_L", "ADD", 1, 0.82, 0.7, 1, 208, 104, "BOTTOM", 0, 62 },
		{ "ScytheShadow_R", "BLEND", 0.3, 0, 0, 0, 208, 104, "BOTTOM", 0, 62 },
		{ "ScytheSpirit_R", "ADD", 1, 0.58, 0.42, 1, 208, 104, "BOTTOM", 0, 62 },
		{ "ScytheRunes_R", "ADD", 1, 0.82, 0.7, 1, 208, 104, "BOTTOM", 0, 62 },
	},
	-- HD side overlays from Shadowflare Art (copied into Textures/Procs). White tint keeps native colors.
	umbra = {
		{ "umbra", "ADD", 1, 1, 1, 1, 128, 256, "RIGHT", -48, 0 },
		{ "umbra", "ADD", 1, 1, 1, 1, 128, 256, "LEFT", 48, 0, nil, true },
	},
	stormcall = {
		{ "stormcall", "ADD", 1, 1, 1, 1, 128, 256, "RIGHT", -48, 0 },
		{ "stormcall", "ADD", 1, 1, 1, 1, 128, 256, "LEFT", 48, 0, nil, true },
	},
	runeblade = {
		{ "RunebladeShadow_L", "BLEND", 0.35, 0, 0, 0, 150, 300, "RIGHT", -130, 0 },
		{ "RunebladeSpirit_L", "ADD", 1, 0.36, 0.72, 1, 150, 300, "RIGHT", -130, 0 },
		{ "RunebladeRunes_L", "ADD", 1, 0.62, 0.88, 1, 150, 300, "RIGHT", -130, 0 },
		{ "RunebladeEdge_L", "ADD", 0.9, 0.75, 0.92, 1, 150, 300, "RIGHT", -130, 0 },
	},
	storm = {
		{ "StormArc_L", "ADD", 1, 0.42, 0.4, 1, 150, 300, "RIGHT", -130, 0 },
		{ "StormBoltsA_L", "ADD", 0.9, 0.72, 0.7, 1, 150, 300, "RIGHT", -130, 0 },
	},
	water = {
		{ "WaveArc_R", "ADD", 1, 0.16, 0.86, 0.9, 150, 300, "LEFT", 130, 0 },
	},
	tempest = {
		{ "GoblinSkull", "ADD", 1, 0.8, 0.86, 1, 130, 130, "CENTER", -100, 20 },
		{ "GoblinJaw", "ADD", 1, 0.8, 0.86, 1, 130, 130, "CENTER", -100, 20 },
		{ "GoblinEyes", "ADD", 1, 1, 1, 1, 130, 130, "CENTER", -100, 20 },
	},
	rime = {
		{ "RimeShadow_R", "BLEND", 0.35, 0, 0, 0, 150, 300, "LEFT", 130, 0 },
		{ "RimeBand_R", "ADD", 1, 0.55, 0.85, 1, 150, 300, "LEFT", 130, 0 },
		{ "RimeCrystals_R", "ADD", 1, 0.75, 0.95, 1, 150, 300, "LEFT", 130, 0 },
	},
	pillar = {
		{ "PillarShadow", "BLEND", 0.35, 0, 0, 0, 256, 64, "TOP", 0, -80 },
		{ "PillarCore", "ADD", 1, 0.45, 0.82, 1, 256, 64, "TOP", 0, -80 },
		{ "PillarFlare", "ADD", 0.85, 0.7, 0.95, 1, 256, 64, "TOP", 0, -80 },
	},
	razor = {
		{ "RazorShadow", "BLEND", 0.35, 0, 0, 0, 84, 84, "CENTER", -110, 10 },
		{ "RazorLight", "ADD", 1, 0.3, 1, 0.82, 84, 84, "CENTER", -110, 10 },
		{ "RazorCracks", "ADD", 1, 0.7, 1, 0.92, 84, 84, "CENTER", -110, 10 },
	},
	eclipse = {
		{ "LunarBandA_L", "ADD", 1, 0.62, 0.4, 1, 150, 300, "RIGHT", -130, 0 },
		{ "MoonDisc", "ADD", 1, 0.62, 0.4, 1, 90, 90, "CENTER", -160, 20 },
		{ "SolarBandA_R", "ADD", 1, 1, 0.62, 0.14, 150, 300, "LEFT", 130, 0 },
		{ "SunDisc", "ADD", 1, 1, 0.62, 0.14, 90, 90, "CENTER", 160, 20 },
	},
	owlkin = {
		{ "OwlkinShadow", "BLEND", 0.4, 0, 0, 0, 224, 128, "BOTTOM", 0, 62 },
		{ "OwlkinWings", "ADD", 1, 0.52, 0.5, 1, 224, 128, "BOTTOM", 0, 62 },
		{ "OwlkinFace", "ADD", 1, 0.52, 0.5, 1, 224, 128, "BOTTOM", 0, 62 },
		{ "OwlkinBeak", "ADD", 1, 0.72, 0.7, 1, 224, 128, "BOTTOM", 0, 62 },
		{ "OwlkinEyes", "ADD", 1, 1, 1, 1, 224, 128, "BOTTOM", 0, 62 },
	},
	dagger = {
		{ "DaggerShadow", "BLEND", 0.4, 0, 0, 0, 256, 64, "TOP", 0, -130 },
		{ "DaggerBlade", "ADD", 1, 0.75, 0.8, 0.7, 256, 64, "TOP", 0, -130 },
		{ "DaggerPoison", "ADD", 1, 0.35, 0.85, 0.2, 256, 64, "TOP", 0, -130 },
	},
	garrote = {
		{ "GarroteWire_L", "ADD", 1, 0.55, 0.08, 0.08, 150, 300, "RIGHT", -130, 0 },
		{ "GarroteBlood_L", "ADD", 0.9, 0.86, 0.06, 0.07, 150, 300, "RIGHT", -130, 0 },
	},
	frostbane = {
		{ "FrostbaneFlameA", "ADD", 0.75, 0.5, 0.86, 1, 104, 104, "CENTER", 135, 0 },
		{ "FrostbaneFlameB", "ADD", 0.75, 0.5, 0.86, 1, 104, 104, "CENTER", 135, 0 },
		{ "FrostbaneIce", "ADD", 1, 0.78, 0.96, 1, 104, 104, "CENTER", 135, 0 },
		{ "FrostbaneShine", "ADD", 0.9, 0.78, 0.96, 1, 104, 104, "CENTER", 135, 0 },
		{ 135842, "BLEND", 1, 1, 1, 1, 88, 88, "CENTER", 135, -4, "FrostbaneSkullMask" },
		{ "FrostbaneEye", "ADD", 1, 0.9, 0.98, 1, 28, 28, "CENTER", 128, 10 },
	},
	lunar = {
		{ "Glow_L", "ADD", 0.5, 0.62, 0.4, 1, 150, 300, "RIGHT", -130, 0 },
		{ "LunarBandA_L", "ADD", 0.85, 0.62, 0.4, 1, 150, 300, "RIGHT", -130, 0 },
		{ "LunarBandB_L", "ADD", 0.9, 0.62, 0.4, 1, 150, 300, "RIGHT", -130, 0 },
		{ "MoonDisc", "BLEND", 1, 0.8, 0.9, 1, 96, 96, "CENTER", -239, 0 },
		{ "BodyGlow", "ADD", 0.45, 0.8, 0.9, 1, 96, 96, "CENTER", -239, 0 },
		{ "MoonCorona", "ADD", 0.95, 0.62, 0.4, 1, 192, 192, "CENTER", -239, 0 },
		{ "EclipseShadow", "BLEND", 0.85, 0, 0, 0, 96, 96, "CENTER", -239, 0 },
	},
	solar = {
		{ "Glow_R", "ADD", 0.6, 1, 0.62, 0.14, 150, 300, "LEFT", 130, 0 },
		{ "SolarBandA_R", "ADD", 0.85, 1, 0.62, 0.14, 150, 300, "LEFT", 130, 0 },
		{ "SolarBandB_R", "ADD", 0.95, 1, 0.62, 0.14, 150, 300, "LEFT", 130, 0 },
		{ "SunDisc", "BLEND", 1, 1, 0.9, 0.58, 96, 96, "CENTER", 239, 0 },
		{ "SunCore", "ADD", 0.42, 1, 1, 1, 96, 96, "CENTER", 239, 0 },
		{ "SunCorona", "ADD", 1, 1, 0.62, 0.14, 192, 192, "CENTER", 239, 0 },
		{ "SunFlare", "ADD", 0.85, 1, 1, 1, 64, 64, "CENTER", 253, 26 },
		{ "EclipseShadow", "BLEND", 0.9, 0, 0, 0, 96, 96, "CENTER", 239, 0 },
	},
	artery = {
		{ "BleedShadow_R", "BLEND", 0.28, 0, 0, 0, 150, 300, "LEFT", 130, 0 },
		{ "ArteryBranches_R", "BLEND", 0.95, 1, 1, 1, 150, 300, "LEFT", 130, 0 },
		{ "ArteryBlood_R", "BLEND", 1, 0.96, 0.1, 0.08, 150, 300, "LEFT", 130, 0 },
		{ "ArteryWall_R", "BLEND", 1, 1, 1, 1, 150, 300, "LEFT", 130, 0 },
	},
}

function LockRemindersMapLook(style)
	if style == "icon" then
		return "icon"
	end
	if style == "trivial" then
		return "storm"
	end
	if style == "magic" or style == "decor" then
		return "scythes"
	end
	if style and LockRemindersProcArt[style] then
		return style
	end
	return "scythes"
end

function LockRemindersLookLabel(style)
	style = LockRemindersMapLook(style)
	local looks = LockRemindersProcLooks
	for index = 1, #looks do
		if looks[index][2] == style then
			return looks[index][1]
		end
	end
	return "Scythes"
end

function LockRemindersSoundLabel(id)
	local choices = LockRemindersSoundChoices
	if choices then
		for index = 1, #choices do
			if choices[index][2] == id then
				return choices[index][1]
			end
		end
	end
	return "None"
end

function LockRemindersEditedTalent()
	local key = LockRemindersSelectedTalent
	if key and db and db.talents and db.talents[key] ~= nil then
		return key
	end
	if db and type(db.talents) == "table" then
		for saved in pairs(db.talents) do
			LockRemindersSelectedTalent = saved
			return saved
		end
	end
	LockRemindersSelectedTalent = nil
end

function LockRemindersEnsureTalent(spellID)
	if not db or type(db.talents) ~= "table" or spellID == nil then
		return nil
	end
	local value = db.talents[spellID]
	if type(value) ~= "table" then
		value = {}
		db.talents[spellID] = value
	end
	if type(value.style) ~= "string" then
		value.style = LockRemindersMapLook(db.talentStyle)
	else
		value.style = LockRemindersMapLook(value.style)
	end
	if not LockRemindersKnownSound(value.sound) then
		value.sound = LockRemindersKnownSound(db.talentSound) and db.talentSound or "none"
	end
	return value
end

function LockRemindersTalentArtSize(spellID)
	if spellID == nil then
		spellID = (talentFrame and talentFrame.spellID) or LockRemindersEditedTalent()
	end
	local value = db and db.talents and spellID and db.talents[spellID]
	local size = type(value) == "table" and tonumber(value.size) or tonumber(db and db.talentSize) or 72
	if size < 40 then
		size = 40
	end
	if size > 160 then
		size = 160
	end
	return size
end

function LockRemindersTalentFade(spellID)
	if spellID == nil then
		spellID = (talentFrame and talentFrame.spellID) or LockRemindersEditedTalent()
	end
	local value = db and db.talents and spellID and db.talents[spellID]
	local fade = type(value) == "table" and tonumber(value.fade) or tonumber(db and db.talentFade) or 0.4
	fade = math.floor(fade * 10 + 0.5) / 10
	if fade < 0 then
		fade = 0
	end
	if fade > 2 then
		fade = 2
	end
	return fade
end

function LockRemindersProcPalette(style)
	local design = LockRemindersProcArt and LockRemindersProcArt[style]
	local color, accent
	if design then
		for index = 1, #design do
			local red, green, blue = design[index][4], design[index][5], design[index][6]
			local sum = (red or 0) + (green or 0) + (blue or 0)
			local white = red and red > 0.97 and green > 0.97 and blue > 0.97
			if sum > 0.08 and not white then
				if not color then
					color = { red, green, blue }
				elseif not accent then
					local gap = math.abs(red - color[1]) + math.abs(green - color[2]) + math.abs(blue - color[3])
					if gap > 0.08 then
						accent = { red, green, blue }
					end
				end
			end
		end
	end
	if not color then
		color = { 1, 0.82, 0.35 }
	end
	if not accent then
		accent = { color[1], color[2], color[3] }
	end
	return color, accent
end

function LockRemindersTalentColor(spellID, which)
	if spellID == nil then
		spellID = LockRemindersEditedTalent()
	end
	local color, accent = LockRemindersProcPalette(LockRemindersTalentStyle(spellID))
	local fallback = which == "accent" and accent or color
	local value = db and db.talents and spellID and db.talents[spellID]
	local saved = type(value) == "table" and value[which]
	if type(saved) ~= "table" and db then
		saved = which == "accent" and db.talentLookAccent or db.talentLookColor
	end
	local red = type(saved) == "table" and tonumber(saved.r) or nil
	local green = type(saved) == "table" and tonumber(saved.g) or nil
	local blue = type(saved) == "table" and tonumber(saved.b) or nil
	if not red or not green or not blue then
		return fallback[1], fallback[2], fallback[3]
	end
	return red, green, blue
end

function LockRemindersFadeTalent(spellID)
	if talentMoving then
		return
	end
	if LockRemindersTalentPreviewUntil and GetTime() < LockRemindersTalentPreviewUntil then
		return
	end
	if talentFrame then
		talentFrame.hold = false
		if talentFrame.hideTimer then
			talentFrame.hideTimer:Cancel()
			talentFrame.hideTimer = nil
		end
	end
	local seconds = LockRemindersTalentFade(spellID)
	local ornament = LockRemindersTalentOrnament
	if seconds <= 0 then
		LockRemindersHideTalentOrnament()
		if talentFrame then
			talentFrame:Hide()
		end
		return
	end
	if ornament and ornament:IsShown() then
		ornament.pulse = false
		ornament.fading = seconds
		ornament.fadeAge = 0
		ornament.fadeFrom = ornament:GetAlpha()
	end
	if talentFrame and talentFrame:IsShown() and talentFrame.fadeOut and talentFrame.fade then
		talentFrame.fadeOut:SetDuration(seconds)
		talentFrame.fade:Stop()
		talentFrame.fade:Play()
	elseif talentFrame and not (ornament and ornament:IsShown()) then
		talentFrame:Hide()
	end
end

function LockRemindersClearTalentProc(spellID)
	if talentMoving then
		return
	end
	if LockRemindersTalentPreviewUntil and GetTime() < LockRemindersTalentPreviewUntil then
		return
	end
	if spellID ~= nil then
		talentRecent[spellID] = nil
		talentRecent[tostring(spellID)] = nil
		local numeric = tonumber(spellID)
		if numeric then
			talentRecent[numeric] = nil
		end
		if talentSeen then
			talentSeen[spellID] = false
			talentSeen[tostring(spellID)] = false
			if numeric then
				talentSeen[numeric] = false
			end
		end
	end
	pcall(LockRemindersFadeTalent, spellID)
end

function LockRemindersTalentStyle(spellID)
	if spellID == nil then
		spellID = LockRemindersEditedTalent()
	end
	local value = db and db.talents and spellID and db.talents[spellID]
	local style = type(value) == "table" and value.style or db and db.talentStyle
	return LockRemindersMapLook(style)
end

function LockRemindersTalentSound(spellID)
	if spellID == nil then
		spellID = LockRemindersEditedTalent()
	end
	local value = db and db.talents and spellID and db.talents[spellID]
	local sound = type(value) == "table" and value.sound
	if LockRemindersKnownSound(sound) then
		return sound
	end
	if LockRemindersKnownSound(db and db.talentSound) then
		return db.talentSound
	end
	return "none"
end

function LockRemindersFillProcChoices()
	local choices = LockRemindersProcChoices
	for index = #choices, 1, -1 do
		choices[index] = nil
	end
	if db and type(db.talents) == "table" then
		for key in pairs(db.talents) do
			local name = SpellDisplayName(key) or SpellName(key) or tostring(key)
			choices[#choices + 1] = { name, key }
		end
		table.sort(choices, function(left, right)
			return tostring(left[1]) < tostring(right[1])
		end)
	end
	if #choices == 0 then
		choices[1] = { "None", "none" }
	end
end

function PlayAlertSound(spellID)
	LockRemindersPlaySoundId(LockRemindersTalentSound(spellID))
end

function PlayScreenFlash()
	local flash = talentFrame and talentFrame.screenFlash
	if not flash or not db or db.talentScreenFlash == false then
		return
	end
	flash:Show()
	flash:SetAlpha(0.5)
	if flash.ag then
		flash.ag:Stop()
		flash.ag:Play()
	end
end

function QuietScreenFlash()
	if not db or db.talentScreenFlash ~= false then
		return
	end
	local overlay = SpellActivationOverlayFrame or SpellActivationOverlay
	if overlay and overlay.Hide then
		pcall(overlay.Hide, overlay)
	end
end

function LockRemindersTalentOnScreen(spellID)
	if spellID == nil then
		spellID = talentFrame and talentFrame.spellID or LockRemindersEditedTalent()
	end
	return LockRemindersTalentStyle(spellID) == "icon"
end

function LockRemindersHideTalentOrnament()
	local frame = LockRemindersTalentOrnament
	if not frame then
		return
	end
	frame.pulse = false
	frame.fading = nil
	frame:EnableMouse(false)
	if frame.hint then
		frame.hint:Hide()
	end
	frame:SetAlpha(1)
	frame:Hide()
end

function LockRemindersSaveTalentArtPoint()
	local frame = LockRemindersTalentOrnament
	if not frame or not db then
		return
	end
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not cx or not cy or not ux or not uy then
		return
	end
	local x = math.floor(cx - ux + 0.5)
	local y = math.floor(cy - uy + 0.5)
	if x < -400 then
		x = -400
	end
	if x > 400 then
		x = 400
	end
	if y < -400 then
		y = -400
	end
	if y > 400 then
		y = 400
	end
	local key = LockRemindersEditedTalent() or (talentFrame and talentFrame.spellID)
	local entry = key and LockRemindersEnsureTalent(key)
	if entry then
		entry.x = x
		entry.y = y
	else
		db.talentArtX = x
		db.talentArtY = y
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function LockRemindersShowTalentOrnament(style, spellID)
	if style == nil or style == "icon" or not LockRemindersProcArt[style] then
		LockRemindersHideTalentOrnament()
		return
	end
	local frame = LockRemindersTalentOrnament
	if not frame then
		frame = CreateFrame("Frame", nil, UIParent)
		frame:SetSize(640, 480)
		frame:SetFrameStrata("DIALOG")
		frame:SetFrameLevel(40)
		frame:SetClampedToScreen(true)
		frame:SetMovable(true)
		frame:EnableMouse(false)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			if talentMoving then
				self.pulse = false
				self:SetAlpha(1)
				self:StartMoving()
			end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			LockRemindersSaveTalentArtPoint()
			if talentMoving then
				self.pulse = true
				self.age = 0
			end
		end)
		frame.left = frame:CreateTexture(nil, "ARTWORK")
		frame.right = frame:CreateTexture(nil, "ARTWORK")
		frame.top = frame:CreateTexture(nil, "ARTWORK")
		frame.left:SetBlendMode("ADD")
		frame.right:SetBlendMode("ADD")
		frame.top:SetBlendMode("ADD")
		frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		frame.hint:SetPoint("TOP", frame, "BOTTOM", 0, -6)
		frame.hint:SetText("Drag")
		frame.hint:SetTextColor(1, 0.86, 0.45)
		frame.hint:Hide()
		frame:SetScript("OnUpdate", function(self, elapsed)
			elapsed = elapsed or 0
			if self.fading then
				self.fadeAge = (self.fadeAge or 0) + elapsed
				local span = self.fading
				if not span or span <= 0 or self.fadeAge >= span then
					self.fading = nil
					self.pulse = false
					self:SetAlpha(1)
					self:Hide()
					return
				end
				self:SetAlpha((self.fadeFrom or 1) * (1 - self.fadeAge / span))
				return
			end
			if not self.pulse then
				return
			end
			self.age = (self.age or 0) + elapsed
			self:SetAlpha(0.55 + 0.45 * math.sin(self.age * 4))
		end)
		LockRemindersTalentOrnament = frame
	end
	if frame:GetParent() ~= UIParent then
		frame:SetParent(UIParent)
	end
	local artX, artY = LockRemindersTalentArtOffset(spellID)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", artX, artY)
	frame:EnableMouse(talentMoving and true or false)
	if frame.hint then
		frame.hint:SetShown(talentMoving and true or false)
	end
	if frame.left then
		frame.left:Hide()
	end
	if frame.right then
		frame.right:Hide()
	end
	if frame.top then
		frame.top:Hide()
	end
	local design = LockRemindersProcArt[style]
	local scale = TalentSize(spellID) / 72
	local media = "Interface\\AddOns\\LockReminders\\Textures\\Procs\\"
	local colorDefault, accentDefault = LockRemindersProcPalette(style)
	local colorRed, colorGreen, colorBlue = LockRemindersTalentColor(spellID, "color")
	local accentRed, accentGreen, accentBlue = LockRemindersTalentColor(spellID, "accent")
	frame.arts = frame.arts or {}
	for index = 1, #design do
		local spec = design[index]
		local tex = frame.arts[index]
		if not tex then
			tex = frame:CreateTexture(nil, "ARTWORK", nil, index)
			frame.arts[index] = tex
		end
		local file = spec[1]
		if type(file) == "number" then
			tex:SetTexture(file)
		else
			tex:SetTexture(media .. file)
			if not tex:GetTexture() then
				tex:SetTexture(media .. file .. ".tga")
			end
		end
		if not tex:GetTexture() then
			tex:Hide()
		else
			local red, green, blue = spec[4], spec[5], spec[6]
			local sum = (red or 0) + (green or 0) + (blue or 0)
			local white = red and green and blue and red > 0.97 and green > 0.97 and blue > 0.97
			if sum > 0.08 and not white then
				local gap = math.abs((red or 0) - colorDefault[1]) + math.abs((green or 0) - colorDefault[2]) + math.abs((blue or 0) - colorDefault[3])
				if gap > 0.08 then
					red, green, blue = accentRed, accentGreen, accentBlue
				else
					red, green, blue = colorRed, colorGreen, colorBlue
				end
			end
			red, green, blue = red or 1, green or 1, blue or 1
			tex:SetBlendMode(spec[2])
			tex:SetAlpha(spec[3])
			tex:SetVertexColor(red, green, blue, 1)
			tex:SetSize(spec[7] * scale, spec[8] * scale)
			tex:ClearAllPoints()
			tex:SetPoint(spec[9], frame, "CENTER", spec[10] * scale, spec[11] * scale)
			if spec[13] then
				tex:SetTexCoord(1, 0, 0, 1)
			else
				tex:SetTexCoord(0, 1, 0, 1)
			end
			if tex.lookMask and tex.RemoveMaskTexture then
				tex:RemoveMaskTexture(tex.lookMask)
				tex.lookMask:Hide()
				tex.lookMask = nil
			end
			if spec[12] and frame.CreateMaskTexture and tex.AddMaskTexture then
				local ok, mask = pcall(frame.CreateMaskTexture, frame)
				if ok and mask then
					mask:SetAllPoints(tex)
					if not pcall(mask.SetTexture, mask, media .. spec[12], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
						mask:SetTexture(media .. spec[12])
					end
					pcall(tex.AddMaskTexture, tex, mask)
					tex.lookMask = mask
				end
			end
			if tex.SetHorizTile then
				tex:SetHorizTile(false)
			end
			if tex.SetVertTile then
				tex:SetVertTile(false)
			end
			tex:Show()
		end
	end
	for index = #design + 1, #frame.arts do
		frame.arts[index]:Hide()
	end
	frame.fading = nil
	frame.pulse = true
	frame.age = 0
	frame:SetAlpha(1)
	frame:Show()
end

function ApplyTalentFace(spellID)
	if not talentFrame then
		return
	end
	local style = LockRemindersTalentStyle(spellID)
	if talentFrame.ornament then
		talentFrame.ornament:Hide()
	end
	talentFrame.icon:SetTexture(spellID and SpellIcon(spellID) or PreviewTalentIcon())
	if style ~= "icon" then
		-- Scythes / art styles: ornament only (no buff icon on top).
		talentFrame.icon:Hide()
		if talentFrame.glow then
			talentFrame.glow:Hide()
		end
		LockRemindersShowTalentOrnament(style, spellID)
	else
		LockRemindersHideTalentOrnament()
		talentFrame.icon:SetDrawLayer("OVERLAY", 7)
		talentFrame.icon:Show()
		if talentFrame.glow then
			talentFrame.glow:Show()
		end
	end
end

local function PlayTalent(spellID, preview)
	if not talentFrame then
		pcall(CreateTalentAlert)
	end
	if not talentFrame then
		return
	end
	ApplyTalentLook()
	ApplyTalentPoint()
	ApplyTalentFace(spellID)
	talentFrame.spellID = spellID
	talentFrame:SetAlpha(1)
	talentFrame:SetScale(1)
	talentFrame:SetFrameStrata("TOOLTIP")
	talentFrame:SetFrameLevel(200)
	local style = LockRemindersTalentStyle(spellID)
	local ornament = LockRemindersTalentOrnament
	if style == "icon" then
		talentFrame:Show()
	else
		talentFrame:Hide()
		if ornament and ornament:IsShown() then
			ornament:SetFrameStrata("TOOLTIP")
			ornament:SetFrameLevel(210)
		end
	end
	PlayAlertSound(spellID)
	if style == "icon" and talentFrame.glow and talentFrame.glow.ag then
		talentFrame.glow.ag:Stop()
		talentFrame.glow.ag:Play()
	end
	if style == "icon" and talentFrame.pop then
		talentFrame.pop:Stop()
		talentFrame.pop:Play()
	end
	if db.talentScreenFlash ~= false then
		PlayScreenFlash()
	else
		QuietScreenFlash()
	end
	if talentFrame.hideTimer then
		talentFrame.hideTimer:Cancel()
		talentFrame.hideTimer = nil
	end
	if talentMoving then
		talentFrame.hold = false
		LockRemindersTalentPreviewUntil = nil
		return
	end
	if preview then
		-- Keep Test visible; Nightfall poll must not wipe it.
		local hold = TalentHold()
		if hold < 6 then
			hold = 6
		end
		LockRemindersTalentPreviewUntil = GetTime() + hold
		talentFrame.hold = false
		talentFrame.hideTimer = C_Timer.NewTimer(hold, function()
			LockRemindersTalentPreviewUntil = nil
			if not talentFrame or talentMoving then
				return
			end
			LockRemindersFadeTalent(talentFrame.spellID)
		end)
		return
	end
	LockRemindersTalentPreviewUntil = nil
	local stay = TalentUntil(spellID)
	talentFrame.hold = stay
	if stay then
		return
	end
	talentFrame.hideTimer = C_Timer.NewTimer(TalentHold(), function()
		if not talentFrame or talentMoving then
			return
		end
		LockRemindersFadeTalent(talentFrame.spellID)
	end)
end

function ShowTalentPreview(show)
	talentMoving = show and true or false
	if not talentFrame then
		return
	end
	if talentFrame.hideTimer then
		talentFrame.hideTimer:Cancel()
		talentFrame.hideTimer = nil
	end
	if talentFrame.fade then
		talentFrame.fade:Stop()
	end
	talentFrame:SetAlpha(1)
	local key = LockRemindersEditedTalent()
	local style = LockRemindersTalentStyle(key)
	talentFrame.spellID = key
	if talentMoving then
		LockRemindersTalentPreviewUntil = nil
		ApplyTalentLook()
		ApplyTalentPoint()
		ApplyTalentFace(key)
		if style == "icon" then
			talentFrame:Show()
		else
			talentFrame:Hide()
			local ornament = LockRemindersTalentOrnament
			if ornament then
				ornament.fading = nil
				ornament.pulse = true
				ornament.age = 0
				ornament:SetAlpha(1)
				ornament:EnableMouse(true)
				if ornament.hint then
					ornament.hint:Show()
				end
				ornament:Show()
			end
		end
		Print("Drag the animation. Press Done when you finish.")
	else
		LockRemindersTalentPreviewUntil = nil
		ApplyTalentLook()
		local ornament = LockRemindersTalentOrnament
		if ornament then
			ornament:EnableMouse(false)
			if ornament.hint then
				ornament.hint:Hide()
			end
		end
		LockRemindersHideTalentOrnament()
		talentFrame:Hide()
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ChangeTalentSize(delta)
	local key = LockRemindersEditedTalent()
	local entry = key and LockRemindersEnsureTalent(key)
	local size = LockRemindersTalentArtSize(key) + delta
	if size < 40 then
		size = 40
	end
	if size > 160 then
		size = 160
	end
	if entry then
		entry.size = size
	else
		db.talentSize = size
	end
	ApplyTalentLook()
	local style = LockRemindersTalentStyle(key)
	if style ~= "icon" then
		LockRemindersShowTalentOrnament(style, key)
	elseif talentMoving and talentFrame then
		talentFrame:Show()
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersTalentArtOffset(spellID)
	if spellID == nil then
		spellID = (talentFrame and talentFrame.spellID) or LockRemindersEditedTalent()
	end
	local value = db and db.talents and spellID and db.talents[spellID]
	local x = type(value) == "table" and tonumber(value.x) or tonumber(db and db.talentArtX) or 0
	local y = type(value) == "table" and tonumber(value.y) or tonumber(db and db.talentArtY) or 0
	if x < -400 then
		x = -400
	end
	if x > 400 then
		x = 400
	end
	if y < -400 then
		y = -400
	end
	if y > 400 then
		y = 400
	end
	return x, y
end

function ChangeTalentPlace(axis, delta)
	local key = LockRemindersEditedTalent()
	local entry = key and LockRemindersEnsureTalent(key)
	local x, y = LockRemindersTalentArtOffset(key)
	if axis == "x" then
		x = x + delta
	else
		y = y + delta
	end
	if x < -400 then
		x = -400
	end
	if x > 400 then
		x = 400
	end
	if y < -400 then
		y = -400
	end
	if y > 400 then
		y = 400
	end
	if entry then
		entry.x = x
		entry.y = y
	elseif db then
		db.talentArtX = x
		db.talentArtY = y
	end
	local style = LockRemindersTalentStyle(key)
	if style ~= "icon" then
		LockRemindersShowTalentOrnament(style, key)
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ChangeTalentFade(delta)
	local key = LockRemindersEditedTalent()
	local entry = key and LockRemindersEnsureTalent(key)
	local fade = LockRemindersTalentFade(key) + delta
	fade = math.floor(fade * 10 + 0.5) / 10
	if fade < 0 then
		fade = 0
	end
	if fade > 2 then
		fade = 2
	end
	if entry then
		entry.fade = fade
	elseif db then
		db.talentFade = fade
	end
	local style = LockRemindersTalentStyle(key)
	if style ~= "icon" then
		LockRemindersShowTalentOrnament(style, key)
		LockRemindersFadeTalent(key)
	elseif talentFrame then
		ApplyTalentFace(key)
		talentFrame:SetAlpha(1)
		talentFrame:Show()
		LockRemindersFadeTalent(key)
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ChangeTalentHold(delta)
	db.talentHold = TalentHold() + delta
	db.talentHold = TalentHold()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersTalentNameMatch(left, right)
	left = Normalize(left or "")
	right = Normalize(right or "")
	if left == "" or right == "" then
		return false
	end
	if left == right then
		return true
	end
	if (left == "shadow trance" or left == "trance de las sombras") and (right == "nightfall" or right == "anochecer" or right == "caida de la noche") then
		return true
	end
	if (right == "shadow trance" or right == "trance de las sombras") and (left == "nightfall" or left == "anochecer" or left == "caida de la noche") then
		return true
	end
	if left == "decimation" or left == "decimacion" then
		return right == "decimation" or right == "decimacion"
	end
	if left == "conflagrate" or left == "conflagrar" or left == "conflagracion" then
		return right == "conflagrate" or right == "conflagrar" or right == "conflagracion"
	end
	return false
end

function LockRemindersTalentAliasNames(spellID)
	spellID = tonumber(spellID)
	local list = {}
	local seen = {}
	local function add(name)
		name = Normalize(name or "")
		if name == "" or name:find("^spell ", 1, true) or name:find("^hechizo ", 1, true) or seen[name] then
			return
		end
		seen[name] = true
		list[#list + 1] = name
	end
	if spellID then
		add(SpellDisplayName(spellID))
		add(SpellName(spellID))
		if spellID == 17941 or spellID == 18094 or spellID == 18095 then
			add("shadow trance")
			add("nightfall")
			add("trance de las sombras")
			add("anochecer")
			add("caida de la noche")
		elseif spellID == 34936 then
			add("backlash")
			add("contragolpe")
		elseif spellID == 440873 or spellID == 440870 then
			add("decimation")
			add("decimacion")
		elseif spellID == 1293817 or spellID == 17962 then
			add("conflagrate")
			add("conflagrar")
			add("conflagracion")
		end
	end
	return list
end

function LockRemindersTalentKeyFromName(name)
	if not db or type(db.talents) ~= "table" or name == nil then
		return nil
	end
	local wanted
	pcall(function()
		local plain = Plain(name)
		wanted = Normalize(plain or name)
	end)
	if not wanted or wanted == "" or wanted:find("^spell ", 1, true) or wanted:find("^hechizo ", 1, true) then
		return nil
	end
	for saved in pairs(db.talents) do
		local aliases = LockRemindersTalentAliasNames(saved)
		for index = 1, #aliases do
			if aliases[index] == wanted or LockRemindersTalentNameMatch(aliases[index], wanted) then
				return saved
			end
		end
	end
	if wanted == "shadow trance" or wanted == "nightfall" or wanted == "trance de las sombras" or wanted == "anochecer" or wanted == "caida de la noche" then
		if db.talents[17941] ~= nil or db.talents["17941"] ~= nil then
			return db.talents[17941] ~= nil and 17941 or "17941"
		end
	end
	if wanted == "backlash" or wanted == "contragolpe" then
		if db.talents[34936] ~= nil or db.talents["34936"] ~= nil then
			return db.talents[34936] ~= nil and 34936 or "34936"
		end
	end
	if wanted == "decimation" or wanted == "decimacion" then
		if db.talents[440873] ~= nil or db.talents["440873"] ~= nil then
			return db.talents[440873] ~= nil and 440873 or "440873"
		end
	end
	if wanted == "conflagrate" or wanted == "conflagrar" or wanted == "conflagracion" then
		if db.talents[1293817] ~= nil or db.talents["1293817"] ~= nil then
			return db.talents[1293817] ~= nil and 1293817 or "1293817"
		end
		if db.talents[17962] ~= nil or db.talents["17962"] ~= nil then
			return db.talents[17962] ~= nil and 17962 or "17962"
		end
	end
	return nil
end

function LockRemindersTalentAlertShowing(spellID)
	local ornament = LockRemindersTalentOrnament
	if ornament and ornament:IsShown() then
		return true
	end
	if talentFrame and talentFrame:IsShown() then
		if spellID == nil or talentFrame.spellID == nil then
			return true
		end
		return talentFrame.spellID == spellID or tostring(talentFrame.spellID) == tostring(spellID)
	end
	return false
end

function TriggerTalent(spellID, name)
	if not db or type(db.talents) ~= "table" or not next(db.talents) then
		return false
	end
	local key = TalentKey(spellID)
	if not key and LockRemindersSecret(spellID) then
		for saved in pairs(db.talents) do
			local id = tonumber(saved)
			if id then
				local aliases = SpellAliases(id)
				for index = 1, #aliases do
					if LockRemindersSameSpell(spellID, aliases[index]) then
						key = saved
						break
					end
				end
			end
			if key then
				break
			end
		end
	end
	if not key and name then
		key = LockRemindersTalentKeyFromName(name)
	end
	if not key and spellID then
		key = LockRemindersTalentKeyFromName(SpellName(spellID))
	end
	if not key then
		return false
	end
	local now = GetTime()
	local showing = LockRemindersTalentAlertShowing(key)
	if talentRecent[key] and now - talentRecent[key] < 1.2 and showing then
		return true
	end
	talentRecent[key] = now
	if talentSeen then
		talentSeen[key] = true
	end
	if not talentFrame then
		pcall(CreateTalentAlert)
	end
	PlayTalent(key)
	if not LockRemindersTalentAlertShowing(key) then
		return false
	end
	return true
end

function LockRemindersTalentFromGlow(spellID)
	if not db or type(db.talents) ~= "table" or not next(db.talents) then
		return nil
	end
	local key = TalentKey(spellID)
	if key then
		return key
	end
	local name = Normalize(SpellName(spellID) or "")
	if name == "" or name:find("^spell ", 1, true) or name:find("^hechizo ", 1, true) then
		name = ""
	end
	local shadowBolts = {
		[686] = true, [695] = true, [705] = true, [1088] = true, [1106] = true,
		[7641] = true, [11659] = true, [11660] = true, [11661] = true,
		[25307] = true, [27209] = true, [47808] = true, [47809] = true,
	}
	local plainID = tonumber(spellID)
	local isBolt = plainID and shadowBolts[plainID]
	if not isBolt and name ~= "" then
		isBolt = name:find("shadow bolt", 1, true) or name:find("proyectil de las sombras", 1, true) or name:find("descarga de las sombras", 1, true)
	end
	if not isBolt and spellID ~= nil and LockRemindersSameSpell then
		for boltID in pairs(shadowBolts) do
			if LockRemindersSameSpell(spellID, boltID) then
				isBolt = true
				break
			end
		end
	end
	local isIncinerate = name:find("incinerate", 1, true) or name:find("incinerar", 1, true)
	local isSoulFire = name:find("soul fire", 1, true) or name:find("fuego de alma", 1, true) or name:find("fuego de las almas", 1, true)
	local isConflag = name:find("conflagrate", 1, true) or name:find("conflagrar", 1, true) or name:find("conflagracion", 1, true)
	-- Nightfall: Forever lights Shadow Bolt, not the Shadow Trance buff id.
	if db.talents[17941] ~= nil or db.talents["17941"] ~= nil then
		if isBolt then
			return db.talents[17941] ~= nil and 17941 or "17941"
		end
		-- Only Shadow Trance configured: any sealed glow is Nightfall.
		if LockRemindersSecret(spellID) then
			local count = 0
			for _ in pairs(db.talents) do
				count = count + 1
			end
			if count == 1 then
				return db.talents[17941] ~= nil and 17941 or "17941"
			end
		end
	end
	-- Backlash: Incinerate / Shadow Bolt glow.
	if db.talents[34936] ~= nil or db.talents["34936"] ~= nil then
		if isIncinerate or isBolt then
			return db.talents[34936] ~= nil and 34936 or "34936"
		end
	end
	-- Decimation: Soul Fire glow / instant.
	if db.talents[440873] ~= nil or db.talents["440873"] ~= nil then
		if isSoulFire then
			return db.talents[440873] ~= nil and 440873 or "440873"
		end
	end
	-- Conflagrate ready glow.
	if isConflag then
		if db.talents[1293817] ~= nil or db.talents["1293817"] ~= nil then
			return db.talents[1293817] ~= nil and 1293817 or "1293817"
		end
		if db.talents[17962] ~= nil or db.talents["17962"] ~= nil then
			return db.talents[17962] ~= nil and 17962 or "17962"
		end
	end
	return nil
end

function LockRemindersNoteTalentGlow(spellID, show)
	local key = LockRemindersTalentFromGlow(spellID)
	if not key then
		return false
	end
	if show then
		LockRemindersStampBuff(key)
		return TriggerTalent(key, SpellName(key)) and true or false
	end
	if talentFrame and talentFrame.hold and (talentFrame.spellID == key or tostring(talentFrame.spellID) == tostring(key)) then
		talentFrame.hold = false
		LockRemindersFadeTalent(key)
	elseif LockRemindersTalentAlertShowing(key) then
		LockRemindersFadeTalent(key)
	end
	if talentSeen then
		talentSeen[key] = false
	end
	return true
end

function LockRemindersReadTalentChat(line)
	if type(line) ~= "string" or line == "" or not db or type(db.talents) ~= "table" or not next(db.talents) then
		return
	end
	local gain = line:match("^You gain ([^%.%!]+)")
		or line:match(" gains ([^%.%!]+)%.?$")
		or line:match("^You acquire ([^%.%!]+)")
		or line:match(" receives ([^%.%!]+)%.?$")
	if not gain then
		return
	end
	gain = gain:gsub("%s*%b()%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
	local key = LockRemindersTalentKeyFromName(gain)
	if not key then
		return
	end
	LockRemindersStampBuff(key)
	LockRemindersCastNames = LockRemindersCastNames or {}
	local aliases = LockRemindersTalentAliasNames(key)
	local now = GetTime()
	for index = 1, #aliases do
		LockRemindersCastNames[aliases[index]] = now
	end
	pcall(TriggerTalent, key, gain)
end

function LockRemindersFindTalentBuff(spellID)
	if not spellID or not db or type(db.talents) ~= "table" then
		return false
	end
	local saved = TalentKey(spellID) or spellID
	local aliases = SpellAliases(tonumber(spellID) or spellID)
	-- Same path Demon Skin uses: sealed aura object still means "present".
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		for index = 1, #aliases do
			local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, aliases[index])
			if ok and aura ~= nil and aura ~= false then
				return true
			end
		end
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
		for index = 1, #aliases do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", aliases[index], "HELPFUL")
			if ok and aura ~= nil and aura ~= false then
				return true
			end
		end
	end
	-- Classic WeakAura style: find by name (Forever may remap the buff id).
	local names = {}
	local function addName(value)
		if type(value) ~= "string" or value == "" then
			return
		end
		names[#names + 1] = value
	end
	addName(SpellDisplayName(saved))
	addName(SpellName(saved))
	local sid = tonumber(saved)
	if sid == 17941 or sid == 18094 or sid == 18095 then
		addName("Shadow Trance")
		addName("Nightfall")
		addName("Trance de las Sombras")
		addName("Anochecer")
		addName("Caida de la Noche")
		addName("Caída de la Noche")
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		for index = 1, #names do
			local ok, found, icon = pcall(AuraUtil.FindAuraByName, names[index], "player", "HELPFUL")
			if ok and found ~= nil and found ~= false then
				return true
			end
			if ok and icon ~= nil and not LockRemindersSecret(icon) and LockRemindersIconsMatch(icon, SpellIcon(saved)) then
				return true
			end
		end
	end
	-- Classic ShadowTranceAlert: match buff texture even when name/id are sealed.
	local wantIcon = SpellIcon(saved)
	local wantPath = "Interface\\Icons\\Spell_Shadow_Twilight"
	if type(UnitBuff) == "function" then
		for index = 1, 40 do
			local packed = { pcall(UnitBuff, "player", index) }
			if not packed[1] then
				break
			end
			local name = packed[2]
			if name == nil or name == false then
				if not (issecretvalue and issecretvalue(name)) then
					break
				end
			end
			for nameIndex = 1, #names do
				if type(name) == "string" and not LockRemindersSecret(name) then
					if Normalize(name) == Normalize(names[nameIndex]) or (LockRemindersTalentNameMatch and LockRemindersTalentNameMatch(name, names[nameIndex])) then
						return true
					end
				end
			end
			for slot = 3, #packed do
				local value = packed[slot]
				if value ~= nil and not LockRemindersSecret(value) then
					if LockRemindersIconsMatch(value, wantIcon) or LockRemindersIconsMatch(value, wantPath) then
						return true
					end
					local numeric = tonumber(value)
					if numeric then
						for aliasIndex = 1, #aliases do
							if numeric == aliases[aliasIndex] then
								return true
							end
						end
					end
				end
			end
		end
	end
	if type(GetPlayerBuffTexture) == "function" and type(GetPlayerBuff) == "function" then
		for index = 0, 40 do
			local okBuff, buff = pcall(GetPlayerBuff, index, "HELPFUL")
			if okBuff and buff and buff ~= 0 then
				local okTex, texture = pcall(GetPlayerBuffTexture, buff)
				if okTex and texture and not LockRemindersSecret(texture) then
					if LockRemindersIconsMatch(texture, wantIcon) or LockRemindersIconsMatch(texture, wantPath) then
						return true
					end
				end
			end
		end
	end
	return false
end

function WatchTalents(prime)
	if not db or type(db.talents) ~= "table" or not next(db.talents) then
		return
	end
	-- WeakAura-style: one light pass. No nested aura scans (those hit the script time limit).
	local present = {}
	local function mark(key)
		if key == nil then
			return
		end
		present[key] = true
		present[tostring(key)] = true
		local numeric = tonumber(key)
		if numeric then
			present[numeric] = true
		end
	end
	for spellID in pairs(db.talents) do
		local id = tonumber(spellID) or spellID
		local aliases = SpellAliases(id)
		if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
			for index = 1, #aliases do
				local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, aliases[index])
				if ok and aura ~= nil and aura ~= false then
					mark(spellID)
					break
				end
			end
		end
		if not present[spellID] and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
			for index = 1, #aliases do
				local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", aliases[index], "HELPFUL")
				if ok and aura ~= nil and aura ~= false then
					mark(spellID)
					break
				end
			end
		end
		if not present[spellID] and LockRemindersFindTalentBuff(spellID) then
			mark(spellID)
		end
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
			if not ok or aura == nil or aura == false then
				break
			end
			local key = LockRemindersMatchTalentAura(aura)
			if key then
				mark(key)
				if not prime then
					pcall(LockRemindersNoteTalentAura, aura)
				end
			end
		end
	end
	local clock = GetTime()
	local now = {}
	for spellID in pairs(db.talents) do
		local has = present[spellID] and true or false
		local nightfall = spellID == 17941 or tostring(spellID) == "17941"
		local backlash = LockRemindersTalentIsBacklash(spellID)
		local decimation = LockRemindersTalentIsDecimation(spellID)
		local conflag = LockRemindersTalentIsConflagrate(spellID)
		-- Nightfall with cast-time tracking: trust cast time, not a 12s latch.
		if nightfall and LockRemindersSBCastBase and LockRemindersNightfallFromCastTime() then
			has = true
			mark(spellID)
		elseif backlash and LockRemindersIncinerateCastBase and LockRemindersBacklashFromCastTime() then
			has = true
			mark(spellID)
		elseif decimation and (LockRemindersDecimationFromCastTime() or LockRemindersFindTalentBuff(spellID)) then
			has = true
			mark(spellID)
		elseif conflag and LockRemindersConflagrateReady() then
			has = true
			mark(spellID)
		elseif not has then
			local recent = talentRecent[spellID] or talentRecent[tostring(spellID)] or talentRecent[tonumber(spellID)]
			if recent and clock - recent < 1.5 then
				has = true
				mark(spellID)
			end
		end
		if nightfall and LockRemindersSBCastBase and not LockRemindersNightfallFromCastTime() then
			has = false
		end
		if backlash and LockRemindersIncinerateCastBase and not LockRemindersBacklashFromCastTime() then
			has = false
		end
		if decimation and LockRemindersSoulFireCastBase and not LockRemindersDecimationFromCastTime() and not LockRemindersFindTalentBuff(spellID) then
			has = false
		end
		if conflag and not LockRemindersConflagrateReady() then
			has = false
		end
		if has then
			now[spellID] = true
			if not prime and not talentMoving and not (LockRemindersTalentPreviewUntil and GetTime() < LockRemindersTalentPreviewUntil) and not LockRemindersTalentAlertShowing(spellID) then
				LockRemindersStampBuff(spellID)
				pcall(TriggerTalent, spellID)
			end
		else
			now[spellID] = false
			if not prime and not talentMoving and not (LockRemindersTalentPreviewUntil and GetTime() < LockRemindersTalentPreviewUntil) and LockRemindersTalentAlertShowing(spellID) then
				pcall(LockRemindersClearTalentProc, spellID)
			end
		end
	end
	talentSeen = now
end

function LockRemindersIconKey(icon)
	if icon == nil or LockRemindersSecret(icon) then
		return nil
	end
	local text = tostring(icon):lower():gsub("\\", "/")
	text = text:gsub("%.blp$", ""):gsub("%.tga$", "")
	local file = text:match("interface/icons/(.+)$") or text:match("/icons/(.+)$")
	if file then
		return file
	end
	if GetFileIDFromPath and type(icon) == "string" then
		local ok, fileID = pcall(GetFileIDFromPath, icon)
		if ok and fileID and not LockRemindersSecret(fileID) then
			return tostring(fileID)
		end
	end
	return text
end

function LockRemindersIconsMatch(left, right)
	local a = LockRemindersIconKey(left)
	local b = LockRemindersIconKey(right)
	if not a or not b then
		return false
	end
	if a == b then
		return true
	end
	return a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

function LockRemindersMatchTalentAura(data, texture)
	if not db or type(db.talents) ~= "table" or not next(db.talents) then
		return nil
	end
	local auraID, auraName, auraIcon, auraDuration, auraHelpful
	if data ~= nil then
		pcall(function()
			auraID = data.spellId or data.spellID
			auraName = data.name
			auraIcon = data.icon
			auraDuration = data.duration
			auraHelpful = data.isHelpful
		end)
	end
	if (auraIcon == nil or LockRemindersSecret(auraIcon)) and texture ~= nil and not LockRemindersSecret(texture) then
		auraIcon = texture
	end
	local nightfallKey
	if db.talents[17941] ~= nil then
		nightfallKey = 17941
	elseif db.talents["17941"] ~= nil then
		nightfallKey = "17941"
	end
	local function nightfallIcon(icon)
		if icon == nil or LockRemindersSecret(icon) then
			return false
		end
		if nightfallKey and LockRemindersIconsMatch(icon, SpellIcon(nightfallKey)) then
			return true
		end
		local text = LockRemindersIconKey(icon) or ""
		if text == "136213" or text == "136214" or text == "136216" or text == "136223" then
			return true
		end
		if text:find("spell_shadow_twilight", 1, true) then
			return true
		end
		if text:find("spell_shadow_shadowworddominate", 1, true) then
			return true
		end
		if text:find("spell_shadow_siphonmana", 1, true) then
			return true
		end
		return text:find("ability_warlock_shadowflame", 1, true) and true or false
	end
	if auraID ~= nil and not LockRemindersSecret(auraID) then
		local key = TalentKey(auraID)
		if key then
			return key
		end
		if LockRemindersSameSpell then
			for saved in pairs(db.talents) do
				local sid = tonumber(saved)
				if sid then
					local aliases = SpellAliases(sid)
					for index = 1, #aliases do
						if LockRemindersSameSpell(auraID, aliases[index]) then
							return saved
						end
					end
				end
			end
		end
	end
	if type(auraName) == "string" and auraName ~= "" and not LockRemindersSecret(auraName) then
		local key = LockRemindersTalentKeyFromName(auraName)
		if key then
			return key
		end
	end
	if auraIcon ~= nil and not LockRemindersSecret(auraIcon) then
		for saved in pairs(db.talents) do
			local sid = tonumber(saved) or saved
			if LockRemindersIconsMatch(auraIcon, SpellIcon(sid)) then
				return saved
			end
		end
		if nightfallKey and nightfallIcon(auraIcon) then
			return nightfallKey
		end
	end
	-- Forever seals short talent procs ("buff hidden by the game" in OneForAll).
	-- Duration may read as 0 / garbage while the icon still paints — if Nightfall is the
	-- only configured proc, any sealed helpful aura is treated as Shadow Trance.
	if nightfallKey and data ~= nil and auraHelpful ~= false then
		local sealed = LockRemindersSecret(auraID)
			or LockRemindersSecret(auraName)
			or LockRemindersSecret(auraDuration)
			or LockRemindersSecret(auraIcon)
		local count = 0
		for _ in pairs(db.talents) do
			count = count + 1
		end
		local short = LockRemindersSecret(auraDuration)
			or (type(auraDuration) == "number" and auraDuration > 0 and auraDuration <= 15)
			or (auraDuration == nil and sealed)
			or (type(auraDuration) == "number" and auraDuration == 0 and sealed)
		if sealed and (count == 1 or short or nightfallIcon(auraIcon)) then
			return nightfallKey
		end
	end
	return nil
end

function LockRemindersNoteTalentAura(data, texture)
	local key = LockRemindersMatchTalentAura(data, texture)
	if not key then
		return false
	end
	LockRemindersStampBuff(key)
	if LockRemindersTalentAlertShowing(key) then
		return true
	end
	return TriggerTalent(key) and true or false
end

function LockRemindersSpellIsOverlayed(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return false
	end
	local fn = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed or IsSpellOverlayed
	if type(fn) ~= "function" then
		return false
	end
	local ok, on = pcall(fn, spellID)
	if not ok or on == nil or LockRemindersSecret(on) then
		return false
	end
	return on and true or false
end

-- Shadowflare's Forever path: buffs are hidden in combat, but Shadow Bolt's cast time
-- drops to 0 while Shadow Trance is up. Learn the normal cast time first, then trust a 0.
function LockRemindersShadowBoltCastTime()
	local ranks = {
		47809, 47808, 27209, 25307, 11661, 11660, 11659, 7641, 1106, 1088, 705, 695, 686,
	}
	local function known(id)
		if IsPlayerSpell then
			local ok, value = pcall(IsPlayerSpell, id)
			if ok and value then
				return true
			end
		end
		if IsSpellKnown then
			local ok, value = pcall(IsSpellKnown, id)
			if ok and value then
				return true
			end
		end
		return false
	end
	local function castMs(id)
		if GetSpellInfo then
			local ok, _, _, _, castTime = pcall(GetSpellInfo, id)
			if ok and castTime ~= nil and not LockRemindersSecret(castTime) then
				castTime = tonumber(castTime)
				if castTime then
					return castTime
				end
			end
		end
		if C_Spell and C_Spell.GetSpellInfo then
			local ok, info = pcall(C_Spell.GetSpellInfo, id)
			if ok and type(info) == "table" and info.castTime ~= nil and not LockRemindersSecret(info.castTime) then
				return tonumber(info.castTime)
			end
		end
	end
	for index = 1, #ranks do
		local id = ranks[index]
		if known(id) then
			local ct = castMs(id)
			if ct ~= nil then
				return ct, id
			end
		end
	end
	for index = 1, #ranks do
		local ct = castMs(ranks[index])
		if ct ~= nil then
			return ct, ranks[index]
		end
	end
end

function LockRemindersSpellCastMs(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return nil
	end
	if GetSpellInfo then
		local ok, _, _, _, castTime = pcall(GetSpellInfo, spellID)
		if ok and castTime ~= nil and not LockRemindersSecret(castTime) then
			castTime = tonumber(castTime)
			if castTime then
				return castTime
			end
		end
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		if ok and type(info) == "table" and info.castTime ~= nil and not LockRemindersSecret(info.castTime) then
			return tonumber(info.castTime)
		end
	end
	return nil
end

function LockRemindersNightfallFromCastTime()
	local ct = LockRemindersShadowBoltCastTime()
	if ct == nil then
		return false
	end
	if ct > 0 then
		LockRemindersSBCastBase = ct
		return false
	end
	-- Instant only after a normal cast time was seen (Shadowflare CheckInstant).
	return LockRemindersSBCastBase ~= nil
end

function LockRemindersBacklashFromCastTime()
	local ranks = { 29722, 32231, 47837, 47838 }
	local ct
	for index = 1, #ranks do
		local ms = LockRemindersSpellCastMs(ranks[index])
		if ms ~= nil then
			ct = ms
			break
		end
	end
	if ct == nil then
		return false
	end
	if ct > 0 then
		LockRemindersIncinerateCastBase = ct
		return false
	end
	return LockRemindersIncinerateCastBase ~= nil
end

function LockRemindersDecimationFromCastTime()
	local ranks = { 6353, 17924, 27211, 30545, 47824, 47825, 440870 }
	local ct
	for index = 1, #ranks do
		local ms = LockRemindersSpellCastMs(ranks[index])
		if ms ~= nil then
			ct = ms
			break
		end
	end
	if ct == nil then
		return false
	end
	if ct > 0 then
		LockRemindersSoulFireCastBase = ct
		return false
	end
	return LockRemindersSoulFireCastBase ~= nil
end

function LockRemindersConflagrateReady()
	local ids = { 1293817, 17962 }
	for index = 1, #ids do
		local id = ids[index]
		if LockRemindersSpellIsOverlayed(id) then
			return true
		end
		if C_Spell and C_Spell.IsSpellUsable then
			local ok, usable = pcall(C_Spell.IsSpellUsable, id)
			if ok and usable == true and not LockRemindersSecret(usable) then
				return true
			end
		end
		if IsUsableSpell then
			local ok, usable = pcall(IsUsableSpell, id)
			if ok and usable == true and not LockRemindersSecret(usable) then
				return true
			end
		end
	end
	return false
end

function LockRemindersTalentIsConflagrate(spellID)
	spellID = tonumber(spellID) or spellID
	return spellID == 1293817 or spellID == 17962 or tostring(spellID) == "1293817" or tostring(spellID) == "17962"
end

function LockRemindersTalentIsDecimation(spellID)
	spellID = tonumber(spellID) or spellID
	return spellID == 440873 or spellID == 440870 or tostring(spellID) == "440873" or tostring(spellID) == "440870"
end

function LockRemindersTalentIsBacklash(spellID)
	spellID = tonumber(spellID) or spellID
	return spellID == 34936 or tostring(spellID) == "34936"
end

function LockRemindersPollTalentOverlay()
	if not db or type(db.talents) ~= "table" or not next(db.talents) then
		return
	end
	local nightfallKey
	if db.talents[17941] ~= nil then
		nightfallKey = 17941
	elseif db.talents["17941"] ~= nil then
		nightfallKey = "17941"
	end
	local bolts = {
		[686] = true, [695] = true, [705] = true, [1088] = true, [1106] = true,
		[7641] = true, [11659] = true, [11660] = true, [11661] = true,
		[25307] = true, [27209] = true, [47808] = true, [47809] = true,
	}
	-- Forever: Shadowflare finds Trance via Shadow Bolt cast time → 0 in combat.
	if talentMoving or (LockRemindersTalentPreviewUntil and GetTime() < LockRemindersTalentPreviewUntil) then
		return
	end
	if nightfallKey then
		local instant = LockRemindersNightfallFromCastTime()
		local showing = LockRemindersTalentAlertShowing(nightfallKey)
		if instant then
			if not showing then
				LockRemindersStampBuff(nightfallKey)
				pcall(TriggerTalent, nightfallKey)
			end
		elseif showing and LockRemindersSBCastBase then
			local ornament = LockRemindersTalentOrnament
			if not (ornament and ornament.fading) then
				pcall(LockRemindersClearTalentProc, nightfallKey)
			end
		elseif not LockRemindersSBCastBase then
			if LockRemindersFindTalentBuff(nightfallKey) then
				LockRemindersStampBuff(nightfallKey)
				pcall(TriggerTalent, nightfallKey)
			else
				for boltID in pairs(bolts) do
					if LockRemindersSpellIsOverlayed(boltID) then
						LockRemindersStampBuff(nightfallKey)
						pcall(TriggerTalent, nightfallKey)
						break
					end
				end
			end
		end
	end
	for saved in pairs(db.talents) do
		if saved == nightfallKey or saved == 17941 or tostring(saved) == "17941" then
			-- handled above
		elseif LockRemindersTalentIsBacklash(saved) then
			local showing = LockRemindersTalentAlertShowing(saved)
			local instant = LockRemindersBacklashFromCastTime()
			if instant then
				if not showing then
					LockRemindersStampBuff(saved)
					pcall(TriggerTalent, saved)
				end
			elseif showing and LockRemindersIncinerateCastBase then
				pcall(LockRemindersClearTalentProc, saved)
			elseif not showing and (LockRemindersFindTalentBuff(saved) or LockRemindersSpellIsOverlayed(34936)) then
				LockRemindersStampBuff(saved)
				pcall(TriggerTalent, saved)
			end
		elseif LockRemindersTalentIsDecimation(saved) then
			local showing = LockRemindersTalentAlertShowing(saved)
			local instant = LockRemindersDecimationFromCastTime()
			local buffed = LockRemindersFindTalentBuff(saved)
			if instant or buffed then
				if not showing then
					LockRemindersStampBuff(saved)
					pcall(TriggerTalent, saved)
				end
			elseif showing and LockRemindersSoulFireCastBase and not buffed then
				pcall(LockRemindersClearTalentProc, saved)
			end
		elseif LockRemindersTalentIsConflagrate(saved) then
			local showing = LockRemindersTalentAlertShowing(saved)
			local ready = LockRemindersConflagrateReady()
			if ready then
				if not showing then
					LockRemindersStampBuff(saved)
					pcall(TriggerTalent, saved)
				end
			elseif showing then
				pcall(LockRemindersClearTalentProc, saved)
			end
		elseif not LockRemindersTalentAlertShowing(saved) then
			if LockRemindersFindTalentBuff(saved) then
				LockRemindersStampBuff(saved)
				pcall(TriggerTalent, saved)
			end
			local sid = tonumber(saved)
			if sid and LockRemindersSpellIsOverlayed(sid) then
				LockRemindersStampBuff(saved)
				pcall(TriggerTalent, saved)
			end
		end
	end
end

function LockRemindersOnlyNightfall()
	if not db or type(db.talents) ~= "table" then
		return nil
	end
	if db.talents[17941] == nil and db.talents["17941"] == nil then
		return nil
	end
	local count = 0
	for _ in pairs(db.talents) do
		count = count + 1
	end
	if count ~= 1 then
		return nil
	end
	return db.talents[17941] ~= nil and 17941 or "17941"
end

function LockRemindersHookBuffTexture(tex)
	if not tex or tex.lrTalentHook or type(tex.SetTexture) ~= "function" then
		return
	end
	tex.lrTalentHook = true
	hooksecurefunc(tex, "SetTexture", function(_, asset)
		if asset == nil then
			return
		end
		-- Forever can seal the file id and still paint the buff on the bar.
		if LockRemindersSecret(asset) then
			local key = LockRemindersOnlyNightfall()
			if key then
				LockRemindersStampBuff(key)
				pcall(TriggerTalent, key)
			end
			return
		end
		pcall(LockRemindersNoteTalentAura, nil, asset)
	end)
end

function LockRemindersHookElvUIAuras()
	if LockRemindersElvAuraHooked then
		return
	end
	local ok, E = pcall(function()
		return ElvUI and ElvUI[1]
	end)
	if not ok or not E or not E.GetModule then
		return
	end
	local got, A = pcall(E.GetModule, E, "Auras")
	if not got or not A or type(A.UpdateAura) ~= "function" then
		return
	end
	LockRemindersElvAuraHooked = true
	hooksecurefunc(A, "UpdateAura", function(_, button)
		if not button or not db or type(db.talents) ~= "table" then
			return
		end
		if button.filter and button.filter ~= "HELPFUL" then
			return
		end
		local texture
		if button.texture and button.texture.GetTexture then
			texture = button.texture:GetTexture()
		end
		LockRemindersHookBuffTexture(button.texture)
		local noted = LockRemindersNoteTalentAura(button.aura or button.auraInfo or button.data, texture)
		if noted then
			return
		end
		local key = LockRemindersOnlyNightfall()
		if not key then
			return
		end
		local dur = button.duration
		local sealedDur = LockRemindersSecret(dur)
		local short = sealedDur or (type(dur) == "number" and dur > 0 and dur <= 15) or (type(dur) == "number" and dur == 0 and LockRemindersSecret(texture))
		local sealedTex = LockRemindersSecret(texture)
		if short or sealedTex or (button.aura and (LockRemindersSecret(button.aura.spellId) or LockRemindersSecret(button.aura.name))) then
			LockRemindersStampBuff(key)
			pcall(TriggerTalent, key)
		end
	end)
end

function LockRemindersScanBuffButtons()
	if not db or type(db.talents) ~= "table" or not next(db.talents) then
		return
	end
	local function readButton(button)
		if not button then
			return
		end
		local shown = true
		if button.IsShown then
			shown = button:IsShown()
		end
		if not shown then
			return
		end
		local icon = button.texture or button.Icon or button.icon
		if type(icon) == "table" then
			LockRemindersHookBuffTexture(icon)
			local texture
			if icon.GetTexture then
				texture = icon:GetTexture()
			end
			pcall(LockRemindersNoteTalentAura, button.auraInfo or button.aura or button.data, texture)
			return
		end
		-- Fallback only when the button has no .texture field.
		if button.GetRegions then
			local regions = { button:GetRegions() }
			for index = 1, #regions do
				local region = regions[index]
				if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.GetTexture then
					LockRemindersHookBuffTexture(region)
					local texture = region:GetTexture()
					if texture ~= nil and not LockRemindersSecret(texture) then
						pcall(LockRemindersNoteTalentAura, nil, texture)
					end
				end
			end
		end
	end
	local function readFrame(frame, depth)
		if not frame or not frame.GetChildren then
			return
		end
		depth = depth or 0
		if depth > 2 then
			return
		end
		local children = { frame:GetChildren() }
		for index = 1, #children do
			readButton(children[index])
			if depth < 2 then
				readFrame(children[index], depth + 1)
			end
		end
	end
	for index = 1, 40 do
		readButton(_G["BuffButton" .. index])
		readButton(_G["AuraButton" .. index])
		readButton(_G["TempEnchant" .. index])
	end
	local frame = _G.BuffFrame
	if frame and frame.auraContainer then
		readFrame(frame.auraContainer, 0)
	else
		readFrame(frame, 0)
	end
	-- ElvUI kills BuffFrame; read its header icons (texture paths stay readable).
	readFrame(_G.ElvUIPlayerBuffs, 0)
	readFrame(_G.ElvUIPlayerBuffs and _G.ElvUIPlayerBuffs.auraHeader, 0)
end

function LockRemindersQueueTalentScan()
	pcall(LockRemindersPollTalentOverlay)
	-- One delayed buff walk is enough; triple scans were burning memory.
	if C_Timer and C_Timer.After then
		C_Timer.After(0.15, function()
			pcall(LockRemindersScanBuffButtons)
			pcall(LockRemindersPollTalentOverlay)
		end)
	else
		pcall(LockRemindersScanBuffButtons)
	end
end

function LockRemindersStartTalentWatch()
	-- Cast-time poll is cheap. Buff-button walks allocate; keep them rare.
	pcall(LockRemindersHookElvUIAuras)
	if LockRemindersTalentTicker then
		LockRemindersTalentTicker:Cancel()
		LockRemindersTalentTicker = nil
	end
	if not C_Timer or not C_Timer.NewTicker then
		return
	end
	LockRemindersTalentTicker = C_Timer.NewTicker(0.4, function()
		if not db or type(db.talents) ~= "table" or not next(db.talents) then
			return
		end
		pcall(LockRemindersPollTalentOverlay)
		-- Fallback scan only before Shadow Bolt cast-time baseline exists.
		if not LockRemindersSBCastBase then
			local now = GetTime()
			if not LockRemindersTalentScanAt or now - LockRemindersTalentScanAt >= 2 then
				LockRemindersTalentScanAt = now
				pcall(LockRemindersScanBuffButtons)
			end
		end
	end)
end

function LockRemindersDumpProcs()
	Print("Proc dump (while Shadow Trance is up):")
	local key = LockRemindersOnlyNightfall() or 17941
	local ct, bolt = LockRemindersShadowBoltCastTime()
	Print("Shadow Bolt castTime=" .. tostring(ct) .. "ms id=" .. tostring(bolt) .. " base=" .. tostring(LockRemindersSBCastBase) .. " instant=" .. tostring(LockRemindersNightfallFromCastTime()))
	Print("FindTalentBuff: " .. tostring(LockRemindersFindTalentBuff(key)))
	if AuraUtil and AuraUtil.FindAuraByName then
		local names = { "Shadow Trance", "Nightfall", "Trance de las Sombras", "Anochecer" }
		for index = 1, #names do
			local ok, found, icon = pcall(AuraUtil.FindAuraByName, names[index], "player", "HELPFUL")
			Print("FindAura " .. names[index] .. ": ok=" .. tostring(ok) .. " found=" .. tostring(found) .. (LockRemindersSecret(found) and "(secret)" or "") .. " icon=" .. tostring(icon))
		end
	end
	for _, id in ipairs({ 17941, 18094, 18095 }) do
		local ok, aura = false, nil
		if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
			ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		end
		Print("GetPlayerAuraBySpellID " .. id .. ": " .. tostring(ok and aura ~= nil and aura ~= false) .. (aura ~= nil and LockRemindersSecret(aura) and " (sealed obj)" or ""))
	end
	local bolts = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307, 27209 }
	local overlayed = false
	for index = 1, #bolts do
		if LockRemindersSpellIsOverlayed(bolts[index]) then
			overlayed = true
			Print("Overlayed bolt: " .. bolts[index])
		end
	end
	if not overlayed then
		Print("No Shadow Bolt overlay via IsSpellOverlayed.")
	end
	local found = 0
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
			if not ok or aura == nil or aura == false then
				break
			end
			found = found + 1
			local id, name, icon, dur
			pcall(function()
				id = aura.spellId or aura.spellID
				name = aura.name
				icon = aura.icon
				dur = aura.duration
			end)
			local bits = {
				"#" .. index,
				"id=" .. tostring(id) .. (LockRemindersSecret(id) and "(secret)" or ""),
				"name=" .. tostring(name) .. (LockRemindersSecret(name) and "(secret)" or ""),
				"icon=" .. tostring(icon) .. (LockRemindersSecret(icon) and "(secret)" or ""),
				"dur=" .. tostring(dur) .. (LockRemindersSecret(dur) and "(secret)" or ""),
				"match=" .. tostring(LockRemindersMatchTalentAura(aura)),
			}
			Print(table.concat(bits, " "))
		end
	end
	Print("Readable aura slots: " .. found)
	local header = _G.ElvUIPlayerBuffs
	if header and header.GetChildren then
		local children = { header:GetChildren() }
		local shown = 0
		for index = 1, #children do
			local button = children[index]
			if button and button.IsShown and button:IsShown() then
				shown = shown + 1
				local tex = button.texture or button.icon or button.Icon
				local asset = tex and tex.GetTexture and tex:GetTexture()
				Print("ElvBuff" .. shown .. " icon=" .. tostring(asset) .. (LockRemindersSecret(asset) and "(secret)" or "") .. " dur=" .. tostring(button.duration) .. (LockRemindersSecret(button.duration) and "(secret)" or "") .. " match=" .. tostring(LockRemindersMatchTalentAura(button.aura, asset)))
			end
		end
		Print("ElvUI buff buttons shown: " .. shown)
	else
		Print("ElvUIPlayerBuffs not found.")
	end
	Print("ElvUI UpdateAura hooked: " .. tostring(LockRemindersElvAuraHooked and true or false))
	Print("/lr proc still previews the animation.")
end

function LockRemindersLayoutItemAlert()
	if not foodFrame or not db then
		return
	end
	local size = tonumber(db.foodSize) or 48
	if size < 24 then
		size = 24
	elseif size > 96 then
		size = 96
	end
	db.foodSize = size
	local foodOn = foodFrame.showFood == true
	local stoneOn = foodFrame.showStone == true
	local thick = LockRemindersGlowThick(size, "foodGlowSize")
	local cell = size + thick * 2
	local red, green, blue = LockRemindersReadGlow("foodGlow", 1, 0.82, 0.35)
	local function place(icon, glow, on, index, cols, pad)
		if not icon then
			return
		end
		icon:SetShown(on)
		if glow then
			glow:SetShown(on)
			if on and glow.ag and not glow.ag:IsPlaying() then
				glow.ag:Play()
			elseif glow.ag and not on then
				glow.ag:Stop()
			end
		end
		if not on then
			if glow and glow.plate then
				glow.plate:Hide()
			end
			return
		end
		local col = (index - 1) % cols
		local line = math.floor((index - 1) / cols)
		icon:ClearAllPoints()
		icon:SetSize(size, size)
		icon:SetPoint("TOPLEFT", foodFrame, "TOPLEFT", pad + col * (cell + pad) + thick, -(pad + line * (cell + pad) + thick))
		LockRemindersFitEvenGlow(glow, icon, size, "foodGlowSize")
		LockRemindersTintEvenGlow(glow, red, green, blue)
	end
	local slots = {}
	if foodOn then
		slots[#slots + 1] = { key = "food", icon = foodFrame.icon, glow = foodFrame.glow, order = 1 }
	end
	if stoneOn then
		slots[#slots + 1] = { key = "healthstone", icon = foodFrame.stone, glow = foodFrame.stoneGlow, order = 2 }
	end
	local rank = {}
	if type(db.itemOrder) == "table" then
		for index = 1, #db.itemOrder do
			rank[db.itemOrder[index]] = index
		end
	end
	table.sort(slots, function(a, b)
		local left = rank[a.key] or 99
		local right = rank[b.key] or 99
		if left == right then
			return a.order < b.order
		end
		return left < right
	end)
	local pad = LockRemindersFoodPad()
	local cols = LockRemindersFoodColumns()
	local count = #slots
	if cols < 1 or cols > count then
		cols = math.max(count, 1)
	end
	local lines = math.max(1, math.ceil(count / cols))
	foodFrame:SetSize(pad * 2 + cols * cell + math.max(0, cols - 1) * pad, pad * 2 + lines * cell + math.max(0, lines - 1) * pad)
	local shown = {}
	for index = 1, #slots do
		place(slots[index].icon, slots[index].glow, true, index, cols, pad)
		shown[slots[index].key] = true
	end
	if not shown.food then
		place(foodFrame.icon, foodFrame.glow, false)
	end
	if not shown.healthstone then
		place(foodFrame.stone, foodFrame.stoneGlow, false)
	end
	if foodFrame.foodHit then
		foodFrame.foodHit:ClearAllPoints()
		foodFrame.foodHit:SetAllPoints(foodFrame.icon)
		foodFrame.foodHit:SetShown(LockRemindersItemArranging and foodFrame.icon:IsShown())
		foodFrame.foodHit:EnableMouse(LockRemindersItemArranging and foodFrame.icon:IsShown() and true or false)
	end
	if foodFrame.stoneHit then
		foodFrame.stoneHit:ClearAllPoints()
		foodFrame.stoneHit:SetAllPoints(foodFrame.stone)
		foodFrame.stoneHit:SetShown(LockRemindersItemArranging and foodFrame.stone:IsShown())
		foodFrame.stoneHit:EnableMouse(LockRemindersItemArranging and foodFrame.stone:IsShown() and true or false)
	end
	LockRemindersApplyFoodChrome()
	LockRemindersStyleFoodIcon()
end

function ApplyFoodLook()
	LockRemindersLayoutItemAlert()
end

function ApplyFoodPoint()
	if not foodFrame or not db then
		return
	end
	if type(db.foodPoint) ~= "table" then
		db.foodPoint = { "CENTER", "CENTER", 0, 80 }
	end
	foodFrame:ClearAllPoints()
	foodFrame:SetPoint(db.foodPoint[1], UIParent, db.foodPoint[2], db.foodPoint[3], db.foodPoint[4])
end

function SaveFoodPoint()
	if not foodFrame or not db then
		return
	end
	local point, _, relative, x, y = foodFrame:GetPoint()
	db.foodPoint = { point, relative, x, y }
end

function ChangeFoodSize(delta)
	if not db then
		return
	end
	db.foodSize = (tonumber(db.foodSize) or 48) + delta
	ApplyFoodLook()
	if foodFrame and foodFrame.moving then
		foodFrame:Show()
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ShowFoodPreview(show)
	if not foodFrame then
		return
	end
	foodFrame.moving = show and true or false
	foodFrame.foodNumber = nil
	foodFrame.foodDim = false
	foodFrame.stoneDim = false
	if db then
		db.foodLocked = not foodFrame.moving
	end
	foodFrame.hint:SetShown(foodFrame.moving)
	if foodFrame.moving then
		local hasFood = false
		if type(db.foodItems) == "table" then
			for _ in pairs(db.foodItems) do
				hasFood = true
				break
			end
		end
		if not hasFood and type(db.food) == "table" then
			for _ in pairs(db.food) do
				hasFood = true
				break
			end
		end
		foodFrame.showFood = hasFood
		foodFrame.showStone = type(db.healthstone) == "table"
		if hasFood then
			local foodIcon = FoodLabel()
			foodFrame.icon:SetTexture(foodIcon or 134062)
		end
	end
	ApplyFoodLook()
	ApplyFoodPoint()
	if foodFrame.moving then
		local icon = FoodLabel()
		foodFrame.icon:SetTexture(icon)
		if foodFrame.stone then
			local stoneIcon = SpellIcon(CREATE_HEALTHSTONE)
			if stoneIcon == nil or stoneIcon == 134400 then
				stoneIcon = ItemIcon(5512) or 135230
			end
			foodFrame.stone:SetTexture(stoneIcon)
		end
		foodFrame:Show()
		foodFrame:SetAlpha(1)
		if foodFrame.glow.ag and not foodFrame.glow.ag:IsPlaying() then
			foodFrame.glow.ag:Play()
		end
	else
		RefreshFood()
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
	if LockRemindersShowItemLayout then
		LockRemindersShowItemLayout(false)
	end
end

function RefreshFood()
	if not foodFrame or not db then
		return
	end
	if foodFrame.moving and not LockRemindersItemArranging then
		foodFrame:Show()
		return
	end
	LockRemindersFoodSoon = false
	local preview = LockRemindersFoodPreview
	local previewOn = preview and preview.at and GetTime() < preview.at
	if preview and preview.at and not previewOn then
		LockRemindersFoodPreview = nil
	end
	local playing = false
	local covered = false
	local soonLeft
	local function noteSoon(left)
		if type(left) == "number" and left > 0 and left <= 15 then
			LockRemindersFoodSoon = true
			if left <= 10 and (not soonLeft or left < soonLeft) then
				soonLeft = left
			end
		end
	end
	local function consider(itemID, spellID, auraID)
		local scope = LockRemindersFoodScope(itemID, spellID)
		if not ScopeActive(scope) then
			return
		end
		if InCombatLockdown() and not scope.combat then
			return
		end
		playing = true
		auraID = tonumber(auraID)
		if auraID and auraID > 0 then
			local has = HasAura(auraID)
			if has == nil or has == true then
				covered = true
				if has == true then
					noteSoon(LockRemindersAuraLeft(auraID))
				end
			end
			return
		end
		-- Eat-food items store true: watch the Well Fed buff by name.
		-- nil means Forever hid the buff name; keep treating it as covered.
		local hasFoodBuff = LockRemindersHasWellFed()
		if hasFoodBuff == nil or hasFoodBuff == true then
			covered = true
			if hasFoodBuff == true then
				noteSoon(LockRemindersWellFedLeft())
			else
				noteSoon(LockRemindersCachedWellFedLeft())
			end
		end
	end
	if type(db.food) == "table" then
		for spellID in pairs(db.food) do
			consider(nil, spellID, spellID)
		end
	end
	if type(db.foodItems) == "table" then
		for itemID, value in pairs(db.foodItems) do
			consider(itemID, nil, value)
		end
	end
	if Blocked() then
		playing = false
		covered = false
		soonLeft = nil
		LockRemindersFoodSoon = false
	end
	local foodMissing = playing and not covered
	local foodSoon = type(soonLeft) == "number" and soonLeft > 0 and soonLeft <= 10
	local showFood = foodMissing or foodSoon or previewOn
	local number
	if previewOn then
		number = preview.left
		showFood = true
	elseif foodSoon and db.foodRemind ~= "alert" then
		number = math.ceil(soonLeft)
	end
	local stoneMissing = false
	if not Blocked() and type(db.healthstone) == "table" and LockRemindersIsWarlock() and ScopeActive(db.healthstone) then
		if not (InCombatLockdown() and not db.healthstone.combat) and not HasHealthstone() then
			stoneMissing = true
		end
	end
	local showStone = stoneMissing
	if LockRemindersItemArranging then
		local hasFood = false
		if type(db.foodItems) == "table" then
			for _ in pairs(db.foodItems) do
				hasFood = true
				break
			end
		end
		if not hasFood and type(db.food) == "table" then
			for _ in pairs(db.food) do
				hasFood = true
				break
			end
		end
		showFood = hasFood
		showStone = type(db.healthstone) == "table"
		number = nil
	end
	if not showFood and not showStone then
		foodFrame.foodNumber = nil
		foodFrame:Hide()
		if foodFrame.count then
			foodFrame.count:Hide()
		end
		return
	end
	foodFrame.showFood = showFood
	foodFrame.showStone = showStone
	foodFrame.foodNumber = number
	foodFrame.foodDim = LockRemindersItemArranging and not foodMissing and not foodSoon and not previewOn
	foodFrame.stoneDim = LockRemindersItemArranging and not stoneMissing
	if showFood then
		local foodIcon = FoodLabel()
		foodFrame.icon:SetTexture(foodIcon or 134062)
	end
	if showStone and foodFrame.stone then
		local stoneIcon = SpellIcon(CREATE_HEALTHSTONE)
		if stoneIcon == nil or stoneIcon == 134400 then
			stoneIcon = ItemIcon(5512) or 135230
		end
		foodFrame.stone:SetTexture(stoneIcon)
	end
	ApplyFoodLook()
	ApplyFoodPoint()
	foodFrame:Show()
	foodFrame:SetAlpha(1)
	LockRemindersStyleFoodIcon()
end

function LockRemindersMissIconSize()
	local size = tonumber(db and db.missSize) or 48
	if size < 32 then
		size = 32
	elseif size > 96 then
		size = 96
	end
	return size
end

LockRemindersSoundChoices = {
	{ "None", "none" },
	{ "Alarms" },
	{ "Buzz", "buzz" },
	{ "Notice", "notice" },
	{ "Blast", "blast" },
	{ "Raid", "raid" },
	{ "Spells" },
	{ "Fireball", "fire" },
	{ "Chi-Ji", "chiji" },
	{ "Zaps", "zaps" },
	{ "Whoosh", "whoosh" },
	{ "Fizzle" },
	{ "Frost", "frost" },
	{ "Holy", "holy" },
	{ "Shadow", "shadow" },
	{ "Fire", "firefizz" },
	{ "Nature", "nature" },
	{ "Interface" },
	{ "Role", "role" },
	{ "Scrap", "scrap" },
	{ "Restore", "restore" },
}

LockRemindersSoundFiles = {
	buzz = 568975,
	notice = 567450,
	blast = 566982,
	raid = 567394,
	fire = 1685538,
	chiji = 1375585,
	zaps = 4546394,
	whoosh = 4556842,
	frost = 569775,
	holy = 569772,
	shadow = 569776,
	firefizz = 569773,
	nature = 569774,
	role = 567513,
	scrap = 2173883,
	restore = 567526,
}

LockRemindersSoundKits = {
	raid = 12197,
	fire = 172796,
	chiji = 60957,
	zaps = 339197,
	whoosh = 305406,
	frost = 1425,
	holy = 1428,
	shadow = 1427,
	firefizz = 1424,
	nature = 1426,
	role = 17317,
	scrap = 169046,
	restore = 62541,
}

function LockRemindersKnownSound(id)
	return id == "none" or (LockRemindersSoundFiles and LockRemindersSoundFiles[id] ~= nil)
end

function LockRemindersZoneQuiet()
	return LockRemindersEnteredAt and GetTime() < LockRemindersEnteredAt
end

function LockRemindersSoundChannel()
	local channel = db and db.soundChannel
	if channel == "Master" or channel == "SFX" or channel == "Dialog" then
		return channel
	end
	return "Dialog"
end

function LockRemindersPlaySoundId(id, hear)
	if not hear and LockRemindersZoneQuiet() then
		return
	end
	local channel = LockRemindersSoundChannel()
	local kit = LockRemindersSoundKits and LockRemindersSoundKits[id]
	if type(kit) == "number" and PlaySound then
		local ok, handle = pcall(PlaySound, kit, channel)
		if ok and handle then
			return
		end
		if channel ~= "Master" then
			ok, handle = pcall(PlaySound, kit, "Master")
			if ok and handle then
				return
			end
		end
	end
	local file = LockRemindersSoundFiles and LockRemindersSoundFiles[id]
	if type(file) == "number" and PlaySoundFile then
		local ok = pcall(PlaySoundFile, file, channel)
		if not ok and channel ~= "Master" then
			pcall(PlaySoundFile, file, "Master")
		end
	end
end

function LockRemindersPlayMissSound()
	LockRemindersPlaySoundId(db and db.missSound or "none")
end

function LockRemindersPreviewSound(id)
	LockRemindersPlaySoundId(id, true)
end

function LockRemindersMissHold()
	local hold = tonumber(db and db.missHold) or 3
	if hold < 1 then
		hold = 1
	elseif hold > 8 then
		hold = 8
	end
	return hold
end

function LockRemindersMissTypeLabel(missType)
	if missType == "RESIST" then
		return "RESISTED"
	end
	if missType == "IMMUNE" then
		return "IMMUNE"
	end
	return "MISSED"
end

function ApplySpellMissLook()
	local frame = LockRemindersMiss.frame
	if not frame or not frame.icon or not db then
		return
	end
	local size = LockRemindersMissIconSize()
	db.missSize = size
	frame.icon:ClearAllPoints()
	frame.icon:SetPoint("LEFT", 7, 0)
	frame.icon:SetSize(size, size)
	frame.icon:SetTexCoord(0, 1, 0, 1)
	LockRemindersSmoothIcon(frame.icon)
	if frame.cooldown then
		frame.cooldown:ClearAllPoints()
		frame.cooldown:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
		frame.cooldown:SetSize(size, size)
	end
	frame.text:SetFont("Fonts\\FRIZQT__.TTF", math.max(16, math.floor(size * 0.4)), "OUTLINE")
	frame.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(18, math.floor(size * 0.52)), "OUTLINE")
	if frame.seconds then
		frame.seconds:SetFont("Fonts\\FRIZQT__.TTF", math.max(13, math.floor(size * 0.3)), "OUTLINE")
	end
	frame.sub:SetFont("Fonts\\FRIZQT__.TTF", math.max(11, math.floor(size * 0.24)), "OUTLINE")
	frame.text:SetTextColor(1, 0.82, 0)
	frame.count:SetTextColor(1, 0.82, 0)
	if frame.seconds then
		frame.seconds:SetTextColor(1, 0.82, 0)
	end
	frame.sub:SetTextColor(1, 0.95, 0.8)
	pcall(frame.SetBackdrop, frame, nil)
end

function ApplySpellMissPoint()
	if not LockRemindersMiss.frame or not db then
		return
	end
	if type(db.missPoint) ~= "table" then
		db.missPoint = { "CENTER", "CENTER", 0, 260 }
	end
	LockRemindersMiss.frame:ClearAllPoints()
	LockRemindersMiss.frame:SetPoint(db.missPoint[1], UIParent, db.missPoint[2], db.missPoint[3], db.missPoint[4])
end

function LockRemindersSaveSpellMissPoint()
	if not LockRemindersMiss.frame or not db then
		return
	end
	local point, _, relative, x, y = LockRemindersMiss.frame:GetPoint()
	db.missPoint = { point, relative, x, y }
end

function LockRemindersPaintMissBanner(label, sub, icon)
	CreateSpellMissAlert()
	local frame = LockRemindersMiss.frame
	if not frame then
		return
	end
	ApplySpellMissLook()
	frame.icon:SetTexture(icon or 136235)
	LockRemindersSmoothIcon(frame.icon)
	label = label or ""
	frame.text:SetText(label)
	frame.text:SetShown(label ~= "")
	if frame.count then
		frame.count:SetText("")
		frame.count:Hide()
	end
	if frame.seconds then
		frame.seconds:SetText("")
		frame.seconds:Hide()
	end
	frame.sub:SetText(sub or "")
	frame.sub:SetShown(sub and sub ~= "")
	frame.text:ClearAllPoints()
	frame.sub:ClearAllPoints()
	if frame.text:IsShown() then
		frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
		if frame.sub:IsShown() then
			frame.text:ClearAllPoints()
			frame.text:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -2)
			frame.sub:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -2)
		end
	elseif frame.sub:IsShown() then
		frame.sub:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
	end
	local nameW = frame.text:IsShown() and frame.text:GetStringWidth() or 0
	local subW = frame.sub:IsShown() and frame.sub:GetStringWidth() or 0
	local textW = math.max(nameW, subW, 72)
	local size = frame.icon:GetWidth()
	if size < 1 then
		size = LockRemindersMissIconSize()
	end
	local stack = 0
	if frame.text:IsShown() then
		stack = stack + frame.text:GetStringHeight()
	end
	if frame.sub:IsShown() then
		stack = stack + (stack > 0 and 2 or 0) + frame.sub:GetStringHeight()
	end
	frame:SetSize(7 + size + 10 + textW + 14, math.max(size + 14, stack + 16))
	LockRemindersFitBanishShade(frame)
	if frame.cooldown then
		frame.cooldown:Hide()
		frame.cooldownKey = nil
	end
	frame:SetAlpha(1)
	frame:SetScale(1)
	frame:Show()
end

function LockRemindersUpdateMissAlerts()
	CreateSpellMissAlert()
	local frame = LockRemindersMiss.frame
	if not frame or not db then
		return
	end
	local now = GetTime()
	frame:EnableMouse(LockRemindersMiss.moving and true or false)
	if LockRemindersMiss.previewUntil and now >= LockRemindersMiss.previewUntil then
		LockRemindersMiss.previewUntil = nil
	end
	if LockRemindersMiss.moving then
		LockRemindersPaintMissBanner(LockRemindersMiss.label or "RESISTED", "Drag", LockRemindersMiss.iconTex or 136235)
		return
	end
	local untilAt = LockRemindersMiss.previewUntil
	if untilAt and now < untilAt then
		LockRemindersPaintMissBanner(LockRemindersMiss.label or "MISSED", LockRemindersMiss.sub or "", LockRemindersMiss.iconTex or 136235)
		return
	end
	frame:Hide()
	frame.cooldownKey = nil
end

function ShowSpellMiss(spellID, spellName, icon, kind, missType, destName)
	if LockRemindersMiss.moving then
		return
	end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
		return
	end
	if type(spellName) ~= "string" or spellName == "" or (issecretvalue and issecretvalue(spellName)) then
		spellName = SpellName(spellID)
	end
	local stamp = (missType or "") .. "\0" .. (spellName or "")
	local now = GetTime()
	if LockRemindersMiss.stamp == stamp and now - (LockRemindersMiss.stampAt or 0) < 0.4 then
		return
	end
	LockRemindersMiss.stamp = stamp
	LockRemindersMiss.stampAt = now
	if type(destName) ~= "string" or (issecretvalue and issecretvalue(destName)) then
		destName = nil
	end
	local sub = spellName or "Spell"
	if destName and destName ~= "" then
		sub = sub .. " · " .. destName
	end
	if kind == "pet" then
		sub = sub .. " · Pet"
	end
	local hold = LockRemindersMissHold()
	LockRemindersMiss.label = LockRemindersMissTypeLabel(missType)
	LockRemindersMiss.sub = sub
	LockRemindersMiss.iconTex = icon or SpellIcon(spellID) or 136235
	LockRemindersMiss.previewUntil = now + hold
	LockRemindersMiss.cooldownKey = stamp .. ":" .. tostring(math.floor(LockRemindersMiss.previewUntil))
	ApplySpellMissPoint()
	LockRemindersPlayMissSound()
	LockRemindersUpdateMissAlerts()
end

function ChangeMissSize(delta)
	if not db then
		return
	end
	db.missSize = LockRemindersMissIconSize() + delta
	ApplySpellMissLook()
	LockRemindersUpdateMissAlerts()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ChangeMissHold(delta)
	if not db then
		return
	end
	db.missHold = LockRemindersMissHold() + delta
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ShowMissPreview(show)
	CreateSpellMissAlert()
	if not LockRemindersMiss.frame then
		return
	end
	LockRemindersMiss.moving = show and true or false
	if LockRemindersMiss.moving then
		LockRemindersMiss.previewUntil = nil
		LockRemindersMiss.label = "RESISTED"
		LockRemindersMiss.sub = "Drag"
		LockRemindersMiss.iconTex = 136235
		ApplySpellMissPoint()
	end
	LockRemindersUpdateMissAlerts()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function CreateSpellMissAlert()
	if LockRemindersMiss.frame then
		return
	end
	local frame = CreateFrame("Frame", "LockRemindersSpellMiss", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if LockRemindersMiss.moving then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveSpellMissPoint()
	end)
	pcall(frame.SetBackdrop, frame, nil)
	frame.fadeLeft = frame:CreateTexture(nil, "BACKGROUND")
	frame.fadeLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
	frame.shade = frame:CreateTexture(nil, "BACKGROUND")
	frame.shade:SetTexture("Interface\\Buttons\\WHITE8x8")
	frame.fadeRight = frame:CreateTexture(nil, "BACKGROUND")
	frame.fadeRight:SetTexture("Interface\\Buttons\\WHITE8x8")
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetTexCoord(0, 1, 0, 1)
	LockRemindersSmoothIcon(frame.icon)
	local okCD, cooldown = pcall(CreateFrame, "Cooldown", nil, frame, "CooldownFrameTemplate")
	if okCD and cooldown then
		pcall(cooldown.SetDrawBling, cooldown, false)
		if cooldown.SetHideCountdownNumbers then
			pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
		end
		if cooldown.SetDrawEdge then
			pcall(cooldown.SetDrawEdge, cooldown, false)
		end
		frame.cooldown = cooldown
	end
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.text:SetJustifyH("LEFT")
	frame.text:SetTextColor(1, 0.82, 0)
	frame.text:SetShadowColor(0, 0, 0, 1)
	frame.text:SetShadowOffset(1, -1)
	frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	frame.count:SetJustifyH("LEFT")
	frame.count:SetTextColor(1, 0.82, 0)
	frame.count:SetShadowColor(0, 0, 0, 1)
	frame.count:SetShadowOffset(1, -1)
	frame.seconds = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.seconds:SetJustifyH("LEFT")
	frame.seconds:SetTextColor(1, 0.82, 0)
	frame.seconds:SetShadowColor(0, 0, 0, 1)
	frame.seconds:SetShadowOffset(1, -1)
	frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.sub:SetJustifyH("LEFT")
	frame.sub:SetTextColor(1, 0.95, 0.8)
	frame:SetScript("OnUpdate", function(self, elapsed)
		if not self:IsShown() and not LockRemindersMiss.moving then
			return
		end
		self._tick = (self._tick or 0) + (elapsed or 0)
		if self._tick < 0.05 then
			return
		end
		self._tick = 0
		pcall(LockRemindersUpdateMissAlerts)
	end)
	LockRemindersMiss.frame = frame
	ApplySpellMissLook()
	ApplySpellMissPoint()
	frame:Hide()
end


function LockRemindersCDIconSize()
	local size = tonumber(db and db.cdSize) or 40
	if size < 28 then
		size = 28
	elseif size > 72 then
		size = 72
	end
	return size
end

function LockRemindersCDHold()
	local hold = tonumber(db and db.cdHold) or 2.2
	if hold < 0.8 then
		hold = 0.8
	elseif hold > 6 then
		hold = 6
	end
	return hold
end

function LockRemindersCDPad()
	local pad = tonumber(db and db.cdPad)
	if not pad then
		pad = 8
	end
	if pad < 0 then
		pad = 0
	elseif pad > 32 then
		pad = 32
	end
	return pad
end

function LockRemindersCDTextSize()
	local size = tonumber(db and db.cdTextSize)
	if not size then
		size = 14
	end
	if size < 8 then
		size = 8
	elseif size > 36 then
		size = 36
	end
	return size
end

function LockRemindersCDFlashMode()
	local mode = db and db.cdFlash
	if mode == "icon" or mode == "screen" or mode == "both" or mode == "none" then
		return mode
	end
	return "icon"
end

function LockRemindersCDFlashLabel(mode)
	mode = mode or LockRemindersCDFlashMode()
	if mode == "screen" then
		return "Screen"
	end
	if mode == "both" then
		return "Both"
	end
	if mode == "none" then
		return "Off"
	end
	return "Icon"
end

function LockRemindersPlayCDScreenFlash()
	local flash = talentFrame and talentFrame.screenFlash
	if not flash then
		return
	end
	local red, green, blue = LockRemindersReadGlow("cdReadyGlow", 0.35, 0.95, 0.45)
	if flash.tex then
		flash.tex:SetVertexColor(red, green, blue)
	end
	flash:Show()
	flash:SetAlpha(0.55)
	if flash.ag then
		flash.ag:Stop()
		flash.ag:Play()
	end
end

function LockRemindersCDTriggerFlash(icon)
	local mode = LockRemindersCDFlashMode()
	if mode == "none" then
		return
	end
	if mode == "screen" or mode == "both" then
		LockRemindersPlayCDScreenFlash()
	end
	-- Soft white flash only — no bounce/scale (that read as blurry pop).
	if (mode == "icon" or mode == "both") and icon and icon.flashAg then
		icon.flashTex:Show()
		icon.flashAg:Stop()
		icon.flashAg:Play()
	end
end

function LockRemindersCDBaseDuration(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return nil
	end
	if GetSpellBaseCooldown then
		local ok, ms = pcall(GetSpellBaseCooldown, spellID)
		ms = ok and tonumber(ms) or nil
		if ms and not LockRemindersSecret(ms) and ms >= 3000 then
			return ms / 1000
		end
	end
	if C_Spell and C_Spell.GetSpellCooldownInfo then
		local ok, info = pcall(C_Spell.GetSpellCooldownInfo, spellID)
		if ok and type(info) == "table" and not LockRemindersSecret(info) then
			local ms = tonumber(info.durationMs or info.duration)
			if ms and not LockRemindersSecret(ms) and ms >= 3000 then
				return ms / 1000
			end
		end
	end
	-- Forever may hide live CD numbers in combat; keep known long racials usable.
	if spellID == 7744 then
		return 120
	end
end

function LockRemindersCDReadSpell(spellID)
	spellID = tonumber(spellID)
	if not spellID then
		return nil
	end
	local function plain(value)
		if value == nil or LockRemindersSecret(value) then
			return nil
		end
		local ok, number = pcall(tonumber, value)
		if not ok or type(number) ~= "number" or LockRemindersSecret(number) then
			return nil
		end
		return number
	end
	local function read(first, second)
		if type(first) == "table" and not LockRemindersSecret(first) then
			return plain(first.startTime) or plain(first.start), plain(first.duration)
		end
		return plain(first), plain(second)
	end
	local function fromRaw(first, second)
		local start, duration = read(first, second)
		if type(start) == "number" and type(duration) == "number" and duration > 1.5 and start > 0 then
			local left = start + duration - GetTime()
			if left > 0 then
				return left, duration, start
			end
		end
		local rawStart, rawDuration = first, second
		if type(first) == "table" and not LockRemindersSecret(first) then
			rawStart = first.startTime or first.start
			rawDuration = first.duration
		end
		if rawStart == nil or rawDuration == nil then
			return
		end
		if not LockRemindersSecret(rawStart) and not LockRemindersSecret(rawDuration) then
			return
		end
		local ok, left = pcall(function()
			return rawStart + rawDuration - GetTime()
		end)
		if not ok or type(left) ~= "number" or LockRemindersSecret(left) or left <= 0 then
			return
		end
		local base = LockRemindersCDBaseDuration(spellID)
		if base and left <= base + 1.5 then
			return left, base, GetTime() - (base - left)
		end
		if left > 1.5 then
			return left, left, GetTime()
		end
	end
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, first, second = pcall(C_Spell.GetSpellCooldown, spellID)
		if ok then
			local left, duration, start = fromRaw(first, second)
			if left then
				return left, duration, start
			end
		end
	end
	if GetSpellCooldown then
		local ok, first, second = pcall(GetSpellCooldown, spellID)
		if ok then
			local left, duration, start = fromRaw(first, second)
			if left then
				return left, duration, start
			end
		end
	end
end

function LockRemindersCDReadItem(itemID)
	itemID = tonumber(itemID)
	if not itemID then
		return nil
	end
	if GetInventoryItemID and GetInventoryItemCooldown then
		for slot = 13, 14 do
			local okID, equipped = pcall(GetInventoryItemID, "player", slot)
			if okID and tonumber(equipped) == itemID then
				local ok, start, duration = pcall(GetInventoryItemCooldown, "player", slot)
				start = ok and tonumber(start) or nil
				duration = ok and tonumber(duration) or nil
				if start and duration and duration > 1.5 and start > 0 then
					local left = start + duration - GetTime()
					if left > 0 then
						return left, duration, start
					end
				end
			end
		end
	end
	local start, duration, cooling = LockRemindersReadItemCooldown(itemID)
	if cooling == true and start and duration then
		local left
		if LockRemindersSecret(start) or LockRemindersSecret(duration) then
			local ok, value = pcall(function()
				return start + duration - GetTime()
			end)
			if ok and type(value) == "number" and not LockRemindersSecret(value) then
				left = value
			end
		else
			left = start + duration - GetTime()
		end
		if left and left > 0 and (not LockRemindersSecret(duration) and duration > 1.5 or LockRemindersSecret(duration)) then
			return left, duration, start
		end
	end
end

function LockRemindersCDEnsureState(kind, id, name, icon)
	local key = LockRemindersCDKey(kind, id)
	local state = LockRemindersCD.states[key]
	if not state then
		state = { key = key, kind = kind, id = tonumber(id) or id }
		LockRemindersCD.states[key] = state
	end
	if name and name ~= "" then
		state.name = name
	end
	if icon then
		state.icon = icon
	end
	return state, key
end

function LockRemindersCDRememberedLeft(state)
	if not state or not state.start or not state.duration then
		return nil
	end
	if LockRemindersSecret(state.start) or LockRemindersSecret(state.duration) then
		return nil
	end
	local left = state.start + state.duration - GetTime()
	if left > 0 then
		return left
	end
end

function LockRemindersCDMarkCooling(state, left, duration, start)
	if not state then
		return
	end
	-- GCD or channel blips must not replace a long cooldown we already trust.
	if state.mode == "cooling" then
		local remembered = LockRemindersCDRememberedLeft(state)
		if remembered and remembered > 0.5 and state.duration and state.duration >= 5 then
			if not duration or duration < 5 or (left and left + 0.75 < remembered and duration + 1 < state.duration) then
				state.left = remembered
				return
			end
		end
	end
	local was = state.mode
	state.mode = "cooling"
	state.left = left
	state.duration = duration
	state.start = start
	state.readyUntil = nil
	state.fading = nil
	state.slotLocked = nil
	state.misses = 0
	if was ~= "cooling" then
		state.pulse = true
	end
end

function LockRemindersCDMarkReady(state)
	if not state then
		return
	end
	local was = state.mode
	-- Skip READY text hold — go straight to leave fade in place.
	state.mode = "out"
	state.left = nil
	state.duration = nil
	state.start = nil
	state.fading = nil
	state.pulse = nil
	state.flash = nil
	state.misses = 0
	state.readyUntil = nil
	state.slotLocked = true
	if type(state.slotIndex) ~= "number" then
		state.slotIndex = 0
	end
	if was == "cooling" then
		LockRemindersPlaySoundId(db and db.cdSound or "chiji")
	end
end

function LockRemindersCDPollCooldown(state, left, duration, start)
	if not state then
		return
	end
	if left and left > 0 then
		LockRemindersCDMarkCooling(state, left, duration, start)
		return
	end
	if state.mode == "cooling" then
		local remembered = LockRemindersCDRememberedLeft(state)
		if remembered and remembered > 0.35 then
			state.left = remembered
			state.misses = 0
			return
		end
		state.misses = (state.misses or 0) + 1
		if state.misses < 3 then
			return
		end
		LockRemindersCDMarkReady(state)
		return
	end
	if state.mode == "out" then
		return
	end
	if state.mode == "ready" and state.readyUntil and GetTime() < state.readyUntil then
		return
	end
	LockRemindersCD.states[state.key] = nil
end

function LockRemindersCDPollSpell(spellID)
	spellID = tonumber(spellID)
	if not spellID or not LockRemindersCDSpellSaved(spellID) then
		return
	end
	local state = LockRemindersCDEnsureState("spell", spellID, SpellName(spellID), SpellIcon(spellID))
	local left, duration, start = LockRemindersCDReadSpell(spellID)
	LockRemindersCDPollCooldown(state, left, duration, start)
end

function LockRemindersCDPollItem(itemID)
	itemID = tonumber(itemID)
	if not itemID or not LockRemindersCDItemSaved(itemID) then
		return
	end
	local state = LockRemindersCDEnsureState("item", itemID, ItemName(itemID), ItemIcon(itemID))
	local left, duration, start = LockRemindersCDReadItem(itemID)
	LockRemindersCDPollCooldown(state, left, duration, start)
end

function LockRemindersCDPollAll()
	if not db then
		return
	end
	if type(db.cdSpells) == "table" then
		for key in pairs(db.cdSpells) do
			local spellID = tonumber(key)
			if spellID then
				LockRemindersCDPollSpell(spellID)
			end
		end
	end
	if type(db.cdItems) == "table" then
		for key in pairs(db.cdItems) do
			local itemID = tonumber(key)
			if itemID then
				LockRemindersCDPollItem(itemID)
			end
		end
	end
	LockRemindersCDLayout()
end

function LockRemindersCDAcquireIcon(index)
	local icon = LockRemindersCD.icons[index]
	if icon then
		return icon
	end
	local bar = LockRemindersCD.bar
	if not bar then
		return nil
	end
	icon = CreateFrame("Frame", nil, bar)
	icon:SetSize(40, 40)
	icon.glow = LockRemindersMakeEvenGlow(icon)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	-- Mild crop only; heavy crop + round mask looked soft/low-res.
	icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	if icon.texture.SetSnapToPixelGrid then
		pcall(icon.texture.SetSnapToPixelGrid, icon.texture, false)
	end
	if icon.texture.SetTexelSnappingPolicy and Enum and Enum.TexelSnappingPolicy then
		pcall(icon.texture.SetTexelSnappingPolicy, icon.texture, Enum.TexelSnappingPolicy.Off)
	end
	LockRemindersRoundIcon(icon.texture)
	icon.shade = icon:CreateTexture(nil, "ARTWORK", nil, 5)
	icon.shade:SetTexture("Interface\\Buttons\\WHITE8x8")
	icon.shade:SetVertexColor(0, 0, 0, 0.55)
	icon.shade:SetAllPoints(icon.texture)
	if icon.texture.LockRemindersMask and icon.shade.AddMaskTexture then
		pcall(icon.shade.AddMaskTexture, icon.shade, icon.texture.LockRemindersMask)
	end
	icon.layer = CreateFrame("Frame", nil, icon)
	icon.layer:SetAllPoints()
	icon.layer:EnableMouse(false)
	icon.text = icon.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	icon.text:SetPoint("CENTER", 0, 0)
	icon.text:SetJustifyH("CENTER")
	icon.text:SetTextColor(1, 0.97, 0.9)
	icon.text:SetShadowColor(0, 0, 0, 1)
	icon.text:SetShadowOffset(1, -1)
	icon.ready = icon.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	icon.ready:SetPoint("TOP", icon, "BOTTOM", 0, -2)
	icon.ready:SetText("READY")
	icon.ready:SetTextColor(0.45, 1, 0.55)
	icon.ready:SetShadowColor(0, 0, 0, 1)
	icon.ready:SetShadowOffset(1, -1)
	icon.ready:Hide()
	-- Outro is driven by OnUpdate in LockRemindersCDStartOutro (layout-safe).
	icon.outro = nil
	icon.flashTex = icon:CreateTexture(nil, "OVERLAY", nil, 7)
	icon.flashTex:SetTexture("Interface\\Buttons\\WHITE8x8")
	icon.flashTex:SetBlendMode("ADD")
	icon.flashTex:SetVertexColor(1, 1, 1, 0.75)
	icon.flashTex:Hide()
	local flashAg = icon:CreateAnimationGroup()
	local flashIn = flashAg:CreateAnimation("Alpha")
	flashIn:SetFromAlpha(0.7)
	flashIn:SetToAlpha(0)
	flashIn:SetDuration(0.35)
	flashIn:SetSmoothing("OUT")
	flashAg:SetScript("OnPlay", function()
		icon.flashTex:Show()
		icon.flashTex:SetAlpha(0.7)
	end)
	flashAg:SetScript("OnFinished", function()
		icon.flashTex:Hide()
		icon.flashTex:SetAlpha(0)
	end)
	icon.flashAg = flashAg
	-- Soft enter: fade in only (no bounce that softens the art).
	local intro = icon:CreateAnimationGroup()
	local introFade = intro:CreateAnimation("Alpha")
	introFade:SetFromAlpha(0.2)
	introFade:SetToAlpha(1)
	introFade:SetDuration(0.22)
	introFade:SetSmoothing("OUT")
	intro:SetScript("OnPlay", function()
		icon:SetScale(1)
		icon:SetAlpha(0.2)
	end)
	intro:SetScript("OnFinished", function()
		icon:SetAlpha(1)
		icon:SetScale(1)
	end)
	icon.intro = intro
	LockRemindersCD.icons[index] = icon
	return icon
end

function LockRemindersCDPlaceIcon(icon, slotIndex, size, vertical, drift)
	if not icon then
		return
	end
	slotIndex = tonumber(slotIndex) or 0
	if slotIndex < 0 then
		slotIndex = 0
	end
	drift = tonumber(drift) or 0
	local gap = LockRemindersCDPad()
	local offset = slotIndex * (size + gap)
	icon.layoutSlot = slotIndex
	icon.layoutOffset = offset
	icon:ClearAllPoints()
	if vertical then
		icon:SetPoint("TOPLEFT", LockRemindersCD.bar, "TOPLEFT", drift, -offset)
	else
		icon:SetPoint("LEFT", LockRemindersCD.bar, "LEFT", offset, drift)
	end
	icon:SetSize(size, size)
end

function LockRemindersCDStartOutro(icon, state)
	if not icon or not state or icon.outroPlaying then
		return
	end
	if icon.intro and icon.intro.Stop then
		icon.intro:Stop()
	end
	if icon.flashAg and icon.flashAg:IsPlaying() then
		icon.flashAg:Stop()
	end
	if icon.flashTex then
		icon.flashTex:Hide()
	end
	if icon.glow then
		icon.glow.quiet = true
		if icon.glow.ag then
			icon.glow.ag:Stop()
		end
		if icon.glow.plate then
			icon.glow.plate:SetAlpha(0)
		end
	end
	if icon.ready then
		icon.ready:Hide()
	end
	state.fading = true
	state.slotLocked = true
	icon.outroPlaying = true
	icon.outroKey = state.key
	icon.stateKey = state.key
	icon.pinnedSlot = state.slotIndex or icon.layoutSlot or 0
	state.slotIndex = icon.pinnedSlot
	icon.outroVertical = db and db.cdVertical == true
	icon.outroSize = math.floor((LockRemindersCDIconSize() or 40) + 0.5)
	icon:SetScale(1)
	icon:SetAlpha(1)
	-- Freeze exact pixels NOW so later layout pack cannot move this frame.
	LockRemindersCDPlaceIcon(icon, icon.pinnedSlot, icon.outroSize, icon.outroVertical, 0)
	icon:SetFrameLevel((LockRemindersCD.bar and LockRemindersCD.bar:GetFrameLevel() or 1) + 50)
	icon:Show()
	local start = GetTime()
	local duration = 0.55
	icon:SetScript("OnUpdate", function(self)
		local t = (GetTime() - start) / duration
		if t >= 1 then
			self:SetScript("OnUpdate", nil)
			self:SetAlpha(1)
			self:SetScale(1)
			self:Hide()
			self.outroPlaying = nil
			local key = self.outroKey or self.stateKey
			self.outroKey = nil
			self.stateKey = nil
			self.pinnedSlot = nil
			if key and LockRemindersCD.states and LockRemindersCD.states[key] then
				LockRemindersCD.states[key] = nil
			end
			pcall(LockRemindersCDLayout)
			return
		end
		-- Smoothstep ease — fade + tiny shrink in place (no slide/bounce).
		local ease = t * t * (3 - 2 * t)
		local alpha = 1 - ease
		if alpha < 0 then
			alpha = 0
		end
		self:SetAlpha(alpha)
		self:SetScale(1 - 0.08 * ease)
	end)
end

function LockRemindersCDPaintIcon(icon, state, size)
	if not icon or not state then
		return
	end
	if icon.outroPlaying then
		return
	end
	icon.stateKey = state.key
	size = math.floor((tonumber(size) or 40) + 0.5)
	icon:SetSize(size, size)
	-- Full-size art so Spacing 0 puts icons flush (the old size-4 inset left a gap).
	icon.texture:SetSize(size, size)
	icon.texture:ClearAllPoints()
	icon.texture:SetPoint("CENTER")
	icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon.texture:SetTexture(state.icon or 136235)
	LockRemindersRoundIcon(icon.texture)
	icon.shade:ClearAllPoints()
	icon.shade:SetAllPoints(icon.texture)
	icon.flashTex:ClearAllPoints()
	icon.flashTex:SetAllPoints(icon.texture)
	if icon.texture.LockRemindersMask then
		if icon.shade.AddMaskTexture and not icon.shade.LockRemindersMasked then
			pcall(icon.shade.AddMaskTexture, icon.shade, icon.texture.LockRemindersMask)
			icon.shade.LockRemindersMasked = true
		end
		if icon.flashTex.AddMaskTexture and not icon.flashTex.LockRemindersMasked then
			pcall(icon.flashTex.AddMaskTexture, icon.flashTex, icon.texture.LockRemindersMask)
			icon.flashTex.LockRemindersMasked = true
		end
	end
	icon.layer:SetFrameLevel((icon:GetFrameLevel() or 1) + 12)
	local font = icon.text:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	local textSize = LockRemindersCDTextSize()
	local vertical = db and db.cdVertical == true
	icon.text:SetFont(font, textSize, "OUTLINE")
	icon.ready:SetFont(font, math.max(9, math.floor(textSize * 0.78)), "OUTLINE")
	icon.text:ClearAllPoints()
	icon.text:SetPoint("CENTER", icon.layer, "CENTER", 0, 0)
	icon.text:SetJustifyH("CENTER")
	icon.ready:ClearAllPoints()
	if vertical then
		icon.ready:SetPoint("LEFT", icon.texture, "RIGHT", 6, 0)
		icon.ready:SetJustifyH("LEFT")
	else
		icon.ready:SetPoint("TOP", icon, "BOTTOM", 0, -2)
		icon.ready:SetJustifyH("CENTER")
	end
	local cooling = state.mode == "cooling"
	local ready = state.mode == "ready" or state.mode == "out"
	local red, green, blue
	if ready then
		red, green, blue = LockRemindersReadGlow("cdReadyGlow", 0.35, 0.95, 0.45)
	else
		red, green, blue = LockRemindersReadGlow("cdGlow", 0.45, 0.75, 1)
	end
	local border = LockRemindersGlowThick(size, "cdGlowSize")
	LockRemindersFitEvenGlow(icon.glow, icon.texture, size, "cdGlowSize")
	if border > 0 then
		LockRemindersTintEvenGlow(icon.glow, red, green, blue)
	end
	if cooling then
		icon.glow.quiet = true
		if icon.glow.ag then
			icon.glow.ag:Stop()
		end
		if border > 0 and icon.glow.plate then
			icon.glow.plate:SetAlpha(0.72)
		end
		local left = state.left or 0
		local duration = state.duration or left
		local alpha = 0.35 + 0.35 * math.min(1, duration > 0 and left / duration or 1)
		icon.shade:SetVertexColor(0, 0, 0, alpha)
		icon.shade:Show()
		icon.text:SetText(LockRemindersSoulCooldownText(left))
		icon.text:Show()
		icon.ready:Hide()
	else
		if icon.glow and icon.glow.ag then
			icon.glow.ag:Stop()
		end
		if border > 0 then
			icon.glow.quiet = nil
		end
		icon.shade:Hide()
		icon.text:Hide()
		-- No READY / !! label — finished CDs leave with the fade only.
		icon.ready:Hide()
	end
	if state.mode == "out" then
		icon:SetAlpha(1)
		icon:Show()
		LockRemindersCDStartOutro(icon, state)
		return
	end
	state.flash = nil
	state.pulse = nil
	icon:SetAlpha(1)
	icon:SetScale(1)
	icon:Show()
end

function LockRemindersCDTakeIcon(state, busy)
	local icons = LockRemindersCD.icons
	for index = 1, #icons do
		local icon = icons[index]
		if icon and not busy[icon] and icon.stateKey == state.key then
			busy[icon] = true
			return icon
		end
	end
	for index = 1, math.max(#icons + 1, 8) do
		local icon = LockRemindersCDAcquireIcon(index)
		if icon and not busy[icon] and not icon.outroPlaying then
			busy[icon] = true
			return icon
		end
	end
end

function LockRemindersCDLayout()
	local bar = LockRemindersCD.bar
	if not bar or not db then
		return
	end
	local size = LockRemindersCDIconSize()
	size = math.floor(size + 0.5)
	local gap = LockRemindersCDPad()
	local step = size + gap
	if step < 1 then
		step = 1
	end
	local vertical = db.cdVertical == true
	local cooling = {}
	local locked = {}
	local toFade = {}
	local now = GetTime()
	for _, state in pairs(LockRemindersCD.states) do
		if state.mode == "cooling" then
			if state.start and state.duration and not LockRemindersSecret(state.start) and not LockRemindersSecret(state.duration) then
				state.left = state.start + state.duration - now
			end
			if not state.left or state.left <= 0 then
				LockRemindersCDMarkReady(state)
			elseif state.left <= 1.25 and type(state.slotIndex) == "number" then
				-- Stop last-second by-time jumps that looked like a bounce.
				state.slotLocked = true
			end
		end
		if state.mode == "ready" then
			if not state.readyUntil or now >= state.readyUntil then
				state.mode = "out"
				toFade[#toFade + 1] = state
			else
				state.slotLocked = true
				locked[#locked + 1] = state
			end
		elseif state.mode == "out" then
			if not state.fading then
				toFade[#toFade + 1] = state
			end
		elseif state.mode == "cooling" then
			if state.slotLocked and type(state.slotIndex) == "number" then
				locked[#locked + 1] = state
			else
				cooling[#cooling + 1] = state
			end
		end
	end
	local orderRank = LockRemindersCDOrderRank()
	local sortManual = db.cdSortMode == "manual"
	table.sort(cooling, function(a, b)
		if sortManual then
			local ra = orderRank[a.key] or 9999
			local rb = orderRank[b.key] or 9999
			if ra ~= rb then
				return ra < rb
			end
			return (a.name or "") < (b.name or "")
		end
		local la = a.left or 0
		local lb = b.left or 0
		if la ~= lb then
			return la < lb
		end
		local ra = orderRank[a.key] or 9999
		local rb = orderRank[b.key] or 9999
		if ra ~= rb then
			return ra < rb
		end
		return (a.name or "") < (b.name or "")
	end)
	local busy = {}
	local occupied = {}
	local fadingCount = 0
	local maxSlot = -1
	local function claimIndex(slot)
		slot = tonumber(slot) or 0
		if slot < 0 then
			slot = 0
		end
		occupied[slot] = true
		if slot > maxSlot then
			maxSlot = slot
		end
		return slot
	end
	local function nextFreeIndex()
		local slot = 0
		while occupied[slot] do
			slot = slot + 1
		end
		return claimIndex(slot)
	end
	-- 1) Reserve every immovable slot BEFORE packing cooling (fixes overlap).
	for index = 1, #LockRemindersCD.icons do
		local icon = LockRemindersCD.icons[index]
		if icon and icon.outroPlaying then
			busy[icon] = true
			fadingCount = fadingCount + 1
			claimIndex(icon.pinnedSlot or icon.layoutSlot or 0)
		end
	end
	for index = 1, #toFade do
		local state = toFade[index]
		claimIndex(state.slotIndex or 0)
	end
	for index = 1, #locked do
		local state = locked[index]
		claimIndex(state.slotIndex or 0)
	end
	-- 2) Paint locked icons on their frozen slots.
	for index = 1, #locked do
		local state = locked[index]
		local icon = LockRemindersCDTakeIcon(state, busy)
		if icon then
			local slot = state.slotIndex or 0
			state.slotIndex = slot
			state.slotLocked = true
			LockRemindersCDPlaceIcon(icon, slot, size, vertical, 0)
			LockRemindersCDPaintIcon(icon, state, size)
		end
	end
	-- 3) Cooling only fills holes — never steals a ready/fading slot.
	for index = 1, #cooling do
		local state = cooling[index]
		local icon = LockRemindersCDTakeIcon(state, busy)
		if icon then
			local slot = nextFreeIndex()
			state.slotIndex = slot
			state.slotLocked = nil
			LockRemindersCDPlaceIcon(icon, slot, size, vertical, 0)
			LockRemindersCDPaintIcon(icon, state, size)
		end
	end
	-- 4) Start leave fades last, still on their reserved slot.
	for index = 1, #toFade do
		local state = toFade[index]
		local icon = LockRemindersCDTakeIcon(state, busy)
		if icon then
			local slot = state.slotIndex or icon.layoutSlot or 0
			state.slotIndex = slot
			LockRemindersCDPlaceIcon(icon, slot, size, vertical, 0)
			LockRemindersCDPaintIcon(icon, state, size)
			fadingCount = fadingCount + 1
		end
	end
	for index = 1, #LockRemindersCD.icons do
		local icon = LockRemindersCD.icons[index]
		if icon and not busy[icon] then
			icon:Hide()
			icon.stateKey = nil
		end
	end
	local count = #cooling + #locked + fadingCount
	local label = LockRemindersClassLabel("cdLabel", "READY")
	local textSize = LockRemindersCDTextSize()
	local sidePad = 4
	if vertical and label ~= "" then
		sidePad = math.max(48, math.floor(textSize * 4.2))
	elseif not vertical and label ~= "" then
		sidePad = 18
	end
	local span = 0
	if count > 0 and maxSlot >= 0 then
		span = maxSlot * step + size
	end
	if vertical then
		bar:SetSize(size + 8 + sidePad, math.max(size, span) + 4)
	else
		bar:SetSize(math.max(size, span) + 8, size + sidePad)
	end
	if count > 0 or LockRemindersCD.moving then
		bar:Show()
	else
		bar:Hide()
	end
end

function LockRemindersApplyCDLook()
	local bar = LockRemindersCD.bar
	if not bar or not db then
		return
	end
	db.cdSize = LockRemindersCDIconSize()
	if LockRemindersCD.moving then
		Paint(bar, 0.05, 0.08, 0.12, 0.72, 0.45, 0.75, 1, 1)
		bar.hint:Show()
		bar:EnableMouse(true)
		local hasDemo = false
		for _, state in pairs(LockRemindersCD.states) do
			if state and state.demo then
				hasDemo = true
				break
			end
		end
		if not hasDemo then
			LockRemindersCDSeedDemo(false)
		end
	else
		pcall(bar.SetBackdrop, bar, nil)
		bar.hint:Hide()
		bar:EnableMouse(false)
	end
	LockRemindersCDLayout()
end

function LockRemindersApplyCDPoint()
	if not LockRemindersCD.bar or not db then
		return
	end
	if type(db.cdPoint) ~= "table" then
		db.cdPoint = { "CENTER", "CENTER", 0, -40 }
	end
	LockRemindersCD.bar:ClearAllPoints()
	LockRemindersCD.bar:SetPoint(db.cdPoint[1], UIParent, db.cdPoint[2], db.cdPoint[3], db.cdPoint[4])
end

function LockRemindersSaveCDPoint()
	if not LockRemindersCD.bar or not db then
		return
	end
	local point, _, relative, x, y = LockRemindersCD.bar:GetPoint()
	db.cdPoint = { point, relative, x, y }
end

function LockRemindersChangeCDSize(delta)
	if not db then
		return
	end
	db.cdSize = LockRemindersCDIconSize() + delta
	LockRemindersApplyCDLook()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersChangeCDHold(delta)
	if not db then
		return
	end
	local hold = LockRemindersCDHold() + delta
	if hold < 0.8 then
		hold = 0.8
	elseif hold > 6 then
		hold = 6
	end
	db.cdHold = hold
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersChangeCDPad(delta)
	if not db then
		return
	end
	local pad = LockRemindersCDPad() + delta
	if pad < 0 then
		pad = 0
	elseif pad > 32 then
		pad = 32
	end
	db.cdPad = pad
	LockRemindersApplyCDLook()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersChangeCDTextSize(delta)
	if not db then
		return
	end
	db.cdTextSize = LockRemindersCDTextSize() + delta
	LockRemindersApplyCDLook()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersToggleCDVertical()
	if not db then
		return
	end
	db.cdVertical = not (db.cdVertical == true)
	LockRemindersApplyCDLook()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersCycleCDFlash()
	if not db then
		return
	end
	local mode = LockRemindersCDFlashMode()
	if mode == "icon" then
		db.cdFlash = "screen"
	elseif mode == "screen" then
		db.cdFlash = "both"
	elseif mode == "both" then
		db.cdFlash = "none"
	else
		db.cdFlash = "icon"
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersCDClearDemo()
	for key, state in pairs(LockRemindersCD.states) do
		if state and state.demo then
			LockRemindersCD.states[key] = nil
		end
	end
end

function LockRemindersCDSeedDemo(readyFlash)
	LockRemindersCDClearDemo()
	local now = GetTime()
	local demos = {
		{ kind = "spell", id = 686, name = "Shadow Bolt", icon = 136235, mode = "cooling", left = 18, duration = 30, start = now - 12 },
		{ kind = "spell", id = 5782, name = "Fear", icon = 136183, mode = "cooling", left = 42, duration = 60, start = now - 18 },
		{ kind = "spell", id = 5484, name = "Howl of Terror", icon = 136147, mode = "cooling", left = 8, duration = 40, start = now - 32 },
		{ kind = "item", id = 37865, name = "Medallion", icon = 133452, mode = "cooling", left = 95, duration = 120, start = now - 25 },
		{ kind = "spell", id = 20572, name = "Blood Fury", icon = 135726, mode = "ready", left = nil, duration = nil, start = nil },
	}
	for index = 1, #demos do
		local info = demos[index]
		local state = LockRemindersCDEnsureState(info.kind, info.id, info.name, info.icon)
		state.demo = true
		state.mode = info.mode
		state.left = info.left
		state.duration = info.duration
		state.start = info.start
		if info.mode == "ready" then
			state.readyUntil = now + LockRemindersCDHold()
			if readyFlash then
				state.flash = true
			end
		else
			state.readyUntil = nil
			state.pulse = true
		end
	end
end

function LockRemindersShowCDPreview(show)
	LockRemindersCD.moving = show and true or false
	if LockRemindersCD.moving then
		LockRemindersCDSeedDemo(false)
	else
		LockRemindersCDClearDemo()
	end
	LockRemindersApplyCDLook()
	LockRemindersApplyCDPoint()
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function LockRemindersTestCDReady()
	if LockRemindersCD.moving then
		LockRemindersShowCDPreview(false)
	end
	LockRemindersCDSeedDemo(true)
	LockRemindersCDLayout()
end

function CreateCDManagerAlert()
	if LockRemindersCD.bar then
		return
	end
	LockRemindersCD.bar = CreateFrame("Frame", "LockRemindersCDManager", UIParent, "BackdropTemplate")
	local bar = LockRemindersCD.bar
	bar:SetFrameStrata("HIGH")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:EnableMouse(false)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function(self)
		if LockRemindersCD.moving then
			self:StartMoving()
		end
	end)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveCDPoint()
	end)
	bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.hint:SetPoint("TOP", bar, "BOTTOM", 0, -4)
	bar.hint:SetText("Drag")
	bar.hint:SetTextColor(0.7, 0.85, 1)
	bar.hint:Hide()
	LockRemindersApplyCDLook()
	LockRemindersApplyCDPoint()
	bar:Hide()
end

function LockRemindersStartCDManager()
	if LockRemindersCD.ticker then
		return
	end
	LockRemindersCD.ticker = C_Timer.NewTicker(0.35, function()
		if LockRemindersCD.moving then
			LockRemindersCDLayout()
			return
		end
		local watching = false
		if db and type(db.cdSpells) == "table" and next(db.cdSpells) then
			watching = true
		end
		if db and type(db.cdItems) == "table" and next(db.cdItems) then
			watching = true
		end
		if watching or next(LockRemindersCD.states) then
			LockRemindersCDPollAll()
		elseif LockRemindersCD.bar then
			LockRemindersCD.bar:Hide()
		end
	end)
end

function LockRemindersCDStampCast(spellID)
	spellID = tonumber(spellID)
	if not spellID or not LockRemindersCDSpellSaved(spellID) then
		return false
	end
	local state = LockRemindersCDEnsureState("spell", spellID, SpellName(spellID), SpellIcon(spellID))
	local left, duration, start = LockRemindersCDReadSpell(spellID)
	if not left then
		duration = LockRemindersCDBaseDuration(spellID)
		if duration then
			start = GetTime()
			left = duration
		end
	end
	if not left or left <= 0 then
		LockRemindersCDPollCooldown(state, left, duration, start)
		return false
	end
	LockRemindersCDMarkCooling(state, left, duration, start)
	return true
end

function LockRemindersNoteCDCast(unit, arg2, arg3, arg4)
	if unit ~= "player" or not db or type(db.cdSpells) ~= "table" then
		return
	end
	local castID
	local secrets = {}
	local function take(value)
		if value == nil then
			return
		end
		if LockRemindersSecret(value) then
			secrets[#secrets + 1] = value
			return
		end
		if type(value) == "number" then
			castID = castID or value
			return
		end
		if type(value) == "string" and value ~= "" then
			local numeric = tonumber(value)
			if numeric then
				castID = castID or numeric
			end
		end
	end
	take(arg2)
	take(arg3)
	take(arg4)
	if not castID and #secrets > 0 then
		for key in pairs(db.cdSpells) do
			local saved = tonumber(key)
			if saved and (db.cdSpells[key] == true or db.cdSpells[tostring(saved)] == true) then
				local aliases = SpellAliases(saved)
				for index = 1, #secrets do
					for aliasIndex = 1, #aliases do
						if LockRemindersSameSpell(secrets[index], aliases[aliasIndex]) then
							castID = saved
							break
						end
					end
					if castID then
						break
					end
				end
			end
			if castID then
				break
			end
		end
	end
	if not castID or not LockRemindersCDSpellSaved(castID) then
		return
	end
	local function stamp()
		pcall(LockRemindersCDStampCast, castID)
		pcall(LockRemindersCDLayout)
	end
	stamp()
	C_Timer.After(0.05, stamp)
	C_Timer.After(0.25, stamp)
end

function LockRemindersSpeedBase()
	local base = tonumber(BASE_MOVEMENT_SPEED)
	if not base or base <= 0 then
		base = 7
	end
	return base
end

function LockRemindersSpeedToPercent(yards)
	yards = tonumber(yards)
	if not yards or yards < 0 then
		return nil
	end
	return math.floor(yards / LockRemindersSpeedBase() * 100 + 0.5)
end

function LockRemindersSpeedPercent(unit)
	if not unit or not UnitExists or not UnitExists(unit) or not GetUnitSpeed then
		return nil
	end
	-- GetUnitSpeed returns current, run, flight, swim. Forever can zero "current"
	-- on player while dead; callers may fall back to run when motion says moving.
	local ok, current, runSpeed, flightSpeed, swimSpeed = pcall(GetUnitSpeed, unit)
	if not ok then
		return nil
	end
	local function take(value)
		if value == nil or LockRemindersSecret(value) then
			return nil
		end
		value = tonumber(value)
		if not value or value < 0 then
			return nil
		end
		return LockRemindersSpeedToPercent(value)
	end
	local currentPct = take(current)
	if currentPct ~= nil and currentPct > 0 then
		return currentPct
	end
	return currentPct, take(runSpeed), take(flightSpeed), take(swimSpeed)
end

function LockRemindersPlayerIsMoving()
	if type(IsPlayerMoving) ~= "function" then
		return nil
	end
	local ok, moving = pcall(IsPlayerMoving)
	if not ok or LockRemindersSecret(moving) then
		return nil
	end
	return moving and true or false
end

function LockRemindersSpeedFromMotion(unit)
	if not UnitPosition or not GetTime or not UnitExists or not UnitExists(unit) then
		return nil
	end
	local ok, y, x = pcall(UnitPosition, unit)
	if not ok or y == nil or x == nil or LockRemindersSecret(y) or LockRemindersSecret(x) then
		return nil
	end
	y = tonumber(y)
	x = tonumber(x)
	if not y or not x or (x == 0 and y == 0) then
		return nil
	end
	local now = GetTime()
	LockRemindersMisc.motion = LockRemindersMisc.motion or {}
	local prev = LockRemindersMisc.motion[unit]
	LockRemindersMisc.motion[unit] = { x = x, y = y, t = now }
	if not prev then
		return nil
	end
	local dt = now - prev.t
	if dt <= 0 or dt > 0.5 then
		return nil
	end
	local dx = x - prev.x
	local dy = y - prev.y
	local yards = math.sqrt(dx * dx + dy * dy)
	if yards / dt > 40 then
		return nil
	end
	if yards < 0.02 then
		return 0
	end
	return LockRemindersSpeedToPercent(yards / dt)
end

function LockRemindersCalmSpeed(percent)
	if percent == nil then
		return nil
	end
	if percent >= 93 and percent <= 110 then
		return 100
	end
	return percent
end

function LockRemindersPlayerIsGhost()
	if not UnitIsDeadOrGhost then
		return false
	end
	local ok, dead = pcall(UnitIsDeadOrGhost, "player")
	return ok and dead == true and not LockRemindersSecret(dead)
end

function LockRemindersReadSpeed(unit)
	local api, runPct, flightPct, swimPct = LockRemindersSpeedPercent(unit)
	local motion = LockRemindersSpeedFromMotion(unit)
	local ghost = unit == "player" and LockRemindersPlayerIsGhost()
	-- Forever often zeros GetUnitSpeed("player") current while dead, but the same
	-- unit as "target" (self-target) still returns the real current speed.
	if ghost and (api == nil or api <= 0) and UnitExists and UnitExists("target") and UnitIsUnit then
		local ok, same = pcall(UnitIsUnit, "target", "player")
		if ok and same == true and not LockRemindersSecret(same) then
			local asTarget = LockRemindersSpeedPercent("target")
			if asTarget ~= nil and asTarget > 0 then
				api = asTarget
			end
		end
	end
	if api ~= nil and api > 0 then
		return LockRemindersCalmSpeed(api)
	end
	-- Ghost current can stay 0 while moving: if motion (or swim/fly) says we move,
	-- show the matching mode speed (usually run = 125% as ghost).
	if ghost then
		local moving = (type(motion) == "number" and motion > 0) or LockRemindersPlayerIsMoving() == true
		if moving then
			local mode = swimPct or flightPct or runPct or motion
			if type(mode) == "number" and mode > 0 then
				return LockRemindersCalmSpeed(mode)
			end
		end
		if type(motion) == "number" and motion > 0 then
			return LockRemindersCalmSpeed(motion)
		end
		return nil
	end
	-- Alive: IsPlayerMoving reliably means stopped -> "--".
	if unit == "player" and LockRemindersPlayerIsMoving() == false then
		return nil
	end
	if type(motion) == "number" and motion > 0 then
		return LockRemindersCalmSpeed(motion)
	end
	return nil
end

function LockRemindersApplyNamedPoint(frame, key, fallback)
	if not frame or not db then
		return
	end
	local point = db[key]
	if type(point) ~= "table" then
		point = fallback
		db[key] = { fallback[1], fallback[2], fallback[3], fallback[4] }
	end
	frame:ClearAllPoints()
	frame:SetPoint(point[1] or "CENTER", UIParent, point[2] or "CENTER", point[3] or 0, point[4] or 0)
end

function LockRemindersSaveNamedPoint(frame, key)
	if not frame or not db then
		return
	end
	local point, _, relative, x, y = frame:GetPoint()
	if point and relative then
		db[key] = { point, relative, x, y }
	end
end

function LockRemindersApplySpeedLook()
	local frame = LockRemindersMisc.speed
	if not frame or not db then
		return
	end
	local size = tonumber(db.speedSize) or 18
	if size < 12 then
		size = 12
	elseif size > 48 then
		size = 48
	end
	db.speedSize = size
	local font = frame.text:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	frame.text:SetFont(font, size, "OUTLINE")
	local red, green, blue = LockRemindersReadGlow("speedColor", 1, 0.96, 0.9)
	frame.text:SetTextColor(red, green, blue)
	local split = db.speedSplit == true
	local width = split and math.max(72, math.floor(size * 4 + 16)) or math.max(128, math.floor(size * 8 + 28))
	frame:SetSize(width, size + 18)
	if frame.target and frame.target.text then
		frame.target.text:SetFont(font, size, "OUTLINE")
		frame.target.text:SetTextColor(red, green, blue)
		frame.target:SetSize(width, size + 18)
	end
end

function LockRemindersUpdateSpeed()
	local frame = LockRemindersMisc.speed
	if not frame or not db then
		return
	end
	if db.speedShow == false and not LockRemindersMisc.speedMoving then
		frame:Hide()
		if frame.target then
			frame.target:Hide()
		end
		return
	end
	local mine = LockRemindersReadSpeed("player")
	if mine ~= nil then
		frame.lastMine = mine
	else
		frame.lastMine = nil
	end
	local hasTarget = UnitExists and UnitExists("target")
	local guid
	if hasTarget and UnitGUID then
		guid = UnitGUID("target")
		if LockRemindersSecret(guid) then
			guid = frame.targetGUID
		end
	end
	if guid ~= frame.targetGUID then
		frame.targetGUID = guid
		frame.lastTarget = nil
		if LockRemindersMisc.motion then
			LockRemindersMisc.motion.target = nil
		end
	end
	if hasTarget then
		local theirs = LockRemindersReadSpeed("target")
		if theirs ~= nil then
			frame.lastTarget = theirs
		else
			frame.lastTarget = nil
		end
	else
		frame.lastTarget = nil
	end
	local left = frame.lastMine and (frame.lastMine .. "%") or "--"
	local right = frame.lastTarget and (frame.lastTarget .. "%") or "--"
	local split = db.speedSplit == true
	if split then
		frame.text:SetText(left)
		if frame.target and frame.target.text then
			frame.target.text:SetText(right)
			frame.target:Show()
		end
	else
		frame.text:SetText(left .. " / " .. right)
		if frame.target then
			frame.target:Hide()
		end
	end
	frame:Show()
end

function LockRemindersSetSpeedMove(on)
	LockRemindersMisc.speedMoving = on and true or false
	local frame = LockRemindersMisc.speed
	if not frame then
		return
	end
	local function chrome(box, on)
		if not box then
			return
		end
		box:SetAlpha(1)
		if on then
			box:Show()
			box:EnableMouse(true)
			box.hint:Show()
			box:SetBackdropColor(0.08, 0.05, 0.12, 0.75)
			box:SetBackdropBorderColor(0.7, 0.55, 0.95, 0.95)
		else
			box:EnableMouse(false)
			box.hint:Hide()
			box:SetBackdropColor(0, 0, 0, 0)
			box:SetBackdropBorderColor(0, 0, 0, 0)
		end
	end
	local moving = LockRemindersMisc.speedMoving
	local split = db.speedSplit == true
	if frame.hint then
		frame.hint:SetText(split and "You" or "Drag")
	end
	chrome(frame, moving)
	chrome(frame.target, moving and split)
	LockRemindersUpdateSpeed()
	LockRemindersRefreshMisc()
end

function LockRemindersAttachPop(frame, shouldStay)
	local intro = frame:CreateAnimationGroup()
	local introFade = intro:CreateAnimation("Alpha")
	introFade:SetFromAlpha(1)
	introFade:SetToAlpha(1)
	introFade:SetDuration(0.14)
	introFade:SetOrder(1)
	introFade:SetSmoothing("OUT")
	local introGrow = intro:CreateAnimation("Scale")
	introGrow:SetScale(1.45, 1.45)
	introGrow:SetOrigin("CENTER", 0, 0)
	introGrow:SetDuration(0.12)
	introGrow:SetOrder(1)
	introGrow:SetSmoothing("OUT")
	local introSettle = intro:CreateAnimation("Scale")
	introSettle:SetScale(0.7, 0.7)
	introSettle:SetOrigin("CENTER", 0, 0)
	introSettle:SetDuration(0.14)
	introSettle:SetOrder(2)
	introSettle:SetSmoothing("OUT")
	intro:SetScript("OnFinished", function()
		frame:SetScale(1)
		frame:SetAlpha(1)
	end)
	frame.intro = intro

	local fade = frame:CreateAnimationGroup()
	local fadeOut = fade:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.32)
	fadeOut:SetSmoothing("IN")
	local fadeScale = fade:CreateAnimation("Scale")
	fadeScale:SetScale(1.28, 1.28)
	fadeScale:SetOrigin("CENTER", 0, 0)
	fadeScale:SetDuration(0.32)
	fadeScale:SetSmoothing("IN")
	fade:SetScript("OnFinished", function()
		if shouldStay() then
			frame:SetAlpha(1)
			frame:SetScale(1)
			return
		end
		frame:Hide()
		frame:SetAlpha(1)
		frame:SetScale(1)
	end)
	frame.fade = fade
end

-- WoW combat-text style: flash in, drift down, fade out.
function LockRemindersMiscTick()
	if not db then
		return
	end
	LockRemindersUpdateSpeed()
end

function LockRemindersStartMisc()
	if LockRemindersMisc.ticker or not C_Timer then
		return
	end
	if C_Timer.NewTicker then
		LockRemindersMisc.ticker = C_Timer.NewTicker(0.25, function()
			pcall(LockRemindersMiscTick)
		end)
		return
	end
	local function again()
		pcall(LockRemindersMiscTick)
		C_Timer.After(0.25, again)
	end
	C_Timer.After(0.25, again)
	LockRemindersMisc.ticker = true
end

function LockRemindersPaintToggle(button, on)
	if not button then
		return
	end
	button.label:SetText(on and "On" or "Off")
	if on then
		Paint(button, 0.14, 0.26, 0.16, 1, 0.4, 0.82, 0.48, 1)
		button.label:SetTextColor(0.86, 1, 0.86)
	else
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label:SetTextColor(0.78, 0.74, 0.86)
	end
end

function LockRemindersPaintChoiceRow(buttons, selected)
	if not buttons then
		return
	end
	for index = 1, #buttons do
		local button = buttons[index]
		local picked = button.choiceId == selected
		button.picked = picked
		if picked then
			Paint(button, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
			button.label:SetTextColor(1, 0.93, 0.72)
		else
			Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
			button.label:SetTextColor(0.86, 0.82, 0.94)
		end
	end
end

function LockRemindersRefreshMisc()
	local bar = panel and panel.miscBar
	if not bar or not db then
		return
	end
	if bar.speedSize then
		bar.speedSize:SetText(tostring(tonumber(db.speedSize) or 18))
	end
	if bar.speedMove then
		bar.speedMove.label:SetText(LockRemindersMisc.speedMoving and "Done" or "Move")
	end
	if bar.speedColor then
		LockRemindersPaintGlowButton(bar.speedColor, "speedColor", 1, 0.96, 0.9)
	end
	LockRemindersPaintChoiceRow(bar.speedLayout, db.speedSplit and "split" or "together")
	LockRemindersPaintToggle(bar.speedToggle, db.speedShow ~= false)
end

function LockRemindersChoiceMenu(parent, anchor, gap, choices, read, write, preview, width)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width or 120, 22)
	button:SetPoint("LEFT", anchor, "RIGHT", gap or 8, 0)
	Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("LEFT", 8, 0)
	button.label:SetPoint("RIGHT", -16, 0)
	button.label:SetJustifyH("LEFT")
	button.label:SetTextColor(1, 0.93, 0.72)
	button.arrow = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.arrow:SetPoint("RIGHT", -6, 0)
	button.arrow:SetText("v")
	button.arrow:SetTextColor(0.9, 0.84, 1)
	local function labelFor(id)
		for index = 1, #choices do
			if choices[index][2] == id then
				return choices[index][1]
			end
		end
		return choices[1][1]
	end
	local function refresh()
		button.label:SetText(labelFor(read()))
	end
	local function paintRow(row, picked)
		row.picked = picked
		if picked then
			Paint(row, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
			row.label:SetTextColor(1, 0.93, 0.72)
		else
			Paint(row, 0.1, 0.08, 0.14, 1, 0.28, 0.22, 0.4, 1)
			row.label:SetTextColor(0.9, 0.86, 0.98)
		end
	end
	button:SetScript("OnClick", function()
		local popup = LockRemindersChoicePopup
		if popup and popup.owner == button and popup:IsShown() then
			popup:Hide()
			return
		end
		if not popup then
			popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
			popup:SetFrameStrata("DIALOG")
			popup:EnableMouse(true)
			Paint(popup, 0.07, 0.05, 0.1, 0.98, 0.45, 0.35, 0.62, 1)
			popup.rows = {}
			popup.blocker = CreateFrame("Button", nil, UIParent)
			popup.blocker:SetAllPoints(UIParent)
			popup.blocker:SetFrameStrata("DIALOG")
			popup.blocker:SetScript("OnClick", function()
				popup:Hide()
			end)
			popup:SetScript("OnHide", function(self)
				self.owner = nil
				if self.blocker then
					self.blocker:Hide()
				end
			end)
			LockRemindersChoicePopup = popup
		end
		local selected = read()
		local y = 4
		for index = 1, #choices do
			local row = popup.rows[index]
			if not row then
				row = CreateFrame("Button", nil, popup, "BackdropTemplate")
				row:SetHeight(22)
				row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.label:SetPoint("LEFT", 8, 0)
				row.label:SetPoint("RIGHT", -8, 0)
				row.label:SetJustifyH("LEFT")
				row:SetScript("OnEnter", function(self)
					if self.header or self.picked then
						return
					end
					self:SetBackdropColor(0.24, 0.16, 0.34, 1)
				end)
				row:SetScript("OnLeave", function(self)
					if self.header then
						return
					end
					paintRow(self, self.picked)
				end)
				popup.rows[index] = row
			end
			local choice = choices[index]
			local header = choice[2] == nil
			local height = header and 18 or 22
			row.header = header
			row:SetHeight(height)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 4, -y)
			row:SetPoint("TOPRIGHT", -4, -y)
			row:Show()
			row.label:SetText(choice[1])
			y = y + height + 2
			if header then
				row.choiceId = nil
				row.picked = false
				Paint(row, 0.16, 0.12, 0.22, 1, 0.16, 0.12, 0.22, 0)
				row.label:SetTextColor(0.78, 0.68, 0.96)
				row:SetScript("OnClick", function() end)
			else
				row.choiceId = choice[2]
				paintRow(row, row.choiceId == selected)
				row:SetScript("OnClick", function(self)
					write(self.choiceId)
					if preview and self.choiceId ~= "none" then
						preview(self.choiceId)
					end
					refresh()
					popup:Hide()
				end)
			end
		end
		for index = #choices + 1, #popup.rows do
			popup.rows[index]:Hide()
		end
		popup:SetSize(button:GetWidth(), y + 4)
		popup:ClearAllPoints()
		if (button:GetBottom() or 0) < y + 24 then
			popup:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
		else
			popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
		end
		popup:SetFrameLevel((popup.blocker:GetFrameLevel() or 1) + 10)
		popup.owner = button
		popup.blocker:Show()
		popup:Show()
	end)
	button:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.24, 0.16, 0.34, 1)
	end)
	button:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	if parent and parent.HookScript then
		parent:HookScript("OnHide", function()
			if LockRemindersChoicePopup and LockRemindersChoicePopup.owner == button then
				LockRemindersChoicePopup:Hide()
			end
		end)
	end
	refresh()
	return refresh, button
end

function LockRemindersMakeSoundRow(parent, anchor, read, write)
	return LockRemindersChoiceMenu(parent, anchor, 8, LockRemindersSoundChoices, read, write, LockRemindersPreviewSound, 156)
end

function LockRemindersOpenSettings(owner, key)
	local bar = CreateFrame("Frame", nil, owner)
	bar:SetPoint("TOPLEFT", 14, -112)
	bar:SetPoint("BOTTOMRIGHT", -16, 28)
	bar:Hide()
	owner[key] = bar
	local scroll = CreateFrame("ScrollFrame", nil, bar)
	scroll:SetAllPoints()
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(700, 40)
	scroll:SetScrollChild(body)
	bar.scroll = scroll
	bar.body = body
	bar.cursor = -4
	local slider = CreateFrame("Slider", nil, bar, "BackdropTemplate")
	slider:SetWidth(8)
	slider:SetPoint("TOPRIGHT", 2, -2)
	slider:SetPoint("BOTTOMRIGHT", 2, 2)
	slider:SetOrientation("VERTICAL")
	slider:SetMinMaxValues(0, 1)
	slider:SetValue(0)
	Paint(slider, 0.1, 0.08, 0.14, 0.9, 0.28, 0.22, 0.38, 1)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
	thumb:SetSize(8, 36)
	thumb:SetVertexColor(0.62, 0.5, 0.86, 0.95)
	slider:SetThumbTexture(thumb)
	slider:Hide()
	bar.slider = slider
	local syncing = false
	local function syncSlider()
		local range = scroll:GetVerticalScrollRange() or 0
		if range <= 1 then
			slider:SetMinMaxValues(0, 1)
			slider:SetValue(0)
			slider:Hide()
			return
		end
		slider:Show()
		slider:SetMinMaxValues(0, range)
		syncing = true
		slider:SetValue(scroll:GetVerticalScroll() or 0)
		syncing = false
	end
	bar.syncSlider = syncSlider
	slider:SetScript("OnValueChanged", function(_, value)
		if syncing then
			return
		end
		scroll:SetVerticalScroll(value or 0)
	end)
	local function wheel(_, delta)
		local range = scroll:GetVerticalScrollRange() or 0
		local value = scroll:GetVerticalScroll() - delta * 40
		if value < 0 then
			value = 0
		end
		if value > range then
			value = range
		end
		scroll:SetVerticalScroll(value)
		syncSlider()
	end
	bar.wheel = wheel
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", wheel)
	body:EnableMouseWheel(true)
	body:SetScript("OnMouseWheel", wheel)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", wheel)
	bar:SetScript("OnShow", function(self)
		local width = self:GetWidth()
		if width and width > 40 then
			self.body:SetWidth(width)
		end
		if self.syncSlider then
			self.syncSlider()
		end
	end)
	return bar
end

function LockRemindersPinSettingsActions(move, test, parent, yOffset)
	yOffset = yOffset or -14
	if test then
		test:ClearAllPoints()
		test:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOffset)
	end
	if move then
		move:ClearAllPoints()
		if test then
			move:SetPoint("RIGHT", test, "LEFT", -8, 0)
		else
			move:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, yOffset)
		end
	end
end

function LockRemindersSettingsHead(bar, text)
	local head = bar.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	head:SetPoint("TOPLEFT", 4, bar.cursor)
	head:SetText(text)
	head:SetTextColor(0.78, 0.68, 0.96)
	bar.cursor = bar.cursor - 18
end

function LockRemindersSettingsCard(bar, height, icon, title, note)
	local card = CreateFrame("Frame", nil, bar.body, "BackdropTemplate")
	card:SetPoint("TOPLEFT", 0, bar.cursor)
	card:SetPoint("TOPRIGHT", -2, bar.cursor)
	card:SetHeight(height)
	Paint(card, 1, 1, 1, 0.035, 1, 1, 1, 0.04)
	card:EnableMouseWheel(true)
	card:SetScript("OnMouseWheel", bar.wheel)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(32, 32)
	card.icon:SetPoint("TOPLEFT", 8, -9)
	card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if icon then
		card.icon:SetTexture(icon)
	end
	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	card.title:SetPoint("TOPLEFT", 48, -8)
	card.title:SetWidth(120)
	card.title:SetJustifyH("LEFT")
	card.title:SetWordWrap(false)
	card.title:SetText(title or "")
	card.title:SetTextColor(1, 0.96, 1)
	card.note = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.note:SetPoint("TOPLEFT", 48, -24)
	card.note:SetWidth(120)
	card.note:SetJustifyH("LEFT")
	card.note:SetWordWrap(false)
	card.note:SetText(note or "")
	card.note:SetTextColor(0.62, 0.58, 0.72)
	bar.cursor = bar.cursor - height - 8
	return card
end

function LockRemindersSettingsFinish(bar)
	bar.body:SetHeight(math.max(40, -bar.cursor + 28))
	if bar.syncSlider then
		C_Timer.After(0, bar.syncSlider)
	end
end

function LockRemindersSettingsCaption(parent, anchor, text, gap)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", anchor, "RIGHT", gap or 12, 0)
	label:SetText(text)
	label:SetTextColor(0.9, 0.84, 1)
	return label
end

function LockRemindersSettingsStepper(parent, anchor, gap, read, write, low, high, step)
	local minus = StepButton(parent, "-")
	minus:SetPoint("LEFT", anchor, "RIGHT", gap or 8, 0)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", minus, "RIGHT", 6, 0)
	text:SetWidth(36)
	text:SetJustifyH("CENTER")
	text:SetTextColor(1, 0.95, 0.86)
	local plus = StepButton(parent, "+")
	plus:SetPoint("LEFT", text, "RIGHT", 2, 0)
	minus:SetScript("OnClick", function()
		local value = (tonumber(read()) or 0) - step
		if value < low then
			value = low
		end
		write(value)
	end)
	plus:SetScript("OnClick", function()
		local value = (tonumber(read()) or 0) + step
		if value > high then
			value = high
		end
		write(value)
	end)
	return plus, text
end

function LockRemindersSettingsButton(parent, anchor, text, gap, onClick)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(64, 22)
	button:SetPoint("LEFT", anchor, "RIGHT", gap or 8, 0)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("CENTER")
	button.label:SetText(text)
	button:SetScript("OnClick", onClick)
	button:EnableMouseWheel(true)
	button:SetScript("OnMouseWheel", function(_, delta)
		local card = parent
		if card and card.GetScript and card:GetScript("OnMouseWheel") then
			card:GetScript("OnMouseWheel")(card, delta)
		end
	end)
	if text == "Test" then
		Paint(button, 0.14, 0.1, 0.2, 1, 0.95, 0.45, 0.35, 1)
	else
		Paint(button, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	end
	button:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	button:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	return button
end

function LockRemindersSettingsEdit(parent, anchor, field, fallback, width, onApply, allowEmpty, maxLetters)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width or 140, 22)
	box:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(tonumber(maxLetters) or 24)
	box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
	box:SetTextColor(1, 0.95, 0.86)
	box:SetJustifyH("LEFT")
	box:SetTextInsets(6, 6, 0, 0)
	Paint(box, 0.08, 0.06, 0.12, 1, 0.45, 0.35, 0.62, 1)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		local text = self:GetText() or ""
		text = text:gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" and not allowEmpty then
			text = fallback
		end
		db[field] = text
		self.quiet = true
		self:SetText(text)
		self.quiet = nil
		if onApply then
			onApply()
		end
	end)
	box:SetScript("OnTextChanged", function(self)
		if self.quiet then
			return
		end
		db[field] = self:GetText() or ""
		if onApply then
			onApply()
		end
	end)
	return box
end

LockRemindersFun = LockRemindersFun or { seen = {} }

function LockRemindersFunHostile()
	-- Sanctuary / neutral PvP flags block UnitCanAttack; opposite faction is still a rival.
	if UnitFactionGroup then
		local okMine, mine = pcall(UnitFactionGroup, "player")
		local okTheirs, theirs = pcall(UnitFactionGroup, "target")
		if okMine and okTheirs and type(mine) == "string" and type(theirs) == "string" and mine ~= "" and theirs ~= "" and not LockRemindersSecret(mine) and not LockRemindersSecret(theirs) then
			return mine ~= theirs
		end
	end
	if UnitIsEnemy then
		local ok, enemy = pcall(UnitIsEnemy, "player", "target")
		if ok and not LockRemindersSecret(enemy) and enemy == true then
			return true
		end
	end
	if UnitCanAttack then
		local ok, attack = pcall(UnitCanAttack, "player", "target")
		if ok and not LockRemindersSecret(attack) then
			return attack == true
		end
	end
	return false
end

function LockRemindersFunRace()
	if not UnitExists or not UnitExists("target") or not UnitIsPlayer or not UnitRace then
		return nil
	end
	local ok, player = pcall(UnitIsPlayer, "target")
	if not ok or player ~= true or LockRemindersSecret(player) then
		return nil
	end
	if UnitIsUnit then
		local sameOk, same = pcall(UnitIsUnit, "target", "player")
		if sameOk and same == true and not LockRemindersSecret(same) then
			return nil
		end
	end
	if not LockRemindersFunHostile() then
		return nil
	end
	local raceOk, _, token = pcall(UnitRace, "target")
	if not raceOk or type(token) ~= "string" or token == "" or LockRemindersSecret(token) then
		return nil
	end
	local faction
	if UnitFactionGroup then
		local factionOk, value = pcall(UnitFactionGroup, "target")
		if factionOk and type(value) == "string" and value ~= "" and not LockRemindersSecret(value) then
			faction = value
		end
	end
	if token == "Undead" then
		token = "Scourge"
	elseif token == "HighOrderSkyborne" or token == "SkyborneAlliance" then
		token = "Skyborne"
		faction = "Alliance"
	elseif token == "WindshaperSkyborne" or token == "SkyborneHorde" then
		token = "Skyborne"
		faction = "Horde"
	end
	return token, faction
end

function LockRemindersFunMatches(token, faction)
	if not token or not db or type(db.funRaces) ~= "table" then
		return false
	end
	if db.funRaces[token] == true then
		return true
	end
	return faction and db.funRaces[token .. ":" .. faction] == true
end

function LockRemindersFunPlay(force)
	if not DoEmote then
		return
	end
	local pool = { "CHICKEN", "SPIT", "RUDE", "LAUGH" }
	local emote = db and db.funEmote or "CHICKEN"
	if emote == "RANDOM" then
		emote = pool[math.random(#pool)]
	else
		local known = false
		for index = 1, #pool do
			if pool[index] == emote then
				known = true
			end
		end
		if not known then
			emote = "CHICKEN"
		end
	end
	local target = UnitExists and UnitExists("target") and "target" or nil
	pcall(DoEmote, emote, target)
	if not force then
		LockRemindersFun.last = GetTime()
	end
end

function LockRemindersFunOnTarget()
	if not db or db.funEnabled ~= true then
		return
	end
	local token, faction = LockRemindersFunRace()
	if not LockRemindersFunMatches(token, faction) then
		return
	end
	local now = GetTime()
	if LockRemindersFun.last and now - LockRemindersFun.last < 0.3 then
		return
	end
	LockRemindersFunPlay(false)
end

function LockRemindersRefreshFun()
	local bar = panel and panel.funBar
	if not bar or not db then
		return
	end
	LockRemindersPaintToggle(bar.toggle, db.funEnabled == true)
	LockRemindersPaintChoiceRow(bar.emotes, db.funEmote or "CHICKEN")
	local races = db.funRaces
	if type(races) ~= "table" then
		races = {}
	end
	local buttons = bar.races or {}
	for index = 1, #buttons do
		local button = buttons[index]
		local on = races[button.raceId] == true
		if on then
			Paint(button, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
			button.label:SetTextColor(1, 0.93, 0.72)
		else
			Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
			button.label:SetTextColor(0.86, 0.82, 0.94)
		end
	end
end

function LockRemindersBuildFun(owner)
	local bar = LockRemindersOpenSettings(owner, "funBar")
	LockRemindersFun.emotes = {
		{ "CHICKEN", "Chicken" },
		{ "SPIT", "Spit" },
		{ "RUDE", "Rude" },
		{ "LAUGH", "Laugh" },
		{ "RANDOM", "Random" },
	}
	LockRemindersFun.raceList = {
		{ "Human", "Human" },
		{ "Dwarf", "Dwarf" },
		{ "NightElf", "Night Elf" },
		{ "Gnome", "Gnome" },
		{ "Orc", "Orc" },
		{ "Scourge", "Undead" },
		{ "Tauren", "Tauren" },
		{ "Troll", "Troll" },
		{ "Skyborne:Alliance", "High Order" },
		{ "Skyborne:Horde", "Windshaper" },
	}

	LockRemindersSettingsHead(bar, "Rivals")
	local enable = LockRemindersSettingsCard(bar, 50, "Interface\\Icons\\Spell_Magic_PolymorphChicken", "Auto emote", "Rival players")
	bar.toggle = CreateFrame("Button", nil, enable, "BackdropTemplate")
	bar.toggle:SetSize(48, 22)
	bar.toggle:SetPoint("TOPLEFT", 176, -14)
	bar.toggle.label = bar.toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.toggle.label:SetPoint("CENTER")
	bar.toggle:SetScript("OnClick", function()
		db.funEnabled = not (db.funEnabled == true)
		LockRemindersRefreshFun()
	end)
	local test = LockRemindersSettingsButton(enable, bar.toggle, "Test", 12, function()
		LockRemindersFunPlay(true)
	end)
	test:SetSize(64, 22)

	local emote = LockRemindersSettingsCard(bar, 50, "Interface\\Icons\\Ability_Rogue_Disguise", "Emote", "One")
	bar.emotes = {}
	local previous = nil
	for index = 1, #LockRemindersFun.emotes do
		local spec = LockRemindersFun.emotes[index]
		local button = CreateFrame("Button", nil, emote, "BackdropTemplate")
		button:SetSize(76, 22)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
		else
			button:SetPoint("TOPLEFT", 176, -14)
		end
		button.choiceId = spec[1]
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button.label:SetText(spec[2])
		button:SetScript("OnClick", function()
			db.funEmote = spec[1]
			LockRemindersRefreshFun()
		end)
		button:EnableMouseWheel(true)
		button:SetScript("OnMouseWheel", bar.wheel)
		bar.emotes[index] = button
		previous = button
	end

	local races = LockRemindersSettingsCard(bar, 108, "Interface\\Icons\\Spell_Shadow_Charm", "Races", "Any selected")
	bar.races = {}
	for index = 1, #LockRemindersFun.raceList do
		local spec = LockRemindersFun.raceList[index]
		local col = (index - 1) % 4
		local row = math.floor((index - 1) / 4)
		local button = CreateFrame("Button", nil, races, "BackdropTemplate")
		button:SetSize(108, 22)
		button:SetPoint("TOPLEFT", 176 + col * 116, -14 - row * 28)
		button.raceId = spec[1]
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button.label:SetText(spec[2])
		button:SetScript("OnClick", function()
			if type(db.funRaces) ~= "table" then
				db.funRaces = {}
			end
			db.funRaces[spec[1]] = not db.funRaces[spec[1]]
			if db.funRaces[spec[1]] ~= true then
				db.funRaces[spec[1]] = nil
			end
			LockRemindersRefreshFun()
		end)
		button:EnableMouseWheel(true)
		button:SetScript("OnMouseWheel", bar.wheel)
		bar.races[index] = button
	end
	LockRemindersSettingsFinish(bar)
end

function LockRemindersBuildMisc(owner)
	local bar = LockRemindersOpenSettings(owner, "miscBar")

	local function toggle(parent, field, x, y)
		local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
		button:SetSize(48, 22)
		button:SetPoint("TOPLEFT", x, y)
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button.label:SetText("On")
		button:SetScript("OnClick", function()
			db[field] = not (db[field] ~= false)
			if field == "speedShow" then
				LockRemindersUpdateSpeed()
			end
			LockRemindersRefreshMisc()
		end)
		return button
	end

	LockRemindersSettingsHead(bar, "Movement")
	local speed = LockRemindersSettingsCard(bar, 82, "Interface\\Icons\\Ability_Rogue_Sprint", "Speed", "You / target")
	bar.speedToggle = toggle(speed, "speedShow", 176, -14)
	local speedSizeLabel = LockRemindersSettingsCaption(speed, bar.speedToggle, "Size", 12)
	local speedPlus
	speedPlus, bar.speedSize = LockRemindersSettingsStepper(speed, speedSizeLabel, 8, function()
		return db.speedSize or 18
	end, function(value)
		db.speedSize = value
		LockRemindersApplySpeedLook()
		LockRemindersRefreshMisc()
	end, 12, 48, 2)
	bar.speedMove = LockRemindersSettingsButton(speed, speedPlus, "Move", 12, function()
		LockRemindersSetSpeedMove(not LockRemindersMisc.speedMoving)
		LockRemindersRefreshMisc()
	end)
	bar.speedColor = LockRemindersGlowSwatch(speed, bar.speedMove, 12, "speedColor", 1, 0.96, 0.9, function()
		LockRemindersApplySpeedLook()
		LockRemindersRefreshMisc()
	end)
	if bar.speedColor.caption then
		bar.speedColor.caption:SetText("Text")
	end
	local together = CreateFrame("Button", nil, speed, "BackdropTemplate")
	together:SetSize(84, 22)
	together:SetPoint("TOPLEFT", 176, -50)
	together.choiceId = "together"
	together.label = together:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	together.label:SetPoint("CENTER")
	together.label:SetText("Together")
	local split = CreateFrame("Button", nil, speed, "BackdropTemplate")
	split:SetSize(72, 22)
	split:SetPoint("LEFT", together, "RIGHT", 8, 0)
	split.choiceId = "split"
	split.label = split:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	split.label:SetPoint("CENTER")
	split.label:SetText("Split")
	local function pickLayout(self)
		db.speedSplit = self.choiceId == "split"
		LockRemindersApplySpeedLook()
		LockRemindersSetSpeedMove(LockRemindersMisc.speedMoving)
	end
	together:SetScript("OnClick", pickLayout)
	split:SetScript("OnClick", pickLayout)
	bar.speedLayout = { together, split }

	LockRemindersSettingsFinish(bar)
end

function CreateMiscAlerts()
	if LockRemindersMisc.speed then
		return
	end
	local speed = CreateFrame("Frame", "LockRemindersSpeed", UIParent, "BackdropTemplate")
	speed:SetFrameStrata("HIGH")
	speed:SetClampedToScreen(true)
	speed:SetMovable(true)
	speed:EnableMouse(true)
	speed:RegisterForDrag("LeftButton")
	speed:SetScript("OnDragStart", function(self)
		if LockRemindersMisc.speedMoving then
			self:StartMoving()
		end
	end)
	speed:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveNamedPoint(self, "speedPoint")
	end)
	speed:SetBackdrop(BACKDROP)
	speed:SetBackdropColor(0, 0, 0, 0)
	speed:SetBackdropBorderColor(0, 0, 0, 0)
	speed.text = speed:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	speed.text:SetPoint("CENTER")
	speed.text:SetJustifyH("CENTER")
	speed.text:SetTextColor(1, 0.96, 0.9)
	speed.text:SetShadowColor(0, 0, 0, 1)
	speed.text:SetShadowOffset(1, -1)
	speed.text:SetText("-- / --")
	speed.hint = speed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	speed.hint:SetPoint("TOP", speed, "BOTTOM", 0, -2)
	speed.hint:SetText("Drag")
	speed.hint:SetTextColor(0.85, 0.75, 1)
	speed.hint:Hide()
	speed:EnableMouse(false)
	local target = CreateFrame("Frame", "LockRemindersSpeedTarget", UIParent, "BackdropTemplate")
	target:SetFrameStrata("HIGH")
	target:SetClampedToScreen(true)
	target:SetMovable(true)
	target:EnableMouse(true)
	target:RegisterForDrag("LeftButton")
	target:SetScript("OnDragStart", function(self)
		if LockRemindersMisc.speedMoving then
			self:StartMoving()
		end
	end)
	target:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveNamedPoint(self, "speedTargetPoint")
	end)
	target:SetBackdrop(BACKDROP)
	target:SetBackdropColor(0, 0, 0, 0)
	target:SetBackdropBorderColor(0, 0, 0, 0)
	target.text = target:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	target.text:SetPoint("CENTER")
	target.text:SetJustifyH("CENTER")
	target.text:SetTextColor(0.7, 0.9, 1)
	target.text:SetShadowColor(0, 0, 0, 1)
	target.text:SetShadowOffset(1, -1)
	target.text:SetText("--")
	target.hint = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	target.hint:SetPoint("TOP", target, "BOTTOM", 0, -2)
	target.hint:SetText("Target")
	target.hint:SetTextColor(0.7, 0.9, 1)
	target.hint:Hide()
	target:EnableMouse(false)
	target:Hide()
	speed.target = target
	speed.hint:SetText("You")
	LockRemindersMisc.speed = speed
	LockRemindersApplySpeedLook()
	LockRemindersApplyNamedPoint(speed, "speedPoint", { "CENTER", "CENTER", 0, -160 })
	LockRemindersApplyNamedPoint(target, "speedTargetPoint", { "CENTER", "CENTER", 90, -160 })
	-- Hide a leftover vital frame from older addon versions.
	local oldVital = _G.LockRemindersVital
	if oldVital then
		oldVital:Hide()
		oldVital:SetParent(nil)
	end
	LockRemindersUpdateSpeed()
end

function LockRemindersSecret(value)
	if value == nil then
		return false
	end
	-- Prefer canaccessvalue when present (oUF/ElvUI Forever path).
	if canaccessvalue then
		local ok, access = pcall(canaccessvalue, value)
		if ok then
			return not access
		end
	end
	if not issecretvalue then
		return false
	end
	local ok, secret = pcall(issecretvalue, value)
	-- If the checker errors, do not treat the value as secret.
	if not ok then
		return false
	end
	return secret and true or false
end

function LockRemindersSecretEquals(value, expected)
	if value == nil or expected == nil then
		return nil
	end
	if not LockRemindersSecret(value) and not LockRemindersSecret(expected) then
		return value == expected
	end
	if not C_CurveUtil or not C_CurveUtil.EvaluateColorValueFromBoolean then
		return nil
	end
	local ok, bit = pcall(function()
		return C_CurveUtil.EvaluateColorValueFromBoolean(value == expected, 1, 0)
	end)
	if not ok or bit == nil or LockRemindersSecret(bit) then
		return nil
	end
	if type(bit) == "table" then
		bit = bit.r or bit[1]
	end
	if bit == nil or LockRemindersSecret(bit) then
		return nil
	end
	bit = tonumber(bit)
	if bit == 1 then
		return true
	end
	if bit == 0 then
		return false
	end
	return nil
end

function LockRemindersSecretRemaining(expires)
	if expires == nil then
		return nil
	end
	if not LockRemindersSecret(expires) then
		expires = tonumber(expires)
		if not expires or expires <= 0 then
			return nil
		end
		local left = expires - GetTime()
		if left < 0 then
			return 0
		end
		return left
	end
	if not C_CurveUtil or not C_CurveUtil.EvaluateColorValueFromBoolean then
		return nil
	end
	local now = GetTime()
	local function greaterThan(bound)
		local proved, bit = pcall(function()
			return C_CurveUtil.EvaluateColorValueFromBoolean(expires > (now + bound), 1, 0)
		end)
		if not proved or bit == nil or LockRemindersSecret(bit) then
			return nil
		end
		if type(bit) == "table" then
			bit = bit.r or bit[1]
		end
		if bit == nil or LockRemindersSecret(bit) then
			return nil
		end
		bit = tonumber(bit)
		if bit == 1 then
			return true
		end
		if bit == 0 then
			return false
		end
		return nil
	end
	local alive = greaterThan(0)
	if alive == nil then
		return nil
	end
	if not alive then
		return 0
	end
	local over = greaterThan(1800)
	if over == nil then
		return nil
	end
	local lo, hi = 0, 1800
	if over then
		lo = 1800
		hi = 7200
		local past = greaterThan(7200)
		if past == nil or past then
			return nil
		end
	end
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		local above = greaterThan(mid)
		if above == nil then
			return nil
		end
		if above then
			lo = mid
		else
			hi = mid
		end
	end
	return hi
end

function LockRemindersIsInterrupt(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID == 19244 or spellID == 19647 or spellID == 19648 or spellID == 19650 or spellID == 20433 or spellID == 20434 or spellID == 24259 or spellID == 119910 or spellID == 132409 then
		return true
	end
	local wanted = Normalize(spellName or "")
	return wanted == "spell lock" or wanted == "bloqueo de hechizo" or wanted == "bloquear hechizo"
end

function LockRemindersIsDevourMagic(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID == 19505 or spellID == 19731 or spellID == 19734 or spellID == 19736 or spellID == 27276 or spellID == 27277 or spellID == 48011 then
		return true
	end
	local wanted = Normalize(spellName or "")
	return wanted == "devour magic" or wanted == "devorar magia" or wanted:find("devour magic", 1, true) or wanted:find("devorar magia", 1, true)
end

function LockRemindersIsSeduction(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID == 6358 then
		return true
	end
	local wanted = Normalize(spellName or "")
	return wanted == "seduction" or wanted == "seduccion"
end

function LockRemindersIsAuraSpell(spellID, spellName)
	if LockRemindersIsInterrupt(spellID, spellName) then
		return true
	end
	local wanted = Normalize(spellName or "")
	if wanted == "" and spellID then
		wanted = Normalize(SpellName(spellID) or "")
	end
	if wanted == "fear" or wanted:find("^fear rank", 1, true) or wanted:find("^fear(", 1, true) then
		return true
	end
	if wanted == "howl of terror" or wanted == "banish" or wanted == "seduction" or wanted == "seduccion" then
		return true
	end
	if wanted:find("^curse of ", 1, true) or wanted:find("^bane of ", 1, true) or wanted:find("^maldicion de ", 1, true) or wanted:find("^corruption", 1, true) or wanted:find("^corrupcion", 1, true) then
		return true
	end
	if wanted == "agony" or wanted == "agonia" or wanted:find("agony", 1, true) or wanted:find("agonia", 1, true) then
		return true
	end
	if wanted == "immolate" or wanted == "inmolar" or wanted == "unstable affliction" or wanted == "afliccion inestable" then
		return true
	end
	spellID = tonumber(spellID)
	return spellID == 980 or spellID == 1014 or spellID == 6217 or spellID == 11711 or spellID == 11712 or spellID == 11713 or spellID == 5782 or spellID == 6213 or spellID == 6215 or spellID == 5484 or spellID == 17928 or spellID == 710 or spellID == 18647 or spellID == 6358
end

function LockRemindersSpellTravels(spellID, spellName)
	local wanted = Normalize(spellName or "")
	if wanted == "" and spellID then
		wanted = Normalize(SpellName(spellID) or "")
	end
	if wanted == "shadow bolt" or wanted:sub(1, 12) == "shadow bolt " or wanted:sub(1, 12) == "shadow bolt(" then
		return true
	end
	if wanted == "descarga de las sombras" or wanted:sub(1, 24) == "descarga de las sombras " then
		return true
	end
	if wanted == "soul fire" or wanted:sub(1, 10) == "soul fire " or wanted:sub(1, 10) == "soul fire(" then
		return true
	end
	if wanted == "fuego de alma" or wanted:sub(1, 14) == "fuego de alma " or wanted == "fuego del alma" or wanted:sub(1, 15) == "fuego del alma " then
		return true
	end
	if wanted == "incinerate" or wanted:sub(1, 11) == "incinerate " or wanted:sub(1, 11) == "incinerate(" or wanted == "incinerar" or wanted:sub(1, 10) == "incinerar " then
		return true
	end
	if wanted == "chaos bolt" or wanted:sub(1, 11) == "chaos bolt " or wanted == "descarga de caos" or wanted:sub(1, 17) == "descarga de caos " then
		return true
	end
	if wanted == "haunt" or wanted:sub(1, 6) == "haunt " or wanted:sub(1, 6) == "haunt(" then
		return true
	end
	if wanted == "immolate" or wanted:sub(1, 9) == "immolate " or wanted:sub(1, 9) == "immolate(" then
		return true
	end
	if wanted == "inmolar" or wanted:sub(1, 8) == "inmolar " or wanted:sub(1, 8) == "inmolar(" then
		return true
	end
	if wanted == "seed of corruption" or wanted:sub(1, 18) == "seed of corruption" then
		return true
	end
	if wanted == "semilla de corrupcion" or wanted:sub(1, 21) == "semilla de corrupcion" then
		return true
	end
	spellID = tonumber(spellID)
	if spellID == 686 or spellID == 695 or spellID == 705 or spellID == 1088 or spellID == 1106 or spellID == 7641
		or spellID == 11659 or spellID == 11660 or spellID == 11661 or spellID == 25307 or spellID == 27209
		or spellID == 47808 or spellID == 47809 or spellID == 6353 or spellID == 17924 or spellID == 27211
		or spellID == 30545 or spellID == 47824 or spellID == 47825 or spellID == 29722 or spellID == 32231
		or spellID == 47837 or spellID == 47838 or spellID == 50796 or spellID == 59170 or spellID == 59171
		or spellID == 59172 or spellID == 48181 or spellID == 59161 or spellID == 59163 or spellID == 59164 then
		return true
	end
	return spellID == 348 or spellID == 707 or spellID == 1094 or spellID == 2941
		or spellID == 11665 or spellID == 11667 or spellID == 11668 or spellID == 25309
		or spellID == 27215 or spellID == 47810 or spellID == 47811
		or spellID == 27243 or spellID == 47835 or spellID == 47836
end

function LockRemindersCcAimUnit(preferPet)
	local picks
	if preferPet then
		picks = { "pettarget", "mouseover", "focus", "target" }
	else
		picks = { "mouseover", "focus", "target" }
	end
	for index = 1, #picks do
		local aim = picks[index]
		if UnitExists and UnitExists(aim) then
			local hostile = true
			if UnitCanAttack then
				local ok, can = pcall(UnitCanAttack, "player", aim)
				if ok and can == false and not LockRemindersSecret(can) then
					hostile = false
				end
			end
			if hostile then
				return aim
			end
		end
	end
	if preferPet and UnitExists and UnitExists("pettarget") then
		return "pettarget"
	end
	if UnitExists and UnitExists("target") then
		return "target"
	end
	return preferPet and "pettarget" or "target"
end

function LockRemindersCcStampKey(aim)
	if not aim then
		return nil, nil
	end
	local guid = LockRemindersMissGuid(aim)
	if guid then
		return guid, aim
	end
	if UnitName then
		local ok, name = pcall(UnitName, aim)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			return "name:" .. Normalize(name), aim
		end
	end
	return "aim:" .. tostring(aim), aim
end

function LockRemindersNoteCast(unit, first, second, third)
	if unit ~= "player" and unit ~= "pet" then
		return
	end
	local secrets = {}
	local function keep(value)
		if value == nil then
			return nil
		end
		if LockRemindersSecret(value) then
			secrets[#secrets + 1] = value
			return nil
		end
		return value
	end
	first = keep(first)
	second = keep(second)
	third = keep(third)
	local spellID = tonumber(third) or tonumber(second) or tonumber(first)
	local spellName
	if type(first) == "string" and first ~= "" and not first:find("-", 1, true) then
		spellName = first
	elseif type(second) == "string" and second ~= "" and not second:find("-", 1, true) then
		spellName = second
	elseif spellID then
		spellName = SpellName(spellID)
	end
	if not spellID and db and type(db.missSpells) == "table" then
		for key in pairs(db.missSpells) do
			local saved = tonumber(key)
			if saved then
				local aliases = SpellAliases(saved)
				for index = 1, #secrets do
					if LockRemindersSameSpell(secrets[index], saved) then
						spellID = saved
						break
					end
					for alias = 1, #aliases do
						if LockRemindersSameSpell(secrets[index], aliases[alias]) then
							spellID = saved
							break
						end
					end
					if spellID then
						break
					end
				end
			end
			if spellID then
				break
			end
		end
	end
	if not spellID and #secrets > 0 then
		local known = { 5782, 6213, 6215, 710, 18647 }
		for index = 1, #secrets do
			for idIndex = 1, #known do
				if LockRemindersSameSpell(secrets[index], known[idIndex]) then
					spellID = known[idIndex]
					break
				end
			end
			if spellID then
				break
			end
		end
	end
	if spellID and (type(spellName) ~= "string" or spellName == "" or spellName:find("^Spell ", 1, true) or spellName:find("^Hechizo ", 1, true)) then
		local named = SpellName(spellID)
		if type(named) == "string" and named ~= "" then
			spellName = named
		end
	end
	local secretID = secrets[1]
	if not spellID and (type(spellName) ~= "string" or spellName == "") and not secretID then
		return
	end
	local now = GetTime()
	local kept = {}
	local casts = LockRemindersMiss.casts or {}
	for index = 1, #casts do
		if now - (casts[index].at or 0) <= 4 then
			kept[#kept + 1] = casts[index]
		end
	end
	local aim = LockRemindersCcAimUnit(unit == "pet")
	local target = select(1, LockRemindersCcStampKey(aim))
	kept[#kept + 1] = {
		spellID = spellID,
		secretID = secretID,
		name = spellName,
		kind = unit == "pet" and "pet" or "player",
		at = now,
		target = target,
		aim = aim,
		interrupt = LockRemindersIsInterrupt(spellID, spellName) or nil,
		aura = LockRemindersIsAuraSpell(spellID, spellName) or nil,
		dot = LockRemindersDebuffIsDot(spellName) or LockRemindersSpellIsCorruption(spellID) or nil,
		travel = LockRemindersSpellTravels(spellID, spellName) or nil,
		aoe = LockRemindersIsAoeSpell(spellID, spellName) or nil,
		school = LockRemindersSpellSchool(spellID, spellName),
	}
	LockRemindersMiss.casts = kept
	if unit == "player" and LockRemindersBanishMatch(spellID, spellName) then
		local key = target or ("cast:" .. tostring(now))
		LockRemindersWarlock.ends = LockRemindersWarlock.ends or {}
		LockRemindersWarlock.guess = LockRemindersWarlock.guess or {}
		LockRemindersWarlock.applied = LockRemindersWarlock.applied or {}
		LockRemindersWarlock.ends[key] = now + (spellID == 710 and 20 or 30)
		LockRemindersWarlock.guess[key] = true
		LockRemindersWarlock.applied[key] = now
		if UnitName and aim then
			local ok, name = pcall(UnitName, aim)
			if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
				LockRemindersWarlock.names = LockRemindersWarlock.names or {}
				LockRemindersWarlock.names[key] = name
			end
		end
		pcall(LockRemindersUpdateClassAlerts)
	end
	if unit == "player" and LockRemindersFearMatch(spellID, spellName) then
		local key = target or ("cast:" .. tostring(now))
		LockRemindersWarlock.fearData = LockRemindersWarlock.fearData or {}
		local fearData = LockRemindersWarlock.fearData
		fearData.ends = fearData.ends or {}
		fearData.guess = fearData.guess or {}
		fearData.applied = fearData.applied or {}
		fearData.ends[key] = now + LockRemindersFearSeconds(spellID)
		fearData.guess[key] = true
		fearData.applied[key] = now
		if UnitName and aim then
			local ok, name = pcall(UnitName, aim)
			if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
				fearData.names = fearData.names or {}
				fearData.names[key] = name
			end
		end
		pcall(LockRemindersUpdateClassAlerts)
	end
end

function LockRemindersIsAoeSpell(spellID, spellName)
	local wanted = Normalize(spellName or "")
	if wanted == "" and spellID then
		wanted = Normalize(SpellName(spellID) or "")
	end
	if wanted == "howl of terror" or wanted:find("^howl of terror", 1, true) or wanted == "aullido de terror" or wanted:find("^aullido de terror", 1, true) then
		return true
	end
	spellID = tonumber(spellID)
	return spellID == 5484 or spellID == 17928
end

function LockRemindersMissGuid(unit)
	if not unit or not UnitGUID then
		return nil
	end
	local ok, guid = pcall(UnitGUID, unit)
	if ok and type(guid) == "string" and guid ~= "" and not LockRemindersSecret(guid) then
		return guid
	end
end

function LockRemindersMissSame(unit, other, guid, otherGuid)
	if unit and other and unit == other then
		return true
	end
	if guid and otherGuid and guid == otherGuid then
		return true
	end
	if unit and other and UnitIsUnit then
		local ok, same = pcall(UnitIsUnit, unit, other)
		if ok and same == true and not LockRemindersSecret(same) then
			return true
		end
	end
	return false
end

function LockRemindersMissWatchedGuid(guid)
	if not guid then
		return false
	end
	local now = GetTime()
	local casts = LockRemindersMiss.casts or {}
	for index = #casts, 1, -1 do
		local cast = casts[index]
		if now - (cast.at or 0) > 4 then
			return false
		end
		if cast.target == guid and not cast.used and not cast.landed then
			return true
		end
	end
	return false
end

function LockRemindersSecretAmountZero(amount)
	if not C_CurveUtil or not C_CurveUtil.CreateCurve or not amount then
		return nil
	end
	local curve = LockRemindersMiss.zeroCurve
	if not curve then
		local ok, created = pcall(C_CurveUtil.CreateCurve)
		if not ok or not created or not created.AddPoint then
			return nil
		end
		if created.SetType and Enum and Enum.LuaCurveType then
			pcall(created.SetType, created, Enum.LuaCurveType.Step)
		end
		created:AddPoint(0, 1)
		created:AddPoint(1, 0)
		LockRemindersMiss.zeroCurve = created
		curve = created
	end
	if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
		local proved, bit = pcall(function()
			return C_CurveUtil.EvaluateColorValueFromBoolean(amount == 0, 1, 0)
		end)
		if proved and type(bit) == "table" then
			bit = bit.r or bit[1]
		end
		if proved and bit ~= nil and not LockRemindersSecret(bit) then
			bit = tonumber(bit)
			if bit == 1 then
				return true
			end
			if bit == 0 then
				return false
			end
		end
	end
	local ok, value = pcall(curve.Evaluate, curve, amount)
	if ok and value ~= nil and not LockRemindersSecret(value) then
		value = tonumber(value)
		-- A secret that the curve cannot read falls on the zero point and
		-- looks like a miss. A plain non-zero is the only curve result to trust.
		if value and value < 0.5 then
			return false
		end
	end
	return nil
end

function LockRemindersDebuffIsDot(name)
	name = Normalize(name or "")
	if name == "" then
		return false
	end
	if name:find("agony", 1, true) or name:find("agonia", 1, true) then
		return true
	end
	if name:find("corruption", 1, true) or name:find("corrupcion", 1, true) then
		return true
	end
	if name:find("immolate", 1, true) or name:find("inmolar", 1, true) then
		return true
	end
	if name:find("unstable affliction", 1, true) or name:find("afliccion inestable", 1, true) then
		return true
	end
	if name:find("siphon life", 1, true) or name:find("succion de vida", 1, true) then
		return true
	end
	if name:find("seed of corruption", 1, true) or name:find("semilla de corrupcion", 1, true) then
		return true
	end
	return false
end

function LockRemindersSpellIsCorruption(spellID)
	spellID = tonumber(spellID)
	return spellID == 172 or spellID == 6222 or spellID == 6223 or spellID == 7648 or spellID == 11671 or spellID == 11672 or spellID == 25311 or spellID == 27216 or spellID == 47812 or spellID == 47813
end

function LockRemindersTargetHasDot(unit)
	if not unit or not UnitExists or not UnitExists(unit) then
		return nil
	end
	local function scan(read)
		local sawEnd = false
		for index = 1, 40 do
			local ok, aura, name = read(index)
			if not ok or LockRemindersSecret(aura) then
				return nil
			end
			if aura == nil or aura == false then
				sawEnd = true
				break
			end
			if LockRemindersDebuffIsDot(name) then
				return true
			end
		end
		if sawEnd then
			return false
		end
		return nil
	end
	if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
		local result = scan(function(index)
			local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, index)
			if not ok or LockRemindersSecret(aura) then
				return false, aura, nil
			end
			if aura == nil or aura == false then
				return true, nil, nil
			end
			return true, aura, aura.name
		end)
		if result ~= nil then
			return result
		end
	end
	if UnitDebuff then
		return scan(function(index)
			local ok, name = pcall(UnitDebuff, unit, index)
			if not ok then
				return false, name, nil
			end
			if name == nil or name == false or name == "" then
				return true, nil, nil
			end
			return true, name, name
		end)
	end
	return nil
end

function LockRemindersCastIsDot(cast)
	if not cast then
		return false
	end
	if cast.dot or LockRemindersDebuffIsDot(cast.name) or LockRemindersSpellIsCorruption(cast.spellID) then
		return true
	end
	return LockRemindersDebuffIsDot(cast.spellID and SpellName(cast.spellID))
end

function LockRemindersDotPresent(unit, spellID, spellName)
	if not unit or not UnitExists or not UnitExists(unit) then
		return nil
	end
	local wanted = Normalize(spellName or "")
	if wanted == "" and spellID then
		wanted = Normalize(SpellName(spellID) or "")
	end
	if wanted == "" and not tonumber(spellID) then
		return nil
	end
	local aliases = spellID and SpellAliases(spellID) or {}
	local function same(id, name)
		if id and not LockRemindersSecret(id) then
			id = tonumber(id)
			if spellID and id == tonumber(spellID) then
				return true
			end
			for index = 1, #aliases do
				if id == aliases[index] then
					return true
				end
			end
		end
		return wanted ~= "" and type(name) == "string" and not LockRemindersSecret(name) and Normalize(name) == wanted
	end
	local function scan(read)
		local sawEnd = false
		for index = 1, 40 do
			local ok, aura, name, id = read(index)
			if not ok or LockRemindersSecret(aura) then
				return nil
			end
			if aura == nil or aura == false then
				sawEnd = true
				break
			end
			local nameKnown = type(name) == "string" and name ~= "" and not LockRemindersSecret(name)
			local idKnown = id ~= nil and not LockRemindersSecret(id)
			if not nameKnown and not idKnown then
				return nil
			end
			if same(id, name) then
				return true
			end
		end
		if sawEnd then
			return false
		end
		return nil
	end
	if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
		return scan(function(index)
			local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, index)
			if not ok or LockRemindersSecret(aura) then
				return false, aura, nil, nil
			end
			if aura == nil or aura == false then
				return true, nil, nil, nil
			end
			return true, aura, aura.name, aura.spellId or aura.spellID
		end)
	end
	if UnitDebuff then
		return scan(function(index)
			local ok, name, _, _, _, _, _, _, _, _, _, id = pcall(UnitDebuff, unit, index)
			return ok, name, name, id
		end)
	end
	return nil
end

function LockRemindersMagicBurstIsDirect(events, hasDot, now)
	local burst, older = {}, {}
	for index = 1, #events do
		local event = events[index]
		local age = now - (event.at or 0)
		if age >= -0.05 and age <= 0.5 then
			burst[#burst + 1] = event
		elseif age > 0.5 and age <= 8 then
			older[#older + 1] = event
		end
	end
	if #burst == 0 then
		return false
	end
	local function similar(a, b)
		if not a or not b or a <= 0 or b <= 0 then
			return false
		end
		local ratio = a / b
		if ratio < 1 then
			ratio = b / a
		end
		return ratio <= 1.85
	end
	local function isTick(amount, at)
		for index = 1, #older do
			local event = older[index]
			local gap = (at or now) - (event.at or 0)
			if gap >= 1.15 and gap <= 3.9 and similar(amount, event.amount) then
				return true
			end
		end
		return false
	end
	local maxAmount, second, maxAt = 0, 0, now
	local distinct = {}
	for index = 1, #burst do
		local amount = burst[index].amount or 0
		if amount > maxAmount then
			second = maxAmount
			maxAmount = amount
			maxAt = burst[index].at or now
		elseif amount > second then
			second = amount
		end
		local known = false
		for seen = 1, #distinct do
			if similar(amount, distinct[seen]) then
				known = true
				break
			end
		end
		if not known and amount > 0 then
			distinct[#distinct + 1] = amount
		end
	end
	if maxAmount <= 0 or isTick(maxAmount, maxAt) then
		return false
	end
	if #distinct >= 3 and second > 0 and maxAmount >= second * 2 then
		return true
	end
	local clusters, olderMax = {}, 0
	for index = 1, #older do
		local amount = older[index].amount or 0
		if amount > olderMax then
			olderMax = amount
		end
	local found = false
		for cluster = 1, #clusters do
			if similar(amount, clusters[cluster]) then
				found = true
				if amount > clusters[cluster] then
					clusters[cluster] = amount
				end
				break
			end
		end
		if not found and amount > 0 then
			clusters[#clusters + 1] = amount
		end
	end
	if #clusters >= 2 and olderMax > 0 and maxAmount >= olderMax * 2 and not similar(maxAmount, olderMax) then
		return true
	end
	if #clusters >= 1 and olderMax > 0 and maxAmount >= olderMax * 5 then
		return true
	end
	if hasDot == false and #clusters == 0 and second == 0 then
		return true
	end
	return false
end

function LockRemindersNewestDirectCast(unit, before)
	local guid = LockRemindersMissGuid(unit)
	local now = GetTime()
	local casts = LockRemindersMiss.casts or {}
	for index = #casts, 1, -1 do
		local cast = casts[index]
		local at = cast.at or 0
		local aimed = cast.aoe or not cast.target or not guid or cast.target == guid
		local fresh = not before or at <= before + 0.02
		local flew = not cast.travel or not before or (before - at) >= 0.12
		if fresh and flew and not cast.landed and not cast.interrupt and (not cast.aura or cast.travel) and aimed and now - at <= 3.5 and LockRemindersMissSpellSaved(cast.spellID, cast.name) then
			return cast
		end
	end
end

function LockRemindersRetireDirectCast(unit, at)
	local cast = LockRemindersNewestDirectCast(unit, at)
	if not cast then
		return
	end
	cast.landed = true
	local held = LockRemindersMiss.held
	if held and held.cast == cast then
		held.cancel = true
	end
	LockRemindersMiss.hitAt = GetTime()
	LockRemindersMiss.hitUnit = unit
	LockRemindersMiss.hitGuid = LockRemindersMissGuid(unit)
end

function LockRemindersRecordMagicDamage(unit, amount)
	amount = tonumber(amount)
	if not amount or amount <= 0 or not unit then
		return
	end
	local guid = LockRemindersMissGuid(unit) or unit
	local now = GetTime()
	LockRemindersMiss.magic = LockRemindersMiss.magic or {}
	local row = LockRemindersMiss.magic[guid]
	if not row then
		row = { events = {} }
		LockRemindersMiss.magic[guid] = row
	end
	local events = row.events
	local last = events[#events]
	if last and last.amount == amount and now - (last.at or 0) < 0.08 then
		return
	end
	local kept = {}
	for index = 1, #events do
		if now - (events[index].at or 0) <= 8 then
			kept[#kept + 1] = events[index]
		end
	end
	kept[#kept + 1] = { at = now, amount = amount }
	row.events = kept
	row.unit = unit
	row.token = (row.token or 0) + 1
	local token = row.token
	local function resolve()
		if row.token ~= token then
			return
		end
		local stamp = GetTime()
		if not LockRemindersMagicBurstIsDirect(row.events, LockRemindersTargetHasDot(row.unit), stamp) then
			return
		end
		local hitAt, best = stamp, 0
		local samples = row.events
		for index = 1, #samples do
			local event = samples[index]
			if stamp - (event.at or 0) <= 0.5 and (event.amount or 0) >= best then
				best = event.amount
				hitAt = event.at or stamp
			end
		end
		LockRemindersRetireDirectCast(row.unit, hitAt)
	end
	if not C_Timer or not C_Timer.After then
		resolve()
		return
	end
	C_Timer.After(0.28, resolve)
end

function LockRemindersMissDelay(cast, now)
	local wait = 0.35
	if cast and (cast.aura or cast.dot or LockRemindersCastIsDot(cast)) then
		-- Forever often reveals DoTs a beat late; wait before calling it a miss.
		wait = 0.85
	elseif cast and cast.aura then
		wait = 0.45
	end
	if cast and cast.travel then
		local due = (cast.at or now) + 1.4 - now
		if due > wait then
			wait = due
		end
		if wait > 2.2 then
			wait = 2.2
		end
	end
	return wait
end

function LockRemindersMissWatchUnit(unit)
	if type(unit) ~= "string" or unit == "" then
		return false
	end
	if unit == "target" or unit == "pettarget" or unit == "focus" then
		return true
	end
	if unit:find("^nameplate%d") and UnitIsUnit then
		local ok, same = pcall(UnitIsUnit, unit, "target")
		if ok and same == true and not LockRemindersSecret(same) then
			return true
		end
		ok, same = pcall(UnitIsUnit, unit, "pettarget")
		if ok and same == true and not LockRemindersSecret(same) then
			return true
		end
	end
	return false
end

function LockRemindersAuraBlocksMiss(unit, cast)
	if not cast then
		return false
	end
	-- Fresh apply when timers are readable.
	if LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, cast.at, true) then
		return true
	end
	-- Forever often secrets duration/expires. If the DoT/aura is on the target at all,
	-- do not fire a miss (false "missed" while the debuff is clearly up).
	if LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, nil, false) then
		return true
	end
	local present = LockRemindersDotPresent(unit, cast.spellID, cast.name)
	if present == true then
		return true
	end
	return false
end

function LockRemindersQueueMissAlert(unit, cast, missType)
	if not cast or not missType or not C_Timer or not C_Timer.After then
		if cast then
			LockRemindersShowMissCast(cast, unit, missType)
		end
		return
	end
	if cast.landed or cast.used then
		return
	end
	-- Spell already on the target: this "miss" was something else.
	if LockRemindersAuraBlocksMiss(unit, cast) then
		cast.landed = true
		return
	end
	cast.used = true
	local now = GetTime()
	local guid = LockRemindersMissGuid(unit)
	local wait = LockRemindersMissDelay(cast, now)
	local held = {
		cast = cast,
		unit = unit,
		guid = guid,
		missType = missType,
		at = now,
		cancel = false,
	}
	LockRemindersMiss.held = held
	C_Timer.After(wait, function()
		if LockRemindersMiss.held == held then
			LockRemindersMiss.held = nil
		end
		if held.cancel or cast.landed then
			cast.used = nil
			return
		end
		if LockRemindersAuraBlocksMiss(unit, cast) then
			cast.landed = true
			cast.used = nil
			return
		end
		local hitAt = LockRemindersMiss.hitAt
		if hitAt and hitAt >= (held.at or 0) - 0.02 then
			if LockRemindersMissSame(LockRemindersMiss.hitUnit, unit, LockRemindersMiss.hitGuid, guid) then
				cast.landed = true
				cast.used = nil
				return
			end
		end
		if missType == "IMMUNE" and cast.target then
			if LockRemindersBanishMatch(cast.spellID, cast.name) then
				if LockRemindersWarlock.ends then
					LockRemindersWarlock.ends[cast.target] = nil
				end
				if LockRemindersWarlock.guess then
					LockRemindersWarlock.guess[cast.target] = nil
				end
			end
			if LockRemindersFearMatch(cast.spellID, cast.name) and LockRemindersWarlock.fearData then
				if LockRemindersWarlock.fearData.ends then
					LockRemindersWarlock.fearData.ends[cast.target] = nil
				end
				if LockRemindersWarlock.fearData.guess then
					LockRemindersWarlock.fearData.guess[cast.target] = nil
				end
			end
		end
		LockRemindersShowMissCast(cast, unit, missType)
	end)
end

function LockRemindersScheduleHitRetire(unit, cast)
	if not cast or not C_Timer or not C_Timer.After then
		return
	end
	local guid = LockRemindersMissGuid(unit)
	local mark = GetTime()
	C_Timer.After(0.12, function()
		if cast.used or cast.landed then
			return
		end
		local missAt = LockRemindersMiss.missAt
		local missGuid = LockRemindersMiss.missGuid
		if missAt and missAt >= mark - 0.02 and (not guid or not missGuid or missGuid == guid) then
			return
		end
		cast.landed = true
	end)
end

function LockRemindersNoteAura(unit, info)
	if type(unit) ~= "string" or unit == "" or unit == "player" or unit == "pet" or unit == "vehicle" then
		return
	end
	local guid = LockRemindersMissGuid(unit)
	local now = GetTime()
	local added = type(info) == "table" and not LockRemindersSecret(info) and info.addedAuras
	local removed = type(info) == "table" and not LockRemindersSecret(info) and info.removedAuras
	if type(removed) == "table" and not LockRemindersSecret(removed) then
		for auraIndex = 1, #removed do
			local aura = removed[auraIndex]
			if type(aura) == "table" then
				local id, name
				pcall(function()
					id = aura.spellId or aura.spellID
					name = aura.name
				end)
				if LockRemindersFearMatch and LockRemindersFearMatch(id, name) then
					LockRemindersClearCcGuid(guid, "fear")
				elseif LockRemindersBanishMatch and LockRemindersBanishMatch(id, name) then
					LockRemindersClearCcGuid(guid, "banish")
				end
			end
		end
	end
	local casts = LockRemindersMiss.casts or {}
	for index = #casts, 1, -1 do
		local cast = casts[index]
		if now - (cast.at or 0) > 1 then
			return
		end
		local aimed = cast.aoe or not cast.target or not guid or cast.target == guid
		if cast.aura and not cast.landed and aimed then
			local landed = false
			if type(added) == "table" and not LockRemindersSecret(added) then
				for auraIndex = 1, #added do
					local aura = added[auraIndex]
					if type(aura) == "table" and not LockRemindersSecret(aura) then
						local id = aura.spellId or aura.spellID
						local name = aura.name
						if not LockRemindersSecret(id) and cast.spellID and tonumber(id) == tonumber(cast.spellID) then
							landed = true
						elseif type(name) == "string" and not LockRemindersSecret(name) and cast.name and Normalize(name) == Normalize(cast.name) then
							landed = true
						end
					end
				end
			elseif LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, cast.at, true) then
				landed = true
			end
			if landed then
				cast.landed = true
				local held = LockRemindersMiss.held
				if held and held.cast == cast then
					held.cancel = true
				end
			end
		end
	end
end

function LockRemindersMissUnit(unit, kind)
	if type(unit) ~= "string" or unit == "" or unit == "player" or unit == "pet" then
		return false
	end
	if unit == "target" or unit == "pettarget" then
		return true
	end
	if unit:find("^nameplate%d") then
		return true
	end
	return LockRemindersMissWatchedGuid(LockRemindersMissGuid(unit))
end

function LockRemindersUnitHasSpell(unit, spellID, spellName, since, freshOnly)
	if not unit or not UnitExists or not UnitExists(unit) then
		return false
	end
	local wanted = Normalize(spellName or "")
	if wanted == "" or wanted:find("^spell ", 1, true) or wanted:find("^hechizo ", 1, true) then
		wanted = ""
	end
	local aliases = spellID and SpellAliases(spellID) or {}
	local function matches(id, name, duration, expires)
		local same = false
		if id and not LockRemindersSecret(id) then
			id = tonumber(id)
			if spellID and id == tonumber(spellID) then
				same = true
			end
			for index = 1, #aliases do
				if id == aliases[index] then
					same = true
				end
			end
		end
		if not same and wanted ~= "" and type(name) == "string" and not LockRemindersSecret(name) and Normalize(name) == wanted then
			same = true
		end
		if not same then
			return false
		end
		duration = tonumber(duration)
		expires = tonumber(expires)
		if since and duration and expires and duration > 0 and expires > 0 then
			local applied = expires - duration
			if applied + 0.4 < since then
				return false
			end
		elseif freshOnly then
			return false
		end
		return true
	end
	if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
	for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, index)
			if not ok or aura == nil or aura == false or LockRemindersSecret(aura) then
			break
		end
			local id = aura.spellId or aura.spellID
			local duration = aura.duration
			local expires = aura.expirationTime
			if LockRemindersSecret(duration) then
				duration = nil
			end
			if LockRemindersSecret(expires) then
				expires = nil
			end
			if matches(id, aura.name, duration, expires) then
				return true
			end
		end
	end
	if UnitDebuff then
		for index = 1, 40 do
			local ok, name, _, _, _, _, duration, expires, _, _, _, id = pcall(UnitDebuff, unit, index)
			if not ok or name == nil or name == false or name == "" then
				break
			end
			if LockRemindersSecret(duration) then
				duration = nil
			end
			if LockRemindersSecret(expires) then
				expires = nil
			end
			if matches(id, name, duration, expires) then
				return true
			end
		end
	end
	if spellID and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, unit, spellID, "HARMFUL")
		if ok and type(aura) == "table" and not LockRemindersSecret(aura) then
			local duration = aura.duration
			local expires = aura.expirationTime
			if LockRemindersSecret(duration) then
				duration = nil
			end
			if LockRemindersSecret(expires) then
				expires = nil
			end
			if matches(aura.spellId or aura.spellID or spellID, aura.name, duration, expires) then
				return true
			end
		end
	end
	return false
end

function LockRemindersSchoolOverlaps(eventSchool, spellSchool)
	eventSchool = tonumber(eventSchool)
	spellSchool = tonumber(spellSchool)
	if not eventSchool or not spellSchool or eventSchool == 1 or spellSchool == 1 then
		return false
	end
	if bit and bit.band then
		return bit.band(eventSchool, spellSchool) ~= 0
	end
	return eventSchool == spellSchool
end

function LockRemindersSpellSchool(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID and C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
		if ok and type(info) == "table" and not LockRemindersSecret(info) then
			local school = tonumber(info.school) or tonumber(info.schoolMask)
			if school and school > 1 and not LockRemindersSecret(school) then
				return school
			end
		end
	end
	local wanted = Normalize(spellName or "")
	if wanted == "" and spellID then
		wanted = Normalize(SpellName(spellID) or "")
	end
	if wanted == "" then
		return nil
	end
	if wanted:find("fire", 1, true) or wanted:find("fuego", 1, true) or wanted:find("immol", 1, true) or wanted:find("inmol", 1, true) or wanted:find("inciner", 1, true) or wanted:find("conflag", 1, true) or wanted:find("searing", 1, true) or wanted:find("abrasad", 1, true) or wanted:find("hellfire", 1, true) or wanted:find("infierno", 1, true) or wanted:find("chaos bolt", 1, true) or wanted:find("descarga de caos", 1, true) then
		return 4
	end
	if wanted:find("frost", 1, true) or wanted:find("escarch", 1, true) or wanted:find("hielo", 1, true) then
		return 16
	end
	if wanted:find("arcane", 1, true) or wanted:find("arcano", 1, true) then
		return 64
	end
	if wanted:find("holy", 1, true) or wanted:find("sagrad", 1, true) then
		return 2
	end
	if wanted:find("nature", 1, true) or wanted:find("naturale", 1, true) then
		return 8
	end
	if wanted:find("shadow", 1, true) or wanted:find("sombra", 1, true) or wanted:find("torment", 1, true) or wanted:find("agony", 1, true) or wanted:find("agonia", 1, true) or wanted:find("corrupt", 1, true) or wanted:find("curse", 1, true) or wanted:find("maldicion", 1, true) or wanted:find("fear", 1, true) or wanted:find("miedo", 1, true) or wanted:find("drain", 1, true) or wanted:find("drenar", 1, true) or wanted:find("banish", 1, true) or wanted:find("destierr", 1, true) or wanted:find("haunt", 1, true) or wanted:find("lash", 1, true) or wanted:find("spell lock", 1, true) or wanted:find("suffering", 1, true) or wanted:find("sufrimiento", 1, true) then
		return 32
	end
end

function LockRemindersTakeMissCast(unit, eventSchool, woundMiss, schoolMagic)
	local now = GetTime()
	local guid
	if unit and UnitGUID then
		local ok, value = pcall(UnitGUID, unit)
		if ok and type(value) == "string" and value ~= "" and not LockRemindersSecret(value) then
			guid = value
		end
	end
	local casts = LockRemindersMiss.casts or {}
	for index = #casts, 1, -1 do
		local cast = casts[index]
		local aimed = not cast.target or not guid or cast.target == guid
		if cast.aoe then
			aimed = true
			if UnitCanAttack then
				local ok, attack = pcall(UnitCanAttack, "player", unit)
				if ok and attack == false then
					aimed = false
				end
			end
		end
		local age = now - (cast.at or 0)
		local limit = 3.5
		if cast.interrupt then
			limit = 2
		elseif cast.travel then
			limit = 3.5
		elseif cast.aura then
			limit = (LockRemindersCastIsDot(cast) and not woundMiss) and 2.5 or 1.2
		end
		local castSchool = cast.school or LockRemindersSpellSchool(cast.spellID, cast.name)
		local schoolOk = false
		if eventSchool and eventSchool ~= 1 then
			schoolOk = not castSchool or LockRemindersSchoolOverlaps(eventSchool, castSchool)
		elseif schoolMagic then
			-- Explicit RESIST/IMMUNE only — never steal a DoT cast from a melee swing miss.
			schoolOk = not eventSchool or eventSchool ~= 1
			if eventSchool and eventSchool ~= 1 and castSchool then
				schoolOk = LockRemindersSchoolOverlaps(eventSchool, castSchool) or not castSchool
			end
		elseif not eventSchool and cast.travel and age >= 0.08 and age <= limit then
			schoolOk = true
		elseif not eventSchool and not cast.travel and age <= (LockRemindersCastIsDot(cast) and 1.2 or 0.45) then
			schoolOk = true
		end
		-- Physical school 1 is melee; do not attach it to shadow DoTs (false misses in combat).
		if eventSchool == 1 then
			schoolOk = false
		end
		local saved = LockRemindersMissSpellSaved(cast.spellID or cast.secretID, cast.name)
		if schoolOk and not cast.used and not cast.landed and aimed and age <= limit and saved and LockRemindersMissUnit(unit, cast.kind) then
			if LockRemindersAuraBlocksMiss(unit, cast) then
				cast.landed = true
			else
				return cast
			end
		end
	end
end

function LockRemindersNoteInterrupted(unit, first, second, third, wasInterrupted)
	if type(unit) ~= "string" or unit == "" or LockRemindersSecret(unit) then
		return
	end
	-- Player cast interrupt/fail: do not touch Fear/Banish timers. Forever can fire
	-- FAILED/INTERRUPTED around a successful Fear and would wipe the alert.
	if unit == "player" or unit == "pet" then
		return
	end
	if wasInterrupted then
		pcall(LockRemindersPetNoteInterrupt, unit)
	end
	local watched = unit == "target" or unit == "pettarget"
	if not watched and unit:find("^nameplate%d") and UnitIsUnit then
		local ok, same = pcall(UnitIsUnit, unit, "target")
		if ok and same == true and not LockRemindersSecret(same) then
			watched = true
		end
		if not watched then
			ok, same = pcall(UnitIsUnit, unit, "pettarget")
			if ok and same == true and not LockRemindersSecret(same) then
				watched = true
			end
		end
	end
	if not watched and not LockRemindersMissWatchedGuid(LockRemindersMissGuid(unit)) then
		return
	end
	local guid
	if UnitGUID then
		local ok, value = pcall(UnitGUID, unit)
		if ok and type(value) == "string" and value ~= "" and not LockRemindersSecret(value) then
			guid = value
		end
	end
	local now = GetTime()
	LockRemindersMiss.interruptedAt = now
	LockRemindersMiss.interruptedUnit = unit
	local casts = LockRemindersMiss.casts or {}
	for index = 1, #casts do
		local cast = casts[index]
		local aimed = not guid or not cast.target or cast.target == guid
		if cast.interrupt and aimed and now - (cast.at or 0) <= 2 then
			cast.landed = true
		end
	end
	local held = LockRemindersMiss.held
	if held and held.interrupt then
		local same = held.unit == unit
		if not same and UnitIsUnit then
			local ok, value = pcall(UnitIsUnit, held.unit, unit)
			same = ok and value == true and not LockRemindersSecret(value)
		end
		if same then
			held.cancel = true
		end
	end
end

function LockRemindersShowRecentMiss(unit, missType)
	if not LockRemindersMissWatchUnit(unit) then
		return
	end
	local now = GetTime()
	local guid = unit and LockRemindersMissGuid(unit) or nil
	local casts = LockRemindersMiss.casts or {}
	local function tryCast(cast)
		if not cast or cast.used or cast.landed then
			return false
		end
		local age = now - (cast.at or 0)
		if age > 4 then
			return false
		end
		local aimed = cast.aoe or not guid or not cast.target or cast.target == guid
		if not aimed then
			return false
		end
		local saved = missType == "IMMUNE" or LockRemindersMissSpellSaved(cast.spellID or cast.secretID, cast.name)
		if not saved and cast.secretID then
			saved = LockRemindersMissSpellSaved(cast.secretID, cast.name)
		end
		if not saved then
			return false
		end
		if LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, cast.at, true) then
			cast.landed = true
			return false
		end
		LockRemindersQueueMissAlert(unit, cast, missType)
		return true
	end
	for index = #casts, 1, -1 do
		if tryCast(casts[index]) then
			return
		end
	end
end

function LockRemindersResolveCombatToken(value)
	if value == nil then
		return nil
	end
	if LockRemindersSecret(value) then
		local names = { "MISS", "MISSED", "RESIST", "RESISTED", "IMMUNE", "WOUND", "HEAL", "DODGE", "PARRY", "BLOCK", "ABSORB", "EVADE", "DEFLECT", "REFLECT" }
		for index = 1, #names do
			if LockRemindersSecretEquals(value, names[index]) then
				return names[index]
			end
		end
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end
	return value:upper()
end

function LockRemindersHandleUnitCombat(unit, action, flag, amount, school)
	if not db then
		return
	end
	if LockRemindersSecret(unit) or type(unit) ~= "string" or unit == "" then
		return
	end
	-- Outgoing misses land on the enemy unit (CombatTextPlus). Ignore self.
	if unit == "player" or unit == "pet" or unit == "vehicle" then
		return
	end
	action = LockRemindersResolveCombatToken(action)
	flag = LockRemindersResolveCombatToken(flag)
	local rawAmount = amount
	local amountSecret = LockRemindersSecret(amount)
	if amountSecret then
		amount = nil
		local zero = LockRemindersSecretAmountZero(rawAmount)
		if zero == true then
			amount = 0
		elseif zero == false then
			amount = 1
		end
	elseif amount ~= nil then
		amount = tonumber(amount)
	end
	if LockRemindersSecret(school) then
		school = nil
	else
		school = tonumber(school)
		if school == 0 then
			school = nil
		end
	end
	if not LockRemindersMissFlags then
		LockRemindersMissFlags = {
			ABSORB = true, BLOCK = true, IMMUNE = true, DODGE = true,
			PARRY = true, DEFLECT = true, EVADE = true, REFLECT = true,
		}
	end
	-- CombatTextPlus: action itself is MISS/RESIST/IMMUNE (not WOUND). Trust that.
	local missType
	local woundMiss = false
	local explicit = false
	if action == "IMMUNE" or (action ~= "WOUND" and flag == "IMMUNE") then
		missType = "IMMUNE"
		explicit = true
	elseif action == "RESIST" or action == "RESISTED" then
		missType = "RESIST"
		explicit = true
	elseif action == "MISS" or action == "MISSED" then
		missType = "MISS"
		explicit = true
	elseif action == "WOUND" then
		local ignored = flag and LockRemindersMissFlags[flag] and flag ~= "IMMUNE"
		if flag == "IMMUNE" and (amount == 0 or amount == nil) then
			missType = "IMMUNE"
			explicit = true
		elseif flag == "RESIST" or flag == "RESISTED" then
			local fullMiss = amount == 0 or amount == nil
			if fullMiss and not ignored then
				missType = "RESIST"
				woundMiss = true
			end
		elseif flag == "MISS" or flag == "MISSED" then
			local fullMiss = amount == 0 or amount == nil
			if fullMiss and not ignored then
				missType = "MISS"
				woundMiss = true
			end
		elseif amount == 0 and not ignored then
			missType = "MISS"
			woundMiss = true
		end
		if not missType then
			if not ignored and type(amount) == "number" and amount > 0 then
				pcall(LockRemindersNoteCcDamage, unit)
			end
			local connected = type(amount) == "number" and amount > 0 and school ~= 1 and not ignored and not amountSecret
			if connected then
				LockRemindersRecordMagicDamage(unit, amount)
			end
			return
		end
	elseif not action and (flag == "MISS" or flag == "MISSED" or flag == "RESIST" or flag == "RESISTED" or flag == "IMMUNE") then
		if flag == "IMMUNE" then
			missType = "IMMUNE"
		elseif flag == "RESIST" or flag == "RESISTED" then
			missType = "RESIST"
		else
			missType = "MISS"
		end
		explicit = true
	elseif not action and amount == 0 and school ~= 1 then
		missType = (flag == "RESIST" or flag == "RESISTED") and "RESIST" or "MISS"
	end
	if not missType then
		return
	end
	if missType == "IMMUNE" and db.immuneAlert == false then
		return
	end
	-- Only your current target (or its nameplate). Other plates' misses are not yours.
	if not LockRemindersMissWatchUnit(unit) then
		return
	end
	-- Partial resist that still deals damage is a hit, not a fail.
	if missType == "RESIST" and type(amount) == "number" and amount > 0 then
		return
	end
	-- Physical swing miss must not steal a pending DoT / Fear cast.
	if missType == "MISS" and school == 1 then
		return
	end
	LockRemindersMiss.missAt = GetTime()
	LockRemindersMiss.missGuid = LockRemindersMissGuid(unit)
	local schoolMagic = missType == "RESIST" or missType == "IMMUNE"
	local cast = LockRemindersTakeMissCast(unit, school, woundMiss, schoolMagic)
	if cast then
		LockRemindersQueueMissAlert(unit, cast, missType)
		return
	end
	if missType == "IMMUNE" then
		cast = LockRemindersTakeImmuneCast(unit)
		if cast then
			LockRemindersQueueMissAlert(unit, cast, "IMMUNE")
			return
		end
	end
	-- No recent tracked cast: do not guess from unrelated combat text.
	-- Named spell misses still come from chat ("Your Bane of Agony Missed …").
end

function LockRemindersTakeImmuneCast(unit)
	local now = GetTime()
	local guid = LockRemindersMissGuid(unit)
	local casts = LockRemindersMiss.casts or {}
	for index = #casts, 1, -1 do
		local cast = casts[index]
		local aimed = not cast.target or not guid or cast.target == guid
		if cast.aoe then
			aimed = true
			if UnitCanAttack then
				local ok, attack = pcall(UnitCanAttack, "player", unit)
				if ok and attack == false then
					aimed = false
				end
			end
		end
		local age = now - (cast.at or 0)
		local limit = 3.5
		if cast.interrupt then
			limit = 2
		elseif cast.travel then
			limit = 3.5
		elseif cast.aura then
			limit = 1.2
		end
		if not cast.used and not cast.landed and aimed and age <= limit and LockRemindersMissUnit(unit, cast.kind) then
			if LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, cast.at, true) then
				cast.landed = true
			else
				return cast
			end
		end
	end
end

function LockRemindersShowImmune(unit)
	if db and db.immuneAlert == false then
		return
	end
	local cast = LockRemindersTakeImmuneCast(unit)
	if not cast then
		return
	end
	LockRemindersShowMissCast(cast, unit, "IMMUNE")
end

function LockRemindersShowMissCast(cast, unit, missType)
	local destName
	if UnitName then
		local ok, name = pcall(UnitName, unit)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			destName = name
		end
	end
	local key = tostring(cast.kind) .. ":" .. tostring(cast.spellID) .. ":" .. tostring(cast.name) .. ":" .. missType .. ":" .. tostring(destName)
	local now = GetTime()
	if key == LockRemindersMiss.lastKey and now - (LockRemindersMiss.lastAt or 0) < 0.35 then
		return
	end
	LockRemindersMiss.lastKey = key
	LockRemindersMiss.lastAt = now
	ShowSpellMiss(cast.spellID, cast.name, cast.spellID and SpellIcon(cast.spellID) or 136235, cast.kind, missType, destName)
end

function LockRemindersPlainChat(text)
	if type(text) == "table" then
		text = text.message or text.text or text.msg or text[1]
	end
	if type(text) ~= "string" or text == "" or LockRemindersSecret(text) then
		return nil
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
	text = text:gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|T.-|t", "")
	return text
end

function LockRemindersMissFromLine(text)
	text = LockRemindersPlainChat(text)
	if not text then
		return
	end
	-- Forever combat log often appends " (Missed)" / " (Resisted)".
	text = text:gsub("%s*%(%s*[Mm]issed%s*%)%s*$", "")
	text = text:gsub("%s*%(%s*[Rr]esisted%s*%)%s*$", "")
	text = text:gsub("%s*%(%s*[Ii]mmune%s*%)%s*$", "")
	local lower = text:lower()
	if lower:find(" hits ", 1, true) or lower:find(" crits ", 1, true) or lower:find(" heals ", 1, true) or lower:find(" healed ", 1, true) then
		return
	end
	local function cleanDest(dest)
		if type(dest) ~= "string" then
			return nil
		end
		dest = dest:gsub("%s*%b()", "")
		dest = dest:gsub("%.%s*$", "")
		dest = dest:gsub("^%s+", ""):gsub("%s+$", "")
		if dest == "" then
			return nil
		end
		return dest
	end
	local function cleanSpell(spell)
		if type(spell) ~= "string" then
			return nil
		end
		local owned = spell:match("^.+'s%s+(.+)$")
		if owned then
			spell = owned
		end
		spell = spell:gsub("%s*%([Rr]ank %d+%)", "")
		spell = spell:gsub("%s+[Rr]ank %d+", "")
		spell = spell:gsub("[%[%]]", "")
		spell = spell:gsub("^%s+", ""):gsub("%s+$", "")
		if spell == "" then
			return nil
		end
		return spell, owned and "pet" or nil
	end
	local yourAt = text:find("Your ", 1, true)
	local slice = yourAt and text:sub(yourAt) or ""
	local spell, dest = slice:match("^Your (.+) Missed (.+)$")
	if not spell then
		spell, dest = slice:match("^Your (.+) missed (.+)$")
	end
	if not spell then
		spell, dest = slice:match("^Your (.+) misses (.+)$")
	end
	if spell then
		local name, petKind = cleanSpell(spell)
		return "MISS", name, cleanDest(dest), petKind or "player"
	end
	spell = slice:match("^Your (.+) missed%.?$")
	if not spell then
		spell = slice:match("^Your (.+) misses%.?$")
	end
	if not spell then
		spell = slice:match("^Your (.+) Missed%.?$")
	end
	if spell then
		local name, petKind = cleanSpell(spell)
		return "MISS", name, nil, petKind or "player"
	end
	spell, dest = slice:match("^Your (.+) was resisted by (.+)$")
	if not spell then
		spell, dest = slice:match("^Your (.+) is resisted by (.+)$")
	end
	if not spell then
		spell, dest = slice:match("^Your (.+) resisted (.+)$")
	end
	if not spell then
		spell, dest = slice:match("^Your (.+) resists (.+)$")
	end
	if spell then
		local name, petKind = cleanSpell(spell)
		return "RESIST", name, cleanDest(dest), petKind or "player"
	end
	spell = slice:match("^Your (.+) was resisted%.?$")
	if not spell then
		spell = slice:match("^Your (.+) is resisted%.?$")
	end
	if spell then
		local name, petKind = cleanSpell(spell)
		return "RESIST", name, nil, petKind or "player"
	end
	dest, spell = text:match("^(.-) resisted your (.+)$")
	if not spell then
		dest, spell = text:match("^(.-) resists your (.+)$")
	end
	if spell then
		local name = cleanSpell(spell)
		return "RESIST", name, cleanDest(dest), "player"
	end
	dest, spell = text:match("^(.-) is immune to your (.+)$")
	if not spell then
		dest, spell = text:match("^(.-) are immune to your (.+)$")
	end
	if spell then
		local name = cleanSpell(spell)
		return "IMMUNE", name, cleanDest(dest), "player"
	end
	local pet
	if UnitName then
		local ok, name = pcall(UnitName, "pet")
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			pet = name
		end
	end
	local at = pet and text:find(pet .. "'s ", 1, true)
	if at then
		local rest = text:sub(at + #pet + 3)
		spell, dest = rest:match("^(.+) Missed (.+)$")
		if not spell then
			spell, dest = rest:match("^(.+) missed (.+)$")
		end
		if not spell then
			spell, dest = rest:match("^(.+) misses (.+)$")
		end
		if spell then
			local name = cleanSpell(spell)
			return "MISS", name, cleanDest(dest), "pet"
		end
		spell, dest = rest:match("^(.+) was resisted by (.+)$")
		if not spell then
			spell, dest = rest:match("^(.+) resisted (.+)$")
		end
		if spell then
			local name = cleanSpell(spell)
			return "RESIST", name, cleanDest(dest), "pet"
		end
	end
	local missWord
	if lower:find("resist", 1, true) and not lower:find(" resisted)", 1, true) and not lower:find(" resist)", 1, true) then
		missWord = "RESIST"
	elseif lower:find("immune", 1, true) then
		missWord = "IMMUNE"
	elseif lower:find(" miss", 1, true) then
		missWord = "MISS"
	end
	if not missWord or not db or type(db.missNames) ~= "table" then
		return
	end
	for _, name in pairs(db.missNames) do
		if type(name) == "string" and name ~= "" and text:find(name, 1, true) then
			local petKind
			if pet and text:find(pet, 1, true) then
				petKind = "pet"
			end
			return missWord, name, nil, petKind or "player"
		end
	end
end

function LockRemindersReadMissLine(text)
	if not db then
		return
	end
	local missType, spell, dest, kind = LockRemindersMissFromLine(text)
	-- Ignore bare "Miss"/"Resist" combat-text words: they are not yours for sure.
	if not missType or not spell then
		return
	end
	if missType == "IMMUNE" then
		if db.immuneAlert == false then
			return
		end
	elseif not LockRemindersMissSpellSaved(nil, spell) then
		return
	end
	local spellID, icon
	local wanted = Normalize(spell)
	if type(db.missNames) == "table" then
		for key, name in pairs(db.missNames) do
			if LockRemindersMissNamesEqual(name, wanted) then
				spellID = tonumber(key)
				icon = SpellIcon(spellID)
				spell = name or spell
				break
			end
		end
	end
	if not spellID and type(db.missSpells) == "table" then
		for key in pairs(db.missSpells) do
			local name = SpellName(key)
			if LockRemindersMissNamesEqual(name, wanted) then
				spellID = tonumber(key)
				icon = SpellIcon(spellID)
				spell = name or spell
				break
			end
		end
	end
	local casts = LockRemindersMiss.casts or {}
	for index = 1, #casts do
		local cast = casts[index]
		if type(cast.name) == "string" and LockRemindersMissNamesEqual(cast.name, wanted) then
			cast.used = true
			if not spellID then
				spellID = cast.spellID
				icon = cast.spellID and SpellIcon(cast.spellID)
			end
			local held = LockRemindersMiss.held
			if held and held.cast == cast then
				held.cancel = true
			end
		end
	end
	ShowSpellMiss(spellID, spell, icon or 136235, kind, missType, dest)
end

function LockRemindersWatchMissChat()
	if not hooksecurefunc then
		return
	end
	LockRemindersMissWrapped = LockRemindersMissWrapped or {}
	local function wrap(frame, method)
		local current = frame and frame[method]
		if type(current) ~= "function" or LockRemindersMissWrapped[current] then
			return
		end
		LockRemindersMissWrapped[current] = true
		hooksecurefunc(frame, method, function(_, message)
			pcall(LockRemindersReadMissLine, message)
		end)
		if frame[method] then
			LockRemindersMissWrapped[frame[method]] = true
		end
	end
	if not LockRemindersMissChatMixin and ChatFrameMixin and ChatFrameMixin.AddMessage then
		LockRemindersMissChatMixin = true
		hooksecurefunc(ChatFrameMixin, "AddMessage", function(_, message)
			pcall(LockRemindersReadMissLine, message)
		end)
	end
	if not LockRemindersMissCombatText and type(CombatText_AddMessage) == "function" then
		LockRemindersMissCombatText = true
		hooksecurefunc("CombatText_AddMessage", function(message)
			pcall(LockRemindersReadMissLine, message)
		end)
	end
	local windows = NUM_CHAT_WINDOWS or 10
	for index = 1, windows do
		local frame = _G["ChatFrame" .. index]
		wrap(frame, "AddMessage")
		wrap(frame, "OldAddMessage")
	end
end

function LockRemindersNow()
	if time then
		local ok, value = pcall(time)
		value = ok and tonumber(value) or nil
		if value and value > 1000000000 then
			return value
		end
	end
	return GetTime()
end

function LockRemindersClock(seconds)
	seconds = math.floor((tonumber(seconds) or 0) + 0.5)
	if seconds < 0 then
		seconds = 0
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function LockRemindersUnitKey(unit)
	if UnitGUID then
		local ok, guid = pcall(UnitGUID, unit)
		if ok and type(guid) == "string" and guid ~= "" and not LockRemindersSecret(guid) then
			return guid
		end
	end
	if UnitName then
		local ok, name = pcall(UnitName, unit)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			return name
		end
	end
end

function LockRemindersUnitLabel(unit, full)
	-- Forever: GetUnitName returns "First Last" as one string. UnitName / UnitNameUnmodified
	-- return first and surname separately; the second value is NOT a realm.
	if full and GetUnitName then
		local ok, name = pcall(GetUnitName, unit, false)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			return name
		end
	end
	if full and UnitNameUnmodified then
		local ok, name, surname = pcall(UnitNameUnmodified, unit)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			if type(surname) == "string" and surname ~= "" and not LockRemindersSecret(surname) then
				return name .. " " .. surname
			end
			return name
		end
	end
	if UnitName then
		local ok, name, surname = pcall(UnitName, unit)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			if full and type(surname) == "string" and surname ~= "" and not LockRemindersSecret(surname) and not tostring(surname):find("-", 1, true) then
				return name .. " " .. surname
			end
			return name
		end
	end
	return "Unknown"
end

function LockRemindersClassColor(class)
	local color = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
	if color and tonumber(color.r) then
		return color.r, color.g, color.b
	end
	return 0.9, 0.85, 1
end

function LockRemindersUnitClassFile(unit)
	if not unit or not UnitClass then
		return nil
	end
	local ok, _, classFile = pcall(UnitClass, unit)
	if ok and type(classFile) == "string" and classFile ~= "" and not LockRemindersSecret(classFile) then
		return classFile
	end
end

function LockRemindersAnnounceNameText(unit)
	-- Plain full name only. SendChatMessage auto-sends; |cff is rejected and the chat-box path needs Enter.
	local name = LockRemindersUnitLabel(unit, true)
	if type(name) ~= "string" or name == "" or LockRemindersSecret(name) then
		return "Unknown"
	end
	return name
end

function LockRemindersCooldownLeft(spellID)
	local function plain(value)
		if value == nil or LockRemindersSecret(value) then
			return nil
		end
		local ok, number = pcall(tonumber, value)
		if not ok or type(number) ~= "number" or LockRemindersSecret(number) then
			return nil
		end
		return number
	end
	local function read(first, second)
		if type(first) == "table" and not LockRemindersSecret(first) then
			return plain(first.startTime) or plain(first.start), plain(first.duration)
		end
		return plain(first), plain(second)
	end
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, first, second = pcall(C_Spell.GetSpellCooldown, spellID)
		if ok then
			local readOk, nextStart, nextDuration = pcall(read, first, second)
			if readOk then
				start, duration = nextStart, nextDuration
			end
		end
	end
	if (type(duration) ~= "number" or duration <= 5) and GetSpellCooldown then
		local ok, first, second = pcall(GetSpellCooldown, spellID)
		if ok then
			local readOk, nextStart, nextDuration = pcall(read, first, second)
			if readOk and type(nextDuration) == "number" then
				start, duration = nextStart, nextDuration
			end
		end
	end
	if type(start) == "number" and type(duration) == "number" and duration > 5 and start > 0 then
		local left = start + duration - GetTime()
		if left > 0 then
			return left, duration
		end
	end
end

function LockRemindersPlayerSoulLeft()
	local spells = { 47884, 27238, 20757, 20756, 20755, 20752, 693, 20707 }
	local bestLeft, bestDuration
	for index = 1, #spells do
		local left, duration = LockRemindersCooldownLeft(spells[index])
		if left and (not bestLeft or left > bestLeft) then
			bestLeft = left
			bestDuration = duration
		end
	end
	return bestLeft, bestDuration
end

function LockRemindersSoulBase()
	local spells = { 47884, 27238, 20757, 20756, 20755, 20752, 693 }
	if GetSpellBaseCooldown then
		for index = 1, #spells do
			local ok, ms = pcall(GetSpellBaseCooldown, spells[index])
			ms = ok and tonumber(ms) or nil
			if ms and ms > 5000 then
				return ms / 1000
			end
		end
	end
	return 900
end

function LockRemindersSoulRemaining(key)
	if not key or not db or type(db.soulCD) ~= "table" then
		return nil
	end
	local expiry = tonumber(db.soulCD[key])
	if not expiry then
		return nil
	end
	local now = LockRemindersNow()
	if expiry > 1000000000 and now < 1000000000 then
		return nil
	end
	local left = expiry - now
	if left <= 0 then
		db.soulCD[key] = nil
		if type(db.soulCDDur) == "table" then
			db.soulCDDur[key] = nil
		end
		return nil
	end
	local duration = type(db.soulCDDur) == "table" and tonumber(db.soulCDDur[key]) or nil
	return left, duration
end

function LockRemindersRememberSoul(key, seconds, duration)
	if not key or not db or not seconds or seconds <= 0 then
		return
	end
	if type(db.soulCD) ~= "table" then
		db.soulCD = {}
	end
	if type(db.soulCDDur) ~= "table" then
		db.soulCDDur = {}
	end
	local now = LockRemindersNow()
	local prev = tonumber(db.soulCD[key])
	if prev and prev > now then
		return
	end
	db.soulCD[key] = now + seconds
	db.soulCDDur[key] = duration or seconds
end

function LockRemindersHasSoulstone()
	for itemID in pairs(LockRemindersSoulItem) do
		local ok, count = pcall(ItemCount, itemID)
		if ok and (tonumber(count) or 0) > 0 then
			return true
		end
	end
	local found = false
	EachBagItem(function(itemID)
		if found then
			return
		end
		if LockRemindersSoulItem[itemID] then
			found = true
			return
		end
		local name = ItemName(itemID)
		if type(name) == "string" then
			local key = Normalize(name)
			if key:find("soulstone", 1, true) or key:find("piedra de alma", 1, true) then
				found = true
			end
		end
	end)
	return found
end

function LockRemindersReadItemCooldown(itemID)
	local function plain(value)
		if value == nil or LockRemindersSecret(value) then
			return nil
		end
		local ok, number = pcall(tonumber, value)
		if not ok or type(number) ~= "number" or LockRemindersSecret(number) then
			return nil
		end
		return number
	end
	local function take(first, second)
		if type(first) == "table" and not LockRemindersSecret(first) then
			return plain(first.startTime) or plain(first.start), plain(first.duration)
		end
		return plain(first), plain(second)
	end
	local start, duration, rawStart, rawDuration, saw
	local function accept(a, b)
		saw = true
		local ok, nextStart, nextDuration = pcall(take, a, b)
		if ok and type(nextStart) == "number" and type(nextDuration) == "number" then
			if nextDuration > 5 and nextStart > 0 then
				start, duration = nextStart, nextDuration
			end
			return
		end
		if type(a) == "table" and not LockRemindersSecret(a) then
			local fieldStart = a.startTime
			if not LockRemindersSecret(fieldStart) and fieldStart == nil then
				fieldStart = a.start
			end
			if LockRemindersSecret(fieldStart) or LockRemindersSecret(a.duration) then
				rawStart, rawDuration = fieldStart, a.duration
				return
			end
		end
		if LockRemindersSecret(a) or LockRemindersSecret(b) then
			rawStart, rawDuration = a, b
		end
	end
	local function ask(reader)
		local ok, first, second = pcall(reader)
		if not ok then
			return false
		end
		if LockRemindersSecret(first) or LockRemindersSecret(second) or (type(first) == "table" and LockRemindersSecret(first)) then
			accept(first, second)
			return true
		end
		if first == nil then
			return false
		end
		accept(first, second)
		return true
	end
	local found = false
	if C_Container and C_Container.GetItemCooldown then
		found = ask(function()
			return C_Container.GetItemCooldown(itemID)
		end)
	end
	if not found and C_Item and C_Item.GetItemCooldown then
		found = ask(function()
			return C_Item.GetItemCooldown(itemID)
		end)
	end
	if not found and GetItemCooldown then
		found = ask(function()
			return GetItemCooldown(itemID)
		end)
	end
	if not saw then
		return nil, nil, nil
	end
	if start and duration then
		local left = start + duration - GetTime()
		if left > 0 then
			return start, duration, true
		end
		return nil, nil, false
	end
	if not (LockRemindersSecret(rawStart) or LockRemindersSecret(rawDuration)) then
		return nil, nil, false
	end
	if not C_CurveUtil or not C_CurveUtil.EvaluateColorValueFromBoolean then
		return rawStart, rawDuration, nil
	end
	local ok, bit = pcall(function()
		local left = rawStart + rawDuration - GetTime()
		return C_CurveUtil.EvaluateColorValueFromBoolean(rawDuration > 5 and left > 0, 1, 0)
	end)
	if not ok or LockRemindersSecret(bit) or bit == nil then
		return rawStart, rawDuration, nil
	end
	if type(bit) == "table" then
		bit = bit.r or bit[1]
	end
	bit = tonumber(bit)
	if bit == 1 then
		return rawStart, rawDuration, true
	end
	if bit == 0 then
		return nil, nil, false
	end
	return rawStart, rawDuration, nil
end

function LockRemindersSoulItemCooldown()
	local bestStart, bestDuration
	local cooling = false
	local unknown = false
	local function keep(itemID)
		local start, duration, state = LockRemindersReadItemCooldown(itemID)
		if state == true then
			bestStart, bestDuration, cooling = start, duration, true
		elseif state == nil then
			unknown = true
		end
	end
	local counted = false
	for itemID in pairs(LockRemindersSoulItem) do
		local ok, count = pcall(ItemCount, itemID)
		if ok and (tonumber(count) or 0) > 0 then
			counted = true
			keep(itemID)
		end
	end
	if not counted then
		EachBagItem(function(itemID)
			if cooling == true then
				return
			end
			local named = LockRemindersSoulItem[itemID]
			if not named then
				local name = ItemName(itemID)
				if type(name) == "string" then
					local key = Normalize(name)
					named = key:find("soulstone", 1, true) or key:find("piedra de alma", 1, true)
				end
			end
			if named then
				keep(itemID)
			end
		end)
	end
	if cooling == true then
		return bestStart, bestDuration, true
	end
	if unknown then
		return nil, nil, nil
	end
	return nil, nil, false
end

function LockRemindersOwnSoulBuff()
	local units = { "player" }
	local grouped = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())
	if IsInRaid and IsInRaid() then
		local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
		if count > 40 then
			count = 40
		end
		for index = 1, count do
			units[#units + 1] = "raid" .. index
		end
	elseif IsInGroup and IsInGroup() then
		local count = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
		if count > 4 then
			count = 4
		end
		for index = 1, count do
			units[#units + 1] = "party" .. index
		end
	end
	if UnitExists and UnitExists("target") then
		units[#units + 1] = "target"
	end
	local playerName = LockRemindersUnitLabel("player", false)
	local otherLock = false
	local unknown = false
	for index = 1, #units do
		local unit = units[index]
		if not UnitExists or UnitExists(unit) then
			local mine = unit == "player"
			if not mine and UnitIsUnit then
				local sameOk, same = pcall(UnitIsUnit, unit, "player")
				mine = sameOk and same == true
			end
			if not mine and grouped and UnitClass then
				local ok, _, classFile = pcall(UnitClass, unit)
				if ok and not LockRemindersSecret(classFile) and classFile == "WARLOCK" then
					otherLock = true
				end
			end
			for buffIndex = 1, 40 do
				local buff = LockRemindersReadBuff(unit, buffIndex)
				if buff == false then
					break
				end
				if type(buff) == "table" and LockRemindersIsSoulAura(buff) then
					if buff.caster and UnitIsUnit then
						local ok, same = pcall(UnitIsUnit, buff.caster, "player")
						if ok and same == true then
							return true
						end
					end
					local casterName = buff.casterName
					if playerName ~= "Unknown" and type(casterName) == "string" and (casterName == playerName or casterName:match("^([^%-]+)") == playerName) then
						return true
					end
					local key = LockRemindersUnitKey(unit)
					local remembered = key and LockRemindersSoul.applied and LockRemindersSoul.applied[key]
					if remembered and playerName ~= "Unknown" and remembered.name == playerName and (not remembered.at or GetTime() - remembered.at < 1800) then
						return true
					end
					if not buff.caster and not casterName and (unit ~= "target" or not grouped) then
						unknown = true
					end
				end
			end
		end
	end
	return unknown and not otherLock
end

function LockRemindersSoulAlertMode()
	if LockRemindersHasSoulstone() then
		local start, duration, cooling = LockRemindersSoulItemCooldown()
		LockRemindersSoul.itemStart = start
		LockRemindersSoul.itemDuration = duration
		if cooling == true or (cooling == nil and LockRemindersSoul.stable == "cooling") then
			return "cooling"
		end
		return "ready"
	end
	LockRemindersSoul.itemStart = nil
	LockRemindersSoul.itemDuration = nil
	if LockRemindersOwnSoulBuff() then
		return "used"
	end
	if LockRemindersSoul.usedUntil and GetTime() < LockRemindersSoul.usedUntil then
		return "used"
	end
	return "missing"
end

function LockRemindersSoulIcon()
	local icon = SpellIcon(20707)
	if icon and icon ~= 134400 then
		return icon
	end
	return ItemIcon(5232) or 136191
end

function LockRemindersIsSoulName(name)
	if type(name) ~= "string" or name == "" or LockRemindersSecret(name) then
		return false
	end
	local key = Normalize(name)
	return key:find("soulstone", 1, true) ~= nil or key:find("piedra de alma", 1, true) ~= nil
end

function LockRemindersIsSoulSpell(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID and LockRemindersSoulCast[spellID] then
		return true
	end
	return LockRemindersIsSoulName(spellName)
end

function LockRemindersIsSoulAura(buff)
	if type(buff) ~= "table" then
		return false
	end
	if buff.spellID and LockRemindersSoulAura[buff.spellID] then
		return true
	end
	return LockRemindersIsSoulName(buff.name)
end

function LockRemindersPlainNumber(value)
	if value == nil or LockRemindersSecret(value) then
		return nil
	end
	local ok, kind = pcall(type, value)
	if not ok or kind ~= "number" then
		return nil
	end
	return value
end

function LockRemindersReadAuraField(aura, field)
	local ok, value = pcall(function()
		return aura[field]
	end)
	if not ok or value == nil or LockRemindersSecret(value) then
		return nil
	end
	return value
end

function LockRemindersReadBuff(unit, index)
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, unit, index)
		if ok and type(aura) == "table" and not LockRemindersSecret(aura) then
			local spellID = LockRemindersReadAuraField(aura, "spellId") or LockRemindersReadAuraField(aura, "spellID")
			local name = LockRemindersReadAuraField(aura, "name")
			local duration = LockRemindersPlainNumber(LockRemindersReadAuraField(aura, "duration"))
			local expires = LockRemindersPlainNumber(LockRemindersReadAuraField(aura, "expirationTime"))
			local icon = LockRemindersReadAuraField(aura, "icon")
			local caster = LockRemindersReadAuraField(aura, "sourceUnit")
			local casterName = LockRemindersReadAuraField(aura, "sourceName")
			if LockRemindersSecret(spellID) then
				spellID = nil
			end
			if LockRemindersSecret(name) or type(name) ~= "string" then
				name = nil
			end
			if LockRemindersSecret(icon) then
				icon = nil
			end
			if LockRemindersSecret(caster) or type(caster) ~= "string" then
				caster = nil
			end
			if LockRemindersSecret(casterName) or type(casterName) ~= "string" or casterName == "" then
				casterName = nil
			end
			spellID = LockRemindersPlainNumber(spellID)
			if not name and not spellID then
				return nil
			end
			return {
				spellID = spellID,
				name = name,
				icon = icon,
				duration = duration,
				expires = expires,
				caster = caster,
				casterName = casterName,
			}
		end
		if ok and (aura == nil or aura == false) then
			return false
		end
	end
	if not UnitBuff then
		return false
	end
	local ok, name, _, icon, _, _, duration, expires, caster = pcall(UnitBuff, unit, index)
	if not ok then
		return false
	end
	if name == nil or name == false or name == "" then
		return false
	end
	if LockRemindersSecret(name) then
		return nil
	end
	duration = LockRemindersPlainNumber(duration)
	expires = LockRemindersPlainNumber(expires)
	if LockRemindersSecret(icon) then
		icon = nil
	end
	if LockRemindersSecret(caster) or type(caster) ~= "string" then
		caster = nil
	end
	return {
		name = name,
		icon = icon,
		duration = duration,
		expires = expires,
		caster = caster,
	}
end

function LockRemindersIsSoulApplySpell(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID and LockRemindersSoulAura[spellID] then
		return true
	end
	if type(spellName) ~= "string" or spellName == "" then
		return false
	end
	local lowered = Normalize(spellName)
	if lowered:find("create", 1, true) or lowered:find("crear", 1, true) then
		return false
	end
	return LockRemindersIsSoulName(spellName)
end

function LockRemindersSoulCastAim()
	local picks = { "mouseover", "target", "focus" }
	for index = 1, #picks do
		local unit = picks[index]
		if UnitExists and UnitExists(unit) then
			local okFriend, friend = UnitIsFriend and pcall(UnitIsFriend, "player", unit)
			if okFriend and friend == true and not LockRemindersSecret(friend) then
				return unit
			end
			local okAttack, attack = pcall(UnitCanAttack, "player", unit)
			if not (okAttack and attack == true and not LockRemindersSecret(attack)) then
				return unit
			end
		end
	end
end

function LockRemindersAnnounceChannel(partyOn, raidOn)
	if partyOn == nil then
		partyOn = true
	end
	if raidOn == nil then
		raidOn = true
	end
	local raidMembers = GetNumRaidMembers and GetNumRaidMembers() or 0
	local inRaid = (IsInRaid and IsInRaid()) or (type(raidMembers) == "number" and raidMembers > 0)
	if inRaid then
		if raidOn then
			return "RAID"
		end
		if partyOn then
			return "PARTY"
		end
		return nil
	end
	local members = GetNumGroupMembers and GetNumGroupMembers() or 0
	local partyMembers = GetNumPartyMembers and GetNumPartyMembers() or 0
	local inParty = (IsInGroup and IsInGroup()) or (type(members) == "number" and members > 0) or (type(partyMembers) == "number" and partyMembers > 0)
	if inParty and partyOn then
		return "PARTY"
	end
end

function LockRemindersFormatAnnounce(template, name)
	if type(template) ~= "string" or template == "" then
		return nil
	end
	local label = name
	if type(label) ~= "string" or label == "" then
		label = "Unknown"
	end
	if template:find("%%s") then
		return (template:gsub("%%s", function()
			return label
		end, 1))
	end
	return template
end

function LockRemindersSendAnnounce(kind, message, channel)
	if type(message) ~= "string" or message == "" or not channel or not SendChatMessage then
		return
	end
	-- Keep the body free of |cff / |H: those make SendChatMessage drop the whole line.
	message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("||", "|")
	if message == "" then
		return
	end
	local now = GetTime()
	local stamp = tostring(kind or "") .. "\0" .. channel .. "\0" .. message
	if LockRemindersSoul.announceStamp == stamp and now - (LockRemindersSoul.announceAt or 0) < 3 then
		return
	end
	LockRemindersSoul.announceStamp = stamp
	LockRemindersSoul.announceAt = now
	pcall(SendChatMessage, message, channel)
end

function LockRemindersAnnounceSoulstone(unit)
	if not db or db.soulAnnounce == false then
		return
	end
	local channel = LockRemindersAnnounceChannel(db.soulAnnounceParty ~= false, db.soulAnnounceRaid ~= false)
	if not channel then
		return
	end
	local targetName = LockRemindersAnnounceNameText(unit)
	if type(targetName) ~= "string" or targetName == "" then
		return
	end
	-- {rt3} is the purple diamond raid marker. %s is the full character name.
	local template = db.soulAnnounceMsg
	if type(template) ~= "string" or template == "" then
		template = "{rt3} Soulstone on %s {rt3}"
	end
	local message = LockRemindersFormatAnnounce(template, targetName)
	LockRemindersSendAnnounce("soul", message, channel)
end

function LockRemindersIsSummonSpell(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID == 698 or spellID == 437169 then
		return true
	end
	local key = Normalize(spellName or "")
	return key == "ritual of summoning" or key == "portal of summoning"
end

function LockRemindersSummonAim()
	local aim = LockRemindersSoulCastAim and LockRemindersSoulCastAim() or nil
	if not aim then
		aim = "target"
	end
	if not UnitExists or not UnitExists(aim) then
		return nil
	end
	if UnitIsPlayer then
		local ok, player = pcall(UnitIsPlayer, aim)
		if not (ok and player == true and not LockRemindersSecret(player)) then
			return nil
		end
	end
	if UnitCanAttack then
		local ok, attack = pcall(UnitCanAttack, "player", aim)
		if ok and attack == true and not LockRemindersSecret(attack) then
			return nil
		end
	end
	return aim
end

function LockRemindersAnnounceSummon(unit)
	if not db or db.summonAnnounce == false then
		return
	end
	local channel = LockRemindersAnnounceChannel(db.summonAnnounceParty ~= false, db.summonAnnounceRaid ~= false)
	if not channel then
		return
	end
	local targetName
	if unit then
		targetName = LockRemindersAnnounceNameText(unit)
	else
		targetName = "now"
	end
	local template = db.summonAnnounceMsg
	if type(template) ~= "string" or template == "" then
		template = "{rt3} Summoning %s - click portal {rt3}"
	end
	local message = LockRemindersFormatAnnounce(template, targetName)
	LockRemindersSendAnnounce("summon", message, channel)
end

function LockRemindersTrySummonAnnounce(spellID, spellName)
	if not db or db.summonAnnounce == false or not LockRemindersIsWarlock() then
		return
	end
	if not LockRemindersIsSummonSpell(spellID, spellName) then
		return
	end
	LockRemindersAnnounceSummon(LockRemindersSummonAim())
end

function LockRemindersResolveSoulSpell(first, second, third)
	local secrets = {}
	local function keep(value)
		if value == nil then
			return nil
		end
		if LockRemindersSecret(value) then
			secrets[#secrets + 1] = value
			return nil
		end
		return value
	end
	first = keep(first)
	second = keep(second)
	third = keep(third)
	local spellID = tonumber(third) or tonumber(second) or tonumber(first)
	local spellName
	if type(first) == "string" and first ~= "" and not first:find("-", 1, true) then
		spellName = first
	elseif type(second) == "string" and second ~= "" and not second:find("-", 1, true) then
		spellName = second
	elseif spellID then
		spellName = SpellName(spellID)
	end
	if not spellID then
		for index = 1, #secrets do
			for auraID in pairs(LockRemindersSoulAura) do
				if LockRemindersSameSpell(secrets[index], auraID) then
					spellID = auraID
					break
				end
			end
			if spellID then
				break
			end
		end
	end
	return spellID, spellName
end

function LockRemindersTrySoulAnnounce(spellID, spellName)
	if not db or db.soulAnnounce == false or not LockRemindersIsWarlock() then
		return
	end
	if not LockRemindersIsSoulApplySpell(spellID, spellName) then
		return
	end
	local aim = LockRemindersSoulCastAim()
	if not aim then
		return
	end
	LockRemindersAnnounceSoulstone(aim)
end

function LockRemindersNoteSoulStart(unit, first, second, third)
	if unit ~= "player" then
		return
	end
	local spellID, spellName = LockRemindersResolveSoulSpell(first, second, third)
	LockRemindersTrySoulAnnounce(spellID, spellName)
	LockRemindersTrySummonAnnounce(spellID, spellName)
end

function LockRemindersPollSoulAnnounce()
	if not LockRemindersIsWarlock() or not UnitCastingInfo then
		return
	end
	local ok, name, _, _, _, _, _, _, _, spellID = pcall(UnitCastingInfo, "player")
	if not ok or (name == nil and spellID == nil) then
		return
	end
	local resolvedID, resolvedName = LockRemindersResolveSoulSpell(name, nil, spellID)
	local plainName = resolvedName or (type(name) == "string" and name or nil)
	if db and db.soulAnnounce ~= false then
		LockRemindersTrySoulAnnounce(resolvedID, plainName)
	end
	if db and db.summonAnnounce ~= false then
		LockRemindersTrySummonAnnounce(resolvedID or tonumber(spellID), plainName)
	end
end

function LockRemindersNoteSoulCast(unit, first, second, third)
	if not LockRemindersIsWarlock() or type(unit) ~= "string" or unit == "" then
		return
	end
	if LockRemindersSecret(first) then
		first = nil
	end
	if LockRemindersSecret(second) then
		second = nil
	end
	if LockRemindersSecret(third) then
		third = nil
	end
	local spellID = tonumber(third) or tonumber(second) or tonumber(first)
	local spellName
	if type(first) == "string" and first ~= "" and not first:find("-", 1, true) then
		spellName = first
	elseif type(second) == "string" and second ~= "" and not second:find("-", 1, true) then
		spellName = second
	end
	if not LockRemindersIsSoulSpell(spellID, spellName) then
		return
	end
	local key = LockRemindersUnitKey(unit)
	if not key then
		return
	end
	local base = LockRemindersSoulBase()
	LockRemindersRememberSoul(key, base, base)
	local useSpell = LockRemindersIsSoulApplySpell(spellID, spellName)
	if useSpell then
		LockRemindersSoul.usedUntil = GetTime() + 8
	else
		return
	end
	local aim = unit == "player" and (LockRemindersSoulCastAim() or "target") or (unit .. "target")
	if not UnitExists or not UnitExists(aim) then
		return
	end
	local targetKey = LockRemindersUnitKey(aim)
	if not targetKey then
		return
	end
	local targetName = LockRemindersUnitLabel(aim, db and db.soulFullName ~= false)
	local casterClass
	if UnitClass then
		local ok, _, classFile = pcall(UnitClass, unit)
		if ok and type(classFile) == "string" and not LockRemindersSecret(classFile) then
			casterClass = classFile
		end
	end
	LockRemindersSoul.applied = LockRemindersSoul.applied or {}
	LockRemindersSoul.applied[targetKey] = {
		name = targetName or LockRemindersUnitLabel(unit, db and db.soulFullName ~= false),
		class = casterClass,
		at = GetTime(),
	}
end

function LockRemindersRegisterCastUnits()
	local frame = LockRemindersEvents
	if not frame or not frame.RegisterUnitEvent then
		return
	end
	local units = { "player", "pet" }
	if IsInRaid and IsInRaid() then
		local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
		if count > 40 then
			count = 40
		end
		for index = 1, count do
			units[#units + 1] = "raid" .. index
		end
	elseif IsInGroup and IsInGroup() then
		local count = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
		if count > 4 then
			count = 4
		end
		for index = 1, count do
			units[#units + 1] = "party" .. index
		end
	end
	pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_START", "player")
	pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", unpack(units))
end

function LockRemindersRegisterCombatUnits()
	local frame = LockRemindersEvents
	if not frame then
		return
	end
	-- CombatTextPlus-style: plain UNIT_COMBAT (all units). RegisterUnitEvent
	-- batches were dropping target/nameplate events on Forever.
	pcall(frame.UnregisterEvent, frame, "UNIT_COMBAT")
	pcall(frame.RegisterEvent, frame, "UNIT_COMBAT")
end

function LockRemindersSoulSnapshot()
	local units = {}
	local seen = {}
	local function add(unit, grouped)
		if not UnitExists or not UnitExists(unit) then
			return
		end
		local key = LockRemindersUnitKey(unit)
		if not key or seen[key] then
			return
		end
		seen[key] = true
		local class
		if UnitClass then
			local ok, _, classFile = pcall(UnitClass, unit)
			if ok and not LockRemindersSecret(classFile) then
				class = classFile
			end
		end
		LockRemindersSoul.classes = LockRemindersSoul.classes or {}
		if class then
			LockRemindersSoul.classes[key] = class
		elseif LockRemindersSoul.classes[key] then
			class = LockRemindersSoul.classes[key]
		end
		units[#units + 1] = {
			unit = unit,
			key = key,
			class = class,
			name = LockRemindersUnitLabel(unit, db and db.soulFullName ~= false),
			grouped = grouped and true or false,
		}
	end
	add("player", true)
	if IsInRaid and IsInRaid() then
		local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
		for index = 1, count do
			add("raid" .. index, true)
		end
	elseif IsInGroup and IsInGroup() then
		local count = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
		for index = 1, count do
			add("party" .. index, true)
		end
	end
	if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
		add("target", false)
	end
	local active = {}
	local used = {}
	for index = 1, #units do
		local info = units[index]
		for buffIndex = 1, 40 do
			local buff = LockRemindersReadBuff(info.unit, buffIndex)
			if buff == false then
				break
			end
			if type(buff) == "table" and LockRemindersIsSoulAura(buff) then
				local left, duration, ends
				LockRemindersSoul.timers = LockRemindersSoul.timers or {}
				local now = GetTime()
				local fresh = LockRemindersPlainNumber(buff.expires)
				local saved = (info.key and LockRemindersSoul.timers[info.key]) or (info.name and LockRemindersSoul.timers[info.name])
				saved = LockRemindersPlainNumber(saved)
				if fresh and fresh > now then
					ends = fresh
				elseif saved and saved > now then
					ends = saved
				end
				if ends and info.key then
					LockRemindersSoul.timers[info.key] = ends
				end
				if ends and info.name and info.name ~= "" and info.name ~= "Unknown" then
					LockRemindersSoul.timers[info.name] = ends
				end
				if ends then
					left = ends - now
					duration = LockRemindersPlainNumber(buff.duration)
					if not duration or duration <= 0 then
						duration = left
					end
				end
				if not left or left > 0 then
					local casterKey, casterName, casterClass
					if buff.caster and UnitExists and UnitExists(buff.caster) then
						casterKey = LockRemindersUnitKey(buff.caster)
						casterName = LockRemindersUnitLabel(buff.caster, db and db.soulFullName ~= false)
						if UnitClass then
							local ok, _, classFile = pcall(UnitClass, buff.caster)
							if ok and type(classFile) == "string" and not LockRemindersSecret(classFile) then
								casterClass = classFile
							end
						end
					end
					if (not casterName or casterName == "" or casterName == "Unknown") and type(buff.casterName) == "string" then
						casterName = buff.casterName
					end
					local remembered = LockRemindersSoul.applied and LockRemindersSoul.applied[info.key]
					if (not casterName or casterName == "" or casterName == "Unknown") and remembered and type(remembered.name) == "string" and remembered.name ~= "" and remembered.name ~= "Unknown" and (not remembered.at or GetTime() - remembered.at < 1800) then
						casterName = remembered.name
						casterClass = remembered.class
					end
					if casterName == "Unknown" then
						casterName = nil
					end
					if casterKey then
						used[casterKey] = true
					elseif remembered and remembered.at and GetTime() - remembered.at < 1800 then
						for unitIndex = 1, #units do
							if units[unitIndex].name == casterName then
								used[units[unitIndex].key] = true
							end
						end
					end
					active[#active + 1] = {
						name = info.name,
						class = info.class,
						icon = buff.icon or LockRemindersSoulIcon(),
						left = left,
						ends = ends,
						duration = duration,
						caster = casterName,
						casterClass = casterClass,
					}
				end
			end
		end
	end
	local unused = {}
	for index = 1, #units do
		local info = units[index]
			if info.grouped and info.class == "WARLOCK" and not used[info.key] then
			local left, duration
			if UnitIsUnit then
				local sameOk, same = pcall(UnitIsUnit, info.unit, "player")
				if sameOk and same == true then
					left, duration = LockRemindersPlayerSoulLeft()
				end
			end
			if not left then
				left, duration = LockRemindersSoulRemaining(info.key)
			end
			unused[#unused + 1] = {
				name = info.name,
				class = info.class,
				icon = LockRemindersSoulIcon(),
				left = left,
				ends = left and left > 0 and (GetTime() + left) or nil,
				duration = duration or (left and LockRemindersSoulBase()) or nil,
			}
		end
	end
	table.sort(active, function(a, b)
		return a.name < b.name
	end)
	table.sort(unused, function(a, b)
		return a.name < b.name
	end)
	return active, unused
end

function LockRemindersSoulTrackFade()
	local fade = tonumber(db and db.soulTrackFade)
	if not fade then
		fade = 92
	end
	fade = math.floor(fade + 0.5)
	if fade < 0 then
		fade = 0
	elseif fade > 100 then
		fade = 100
	end
	return fade
end

function LockRemindersSoulTrackFont()
	local size = tonumber(db and db.soulTrackFont) or 10
	if size < 10 then
		size = 10
	elseif size > 28 then
		size = 28
	end
	return size
end

function LockRemindersSetFontSize(fs, size)
	if not fs or not fs.GetFont or not fs.SetFont then
		return
	end
	local font, _, flags = fs:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	fs:SetFont(font, size, flags)
end

function LockRemindersLayoutSoulRow(row)
	local fontSize = LockRemindersSoulTrackFont()
	LockRemindersSetFontSize(row.name, fontSize)
	LockRemindersSetFontSize(row.time, math.max(8, fontSize - 3))
	row:SetHeight(math.max(40, fontSize + 28))
	local icon = math.max(28, fontSize + 14)
	row.icon:SetSize(icon, icon)
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", 4, 4)
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetJustifyV("MIDDLE")
	if row.name.SetWordWrap then
		row.name:SetWordWrap(false)
	end
	if row.by then
		row.by:Hide()
	end
	row.time:ClearAllPoints()
	row.time:SetPoint("RIGHT", -6, 4)
	row.time:SetJustifyH("RIGHT")
	row.track:ClearAllPoints()
	row.track:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -2)
	row.track:SetHeight(6)
	row.fill:ClearAllPoints()
	row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
	row.fill:SetHeight(6)
end

function LockRemindersSoulRow(index)
	local row = LockRemindersSoul.rows[index]
	if row then
		if not row.by then
			row.by = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		end
		LockRemindersLayoutSoulRow(row)
		return row
	end
	local parent = LockRemindersSoul.tracker
	row = CreateFrame("Frame", nil, parent)
	row:SetSize(236, 40)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.by = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.track = row:CreateTexture(nil, "BACKGROUND")
	row.track:SetTexture("Interface\\Buttons\\WHITE8x8")
	row.track:SetVertexColor(0.12, 0.1, 0.16, 0.95)
	row.fill = row:CreateTexture(nil, "ARTWORK")
	row.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
	LockRemindersLayoutSoulRow(row)
	LockRemindersSoul.rows[index] = row
	return row
end

function LockRemindersTickSoulRows()
	local rows = LockRemindersSoul and LockRemindersSoul.rows
	if not rows then
		return
	end
	local now = GetTime()
	for index = 1, #rows do
		local row = rows[index]
		if row:IsShown() and type(row.ends) == "number" then
			local left = row.ends - now
			if left < 0 then
				left = 0
			end
			if row.time then
				row.time:SetText(LockRemindersClock(left))
			end
			local duration = tonumber(row.duration) or 0
			if duration > 0 and row.fill and row.fill:IsShown() and row.track then
				local width = row.track:GetWidth() or 0
				if width > 0 then
					local fraction = left / duration
					if fraction < 0 then
						fraction = 0
					elseif fraction > 1 then
						fraction = 1
					end
					row.fill:SetWidth(math.max(fraction * width, 0.01))
				end
			end
		end
	end
end

function LockRemindersPaintSoulRow(row, info, kind)
	local r, g, b = LockRemindersClassColor(info.class)
	local function channel(value)
		value = tonumber(value) or 1
		if value < 0 then
			value = 0
		elseif value > 1 then
			value = 1
		end
		return math.floor(value * 255 + 0.5)
	end
	local name = info.name or ""
	if kind == "active" and type(info.caster) == "string" and info.caster ~= "" then
		local casterR, casterG, casterB = LockRemindersClassColor(info.casterClass)
		row.name:SetText(string.format("|cff%02x%02x%02x%s|r |cff%02x%02x%02x(%s)|r", channel(r), channel(g), channel(b), name, channel(casterR), channel(casterG), channel(casterB), info.caster))
		row.name:SetTextColor(1, 1, 1)
	else
		row.name:SetText(name)
		row.name:SetTextColor(r, g, b)
	end
	row.icon:SetTexture(info.icon or LockRemindersSoulIcon())
	local freshEnds = LockRemindersPlainNumber(info.ends)
	local now = GetTime()
	if freshEnds and freshEnds > now then
		row.ends = freshEnds
		row.who = info.name
	elseif row.who == info.name and type(row.ends) == "number" and row.ends > now then
		freshEnds = row.ends
	else
		row.ends = nil
		row.who = info.name
	end
	if LockRemindersPlainNumber(info.duration) then
		row.duration = info.duration
	end
	local left = (type(row.ends) == "number" and (row.ends - now)) or tonumber(info.left)
	if left and left < 0 then
		left = 0
	end
	local duration = tonumber(row.duration) or tonumber(info.duration) or 0
	local fraction = 0
	if left and left > 0 and duration > 0 then
		fraction = left / duration
	end
	if fraction < 0 then
		fraction = 0
	end
	if fraction > 1 then
		fraction = 1
	end
	row.fraction = fraction
	if kind == "active" then
		row.icon:SetVertexColor(1, 1, 1)
		row.time:SetText(left and LockRemindersClock(left) or "--")
		row.time:SetTextColor(0.95, 0.9, 1)
		row.track:Show()
		row.fill:Show()
		row.fill:SetVertexColor(0.62, 0.38, 0.95, 1)
	elseif left and left > 0 then
		row.icon:SetVertexColor(1, 0.85, 0.55)
		row.time:SetText(LockRemindersClock(left))
		row.time:SetTextColor(1, 0.82, 0.45)
		row.track:Show()
		row.fill:Show()
		row.fill:SetVertexColor(0.85, 0.55, 0.2, 1)
	else
		row.icon:SetVertexColor(0.55, 0.55, 0.55)
		row.time:SetText("Ready")
		row.time:SetTextColor(0.45, 0.9, 0.5)
		row.track:Hide()
		row.fill:Hide()
	end
	LockRemindersLayoutSoulRow(row)
	row:Show()
end

function LockRemindersApplySoulLook()
	local frame = LockRemindersSoul.alert
	if not frame or not db then
		return
	end
	local size = tonumber(db.soulSize) or 48
	if size < 32 then
		size = 32
	elseif size > 96 then
		size = 96
	end
	db.soulSize = size
	frame.icon:SetSize(size - 4, size - 4)
	LockRemindersRoundIcon(frame.icon)
	local ready = LockRemindersSoul.mode == "ready"
	local red, green, blue
	if ready then
		red, green, blue = LockRemindersReadGlow("soulReadyGlow", 0.35, 0.95, 0.45)
	else
		red, green, blue = LockRemindersReadGlow("soulGlow", 0.72, 0.4, 1)
	end
	LockRemindersFitEvenGlow(frame.glow, frame.icon, size - 4, "soulGlowSize")
	LockRemindersTintEvenGlow(frame.glow, red, green, blue)
	local label = ready and LockRemindersClassLabel("soulReadyLabel", false) or LockRemindersClassLabel("soulLabel", false)
	frame.label:SetText(label)
	frame.label:SetShown(label ~= "")
	frame.label:SetTextColor(red, green, blue)
	frame:SetSize(math.max(size + 24, math.floor(size * 2.4)), size + (label ~= "" and 30 or 8))
	local font = frame.label:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	frame.label:SetFont(font, math.max(10, math.floor(size * 0.28)), "OUTLINE")
	if frame.glow then
		if LockRemindersSoul.mode == "cooling" then
			frame.glow.quiet = true
			if frame.glow.ag then
				frame.glow.ag:Stop()
			end
			if frame.glow.plate then
				frame.glow.plate:SetAlpha(0.72)
			end
		else
			frame.glow.quiet = nil
		end
	end
	pcall(LockRemindersSyncSoulClick)
	pcall(LockRemindersSyncSoulCooldown)
end

function LockRemindersSoulCooldownText(left)
	left = tonumber(left)
	if not left or left < 0 then
		left = 0
	end
	if left >= 60 then
		return tostring(math.ceil(left / 60)) .. "m"
	end
	return tostring(math.ceil(left)) .. "s"
end

function LockRemindersSyncSoulCooldown()
	local frame = LockRemindersSoul.alert
	if not frame or not frame.icon then
		return
	end
	LockRemindersRoundIcon(frame.icon)
	if frame.cooldown then
		frame.cooldown:Hide()
	end
	local shade = frame.cdShade
	if not shade then
		shade = frame:CreateTexture(nil, "ARTWORK", nil, 5)
		shade:SetTexture("Interface\\Buttons\\WHITE8x8")
		shade:SetVertexColor(0, 0, 0, 0.58)
		frame.cdShade = shade
	end
	if frame.icon.LockRemindersMask and shade.AddMaskTexture and not shade.LockRemindersMasked then
		pcall(shade.AddMaskTexture, shade, frame.icon.LockRemindersMask)
		shade.LockRemindersMasked = true
	elseif not shade.LockRemindersMasked and frame.CreateMaskTexture and shade.AddMaskTexture then
		local mask = frame:CreateMaskTexture()
		mask:SetTexture("Interface\\COMMON\\common-iconmask")
		mask:SetAllPoints(frame.icon)
		pcall(shade.AddMaskTexture, shade, mask)
		shade.LockRemindersMask = mask
		shade.LockRemindersMasked = true
	elseif shade.LockRemindersMask then
		shade.LockRemindersMask:ClearAllPoints()
		shade.LockRemindersMask:SetAllPoints(frame.icon)
	end
	local layer = frame.cdLayer
	if not layer then
		layer = CreateFrame("Frame", nil, frame)
		layer:EnableMouse(false)
		frame.cdLayer = layer
	end
	local text = frame.cdText
	if not text then
		text = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetJustifyH("CENTER")
		text:SetJustifyV("MIDDLE")
		text:SetTextColor(1, 0.97, 0.9)
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(1, -1)
		frame.cdText = text
	end
	local size = frame.icon:GetWidth()
	if size < 8 then
		size = (tonumber(db and db.soulSize) or 48) - 4
	end
	shade:ClearAllPoints()
	shade:SetAllPoints(frame.icon)
	local base = frame:GetFrameLevel() or 1
	layer:ClearAllPoints()
	layer:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
	layer:SetSize(size, size)
	layer:SetFrameLevel(base + 12)
	text:ClearAllPoints()
	text:SetPoint("CENTER", layer, "CENTER", 0, 0)
	local font = text:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	text:SetFont(font, math.max(13, math.floor(size * 0.34)), "OUTLINE")
	if LockRemindersSoul.mode ~= "cooling" then
		shade:Hide()
		text:Hide()
		layer:Hide()
		frame.cooldownKey = nil
		return
	end
	local start = LockRemindersSoul.itemStart
	local duration = LockRemindersSoul.itemDuration
	local left
	if start ~= nil and duration ~= nil then
		if LockRemindersSecret(start) or LockRemindersSecret(duration) then
			local ok, value = pcall(function()
				return start + duration - GetTime()
			end)
			if ok and type(value) == "number" and not LockRemindersSecret(value) then
				left = value
			end
		else
			left = start + duration - GetTime()
		end
	end
	if not left or left <= 0 then
		shade:Hide()
		text:Hide()
		layer:Hide()
		return
	end
	local alpha = 0.42
	if type(duration) == "number" and duration > 0 and not LockRemindersSecret(duration) then
		alpha = 0.35 + 0.35 * math.min(1, left / duration)
	end
	shade:SetVertexColor(0, 0, 0, alpha)
	shade:Show()
	layer:Show()
	text:SetText(LockRemindersSoulCooldownText(left))
	text:Show()
end

function LockRemindersShowSoulAlert(replay)
	local frame = LockRemindersSoul.alert
	if not frame then
		return
	end
	LockRemindersApplySoulLook()
	LockRemindersApplyNamedPoint(frame, "soulPoint", { "CENTER", "CENTER", 0, 180 })
	frame.icon:SetTexture(LockRemindersSoulIcon())
	local fading = frame.fade and frame.fade:IsPlaying()
	if not frame:IsShown() or fading or replay then
		if fading then
			frame.fade:Stop()
		end
		if frame.intro and frame.intro:IsPlaying() then
			frame.intro:Stop()
		end
		frame:SetScale(1)
		frame:SetAlpha(0)
		frame:Show()
		if frame.intro then
			frame.intro:Play()
		else
			frame:SetAlpha(1)
		end
	end
	local mode = LockRemindersSoul.mode
	local prev = LockRemindersSoul.soundMode
	local quiet = LockRemindersZoneQuiet()
	local arm = mode == "missing" and prev ~= nil and prev ~= "missing"
	if replay or (arm and not quiet) then
		LockRemindersSoul.alertPlayed = true
		LockRemindersPlaySoundId(db and db.soulSound or "chiji", replay)
	end
	if mode then
		LockRemindersSoul.soundMode = mode
	end
	if frame.glow then
		if mode == "cooling" then
			frame.glow.quiet = true
			if frame.glow.ag then
				frame.glow.ag:Stop()
			end
			if frame.glow.plate then
				frame.glow.plate:SetAlpha(0.72)
			end
		else
			frame.glow.quiet = nil
			if frame.glow.ag and not frame.glow.ag:IsPlaying() then
				frame.glow.ag:Play()
			end
		end
	end
end

function LockRemindersHideSoulAlert()
	local frame = LockRemindersSoul.alert
	if not frame or LockRemindersSoul.moving or not frame:IsShown() then
		return
	end
	if frame.fade and frame.fade:IsPlaying() then
		return
	end
	if frame.intro and frame.intro:IsPlaying() then
		frame.intro:Stop()
		frame:SetScale(1)
	end
	if frame.cdShade then
		frame.cdShade:Hide()
	end
	if frame.cdText then
		frame.cdText:Hide()
	end
	if frame.cdLayer then
		frame.cdLayer:Hide()
	end
	LockRemindersSoul.alertPlayed = false
	if frame.fade then
		frame:SetAlpha(1)
		frame.fade:Play()
	else
		frame:Hide()
	end
end

function LockRemindersSetSoulMove(on)
	LockRemindersSoul.moving = on and true or false
	local frame = LockRemindersSoul.alert
	if not frame then
		return
	end
	frame.hint:SetShown(LockRemindersSoul.moving)
	frame:EnableMouse(LockRemindersSoul.moving)
	if LockRemindersSoul.moving then
		LockRemindersSoul.previewUntil = nil
		LockRemindersShowSoulAlert(false)
		frame:SetAlpha(1)
	else
		LockRemindersUpdateSoul()
	end
	LockRemindersRefreshSoul()
	LockRemindersSyncSoulClick()
end

function LockRemindersSoulCastName()
	local spells = { 47884, 27238, 20757, 20756, 20755, 20752, 693 }
	for index = 1, #spells do
		local spellID = spells[index]
		local known = false
		if IsPlayerSpell then
			local ok, result = pcall(IsPlayerSpell, spellID)
			if ok and result == true then
				known = true
			elseif ok and result == false then
				known = false
			else
				known = KnowsSpell(spellID)
			end
		else
			known = KnowsSpell(spellID)
		end
		if known then
			local name = SpellName(spellID)
			if type(name) ~= "string" or name == "" or name:find("^Spell ", 1, true) or name:find("^Hechizo ", 1, true) then
				name = nil
			end
			if not name and GetSpellInfo then
				local ok, info = pcall(GetSpellInfo, spellID)
				if ok and type(info) == "string" and info ~= "" then
					name = info
				end
			end
			if name then
				return name
			end
		end
	end
end

function LockRemindersSoulClickText()
	local items = { 36895, 22116, 16896, 16895, 16893, 16892, 5232 }
	local lines = {}
	for index = 1, #items do
		lines[#lines + 1] = "/use item:" .. items[index]
	end
	local name = LockRemindersSoulCastName()
	if name then
		lines[#lines + 1] = "/cast " .. name
	end
	return table.concat(lines, "\n")
end

function LockRemindersSyncSoulClick()
	local frame = LockRemindersSoul and LockRemindersSoul.alert
	if not frame or not frame.icon then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		return
	end
	local button = frame.click
	if not button then
		local ok, created = pcall(CreateFrame, "Button", "LockRemindersSoulClick", frame, "SecureActionButtonTemplate")
		if not ok or not created then
			return
		end
		button = created
		button:RegisterForClicks("LeftButtonUp")
		button:SetAttribute("type", "macro")
		frame.click = button
	end
	button:SetAttribute("macrotext", LockRemindersSoulClickText())
	button:ClearAllPoints()
	local size = (tonumber(db and db.soulSize) or 48) - 4
	if size < 28 then
		size = 28
	end
	button:SetSize(size, size)
	button:SetPoint("TOP", frame, "TOP", 0, -4)
	button:SetFrameLevel((frame:GetFrameLevel() or 1) + 8)
	if LockRemindersSoul.moving then
		button:EnableMouse(false)
		button:Hide()
	else
		button:EnableMouse(true)
		button:Show()
	end
end

function LockRemindersSetSoulTrackMove(on)
	LockRemindersSoul.trackMoving = on and true or false
	local frame = LockRemindersSoul.tracker
	if not frame then
		return
	end
	frame.hint:SetShown(LockRemindersSoul.trackMoving)
	frame:EnableMouse(LockRemindersSoul.trackMoving)
	if LockRemindersSoul.trackMoving then
		frame:Show()
		frame:SetBackdropBorderColor(0.85, 0.7, 1, 1)
	end
	LockRemindersApplySoulTrackLook()
	LockRemindersUpdateSoul()
	LockRemindersRefreshSoul()
end

function LockRemindersPreviewSoul()
	if LockRemindersSoul.moving then
		LockRemindersSetSoulMove(false)
	end
	LockRemindersSoul.previewUntil = GetTime() + 2.2
	LockRemindersSoul.mode = "missing"
	LockRemindersSoul.alertPlayed = false
	LockRemindersShowSoulAlert(true)
end

function LockRemindersSoulSample()
	local full = db and db.soulFullName ~= false
	local function person(first, last)
		if full then
			return first .. " " .. last
		end
		return first
	end
	local icon = LockRemindersSoulIcon()
	if not LockRemindersSoul.sampleAt then
		LockRemindersSoul.sampleAt = GetTime()
	end
	local origin = LockRemindersSoul.sampleAt
	local active = {
		{ name = person("Aldric", "Moonshade"), class = "WARLOCK", caster = person("Selene", "Darkwell"), casterClass = "WARLOCK", icon = icon, ends = origin + 1480, duration = 1800 },
		{ name = person("Vesper", "Nightfall"), class = "PRIEST", caster = person("Theron", "Blackvale"), casterClass = "WARLOCK", icon = icon, ends = origin + 640, duration = 1800 },
		{ name = person("Corvin", "Ashbane"), class = "MAGE", caster = person("Aldric", "Moonshade"), casterClass = "WARLOCK", icon = icon, ends = origin + 90, duration = 1800 },
	}
	local unused = {
		{ name = person("Selene", "Darkwell"), class = "WARLOCK", icon = icon, ends = origin + 420, duration = 900 },
		{ name = person("Theron", "Blackvale"), class = "WARLOCK", icon = icon },
	}
	return active, unused
end

function LockRemindersApplySoulTrackLook()
	local frame = LockRemindersSoul.tracker
	if not frame or not db then
		return
	end
	local size = tonumber(db.soulTrackSize) or 100
	if size < 70 then
		size = 70
	elseif size > 160 then
		size = 160
	end
	db.soulTrackSize = size
	frame:SetScale(size / 100)
	if frame.title then
		frame.title:Hide()
	end
	if frame.activeTitle then
		frame.activeTitle:Hide()
	end
	if frame.readyTitle then
		frame.readyTitle:Hide()
	end
	local fade = LockRemindersSoulTrackFade() / 100
	frame:SetBackdropColor(0.06, 0.05, 0.08, fade)
	if LockRemindersSoul.trackMoving then
		frame:SetBackdropBorderColor(0.85, 0.7, 1, 1)
	elseif db.soulTrackFrame ~= false then
		frame:SetBackdropBorderColor(0.45, 0.32, 0.62, 1)
	else
		frame:SetBackdropBorderColor(0, 0, 0, 0)
	end
end

function LockRemindersUpdateSoulTracker()
	local frame = LockRemindersSoul.tracker
	if not frame or not db then
		return
	end
	if not LockRemindersIsWarlock() then
		frame:Hide()
		return
	end
	LockRemindersApplySoulTrackLook()
	local active, unused
	if LockRemindersSoul.trackSample then
		active, unused = LockRemindersSoulSample()
	else
		active, unused = LockRemindersSoulSnapshot()
	end
	local grouped = (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid())
	local scopeOn = ScopeActive(db.soulTrackScope or { always = true })
	local show = LockRemindersSoul.trackMoving or LockRemindersSoul.trackSample or (db.soulTrack ~= false and scopeOn and (grouped or #active > 0))
	if not show then
		frame:Hide()
		return
	end
	local y = -8
	local rowIndex = 0
	local function place(list, kind)
		if #list == 0 then
			return
		end
		for index = 1, #list do
			rowIndex = rowIndex + 1
			local row = LockRemindersSoulRow(rowIndex)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 8, y)
			LockRemindersPaintSoulRow(row, list[index], kind)
			y = y - row:GetHeight() - 4
		end
	end
	place(active, "active")
	if #active > 0 and #unused > 0 then
		y = y - 10
	end
	place(unused, "ready")
	for index = rowIndex + 1, #LockRemindersSoul.rows do
		LockRemindersSoul.rows[index]:Hide()
	end
	local widest = 80
	local timeWidth = 48
	for index = 1, rowIndex do
		local row = LockRemindersSoul.rows[index]
		local textWidth = row.name:GetStringWidth() or 0
		if row.by and row.by:IsShown() then
			local byWidth = row.by:GetStringWidth() or 0
			if byWidth > textWidth then
				textWidth = byWidth
			end
		end
		if textWidth > widest then
			widest = textWidth
		end
		local clockWidth = row.time:GetStringWidth() or 0
		if clockWidth > timeWidth then
			timeWidth = clockWidth
		end
	end
	local width = math.max(260, math.min(720, widest + timeWidth + 80))
	frame:SetWidth(width)
	for index = 1, rowIndex do
		local row = LockRemindersSoul.rows[index]
		row:SetWidth(width - 16)
		local icon = math.max(28, LockRemindersSoulTrackFont() + 14)
		local barWidth = math.max(80, width - 16 - icon - 24)
		row.track:SetWidth(barWidth)
		row.name:SetWidth(math.max(width - timeWidth - 70, 60))
		if row.by then
			row.by:SetWidth(math.max(widest + 4, 60))
		end
		if row.fill:IsShown() then
			row.fill:SetWidth(math.max((row.fraction or 0) * barWidth, 0.01))
		end
	end
	if rowIndex == 0 then
		y = -36
	end
	frame:SetHeight(-y + 8)
	frame:Show()
end

function LockRemindersUpdateSoul()
	if not db or not LockRemindersIsWarlock() then
		if LockRemindersSoul.alert then
			LockRemindersSoul.alert:Hide()
		end
		if LockRemindersSoul.tracker then
			LockRemindersSoul.tracker:Hide()
		end
		if LockRemindersWarlock.banish then
			LockRemindersWarlock.banish:Hide()
		end
		if LockRemindersWarlock.fear then
			LockRemindersWarlock.fear:Hide()
		end
		if LockRemindersWarlock.shards then
			LockRemindersWarlock.shards:Hide()
		end
		return
	end
	pcall(LockRemindersPollSoulAnnounce)
	LockRemindersUpdateClassAlerts()
	pcall(LockRemindersUpdatePetAlerts)
	LockRemindersUpdateSoulTracker()
	local frame = LockRemindersSoul.alert
	if not frame or LockRemindersSoul.moving then
		return
	end
	if LockRemindersSoul.previewUntil and GetTime() < LockRemindersSoul.previewUntil then
		return
	end
	local mode
	if LockRemindersZoneQuiet() and LockRemindersSoul.zoneMode then
		mode = LockRemindersSoul.zoneMode
	else
		LockRemindersSoul.zoneMode = nil
		mode = LockRemindersSoulAlertMode()
	end
	local stable = LockRemindersSoul.stable
	if mode == "missing" and (stable == "ready" or stable == "used" or stable == "cooling") then
		LockRemindersSoul.missingAt = LockRemindersSoul.missingAt or GetTime()
		if GetTime() - LockRemindersSoul.missingAt < 2 then
			mode = stable
		end
	else
		LockRemindersSoul.missingAt = nil
	end
	LockRemindersSoul.mode = mode
	LockRemindersSoul.stable = mode
	if LockRemindersSoul.soundMode == nil then
		LockRemindersSoul.soundMode = mode
	end
	local show = db.soulAlert ~= false and ScopeActive(db.soulScope or { always = true }) and mode ~= "used" and not Blocked()
	LockRemindersSoul.missing = show
	if show then
		LockRemindersShowSoulAlert(false)
	else
		LockRemindersSoul.soundMode = mode
		LockRemindersHideSoulAlert()
	end
end

function LockRemindersStartSoul()
	if LockRemindersSoul.ticker or not C_Timer or not LockRemindersIsWarlock() then
		return
	end
	LockRemindersSoul.ticker = C_Timer.NewTicker(0.4, function()
		pcall(LockRemindersUpdateSoul)
	end)
end

function LockRemindersLockAnnounceExtras(on, party, raid, msg, msgLabel)
	local alpha = on and 1 or 0.35
	local mouse = on and true or false
	local function lockBox(box)
		if not box then
			return
		end
		box:EnableMouse(mouse)
		if box.hit and box.hit.EnableMouse then
			box.hit:EnableMouse(mouse)
		end
		box:SetAlpha(alpha)
		if box.caption and box.caption.SetAlpha then
			box.caption:SetAlpha(alpha)
		end
	end
	lockBox(party)
	lockBox(raid)
	if msg then
		if not on and msg.ClearFocus then
			msg:ClearFocus()
		end
		if on and msg.Enable then
			msg:Enable()
		elseif not on and msg.Disable then
			msg:Disable()
		else
			msg:EnableMouse(mouse)
		end
		msg:SetAlpha(alpha)
	end
	if msgLabel and msgLabel.SetAlpha then
		msgLabel:SetAlpha(alpha)
	end
end

function LockRemindersRefreshSoul()
	local bar = panel and panel.soulBar
	if not bar or not db then
		return
	end
	if bar.sizeText then
		bar.sizeText:SetText(tostring(tonumber(db.soulSize) or 48))
	end
	if bar.alertChecks then
		bar.alertChecks.refresh()
	end
	if bar.trackChecks then
		bar.trackChecks.refresh()
	end
	if bar.trackSize then
		bar.trackSize:SetText(tostring(tonumber(db.soulTrackSize) or 100))
	end
	if bar.trackFont then
		bar.trackFont:SetText(tostring(LockRemindersSoulTrackFont()))
	end
	if bar.trackFade then
		bar.trackFade:SetText(tostring(LockRemindersSoulTrackFade()))
	end
	if bar.moveButton then
		bar.moveButton.label:SetText(LockRemindersSoul.moving and "Done" or "Move")
	end
	if bar.trackMove then
		bar.trackMove.label:SetText(LockRemindersSoul.trackMoving and "Done" or "Move")
	end
	if bar.trackTest then
		bar.trackTest.label:SetText(LockRemindersSoul.trackSample and "Stop" or "Test")
	end
	if bar.fullName and bar.fullName.SetChecked then
		bar.fullName:SetChecked(db.soulFullName ~= false)
	end
	if bar.trackFrame and bar.trackFrame.SetChecked then
		bar.trackFrame:SetChecked(db.soulTrackFrame ~= false)
	end
	if bar.soulAnnounce and bar.soulAnnounce.SetChecked then
		bar.soulAnnounce:SetChecked(db.soulAnnounce ~= false)
	end
	if bar.soulAnnounceParty and bar.soulAnnounceParty.SetChecked then
		bar.soulAnnounceParty:SetChecked(db.soulAnnounceParty ~= false)
	end
	if bar.soulAnnounceRaid and bar.soulAnnounceRaid.SetChecked then
		bar.soulAnnounceRaid:SetChecked(db.soulAnnounceRaid ~= false)
	end
	if bar.soulAnnounceMsg then
		bar.soulAnnounceMsg.quiet = true
		bar.soulAnnounceMsg:SetText(type(db.soulAnnounceMsg) == "string" and db.soulAnnounceMsg ~= "" and db.soulAnnounceMsg or "{rt3} Soulstone on %s {rt3}")
		bar.soulAnnounceMsg.quiet = nil
	end
	LockRemindersLockAnnounceExtras(db.soulAnnounce ~= false, bar.soulAnnounceParty, bar.soulAnnounceRaid, bar.soulAnnounceMsg, bar.soulAnnounceMsgLabel)
	if bar.summonAnnounce and bar.summonAnnounce.SetChecked then
		bar.summonAnnounce:SetChecked(db.summonAnnounce ~= false)
	end
	if bar.summonAnnounceParty and bar.summonAnnounceParty.SetChecked then
		bar.summonAnnounceParty:SetChecked(db.summonAnnounceParty ~= false)
	end
	if bar.summonAnnounceRaid and bar.summonAnnounceRaid.SetChecked then
		bar.summonAnnounceRaid:SetChecked(db.summonAnnounceRaid ~= false)
	end
	if bar.summonAnnounceMsg then
		bar.summonAnnounceMsg.quiet = true
		bar.summonAnnounceMsg:SetText(type(db.summonAnnounceMsg) == "string" and db.summonAnnounceMsg ~= "" and db.summonAnnounceMsg or "{rt3} Summoning %s - click portal {rt3}")
		bar.summonAnnounceMsg.quiet = nil
	end
	LockRemindersLockAnnounceExtras(db.summonAnnounce ~= false, bar.summonAnnounceParty, bar.summonAnnounceRaid, bar.summonAnnounceMsg, bar.summonAnnounceMsgLabel)
	LockRemindersPaintToggle(bar.alertToggle, db.soulAlert ~= false)
	LockRemindersPaintToggle(bar.trackToggle, db.soulTrack ~= false)
	LockRemindersPaintToggle(bar.banishToggle, db.banishAlert ~= false)
	LockRemindersPaintToggle(bar.fearToggle, db.fearAlert ~= false)
	LockRemindersPaintToggle(bar.shardToggle, db.shardShow ~= false)
	if bar.banishChecks then
		bar.banishChecks.refresh()
	end
	if bar.fearChecks then
		bar.fearChecks.refresh()
	end
	if bar.shardChecks then
		bar.shardChecks.refresh()
	end
	if bar.banishWarn then
		bar.banishWarn:SetText(tostring(tonumber(db.banishWarn) or 5))
	end
	if bar.banishSize then
		bar.banishSize:SetText(tostring(tonumber(db.banishSize) or 48))
	end
	if bar.fearWarn then
		bar.fearWarn:SetText(tostring(tonumber(db.fearWarn) or 5))
	end
	if bar.fearSize then
		bar.fearSize:SetText(tostring(tonumber(db.fearSize) or 48))
	end
	if bar.shardSize then
		bar.shardSize:SetText(tostring(tonumber(db.shardSize) or 40))
	end
	if bar.soulLabel and bar.soulLabel.SetText and not bar.soulLabel:HasFocus() then
		bar.soulLabel.quiet = true
		bar.soulLabel:SetText(LockRemindersClassLabel("soulLabel", false))
		bar.soulLabel.quiet = nil
	end
	if bar.soulReadyLabel and bar.soulReadyLabel.SetText and not bar.soulReadyLabel:HasFocus() then
		bar.soulReadyLabel.quiet = true
		bar.soulReadyLabel:SetText(LockRemindersClassLabel("soulReadyLabel", false))
		bar.soulReadyLabel.quiet = nil
	end
	if bar.banishLabel and bar.banishLabel.SetText and not bar.banishLabel:HasFocus() then
		bar.banishLabel.quiet = true
		bar.banishLabel:SetText(LockRemindersClassLabel("banishLabel", false))
		bar.banishLabel.quiet = nil
	end
	if bar.fearLabel and bar.fearLabel.SetText and not bar.fearLabel:HasFocus() then
		bar.fearLabel.quiet = true
		bar.fearLabel:SetText(LockRemindersClassLabel("fearLabel", false))
		bar.fearLabel.quiet = nil
	end
	if bar.shardLabel and bar.shardLabel.SetText and not bar.shardLabel:HasFocus() then
		bar.shardLabel.quiet = true
		bar.shardLabel:SetText(LockRemindersClassLabel("shardLabel", false))
		bar.shardLabel.quiet = nil
	end
	if bar.banishMove and bar.banishMove.label then
		bar.banishMove.label:SetText(LockRemindersWarlock.banishMoving and "Done" or "Move")
	end
	if bar.banishTest and bar.banishTest.label then
		local testing = LockRemindersWarlock.banishPreview and GetTime() < LockRemindersWarlock.banishPreview
		bar.banishTest.label:SetText(testing and "Stop" or "Test")
	end
	if bar.fearMove and bar.fearMove.label then
		bar.fearMove.label:SetText(LockRemindersWarlock.fearMoving and "Done" or "Move")
	end
	if bar.fearTest and bar.fearTest.label then
		local testing = LockRemindersWarlock.fearPreview and GetTime() < LockRemindersWarlock.fearPreview
		bar.fearTest.label:SetText(testing and "Stop" or "Test")
	end
	if bar.shardMove and bar.shardMove.label then
		bar.shardMove.label:SetText(LockRemindersWarlock.shardMoving and "Done" or "Move")
	end
	if bar.shardGlow then
		LockRemindersPaintShardGlow(bar.shardGlow)
	end
	if bar.shardCount then
		LockRemindersPaintShardCount(bar.shardCount)
	end
	if bar.refreshSound then
		bar.refreshSound()
	end
end

function LockRemindersMakeScopeChecks(parent, anchor, field)
	local specs = {
		{ "raid", "Raid" },
		{ "party", "Party" },
		{ "instance", "Instance" },
		{ "always", "Always" },
	}
	local boxes = {}
	local previous = anchor
	local pad = 8
	for index = 1, #specs do
		local flag = specs[index][1]
		local caption = specs[index][2]
		local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
		box:SetSize(14, 14)
		box:SetPoint("LEFT", previous, "RIGHT", pad, 0)
		Paint(box, 0.08, 0.06, 0.1, 1, 0.58, 0.45, 0.82, 1)
		box.mark = box:CreateTexture(nil, "OVERLAY")
		box.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		box.mark:SetSize(16, 16)
		box.mark:SetPoint("CENTER")
		box.mark:Hide()
		function box:SetChecked(on)
			self.checked = on and true or false
			self.mark:SetShown(self.checked)
			if self.checked then
				self:SetBackdropColor(0.32, 0.22, 0.48, 1)
			else
				self:SetBackdropColor(0.08, 0.06, 0.1, 1)
			end
		end
		box.caption = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.caption:SetPoint("LEFT", box, "RIGHT", 3, 0)
		box.caption:SetText(caption)
		box.caption:SetTextColor(0.92, 0.88, 1)
		box:SetScript("OnClick", function()
			local always, party, raid, instance = ScopeFlags(db[field])
			local scope = { always = always, party = party, raid = raid, instance = instance }
			scope[flag] = not scope[flag]
			db[field] = scope
			LockRemindersUpdateSoul()
			LockRemindersRefreshSoul()
		end)
		local hit = CreateFrame("Button", nil, parent)
		hit:SetPoint("LEFT", box, "LEFT", 0, 0)
		hit:SetPoint("RIGHT", box.caption, "RIGHT", 2, 0)
		hit:SetHeight(20)
		hit:SetScript("OnClick", function()
			box:Click()
		end)
		boxes[flag] = box
		previous = box.caption
		pad = 8
	end
	function boxes.refresh()
		local always, party, raid, instance = ScopeFlags(db and db[field])
		boxes.raid:SetChecked(raid)
		boxes.party:SetChecked(party)
		if boxes.instance then
			boxes.instance:SetChecked(instance)
		end
		boxes.always:SetChecked(always)
	end
	return boxes
end

function LockRemindersBuildSoul(owner)
	local bar = LockRemindersOpenSettings(owner, "soulBar")

	local function toggle(parent, field, x, y)
		local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
		button:SetSize(48, 22)
		button:SetPoint("TOPLEFT", x, y)
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button:SetScript("OnClick", function()
			db[field] = not (db[field] ~= false)
			LockRemindersUpdateSoul()
			LockRemindersRefreshSoul()
		end)
		return button
	end

	local function checkBox(parent, x, y, label, field, apply)
		local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
		box:SetSize(14, 14)
		box:SetPoint("TOPLEFT", x, y)
		Paint(box, 0.08, 0.06, 0.1, 1, 0.58, 0.45, 0.82, 1)
		box.mark = box:CreateTexture(nil, "OVERLAY")
		box.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		box.mark:SetSize(16, 16)
		box.mark:SetPoint("CENTER")
		function box:SetChecked(on)
			self.checked = on and true or false
			self.mark:SetShown(self.checked)
			if self.checked then
				self:SetBackdropColor(0.32, 0.22, 0.48, 1)
			else
				self:SetBackdropColor(0.08, 0.06, 0.1, 1)
			end
		end
		box.caption = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.caption:SetPoint("LEFT", box, "RIGHT", 4, 0)
		box.caption:SetText(label)
		box.caption:SetTextColor(0.92, 0.88, 1)
		box:SetScript("OnClick", function()
			db[field] = not (db[field] ~= false)
			if apply then
				apply()
			end
			LockRemindersUpdateSoul()
			LockRemindersRefreshSoul()
		end)
		local hit = CreateFrame("Button", nil, parent)
		hit:SetPoint("LEFT", box, "LEFT", 0, 0)
		hit:SetPoint("RIGHT", box.caption, "RIGHT", 2, 0)
		hit:SetHeight(20)
		hit:SetScript("OnClick", function()
			box:Click()
		end)
		box.hit = hit
		return box
	end

	local function step(parent, anchor, read, write, low, high, stepSize)
		return LockRemindersSettingsStepper(parent, anchor, 8, read, write, low, high, stepSize)
	end

	LockRemindersSettingsHead(bar, "Soulstone")
	local missing = LockRemindersSettingsCard(bar, 214, LockRemindersSoulIcon(), "Missing stone", "Empty or ready")
	bar.alertToggle = toggle(missing, "soulAlert", 176, -14)
	bar.alertChecks = LockRemindersMakeScopeChecks(missing, bar.alertToggle, "soulScope")
	local sizeLabel = LockRemindersSettingsCaption(missing, bar.alertChecks.always.caption, "Size", 12)
	local plus
	plus, bar.sizeText = step(missing, sizeLabel, function()
		return db.soulSize or 48
	end, function(value)
		db.soulSize = value
		LockRemindersApplySoulLook()
		LockRemindersRefreshSoul()
	end, 32, 96, 4)
	bar.moveButton = LockRemindersSettingsButton(missing, plus, "Move", 10, function()
		LockRemindersSetSoulMove(not LockRemindersSoul.moving)
	end)
	bar.testButton = LockRemindersSettingsButton(missing, bar.moveButton, "Test", 8, function()
		LockRemindersPreviewSoul()
	end)
	LockRemindersPinSettingsActions(bar.moveButton, bar.testButton, missing, -14)
	local soulTextLabel = missing:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	soulTextLabel:SetPoint("TOPLEFT", 176, -50)
	soulTextLabel:SetText("Empty")
	soulTextLabel:SetTextColor(0.9, 0.84, 1)
	bar.soulLabel = LockRemindersSettingsEdit(missing, soulTextLabel, "soulLabel", "SOULSTONE", 140, function()
		if missing:IsVisible() then
			LockRemindersSoul.mode = "missing"
			LockRemindersSoul.soundMode = "missing"
			LockRemindersSoul.previewUntil = GetTime() + 2.2
			LockRemindersShowSoulAlert(false)
		end
	end, true)
	bar.soulGlow = LockRemindersGlowSwatch(missing, bar.soulLabel, 12, "soulGlow", 0.72, 0.4, 1, function()
		LockRemindersSoul.mode = "missing"
		LockRemindersApplySoulLook()
	end)
	LockRemindersGlowBorderControl(missing, bar.soulGlow, 10, "soulGlowSize", LockRemindersApplySoulLook)
	local readyTextLabel = missing:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	readyTextLabel:SetPoint("TOPLEFT", 176, -84)
	readyTextLabel:SetText("Ready")
	readyTextLabel:SetTextColor(0.9, 0.84, 1)
	bar.soulReadyLabel = LockRemindersSettingsEdit(missing, readyTextLabel, "soulReadyLabel", "READY", 140, function()
		if missing:IsVisible() then
			LockRemindersSoul.mode = "ready"
			LockRemindersSoul.soundMode = "ready"
			LockRemindersSoul.previewUntil = GetTime() + 2.2
			LockRemindersShowSoulAlert(false)
		end
	end, true)
	bar.soulReadyGlow = LockRemindersGlowSwatch(missing, bar.soulReadyLabel, 12, "soulReadyGlow", 0.35, 0.95, 0.45, function()
		LockRemindersSoul.mode = "ready"
		LockRemindersSoul.soundMode = "ready"
		LockRemindersSoul.previewUntil = GetTime() + 2.2
		LockRemindersShowSoulAlert(false)
	end)
	local soulSoundLabel = missing:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	soulSoundLabel:SetPoint("TOPLEFT", 176, -118)
	soulSoundLabel:SetText("Sound")
	soulSoundLabel:SetTextColor(0.9, 0.84, 1)
	bar.refreshSound = LockRemindersMakeSoundRow(missing, soulSoundLabel, function()
		return db and db.soulSound or "chiji"
	end, function(id)
		db.soulSound = id
	end)
	bar.soulAnnounce = checkBox(missing, 176, -148, "Announce", "soulAnnounce")
	bar.soulAnnounceParty = checkBox(missing, 280, -148, "Party", "soulAnnounceParty")
	bar.soulAnnounceRaid = checkBox(missing, 360, -148, "Raid", "soulAnnounceRaid")
	bar.soulAnnounceMsgLabel = missing:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.soulAnnounceMsgLabel:SetPoint("TOPLEFT", 176, -176)
	bar.soulAnnounceMsgLabel:SetText("Msg")
	bar.soulAnnounceMsgLabel:SetTextColor(0.9, 0.84, 1)
	bar.soulAnnounceMsg = LockRemindersSettingsEdit(missing, bar.soulAnnounceMsgLabel, "soulAnnounceMsg", "{rt3} Soulstone on %s {rt3}", 260, nil, false, 80)

	LockRemindersSettingsHead(bar, "Summon")
	local summon = LockRemindersSettingsCard(bar, 78, "Interface\\Icons\\Spell_Shadow_Twilight", "Ritual", "Announce")
	bar.summonAnnounce = checkBox(summon, 176, -14, "Announce", "summonAnnounce")
	bar.summonAnnounceParty = checkBox(summon, 280, -14, "Party", "summonAnnounceParty")
	bar.summonAnnounceRaid = checkBox(summon, 360, -14, "Raid", "summonAnnounceRaid")
	bar.summonAnnounceMsgLabel = summon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.summonAnnounceMsgLabel:SetPoint("TOPLEFT", 176, -42)
	bar.summonAnnounceMsgLabel:SetText("Msg")
	bar.summonAnnounceMsgLabel:SetTextColor(0.9, 0.84, 1)
	bar.summonAnnounceMsg = LockRemindersSettingsEdit(summon, bar.summonAnnounceMsgLabel, "summonAnnounceMsg", "{rt3} Summoning %s - click portal {rt3}", 260, nil, false, 80)

	LockRemindersSettingsHead(bar, "SS tracker")
	local track = LockRemindersSettingsCard(bar, 82, LockRemindersSoulIcon(), "On screen", "Active stones")
	bar.trackToggle = toggle(track, "soulTrack", 176, -14)
	bar.trackChecks = LockRemindersMakeScopeChecks(track, bar.trackToggle, "soulTrackScope")
	local trackSizeLabel = LockRemindersSettingsCaption(track, bar.trackChecks.always.caption, "Size", 12)
	local trackPlus
	trackPlus, bar.trackSize = step(track, trackSizeLabel, function()
		return db.soulTrackSize or 100
	end, function(value)
		db.soulTrackSize = value
		LockRemindersApplySoulTrackLook()
		LockRemindersUpdateSoul()
		LockRemindersRefreshSoul()
	end, 70, 160, 10)
	bar.trackMove = LockRemindersSettingsButton(track, trackPlus, "Move", 10, function()
		LockRemindersSetSoulTrackMove(not LockRemindersSoul.trackMoving)
	end)
	bar.trackTest = LockRemindersSettingsButton(track, bar.trackMove, "Test", 8, function()
		LockRemindersSoul.trackSample = not LockRemindersSoul.trackSample
		if not LockRemindersSoul.trackSample then
			LockRemindersSoul.sampleAt = nil
		end
		LockRemindersUpdateSoul()
		LockRemindersRefreshSoul()
	end)
	LockRemindersPinSettingsActions(bar.trackMove, bar.trackTest, track, -14)
	bar.fullName = checkBox(track, 176, -50, "Full name", "soulFullName")
	bar.trackFrame = checkBox(track, 280, -50, "Frame", "soulTrackFrame", LockRemindersApplySoulTrackLook)
	local trackTextLabel = LockRemindersSettingsCaption(track, bar.trackFrame.caption, "Text", 16)
	local trackTextPlus
	trackTextPlus, bar.trackFont = step(track, trackTextLabel, function()
		return LockRemindersSoulTrackFont()
	end, function(value)
		db.soulTrackFont = value
		LockRemindersApplySoulTrackLook()
		LockRemindersUpdateSoul()
		LockRemindersRefreshSoul()
	end, 10, 28, 2)
	local trackFadeLabel = LockRemindersSettingsCaption(track, trackTextPlus, "Fade", 16)
	local trackFadePlus
	trackFadePlus, bar.trackFade = step(track, trackFadeLabel, function()
		return LockRemindersSoulTrackFade()
	end, function(value)
		db.soulTrackFade = value
		LockRemindersApplySoulTrackLook()
		LockRemindersRefreshSoul()
	end, 0, 100, 5)

	LockRemindersSettingsHead(bar, "Banish")
	local banish = LockRemindersSettingsCard(bar, 90, "Interface\\Icons\\Spell_Shadow_Cripple", "Banish", "Countdown")
	bar.banishToggle = toggle(banish, "banishAlert", 176, -14)
	bar.banishChecks = LockRemindersMakeScopeChecks(banish, bar.banishToggle, "banishScope")
	local secondsLabel = LockRemindersSettingsCaption(banish, bar.banishChecks.always.caption, "Seconds", 12)
	local banishWarnPlus
	banishWarnPlus, bar.banishWarn = step(banish, secondsLabel, function()
		return db.banishWarn or 5
	end, function(value)
		db.banishWarn = value
		LockRemindersRefreshSoul()
	end, 2, 15, 1)
	local banishSizeLabel = banish:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	banishSizeLabel:SetPoint("TOPLEFT", 176, -50)
	banishSizeLabel:SetText("Size")
	banishSizeLabel:SetTextColor(0.9, 0.84, 1)
	local banishSizePlus
	banishSizePlus, bar.banishSize = step(banish, banishSizeLabel, function()
		return db.banishSize or 48
	end, function(value)
		db.banishSize = value
		LockRemindersApplyClassLook()
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end, 32, 96, 4)
	local banishTextLabel = LockRemindersSettingsCaption(banish, banishSizePlus, "Text", 12)
	bar.banishLabel = LockRemindersSettingsEdit(banish, banishTextLabel, "banishLabel", "BANISH", 140, function()
		LockRemindersApplyClassLook()
		LockRemindersUpdateClassAlerts()
	end, true)
	bar.banishMove = LockRemindersSettingsButton(banish, bar.banishLabel, "Move", 10, function()
		LockRemindersCreateClassAlerts()
		LockRemindersWarlock.banishMoving = not LockRemindersWarlock.banishMoving
		LockRemindersWarlock.banishPreview = nil
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)
	bar.banishTest = LockRemindersSettingsButton(banish, bar.banishMove, "Test", 8, function()
		LockRemindersCreateClassAlerts()
		if LockRemindersWarlock.banishPreview and GetTime() < LockRemindersWarlock.banishPreview then
			LockRemindersWarlock.banishPreview = nil
			LockRemindersWarlock.banishMoving = false
		else
			LockRemindersWarlock.banishMoving = false
			LockRemindersWarlock.banishPreview = GetTime() + math.max(2, tonumber(db.banishWarn) or 5)
		end
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)
	LockRemindersPinSettingsActions(bar.banishMove, bar.banishTest, banish, -50)

	LockRemindersSettingsHead(bar, "Fear")
	local fear = LockRemindersSettingsCard(bar, 90, "Interface\\Icons\\Spell_Shadow_Possession", "Fear", "Countdown")
	bar.fearToggle = toggle(fear, "fearAlert", 176, -14)
	bar.fearChecks = LockRemindersMakeScopeChecks(fear, bar.fearToggle, "fearScope")
	local fearSecondsLabel = LockRemindersSettingsCaption(fear, bar.fearChecks.always.caption, "Seconds", 12)
	local fearWarnPlus
	fearWarnPlus, bar.fearWarn = step(fear, fearSecondsLabel, function()
		return db.fearWarn or 5
	end, function(value)
		db.fearWarn = value
		LockRemindersRefreshSoul()
	end, 2, 15, 1)
	local fearSizeLabel = fear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fearSizeLabel:SetPoint("TOPLEFT", 176, -50)
	fearSizeLabel:SetText("Size")
	fearSizeLabel:SetTextColor(0.9, 0.84, 1)
	local fearSizePlus
	fearSizePlus, bar.fearSize = step(fear, fearSizeLabel, function()
		return db.fearSize or 48
	end, function(value)
		db.fearSize = value
		LockRemindersApplyClassLook()
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end, 32, 96, 4)
	local fearTextLabel = LockRemindersSettingsCaption(fear, fearSizePlus, "Text", 12)
	bar.fearLabel = LockRemindersSettingsEdit(fear, fearTextLabel, "fearLabel", "FEAR", 140, function()
		LockRemindersApplyClassLook()
		LockRemindersUpdateClassAlerts()
	end, true)
	bar.fearMove = LockRemindersSettingsButton(fear, bar.fearLabel, "Move", 10, function()
		LockRemindersCreateClassAlerts()
		LockRemindersWarlock.fearMoving = not LockRemindersWarlock.fearMoving
		LockRemindersWarlock.fearPreview = nil
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)
	bar.fearTest = LockRemindersSettingsButton(fear, bar.fearMove, "Test", 8, function()
		LockRemindersCreateClassAlerts()
		if LockRemindersWarlock.fearPreview and GetTime() < LockRemindersWarlock.fearPreview then
			LockRemindersWarlock.fearPreview = nil
			LockRemindersWarlock.fearMoving = false
		else
			LockRemindersWarlock.fearMoving = false
			LockRemindersWarlock.fearPreview = GetTime() + math.max(2, tonumber(db.fearWarn) or 5)
		end
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)
	LockRemindersPinSettingsActions(bar.fearMove, bar.fearTest, fear, -50)

	LockRemindersSettingsHead(bar, "Soul shards")
	local shards = LockRemindersSettingsCard(bar, 114, "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", "Soul shards", "In your bags")
	bar.shardToggle = toggle(shards, "shardShow", 176, -14)
	bar.shardChecks = LockRemindersMakeScopeChecks(shards, bar.shardToggle, "shardScope")
	local shardSizeLabel = LockRemindersSettingsCaption(shards, bar.shardChecks.always.caption, "Size", 12)
	local shardSizePlus
	shardSizePlus, bar.shardSize = step(shards, shardSizeLabel, function()
		return db.shardSize or 40
	end, function(value)
		db.shardSize = value
		LockRemindersApplyClassLook()
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end, 24, 80, 4)
	local shardTextLabel = LockRemindersSettingsCaption(shards, shards, "Text", 0)
	shardTextLabel:ClearAllPoints()
	shardTextLabel:SetPoint("TOPLEFT", 176, -50)
	bar.shardLabel = LockRemindersSettingsEdit(shards, shardTextLabel, "shardLabel", "NO SHARDS", 120, function()
		LockRemindersApplyClassLook()
		LockRemindersUpdateClassAlerts()
	end, true)
	bar.shardMove = LockRemindersSettingsButton(shards, bar.shardLabel, "Move", 10, function()
		LockRemindersCreateClassAlerts()
		LockRemindersWarlock.shardMoving = not LockRemindersWarlock.shardMoving
		if LockRemindersWarlock.shardMoving then
			LockRemindersWarlock.shardPreview = nil
		end
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)
	bar.shardTest = LockRemindersSettingsButton(shards, bar.shardMove, "Test", 8, function()
		LockRemindersCreateClassAlerts()
		LockRemindersWarlock.shardMoving = false
		LockRemindersWarlock.shardPreview = GetTime() + 2.5
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)
	LockRemindersPinSettingsActions(bar.shardMove, bar.shardTest, shards, -50)
	local glowLabel = LockRemindersSettingsCaption(shards, shards, "Glow", 0)
	glowLabel:ClearAllPoints()
	glowLabel:SetPoint("TOPLEFT", 176, -78)
	bar.shardGlow = CreateFrame("Button", nil, shards, "BackdropTemplate")
	bar.shardGlow:SetSize(22, 22)
	bar.shardGlow:SetPoint("LEFT", glowLabel, "RIGHT", 12, 0)
	bar.shardGlow:SetScript("OnClick", function()
		LockRemindersPickShardGlow()
	end)
	local borderPlus = LockRemindersGlowBorderControl(shards, bar.shardGlow, 10, "shardGlowSize", function()
		LockRemindersApplyClassLook()
		LockRemindersUpdateClassAlerts()
	end)
	local countLabel = LockRemindersSettingsCaption(shards, borderPlus, "Count", 16)
	bar.shardCount = CreateFrame("Button", nil, shards, "BackdropTemplate")
	bar.shardCount:SetSize(22, 22)
	bar.shardCount:SetPoint("LEFT", countLabel, "RIGHT", 8, 0)
	bar.shardCount:SetScript("OnClick", function()
		LockRemindersPickShardCount()
	end)
	LockRemindersPaintShardCount(bar.shardCount)
	LockRemindersSettingsFinish(bar)
	if bar.soulLabel then
		bar.soulLabel.quiet = true
		bar.soulLabel:SetText(LockRemindersClassLabel("soulLabel", false))
		bar.soulLabel.quiet = nil
	end
	if bar.soulReadyLabel then
		bar.soulReadyLabel.quiet = true
		bar.soulReadyLabel:SetText(LockRemindersClassLabel("soulReadyLabel", false))
		bar.soulReadyLabel.quiet = nil
	end
	if bar.soulAnnounceMsg then
		bar.soulAnnounceMsg.quiet = true
		bar.soulAnnounceMsg:SetText(type(db.soulAnnounceMsg) == "string" and db.soulAnnounceMsg ~= "" and db.soulAnnounceMsg or "{rt3} Soulstone on %s {rt3}")
		bar.soulAnnounceMsg.quiet = nil
	end
	if bar.summonAnnounceMsg then
		bar.summonAnnounceMsg.quiet = true
		bar.summonAnnounceMsg:SetText(type(db.summonAnnounceMsg) == "string" and db.summonAnnounceMsg ~= "" and db.summonAnnounceMsg or "{rt3} Summoning %s - click portal {rt3}")
		bar.summonAnnounceMsg.quiet = nil
	end
	if bar.banishLabel then
		bar.banishLabel.quiet = true
		bar.banishLabel:SetText(LockRemindersClassLabel("banishLabel", false))
		bar.banishLabel.quiet = nil
	end
	if bar.fearLabel then
		bar.fearLabel.quiet = true
		bar.fearLabel:SetText(LockRemindersClassLabel("fearLabel", false))
		bar.fearLabel.quiet = nil
	end
	if bar.shardLabel then
		bar.shardLabel.quiet = true
		bar.shardLabel:SetText(LockRemindersClassLabel("shardLabel", false))
		bar.shardLabel.quiet = nil
	end
	if bar.refreshSound then
		bar.refreshSound()
	end
end

LockRemindersWarlock = LockRemindersWarlock or {}

function LockRemindersBanishMatch(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID == 710 or spellID == 18647 then
		return true
	end
	local wanted = Normalize(spellName or "")
	return wanted == "banish" or wanted == "desterrar" or wanted == "exilio" or wanted == "exiliar"
end

function LockRemindersFearMatch(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID == 5782 or spellID == 6213 or spellID == 6215 then
		return true
	end
	local wanted = Normalize(spellName or "")
	if wanted == "fear" or wanted == "miedo" then
		return true
	end
	if wanted:find("^fear rank", 1, true) or wanted:find("^fear(", 1, true) then
		return true
	end
	if wanted:find("^miedo", 1, true) and not wanted:find("aullido", 1, true) then
		return true
	end
	return false
end

function LockRemindersFearSeconds(spellID)
	spellID = tonumber(spellID)
	if spellID == 5782 then
		return 10
	end
	if spellID == 6213 then
		return 15
	end
	return 20
end

function LockRemindersClearCcGuid(guid, kind)
	if type(guid) ~= "string" or guid == "" then
		return false
	end
	local cleared = false
	if kind ~= "fear" then
		if LockRemindersWarlock.ends and LockRemindersWarlock.ends[guid] then
			LockRemindersWarlock.ends[guid] = nil
			cleared = true
		end
		if LockRemindersWarlock.guess then
			LockRemindersWarlock.guess[guid] = nil
		end
		if LockRemindersWarlock.applied then
			LockRemindersWarlock.applied[guid] = nil
		end
	end
	if kind ~= "banish" then
		local fearData = LockRemindersWarlock.fearData
		if fearData then
			if fearData.ends and fearData.ends[guid] then
				fearData.ends[guid] = nil
				cleared = true
			end
			if fearData.guess then
				fearData.guess[guid] = nil
			end
			if fearData.applied then
				fearData.applied[guid] = nil
			end
		end
	end
	if cleared then
		pcall(LockRemindersUpdateClassAlerts)
	end
	return cleared
end

function LockRemindersNoteCcDamage(unit)
	if type(unit) ~= "string" or unit == "" then
		return
	end
	local guid = LockRemindersMissGuid(unit)
	if not guid then
		return
	end
	local now = GetTime()
	local fearData = LockRemindersWarlock.fearData
	local fearAt = fearData and fearData.applied and fearData.applied[guid]
	if fearAt and now - fearAt >= 1.25 then
		LockRemindersClearCcGuid(guid, "fear")
	end
	local banishAt = LockRemindersWarlock.applied and LockRemindersWarlock.applied[guid]
	if banishAt and now - banishAt >= 1.25 then
		LockRemindersClearCcGuid(guid, "banish")
	end
	local seduce = LockRemindersPet and LockRemindersPet.seduction
	local seduceAt = seduce and seduce.applied and seduce.applied[guid]
	if seduceAt and now - seduceAt >= 1.25 then
		LockRemindersClearPetSeduction(guid)
	end
end

function LockRemindersClearCcByName(name, kind)
	if type(name) ~= "string" or name == "" or LockRemindersSecret(name) then
		return false
	end
	local wanted = Normalize(name)
	local cleared = false
	local function sweep(names)
		if type(names) ~= "table" then
			return
		end
		for guid, saved in pairs(names) do
			if Normalize(saved or "") == wanted then
				if LockRemindersClearCcGuid(guid, kind) then
					cleared = true
				end
			end
		end
	end
	if kind ~= "fear" then
		sweep(LockRemindersWarlock.names)
	end
	if kind ~= "banish" then
		local fearData = LockRemindersWarlock.fearData
		sweep(fearData and fearData.names)
	end
	return cleared
end

function LockRemindersClearCcUnit(unit, kind)
	if type(unit) ~= "string" or unit == "" then
		return false
	end
	local cleared = false
	local guid = LockRemindersMissGuid(unit)
	if guid and LockRemindersClearCcGuid(guid, kind) then
		cleared = true
	end
	if UnitName then
		local ok, name = pcall(UnitName, unit)
		if ok and LockRemindersClearCcByName(name, kind) then
			cleared = true
		end
	end
	return cleared
end

function LockRemindersReadCcLine(text)
	if type(text) ~= "string" or text == "" or LockRemindersSecret(text) then
		return
	end
	local name = text:match("^(.+) breaks free of your Fear!?$")
		or text:match("^(.+) se libera de tu Miedo!?$")
	if name then
		LockRemindersClearCcByName(name, "fear")
		return
	end
	name = text:match("^(.+) breaks free of your Banish!?$")
		or text:match("^(.+) se libera de tu Destierro!?$")
		or text:match("^(.+) se libera de tu Banish!?$")
	if name then
		LockRemindersClearCcByName(name, "banish")
		return
	end
	name = text:match("^Fear fades from (.+)%.?$")
		or text:match("^Miedo desaparece de (.+)%.?$")
		or text:match("^Miedo se desvanece de (.+)%.?$")
	if name then
		LockRemindersClearCcByName(name, "fear")
		return
	end
	name = text:match("^Banish fades from (.+)%.?$")
		or text:match("^Destierro desaparece de (.+)%.?$")
		or text:match("^Destierro se desvanece de (.+)%.?$")
	if name then
		LockRemindersClearCcByName(name, "banish")
		return
	end
	-- Cast-interrupt chat lines are ignored here: they race a successful Fear land.
end

function LockRemindersReadCc(unit, match)
	if not unit or not UnitExists or not UnitExists(unit) then
		return nil
	end
	local hidden, blocked = false, false
	local function fromTimes(duration, expires)
		if LockRemindersSecret(duration) then
			duration = nil
		end
		if LockRemindersSecret(expires) then
			expires = nil
		end
		duration = tonumber(duration)
		expires = tonumber(expires)
		if duration and expires and duration > 0 and expires > 0 then
			return expires - GetTime(), expires
		end
		return nil
	end
	local function consider(id, name, duration, expires)
		if LockRemindersSecret(id) then
			id = nil
		end
		if LockRemindersSecret(name) then
			name = nil
		end
		local named = type(name) == "string" and name ~= ""
		local knownId = type(id) == "number" or (type(id) == "string" and id ~= "")
		if not named and not knownId then
			return "blocked"
		end
		if not match(id, name) then
			return nil
		end
		local left, ends = fromTimes(duration, expires)
		if left then
			return left, ends
		end
		return "hidden"
	end
	local function scanIndex(status, ends)
		if type(status) == "number" and status > 0 then
			return status, ends
		end
		if status == "hidden" then
			hidden = true
		elseif status == "blocked" then
			blocked = true
		end
		return nil
	end
	if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, index)
			if not ok or aura == nil or aura == false or LockRemindersSecret(aura) then
				if aura ~= nil and aura ~= false then
					blocked = true
				end
				break
			end
			local left, ends = scanIndex(consider(aura.spellId or aura.spellID, aura.name, aura.duration, aura.expirationTime))
			if left then
				return left, ends
			end
		end
	end
	if UnitDebuff then
		for index = 1, 40 do
			local ok, name, _, _, _, _, duration, expires, _, _, _, id = pcall(UnitDebuff, unit, index)
			if not ok or name == nil or name == false or LockRemindersSecret(name) or name == "" then
				if not ok or LockRemindersSecret(name) then
					blocked = true
				end
				break
			end
			local left, ends = scanIndex(consider(id, name, duration, expires))
			if left then
				return left, ends
			end
		end
	end
	if hidden then
		return true
	end
	if blocked or (not C_UnitAuras and not UnitDebuff) then
		return nil
	end
	return false
end

function LockRemindersReadBanish(unit)
	return LockRemindersReadCc(unit, LockRemindersBanishMatch)
end

function LockRemindersSoonestCc(match, data)
	local bestLeft, bestEnds, bestName, bestGuid
	local seen = {}
	local function rememberName(guid, unit)
		if not guid or not UnitName then
			return
		end
		local ok, name = pcall(UnitName, unit)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			data.names = data.names or {}
			data.names[guid] = name
		end
	end
	local function scan(unit)
		local left, ends = LockRemindersReadCc(unit, match)
		local guid = LockRemindersMissGuid(unit)
		if left == false then
			-- Forever can briefly hide CC auras; keep recent cast guesses.
			local appliedAt = data.applied and guid and data.applied[guid]
			if guid and (not appliedAt or GetTime() - appliedAt >= 1.25) then
				if data.ends then
					data.ends[guid] = nil
				end
				if data.guess then
					data.guess[guid] = nil
				end
				if data.applied then
					data.applied[guid] = nil
				end
			end
			return
		end
		if guid then
			seen[guid] = true
		end
		if type(left) == "number" and ends then
			if guid then
				data.ends = data.ends or {}
				data.ends[guid] = ends
				if data.guess then
					data.guess[guid] = nil
				end
				rememberName(guid, unit)
			end
		elseif guid and data.ends and data.ends[guid] then
			ends = data.ends[guid]
			left = ends - GetTime()
			rememberName(guid, unit)
		else
			return
		end
		if left <= 0 then
			if guid and data.ends then
				data.ends[guid] = nil
			end
			return
		end
		if not bestLeft or left < bestLeft then
			bestLeft, bestEnds, bestGuid = left, ends, guid
			bestName = data.names and guid and data.names[guid] or nil
		end
	end
	scan("mouseover")
	scan("focus")
	scan("target")
	for index = 1, 40 do
		scan("nameplate" .. index)
	end
	local endsMap = data.ends
	if endsMap then
		for guid, expires in pairs(endsMap) do
			local left = (tonumber(expires) or 0) - GetTime()
			if left <= 0 then
				endsMap[guid] = nil
				if data.guess then
					data.guess[guid] = nil
				end
				if data.applied then
					data.applied[guid] = nil
				end
			elseif not bestLeft or left < bestLeft then
				bestLeft, bestEnds, bestGuid = left, expires, guid
				bestName = data.names and data.names[guid] or nil
			end
		end
	end
	return bestLeft, bestEnds, bestName, bestGuid
end

function LockRemindersSoonestBanish()
	return LockRemindersSoonestCc(LockRemindersBanishMatch, LockRemindersWarlock)
end

function LockRemindersSoonestFear()
	LockRemindersWarlock.fearData = LockRemindersWarlock.fearData or {}
	return LockRemindersSoonestCc(LockRemindersFearMatch, LockRemindersWarlock.fearData)
end

function LockRemindersShardCount()
	local get = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not get then
		return nil
	end
	local ok, count = pcall(get, 6265)
	if not ok or count == nil or LockRemindersSecret(count) then
		return nil
	end
	count = tonumber(count)
	if not count or count < 0 then
		return nil
	end
	return count
end

function LockRemindersClassLabel(field, fallback)
	local text = db and db[field]
	if type(text) ~= "string" then
		if fallback == false then
			return ""
		end
		return fallback
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" and fallback ~= false then
		return fallback
	end
	return text
end

function LockRemindersClassShown(alertField, scopeField)
	if not db or db[alertField] == false then
		return false
	end
	return ScopeActive(db[scopeField] or { always = true })
end

function LockRemindersShardGlowColor()
	local color = db and db.shardGlow
	local red = type(color) == "table" and tonumber(color.r) or nil
	local green = type(color) == "table" and tonumber(color.g) or nil
	local blue = type(color) == "table" and tonumber(color.b) or nil
	if not red or not green or not blue then
		return 0.64, 0.32, 0.95
	end
	return red, green, blue
end

function LockRemindersPaintShardGlow(button)
	if not button then
		return
	end
	local red, green, blue = LockRemindersShardGlowColor()
	Paint(button, red, green, blue, 1, 0.95, 0.9, 1, 1)
end

function LockRemindersSetShardGlow(red, green, blue)
	if not db then
		return
	end
	db.shardGlow = { r = red, g = green, b = blue }
	local panelBar = panel and panel.soulBar
	if panelBar and panelBar.shardGlow then
		LockRemindersPaintShardGlow(panelBar.shardGlow)
	end
	LockRemindersApplyClassLook()
	LockRemindersUpdateClassAlerts()
end

function LockRemindersShardCountColor()
	local color = db and db.shardCount
	local red = type(color) == "table" and tonumber(color.r) or nil
	local green = type(color) == "table" and tonumber(color.g) or nil
	local blue = type(color) == "table" and tonumber(color.b) or nil
	if not red or not green or not blue then
		return 1, 0.97, 0.86
	end
	return red, green, blue
end

function LockRemindersPaintShardCount(button)
	if not button then
		return
	end
	local red, green, blue = LockRemindersShardCountColor()
	Paint(button, red, green, blue, 1, 0.95, 0.9, 1, 1)
end

function LockRemindersSetShardCount(red, green, blue)
	if not db then
		return
	end
	db.shardCount = { r = red, g = green, b = blue }
	local panelBar = panel and panel.soulBar
	if panelBar and panelBar.shardCount then
		LockRemindersPaintShardCount(panelBar.shardCount)
	end
	LockRemindersApplyClassLook()
	LockRemindersUpdateClassAlerts()
end

function LockRemindersPickShardCount()
	if not ColorPickerFrame or not db then
		return
	end
	local red, green, blue = LockRemindersShardCountColor()
	local previous = { r = red, g = green, b = blue }
	local function apply(nextRed, nextGreen, nextBlue)
		if not nextRed then
			return
		end
		LockRemindersSetShardCount(nextRed, nextGreen, nextBlue)
	end
	local function read()
		if ColorPickerFrame.GetColorRGB then
			return ColorPickerFrame:GetColorRGB()
		end
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = red,
			g = green,
			b = blue,
			hasOpacity = false,
			swatchFunc = function()
				apply(read())
			end,
			cancelFunc = function()
				apply(previous.r, previous.g, previous.b)
			end,
		})
		return
	end
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.func = function()
		apply(read())
	end
	ColorPickerFrame.cancelFunc = function()
		apply(previous.r, previous.g, previous.b)
	end
	ColorPickerFrame.previousValues = { red, green, blue }
	if ColorPickerFrame.SetColorRGB then
		ColorPickerFrame:SetColorRGB(red, green, blue)
	end
	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()
end

function LockRemindersPickShardGlow()
	if not ColorPickerFrame or not db then
		return
	end
	local red, green, blue = LockRemindersShardGlowColor()
	local previous = { r = red, g = green, b = blue }
	local function apply(nextRed, nextGreen, nextBlue)
		if not nextRed then
			return
		end
		LockRemindersSetShardGlow(nextRed, nextGreen, nextBlue)
	end
	local function read()
		if ColorPickerFrame.GetColorRGB then
			return ColorPickerFrame:GetColorRGB()
		end
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = red,
			g = green,
			b = blue,
			hasOpacity = false,
			swatchFunc = function()
				apply(read())
			end,
			cancelFunc = function()
				apply(previous.r, previous.g, previous.b)
			end,
		})
		return
	end
	ColorPickerFrame.hasOpacity = false
	ColorPickerFrame.func = function()
		apply(read())
	end
	ColorPickerFrame.cancelFunc = function()
		apply(previous.r, previous.g, previous.b)
	end
	ColorPickerFrame.previousValues = { red, green, blue }
	if ColorPickerFrame.SetColorRGB then
		ColorPickerFrame:SetColorRGB(red, green, blue)
	end
	ColorPickerFrame:Hide()
	ColorPickerFrame:Show()
end

function LockRemindersFitBanishShade(frame)
	if not frame or not frame.shade or not frame.fadeLeft or not frame.fadeRight then
		return
	end
	local width = frame:GetWidth() or 0
	if width < 8 then
		return
	end
	local fade = math.floor(width * 0.22)
	if fade < 24 then
		fade = 24
	end
	if fade * 2 > width - 4 then
		fade = math.floor(width * 0.3)
	end
	local function gradient(texture, fromA, toA)
		texture:SetTexture("Interface\\Buttons\\WHITE8x8")
		local painted = false
		if CreateColor and texture.SetGradient then
			painted = pcall(texture.SetGradient, texture, "HORIZONTAL", CreateColor(0, 0, 0, fromA), CreateColor(0, 0, 0, toA))
			if not painted then
				painted = pcall(texture.SetGradient, texture, "Horizontal", CreateColor(0, 0, 0, fromA), CreateColor(0, 0, 0, toA))
			end
		end
		if not painted then
			texture:SetVertexColor(0, 0, 0, (fromA + toA) * 0.5)
		end
	end
	frame.fadeLeft:ClearAllPoints()
	frame.fadeLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	frame.fadeLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	frame.fadeLeft:SetWidth(fade)
	gradient(frame.fadeLeft, 0, 0.55)
	frame.fadeRight:ClearAllPoints()
	frame.fadeRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	frame.fadeRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame.fadeRight:SetWidth(fade)
	gradient(frame.fadeRight, 0.55, 0)
	frame.shade:ClearAllPoints()
	frame.shade:SetPoint("TOPLEFT", frame.fadeLeft, "TOPRIGHT", 0, 0)
	frame.shade:SetPoint("BOTTOMRIGHT", frame.fadeRight, "BOTTOMLEFT", 0, 0)
	frame.shade:SetVertexColor(0, 0, 0, 0.55)
	pcall(frame.SetBackdrop, frame, nil)
end

function LockRemindersApplyClassLook()
	local banish = LockRemindersWarlock.banish
	local shards = LockRemindersWarlock.shards
	local function styleBanner(frame, kind, primarySpell, fallbackSpell, fallbackIcon)
		if not frame or not frame.icon then
			return
		end
		local size = tonumber(db and db[kind .. "Size"]) or 48
		if size < 32 then
			size = 32
		elseif size > 96 then
			size = 96
		end
		if db then
			db[kind .. "Size"] = size
		end
		frame.icon:ClearAllPoints()
		frame.icon:SetPoint("LEFT", 7, 0)
		frame.icon:SetSize(size, size)
		frame.icon:SetTexCoord(0, 1, 0, 1)
		LockRemindersSmoothIcon(frame.icon)
		if frame.cooldown then
			frame.cooldown:ClearAllPoints()
			frame.cooldown:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
			frame.cooldown:SetSize(size, size)
		end
		local nameSize = math.max(16, math.floor(size * 0.4))
		local numberSize = math.max(18, math.floor(size * 0.52))
		local secondsSize = math.max(13, math.floor(size * 0.3))
		local subSize = math.max(11, math.floor(size * 0.24))
		frame.text:SetFont("Fonts\\FRIZQT__.TTF", nameSize, "OUTLINE")
		frame.count:SetFont("Fonts\\FRIZQT__.TTF", numberSize, "OUTLINE")
		if frame.seconds then
			frame.seconds:SetFont("Fonts\\FRIZQT__.TTF", secondsSize, "OUTLINE")
		end
		frame.sub:SetFont("Fonts\\FRIZQT__.TTF", subSize, "OUTLINE")
		local icon = SpellIcon(primarySpell)
		if not icon or icon == 134400 then
			icon = SpellIcon(fallbackSpell)
		end
		frame.icon:SetTexture(icon or fallbackIcon)
		LockRemindersSmoothIcon(frame.icon)
		if frame.redTop then
			frame.redTop:Hide()
		end
		if frame.redBottom then
			frame.redBottom:Hide()
		end
		pcall(frame.SetBackdrop, frame, nil)
	end
	styleBanner(banish, "banish", 18647, 710, "Interface\\Icons\\Spell_Shadow_Cripple")
	styleBanner(LockRemindersWarlock.fear, "fear", 6215, 5782, "Interface\\Icons\\Spell_Shadow_Possession")
	if shards and shards.icon then
		local size = tonumber(db and db.shardSize) or 40
		if size < 24 then
			size = 24
		elseif size > 80 then
			size = 80
		end
		if db then
			db.shardSize = size
		end
		local thick = LockRemindersPlaceAlertIcon(shards.icon, shards.glow, size, "TOP", "shardGlowSize")
		LockRemindersTintEvenGlow(shards.glow, LockRemindersShardGlowColor())
		shards.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(12, math.floor(size * 0.46)), "OUTLINE")
		shards.text:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, math.floor(size * 0.28)), "OUTLINE")
		shards:SetSize(size + thick * 2, size + thick * 2 + math.floor(size * 0.45))
		shards.icon:SetTexture(ItemIcon(6265) or "Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
	end
end

function LockRemindersUpdateClassAlerts()
	local banish = LockRemindersWarlock.banish
	local fear = LockRemindersWarlock.fear
	local shards = LockRemindersWarlock.shards
	if not banish or not shards or not db then
		return
	end
	local now = GetTime()
	banish:EnableMouse(LockRemindersWarlock.banishMoving and true or false)
	if fear then
		fear:EnableMouse(LockRemindersWarlock.fearMoving and true or false)
	end
	shards:EnableMouse(LockRemindersWarlock.shardMoving and true or false)
	if LockRemindersWarlock.banishMoving or LockRemindersWarlock.shardMoving then
		local function edge(frame, on)
			if on then
				frame:SetBackdropColor(0, 0, 0, 0.45)
				frame:SetBackdropBorderColor(0.72, 0.45, 1, 1)
			else
				frame:SetBackdropColor(0, 0, 0, 0)
				frame:SetBackdropBorderColor(0, 0, 0, 0)
			end
		end
		edge(shards, LockRemindersWarlock.shardMoving)
		pcall(banish.SetBackdrop, banish, nil)
	else
		pcall(banish.SetBackdrop, banish, nil)
		shards:SetBackdropColor(0, 0, 0, 0)
		shards:SetBackdropBorderColor(0, 0, 0, 0)
	end
	local function paintBanner(frame, kind, seconds, sub, cooldownKey)
		LockRemindersApplyClassLook()
		local label = LockRemindersClassLabel(kind .. "Label", false)
		frame.text:SetText(label)
		frame.text:SetShown(label ~= "")
		frame.count:SetText(tostring(math.max(1, math.ceil(seconds))))
		if frame.seconds then
			local word = SECONDS
			if type(word) ~= "string" or word == "" then
				word = "Seconds"
			end
			frame.seconds:SetText(word)
			frame.seconds:Show()
		end
		frame.sub:SetText(sub or "")
		frame.sub:SetShown(sub and sub ~= "")
		frame.text:ClearAllPoints()
		frame.count:ClearAllPoints()
		if frame.seconds then
			frame.seconds:ClearAllPoints()
		end
		frame.sub:ClearAllPoints()
		if label ~= "" then
			frame.text:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -1)
			frame.count:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -2)
		else
			frame.count:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -1)
		end
		if frame.seconds then
			frame.seconds:SetPoint("LEFT", frame.count, "RIGHT", 6, -1)
		end
		if frame.sub:IsShown() then
			frame.sub:SetPoint("TOPLEFT", frame.count, "BOTTOMLEFT", 0, -1)
		end
		local nameW = frame.text:IsShown() and frame.text:GetStringWidth() or 0
		local timeW = frame.count:GetStringWidth()
		if frame.seconds and frame.seconds:IsShown() then
			timeW = timeW + 6 + frame.seconds:GetStringWidth()
		end
		local subW = frame.sub:IsShown() and frame.sub:GetStringWidth() or 0
		local textW = math.max(nameW, timeW, subW, 72)
		local size = frame.icon:GetWidth()
		if size < 1 then
			size = tonumber(db[kind .. "Size"]) or 48
		end
		local stack = (frame.text:IsShown() and frame.text:GetStringHeight() + 2 or 0) + frame.count:GetStringHeight()
		if frame.sub:IsShown() then
			stack = stack + 2 + frame.sub:GetStringHeight()
		end
		frame:SetSize(7 + size + 10 + textW + 14, math.max(size + 14, stack + 16))
		LockRemindersFitBanishShade(frame)
		if frame.cooldown then
			if not cooldownKey then
				frame.cooldown:Hide()
				frame.cooldownKey = nil
			elseif cooldownKey ~= frame.cooldownKey and frame.cooldown.SetCooldown then
				frame.cooldownKey = cooldownKey
				frame.cooldown:SetCooldown(GetTime(), math.max(0.2, seconds))
				frame.cooldown:Show()
			end
		end
		if frame.glow then
			frame.glow:Hide()
		end
		frame:Show()
	end
	local function paintShards(count, zero)
		LockRemindersApplyClassLook()
		shards.count:SetText(tostring(count))
		local countRed, countGreen, countBlue = LockRemindersShardCountColor()
		shards.count:SetTextColor(countRed, countGreen, countBlue)
		if zero then
			local label = LockRemindersClassLabel("shardLabel", false)
			shards.text:SetText(label)
			shards.text:SetShown(label ~= "")
			if shards.glow then
				shards.glow:Show()
				if shards.glow.ag and not shards.glow.ag:IsPlaying() then
					shards.glow.ag:Play()
				end
			end
		else
			shards.text:SetText("")
			shards.text:Hide()
			if shards.glow then
				if shards.glow.ag then
					shards.glow.ag:Stop()
				end
				shards.glow:Hide()
			end
		end
		local iconSize = shards.icon:GetWidth()
		if iconSize > 0 then
			local thick = LockRemindersGlowThick(iconSize, "shardGlowSize")
			shards:SetWidth(iconSize + thick * 2)
			if zero and shards.text:IsShown() then
				shards:SetHeight(iconSize + thick * 2 + math.floor(iconSize * 0.45))
			else
				shards:SetHeight(iconSize + thick * 2)
			end
		end
		shards:Show()
	end
	local function showCountdown(frame, kind, moving, preview, soonest, warn, keyField)
		if not frame then
			return
		end
		if preview and now >= preview then
			LockRemindersWarlock[kind .. "Preview"] = nil
			preview = nil
		end
		if moving then
			paintBanner(frame, kind, 5, "Drag")
			return
		end
		if preview and now < preview then
			paintBanner(frame, kind, preview - now, "Target", "preview:" .. tostring(math.floor(preview)))
			return
		end
		if not LockRemindersClassShown(kind .. "Alert", kind .. "Scope") then
			frame:Hide()
			frame.cooldownKey = nil
			return
		end
		local left, ends, name, guid = soonest()
		if left and left <= warn then
			local key = tostring(guid or name or kind) .. ":" .. tostring(math.floor(ends or 0))
			paintBanner(frame, kind, left, name or "", key)
			if key ~= LockRemindersWarlock[keyField] then
				LockRemindersWarlock[keyField] = key
				LockRemindersPlaySoundId(db.soulSound or "chiji")
			end
		else
			frame:Hide()
			frame.cooldownKey = nil
			if not left and not LockRemindersZoneQuiet() then
				LockRemindersWarlock[keyField] = nil
			end
		end
	end
	showCountdown(banish, "banish", LockRemindersWarlock.banishMoving, LockRemindersWarlock.banishPreview, LockRemindersSoonestBanish, tonumber(db.banishWarn) or 5, "banishKey")
	if fear then
		showCountdown(fear, "fear", LockRemindersWarlock.fearMoving, LockRemindersWarlock.fearPreview, LockRemindersSoonestFear, tonumber(db.fearWarn) or 5, "fearKey")
	elseif LockRemindersIsWarlock() then
		pcall(LockRemindersCreateClassAlerts)
	end
	if LockRemindersWarlock.shardMoving then
		paintShards(3, false)
		return
	end
	if LockRemindersWarlock.shardPreview and now < LockRemindersWarlock.shardPreview then
		paintShards(0, true)
		return
	end
	local count = LockRemindersShardCount()
	if count == nil then
		count = LockRemindersWarlock.lastShards
	elseif count == 0 and (LockRemindersWarlock.lastShards or 0) > 0 then
		if LockRemindersZoneQuiet() then
			count = LockRemindersWarlock.lastShards
			LockRemindersWarlock.shardZeroAt = nil
		else
			LockRemindersWarlock.shardZeroAt = LockRemindersWarlock.shardZeroAt or now
			if now - LockRemindersWarlock.shardZeroAt < 2 then
				count = LockRemindersWarlock.lastShards
			end
		end
	else
		LockRemindersWarlock.shardZeroAt = nil
	end
	if count ~= nil then
		local crossed = (LockRemindersWarlock.lastShards or 0) > 0 and count == 0
		LockRemindersWarlock.lastShards = count
		if crossed and LockRemindersClassShown("shardShow", "shardScope") then
			LockRemindersPlaySoundId(db.soulSound or "chiji")
		end
	end
	if count == nil or not LockRemindersClassShown("shardShow", "shardScope") then
		shards:Hide()
		return
	end
	paintShards(count, count == 0)
end

function LockRemindersCreateClassAlerts()
	if not LockRemindersIsWarlock() then
		return
	end
	if LockRemindersWarlock.banish and LockRemindersWarlock.fear and LockRemindersWarlock.shards then
		return
	end
	local function movable(name, key, movingKey)
		local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
		frame:SetFrameStrata("HIGH")
		frame:SetClampedToScreen(true)
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			if LockRemindersWarlock[movingKey] then
				self:StartMoving()
			end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			LockRemindersSaveNamedPoint(self, key)
		end)
		frame:SetBackdrop(BACKDROP)
		frame:SetBackdropColor(0, 0, 0, 0)
		frame:SetBackdropBorderColor(0, 0, 0, 0)
		frame:EnableMouse(false)
		return frame
	end
	local function banner(name, pointKey, movingKey)
		local frame = movable(name, pointKey, movingKey)
		pcall(frame.SetBackdrop, frame, nil)
		frame.fadeLeft = frame:CreateTexture(nil, "BACKGROUND")
		frame.fadeLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
		frame.shade = frame:CreateTexture(nil, "BACKGROUND")
		frame.shade:SetTexture("Interface\\Buttons\\WHITE8x8")
		frame.shade:SetVertexColor(0, 0, 0, 0.55)
		frame.fadeRight = frame:CreateTexture(nil, "BACKGROUND")
		frame.fadeRight:SetTexture("Interface\\Buttons\\WHITE8x8")
		frame.icon = frame:CreateTexture(nil, "ARTWORK")
		frame.icon:SetTexCoord(0, 1, 0, 1)
		LockRemindersSmoothIcon(frame.icon)
		local cooldownOk, cooldown = pcall(CreateFrame, "Cooldown", nil, frame, "CooldownFrameTemplate")
		if cooldownOk and cooldown then
			pcall(cooldown.SetDrawBling, cooldown, false)
			if cooldown.SetHideCountdownNumbers then
				pcall(cooldown.SetHideCountdownNumbers, cooldown, true)
			end
			if cooldown.SetDrawEdge then
				pcall(cooldown.SetDrawEdge, cooldown, false)
			end
			frame.cooldown = cooldown
		end
		frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		frame.text:SetJustifyH("LEFT")
		frame.text:SetTextColor(1, 0.82, 0)
		frame.text:SetShadowColor(0, 0, 0, 1)
		frame.text:SetShadowOffset(1, -1)
		frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		frame.count:SetJustifyH("LEFT")
		frame.count:SetTextColor(1, 0.82, 0)
		frame.count:SetShadowColor(0, 0, 0, 1)
		frame.count:SetShadowOffset(1, -1)
		frame.seconds = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.seconds:SetJustifyH("LEFT")
		frame.seconds:SetTextColor(1, 0.82, 0)
		frame.seconds:SetShadowColor(0, 0, 0, 1)
		frame.seconds:SetShadowOffset(1, -1)
		frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		frame.sub:SetJustifyH("LEFT")
		frame.sub:SetTextColor(1, 0.95, 0.8)
		return frame
	end
	local banish = LockRemindersWarlock.banish
	if not banish then
		banish = banner("LockRemindersBanish", "banishPoint", "banishMoving")
		LockRemindersWarlock.banish = banish
		LockRemindersApplyNamedPoint(banish, "banishPoint", { "CENTER", "CENTER", 180, 210 })
		banish:Hide()
	end
	local fear = LockRemindersWarlock.fear
	if not fear then
		fear = banner("LockRemindersFear", "fearPoint", "fearMoving")
		LockRemindersWarlock.fear = fear
		LockRemindersApplyNamedPoint(fear, "fearPoint", { "CENTER", "CENTER", 180, 120 })
		fear:Hide()
	end
	local shards = LockRemindersWarlock.shards
	if not shards then
		shards = movable("LockRemindersShards", "shardPoint", "shardMoving")
		shards.icon = shards:CreateTexture(nil, "ARTWORK")
		shards.icon:SetPoint("TOP", 0, 0)
		shards.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		LockRemindersRoundIcon(shards.icon)
		shards.glow = LockRemindersMakeEvenGlow(shards)
		LockRemindersTintEvenGlow(shards.glow, LockRemindersShardGlowColor())
		shards.glow:Hide()
		shards.count = shards:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		shards.count:SetPoint("CENTER", shards.icon, "CENTER", 1, 0)
		shards.count:SetTextColor(LockRemindersShardCountColor())
		shards.count:SetShadowColor(0, 0, 0, 1)
		shards.count:SetShadowOffset(1, -1)
		shards.text = shards:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		shards.text:SetPoint("TOP", shards.icon, "BOTTOM", 0, -2)
		shards.text:SetTextColor(1, 0.45, 0.35)
		shards.text:SetShadowColor(0, 0, 0, 1)
		shards.text:SetShadowOffset(1, -1)
		LockRemindersWarlock.shards = shards
		LockRemindersApplyNamedPoint(shards, "shardPoint", { "CENTER", "CENTER", -180, -80 })
		shards:Hide()
	end
	LockRemindersApplyClassLook()
end


function LockRemindersPetEnabled(field)
	if not LockRemindersIsWarlock() or not db then
		return false
	end
	return db[field] ~= false
end

function LockRemindersPetSpellIcon(kind)
	if kind == "lock" then
		return SpellIcon(19647) or 136174
	end
	if kind == "purge" then
		return SpellIcon(19505) or 136075
	end
	if kind == "seduce" then
		return SpellIcon(6358) or 136175
	end
	return 136216
end

function LockRemindersPetColor()
	return 0.45, 1.0, 0.62
end

function LockRemindersFitPetShade(frame)
	LockRemindersFitBanishShade(frame)
	if not frame then
		return
	end
	if frame.shade then
		frame.shade:SetVertexColor(0.02, 0.16, 0.08, 0.68)
	end
	if frame.fadeLeft then
		frame.fadeLeft:SetVertexColor(0.01, 0.1, 0.05, 0.45)
	end
	if frame.fadeRight then
		frame.fadeRight:SetVertexColor(0.01, 0.1, 0.05, 0.45)
	end
end

function LockRemindersPetField(kind, suffix)
	if kind == "lock" then
		return "petLock" .. suffix
	elseif kind == "purge" then
		return "petPurge" .. suffix
	end
	return "petSeduce" .. suffix
end

function LockRemindersPetDefaults(kind)
	if kind == "lock" then
		return "SPELL LOCK", 19647, "Interface\\Icons\\Spell_Shadow_MindRot", { "CENTER", "CENTER", 0, 160 }
	elseif kind == "purge" then
		return "DEVOUR MAGIC", 19505, "Interface\\Icons\\Spell_Nature_Purge", { "CENTER", "CENTER", 0, 90 }
	end
	return "SEDUCTION", 6358, "Interface\\Icons\\Spell_Shadow_MindSteal", { "CENTER", "CENTER", 180, 40 }
end

function LockRemindersSyncScopeChecks(boxes, scope)
	if type(boxes) ~= "table" then
		return
	end
	local always, party, raid, instance = ScopeFlags(scope)
	if boxes.always then
		boxes.always:SetChecked(always)
	end
	if boxes.party then
		boxes.party:SetChecked(party)
	end
	if boxes.raid then
		boxes.raid:SetChecked(raid)
	end
	if boxes.instance then
		boxes.instance:SetChecked(instance)
	end
end

function LockRemindersApplyPetLook()
	local red, green, blue = LockRemindersPetColor()
	for _, kind in ipairs({ "lock", "purge", "seduce" }) do
		local frame = LockRemindersPet[kind]
		if frame and frame.icon then
			local sizeField = LockRemindersPetField(kind, "Size")
			local size = tonumber(db and db[sizeField]) or 48
			if size < 32 then size = 32 elseif size > 96 then size = 96 end
			if db then db[sizeField] = size end
			frame.icon:ClearAllPoints()
			frame.icon:SetPoint("LEFT", 7, 0)
			frame.icon:SetSize(size, size)
			frame.icon:SetTexCoord(0, 1, 0, 1)
			if frame.cooldown then
				frame.cooldown:ClearAllPoints()
				frame.cooldown:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
				frame.cooldown:SetSize(size, size)
			end
			frame.text:SetFont("Fonts\\FRIZQT__.TTF", math.max(16, math.floor(size * 0.4)), "OUTLINE")
			frame.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(18, math.floor(size * 0.52)), "OUTLINE")
			if frame.seconds then
				frame.seconds:SetFont("Fonts\\FRIZQT__.TTF", math.max(13, math.floor(size * 0.3)), "OUTLINE")
			end
			frame.sub:SetFont("Fonts\\FRIZQT__.TTF", math.max(11, math.floor(size * 0.24)), "OUTLINE")
			frame.text:SetTextColor(red, green, blue)
			frame.count:SetTextColor(red, green, blue)
			if frame.seconds then frame.seconds:SetTextColor(red, green, blue) end
			frame.sub:SetTextColor(0.85, 1, 0.9)
			local _, spellID, fallback = LockRemindersPetDefaults(kind)
			local icon = SpellIcon(spellID)
			if not icon or icon == 134400 then icon = fallback end
			frame.icon:SetTexture(icon)
			LockRemindersSmoothIcon(frame.icon)
			pcall(frame.SetBackdrop, frame, nil)
		end
	end
end

function LockRemindersPaintPetBanner(frame, kind, seconds, sub, cooldownKey)
	if not frame then return end
	LockRemindersApplyPetLook()
	local label = LockRemindersClassLabel(LockRemindersPetField(kind, "Label"), false)
	frame.text:SetText(label or "")
	frame.text:SetShown(label ~= nil and label ~= "")
	frame.count:SetText(tostring(math.max(1, math.ceil(seconds))))
	if frame.seconds then
		local word = SECONDS
		if type(word) ~= "string" or word == "" then word = "Seconds" end
		frame.seconds:SetText(word)
		frame.seconds:Show()
	end
	frame.sub:SetText(sub or "")
	frame.sub:SetShown(sub and sub ~= "")
	frame.text:ClearAllPoints()
	frame.count:ClearAllPoints()
	if frame.seconds then frame.seconds:ClearAllPoints() end
	frame.sub:ClearAllPoints()
	if frame.text:IsShown() then
		frame.text:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -1)
		frame.count:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -2)
	else
		frame.count:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -1)
	end
	if frame.seconds then frame.seconds:SetPoint("LEFT", frame.count, "RIGHT", 6, -1) end
	if frame.sub:IsShown() then frame.sub:SetPoint("TOPLEFT", frame.count, "BOTTOMLEFT", 0, -1) end
	local nameW = frame.text:IsShown() and frame.text:GetStringWidth() or 0
	local timeW = frame.count:GetStringWidth()
	if frame.seconds and frame.seconds:IsShown() then timeW = timeW + 6 + frame.seconds:GetStringWidth() end
	local subW = frame.sub:IsShown() and frame.sub:GetStringWidth() or 0
	local textW = math.max(nameW, timeW, subW, 72)
	local size = frame.icon:GetWidth()
	if size < 1 then size = tonumber(db[LockRemindersPetField(kind, "Size")]) or 48 end
	local stack = (frame.text:IsShown() and frame.text:GetStringHeight() + 2 or 0) + frame.count:GetStringHeight()
	if frame.sub:IsShown() then stack = stack + 2 + frame.sub:GetStringHeight() end
	frame:SetSize(7 + size + 10 + textW + 14, math.max(size + 14, stack + 16))
	LockRemindersFitPetShade(frame)
	if frame.cooldown then
		if not cooldownKey then
			frame.cooldown:Hide()
			frame.cooldownKey = nil
		elseif cooldownKey ~= frame.cooldownKey and frame.cooldown.SetCooldown then
			frame.cooldownKey = cooldownKey
			frame.cooldown:SetCooldown(GetTime(), math.max(0.2, seconds))
			frame.cooldown:Show()
		end
	end
	frame:Show()
end

function LockRemindersTriggerPetBanner(kind, sub)
	if not LockRemindersIsWarlock() or not db then return end
	if not LockRemindersClassShown(LockRemindersPetField(kind, "Alert"), LockRemindersPetField(kind, "Scope")) then return end
	LockRemindersCreatePetAlerts()
	local hold = tonumber(db[LockRemindersPetField(kind, "Warn")]) or (kind == "seduce" and 5 or 3)
	if hold < 1 then hold = 1 end
	LockRemindersPet[kind .. "Moving"] = false
	LockRemindersPet[kind .. "Preview"] = GetTime() + hold
	LockRemindersPet[kind .. "Sub"] = sub
	LockRemindersPlaySoundId(db.petSound or db.soulSound or "chiji")
	pcall(LockRemindersUpdatePetAlerts)
end

function LockRemindersPetResolveSpell(first, second, third)
	local secrets = {}
	local function keep(value)
		if value == nil then return nil end
		if LockRemindersSecret(value) then
			secrets[#secrets + 1] = value
			return nil
		end
		return value
	end
	first, second, third = keep(first), keep(second), keep(third)
	local spellID = tonumber(third) or tonumber(second) or tonumber(first)
	local spellName
	if type(first) == "string" and first ~= "" and not first:find("-", 1, true) then
		spellName = first
	elseif type(second) == "string" and second ~= "" and not second:find("-", 1, true) then
		spellName = second
	elseif spellID then
		spellName = SpellName(spellID)
	end
	if not spellID then
		local ids = { 19244, 19647, 19505, 19731, 19734, 19736, 27276, 27277, 6358 }
		for index = 1, #secrets do
			for idIndex = 1, #ids do
				if LockRemindersSameSpell(secrets[index], ids[idIndex]) then
					spellID = ids[idIndex]
					break
				end
			end
			if spellID then break end
		end
	end
	return spellID, spellName
end

function LockRemindersPetTargetGuid()
	local aim = "pettarget"
	if not (UnitExists and UnitExists(aim)) then aim = "target" end
	if not (UnitExists and UnitExists(aim)) then return nil, aim end
	local ok, guid = pcall(UnitGUID, aim)
	if ok and type(guid) == "string" and guid ~= "" and not LockRemindersSecret(guid) then
		return guid, aim
	end
	return nil, aim
end

function LockRemindersPetNoteCast(unit, first, second, third)
	if unit ~= "pet" or not LockRemindersIsWarlock() or not db then return end
	local spellID, spellName = LockRemindersPetResolveSpell(first, second, third)
	local guid, aim = LockRemindersPetTargetGuid()
	local targetName = LockRemindersUnitLabel and LockRemindersUnitLabel(aim, false) or nil
	if LockRemindersIsInterrupt(spellID, spellName) and LockRemindersClassShown("petLockAlert", "petLockScope") then
		LockRemindersPet.lockAt = GetTime()
		LockRemindersPet.lockGuid = guid
		LockRemindersPet.lockShown = false
		if C_Timer and C_Timer.After then
			C_Timer.After(0.95, function()
				if LockRemindersPet.lockShown then return end
				if not LockRemindersPet.lockAt or GetTime() - LockRemindersPet.lockAt < 0.9 then return end
				LockRemindersPet.lockShown = true
				LockRemindersTriggerPetBanner("lock", targetName or "Pet")
			end)
		end
	end
	if LockRemindersIsDevourMagic(spellID, spellName) and LockRemindersClassShown("petPurgeAlert", "petPurgeScope") then
		LockRemindersTriggerPetBanner("purge", targetName or "Purge")
	end
	if LockRemindersIsSeduction(spellID, spellName) and LockRemindersClassShown("petSeduceAlert", "petSeduceScope") then
		local key = guid or ("fallback:" .. tostring(targetName or "seduce"))
		LockRemindersPet.seduction = LockRemindersPet.seduction or {}
		LockRemindersPet.seduction.ends = LockRemindersPet.seduction.ends or {}
		LockRemindersPet.seduction.applied = LockRemindersPet.seduction.applied or {}
		LockRemindersPet.seduction.names = LockRemindersPet.seduction.names or {}
		LockRemindersPet.seduction.ends[key] = GetTime() + (tonumber(db.petSeduceSeconds) or 15)
		LockRemindersPet.seduction.applied[key] = GetTime()
		LockRemindersPet.seduction.names[key] = targetName
		pcall(LockRemindersUpdatePetAlerts)
	end
end

function LockRemindersPetNoteInterrupt(unit)
	if LockRemindersPet.lockShown then return end
	if not LockRemindersClassShown("petLockAlert", "petLockScope") then return end
	if not LockRemindersPet.lockAt or GetTime() - LockRemindersPet.lockAt > 2.2 then return end
	local guid = LockRemindersMissGuid and LockRemindersMissGuid(unit)
	if LockRemindersPet.lockGuid then
		if not guid or LockRemindersPet.lockGuid ~= guid then
			return
		end
	elseif unit ~= "target" and unit ~= "pettarget" then
		return
	end
	LockRemindersPet.lockShown = true
	local name = LockRemindersUnitLabel and LockRemindersUnitLabel(unit, false) or nil
	LockRemindersTriggerPetBanner("lock", name or "Interrupted")
end

function LockRemindersClearPetSeduction(guid)
	local data = LockRemindersPet.seduction
	if not data or type(guid) ~= "string" then return false end
	local cleared = false
	if data.ends and data.ends[guid] then data.ends[guid] = nil; cleared = true end
	if data.applied then data.applied[guid] = nil end
	if data.names then data.names[guid] = nil end
	if cleared then pcall(LockRemindersUpdatePetAlerts) end
	return cleared
end

function LockRemindersSoonestSeduction()
	local data = LockRemindersPet.seduction
	if not data or type(data.ends) ~= "table" then return end
	local now = GetTime()
	local bestLeft, bestEnds, bestName, bestGuid
	for guid, ends in pairs(data.ends) do
		ends = tonumber(ends)
		if ends then
			local left = ends - now
			if left <= 0 then
				data.ends[guid] = nil
			elseif not bestLeft or left < bestLeft then
				bestLeft, bestEnds, bestGuid = left, ends, guid
				bestName = data.names and data.names[guid]
			end
		end
	end
	return bestLeft, bestEnds, bestName, bestGuid
end

function LockRemindersCreatePetAlerts()
	if not LockRemindersIsWarlock() then return end
	local function banner(kind)
		if LockRemindersPet[kind] then return LockRemindersPet[kind] end
		local pointKey = LockRemindersPetField(kind, "Point")
		local movingKey = kind .. "Moving"
		local frame = CreateFrame("Frame", "LockRemindersPet" .. kind, UIParent, "BackdropTemplate")
		frame:SetFrameStrata("HIGH")
		frame:SetClampedToScreen(true)
		frame:SetMovable(true)
		frame:EnableMouse(false)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self)
			if LockRemindersPet[movingKey] then self:StartMoving() end
		end)
		frame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			LockRemindersSaveNamedPoint(self, pointKey)
		end)
		pcall(frame.SetBackdrop, frame, nil)
		frame.fadeLeft = frame:CreateTexture(nil, "BACKGROUND")
		frame.fadeLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
		frame.shade = frame:CreateTexture(nil, "BACKGROUND")
		frame.shade:SetTexture("Interface\\Buttons\\WHITE8x8")
		frame.fadeRight = frame:CreateTexture(nil, "BACKGROUND")
		frame.fadeRight:SetTexture("Interface\\Buttons\\WHITE8x8")
		frame.icon = frame:CreateTexture(nil, "ARTWORK")
		frame.icon:SetTexCoord(0, 1, 0, 1)
		LockRemindersSmoothIcon(frame.icon)
		local okCD, cooldown = pcall(CreateFrame, "Cooldown", nil, frame, "CooldownFrameTemplate")
		if okCD and cooldown then
			pcall(cooldown.SetDrawBling, cooldown, false)
			if cooldown.SetHideCountdownNumbers then pcall(cooldown.SetHideCountdownNumbers, cooldown, true) end
			if cooldown.SetDrawEdge then pcall(cooldown.SetDrawEdge, cooldown, false) end
			frame.cooldown = cooldown
		end
		local red, green, blue = LockRemindersPetColor()
		frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		frame.text:SetJustifyH("LEFT")
		frame.text:SetTextColor(red, green, blue)
		frame.text:SetShadowColor(0, 0, 0, 1)
		frame.text:SetShadowOffset(1, -1)
		frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		frame.count:SetJustifyH("LEFT")
		frame.count:SetTextColor(red, green, blue)
		frame.count:SetShadowColor(0, 0, 0, 1)
		frame.count:SetShadowOffset(1, -1)
		frame.seconds = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.seconds:SetJustifyH("LEFT")
		frame.seconds:SetTextColor(red, green, blue)
		frame.seconds:SetShadowColor(0, 0, 0, 1)
		frame.seconds:SetShadowOffset(1, -1)
		frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		frame.sub:SetJustifyH("LEFT")
		frame.sub:SetTextColor(0.85, 1, 0.9)
		LockRemindersPet[kind] = frame
		local _, _, _, defaultPoint = LockRemindersPetDefaults(kind)
		LockRemindersApplyNamedPoint(frame, pointKey, defaultPoint)
		frame:Hide()
		return frame
	end
	banner("lock")
	banner("purge")
	banner("seduce")
	LockRemindersApplyPetLook()
end

function LockRemindersUpdatePetAlerts()
	if not LockRemindersIsWarlock() or not db then return end
	LockRemindersCreatePetAlerts()
	local now = GetTime()
	local function showKind(kind)
		local frame = LockRemindersPet[kind]
		if not frame then return end
		local moving = LockRemindersPet[kind .. "Moving"]
		local preview = LockRemindersPet[kind .. "Preview"]
		frame:EnableMouse(moving and true or false)
		if preview and now >= preview then
			LockRemindersPet[kind .. "Preview"] = nil
			preview = nil
		end
		if moving then
			LockRemindersPaintPetBanner(frame, kind, 5, "Drag")
			return
		end
		if preview and now < preview then
			LockRemindersPaintPetBanner(frame, kind, preview - now, LockRemindersPet[kind .. "Sub"] or "Target", "preview:" .. tostring(math.floor(preview)))
			return
		end
		if kind == "seduce" then
			if not LockRemindersClassShown("petSeduceAlert", "petSeduceScope") then
				frame:Hide(); frame.cooldownKey = nil; return
			end
			local left, ends, name, guid = LockRemindersSoonestSeduction()
			local warn = tonumber(db.petSeduceWarn) or 5
			if left and left <= warn then
				local key = tostring(guid or name or "seduce") .. ":" .. tostring(math.floor(ends or 0))
				LockRemindersPaintPetBanner(frame, kind, left, name or "", key)
				if key ~= LockRemindersPet.seduceKey then
					LockRemindersPet.seduceKey = key
					LockRemindersPlaySoundId(db.petSound or db.soulSound or "chiji")
				end
			else
				frame:Hide(); frame.cooldownKey = nil
				if not left then LockRemindersPet.seduceKey = nil end
			end
			return
		end
		frame:Hide()
		frame.cooldownKey = nil
	end
	showKind("lock")
	showKind("purge")
	showKind("seduce")
end

function LockRemindersRefreshPets()
	if not panel or not panel.petBar then return end
	local bar = panel.petBar
	local function paint(button, on)
		if on then
			button.label:SetText("On")
			Paint(button, 0.22, 0.36, 0.22, 1, 0.45, 0.85, 0.5, 1)
		else
			button.label:SetText("Off")
			Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		end
	end
	for _, kind in ipairs({ "lock", "purge", "seduce" }) do
		local toggleBtn = bar[kind .. "Toggle"]
		if toggleBtn then paint(toggleBtn, db[LockRemindersPetField(kind, "Alert")] ~= false) end
		if bar[kind .. "Warn"] then
			bar[kind .. "Warn"]:SetText(tostring(tonumber(db[LockRemindersPetField(kind, "Warn")]) or (kind == "seduce" and 5 or 3)))
		end
		if bar[kind .. "Size"] then
			bar[kind .. "Size"]:SetText(tostring(tonumber(db[LockRemindersPetField(kind, "Size")]) or 48))
		end
		if bar[kind .. "Move"] then
			bar[kind .. "Move"].label:SetText(LockRemindersPet[kind .. "Moving"] and "Done" or "Move")
		end
		if bar[kind .. "Checks"] then
			LockRemindersSyncScopeChecks(bar[kind .. "Checks"], db[LockRemindersPetField(kind, "Scope")])
		end
	end
	LockRemindersUpdatePetAlerts()
end

function LockRemindersBuildPets(owner)
	local bar = LockRemindersOpenSettings(owner, "petBar")
	local function toggle(parent, field, x, y)
		local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
		button:SetSize(48, 22)
		button:SetPoint("TOPLEFT", x, y)
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button:SetScript("OnClick", function()
			db[field] = not (db[field] ~= false)
			LockRemindersRefreshPets()
		end)
		return button
	end
	local function step(parent, anchor, read, write, low, high, stepSize)
		return LockRemindersSettingsStepper(parent, anchor, 8, read, write, low, high, stepSize)
	end
	local function buildCard(kind, title, blurb)
		local label, _, icon = LockRemindersPetDefaults(kind)
		LockRemindersSettingsHead(bar, title)
		local card = LockRemindersSettingsCard(bar, 90, icon, title, blurb)
		local alertField = LockRemindersPetField(kind, "Alert")
		local scopeField = LockRemindersPetField(kind, "Scope")
		local warnField = LockRemindersPetField(kind, "Warn")
		local sizeField = LockRemindersPetField(kind, "Size")
		local labelField = LockRemindersPetField(kind, "Label")
		bar[kind .. "Toggle"] = toggle(card, alertField, 176, -14)
		bar[kind .. "Checks"] = LockRemindersMakeScopeChecks(card, bar[kind .. "Toggle"], scopeField)
		local warnCaption = kind == "seduce" and "Seconds" or "Hold"
		local warnLabel = LockRemindersSettingsCaption(card, bar[kind .. "Checks"].always.caption, warnCaption, 12)
		local warnPlus
		warnPlus, bar[kind .. "Warn"] = step(card, warnLabel, function()
			return db[warnField] or (kind == "seduce" and 5 or 3)
		end, function(value)
			db[warnField] = value
			LockRemindersRefreshPets()
		end, kind == "seduce" and 2 or 1, kind == "seduce" and 15 or 8, kind == "seduce" and 1 or 0.5)
		local sizeLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sizeLabel:SetPoint("TOPLEFT", 176, -50)
		sizeLabel:SetText("Size")
		sizeLabel:SetTextColor(0.9, 0.84, 1)
		local sizePlus
		sizePlus, bar[kind .. "Size"] = step(card, sizeLabel, function()
			return db[sizeField] or 48
		end, function(value)
			db[sizeField] = value
			LockRemindersApplyPetLook()
			LockRemindersUpdatePetAlerts()
			LockRemindersRefreshPets()
		end, 32, 96, 4)
		local textLabel = LockRemindersSettingsCaption(card, sizePlus, "Text", 12)
		bar[kind .. "Label"] = LockRemindersSettingsEdit(card, textLabel, labelField, label, 140, function()
			LockRemindersApplyPetLook()
			LockRemindersUpdatePetAlerts()
		end, true)
		bar[kind .. "Move"] = LockRemindersSettingsButton(card, bar[kind .. "Label"], "Move", 10, function()
			LockRemindersCreatePetAlerts()
			LockRemindersPet[kind .. "Moving"] = not LockRemindersPet[kind .. "Moving"]
			LockRemindersPet[kind .. "Preview"] = nil
			for _, other in ipairs({ "lock", "purge", "seduce" }) do
				if other ~= kind then LockRemindersPet[other .. "Moving"] = false end
			end
			LockRemindersUpdatePetAlerts()
			LockRemindersRefreshPets()
		end)
		bar[kind .. "Test"] = LockRemindersSettingsButton(card, bar[kind .. "Move"], "Test", 8, function()
			LockRemindersCreatePetAlerts()
			local previewKey = kind .. "Preview"
			if LockRemindersPet[previewKey] and GetTime() < LockRemindersPet[previewKey] then
				LockRemindersPet[previewKey] = nil
				LockRemindersPet[kind .. "Moving"] = false
			else
				LockRemindersTriggerPetBanner(kind, "Target")
			end
			LockRemindersUpdatePetAlerts()
			LockRemindersRefreshPets()
		end)
		LockRemindersPinSettingsActions(bar[kind .. "Move"], bar[kind .. "Test"], card, -50)
	end
	buildCard("lock", "Spell Lock", "Cast and interrupt")
	buildCard("purge", "Devour Magic", "On cast")
	buildCard("seduce", "Seduction", "Countdown")
	LockRemindersSettingsHead(bar, "Sound")
	local soundCard = LockRemindersSettingsCard(bar, 56, LockRemindersPetSpellIcon("lock"), "Pet alerts", "Shared sound")
	local soundLabel = soundCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	soundLabel:SetPoint("TOPLEFT", 176, -18)
	soundLabel:SetText("Sound")
	soundLabel:SetTextColor(0.9, 0.84, 1)
	bar.refreshSound = LockRemindersMakeSoundRow(soundCard, soundLabel, function()
		return db and db.petSound or "chiji"
	end, function(id)
		db.petSound = id
	end)
end


function CreateSoulAlerts()
	if not LockRemindersIsWarlock() then
		return
	end
	LockRemindersCreateClassAlerts()
	if LockRemindersSoul.alert then
		return
	end
	local frame = CreateFrame("Frame", "LockRemindersSoulAlert", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if LockRemindersSoul.moving then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveNamedPoint(self, "soulPoint")
	end)
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOP", 0, -4)
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	LockRemindersRoundIcon(frame.icon)
	frame.glow = LockRemindersMakeEvenGlow(frame)
	LockRemindersTintEvenGlow(frame.glow, 0.72, 0.4, 1)
	frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.label:SetPoint("TOP", frame.icon, "BOTTOM", 0, -2)
	frame.label:SetText("SOULSTONE")
	frame.label:SetTextColor(0.86, 0.7, 1)
	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.hint:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	frame.hint:SetText("Drag")
	frame.hint:SetTextColor(0.8, 0.65, 1)
	frame.hint:Hide()
	frame:EnableMouse(false)
	LockRemindersSoul.alert = frame
	LockRemindersAttachPop(frame, function()
		if LockRemindersSoul.moving then
			return true
		end
		if LockRemindersSoul.previewUntil and GetTime() < LockRemindersSoul.previewUntil then
			return true
		end
		return LockRemindersSoul.missing
	end)
	LockRemindersApplySoulLook()
	LockRemindersApplyNamedPoint(frame, "soulPoint", { "CENTER", "CENTER", 0, 180 })
	LockRemindersSyncSoulClick()
	frame:Hide()

	local tracker = CreateFrame("Frame", "LockRemindersSoulTracker", UIParent, "BackdropTemplate")
	tracker:SetFrameStrata("MEDIUM")
	tracker:SetClampedToScreen(true)
	tracker:SetMovable(true)
	tracker:EnableMouse(true)
	tracker:RegisterForDrag("LeftButton")
	tracker:SetSize(250, 48)
	tracker:SetScript("OnDragStart", function(self)
		if LockRemindersSoul.trackMoving then
			self:StartMoving()
		end
	end)
	tracker:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveNamedPoint(self, "soulTrackPoint")
	end)
	tracker:SetScript("OnUpdate", function()
		LockRemindersTickSoulRows()
	end)
	Paint(tracker, 0.06, 0.05, 0.08, 0.92, 0.45, 0.32, 0.62, 1)
	tracker.activeTitle = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tracker.activeTitle:SetText("Active")
	tracker.activeTitle:SetTextColor(0.78, 0.7, 0.95)
	tracker.readyTitle = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tracker.readyTitle:SetText("Not used")
	tracker.readyTitle:SetTextColor(0.78, 0.7, 0.95)
	tracker.hint = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tracker.hint:SetPoint("TOP", tracker, "BOTTOM", 0, -2)
	tracker.hint:SetText("Drag")
	tracker.hint:SetTextColor(0.8, 0.65, 1)
	tracker.hint:Hide()
	tracker:EnableMouse(false)
	LockRemindersSoul.tracker = tracker
	LockRemindersApplyNamedPoint(tracker, "soulTrackPoint", { "CENTER", "CENTER", -280, 40 })
	LockRemindersApplySoulTrackLook()
	tracker:Hide()
end

function CreateFoodAlert()
	if foodFrame then
		return
	end
	foodFrame = CreateFrame("Frame", "LockRemindersFoodAlert", UIParent, "BackdropTemplate")
	foodFrame:SetFrameStrata("HIGH")
	foodFrame:SetClampedToScreen(true)
	foodFrame:SetMovable(true)
	foodFrame:EnableMouse(true)
	foodFrame:RegisterForDrag("LeftButton")
	foodFrame:SetScript("OnDragStart", function(self)
		if self.moving or db.foodLocked == false then
			self:StartMoving()
		end
	end)
	foodFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveFoodPoint()
	end)
	foodFrame.icon = foodFrame:CreateTexture(nil, "ARTWORK")
	foodFrame.icon:SetPoint("TOPLEFT", 2, -2)
	foodFrame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	foodFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	LockRemindersRoundIcon(foodFrame.icon)
	foodFrame.glow = LockRemindersMakeEvenGlow(foodFrame)
	LockRemindersTintEvenGlow(foodFrame.glow, 1, 0.82, 0.35)
	foodFrame.glow:Hide()
	foodFrame.stone = foodFrame:CreateTexture(nil, "ARTWORK")
	foodFrame.stone:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	LockRemindersRoundIcon(foodFrame.stone)
	foodFrame.stone:Hide()
	foodFrame.stoneGlow = LockRemindersMakeEvenGlow(foodFrame)
	LockRemindersTintEvenGlow(foodFrame.stoneGlow, 1, 0.82, 0.35)
	foodFrame.stoneGlow:Hide()
	foodFrame.count = foodFrame:CreateFontString(nil, "OVERLAY")
	foodFrame.count:SetPoint("CENTER", foodFrame.icon, "CENTER", 0, 0)
	foodFrame.count:SetJustifyH("CENTER")
	foodFrame.count:SetJustifyV("MIDDLE")
	foodFrame.count:SetTextColor(1, 1, 1)
	foodFrame.count:Hide()
	foodFrame.foodHit = CreateFrame("Button", nil, foodFrame)
	foodFrame.foodHit:SetFrameLevel((foodFrame:GetFrameLevel() or 1) + 6)
	foodFrame.foodHit:Hide()
	LockRemindersBindItemDrag(foodFrame.foodHit, foodFrame.icon, foodFrame.glow, "food")
	foodFrame.stoneHit = CreateFrame("Button", nil, foodFrame)
	foodFrame.stoneHit:SetFrameLevel((foodFrame:GetFrameLevel() or 1) + 6)
	foodFrame.stoneHit:Hide()
	LockRemindersBindItemDrag(foodFrame.stoneHit, foodFrame.stone, foodFrame.stoneGlow, "healthstone")
	foodFrame.hint = foodFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	foodFrame.hint:SetPoint("TOP", foodFrame, "BOTTOM", 0, -6)
	foodFrame.hint:SetText("Drag")
	foodFrame.hint:SetTextColor(1, 0.86, 0.45)
	foodFrame.hint:Hide()
	ApplyFoodLook()
	ApplyFoodPoint()
	foodFrame:Hide()
end

function CreateTalentAlert()
	if talentFrame then
		return
	end
	talentFrame = CreateFrame("Frame", "LockRemindersTalentAlert", UIParent, "BackdropTemplate")
	talentFrame:SetFrameStrata("HIGH")
	talentFrame:SetClampedToScreen(true)
	talentFrame:SetMovable(true)
	talentFrame:EnableMouse(true)
	talentFrame:RegisterForDrag("LeftButton")
	talentFrame:SetScript("OnDragStart", function(self)
		if talentMoving then
			self:StartMoving()
		end
	end)
	talentFrame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveTalentPoint()
	end)
	talentFrame.icon = talentFrame:CreateTexture(nil, "ARTWORK")
	talentFrame.icon:SetPoint("TOPLEFT", 2, -2)
	talentFrame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	talentFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	LockRemindersRoundIcon(talentFrame.icon)
	talentFrame.ornament = talentFrame:CreateTexture(nil, "OVERLAY")
	talentFrame.ornament:SetPoint("CENTER")
	talentFrame.ornament:SetBlendMode("ADD")
	talentFrame.ornament:Hide()
	talentFrame.glow = LockRemindersMakeEvenGlow(talentFrame)
	LockRemindersTintEvenGlow(talentFrame.glow, 1, 0.82, 0.35)
	talentFrame.burst = CreateFrame("Frame", nil, talentFrame)
	talentFrame.burst:SetPoint("CENTER")
	talentFrame.burst.tex = talentFrame.burst:CreateTexture(nil, "OVERLAY")
	talentFrame.burst.tex:SetAllPoints()
	talentFrame.burst.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	talentFrame.burst.tex:SetBlendMode("ADD")
	talentFrame.burst.tex:SetVertexColor(1, 0.9, 0.55)
	talentFrame.burst:SetAlpha(0)
	local burst = talentFrame.burst:CreateAnimationGroup()
	local burstScale = burst:CreateAnimation("Scale")
	burstScale:SetScale(1.65, 1.65)
	burstScale:SetOrigin("CENTER", 0, 0)
	burstScale:SetDuration(0.42)
	burstScale:SetSmoothing("OUT")
	local burstFade = burst:CreateAnimation("Alpha")
	burstFade:SetFromAlpha(0.9)
	burstFade:SetToAlpha(0)
	burstFade:SetDuration(0.42)
	burst:SetScript("OnFinished", function()
		talentFrame.burst:SetScale(1)
		talentFrame.burst:SetAlpha(0)
	end)
	talentFrame.burstAg = burst
	local pop = talentFrame:CreateAnimationGroup()
	local grow = pop:CreateAnimation("Scale")
	grow:SetScale(1.22, 1.22)
	grow:SetOrigin("CENTER", 0, 0)
	grow:SetDuration(0.12)
	grow:SetOrder(1)
	grow:SetSmoothing("OUT")
	local settle = pop:CreateAnimation("Scale")
	settle:SetScale(0.82, 0.82)
	settle:SetOrigin("CENTER", 0, 0)
	settle:SetDuration(0.16)
	settle:SetOrder(2)
	settle:SetSmoothing("OUT")
	pop:SetScript("OnFinished", function()
		if talentFrame then
			talentFrame:SetScale(1)
		end
	end)
	talentFrame.pop = pop
	local fade = talentFrame:CreateAnimationGroup()
	local fadeOut = fade:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.35)
	fade:SetScript("OnFinished", function()
		if talentFrame and not talentMoving then
			LockRemindersHideTalentOrnament()
			talentFrame:Hide()
			talentFrame:SetAlpha(1)
		end
	end)
	talentFrame.fade = fade
	talentFrame.fadeOut = fadeOut
	talentFrame.hint = talentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	talentFrame.hint:SetPoint("TOP", talentFrame, "BOTTOM", 0, -6)
	talentFrame.hint:SetText("Drag")
	talentFrame.hint:SetTextColor(1, 0.86, 0.45)
	talentFrame.hint:Hide()
	local screenFlash = CreateFrame("Frame", "LockRemindersScreenFlash", UIParent)
	screenFlash:SetAllPoints(UIParent)
	screenFlash:SetFrameStrata("FULLSCREEN")
	screenFlash:EnableMouse(false)
	screenFlash.tex = screenFlash:CreateTexture(nil, "ARTWORK")
	screenFlash.tex:SetAllPoints()
	screenFlash.tex:SetTexture("Interface\\Buttons\\WHITE8x8")
	screenFlash.tex:SetBlendMode("ADD")
	screenFlash.tex:SetVertexColor(1, 0.82, 0.35)
	screenFlash:SetAlpha(0)
	local screenAg = screenFlash:CreateAnimationGroup()
	local screenFade = screenAg:CreateAnimation("Alpha")
	screenFade:SetFromAlpha(0.55)
	screenFade:SetToAlpha(0)
	screenFade:SetDuration(0.45)
	screenFade:SetSmoothing("OUT")
	screenAg:SetScript("OnFinished", function()
		screenFlash:Hide()
		screenFlash:SetAlpha(0)
	end)
	screenFlash.ag = screenAg
	screenFlash:Hide()
	talentFrame.screenFlash = screenFlash
	ApplyTalentLook()
	ApplyTalentPoint()
	talentFrame:Hide()
end

local function CreatePanel()
	panel = CreateFrame("Frame", "LockRemindersPanel", UIParent, "BackdropTemplate")
	panel:SetSize(760, 800)
	panel:SetFrameStrata("HIGH")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	if not TryElvUI(panel) then
		Paint(panel, 0.06, 0.05, 0.08, 0.97, 0.58, 0.45, 0.82, 1)
	end
	if db.panelPoint then
		panel:SetPoint(db.panelPoint[1], UIParent, db.panelPoint[2], db.panelPoint[3], db.panelPoint[4])
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end

	local drag = CreateFrame("Frame", nil, panel)
	drag:SetPoint("TOPLEFT")
	drag:SetPoint("TOPRIGHT", -40, 0)
	drag:SetHeight(42)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	drag:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		local point, _, relative, x, y = panel:GetPoint()
		db.panelPoint = { point, relative, x, y }
	end)
	drag:SetScript("OnMouseDown", function()
		if searchBox then
			searchBox:ClearFocus()
		end
	end)

	local titleIcon = panel:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(20, 20)
	titleIcon:SetPoint("TOPLEFT", 14, -12)
	titleIcon:SetTexture(136216)
	titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
	title:SetText("LockReminders")
	title:SetTextColor(0.9, 0.82, 1)

	local close = CreateFrame("Button", nil, panel, "BackdropTemplate")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -12, -10)
	Paint(close, 0.2, 0.12, 0.16, 1, 0.7, 0.32, 0.38, 1)
	close.label = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	close.label:SetPoint("CENTER", 0, 0)
	close.label:SetText("X")
	close:SetScript("OnClick", HidePanel)
	close:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.45, 0.14, 0.18, 1)
	end)
	close:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.2, 0.12, 0.16, 1)
	end)

	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 12, -40)
	line:SetPoint("TOPRIGHT", -12, -40)
	line:SetHeight(1)
	line:SetTexture("Interface\\Buttons\\WHITE8x8")
	line:SetVertexColor(0.58, 0.45, 0.82, 0.45)

	CreateSearchBox()
	HookItemLinks()

	tabs = {}
	MakeTab("Buffs", "powers")
	MakeTab("Items", "food")
	MakeTab("Procs", "talents")
	MakeTab("Misses", "spells")
	MakeTab("CDs", "cds")
	MakeTab("Misc", "misc")
	if LockRemindersIsWarlock() then
		MakeTab("Warlock", "soul")
		MakeTab("Pets", "pets")
	end
	MakeTab("Fun", "fun")

	panel.backButton = CreateFrame("Button", nil, panel, "BackdropTemplate")
	panel.backButton:SetSize(88, 26)
	panel.backButton:SetPoint("TOPLEFT", 14, -48)
	Paint(panel.backButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	panel.backButton.label = panel.backButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.backButton.label:SetPoint("CENTER")
	panel.backButton.label:SetText("Back")
	panel.backButton:SetScript("OnClick", function()
		SetTab(panel.alertModule or "powers")
	end)
	panel.backButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	panel.backButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.backButton:Hide()

	panel.alertTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.alertTitle:SetPoint("LEFT", panel.backButton, "RIGHT", 16, 0)
	panel.alertTitle:SetText("Alert")
	panel.alertTitle:SetTextColor(0.95, 0.9, 1)
	panel.alertTitle:Hide()

	raidCheck = CreateFrame("Button", nil, panel, "BackdropTemplate")
	raidCheck:SetSize(72, 22)
	raidCheck:SetPoint("TOPLEFT", 112, -140)
	Paint(raidCheck, 0.18, 0.14, 0.28, 1, 0.58, 0.45, 0.82, 1)
	raidCheck.scopeText = raidCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	raidCheck.scopeText:SetPoint("CENTER", 0, 0)
	raidCheck.scopeText:SetText(ScopeLabel(addScope))
	raidCheck.scopeText:SetTextColor(0.94, 0.9, 1)
	raidCheck:SetScript("OnClick", function(self)
		addScope = NextScope(addScope)
		self.scopeText:SetText(ScopeLabel(addScope))
	end)
	raidCheck:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	raidCheck:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.18, 0.14, 0.28, 1)
	end)

	raidCheck.labelButton = CreateFrame("Button", nil, panel)
	raidCheck.labelButton:SetPoint("TOPLEFT", 16, -140)
	raidCheck.labelButton:SetSize(88, 22)
	raidCheck.labelButton.label = raidCheck.labelButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	raidCheck.labelButton.label:SetPoint("LEFT")
	raidCheck.labelButton.label:SetText("When adding")
	raidCheck.labelButton:SetScript("OnClick", function()
		raidCheck:Click()
	end)

	modeHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	modeHint:SetPoint("TOPLEFT", 16, -140)
	modeHint:SetWidth(520)
	modeHint:SetJustifyH("LEFT")
	modeHint:SetTextColor(0.75, 0.7, 0.84)
	modeHint:Hide()

	panel.alertButton = CreateFrame("Button", nil, panel, "BackdropTemplate")
	panel.alertButton:SetSize(140, 22)
	panel.alertButton:SetPoint("TOPRIGHT", -16, -140)
	Paint(panel.alertButton, 0.14, 0.1, 0.2, 1, 0.95, 0.78, 0.35, 1)
	panel.alertButton.label = panel.alertButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.alertButton.label:SetPoint("CENTER")
	panel.alertButton.label:SetText("Configure alert")
	panel.alertButton:SetScript("OnClick", function()
		if activeTab == "powers" or activeTab == "food" or activeTab == "talents" or activeTab == "spells" or activeTab == "cds" then
			panel.alertModule = activeTab
			SetTab("alert")
		end
	end)
	panel.alertButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	panel.alertButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.alertButton:Hide()

	talentBar = CreateFrame("Frame", nil, panel)
	talentBar:SetPoint("TOPLEFT", 14, -112)
	talentBar:SetPoint("TOPRIGHT", -16, -112)
	talentBar:SetHeight(278)
	talentBar:Hide()

	panel.foodBar = CreateFrame("Frame", nil, panel)
	panel.foodBar:SetPoint("TOPLEFT", 14, -112)
	panel.foodBar:SetPoint("TOPRIGHT", -16, -112)
	panel.foodBar:SetHeight(40)
	panel.foodBar:Hide()
	local foodSizeLabel = panel.foodBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	foodSizeLabel:SetPoint("TOPLEFT", 4, -8)
	foodSizeLabel:SetText("Size")
	foodSizeLabel:SetTextColor(0.9, 0.84, 1)
	local foodMinus = StepButton(panel.foodBar, "-")
	foodMinus:SetPoint("LEFT", foodSizeLabel, "RIGHT", 10, 0)
	foodMinus:SetScript("OnClick", function()
		ChangeFoodSize(-8)
	end)
	panel.foodBar.sizeText = panel.foodBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.foodBar.sizeText:SetPoint("LEFT", foodMinus, "RIGHT", 6, 0)
	panel.foodBar.sizeText:SetWidth(28)
	panel.foodBar.sizeText:SetJustifyH("CENTER")
	local foodPlus = StepButton(panel.foodBar, "+")
	foodPlus:SetPoint("LEFT", panel.foodBar.sizeText, "RIGHT", 2, 0)
	foodPlus:SetScript("OnClick", function()
		ChangeFoodSize(8)
	end)
	panel.foodBar.moveButton = CreateFrame("Button", nil, panel.foodBar, "BackdropTemplate")
	panel.foodBar.moveButton:SetSize(88, 22)
	panel.foodBar.moveButton:SetPoint("LEFT", foodPlus, "RIGHT", 16, 0)
	Paint(panel.foodBar.moveButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	panel.foodBar.moveButton.label = panel.foodBar.moveButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.foodBar.moveButton.label:SetPoint("CENTER")
	panel.foodBar.moveButton.label:SetText("Move")
	panel.foodBar.moveButton:SetScript("OnClick", function()
		ShowFoodPreview(not (foodFrame and foodFrame.moving))
	end)
	panel.foodBar.moveButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	panel.foodBar.moveButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.foodBar.glow = LockRemindersGlowSwatch(panel.foodBar, panel.foodBar.moveButton, 12, "foodGlow", 1, 0.82, 0.35, ApplyFoodLook)
	LockRemindersGlowBorderControl(panel.foodBar, panel.foodBar.glow, 10, "foodGlowSize", ApplyFoodLook)

	panel.spellBar = CreateFrame("Frame", nil, panel)
	panel.spellBar:SetPoint("TOPLEFT", 14, -112)
	panel.spellBar:SetPoint("TOPRIGHT", -16, -112)
	panel.spellBar:SetHeight(104)
	panel.spellBar:Hide()
	local missSizeLabel = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	missSizeLabel:SetPoint("TOPLEFT", 4, -8)
	missSizeLabel:SetText("Size")
	missSizeLabel:SetTextColor(0.9, 0.84, 1)
	local missMinus = StepButton(panel.spellBar, "-")
	missMinus:SetPoint("LEFT", missSizeLabel, "RIGHT", 10, 0)
	missMinus:SetScript("OnClick", function()
		ChangeMissSize(-4)
	end)
	panel.spellBar.sizeText = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.spellBar.sizeText:SetPoint("LEFT", missMinus, "RIGHT", 6, 0)
	panel.spellBar.sizeText:SetWidth(28)
	panel.spellBar.sizeText:SetJustifyH("CENTER")
	local missPlus = StepButton(panel.spellBar, "+")
	missPlus:SetPoint("LEFT", panel.spellBar.sizeText, "RIGHT", 2, 0)
	missPlus:SetScript("OnClick", function()
		ChangeMissSize(4)
	end)
	local missHoldLabel = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	missHoldLabel:SetPoint("LEFT", missPlus, "RIGHT", 18, 0)
	missHoldLabel:SetText("Seconds")
	missHoldLabel:SetTextColor(0.9, 0.84, 1)
	local missHoldMinus = StepButton(panel.spellBar, "-")
	missHoldMinus:SetPoint("LEFT", missHoldLabel, "RIGHT", 8, 0)
	missHoldMinus:SetScript("OnClick", function()
		ChangeMissHold(-0.5)
	end)
	panel.spellBar.holdText = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.spellBar.holdText:SetPoint("LEFT", missHoldMinus, "RIGHT", 6, 0)
	panel.spellBar.holdText:SetWidth(32)
	panel.spellBar.holdText:SetJustifyH("CENTER")
	local missHoldPlus = StepButton(panel.spellBar, "+")
	missHoldPlus:SetPoint("LEFT", panel.spellBar.holdText, "RIGHT", 2, 0)
	missHoldPlus:SetScript("OnClick", function()
		ChangeMissHold(0.5)
	end)
	panel.spellBar.moveButton = CreateFrame("Button", nil, panel.spellBar, "BackdropTemplate")
	panel.spellBar.moveButton:SetSize(72, 22)
	panel.spellBar.moveButton:SetPoint("TOPLEFT", 4, -40)
	Paint(panel.spellBar.moveButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	panel.spellBar.moveButton.label = panel.spellBar.moveButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.spellBar.moveButton.label:SetPoint("CENTER")
	panel.spellBar.moveButton.label:SetText("Move")
	panel.spellBar.moveButton:SetScript("OnClick", function()
		ShowMissPreview(not LockRemindersMiss.moving)
	end)
	panel.spellBar.moveButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	panel.spellBar.moveButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.spellBar.testButton = CreateFrame("Button", nil, panel.spellBar, "BackdropTemplate")
	panel.spellBar.testButton:SetSize(72, 22)
	panel.spellBar.testButton:SetPoint("LEFT", panel.spellBar.moveButton, "RIGHT", 8, 0)
	Paint(panel.spellBar.testButton, 0.14, 0.1, 0.2, 1, 0.95, 0.45, 0.35, 1)
	panel.spellBar.testButton.label = panel.spellBar.testButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.spellBar.testButton.label:SetPoint("CENTER")
	panel.spellBar.testButton.label:SetText("Test")
	panel.spellBar.testButton:SetScript("OnClick", function()
		if LockRemindersMiss.moving then
			ShowMissPreview(false)
		end
		if LockRemindersMiss.previewUntil and GetTime() < LockRemindersMiss.previewUntil then
			LockRemindersMiss.previewUntil = nil
			LockRemindersUpdateMissAlerts()
			return
		end
		ShowSpellMiss(686, "Shadow Bolt", 136235, "player", "RESIST", "Target")
	end)
	panel.spellBar.testButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.42, 0.16, 0.14, 1)
	end)
	panel.spellBar.testButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	local immuneLabel = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	immuneLabel:SetPoint("LEFT", panel.spellBar.testButton, "RIGHT", 12, 0)
	immuneLabel:SetText("Immune")
	immuneLabel:SetTextColor(1, 0.86, 0.35)
	panel.spellBar.immuneToggle = CreateFrame("Button", nil, panel.spellBar, "BackdropTemplate")
	panel.spellBar.immuneToggle:SetSize(48, 22)
	panel.spellBar.immuneToggle:SetPoint("LEFT", immuneLabel, "RIGHT", 8, 0)
	Paint(panel.spellBar.immuneToggle, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
	panel.spellBar.immuneToggle.label = panel.spellBar.immuneToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.spellBar.immuneToggle.label:SetPoint("CENTER")
	panel.spellBar.immuneToggle:SetScript("OnClick", function()
		db.immuneAlert = not (db.immuneAlert ~= false)
		if panel.spellBar.refresh then
			panel.spellBar.refresh()
		end
	end)
	panel.spellBar.immuneTest = CreateFrame("Button", nil, panel.spellBar, "BackdropTemplate")
	panel.spellBar.immuneTest:SetSize(72, 22)
	panel.spellBar.immuneTest:SetPoint("LEFT", panel.spellBar.immuneToggle, "RIGHT", 8, 0)
	Paint(panel.spellBar.immuneTest, 0.32, 0.24, 0.08, 1, 0.95, 0.78, 0.35, 1)
	panel.spellBar.immuneTest.label = panel.spellBar.immuneTest:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.spellBar.immuneTest.label:SetPoint("CENTER")
	panel.spellBar.immuneTest.label:SetText("Test")
	panel.spellBar.immuneTest.label:SetTextColor(1, 0.93, 0.72)
	panel.spellBar.immuneTest:SetScript("OnClick", function()
		if LockRemindersMiss.moving then
			ShowMissPreview(false)
		end
		ShowSpellMiss(5782, "Fear", 136183, "player", "IMMUNE", "Target")
	end)
	panel.spellBar.immuneTest:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.42, 0.32, 0.1, 1)
	end)
	panel.spellBar.immuneTest:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.32, 0.24, 0.08, 1)
	end)
	local missSoundLabel = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	missSoundLabel:SetPoint("TOPLEFT", 4, -76)
	missSoundLabel:SetText("Sound")
	missSoundLabel:SetTextColor(0.9, 0.84, 1)
	panel.spellBar.refreshSound = LockRemindersMakeSoundRow(panel.spellBar, missSoundLabel, function()
		return db and db.missSound or "zaps"
	end, function(id)
		db.missSound = id
	end)
	panel.spellBar.refresh = function()
		LockRemindersPaintToggle(panel.spellBar.immuneToggle, not db or db.immuneAlert ~= false)
		if panel.spellBar.refreshSound then
			panel.spellBar.refreshSound()
		end
	end

	panel.cdBar = CreateFrame("Frame", nil, panel)
	panel.cdBar:SetPoint("TOPLEFT", 14, -112)
	panel.cdBar:SetPoint("TOPRIGHT", -16, -112)
	panel.cdBar:SetHeight(210)
	panel.cdBar:Hide()
	local cdSizeLabel = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cdSizeLabel:SetPoint("TOPLEFT", 4, -8)
	cdSizeLabel:SetText("Size")
	cdSizeLabel:SetTextColor(0.9, 0.84, 1)
	local cdMinus = StepButton(panel.cdBar, "-")
	cdMinus:SetPoint("LEFT", cdSizeLabel, "RIGHT", 10, 0)
	cdMinus:SetScript("OnClick", function()
		LockRemindersChangeCDSize(-4)
	end)
	panel.cdBar.sizeText = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.cdBar.sizeText:SetPoint("LEFT", cdMinus, "RIGHT", 6, 0)
	panel.cdBar.sizeText:SetWidth(28)
	panel.cdBar.sizeText:SetJustifyH("CENTER")
	local cdPlus = StepButton(panel.cdBar, "+")
	cdPlus:SetPoint("LEFT", panel.cdBar.sizeText, "RIGHT", 2, 0)
	cdPlus:SetScript("OnClick", function()
		LockRemindersChangeCDSize(4)
	end)
	local cdHoldLabel = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cdHoldLabel:SetPoint("LEFT", cdPlus, "RIGHT", 18, 0)
	cdHoldLabel:SetText("Ready")
	cdHoldLabel:SetTextColor(0.9, 0.84, 1)
	local cdHoldMinus = StepButton(panel.cdBar, "-")
	cdHoldMinus:SetPoint("LEFT", cdHoldLabel, "RIGHT", 8, 0)
	cdHoldMinus:SetScript("OnClick", function()
		LockRemindersChangeCDHold(-0.4)
	end)
	panel.cdBar.holdText = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.cdBar.holdText:SetPoint("LEFT", cdHoldMinus, "RIGHT", 6, 0)
	panel.cdBar.holdText:SetWidth(32)
	panel.cdBar.holdText:SetJustifyH("CENTER")
	local cdHoldPlus = StepButton(panel.cdBar, "+")
	cdHoldPlus:SetPoint("LEFT", panel.cdBar.holdText, "RIGHT", 2, 0)
	cdHoldPlus:SetScript("OnClick", function()
		LockRemindersChangeCDHold(0.4)
	end)
	local cdPadLabel = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cdPadLabel:SetPoint("LEFT", cdHoldPlus, "RIGHT", 18, 0)
	cdPadLabel:SetText("Spacing")
	cdPadLabel:SetTextColor(0.9, 0.84, 1)
	local cdPadMinus = StepButton(panel.cdBar, "-")
	cdPadMinus:SetPoint("LEFT", cdPadLabel, "RIGHT", 8, 0)
	cdPadMinus:SetScript("OnClick", function()
		LockRemindersChangeCDPad(-2)
	end)
	panel.cdBar.padText = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.cdBar.padText:SetPoint("LEFT", cdPadMinus, "RIGHT", 6, 0)
	panel.cdBar.padText:SetWidth(28)
	panel.cdBar.padText:SetJustifyH("CENTER")
	local cdPadPlus = StepButton(panel.cdBar, "+")
	cdPadPlus:SetPoint("LEFT", panel.cdBar.padText, "RIGHT", 2, 0)
	cdPadPlus:SetScript("OnClick", function()
		LockRemindersChangeCDPad(2)
	end)
	panel.cdBar.moveButton = CreateFrame("Button", nil, panel.cdBar, "BackdropTemplate")
	panel.cdBar.moveButton:SetSize(72, 22)
	panel.cdBar.moveButton:SetPoint("TOPLEFT", 4, -40)
	Paint(panel.cdBar.moveButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	panel.cdBar.moveButton.label = panel.cdBar.moveButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.cdBar.moveButton.label:SetPoint("CENTER")
	panel.cdBar.moveButton.label:SetText("Move")
	panel.cdBar.moveButton:SetScript("OnClick", function()
		LockRemindersShowCDPreview(not LockRemindersCD.moving)
	end)
	panel.cdBar.moveButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	panel.cdBar.moveButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.cdBar.testButton = CreateFrame("Button", nil, panel.cdBar, "BackdropTemplate")
	panel.cdBar.testButton:SetSize(72, 22)
	panel.cdBar.testButton:SetPoint("LEFT", panel.cdBar.moveButton, "RIGHT", 8, 0)
	Paint(panel.cdBar.testButton, 0.14, 0.1, 0.2, 1, 0.95, 0.45, 0.35, 1)
	panel.cdBar.testButton.label = panel.cdBar.testButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.cdBar.testButton.label:SetPoint("CENTER")
	panel.cdBar.testButton.label:SetText("Test")
	panel.cdBar.testButton:SetScript("OnClick", function()
		LockRemindersTestCDReady()
	end)
	panel.cdBar.testButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.42, 0.16, 0.14, 1)
	end)
	panel.cdBar.testButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.cdBar.layoutToggle = CreateFrame("Button", nil, panel.cdBar, "BackdropTemplate")
	panel.cdBar.layoutToggle:SetSize(96, 22)
	panel.cdBar.layoutToggle:SetPoint("LEFT", panel.cdBar.testButton, "RIGHT", 8, 0)
	Paint(panel.cdBar.layoutToggle, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	panel.cdBar.layoutToggle.label = panel.cdBar.layoutToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.cdBar.layoutToggle.label:SetPoint("CENTER")
	panel.cdBar.layoutToggle:SetScript("OnClick", function()
		LockRemindersToggleCDVertical()
	end)
	panel.cdBar.layoutToggle:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	panel.cdBar.layoutToggle:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.cdBar.flashToggle = CreateFrame("Button", nil, panel.cdBar, "BackdropTemplate")
	panel.cdBar.flashToggle:SetSize(88, 22)
	panel.cdBar.flashToggle:SetPoint("LEFT", panel.cdBar.layoutToggle, "RIGHT", 8, 0)
	Paint(panel.cdBar.flashToggle, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
	panel.cdBar.flashToggle.label = panel.cdBar.flashToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.cdBar.flashToggle.label:SetPoint("CENTER")
	panel.cdBar.flashToggle:SetScript("OnClick", function()
		LockRemindersCycleCDFlash()
	end)
	panel.cdBar.flashToggle:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	panel.cdBar.flashToggle:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	panel.cdBar.glow = LockRemindersGlowSwatch(panel.cdBar, panel.cdBar.flashToggle, 12, "cdGlow", 0.45, 0.75, 1, LockRemindersApplyCDLook)
	local cdBorder = LockRemindersGlowBorderControl(panel.cdBar, panel.cdBar.glow, 10, "cdGlowSize", LockRemindersApplyCDLook)
	panel.cdBar.readyGlow = LockRemindersGlowSwatch(panel.cdBar, cdBorder, 12, "cdReadyGlow", 0.35, 0.95, 0.45, LockRemindersApplyCDLook)
	if panel.cdBar.readyGlow.caption then
		panel.cdBar.readyGlow.caption:SetText("Ready")
	end
	local cdTextLabel = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cdTextLabel:SetPoint("TOPLEFT", 4, -76)
	cdTextLabel:SetText("Text")
	cdTextLabel:SetTextColor(0.9, 0.84, 1)
	panel.cdBar.labelBox = LockRemindersSettingsEdit(panel.cdBar, cdTextLabel, "cdLabel", "READY", 120, function()
		if not panel.cdBar.labelBox or not panel.cdBar.labelBox.quiet then
			LockRemindersApplyCDLook()
		end
	end, true)
	local cdTextSizeLabel = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cdTextSizeLabel:SetPoint("LEFT", panel.cdBar.labelBox, "RIGHT", 14, 0)
	cdTextSizeLabel:SetText("Text size")
	cdTextSizeLabel:SetTextColor(0.9, 0.84, 1)
	local cdTextMinus = StepButton(panel.cdBar, "-")
	cdTextMinus:SetPoint("LEFT", cdTextSizeLabel, "RIGHT", 8, 0)
	cdTextMinus:SetScript("OnClick", function()
		LockRemindersChangeCDTextSize(-1)
	end)
	panel.cdBar.textSizeText = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.cdBar.textSizeText:SetPoint("LEFT", cdTextMinus, "RIGHT", 6, 0)
	panel.cdBar.textSizeText:SetWidth(28)
	panel.cdBar.textSizeText:SetJustifyH("CENTER")
	local cdTextPlus = StepButton(panel.cdBar, "+")
	cdTextPlus:SetPoint("LEFT", panel.cdBar.textSizeText, "RIGHT", 2, 0)
	cdTextPlus:SetScript("OnClick", function()
		LockRemindersChangeCDTextSize(1)
	end)
	local cdSoundLabel = panel.cdBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cdSoundLabel:SetPoint("TOPLEFT", 4, -112)
	cdSoundLabel:SetText("Ready sound")
	cdSoundLabel:SetTextColor(0.9, 0.84, 1)
	panel.cdBar.refreshSound = LockRemindersMakeSoundRow(panel.cdBar, cdSoundLabel, function()
		return db and db.cdSound or "chiji"
	end, function(id)
		db.cdSound = id
	end)
	panel.cdBar.refresh = function()
		if panel.cdBar.layoutToggle and panel.cdBar.layoutToggle.label then
			panel.cdBar.layoutToggle.label:SetText(db and db.cdVertical and "Vertical" or "Horizontal")
		end
		if panel.cdBar.flashToggle and panel.cdBar.flashToggle.label then
			panel.cdBar.flashToggle.label:SetText(LockRemindersCDFlashLabel())
		end
		if panel.cdBar.labelBox and panel.cdBar.labelBox.SetText and not panel.cdBar.labelBox:HasFocus() then
			panel.cdBar.labelBox.quiet = true
			panel.cdBar.labelBox:SetText(LockRemindersClassLabel("cdLabel", false))
			panel.cdBar.labelBox.quiet = nil
		end
		if panel.cdBar.refreshSound then
			panel.cdBar.refreshSound()
		end
	end

	local sizeLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sizeLabel:SetPoint("TOPLEFT", 4, -4)
	sizeLabel:SetText("Size")
	sizeLabel:SetTextColor(0.9, 0.84, 1)
	local sizeMinus = StepButton(talentBar, "-")
	sizeMinus:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
	sizeMinus:SetScript("OnClick", function()
		ChangeTalentSize(-8)
	end)
	talentSizeText = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	talentSizeText:SetPoint("LEFT", sizeMinus, "RIGHT", 6, 0)
	talentSizeText:SetWidth(28)
	talentSizeText:SetJustifyH("CENTER")
	local sizePlus = StepButton(talentBar, "+")
	sizePlus:SetPoint("LEFT", talentSizeText, "RIGHT", 2, 0)
	sizePlus:SetScript("OnClick", function()
		ChangeTalentSize(8)
	end)

	local holdLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	holdLabel:SetPoint("LEFT", sizePlus, "RIGHT", 28, 0)
	holdLabel:SetText("Seconds")
	holdLabel:SetTextColor(0.9, 0.84, 1)
	local holdMinus = StepButton(talentBar, "-")
	holdMinus:SetPoint("LEFT", holdLabel, "RIGHT", 10, 0)
	holdMinus:SetScript("OnClick", function()
		ChangeTalentHold(-0.4)
	end)
	talentHoldText = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	talentHoldText:SetPoint("LEFT", holdMinus, "RIGHT", 6, 0)
	talentHoldText:SetWidth(32)
	talentHoldText:SetJustifyH("CENTER")
	local holdPlus = StepButton(talentBar, "+")
	holdPlus:SetPoint("LEFT", talentHoldText, "RIGHT", 2, 0)
	holdPlus:SetScript("OnClick", function()
		ChangeTalentHold(0.4)
	end)
	talentBar.glow = LockRemindersGlowSwatch(talentBar, holdPlus, 16, "talentGlow", 1, 0.82, 0.35, ApplyTalentLook)
	LockRemindersGlowBorderControl(talentBar, talentBar.glow, 10, "talentGlowSize", ApplyTalentLook)

	talentMoveButton = CreateFrame("Button", nil, talentBar, "BackdropTemplate")
	talentMoveButton:SetSize(88, 22)
	talentMoveButton:SetPoint("TOPLEFT", 4, -36)
	Paint(talentMoveButton, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	talentMoveButton.label = talentMoveButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	talentMoveButton.label:SetPoint("CENTER")
	talentMoveButton.label:SetText("Move")
	talentMoveButton:SetScript("OnClick", function()
		ShowTalentPreview(not talentMoving)
	end)
	talentMoveButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	talentMoveButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)

	local testButton = CreateFrame("Button", nil, talentBar, "BackdropTemplate")
	testButton:SetSize(88, 22)
	testButton:SetPoint("LEFT", talentMoveButton, "RIGHT", 8, 0)
	Paint(testButton, 0.14, 0.1, 0.2, 1, 0.95, 0.78, 0.35, 1)
	testButton.label = testButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	testButton.label:SetPoint("CENTER")
	testButton.label:SetText("Test")
	testButton:SetScript("OnClick", function()
		PlayTalent(LockRemindersEditedTalent(), true)
	end)
	testButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	testButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	talentBar.glow:ClearAllPoints()
	talentBar.glow:SetPoint("LEFT", testButton, "RIGHT", 12, 0)

	holdLabel:SetText("Show")
	local durationButton
	talentBar.refreshDuration, durationButton = LockRemindersChoiceMenu(talentBar, holdLabel, 8, {
		{ "Seconds", "seconds" },
		{ "Until the buff ends", "until" },
	}, function()
		return db.talentUntilEnd and "until" or "seconds"
	end, function(id)
		db.talentUntilEnd = id == "until"
		if talentBar.refresh then
			talentBar.refresh()
		end
	end, nil, 168)
	holdMinus:ClearAllPoints()
	holdMinus:SetPoint("LEFT", durationButton, "RIGHT", 10, 0)

	local procLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	procLabel:SetPoint("TOPLEFT", 4, -70)
	procLabel:SetText("Proc")
	procLabel:SetTextColor(0.9, 0.84, 1)
	talentBar.refreshProc = LockRemindersChoiceMenu(talentBar, procLabel, 8, LockRemindersProcChoices, function()
		local key = LockRemindersEditedTalent()
		return key or "none"
	end, function(id)
		if id ~= "none" then
			LockRemindersSelectedTalent = id
		end
		if talentBar.refresh then
			talentBar.refresh()
		end
		if id ~= "none" then
			PlayTalent(id, true)
		end
	end, nil, 220)

	local effectLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	effectLabel:SetPoint("TOPLEFT", 4, -104)
	effectLabel:SetText("Look")
	effectLabel:SetTextColor(0.9, 0.84, 1)
	talentBar.refreshLook = LockRemindersChoiceMenu(talentBar, effectLabel, 8, LockRemindersProcLooks, function()
		return LockRemindersTalentStyle(LockRemindersEditedTalent())
	end, function(id)
		local key = LockRemindersEditedTalent()
		local entry = key and LockRemindersEnsureTalent(key)
		if entry then
			entry.style = id
		end
		db.talentStyle = id
		if talentMoving then
			ShowTalentPreview(true)
		end
		PlayTalent(key, true)
		Touch()
		if talentBar.refresh then
			talentBar.refresh()
		end
	end, nil, 160)

	local soundLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	soundLabel:SetPoint("TOPLEFT", 4, -138)
	soundLabel:SetText("Sound")
	soundLabel:SetTextColor(0.9, 0.84, 1)
	talentBar.refreshSound = LockRemindersMakeSoundRow(talentBar, soundLabel, function()
		return LockRemindersTalentSound(LockRemindersEditedTalent())
	end, function(id)
		local key = LockRemindersEditedTalent()
		local entry = key and LockRemindersEnsureTalent(key)
		if entry then
			entry.sound = id
		end
		db.talentSound = id
		Touch()
	end)

	talentBar.flashCheck = CreateFrame("Button", nil, talentBar, "BackdropTemplate")
	talentBar.flashCheck:SetSize(22, 22)

	local fadeLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fadeLabel:SetPoint("TOPLEFT", 4, -172)
	fadeLabel:SetText("Fade")
	fadeLabel:SetTextColor(0.9, 0.84, 1)
	local fadeMinus = StepButton(talentBar, "-")
	fadeMinus:SetPoint("LEFT", fadeLabel, "RIGHT", 10, 0)
	fadeMinus:SetScript("OnClick", function()
		ChangeTalentFade(-0.1)
	end)
	talentBar.fadeText = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	talentBar.fadeText:SetPoint("LEFT", fadeMinus, "RIGHT", 6, 0)
	talentBar.fadeText:SetWidth(32)
	talentBar.fadeText:SetJustifyH("CENTER")
	local fadePlus = StepButton(talentBar, "+")
	fadePlus:SetPoint("LEFT", talentBar.fadeText, "RIGHT", 2, 0)
	fadePlus:SetScript("OnClick", function()
		ChangeTalentFade(0.1)
	end)
	local function previewLook()
		local key = LockRemindersEditedTalent()
		local style = LockRemindersTalentStyle(key)
		if style ~= "icon" then
			LockRemindersShowTalentOrnament(style, key)
		end
	end
	local function writeLookColor(which, red, green, blue)
		local key = LockRemindersEditedTalent()
		local entry = key and LockRemindersEnsureTalent(key)
		local color = { r = red, g = green, b = blue }
		if entry then
			entry[which] = color
		elseif db then
			if which == "accent" then
				db.talentLookAccent = color
			else
				db.talentLookColor = color
			end
		end
	end
	talentBar.colorSwatch = LockRemindersColorSwatch(talentBar, fadePlus, 16, "Color", function()
		return LockRemindersTalentColor(LockRemindersEditedTalent(), "color")
	end, function(red, green, blue)
		writeLookColor("color", red, green, blue)
	end, previewLook)
	talentBar.accentSwatch = LockRemindersColorSwatch(talentBar, talentBar.colorSwatch, 12, "Accent", function()
		return LockRemindersTalentColor(LockRemindersEditedTalent(), "accent")
	end, function(red, green, blue)
		writeLookColor("accent", red, green, blue)
	end, previewLook)

	talentBar.flashCheck:SetPoint("TOPLEFT", 4, -206)
	Paint(talentBar.flashCheck, 0.14, 0.1, 0.2, 1, 0.58, 0.45, 0.82, 1)
	talentBar.flashCheck.mark = talentBar.flashCheck:CreateTexture(nil, "OVERLAY")
	talentBar.flashCheck.mark:SetPoint("CENTER")
	talentBar.flashCheck.mark:SetSize(12, 12)
	talentBar.flashCheck.mark:SetTexture("Interface\\Buttons\\WHITE8x8")
	talentBar.flashCheck.mark:SetVertexColor(0.95, 0.78, 0.35)
	talentBar.flashLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	talentBar.flashLabel:SetPoint("LEFT", talentBar.flashCheck, "RIGHT", 8, 0)
	talentBar.flashLabel:SetText("Screen flash")
	talentBar.flashLabel:SetTextColor(0.94, 0.9, 1)
	local function toggleFlash()
		db.talentScreenFlash = not (db.talentScreenFlash ~= false)
		if db.talentScreenFlash then
			PlayScreenFlash()
		else
			QuietScreenFlash()
		end
		if talentBar.refresh then
			talentBar.refresh()
		end
	end
	talentBar.flashCheck:SetScript("OnClick", toggleFlash)
	talentBar.flashLabelButton = CreateFrame("Button", nil, talentBar)
	talentBar.flashLabelButton:SetPoint("LEFT", talentBar.flashCheck, "RIGHT", 8, 0)
	talentBar.flashLabelButton:SetSize(180, 22)
	talentBar.flashLabelButton:SetScript("OnClick", toggleFlash)

	talentBar.refresh = function()
		if not db then
			return
		end
		if talentBar.refreshDuration then
			talentBar.refreshDuration()
		end
		LockRemindersFillProcChoices()
		if talentBar.refreshProc then
			talentBar.refreshProc()
		end
		if talentBar.refreshLook then
			talentBar.refreshLook()
		end
		if talentBar.refreshSound then
			talentBar.refreshSound()
		end
		if talentBar.fadeText then
			talentBar.fadeText:SetText(string.format("%.1f", LockRemindersTalentFade()))
		end
		if talentBar.colorSwatch and talentBar.colorSwatch.refresh then
			talentBar.colorSwatch.refresh()
		end
		if talentBar.accentSwatch and talentBar.accentSwatch.refresh then
			talentBar.accentSwatch.refresh()
		end
		local untilEnd = db.talentUntilEnd and true or false
		holdMinus:SetShown(not untilEnd)
		talentHoldText:SetShown(not untilEnd)
		holdPlus:SetShown(not untilEnd)
		if talentMoveButton then
			talentMoveButton:Show()
		end
		local on = db.talentScreenFlash ~= false
		talentBar.flashCheck.mark:SetShown(on)
		if on then
			Paint(talentBar.flashCheck, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
		else
			Paint(talentBar.flashCheck, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		end
	end

	scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", 14, -176)
	scroll:SetPoint("BOTTOMRIGHT", -24, 40)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		ScrollBy(delta)
	end)
	scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(440, 1)
	scroll:SetScrollChild(scrollChild)
	BindWheel(scrollChild)

	scrollBar = CreateFrame("Slider", nil, panel, "BackdropTemplate")
	scrollBar:SetWidth(8)
	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	scrollBar:SetOrientation("VERTICAL")
	scrollBar:SetMinMaxValues(0, 1)
	scrollBar:SetValue(0)
	Paint(scrollBar, 0.1, 0.08, 0.14, 0.9, 0.28, 0.22, 0.38, 1)
	local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
	thumb:SetSize(8, 36)
	thumb:SetVertexColor(0.62, 0.5, 0.86, 0.95)
	scrollBar:SetThumbTexture(thumb)
	scrollBar:SetScript("OnValueChanged", function(_, value)
		if syncingScroll or not scroll then
			return
		end
		scroll:SetVerticalScroll(value)
	end)

	emptyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	emptyLabel:SetPoint("TOPLEFT", scroll, "TOPLEFT", 16, -36)
	emptyLabel:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -16, -36)
	emptyLabel:SetJustifyH("CENTER")
	emptyLabel:SetJustifyV("TOP")
	emptyLabel:SetWordWrap(true)
	emptyLabel:SetSpacing(3)
	emptyLabel:SetTextColor(0.78, 0.72, 0.88)

	footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", 14, 10)
	footer:SetPoint("BOTTOMRIGHT", -16, 10)
	footer:SetJustifyH("CENTER")
	footer:SetWordWrap(true)
	footer:SetTextColor(0.58, 0.54, 0.66)

	panel:SetScript("OnShow", function()
		currentSignature = nil
		RebuildList(true)
	end)
	panel:SetScript("OnHide", function()
		currentSignature = nil
		if listTicker then
			listTicker:Cancel()
			listTicker = nil
		end
		if searchBox then
			searchBox:ClearFocus()
		end
		if talentMoving then
			ShowTalentPreview(false)
		end
	end)

	if not tContains(UISpecialFrames, "LockRemindersPanel") then
		tinsert(UISpecialFrames, "LockRemindersPanel")
	end

	LockRemindersBuildMisc(panel)
	LockRemindersBuildFun(panel)
	if LockRemindersIsWarlock() then
		LockRemindersBuildSoul(panel)
		LockRemindersBuildPets(panel)
	end
	SetTab("powers")
	panel:Hide()
end

local function AngleFromCursor()
	local mx, my = Minimap:GetCenter()
	if not mx or not my then
		return db.minimapAngle or 225
	end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	if not scale or scale == 0 then
		scale = 1
	end
	cx, cy = cx / scale, cy / scale
	return math.deg(math.atan2(cy - my, cx - mx))
end

local function PlaceMinimapButton()
	if not minimapButton or not Minimap then
		return
	end
	local angle = db.minimapAngle or 225
	local rad = math.rad(angle)
	local w = (Minimap:GetWidth() or 140) / 2 + 5
	local h = (Minimap:GetHeight() or 140) / 2 + 5
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * w, math.sin(rad) * h)
end

local function CreateMinimapButton()
	if minimapButton or not Minimap then
		return
	end

	local button = CreateFrame("Button", "LockRemindersMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetClampedToScreen(true)

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture(136216)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("LockReminders", 0.72, 0.62, 0.9)
		GameTooltip:AddLine("Open powers and consumables", 1, 1, 1)
		GameTooltip:AddLine("Configure alert opens size and position", 0.75, 0.75, 0.75)
		GameTooltip:AddLine("Right-click: lock the frame", 0.75, 0.75, 0.75)
		GameTooltip:AddLine("Drag: move the icon", 0.75, 0.75, 0.75)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStart", function(self)
		self.dragging = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			db.minimapAngle = AngleFromCursor()
			PlaceMinimapButton()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		db.minimapAngle = AngleFromCursor()
		PlaceMinimapButton()
	end)
	button:SetScript("OnClick", function(self, mouse)
		if self.dragging then
			self.dragging = false
			return
		end
		if mouse == "RightButton" then
			db.locked = not db.locked
			Print(db.locked and "Frame locked." or "Frame unlocked. Drag it from the border.")
			if activeTab == "alert" and ShowLayout then
				ShowLayout(false)
			end
			return
		end
		TogglePanel()
	end)

	minimapButton = button
	PlaceMinimapButton()
	pcall(Minimap.HookScript, Minimap, "OnSizeChanged", PlaceMinimapButton)
end

local function ShowAuras()
	if Restricted() then
		Print("Cannot read buffs right now. Leave combat and try again.")
		return
	end
	Print("Active buffs. You can also search them from the minimap icon.")
	local found = false
	EachAura(function(spellID, name)
		found = true
		Print(spellID .. "  " .. name)
	end)
	if not found then
		Print("No readable buffs.")
	end
end

local function Help()
	Print("Click the minimap icon to add buffs and items.")
	Print("Drag the alert border to move it. /lr lock keeps it still.")
	Print("Each module has its own alert. Configure alert opens its size and position.")
	Print("Procs: Nightfall, Backlash, Decimation, Conflagrate ready.")
	Print("Spell misses/resist: add a spell or a pet spell. Only those miss and resist.")
	Print("CD Manager: track spell, racial, and trinket cooldowns. /lr cds")
	Print("Miscellaneous: movement speed. /lr misc")
	Print("Fun: emote a hostile player of a chosen race. /lr fun")
	Print("Soulstone tracker is for warlocks. /lr soul")
	Print("Pets: Spell Lock, Devour Magic, Seduction. /lr pets")
	Print("/lr arrange  —  arrange the icons inside the alert.")
	Print("/lr  —  opens the window.")
	Print("/lr buffs  —  lists active buffs with their ID.")
	Print("/lr add 12345  —  adds it with the mode chosen in When adding.")
	Print("/lr add 12345 always  —  Always, Party, or Raid.")
	Print("/lr food 12345  —  in a raid it alerts if you do not have that food.")
	Print("/lr remove 12345")
end

local function Command(message)
	if not db then
		Print("Still loading.")
		return
	end

	local command, rest = message:match("^(%S*)%s*(.-)$")
	command = (command or ""):lower()
	local spellID = tonumber(rest:match("^(%d+)"))
	local scope = rest:match("%d+%s+(%S+)")
	scope = scope and scope:lower()

	if command == "" or command == "show" or command == "config" then
		TogglePanel()
	elseif command == "proc" or command == "testproc" then
		local key = spellID or LockRemindersEditedTalent()
		if not key and db and type(db.talents) == "table" then
			for saved in pairs(db.talents) do
				key = saved
				break
			end
		end
		if not key then
			Print("Add a proc first.")
			return
		end
		pcall(CreateTalentAlert)
		PlayTalent(key, true)
		Print("Proc preview: " .. (SpellDisplayName(key) or SpellName(key) or tostring(key)))
	elseif command == "dump" or command == "procdump" then
		pcall(LockRemindersHookElvUIAuras)
		pcall(LockRemindersDumpProcs)
	elseif command == "help" then
		Help()
	elseif command == "lock" then
		db.locked = not db.locked
		Print(db.locked and "Frame locked." or "Frame unlocked. Drag it from the border.")
		if activeTab == "alert" and ShowLayout then
			ShowLayout(false)
		end
	elseif command == "arrange" then
		ToggleArrange()
	elseif command == "buffs" then
		ShowAuras()
	elseif command == "add" then
		if not spellID then
			Print("Usage: /lr add 12345")
			return
		end
		local where = addScope
		if scope == "raid" then
			where = "raid"
		elseif scope == "party" then
			where = "party"
		elseif scope == "always" then
			where = "always"
		end
		AddAura(spellID, where)
	elseif command == "fun" then
		if not panel then
			Print("Still loading.")
			return
		end
		panel:Show()
		SetTab("fun")
	elseif command == "pets" or command == "petalerts" then
		if not panel then
			Print("Still loading.")
			return
		end
		if not LockRemindersIsWarlock() then
			Print("Pets is for warlocks.")
			return
		end
		if not panel:IsShown() then
			panel:Show()
		end
		SetTab("pets")
	elseif command == "soul" or command == "soulstone" then
		if not panel then
			Print("Still loading.")
			return
		end
		if not LockRemindersIsWarlock() then
			Print("Soulstone tracker is for warlocks.")
			return
		end
		panel:Show()
		SetTab("soul")
	elseif command == "misc" or command == "miscellaneous" then
		if not panel then
			Print("Still loading.")
			return
		end
		panel:Show()
		SetTab("misc")
	elseif command == "spells" or command == "miss" then
		if not panel then
			Print("Still loading.")
			return
		end
		panel:Show()
		SetTab("spells")
	elseif command == "cds" or command == "cd" or command == "cooldown" then
		if not panel then
			Print("Still loading.")
			return
		end
		panel:Show()
		SetTab("cds")
	elseif command == "food" then
		if not spellID then
			Print("Look it up with /lr buffs, then /lr food 12345")
			return
		end
		AddFood(spellID)
	elseif command == "remove" then
		if not spellID then
			Print("Usage: /lr remove 12345")
			return
		end
		RemoveSpell(spellID)
	elseif command == "reset" then
		db.auras = {}
		db.food = {}
		db.foodItems = {}
		db.point = { "CENTER", "CENTER", 0, 220 }
		db.locked = false
		db.showFrame = false
		db.iconSize = 40
		db.iconPad = 8
		db.columns = 0
		db.order = {}
		db.itemOrder = {}
		db.foodLocked = true
		db.foodColumns = 0
		db.foodPad = 8
		db.foodShowFrame = false
		db.foodRemind = "count"
		db.foodScope = {}
		db.talents = {}
		db.talentPoint = { "CENTER", "CENTER", 0, 140 }
		db.talentSize = 72
		db.talentHold = 2.2
		db.talentFade = 0.4
		db.talentArtX = 0
		db.talentArtY = 0
		db.talentLookColor = nil
		db.talentLookAccent = nil
		db.missPlayer = false
		db.missPet = false
		db.missSpells = {}
		db.missNames = {}
		db.missPoint = { "CENTER", "CENTER", 0, 260 }
		db.missSize = 48
		db.missHold = 3
		db.missSound = "zaps"
		db.immuneAlert = true
		db.cdSpells = {}
		db.cdItems = {}
		db.cdOrder = {}
		db.cdSortMode = "time"
		db.cdPoint = { "CENTER", "CENTER", 0, -40 }
		db.cdSize = 40
		db.cdHold = 2.2
		db.cdPad = 8
		db.cdVertical = false
		db.cdTextSize = 14
		db.cdLabel = "READY"
		db.cdFlash = "icon"
		db.cdSound = "chiji"
		db.soundChannel = "Dialog"
		db.cdGlowSize = 2
		db.cdGlow = { r = 0.45, g = 0.75, b = 1 }
		db.cdReadyGlow = { r = 0.35, g = 0.95, b = 0.45 }
		LockRemindersCD.moving = false
		LockRemindersCD.states = {}
		if LockRemindersCD.bar then
			LockRemindersApplyCDLook()
			LockRemindersApplyCDPoint()
			LockRemindersCD.bar:Hide()
		end
		db.funEnabled = false
		db.funEmote = "CHICKEN"
		db.buffRemind = "count"
		db.funRaces = {}
		db.speedShow = true
		db.speedSplit = false
		db.speedSize = 18
		db.speedColor = { r = 1, g = 0.96, b = 0.9 }
		db.speedPoint = { "CENTER", "CENTER", 0, -160 }
		db.speedTargetPoint = { "CENTER", "CENTER", 90, -160 }
		LockRemindersMisc.speedMoving = false
		db.soulAlert = true
		db.soulAnnounce = true
		db.soulAnnounceParty = true
		db.soulAnnounceRaid = true
		db.soulAnnounceMsg = "{rt3} Soulstone on %s {rt3}"
		db.summonAnnounce = true
		db.summonAnnounceParty = true
		db.summonAnnounceRaid = true
		db.summonAnnounceMsg = "{rt3} Summoning %s - click portal {rt3}"
		db.soulScope = { always = true, party = false, raid = false, instance = false }
		db.soulSize = 48
		db.soulLabel = "SOULSTONE"
		db.soulReadyLabel = "READY"
		db.soulPoint = { "CENTER", "CENTER", 0, 180 }
		db.soulSound = "chiji"
		db.soulTrack = true
		db.soulTrackScope = { always = true, party = false, raid = false, instance = false }
		db.soulTrackSize = 100
		db.soulTrackFont = 10
		db.soulTrackFade = 92
		db.soulFullName = true
		db.soulTrackFrame = true
		db.soulTrackPoint = { "CENTER", "CENTER", -280, 40 }
		db.banishAlert = true
		db.banishWarn = 5
		db.banishSize = 48
		db.banishLabel = "BANISH"
		db.banishScope = { always = true, party = false, raid = false, instance = false }
		db.banishPoint = { "CENTER", "CENTER", 180, 210 }
		db.fearAlert = true
		db.fearWarn = 5
		db.fearSize = 48
		db.fearLabel = "FEAR"
		db.fearScope = { always = true, party = false, raid = false, instance = false }
		db.fearPoint = { "CENTER", "CENTER", 180, 120 }
		db.petLockAlert = true
		db.petLockWarn = 3
		db.petLockSize = 48
		db.petLockLabel = "SPELL LOCK"
		db.petLockScope = { always = true, party = false, raid = false, instance = false }
		db.petLockPoint = { "CENTER", "CENTER", 0, 160 }
		db.petPurgeAlert = true
		db.petPurgeWarn = 3
		db.petPurgeSize = 48
		db.petPurgeLabel = "DEVOUR MAGIC"
		db.petPurgeScope = { always = true, party = false, raid = false, instance = false }
		db.petPurgePoint = { "CENTER", "CENTER", 0, 90 }
		db.petSeduceAlert = true
		db.petSeduceWarn = 5
		db.petSeduceSeconds = 15
		db.petSeduceSize = 48
		db.petSeduceLabel = "SEDUCTION"
		db.petSeduceScope = { always = true, party = false, raid = false, instance = false }
		db.petSeducePoint = { "CENTER", "CENTER", 180, 40 }
		db.petSound = "chiji"
		db.shardShow = true
		db.shardSize = 40
		db.shardLabel = "NO SHARDS"
		db.buffGlow = { r = 1, g = 0.82, b = 0.35 }
		db.buffGlowSize = 2
		db.foodGlowSize = 2
		db.talentGlowSize = 2
		db.missGlowSize = 2
		db.soulGlowSize = 2
		db.banishGlowSize = 2
		db.shardGlowSize = 2
		db.foodGlow = { r = 1, g = 0.82, b = 0.35 }
		db.talentGlow = { r = 1, g = 0.82, b = 0.35 }
		db.missGlow = { r = 1, g = 0.15, b = 0.1 }
		db.soulGlow = { r = 0.72, g = 0.4, b = 1 }
		db.soulReadyGlow = { r = 0.35, g = 0.95, b = 0.45 }
		db.banishGlow = { r = 0.72, g = 0.4, b = 1 }
		db.shardGlow = { r = 0.64, g = 0.32, b = 0.95 }
		db.shardCount = { r = 1, g = 0.97, b = 0.86 }
		db.shardScope = { always = true, party = false, raid = false, instance = false }
		db.shardPoint = { "CENTER", "CENTER", -180, -80 }
		LockRemindersWarlock.banishMoving = false
		LockRemindersWarlock.fearMoving = false
		LockRemindersWarlock.shardMoving = false
		LockRemindersWarlock.banishPreview = nil
		LockRemindersWarlock.fearPreview = nil
		LockRemindersWarlock.shardPreview = nil
		db.soulCD = {}
		db.soulCDDur = {}
		LockRemindersSoul.moving = false
		LockRemindersSoul.trackMoving = false
		LockRemindersSoul.missing = false
		LockRemindersSoul.previewUntil = nil
		LockRemindersSoul.trackSample = false
		arranging = false
		talentMoving = false
		LockRemindersMiss.moving = false
		db.minimapAngle = 225
		db.panelPoint = nil
		if frame then
		ApplyPoint()
		end
		PlaceMinimapButton()
		if panel then
			panel:ClearAllPoints()
			panel:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
		end
		if LockRemindersMisc.speed then
			LockRemindersApplySpeedLook()
			LockRemindersApplyNamedPoint(LockRemindersMisc.speed, "speedPoint", db.speedPoint)
			if LockRemindersMisc.speed.target then
				LockRemindersApplyNamedPoint(LockRemindersMisc.speed.target, "speedTargetPoint", db.speedTargetPoint)
			end
			LockRemindersSetSpeedMove(false)
		end
		if LockRemindersSoul.alert then
			LockRemindersApplySoulLook()
			LockRemindersApplyNamedPoint(LockRemindersSoul.alert, "soulPoint", db.soulPoint)
			LockRemindersSoul.alert:Hide()
		end
		if LockRemindersSoul.tracker then
			LockRemindersApplyNamedPoint(LockRemindersSoul.tracker, "soulTrackPoint", db.soulTrackPoint)
			LockRemindersSetSoulTrackMove(false)
		end
		Print("List and position reset.")
		Refresh()
		if UpdateListNow then
			UpdateListNow()
		end
	else
		Help()
	end
end

local function InitDB()
	if type(LockRemindersDB) ~= "table" then
		LockRemindersDB = {}
	end
	db = LockRemindersDB
	if type(db.auras) ~= "table" then
		db.auras = {}
	end
	if type(db.food) ~= "table" then
		db.food = {}
	end
	if type(db.foodItems) ~= "table" then
		db.foodItems = {}
	end
	if type(db.foodCombat) ~= "table" then
		db.foodCombat = {}
	end
	if type(db.point) ~= "table" then
		db.point = { "CENTER", "CENTER", 0, 220 }
	end
	if type(db.minimapAngle) ~= "number" then
		db.minimapAngle = 225
	end
	if db.locked == nil then
		db.locked = false
	end
	if db.showFrame == nil then
		db.showFrame = false
	end
	if type(db.iconSize) ~= "number" then
		db.iconSize = 40
	end
	if type(db.iconPad) ~= "number" then
		db.iconPad = 8
	end
	if type(db.columns) ~= "number" then
		db.columns = 0
	end
	if db.buffRemind ~= "count" and db.buffRemind ~= "alert" then
		db.buffRemind = "count"
	end
	if type(db.order) ~= "table" then
		db.order = {}
	end
	if type(db.itemOrder) ~= "table" then
		db.itemOrder = {}
	end
	if type(db.foodLocked) ~= "boolean" then
		db.foodLocked = true
	end
	if type(db.foodColumns) ~= "number" then
		db.foodColumns = 0
	end
	if type(db.foodPad) ~= "number" then
		db.foodPad = 8
	end
	if type(db.foodShowFrame) ~= "boolean" then
		db.foodShowFrame = false
	end
	if db.foodRemind ~= "count" and db.foodRemind ~= "alert" then
		db.foodRemind = "count"
	end
	if type(db.foodScope) ~= "table" then
		db.foodScope = {}
	end
	if type(db.talents) ~= "table" then
		db.talents = {}
	end
	if type(db.talentPoint) ~= "table" then
		db.talentPoint = { "CENTER", "CENTER", 0, 140 }
	end
	if type(db.talentSize) ~= "number" then
		db.talentSize = 72
	end
	if type(db.talentHold) ~= "number" then
		db.talentHold = 2.2
	end
	if type(db.talentFade) ~= "number" then
		db.talentFade = 0.4
	end
	if type(db.talentArtX) ~= "number" then
		db.talentArtX = 0
	end
	if type(db.talentArtY) ~= "number" then
		db.talentArtY = 0
	end
	if type(db.talentStyle) ~= "string" then
		db.talentStyle = "scythes"
	else
		db.talentStyle = LockRemindersMapLook(db.talentStyle)
	end
	if type(db.talentSound) ~= "string" or not LockRemindersKnownSound(db.talentSound) then
		db.talentSound = "none"
	end
	for key, value in pairs(db.talents) do
		if type(value) ~= "table" then
			db.talents[key] = {
				untilEnd = false,
				style = db.talentStyle,
				sound = LockRemindersKnownSound(db.talentSound) and db.talentSound or "none",
			}
		else
			value.style = LockRemindersMapLook(value.style or db.talentStyle)
			if not LockRemindersKnownSound(value.sound) then
				value.sound = LockRemindersKnownSound(db.talentSound) and db.talentSound or "none"
			end
		end
	end
	if db.talentScreenFlash == nil then
		db.talentScreenFlash = true
	end
	if type(db.foodPoint) ~= "table" then
		db.foodPoint = { "CENTER", "CENTER", 0, 80 }
	end
	if type(db.foodSize) ~= "number" then
		db.foodSize = 48
	end
	if type(db.missPlayer) ~= "boolean" then
		db.missPlayer = false
	end
	if type(db.missPet) ~= "boolean" then
		db.missPet = false
	end
	if type(db.missSpells) ~= "table" then
		db.missSpells = {}
	end
	if type(db.missNames) ~= "table" then
		db.missNames = {}
	end
	LockRemindersCacheMissNames()
	if type(db.missPoint) ~= "table" then
		db.missPoint = { "CENTER", "CENTER", 0, 260 }
	end
	if type(db.missSize) ~= "number" then
		db.missSize = 48
	end
	if type(db.missHold) ~= "number" then
		db.missHold = 3
	end
	if type(db.missSound) ~= "string" or not LockRemindersKnownSound(db.missSound) then
		db.missSound = "zaps"
	end
	if type(db.immuneAlert) ~= "boolean" then
		db.immuneAlert = true
	end
	if type(db.cdSpells) ~= "table" then
		db.cdSpells = {}
	end
	if type(db.cdItems) ~= "table" then
		db.cdItems = {}
	end
	if type(db.cdOrder) ~= "table" then
		db.cdOrder = {}
	end
	if db.cdSortMode ~= "manual" and db.cdSortMode ~= "time" then
		db.cdSortMode = "time"
	end
	if type(db.cdPoint) ~= "table" then
		db.cdPoint = { "CENTER", "CENTER", 0, -40 }
	end
	if type(db.cdSize) ~= "number" then
		db.cdSize = 40
	end
	if type(db.cdHold) ~= "number" then
		db.cdHold = 2.2
	end
	if type(db.cdPad) ~= "number" then
		db.cdPad = 8
	end
	if type(db.cdVertical) ~= "boolean" then
		db.cdVertical = false
	end
	if type(db.cdTextSize) ~= "number" then
		db.cdTextSize = 14
	end
	if type(db.cdLabel) ~= "string" then
		db.cdLabel = "READY"
	end
	if db.cdFlash ~= "icon" and db.cdFlash ~= "screen" and db.cdFlash ~= "both" and db.cdFlash ~= "none" then
		db.cdFlash = "icon"
	end
	if db.soundChannel ~= "Master" and db.soundChannel ~= "SFX" and db.soundChannel ~= "Dialog" then
		db.soundChannel = "Dialog"
	end
	if type(db.cdSound) ~= "string" or not LockRemindersKnownSound(db.cdSound) then
		db.cdSound = "chiji"
	end
	if type(db.cdGlowSize) ~= "number" then
		db.cdGlowSize = 2
	end
	if type(db.cdGlow) ~= "table" then
		db.cdGlow = { r = 0.45, g = 0.75, b = 1 }
	end
	if type(db.cdReadyGlow) ~= "table" then
		db.cdReadyGlow = { r = 0.35, g = 0.95, b = 0.45 }
	end
	if type(db.funEnabled) ~= "boolean" then
		db.funEnabled = false
	end
	if type(db.funEmote) ~= "string" then
		db.funEmote = "CHICKEN"
	end
	if type(db.funRaces) ~= "table" then
		db.funRaces = {}
	end
	if type(db.speedShow) ~= "boolean" then
		db.speedShow = true
	end
	if type(db.speedSplit) ~= "boolean" then
		db.speedSplit = false
	end
	if type(db.speedSize) ~= "number" then
		db.speedSize = 18
	end
	if type(db.speedColor) ~= "table" then
		db.speedColor = { r = 1, g = 0.96, b = 0.9 }
	end
	if type(db.speedPoint) ~= "table" then
		db.speedPoint = { "CENTER", "CENTER", 0, -160 }
	end
	if type(db.speedTargetPoint) ~= "table" then
		db.speedTargetPoint = { "CENTER", "CENTER", 90, -160 }
	end
	if type(db.soulAlert) ~= "boolean" then
		db.soulAlert = true
	end
	if type(db.soulAnnounce) ~= "boolean" then
		db.soulAnnounce = true
	end
	if type(db.soulAnnounceParty) ~= "boolean" then
		db.soulAnnounceParty = true
	end
	if type(db.soulAnnounceRaid) ~= "boolean" then
		db.soulAnnounceRaid = true
	end
	if type(db.soulAnnounceMsg) ~= "string" or db.soulAnnounceMsg == "" then
		db.soulAnnounceMsg = "{rt3} Soulstone on %s {rt3}"
	end
	if type(db.summonAnnounce) ~= "boolean" then
		db.summonAnnounce = true
	end
	if type(db.summonAnnounceParty) ~= "boolean" then
		db.summonAnnounceParty = true
	end
	if type(db.summonAnnounceRaid) ~= "boolean" then
		db.summonAnnounceRaid = true
	end
	if type(db.summonAnnounceMsg) ~= "string" or db.summonAnnounceMsg == "" then
		db.summonAnnounceMsg = "{rt3} Summoning %s - click portal {rt3}"
	end
	if type(db.soulScope) == "string" or type(db.soulScope) ~= "table" then
		local always, party, raid, instance = ScopeFlags(db.soulScope)
		db.soulScope = { always = always, party = party, raid = raid, instance = instance }
	end
	if type(db.soulSize) ~= "number" then
		db.soulSize = 48
	end
	if type(db.soulPoint) ~= "table" then
		db.soulPoint = { "CENTER", "CENTER", 0, 180 }
	end
	if type(db.soulSound) ~= "string" or not LockRemindersKnownSound(db.soulSound) then
		db.soulSound = "chiji"
	end
	if type(db.soulTrack) ~= "boolean" then
		db.soulTrack = true
	end
	if type(db.soulTrackScope) == "string" or type(db.soulTrackScope) ~= "table" then
		local always, party, raid, instance = ScopeFlags(db.soulTrackScope)
		db.soulTrackScope = { always = always, party = party, raid = raid, instance = instance }
	end
	if type(db.soulTrackSize) ~= "number" then
		db.soulTrackSize = 100
	end
	if type(db.soulTrackFont) ~= "number" then
		db.soulTrackFont = 10
	end
	if type(db.soulTrackFade) ~= "number" then
		db.soulTrackFade = 92
	end
	if type(db.soulFullName) ~= "boolean" then
		db.soulFullName = true
	end
	if type(db.soulTrackFrame) ~= "boolean" then
		db.soulTrackFrame = true
	end
	if type(db.soulTrackPoint) ~= "table" then
		db.soulTrackPoint = { "CENTER", "CENTER", -280, 40 }
	end
	if type(db.banishAlert) ~= "boolean" then
		db.banishAlert = true
	end
	if type(db.banishWarn) ~= "number" then
		db.banishWarn = 5
	end
	if type(db.banishSize) ~= "number" then
		db.banishSize = 48
	end
	if type(db.soulLabel) ~= "string" then
		db.soulLabel = "SOULSTONE"
	end
	if type(db.soulReadyLabel) ~= "string" then
		db.soulReadyLabel = "READY"
	end
	if type(db.banishLabel) ~= "string" then
		db.banishLabel = "BANISH"
	end
	if type(db.banishScope) == "string" or type(db.banishScope) ~= "table" then
		local always, party, raid, instance = ScopeFlags(db.banishScope)
		db.banishScope = { always = always, party = party, raid = raid, instance = instance }
	end
	if type(db.banishPoint) ~= "table" then
		db.banishPoint = { "CENTER", "CENTER", 180, 210 }
	end
	if type(db.fearAlert) ~= "boolean" then
		db.fearAlert = true
	end
	if type(db.fearWarn) ~= "number" then
		db.fearWarn = 5
	end
	if type(db.fearSize) ~= "number" then
		db.fearSize = 48
	end
	if type(db.fearLabel) ~= "string" then
		db.fearLabel = "FEAR"
	end
	if type(db.fearScope) == "string" or type(db.fearScope) ~= "table" then
		local always, party, raid, instance = ScopeFlags(db.fearScope)
		db.fearScope = { always = always, party = party, raid = raid, instance = instance }
	end
	if type(db.fearPoint) ~= "table" then
		db.fearPoint = { "CENTER", "CENTER", 180, 120 }
	end
	if type(db.petLockAlert) ~= "boolean" then
		db.petLockAlert = true
	end
	if type(db.petLockWarn) ~= "number" then
		db.petLockWarn = tonumber(db.petFlashHold) or 3
	end
	if type(db.petLockSize) ~= "number" then
		db.petLockSize = tonumber(db.petFlashSize) or 48
	end
	if type(db.petLockLabel) ~= "string" then
		db.petLockLabel = "SPELL LOCK"
	end
	if type(db.petLockScope) ~= "table" then
		db.petLockScope = { always = true, party = false, raid = false, instance = false }
	end
	if type(db.petLockPoint) ~= "table" then
		db.petLockPoint = type(db.petFlashPoint) == "table" and db.petFlashPoint or { "CENTER", "CENTER", 0, 160 }
	end
	if type(db.petPurgeAlert) ~= "boolean" then
		db.petPurgeAlert = true
	end
	if type(db.petPurgeWarn) ~= "number" then
		db.petPurgeWarn = 3
	end
	if type(db.petPurgeSize) ~= "number" then
		db.petPurgeSize = 48
	end
	if type(db.petPurgeLabel) ~= "string" then
		db.petPurgeLabel = "DEVOUR MAGIC"
	end
	if type(db.petPurgeScope) ~= "table" then
		db.petPurgeScope = { always = true, party = false, raid = false, instance = false }
	end
	if type(db.petPurgePoint) ~= "table" then
		db.petPurgePoint = { "CENTER", "CENTER", 0, 90 }
	end
	if type(db.petSeduceAlert) ~= "boolean" then
		db.petSeduceAlert = true
	end
	if type(db.petSeduceWarn) ~= "number" then
		db.petSeduceWarn = 5
	end
	if type(db.petSeduceSeconds) ~= "number" then
		db.petSeduceSeconds = 15
	end
	if type(db.petSeduceSize) ~= "number" then
		db.petSeduceSize = 48
	end
	if type(db.petSeduceLabel) ~= "string" then
		db.petSeduceLabel = "SEDUCTION"
	end
	if type(db.petSeduceScope) ~= "table" then
		db.petSeduceScope = { always = true, party = false, raid = false, instance = false }
	end
	if type(db.petSeducePoint) ~= "table" then
		db.petSeducePoint = { "CENTER", "CENTER", 180, 40 }
	end
	if type(db.petSound) ~= "string" then
		db.petSound = "chiji"
	end
	if type(db.shardShow) ~= "boolean" then
		db.shardShow = true
	end
	if type(db.shardSize) ~= "number" then
		db.shardSize = 40
	end
	if type(db.shardLabel) ~= "string" then
		db.shardLabel = "NO SHARDS"
	end
	if type(db.buffGlow) ~= "table" then
		db.buffGlow = { r = 1, g = 0.82, b = 0.35 }
	end
	if type(db.buffGlowSize) ~= "number" then
		db.buffGlowSize = 2
	end
	if type(db.foodGlowSize) ~= "number" then
		db.foodGlowSize = 2
	end
	if type(db.talentGlowSize) ~= "number" then
		db.talentGlowSize = 2
	end
	if type(db.missGlowSize) ~= "number" then
		db.missGlowSize = 2
	end
	if type(db.cdGlowSize) ~= "number" then
		db.cdGlowSize = 2
	end
	if type(db.soulGlowSize) ~= "number" then
		db.soulGlowSize = 2
	end
	if type(db.banishGlowSize) ~= "number" then
		db.banishGlowSize = 2
	end
	if type(db.shardGlowSize) ~= "number" then
		db.shardGlowSize = 2
	end
	if type(db.foodGlow) ~= "table" then
		db.foodGlow = { r = 1, g = 0.82, b = 0.35 }
	end
	if type(db.talentGlow) ~= "table" then
		db.talentGlow = { r = 1, g = 0.82, b = 0.35 }
	end
	if type(db.missGlow) ~= "table" then
		db.missGlow = { r = 1, g = 0.15, b = 0.1 }
	end
	if type(db.cdGlow) ~= "table" then
		db.cdGlow = { r = 0.45, g = 0.75, b = 1 }
	end
	if type(db.cdReadyGlow) ~= "table" then
		db.cdReadyGlow = { r = 0.35, g = 0.95, b = 0.45 }
	end
	if type(db.soulGlow) ~= "table" then
		db.soulGlow = { r = 0.72, g = 0.4, b = 1 }
	end
	if type(db.soulReadyGlow) ~= "table" then
		db.soulReadyGlow = { r = 0.35, g = 0.95, b = 0.45 }
	end
	if type(db.banishGlow) ~= "table" then
		db.banishGlow = { r = 0.72, g = 0.4, b = 1 }
	end
	if type(db.shardGlow) ~= "table" then
		db.shardGlow = { r = 0.64, g = 0.32, b = 0.95 }
	end
	if type(db.shardCount) ~= "table" then
		db.shardCount = { r = 1, g = 0.97, b = 0.86 }
	end
	if type(db.shardScope) == "string" or type(db.shardScope) ~= "table" then
		local always, party, raid, instance = ScopeFlags(db.shardScope)
		db.shardScope = { always = always, party = party, raid = raid, instance = instance }
	end
	if type(db.shardPoint) ~= "table" then
		db.shardPoint = { "CENTER", "CENTER", -180, -80 }
	end
	if type(db.soulCD) ~= "table" then
		db.soulCD = {}
	end
	if type(db.soulCDDur) ~= "table" then
		db.soulCDDur = {}
	end
end

local events = CreateFrame("Frame")
LockRemindersEvents = events
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
pcall(events.RegisterEvent, events, "SPELLS_CHANGED")
pcall(events.RegisterEvent, events, "UNIT_COMBAT")
pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_INTERRUPTED")
pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_FAILED")
pcall(events.RegisterEvent, events, "SPELL_ACTIVATION_OVERLAY_SHOW")
pcall(events.RegisterEvent, events, "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
pcall(events.RegisterEvent, events, "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
pcall(events.RegisterEvent, events, "SPELL_UPDATE_USABLE")
pcall(events.RegisterEvent, events, "ACTIONBAR_UPDATE_USABLE")
pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_START")
pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED")
pcall(events.RegisterEvent, events, "SPELL_UPDATE_COOLDOWN")
pcall(events.RegisterEvent, events, "ACTIONBAR_UPDATE_COOLDOWN")
pcall(events.RegisterEvent, events, "PLAYER_EQUIPMENT_CHANGED")
pcall(events.RegisterEvent, events, "BAG_UPDATE")
pcall(events.RegisterEvent, events, "PLAYER_TARGET_CHANGED")
pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_SELF_DAMAGE")
pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_PET_DAMAGE")
	pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_MISC_INFO")
	pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
	pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_SELF_MISSES")
	pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_SELF_MISSES")
	pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_PET_MISSES")
	pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_PET_MISSES")
	pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
	pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_SELF_BUFF")
	pcall(events.RegisterEvent, events, "CHAT_MSG_SPELL_AURA_GONE_SELF")
if events.RegisterUnitEvent then
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_START", "player")
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
end

function LockRemindersSameSpell(left, right)
	right = tonumber(right)
	if not right or right <= 0 then
		return false
	end
	if left == nil or LockRemindersSecret(left) then
		if not LockRemindersSecret(left) or not C_CurveUtil or not C_CurveUtil.EvaluateColorValueFromBoolean then
			return false
		end
		local ok, bit = pcall(function()
			return C_CurveUtil.EvaluateColorValueFromBoolean(left == right, 1, 0)
		end)
		if ok and type(bit) == "table" then
			bit = bit.r or bit[1]
		end
		return ok and tonumber(bit) == 1 and not LockRemindersSecret(bit)
	end
	return tonumber(left) == right
end

function LockRemindersMarkSecretAura(secretID)
	if not secretID or not LockRemindersSecret(secretID) or not db then
		return
	end
	LockRemindersCastSeen = LockRemindersCastSeen or {}
	local function stampSaved(saved)
		LockRemindersStampBuff(saved)
		LockRemindersBuffKnown = LockRemindersBuffKnown or {}
		LockRemindersBuffKnown[saved] = true
	end
	if type(db.auras) == "table" then
		for key in pairs(db.auras) do
			local saved = tonumber(key)
			if saved then
				local aliases = SpellAliases(saved)
				for index = 1, #aliases do
					if LockRemindersSameSpell(secretID, aliases[index]) then
						stampSaved(saved)
						return
					end
				end
			end
		end
	end
	if type(db.talents) == "table" then
		for key in pairs(db.talents) do
			local saved = tonumber(key)
			if saved then
				local aliases = SpellAliases(saved)
				for index = 1, #aliases do
					if LockRemindersSameSpell(secretID, aliases[index]) then
						stampSaved(saved)
						pcall(TriggerTalent, saved)
						return
					end
				end
			end
		end
	end
end

function MarkCastBuff(spellID, spellName)
	LockRemindersCastSeen = LockRemindersCastSeen or {}
	if LockRemindersSecret(spellID) then
		LockRemindersMarkSecretAura(spellID)
		spellID = nil
	else
		spellID = tonumber(spellID)
	end
	if spellID and spellID > 0 then
		LockRemindersStampBuff(spellID)
	else
		spellID = nil
	end
	local wanted = ""
	if type(spellName) == "string" and spellName ~= "" and not (issecretvalue and issecretvalue(spellName)) then
		wanted = Normalize(spellName)
	elseif spellID then
		wanted = Normalize(SpellName(spellID) or "")
	end
	if wanted == "" or wanted:find("^spell ", 1, true) or wanted:find("^hechizo ", 1, true) then
		if spellID then
			pcall(TriggerTalent, spellID, spellName)
		end
		return
	end
	LockRemindersCastNames = LockRemindersCastNames or {}
	LockRemindersCastNames[wanted] = GetTime()
	if db and type(db.auras) == "table" then
		for key in pairs(db.auras) do
			local saved = tonumber(key)
			if saved and LockRemindersTalentNameMatch(Normalize(SpellName(saved) or ""), wanted) then
				LockRemindersStampBuff(saved)
			end
		end
	end
	local talentKey = LockRemindersTalentKeyFromName and LockRemindersTalentKeyFromName(wanted)
	if talentKey then
		LockRemindersStampBuff(talentKey)
		local aliases = LockRemindersTalentAliasNames(talentKey)
		local stampAt = GetTime()
		for index = 1, #aliases do
			LockRemindersCastNames[aliases[index]] = stampAt
		end
	end
	pcall(TriggerTalent, spellID or talentKey, spellName or wanted)
end

function LockRemindersStampBuff(spellID)
	spellID = tonumber(spellID)
	if not spellID or spellID <= 0 then
		return
	end
	LockRemindersCastSeen = LockRemindersCastSeen or {}
	LockRemindersBuffGone = LockRemindersBuffGone or {}
	local now = GetTime()
	local aliases = SpellAliases(spellID)
	for index = 1, #aliases do
		LockRemindersCastSeen[aliases[index]] = now
		LockRemindersBuffGone[aliases[index]] = nil
	end
	LockRemindersCastSeen[spellID] = now
	LockRemindersBuffGone[spellID] = nil
	if LockRemindersBuffUntil then
		LockRemindersBuffUntil[spellID] = nil
		for index = 1, #aliases do
			LockRemindersBuffUntil[aliases[index]] = nil
		end
	end
	if LockRemindersAuraSync then
		LockRemindersAuraSync[spellID] = nil
		for index = 1, #aliases do
			LockRemindersAuraSync[aliases[index]] = nil
		end
	end
end

function LockRemindersForgetBuff(spellID, spellName)
	local key
	if spellID and not LockRemindersSecret(spellID) then
		key = SavedAuraKey(spellID)
	end
	if not key and type(spellName) == "string" and spellName ~= "" and not LockRemindersSecret(spellName) and db and type(db.auras) == "table" then
		local wanted = Normalize(spellName)
		for saved in pairs(db.auras) do
			local id = tonumber(saved)
			if id and Normalize(SpellName(id) or "") == wanted then
				key = id
			end
		end
	end
	if not key then
		return
	end
	LockRemindersBuffGone = LockRemindersBuffGone or {}
	LockRemindersBuffGone[key] = true
	if LockRemindersBuffKnown then
		LockRemindersBuffKnown[key] = false
	end
	if LockRemindersBuffUntil then
		LockRemindersBuffUntil[key] = nil
	end
	if LockRemindersAuraSync then
		LockRemindersAuraSync[key] = nil
	end
	if LockRemindersCastSeen then
		LockRemindersCastSeen[key] = nil
		local aliases = SpellAliases(key)
		for index = 1, #aliases do
			LockRemindersCastSeen[aliases[index]] = nil
			LockRemindersBuffGone[aliases[index]] = true
		end
	end
	if LockRemindersCastNames and type(spellName) == "string" and not LockRemindersSecret(spellName) then
		LockRemindersCastNames[Normalize(spellName)] = nil
	end
end

function WatchCombatAlerts()
	if not events or events.combatTicker then
		return
	end
	events.combatTicker = C_Timer.NewTicker(0.5, function()
		if not InCombatLockdown() then
			if events.combatTicker then
				events.combatTicker:Cancel()
				events.combatTicker = nil
			end
			return
		end
		pcall(Refresh)
	end)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		InitDB()
		return
	end
	if event == "PLAYER_LOGIN" then
		LockRemindersEnteredAt = GetTime() + 8
		CreateUI()
		CreatePanel()
		CreateTalentAlert()
		CreateFoodAlert()
		CreateSpellMissAlert()
		pcall(LockRemindersCacheMissNames)
		pcall(LockRemindersWatchMissChat)
		CreateCDManagerAlert()
		LockRemindersStartCDManager()
		CreateMiscAlerts()
		LockRemindersStartMisc()
		pcall(CreateSoulAlerts)
		pcall(LockRemindersCreatePetAlerts)
		LockRemindersStartSoul()
		pcall(LockRemindersHookElvUIAuras)
		pcall(LockRemindersStartTalentWatch)
		LockRemindersRegisterCastUnits()
		LockRemindersRegisterCombatUnits()
		CreateMinimapButton()
		Refresh()
		C_Timer.After(1, function()
			pcall(WatchTalents, true)
			pcall(LockRemindersCDPollAll)
			pcall(LockRemindersWatchMissChat)
			pcall(LockRemindersRegisterCombatUnits)
			pcall(LockRemindersHookElvUIAuras)
			pcall(LockRemindersStartTalentWatch)
		end)
		C_Timer.After(3, function()
			pcall(LockRemindersHookElvUIAuras)
		end)
		return
	end
	if event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "SPELL_DATA_LOAD_RESULT" then
		pcall(LockRemindersSyncSoulClick)
		pcall(LockRemindersCacheMissNames)
		InvalidateSpellbook()
		if UpdateListNow then
			UpdateListNow()
		end
	end
	if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		local ok, shown = pcall(LockRemindersNoteTalentGlow, arg1, true)
		if (not ok or not shown) and arg2 then
			ok, shown = pcall(LockRemindersNoteTalentGlow, arg2, true)
		end
		if not shown then
			pcall(LockRemindersPollTalentOverlay)
		end
		return
	end
	if event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		pcall(LockRemindersNoteTalentGlow, arg1, false)
		if arg2 then
			pcall(LockRemindersNoteTalentGlow, arg2, false)
		end
		return
	end
	if event == "SPELL_ACTIVATION_OVERLAY_SHOW" then
		local ok, shown = pcall(TriggerTalent, arg1, arg2)
		if (not ok or not shown) and arg2 then
			ok, shown = pcall(TriggerTalent, arg2, arg1)
		end
		if (not ok or not shown) and type(arg1) == "string" then
			ok, shown = pcall(TriggerTalent, nil, arg1)
		end
		if not shown then
			ok, shown = pcall(LockRemindersNoteTalentGlow, arg1, true)
		end
		if ok and shown then
			pcall(QuietScreenFlash)
		end
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		pcall(LockRemindersUpdateSpeed)
		pcall(LockRemindersFunOnTarget)
		pcall(LockRemindersRegisterCombatUnits)
	end
	if type(event) == "string" and event:find("CHAT_MSG_", 1, true) == 1 then
		pcall(LockRemindersReadMissLine, arg1)
		pcall(LockRemindersReadCcLine, arg1)
		pcall(LockRemindersReadTalentChat, arg1)
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		-- Quiet sounds after zoning / loading screens.
		LockRemindersEnteredAt = GetTime() + 8
		LockRemindersSoul.zoneMode = LockRemindersSoul.stable or LockRemindersSoul.mode or LockRemindersSoul.zoneMode
		LockRemindersSoul.soundMode = LockRemindersSoul.zoneMode or LockRemindersSoul.soundMode
		if LockRemindersBuffGone then
			for key in pairs(LockRemindersBuffGone) do
				LockRemindersBuffGone[key] = nil
			end
		end
		if LockRemindersBuffKnown then
			for key in pairs(LockRemindersBuffKnown) do
				LockRemindersBuffKnown[key] = nil
			end
		end
		if LockRemindersBuffUntil then
			for key in pairs(LockRemindersBuffUntil) do
				LockRemindersBuffUntil[key] = nil
			end
		end
		if LockRemindersAuraSync then
			for key in pairs(LockRemindersAuraSync) do
				LockRemindersAuraSync[key] = nil
			end
		end
		pcall(LockRemindersRegisterCastUnits)
		pcall(LockRemindersRegisterCombatUnits)
		pcall(LockRemindersCacheMissNames)
		pcall(LockRemindersWatchMissChat)
		PlaceMinimapButton()
		C_Timer.After(0.6, function()
			pcall(Refresh)
			pcall(LockRemindersCDPollAll)
			pcall(LockRemindersRegisterCombatUnits)
		end)
		C_Timer.After(2, function()
			pcall(LockRemindersCacheMissNames)
			pcall(LockRemindersWatchMissChat)
		end)
		C_Timer.After(1, function()
			pcall(WatchTalents, true)
		end)
	end
	if event == "PLAYER_REGEN_DISABLED" then
		WatchCombatAlerts()
	elseif event == "PLAYER_REGEN_ENABLED" then
		pcall(LockRemindersSyncSoulClick)
		if events.combatTicker then
			events.combatTicker:Cancel()
			events.combatTicker = nil
		end
		if LockRemindersCastSeen then
			for key in pairs(LockRemindersCastSeen) do
				LockRemindersCastSeen[key] = nil
			end
		end
		if LockRemindersCastNames then
			for key in pairs(LockRemindersCastNames) do
				LockRemindersCastNames[key] = nil
			end
		end
	end
	if event == "UNIT_COMBAT" then
		pcall(LockRemindersHandleUnitCombat, arg1, arg2, arg3, arg4, arg5)
		return
	end
	if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		pcall(LockRemindersNoteInterrupted, arg1, arg2, arg3, arg4, event == "UNIT_SPELLCAST_INTERRUPTED")
		return
	end
	if event == "GROUP_ROSTER_UPDATE" then
		pcall(LockRemindersRegisterCastUnits)
	end
	if event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE" then
		C_Timer.After(0.05, function()
			pcall(LockRemindersCDPollAll)
		end)
		if event ~= "BAG_UPDATE" then
			return
		end
	end
	if event == "UNIT_SPELLCAST_START" then
		pcall(LockRemindersNoteSoulStart, arg1, arg2, arg3, arg4)
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		pcall(LockRemindersNoteSoulCast, arg1, arg2, arg3, arg4)
		pcall(LockRemindersNoteCDCast, arg1, arg2, arg3, arg4)
		pcall(LockRemindersPetNoteCast, arg1, arg2, arg3, arg4)
		if arg1 == "player" or arg1 == "pet" then
			pcall(LockRemindersNoteCast, arg1, arg2, arg3, arg4)
		end
		if arg1 and arg1 ~= "player" then
			return
		end
		local castID, castName
		local function take(value)
			if value == nil then
				return
			end
			if LockRemindersSecret(value) then
				LockRemindersMarkSecretAura(value)
				return
			end
			if type(value) == "number" then
				castID = castID or value
				return
			end
			if type(value) ~= "string" or value == "" or value:find("-", 1, true) then
				return
			end
			local numeric = tonumber(value)
			if numeric then
				castID = castID or numeric
			else
				castName = castName or value
			end
		end
		take(arg2)
		take(arg3)
		take(arg4)
		MarkCastBuff(castID, castName)
		pcall(Refresh)
		C_Timer.After(0.15, function()
			pcall(Refresh)
		end)
		C_Timer.After(0.45, function()
			pcall(Refresh)
		end)
		return
	end
	if event == "UNIT_AURA" and (not arg1 or arg1 == "player" or arg1 == "vehicle") and type(arg2) == "table" and not (issecretvalue and issecretvalue(arg2)) then
		local removed = arg2.removedAuras
		if type(removed) == "table" and not LockRemindersSecret(removed) then
			for index = 1, #removed do
				local aura = removed[index]
				if type(aura) == "table" and not (issecretvalue and issecretvalue(aura)) then
					LockRemindersForgetBuff(aura.spellId or aura.spellID, aura.name)
				end
			end
		end
		local added = arg2.addedAuras
		if type(added) == "table" and not LockRemindersSecret(added) then
			for index = 1, #added do
				local aura = added[index]
				if type(aura) == "table" then
					-- Sealed Forever procs still arrive here as tables; match by sealed fields.
					local okNote, noted = pcall(LockRemindersNoteTalentAura, aura)
					if not (okNote and noted) then
						local key = LockRemindersMatchTalentAura(aura)
						if key then
							LockRemindersStampBuff(key)
							pcall(TriggerTalent, key)
						end
					end
					local auraID, auraName
					pcall(function()
						auraID = aura.spellId or aura.spellID
						auraName = aura.name
					end)
					if not LockRemindersSecret(aura) then
						MarkCastBuff(auraID, auraName)
						if not LockRemindersSecret(auraID) or not LockRemindersSecret(auraName) then
							pcall(TriggerTalent, auraID, auraName)
						end
					end
				end
			end
		end
		local updated = arg2.updatedAuraInstanceIDs
		if type(updated) == "table" and not LockRemindersSecret(updated) and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
			for index = 1, #updated do
				local instanceID = updated[index]
				if instanceID ~= nil and not LockRemindersSecret(instanceID) then
					local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceID)
					if ok and aura then
						pcall(LockRemindersNoteTalentAura, aura)
					end
				end
			end
		end
	end
	if event == "UNIT_AURA" and arg1 and arg1 ~= "player" and arg1 ~= "vehicle" then
		pcall(LockRemindersNoteAura, arg1, arg2)
		return
	end
	if event == "UNIT_AURA" then
		pcall(WatchTalents, false)
		pcall(LockRemindersQueueTalentScan)
	end
	if event == "SPELL_UPDATE_USABLE" or event == "ACTIONBAR_UPDATE_USABLE" then
		pcall(LockRemindersPollTalentOverlay)
		pcall(LockRemindersQueueTalentScan)
	end
	pcall(Refresh)
	if event == "UNIT_AURA" or event == "BAG_UPDATE_DELAYED" or event == "SPELL_DATA_LOAD_RESULT" or event == "ITEM_DATA_LOAD_RESULT" then
		QueueListRefresh()
	end
end)

SLASH_LOCKREMINDERS1 = "/lr"
SLASH_LOCKREMINDERS2 = "/lockreminders"
SlashCmdList.LOCKREMINDERS = Command
