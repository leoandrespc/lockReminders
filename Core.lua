local ADDON = ...

local WARLOCK = "WARLOCK"
local CREATE_HEALTHSTONE = 6201
local SACRIFICE = 108503
local HEALTHSTONES = { 5512, 224464 }
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
LockRemindersMisc = { speedMoving = false, vitalMoving = false, healthDown = false, manaDown = false }
LockRemindersSoul = { moving = false, trackMoving = false, missing = false, rows = {} }
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
		if not ok or (issecretvalue and issecretvalue(aura)) then
			return nil
		end
		if aura == nil or aura == false then
			absent = true
			return nil
		end
		return true
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
		if value == nil or (issecretvalue and issecretvalue(value)) then
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
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
			if not ok or aura == nil or aura == false or (issecretvalue and issecretvalue(aura)) then
				break
			end
			local id = aura.spellId or aura.spellID
			local name = aura.name
			if sameID(id) then
				return true
			end
			if wanted and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name:lower() == wanted then
				return true
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
	if absent and not InCombatLockdown() then
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
		if ItemCount(HEALTHSTONES[i]) > 0 then
			return true
		end
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
	return "always"
end

local function ScopeFlags(where)
	if type(where) == "table" then
		return where.always and true or false, where.party and true or false, where.raid and true or false
	end
	local mode = NormalizeScope(where)
	if mode == "raid" then
		return false, false, true
	end
	if mode == "party" then
		return false, true, false
	end
	return true, false, false
end

local function ScopeLabel(where)
	local always, party, raid = ScopeFlags(where)
	local parts = {}
	if raid then
		parts[#parts + 1] = "Raid"
	end
	if party then
		parts[#parts + 1] = "Party"
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
	return "always"
end

local function ScopeActive(where)
	local always, party, raid = ScopeFlags(where)
	if always then
		return true
	end
	if raid and IsInRaid() then
		return true
	end
	if party and IsInGroup() and not IsInRaid() then
		return true
	end
	return false
end

local function AuraScope(spellID)
	return db.auras[spellID] or db.auras[tostring(spellID)]
end

local function SpellAliases(spellID)
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
		if expires == nil or LockRemindersSecret(expires) then
			return nil
		end
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
	local function fromTable(aura)
		if type(aura) ~= "table" or LockRemindersSecret(aura) then
			return nil
		end
		return readExpires(aura.expirationTime or aura.expiration)
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
			local ok, name, _, _, _, _, _, expires = pcall(UnitBuff, "player", index)
			if not ok or name == nil or name == false or name == "" or LockRemindersSecret(name) then
				if not ok or name == nil or name == false or name == "" then
					break
				end
			elseif type(name) == "string" and Normalize(name) == wanted then
				local left = readExpires(expires)
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
		LockRemindersSoonTicker = C_Timer.NewTicker(0.2, function()
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

	local seenNames = {}
	for spellID, where in pairs(db.auras) do
		local show = ScopeActive(where)
		local name = SpellName(spellID)
		local nameKey = Normalize(name or "")
		if nameKey ~= "" and seenNames[nameKey] then
			show = false
		end
		if show and inCombat and not (type(where) == "table" and where.combat) then
			show = false
		end
		if show and KnowsSpell(spellID) then
			local left = LockRemindersAuraLeft(spellID)
			local soon = left and left > 0 and left <= 10
			local has = PlayerHasBuff(spellID)
			LockRemindersSoonSeen = LockRemindersSoonSeen or {}
			if left and left > 10 then
				LockRemindersSoonSeen[spellID] = nil
			elseif soon then
				LockRemindersSoonSeen[spellID] = true
			elseif LockRemindersSoonSeen[spellID] then
				has = false
			end
			if soon or has == false then
				if nameKey ~= "" then
					seenNames[nameKey] = true
				end
				list[#list + 1] = {
					key = "aura:" .. spellID,
					icon = SpellIcon(spellID),
					text = name,
					left = soon and math.ceil(left) or nil,
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

	if type(db.healthstone) == "table" and ScopeActive(db.healthstone) and LockRemindersIsWarlock() then
		local showStone = true
		if inCombat and not db.healthstone.combat then
			showStone = false
		end
		if showStone and not HasHealthstone() then
			list[#list + 1] = {
				key = "healthstone",
				icon = SpellIcon(CREATE_HEALTHSTONE),
				text = "Healthstone",
			}
		end
	end

	return list
end

local GAP = 8
local PAD = 10

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
	if type(db.healthstone) == "table" and LockRemindersIsWarlock() then
		list[#list + 1] = {
			key = "healthstone",
			icon = SpellIcon(CREATE_HEALTHSTONE),
			text = "Healthstone",
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
	local cols = ColumnsFor(count)
	local col = math.floor((px - PAD) / (size + GAP))
	local line = math.floor((py - PAD) / (size + GAP))
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
	row:SetSize(size, size)
	row.glow:SetSize(size * 1.9, size * 1.9)
	if row.count then
		local font = row.count:GetFont()
		if type(font) ~= "string" or font == "" then
			font = "Fonts\\FRIZQT__.TTF"
		end
		row.count:SetFont(font, math.max(14, math.floor(size * 0.62)), "OUTLINE")
	end
end

local Refresh

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
	row.icon:SetAllPoints()
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.glow = CreateFrame("Frame", nil, row)
	row.glow:SetPoint("CENTER")
	row.glow:SetSize(IconSize() * 1.9, IconSize() * 1.9)
	row.glow:SetFrameLevel(row:GetFrameLevel() + 2)
	row.glow.tex = row.glow:CreateTexture(nil, "OVERLAY")
	row.glow.tex:SetAllPoints()
	row.glow.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	row.glow.tex:SetBlendMode("ADD")
	row.glow.tex:SetVertexColor(1, 0.82, 0.35)

	local ag = row.glow:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local alpha = ag:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.15)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.55)
	alpha:SetSmoothing("IN_OUT")
	row.glow.ag = ag

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
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * (size + GAP), -(PAD + line * (size + GAP)))
		row:SetFrameLevel((frame:GetFrameLevel() or 1) + 2)
		row:EnableMouse(arranging)
		if arranging and missingKeys and not missingKeys[row.key] then
			row:SetAlpha(0.45)
		else
			row:SetAlpha(1)
		end
		row.quiet = list[i].left and true or false
		row.icon:SetVertexColor(1, 1, 1)
		if row.icon.SetDesaturated then
			row.icon:SetDesaturated(false)
		end
		if row.quiet then
			watching = true
			if row.glow.ag then
				row.glow.ag:Stop()
			end
			row.glow:Hide()
			row.count:SetText(tostring(list[i].left))
			row.count:SetTextColor(1, 1, 1)
			row.count:Show()
		else
			row.count:Hide()
			row.glow:Show()
		end
		row:Show()
		if not row.quiet then
			PlayGlow(row)
		end
	end
	LockRemindersSetSoonWatch(watching)
	for i = count + 1, #rows do
		rows[i]:Hide()
		rows[i].key = nil
	end
	frame:SetSize(PAD * 2 + cols * size + (cols - 1) * GAP, PAD * 2 + lines * size + (lines - 1) * GAP)
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

	if arranging and Restricted() then
		frame:Hide()
		return
	end

	local list = arranging and Tracked() or Missing()
	if not list then
		frame:Hide()
		LockRemindersSetSoonWatch(false)
		return
	end

	local catalog = Tracked()
	SyncOrder(catalog)
	SortEntries(list)
	if #list == 0 then
		frame:Hide()
		LockRemindersSetSoonWatch(false)
		return
	end

	local missingKeys
	if arranging then
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
	local always, party, raid = ScopeFlags(where)
	db.auras[spellID] = { always = always, party = party, raid = raid }
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
	Print("Food added: " .. info.name .. ". In a raid it alerts if none of the list is active.")
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

function ConsumableKept(itemID)
	local group = ConsumableGroup(itemID)
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
	db.foodItems[itemID] = spellID or true
	if spellID then
		Print("Consumable added: " .. name .. ".")
	else
		Print(name .. " is on the list. In a raid it alerts if its buff is missing.")
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
	local always, party, raid = ScopeFlags(db.auras[key])
	local combat = type(db.auras[key]) == "table" and db.auras[key].combat and true or false
	local scope = { always = always, party = party, raid = raid, combat = combat }
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
	local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
	if not ok or aura == nil then
		return "end"
	end
	local readOk, spellID, name, icon = pcall(function()
		if issecretvalue and issecretvalue(aura) then
			return nil
		end
		local id = aura.spellId or aura.spellID
		local auraName = aura.name
		local auraIcon = aura.icon
		if not id or not auraName or auraName == "" then
			return nil
		end
		if issecretvalue and (issecretvalue(id) or issecretvalue(auraName)) then
			return nil
		end
		if auraIcon and issecretvalue and issecretvalue(auraIcon) then
			auraIcon = nil
		end
		return id, auraName, auraIcon
	end)
	if not readOk or not spellID or not name then
		return "skip"
	end
	return "ok", spellID, name, icon
end

local function EachAura(callback)
	for index = 1, 40 do
		local status, spellID, name, icon = AuraAt(index)
		if status == "end" then
			return
		end
		if status == "ok" then
			callback(spellID, name, icon)
		end
	end
end

PlayerHasBuff = function(spellID)
	LockRemindersBuffKnown = LockRemindersBuffKnown or {}
	LockRemindersCastSeen = LockRemindersCastSeen or {}
	local aliases = SpellAliases(spellID)
	if InCombatLockdown() then
		if LockRemindersCastSeen[spellID] then
			LockRemindersBuffKnown[spellID] = true
			return true
		end
		for index = 1, #aliases do
			if LockRemindersCastSeen[aliases[index]] then
				LockRemindersBuffKnown[spellID] = true
				return true
			end
		end
	end
	local unknown = false
	for index = 1, #aliases do
		local has = HasAura(aliases[index])
		if has then
			LockRemindersBuffKnown[spellID] = true
			return true
		end
		if has == nil then
			unknown = true
		end
	end
	local wanted = Normalize(SpellName(spellID) or "")
	if wanted ~= "" and not (wanted:find("^hechizo ", 1, true) or wanted:find("^spell ", 1, true)) then
		local matched = false
		EachAura(function(_, name)
			if Normalize(name) == wanted then
				matched = true
			end
		end)
		if matched then
			LockRemindersBuffKnown[spellID] = true
			return true
		end
	end
	if not unknown then
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
				local itemID, count, icon
				if C_Container and C_Container.GetContainerItemInfo then
					local info = C_Container.GetContainerItemInfo(bag, slot)
					if info then
						itemID = info.itemID
						count = info.stackCount or 1
						icon = info.iconFileID
						RememberItemName(itemID, info.itemName)
						RememberItemName(itemID, NameFromLink(info.hyperlink))
					end
				elseif GetContainerItemID then
					itemID = GetContainerItemID(bag, slot)
					if itemID and GetContainerItemInfo then
						local _, itemCount = GetContainerItemInfo(bag, slot)
						count = itemCount or 1
					end
				end
				if itemID and not (issecretvalue and issecretvalue(itemID)) then
					local link
					if C_Container and C_Container.GetContainerItemLink then
						local ok, value = pcall(C_Container.GetContainerItemLink, bag, slot)
						if ok then
							link = value
						end
					elseif GetContainerItemLink then
						local ok, value = pcall(GetContainerItemLink, bag, slot)
						if ok then
							link = value
						end
					end
					RememberItemName(itemID, NameFromLink(link))
					if issecretvalue and issecretvalue(count) then
						count = 1
					end
					callback(itemID, tonumber(count) or 1, icon)
				end
			end
		end)
	end
end

local function BagContents()
	local counts = {}
	local icons = {}
	EachBagItem(function(itemID, count, icon)
		counts[itemID] = (counts[itemID] or 0) + count
		if icon then
			icons[itemID] = icon
		end
	end)
	return counts, icons
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
		if savedName ~= "" and savedName == wanted then
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
	db.talents[spellID] = { untilEnd = false }
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
		local untilEnd = db.talentUntilEnd
		if untilEnd == nil then
			untilEnd = type(db.talents[savedKey]) == "table" and db.talents[savedKey].untilEnd
		end
		entry.extraLabel = untilEnd and "Until end" or "Seconds"
		entry.sub = untilEnd and "Stays until the buff ends" or "Plays for the chosen seconds"
		entry.extra = function()
			local on = not (db.talentUntilEnd and true or false)
			if db.talentUntilEnd == nil then
				on = not (type(db.talents[savedKey]) == "table" and db.talents[savedKey].untilEnd)
			end
			db.talentUntilEnd = on and true or false
			db.talents[savedKey] = { untilEnd = db.talentUntilEnd }
			Print(db.talentUntilEnd and "The alert stays until the buff ends." or "The alert lasts for the chosen seconds.")
			Touch()
		end
	end
	if kind == "food" and savedKey then
		entry.combatToggle = true
		if FoodInCombat(nil, savedKey) then
			entry.sub = (entry.sub or "On your list") .. " · Combat"
		end
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
		entry.combatToggle = true
		if FoodInCombat(itemID) then
			entry.sub = (entry.sub or "") .. " · Combat"
		end
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
			local always, party, raid = ScopeFlags(addScope)
			db.pet = { always = always, party = party, raid = raid, combat = false }
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
			resolved = display
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
			backlash = { 34936, "Backlash" },
			contragolpe = { 34936, "Backlash" },
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

	if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
		local okTabs, tabCount = pcall(GetNumTalentTabs)
		tabCount = okTabs and tonumber(tabCount) or 0
		for tab = 1, tabCount do
			local okCount, count = pcall(GetNumTalents, tab)
			count = okCount and tonumber(count) or 0
			for index = 1, count do
				local okInfo, name, icon, _, _, rank = pcall(GetTalentInfo, tab, index)
				name = okInfo and Plain(name)
				rank = tonumber(rank) or 0
				local buff = name and catalog[talentKey(name)]
				if buff and rank > 0 then
					offer(buff[1], buff[2], icon, "From " .. name, name)
				end
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
			local always, party, raid = ScopeFlags(addScope)
			db.healthstone = { always = always, party = party, raid = raid, combat = false }
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
	local counts, icons = BagContents()

	local function push(itemID, name, icon, sub)
		itemID = tonumber(itemID)
		if not itemID or seen[itemID] then
			return
		end
		seen[itemID] = true
		if not name then
			RequestItem(itemID)
			name = "Loading..."
		end
		local group = ConsumableGroup(itemID)
		if db.foodItems[itemID] == nil and not ConsumableKept(itemID) then
			return
		end
		local rows = buckets[group]
		if not rows then
			rows = {}
			buckets[group] = rows
		end
		rows[#rows + 1] = ItemEntry(itemID, name, icon, sub, 0)
	end

	for itemID, count in pairs(counts) do
		pcall(function()
			if IsConsumableItem(itemID) then
				local name = ItemName(itemID)
				local wanted = query == "" or itemID == itemLink or itemID == typedID or NameMatches(name, query)
				if wanted then
					local sub = ConsumableGroup(itemID)
					if db.foodItems[itemID] then
						sub = "On your list · " .. sub
					else
						sub = sub .. " · x" .. tostring(count)
					end
					push(itemID, name, icons[itemID], sub)
				end
			end
		end)
	end

	local function pin(itemID)
		if not itemID or seen[itemID] then
			return
		end
		local saved = db.foodItems[itemID] ~= nil
		if not saved and not IsConsumableItem(itemID) then
			return
		end
		local name = ItemName(itemID)
		if query ~= "" and itemID ~= typedID and itemID ~= itemLink and not NameMatches(name, query) then
			return
		end
		local sub = ConsumableGroup(itemID)
		if saved then
			sub = "On your list · " .. sub
		end
		push(itemID, name, ItemIcon(itemID), sub)
	end

	pcall(pin, itemLink)
	pcall(pin, typedID)
	for itemID in pairs(db.foodItems) do
		pcall(pin, itemID)
	end

	local order = { "Food", "Potions", "Flasks", "Elixirs" }
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
		{ title = "Powers", rows = powers },
		{ title = "Consumables", rows = foods }
	)
end

function LockRemindersMissSpellSaved(spellID, spellName)
	if not db or type(db.missSpells) ~= "table" then
		return false
	end
	spellID = tonumber(spellID)
	if spellID and (db.missSpells[spellID] or db.missSpells[tostring(spellID)]) then
		return true
	end
	local wanted = Normalize(spellName or "")
	if wanted == "" or wanted:find("^spell ", 1, true) or wanted:find("^hechizo ", 1, true) then
		return false
	end
	for key in pairs(db.missSpells) do
		if Normalize(SpellName(key) or "") == wanted then
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
	Print((SpellName(spellID) or "Spell") .. " will alert when it misses or resists.")
	Touch()
end

function LockRemindersRemoveMissSpell(spellID, spellName)
	local wanted = Normalize(spellName or SpellName(spellID) or "")
	local numberID = tonumber(spellID)
	if numberID then
		db.missSpells[numberID] = nil
		db.missSpells[tostring(numberID)] = nil
	end
	if spellID ~= nil then
		db.missSpells[spellID] = nil
	end
	if wanted ~= "" then
		for key in pairs(db.missSpells) do
			if Normalize(SpellName(key) or "") == wanted then
				db.missSpells[key] = nil
			end
		end
	end
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

function LockRemindersCollectSpellMiss(query, typedID, spellLink)
	local saved = {}
	local book = {}
	local pets = {}
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

	local function offer(info, fromPet, into)
		if not info or seen[info.spellID] or seen[Normalize(info.name or "")] then
			return
		end
		if query ~= "" and info.spellID ~= typedID and info.spellID ~= spellLink and not NameMatches(info.name, query) then
			return
		end
		remember(info.spellID, info.name)
		into[#into + 1] = LockRemindersMissSpellEntry(info.spellID, info.name, info.icon, fromPet)
	end

	local spells = CollectSpellbook(false)
	for index = 1, #spells do
		offer(spells[index], false, book)
	end
	local petSpells = LockRemindersCollectPetSpells()
	for index = 1, #petSpells do
		offer(petSpells[index], true, pets)
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
	return Sections(
		{ title = "Chosen", rows = saved },
		{ title = "Pet spells", rows = pets },
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
			return "No spell with that name in your spellbook or your pet's."
		end
		return "No spells to choose yet.\nSummon your pet to list its spells."
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
			if type(settings) == "table" then
				local always, party, raid = ScopeFlags(settings)
				local current = always
				if flag == "raid" then
					current = raid
				elseif flag == "party" then
					current = party
				elseif flag == "combat" then
					current = settings.combat
				end
				local scope = {
					always = always,
					party = party,
					raid = raid,
					combat = settings.combat and true or false,
				}
				if flag == "combat" then
					scope.combat = not current and true or false
				else
					scope[flag] = not current and true or false
				end
				if row.entry.pet then
					db.pet = scope
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
			local always, party, raid = ScopeFlags(AuraScope(row.spellID))
			local current = always
			if flag == "raid" then
				current = raid
			elseif flag == "party" then
				current = party
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
		if row.entry and row.entry.action then
			row.entry.action()
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
		row.scopes.always:SetShown(full)
		row.scopes.combat:SetShown(true)
		row.scopes.combat:ClearAllPoints()
		if full then
			local where = (entry.pet and db.pet) or (entry.stone and db.healthstone) or AuraScope(entry.spellID)
			local always, party, raid = ScopeFlags(where)
			row.scopes.raid:SetChecked(raid)
			row.scopes.party:SetChecked(party)
			row.scopes.always:SetChecked(always)
			row.scopes.combat:SetChecked(type(where) == "table" and where.combat)
			row.scopes.combat:SetPoint("LEFT", row.scopes, "LEFT", 174, 0)
			row.scopes:SetWidth(252)
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
	orderTitle:SetPoint("TOPLEFT", 8, -140)
	orderTitle:SetText("Order inside the alert")
	orderTitle:SetTextColor(0.9, 0.82, 1)

	layoutEmpty = layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	layoutEmpty:SetPoint("TOPLEFT", 8, -168)
	layoutEmpty:SetWidth(420)
	layoutEmpty:SetJustifyH("LEFT")
	layoutEmpty:SetText("Add a power and you can order it here.")
	layoutEmpty:SetTextColor(0.75, 0.7, 0.84)
	layoutEmpty:Hide()
end

local function OrderLabel(entry)
	local spellID = tonumber(tostring(entry.key):match("^aura:(%d+)$"))
	local where = spellID and (db.auras[spellID] or db.auras[tostring(spellID)])
	if where then
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
	row:SetPoint("TOPLEFT", layoutRoot, "TOPLEFT", 0, -(168 + (index - 1) * 34))
	row:SetPoint("TOPRIGHT", layoutRoot, "TOPRIGHT", 0, -(168 + (index - 1) * 34))
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
	EnsureLayout()
	if not layoutRoot then
		return
	end
	layoutRoot:Show()
	layoutRoot:SetWidth(math.max(scroll:GetWidth(), 200))
	sizeValue:SetText(tostring(IconSize()))
	colsValue:SetText(ColumnsLabel())
	lockButton.label:SetText(db.locked and "Unlock frame" or "Lock frame")
	frameButton.label:SetText(db.showFrame and "Hide frame" or "Show frame")
	if db.showFrame then
		local r, g, b = ClassColor()
		frameButton:SetBackdropBorderColor(r, g, b, 1)
	else
		frameButton:SetBackdropBorderColor(0.58, 0.45, 0.82, 1)
	end
	arrangeButton.label:SetText(arranging and "Done" or "Arrange")
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

	local height = 180 + #list * 34
	if #list == 0 then
		layoutEmpty:Show()
		height = 208
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
end

local function RebuildList(resetScroll)
	if not panel or not panel:IsShown() or not searchBox then
		return
	end

	if activeTab == "alert" then
		local module = panel.alertModule or "powers"
		if module ~= "powers" then
			HideLayout()
			ReleaseBrowser()
			emptyLabel:Hide()
			scroll:Hide()
			if scrollBar then
				scrollBar:Hide()
			end
			return
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

	if activeTab == "misc" or activeTab == "soul" then
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
			panel.spellBar.sizeText:SetText(tostring(tonumber(db.missSize) or 40))
		end
		if db and panel.spellBar.holdText then
			panel.spellBar.holdText:SetText(string.format("%.1f", tonumber(db.missHold) or 2.2))
		end
		if panel.spellBar.moveButton then
			panel.spellBar.moveButton.label:SetText(LockRemindersMiss.moving and "Done" or "Move")
		end
		if panel.spellBar.refresh then
			panel.spellBar.refresh()
		end
	end
	local showMisc = activeTab == "misc"
	local showSoul = activeTab == "soul"
	local hideList = (activeTab == "alert" and module ~= "powers") or showMisc or showSoul
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
	if emptyLabel and (showMisc or showSoul) then
		emptyLabel:Hide()
	end
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", 14, -180)
	scroll:SetPoint("BOTTOMRIGHT", -24, 40)
	scroll:SetShown(not hideList)
	if scrollBar then
		scrollBar:SetShown(not hideList)
	end
	if talentSizeText and db then
		talentSizeText:SetText(tostring(tonumber(db.talentSize) or 72))
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
				panel.alertTitle:SetText("Talent alert")
			elseif module == "food" then
				panel.alertTitle:SetText("Consumable alert")
			elseif module == "spells" then
				panel.alertTitle:SetText("Spell alert")
			else
				panel.alertTitle:SetText("Power alert")
			end
		end
	end
	local powers = id == "powers"
	raidCheck:SetShown(powers)
	raidCheck.labelButton:SetShown(powers)
	modeHint:Hide()
	local showConfig = id == "powers" or id == "food" or id == "talents" or id == "spells"
	if panel.alertButton then
		panel.alertButton:SetShown(showConfig)
	end
	footer:SetText("")
	if searchBox then
		local showSearch = not configuring and id ~= "misc" and id ~= "soul"
		searchBox:SetShown(showSearch)
		if searchBox.searchChrome then
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
	local col = count % 4
	local row = math.floor(count / 4)
	local tab = CreateFrame("Button", nil, panel, "BackdropTemplate")
	tab:SetSize(172, 26)
	tab:SetPoint("TOPLEFT", 14 + col * 180, -48 - row * 32)
	Paint(tab, 0.12, 0.1, 0.16, 1, 0.35, 0.28, 0.48, 1)
	tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tab.label:SetPoint("CENTER")
	tab.label:SetJustifyH("CENTER")
	tab.label:SetText(label)
	if tab.label.SetWordWrap then
		tab.label:SetWordWrap(false)
	end
	tab.accent = tab:CreateTexture(nil, "OVERLAY")
	tab.accent:SetPoint("BOTTOMLEFT", 6, 2)
	tab.accent:SetPoint("BOTTOMRIGHT", -6, 2)
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
		if raw:find("Hspell:", 1, true) and activeTab ~= "powers" and activeTab ~= "talents" and activeTab ~= "spells" then
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
	local ok, box = pcall(CreateFrame, "EditBox", "LockRemindersSearchBox", panel, "SearchBoxTemplate")
	if ok and box then
		searchBox = box
		searchBox:SetPoint("TOPLEFT", 14, -118)
		searchBox:SetPoint("TOPRIGHT", -16, -118)
		searchBox:SetHeight(22)
		searchBox:SetAutoFocus(false)
		if searchBox.Instructions then
			searchBox.Instructions:SetText("Search by name")
		end
		BindSearchBox(searchBox, true)
		return
	end

	local bg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	bg:SetHeight(28)
	bg:SetPoint("TOPLEFT", 14, -116)
	bg:SetPoint("TOPRIGHT", -16, -48)
	Paint(bg, 0.03, 0.02, 0.05, 1, 0.4, 0.32, 0.55, 1)
	bg:EnableMouse(true)

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
	bg:SetScript("OnMouseDown", function()
		searchBox:SetFocus()
	end)
	searchBox:SetScript("OnEditFocusGained", function()
		bg:SetBackdropBorderColor(0.75, 0.62, 0.98, 1)
	end)
	searchBox:SetScript("OnEditFocusLost", function()
		bg:SetBackdropBorderColor(0.4, 0.32, 0.55, 1)
	end)
	BindSearchBox(searchBox, false)
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

local function TalentSize()
	local size = tonumber(db and db.talentSize) or 72
	if size < 40 then
		size = 40
	end
	if size > 160 then
		size = 160
	end
	return size
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
	talentFrame:SetSize(size, size)
	talentFrame.glow:SetSize(size * 2.15, size * 2.15)
	talentFrame.burst:SetSize(size * 2.6, size * 2.6)
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

function PlayAlertSound()
	local sound = db and db.talentSound or "none"
	if LockRemindersSoundFiles and LockRemindersSoundFiles[sound] then
		LockRemindersPlaySoundId(sound)
		return
	end
	local kits, legacy, file
	if sound == "alarm" then
		kits, legacy, file = { "RAID_WARNING" }, "RaidWarning", "Sound\\Interface\\RaidWarning.ogg"
	elseif sound == "bell" then
		kits, legacy, file = { "READY_CHECK" }, "ReadyCheck", "Sound\\Interface\\ReadyCheck.ogg"
	elseif sound == "level" then
		kits, legacy, file = { "LEVEL_UP", "LEVELUP" }, "LevelUp", "Sound\\Interface\\LevelUp.ogg"
	elseif sound == "coin" then
		kits, legacy, file = { "AUCTION_WINDOW_OPEN" }, "AuctionWindowOpen", "Sound\\Interface\\AuctionWindowOpen.ogg"
	elseif sound == "ping" then
		kits, legacy, file = { "MAP_PING" }, "MapPing", "Sound\\Interface\\MapPing.ogg"
	elseif sound == "tell" then
		kits, legacy, file = { "TELL_MESSAGE" }, "TellMessage", "Sound\\Interface\\TellMessage.ogg"
	elseif sound == "invite" then
		kits, legacy, file = { "IG_PLAYER_INVITE", "IG_PLAYER_INVITE_A" }, "igPlayerInvite", "Sound\\Interface\\iPlayerInviteA.ogg"
	elseif sound == "clock" then
		kits, legacy, file = { "ALARM_CLOCK_WARNING_3" }, "AlarmClockWarning3", "Sound\\Interface\\AlarmClockWarning3.ogg"
	else
		return
	end
	local function heard(ok, willPlay)
		return ok and willPlay ~= false
	end
	if SOUNDKIT then
		for index = 1, #kits do
			local id = SOUNDKIT[kits[index]]
			if type(id) == "number" then
				if heard(pcall(PlaySound, id, "SFX")) or heard(pcall(PlaySound, id)) then
					return
				end
			end
		end
	end
	if legacy and (heard(pcall(PlaySound, legacy, "SFX")) or heard(pcall(PlaySound, legacy))) then
		return
	end
	if PlaySoundFile and file then
		if heard(pcall(PlaySoundFile, file, "SFX")) or heard(pcall(PlaySoundFile, file, "Master")) then
			return
		end
		pcall(PlaySoundFile, file:gsub("\\", "/"), "Master")
	end
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

function ApplyTalentFace(spellID)
	if not talentFrame then
		return
	end
	local style = db and db.talentStyle or "icon"
	local size = TalentSize()
	talentFrame.icon:SetDrawLayer("OVERLAY", 7)
	talentFrame.icon:Show()
	talentFrame.icon:SetTexture(spellID and SpellIcon(spellID) or PreviewTalentIcon())
	if style == "icon" or not talentFrame.ornament then
		if talentFrame.ornament then
			talentFrame.ornament:Hide()
		end
		return
	end
	local texture = "Interface\\Buttons\\UI-ActionButton-Border"
	if style == "star" then
		texture = "Interface\\Cooldown\\star4"
	elseif style == "flash" then
		texture = "Interface\\Cooldown\\Ping4"
	elseif style == "lozenge" then
		texture = "Interface\\Cooldown\\Lozenge"
	elseif style == "glow" then
		texture = "Interface\\Buttons\\WHITE8x8"
	end
	talentFrame.ornament:SetDrawLayer("ARTWORK", 0)
	talentFrame.ornament:SetTexture(texture)
	talentFrame.ornament:SetSize(size * 1.8, size * 1.8)
	talentFrame.ornament:SetVertexColor(1, 0.86, 0.45)
	talentFrame.ornament:Show()
end

local function PlayTalent(spellID, preview)
	if not talentFrame then
		return
	end
	ApplyTalentLook()
	ApplyTalentPoint()
	ApplyTalentFace(spellID)
	talentFrame.spellID = spellID
	talentFrame:SetAlpha(1)
	talentFrame:SetScale(1)
	talentFrame:Show()
	PlayAlertSound()
	if talentFrame.glow.ag then
		talentFrame.glow.ag:Stop()
		talentFrame.glow.ag:Play()
	end
	if talentFrame.pop then
		talentFrame.pop:Stop()
		talentFrame.pop:Play()
	end
	if db.talentScreenFlash ~= false then
		if talentFrame.burstAg then
			talentFrame.burstAg:Stop()
			talentFrame.burstAg:Play()
		end
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
		return
	end
	local stay = not preview and TalentUntil(spellID)
	talentFrame.hold = stay
	if stay then
		return
	end
	talentFrame.hideTimer = C_Timer.NewTimer(TalentHold(), function()
		if not talentFrame or talentMoving then
			return
		end
		if talentFrame.fade then
			talentFrame.fade:Stop()
			talentFrame.fade:Play()
		else
			talentFrame:Hide()
		end
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
	if talentMoving then
		ApplyTalentLook()
		ApplyTalentPoint()
		ApplyTalentFace()
		talentFrame:Show()
		Print("Drag the animation. Press Done when you finish.")
	else
		ApplyTalentLook()
		talentFrame:Hide()
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ChangeTalentSize(delta)
	db.talentSize = TalentSize() + delta
	db.talentSize = TalentSize()
	ApplyTalentLook()
	if talentMoving and talentFrame then
		talentFrame:Show()
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

function TriggerTalent(spellID, name)
	if not db or type(db.talents) ~= "table" or not next(db.talents) then
		return
	end
	local key = TalentKey(spellID)
	if not key and name then
		local wanted
		pcall(function()
			local plain = Plain(name)
			wanted = plain and Normalize(plain) or nil
		end)
		if wanted and wanted ~= "" then
			for saved in pairs(db.talents) do
				local savedName = Normalize(SpellName(saved) or "")
				if savedName == wanted or (wanted == "shadow trance" and savedName == "nightfall") then
					key = saved
					break
				end
			end
		end
	end
	if not key then
		return
	end
	local now = GetTime()
	if talentRecent[key] and now - talentRecent[key] < 1.2 then
		return
	end
	talentRecent[key] = now
	if talentSeen then
		talentSeen[key] = true
	end
	PlayTalent(key)
end

function WatchTalents(prime)
	if not db or type(db.talents) ~= "table" then
		return
	end
	local now = {}
	for spellID in pairs(db.talents) do
		local has = PlayerHasBuff(spellID)
		if has == false and Normalize(SpellName(spellID) or "") == "nightfall" then
			local trance = false
			EachAura(function(_, auraName)
				if Normalize(auraName or "") == "shadow trance" then
					trance = true
				end
			end)
			if trance then
				has = true
			end
		end
		if has == true then
			now[spellID] = true
			if not prime and talentSeen and not talentSeen[spellID] then
				TriggerTalent(spellID)
			end
		elseif has == false then
			now[spellID] = false
			if talentFrame and talentFrame.hold and not talentMoving and talentFrame:IsShown() then
				local shown = talentFrame.spellID
				if shown == spellID or tostring(shown) == tostring(spellID) then
					talentFrame.hold = false
					if talentFrame.fade then
						talentFrame.fade:Stop()
						talentFrame.fade:Play()
					else
						talentFrame:Hide()
					end
				end
			end
		elseif talentSeen and talentSeen[spellID] then
			now[spellID] = true
		end
	end
	talentSeen = now
end

function ApplyFoodLook()
	if not foodFrame or not db then
		return
	end
	local size = tonumber(db.foodSize) or 48
	if size < 24 then
		size = 24
	end
	if size > 96 then
		size = 96
	end
	db.foodSize = size
	foodFrame:SetSize(size, size)
	foodFrame.glow:SetSize(size * 1.8, size * 1.8)
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
	foodFrame.hint:SetShown(foodFrame.moving)
	ApplyFoodLook()
	ApplyFoodPoint()
	if foodFrame.moving then
		local icon = FoodLabel()
		foodFrame.icon:SetTexture(icon)
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
end

function RefreshFood()
	if not foodFrame or not db then
		return
	end
	if foodFrame.moving then
		foodFrame:Show()
		return
	end
	if Blocked() or not IsInRaid() then
		foodFrame:Hide()
		return
	end
	if InCombatLockdown() and not AnyFoodInCombat() then
		foodFrame:Hide()
		return
	end
	local foodAuras = FoodAuraIDs()
	if #foodAuras == 0 then
		foodFrame:Hide()
		return
	end
	for index = 1, #foodAuras do
		local has = HasAura(foodAuras[index])
		if has == nil or has then
			foodFrame:Hide()
			return
		end
	end
	local icon = FoodLabel()
	foodFrame.icon:SetTexture(icon)
	ApplyFoodLook()
	ApplyFoodPoint()
	foodFrame:Show()
	foodFrame:SetAlpha(1)
	if foodFrame.glow.ag and not foodFrame.glow.ag:IsPlaying() then
		foodFrame.glow.ag:Play()
	end
end

function LockRemindersMissIconSize()
	local size = tonumber(db and db.missSize) or 40
	if size < 28 then
		size = 28
	end
	if size > 80 then
		size = 80
	end
	return size
end

LockRemindersSoundFiles = {
	pulse = true, drip = true, knock = true, chime = true,
	bloom = true, rise = true, tick = true, hum = true, spark = true, glass = true,
	beep = true, buzz = true, chirp = true, pop = true,
	ding = true, sweep = true, clap = true, warp = true,
}

function LockRemindersPlaySoundId(id)
	if LockRemindersSoundFiles[id] then
		if PlaySoundFile then
			pcall(PlaySoundFile, "Interface/AddOns/LockReminders/Sounds/" .. id .. ".mp3")
		end
		return
	end
	if id ~= "alarm" and id ~= "ping" then
		return
	end
	local kit, legacy, file
	if id == "alarm" then
		kit, legacy, file = "RAID_WARNING", "RaidWarning", "Sound\\Interface\\RaidWarning.ogg"
	else
		kit, legacy, file = "MAP_PING", "MapPing", "Sound\\Interface\\MapPing.ogg"
	end
	if SOUNDKIT and type(SOUNDKIT[kit]) == "number" then
		if pcall(PlaySound, SOUNDKIT[kit], "SFX") then
			return
		end
	end
	if legacy and pcall(PlaySound, legacy, "SFX") then
		return
	end
	if PlaySoundFile and file then
		pcall(PlaySoundFile, file, "Master")
	end
end

function LockRemindersPlayMissSound()
	LockRemindersPlaySoundId(db and db.missSound or "none")
end

function ApplySpellMissLook()
	if not LockRemindersMiss.frame or not db then
		return
	end
	local frame = LockRemindersMiss.frame
	local size = LockRemindersMissIconSize()
	db.missSize = size
	local width = math.max(size + 96, 240)
	frame:SetSize(width, size + 92)
	frame.icon:ClearAllPoints()
	frame.icon:SetPoint("TOP", 0, -8)
	frame.icon:SetSize(size, size)
	frame.glow:ClearAllPoints()
	frame.glow:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
	frame.glow:SetSize(size * 2.05, size * 2.05)
	frame.word:ClearAllPoints()
	frame.word:SetPoint("TOP", frame.icon, "BOTTOM", 0, -6)
	frame.word:SetWidth(width - 12)
	local font, _, flags = frame.word:GetFont()
	if font then
		frame.word:SetFont(font, math.max(22, math.floor(size * 0.5)), flags or "")
	end
	frame.spell:ClearAllPoints()
	frame.spell:SetPoint("TOP", frame.word, "BOTTOM", 0, -2)
	frame.spell:SetWidth(width - 12)
	frame.detail:ClearAllPoints()
	frame.detail:SetPoint("TOP", frame.spell, "BOTTOM", 0, -1)
	frame.detail:SetWidth(width - 12)
	if LockRemindersMiss.moving then
		Paint(frame, 0.08, 0.03, 0.03, 0.72, 0.85, 0.2, 0.16, 1)
		frame.hint:Show()
		frame:EnableMouse(true)
	else
		pcall(frame.SetBackdrop, frame, nil)
		frame.hint:Hide()
		frame:EnableMouse(false)
	end
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

function ShowSpellMiss(spellID, spellName, icon, kind, missType, destName)
	if not LockRemindersMiss.frame or LockRemindersMiss.moving or Blocked() then
		return
	end
	if type(spellName) ~= "string" or spellName == "" or (issecretvalue and issecretvalue(spellName)) then
		spellName = SpellName(spellID)
	end
	if type(destName) ~= "string" or (issecretvalue and issecretvalue(destName)) then
		destName = nil
	end
	local label = "MISSED"
	local wordR, wordG, wordB = 1, 0.55, 0.18
	if missType == "RESIST" then
		label = "RESISTED"
		wordR, wordG, wordB = 1, 0.22, 0.18
	elseif missType == "IMMUNE" then
		label = "IMMUNE"
		wordR, wordG, wordB = 1, 0.86, 0.35
	end
	local detail = ""
	if destName and destName ~= "" then
		detail = destName
	end
	if kind == "pet" then
		detail = detail ~= "" and (detail .. " · Pet") or "Pet"
	end
	local frame = LockRemindersMiss.frame
	frame.icon:SetTexture(icon or SpellIcon(spellID) or 136235)
	frame.word:SetText(label)
	frame.word:SetTextColor(wordR, wordG, wordB)
	if frame.glow then
		if missType == "IMMUNE" then
			frame.glow:SetVertexColor(1, 0.75, 0.2, 0.9)
		else
			frame.glow:SetVertexColor(1, 0.15, 0.1, 0.9)
		end
	end
	frame.spell:SetText(spellName or "Spell")
	frame.detail:SetText(detail)
	ApplySpellMissLook()
	ApplySpellMissPoint()
	frame:SetScale(1)
	frame:SetAlpha(0)
	frame:Show()
	if frame.fade then
		pcall(function()
			frame.fade:Stop()
		end)
	end
	if frame.intro then
		pcall(function()
			frame.intro:Stop()
			frame.intro:Play()
		end)
	else
		frame:SetAlpha(1)
	end
	if LockRemindersMiss.ticker then
		LockRemindersMiss.ticker:Cancel()
		LockRemindersMiss.ticker = nil
	end
	local hold = tonumber(db.missHold) or 2.2
	if hold < 0.8 then
		hold = 0.8
	end
	LockRemindersMiss.ticker = C_Timer.NewTimer(hold, function()
		LockRemindersMiss.ticker = nil
		if not LockRemindersMiss.frame or LockRemindersMiss.moving then
			return
		end
		if LockRemindersMiss.frame.fade then
			pcall(function()
				LockRemindersMiss.frame.fade:Play()
			end)
		else
			LockRemindersMiss.frame:Hide()
		end
	end)
	LockRemindersPlayMissSound()
end

function ChangeMissSize(delta)
	if not db then
		return
	end
	db.missSize = LockRemindersMissIconSize() + delta
	ApplySpellMissLook()
	if LockRemindersMiss.moving then
		LockRemindersMiss.frame:Show()
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ChangeMissHold(delta)
	if not db then
		return
	end
	local hold = (tonumber(db.missHold) or 2.2) + delta
	if hold < 0.8 then
		hold = 0.8
	end
	if hold > 6 then
		hold = 6
	end
	db.missHold = hold
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function ShowMissPreview(show)
	if not LockRemindersMiss.frame then
		return
	end
	LockRemindersMiss.moving = show and true or false
	ApplySpellMissLook()
	ApplySpellMissPoint()
	if LockRemindersMiss.moving then
		if LockRemindersMiss.ticker then
			LockRemindersMiss.ticker:Cancel()
			LockRemindersMiss.ticker = nil
		end
		if LockRemindersMiss.frame.intro then
			pcall(function()
				LockRemindersMiss.frame.intro:Stop()
			end)
		end
		if LockRemindersMiss.frame.fade then
			pcall(function()
				LockRemindersMiss.frame.fade:Stop()
			end)
		end
		LockRemindersMiss.frame.icon:SetTexture(136235)
		LockRemindersMiss.frame.word:SetText("RESISTED")
		LockRemindersMiss.frame.word:SetTextColor(1, 0.22, 0.18)
		LockRemindersMiss.frame.spell:SetText("Shadow Bolt")
		LockRemindersMiss.frame.detail:SetText("Target")
		LockRemindersMiss.frame:SetScale(1)
		LockRemindersMiss.frame:Show()
		LockRemindersMiss.frame:SetAlpha(1)
	else
		LockRemindersMiss.frame:Hide()
	end
	if UpdateTalentChrome then
		UpdateTalentChrome()
	end
end

function CreateSpellMissAlert()
	if LockRemindersMiss.frame then
		return
	end
	LockRemindersMiss.frame = CreateFrame("Frame", "LockRemindersSpellMiss", UIParent, "BackdropTemplate")
	LockRemindersMiss.frame:SetFrameStrata("HIGH")
	LockRemindersMiss.frame:SetClampedToScreen(true)
	LockRemindersMiss.frame:SetMovable(true)
	LockRemindersMiss.frame:EnableMouse(true)
	LockRemindersMiss.frame:RegisterForDrag("LeftButton")
	LockRemindersMiss.frame:SetScript("OnDragStart", function(self)
		if LockRemindersMiss.moving then
			self:StartMoving()
		end
	end)
	LockRemindersMiss.frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveSpellMissPoint()
	end)
	local frame = LockRemindersMiss.frame
	frame.glow = frame:CreateTexture(nil, "BACKGROUND")
	frame.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	frame.glow:SetBlendMode("ADD")
	frame.glow:SetVertexColor(1, 0.15, 0.1, 0.9)
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.word = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.word:SetJustifyH("CENTER")
	frame.word:SetTextColor(1, 0.22, 0.18)
	frame.word:SetShadowColor(0, 0, 0, 1)
	frame.word:SetShadowOffset(2, -2)
	frame.spell = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.spell:SetJustifyH("CENTER")
	frame.spell:SetTextColor(1, 0.96, 0.9)
	frame.spell:SetShadowColor(0, 0, 0, 1)
	frame.spell:SetShadowOffset(1, -1)
	frame.detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.detail:SetJustifyH("CENTER")
	frame.detail:SetTextColor(1, 0.75, 0.7)
	frame.detail:SetShadowColor(0, 0, 0, 1)
	frame.detail:SetShadowOffset(1, -1)
	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.hint:SetPoint("TOP", frame, "BOTTOM", 0, -4)
	frame.hint:SetText("Drag")
	frame.hint:SetTextColor(1, 0.55, 0.45)
	frame.hint:Hide()

	local intro = frame:CreateAnimationGroup()
	local introFade = intro:CreateAnimation("Alpha")
	introFade:SetFromAlpha(0)
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
		if frame then
			frame:SetScale(1)
			frame:SetAlpha(1)
		end
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
		if frame and not LockRemindersMiss.moving then
			frame:Hide()
			frame:SetAlpha(1)
			frame:SetScale(1)
		end
	end)
	frame.fade = fade
	ApplySpellMissLook()
	ApplySpellMissPoint()
	frame:Hide()
end

function LockRemindersUnitPercent(current, max)
	if LockRemindersSecret(current) or LockRemindersSecret(max) then
		return nil
	end
	current = tonumber(current)
	max = tonumber(max)
	if not current or not max or max <= 0 then
		return nil
	end
	return math.floor(current / max * 100 + 0.5)
end

function LockRemindersSpeedPercent(unit)
	if not unit or not UnitExists or not UnitExists(unit) or not GetUnitSpeed then
		return nil
	end
	local ok, current = pcall(GetUnitSpeed, unit)
	if not ok or current == nil or LockRemindersSecret(current) then
		return nil
	end
	current = tonumber(current)
	if not current then
		return nil
	end
	if current < 0 then
		current = 0
	end
	return math.floor(current / 7 * 100 + 0.5)
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
	return math.floor(yards / dt / 7 * 100 + 0.5)
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

function LockRemindersReadSpeed(unit)
	local api = LockRemindersSpeedPercent(unit)
	local motion = LockRemindersSpeedFromMotion(unit)
	if unit == "player" and LockRemindersPlayerIsMoving() == false then
		return 0
	end
	if motion == 0 and not (unit == "player" and LockRemindersPlayerIsMoving() == true) then
		return 0
	end
	if api ~= nil and api > 0 then
		return LockRemindersCalmSpeed(api)
	end
	return LockRemindersCalmSpeed(motion)
end

function LockRemindersScaledPercent(kind)
	if not CurveConstants or not CurveConstants.ScaleTo100 then
		return nil
	end
	local ok, value
	if kind == "health" and UnitHealthPercent then
		ok, value = pcall(UnitHealthPercent, "player", true, CurveConstants.ScaleTo100)
	elseif kind == "mana" and UnitPowerPercent then
		local power = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
		ok, value = pcall(UnitPowerPercent, "player", power, true, CurveConstants.ScaleTo100)
	end
	if not ok or value == nil or LockRemindersSecret(value) then
		return nil
	end
	value = tonumber(value)
	if not value then
		return nil
	end
	return math.floor(value + 0.5)
end

function LockRemindersHealthPercent()
	if UnitHealth and UnitHealthMax then
		local okCurrent, current = pcall(UnitHealth, "player")
		local okMax, max = pcall(UnitHealthMax, "player")
		if okCurrent and okMax then
			local percent = LockRemindersUnitPercent(current, max)
			if percent ~= nil then
				return percent
			end
		end
	end
	return LockRemindersScaledPercent("health")
end

function LockRemindersManaPercent()
	local current, max
	if UnitPower and UnitPowerMax then
		local okCurrent, value = pcall(UnitPower, "player", 0)
		local okMax, total = pcall(UnitPowerMax, "player", 0)
		if okCurrent and okMax then
			current, max = value, total
		end
	end
	if current == nil and UnitMana and UnitManaMax then
		local okCurrent, value = pcall(UnitMana, "player")
		local okMax, total = pcall(UnitManaMax, "player")
		if okCurrent and okMax then
			current, max = value, total
		end
	end
	local percent = LockRemindersUnitPercent(current, max)
	if percent ~= nil then
		return percent
	end
	return LockRemindersScaledPercent("mana")
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
	local width = math.floor(size * 8 + 28)
	if width < 128 then
		width = 128
	end
	frame:SetSize(width, size + 18)
end

function LockRemindersUpdateSpeed()
	local frame = LockRemindersMisc.speed
	if not frame or not db then
		return
	end
	if db.speedShow == false and not LockRemindersMisc.speedMoving then
		frame:Hide()
		return
	end
	local mine = LockRemindersReadSpeed("player")
	if mine ~= nil then
		frame.lastMine = mine
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
		end
	end
	local left = frame.lastMine and (frame.lastMine .. "%") or "--"
	local right = frame.lastTarget and (frame.lastTarget .. "%") or "--"
	frame.text:SetText(left .. " / " .. right)
	frame:Show()
end

function LockRemindersSetSpeedMove(on)
	LockRemindersMisc.speedMoving = on and true or false
	local frame = LockRemindersMisc.speed
	if not frame then
		return
	end
	frame:SetAlpha(1)
	if LockRemindersMisc.speedMoving then
		frame:Show()
		frame:EnableMouse(true)
		frame.hint:Show()
		frame:SetBackdropColor(0.08, 0.05, 0.12, 0.75)
		frame:SetBackdropBorderColor(0.7, 0.55, 0.95, 0.95)
	else
		frame:EnableMouse(false)
		frame.hint:Hide()
		frame:SetBackdropColor(0, 0, 0, 0)
		frame:SetBackdropBorderColor(0, 0, 0, 0)
	end
	LockRemindersUpdateSpeed()
	LockRemindersRefreshMisc()
end

function LockRemindersApplyVitalLook()
	local frame = LockRemindersMisc.vital
	if not frame or not db then
		return
	end
	local size = tonumber(db.vitalSize) or 32
	if size < 16 then
		size = 16
	elseif size > 64 then
		size = 64
	end
	db.vitalSize = size
	local font = frame.health:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	frame.health:SetFont(font, size, "OUTLINE")
	frame.mana:SetFont(font, size, "OUTLINE")
	frame.health:SetText(LockRemindersVitalLabel("health"))
	frame.mana:SetText(LockRemindersVitalLabel("mana"))
	local width = math.max(frame.health:GetStringWidth() or 0, frame.mana:GetStringWidth() or 0)
	frame:SetSize(math.max(math.floor(size * 8 + 24), math.floor(width + size * 2)), math.floor(size * 2.6 + 16))
	LockRemindersApplyVitalFace()
end

function LockRemindersVitalLabel(kind)
	local text = db and (kind == "mana" and db.manaLabel or db.healthLabel)
	if type(text) ~= "string" or text == "" then
		return kind == "mana" and "LOW MANA" or "LOW HEALTH"
	end
	return text
end

function LockRemindersApplyVitalFace()
	local frame = LockRemindersMisc.vital
	if not frame then
		return
	end
	if frame.ornament then
		frame.ornament:Hide()
	end
	local style = db and db.vitalStyle or "none"
	if frame.motionStyle ~= style then
		frame.motionStyle = style
		frame.motionT = 0
	end
end

function LockRemindersAnchorVitalText(ox, oy)
	local frame = LockRemindersMisc.vital
	if not frame then
		return
	end
	ox = ox or 0
	oy = oy or 0
	local healthLow = frame.health:IsShown()
	local manaLow = frame.mana:IsShown()
	frame.health:ClearAllPoints()
	frame.mana:ClearAllPoints()
	if healthLow and manaLow then
		frame.health:SetPoint("TOP", frame, "TOP", ox, -4 + oy)
		frame.mana:SetPoint("TOP", frame.health, "BOTTOM", 0, -2)
	elseif healthLow then
		frame.health:SetPoint("CENTER", frame, "CENTER", ox, oy)
	elseif manaLow then
		frame.mana:SetPoint("CENTER", frame, "CENTER", ox, oy)
	end
end

function LockRemindersStepVitalMotion(frame, elapsed)
	if not frame or not frame.health or not db then
		return
	end
	local style = db.vitalStyle or "none"
	local active = frame:IsShown() and not LockRemindersMisc.vitalMoving and (style == "pulse" or style == "shake" or style == "bounce" or style == "flash" or style == "pop")
	if not active then
		if frame.motionOn then
			frame.motionOn = nil
			frame.motionT = 0
			local size = tonumber(db.vitalSize) or 32
			local font = frame.health:GetFont()
			if type(font) ~= "string" or font == "" then
				font = "Fonts\\FRIZQT__.TTF"
			end
			frame.health:SetFont(font, size, "OUTLINE")
			frame.mana:SetFont(font, size, "OUTLINE")
			if not LockRemindersMisc.curveShown then
				frame.health:SetAlpha(frame.health:IsShown() and 1 or 0)
				frame.mana:SetAlpha(frame.mana:IsShown() and 1 or 0)
			end
			LockRemindersAnchorVitalText(0, 0)
		end
		return
	end
	frame.motionOn = true
	frame.motionT = (frame.motionT or 0) + (elapsed or 0)
	local t = frame.motionT
	local size = tonumber(db.vitalSize) or 32
	local scale, alpha, ox, oy = 1, 1, 0, 0
	if style == "pulse" then
		scale = 1 + 0.2 * math.sin(t * 7)
	elseif style == "shake" then
		ox = math.sin(t * 36) * 9
	elseif style == "bounce" then
		oy = math.abs(math.sin(t * 7)) * 18
	elseif style == "flash" then
		if LockRemindersMisc.curveShown then
			scale = 1 + 0.14 * math.sin(t * 18)
		else
			alpha = 0.15 + 0.85 * (0.5 + 0.5 * math.sin(t * 18))
		end
	elseif style == "pop" then
		local phase = t % 0.74
		if phase < 0.14 then
			scale = 1 + (phase / 0.14) * 0.55
		elseif phase < 0.34 then
			scale = 1.55 - ((phase - 0.14) / 0.2) * 0.63
		else
			scale = 0.92
		end
	end
	local font = frame.health:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	local drawn = size * scale
	if drawn < 12 then
		drawn = 12
	end
	frame.health:SetFont(font, drawn, "OUTLINE")
	frame.mana:SetFont(font, drawn, "OUTLINE")
	if not LockRemindersMisc.curveShown then
		frame.health:SetAlpha(frame.health:IsShown() and alpha or 0)
		frame.mana:SetAlpha(frame.mana:IsShown() and alpha or 0)
	end
	LockRemindersAnchorVitalText(ox, oy)
end

function LockRemindersPlaceVitalText(healthLow, manaLow)
	local frame = LockRemindersMisc.vital
	if not frame then
		return
	end
	frame.health:SetAlpha(1)
	frame.mana:SetAlpha(1)
	frame.health:SetText(LockRemindersVitalLabel("health"))
	frame.mana:SetText(LockRemindersVitalLabel("mana"))
	frame.health:SetShown(healthLow and true or false)
	frame.mana:SetShown(manaLow and true or false)
	LockRemindersAnchorVitalText(0, 0)
	LockRemindersApplyVitalFace()
end

function LockRemindersAttachPop(frame, shouldStay)
	local intro = frame:CreateAnimationGroup()
	local introFade = intro:CreateAnimation("Alpha")
	introFade:SetFromAlpha(0)
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

function LockRemindersSyncVital(healthLow, manaLow, soundId, replay)
	local frame = LockRemindersMisc.vital
	if not frame or LockRemindersMisc.vitalMoving then
		return
	end
	if not healthLow and not manaLow then
		if not frame:IsShown() then
			return
		end
		if frame.fade and frame.fade:IsPlaying() then
			return
		end
		if frame.intro and frame.intro:IsPlaying() then
			frame.intro:Stop()
			frame:SetScale(1)
		end
		frame:SetAlpha(1)
		if frame.fade then
			frame.fade:Play()
		else
			frame:Hide()
		end
		return
	end
	local healthShown = frame.health:IsShown()
	local manaShown = frame.mana:IsShown()
	if not frame:IsShown() or replay or healthShown ~= healthLow or manaShown ~= manaLow then
		LockRemindersApplyVitalLook()
		LockRemindersPlaceVitalText(healthLow, manaLow)
	end
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
	if soundId and soundId ~= "none" then
		LockRemindersPlaySoundId(soundId)
	end
end

function LockRemindersSetVitalMove(on)
	LockRemindersMisc.vitalMoving = on and true or false
	local frame = LockRemindersMisc.vital
	if not frame then
		return
	end
	if frame.intro and frame.intro:IsPlaying() then
		frame.intro:Stop()
	end
	if frame.fade and frame.fade:IsPlaying() then
		frame.fade:Stop()
	end
	frame:SetScale(1)
	frame:SetAlpha(1)
	if LockRemindersMisc.vitalMoving then
		LockRemindersApplyVitalLook()
		LockRemindersPlaceVitalText(true, true)
		frame:Show()
		frame:EnableMouse(true)
		frame.hint:Show()
		frame:SetBackdropColor(0.08, 0.05, 0.12, 0.72)
		frame:SetBackdropBorderColor(0.7, 0.5, 0.9, 0.9)
	else
		frame:EnableMouse(false)
		frame.hint:Hide()
		frame:SetBackdropColor(0, 0, 0, 0)
		frame:SetBackdropBorderColor(0, 0, 0, 0)
		LockRemindersMisc.previewUntil = nil
		LockRemindersMiscTick()
	end
	LockRemindersRefreshMisc()
end

function LockRemindersPreviewVital(kind)
	if not LockRemindersMisc.vital then
		return
	end
	if LockRemindersMisc.vitalMoving then
		LockRemindersSetVitalMove(false)
	end
	local sound = kind == "mana" and (db and db.manaSound or "drip") or (db and db.healthSound or "pulse")
	LockRemindersMisc.previewUntil = GetTime() + LockRemindersVitalHold()
	LockRemindersSyncVital(kind ~= "mana", kind ~= "health", sound, true)
end

function LockRemindersVitalCurve(percent)
	LockRemindersMisc.curves = LockRemindersMisc.curves or {}
	percent = tonumber(percent) or 35
	local curve = LockRemindersMisc.curves[percent]
	if curve then
		return curve
	end
	if not C_CurveUtil or not C_CurveUtil.CreateCurve or not Enum or not Enum.LuaCurveType then
		return nil
	end
	local ok, created = pcall(C_CurveUtil.CreateCurve)
	if not ok or not created or not created.AddPoint then
		return nil
	end
	local edge = percent / 100
	if edge < 0.01 then
		edge = 0.01
	elseif edge > 0.99 then
		edge = 0.99
	end
	pcall(created.SetType, created, Enum.LuaCurveType.Step)
	created:AddPoint(0, 1)
	created:AddPoint(edge, 1)
	created:AddPoint(math.min(edge + 0.001, 1), 0)
	created:AddPoint(1, 0)
	LockRemindersMisc.curves[percent] = created
	return created
end

function LockRemindersCurveAlpha(kind, percent)
	local curve = LockRemindersVitalCurve(percent)
	if not curve then
		return nil
	end
	local ok, alpha
	if kind == "health" and UnitHealthPercent then
		ok, alpha = pcall(UnitHealthPercent, "player", true, curve)
	elseif kind == "mana" and UnitPowerPercent then
		local power = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
		ok, alpha = pcall(UnitPowerPercent, "player", power, true, curve)
	end
	if not ok or alpha == nil then
		return nil
	end
	return alpha
end

function LockRemindersCurveFlag(kind, percent)
	local alpha = LockRemindersCurveAlpha(kind, percent)
	if alpha == nil or LockRemindersSecret(alpha) then
		return nil
	end
	alpha = tonumber(alpha)
	if not alpha then
		return nil
	end
	return alpha >= 0.5
end

function LockRemindersShowCurveVitals(healthOn, manaOn, healthPct, manaPct)
	local frame = LockRemindersMisc.vital
	if not frame then
		return false
	end
	local healthAlpha = healthOn and LockRemindersCurveAlpha("health", healthPct) or nil
	local manaAlpha = manaOn and LockRemindersCurveAlpha("mana", manaPct) or nil
	if healthAlpha == nil and manaAlpha == nil then
		return false
	end
	LockRemindersMisc.curveShown = true
	LockRemindersApplyVitalLook()
	LockRemindersPlaceVitalText(healthAlpha ~= nil, manaAlpha ~= nil)
	if healthAlpha ~= nil then
		frame.health:SetAlpha(healthAlpha)
	end
	if manaAlpha ~= nil then
		frame.mana:SetAlpha(manaAlpha)
	end
	if frame.fade and frame.fade:IsPlaying() then
		frame.fade:Stop()
	end
	if frame.intro and frame.intro:IsPlaying() then
		frame.intro:Stop()
	end
	frame:SetScale(1)
	frame:SetAlpha(1)
	frame:Show()
	return true
end

function LockRemindersMiscTick()
	if not db then
		return
	end
	LockRemindersUpdateSpeed()
	if not LockRemindersMisc.vital or LockRemindersMisc.vitalMoving then
		return
	end
	if LockRemindersMisc.previewUntil and GetTime() < LockRemindersMisc.previewUntil then
		return
	end
	local healthOn = db.healthAlert ~= false
	local manaOn = db.manaAlert ~= false
	local healthPct = tonumber(db.healthPct) or 35
	local manaPct = tonumber(db.manaPct) or 25
	local hp = LockRemindersHealthPercent()
	local mp = LockRemindersManaPercent()
	if healthOn and hp == nil then
		local low = LockRemindersCurveFlag("health", healthPct)
		if low == true then
			hp = 0
		elseif low == false then
			hp = 100
		end
	end
	if manaOn and mp == nil then
		local low = LockRemindersCurveFlag("mana", manaPct)
		if low == true then
			mp = 0
		elseif low == false then
			mp = 100
		end
	end
	if (healthOn and hp == nil) or (manaOn and mp == nil) then
		if LockRemindersShowCurveVitals(healthOn and hp == nil, manaOn and mp == nil, healthPct, manaPct) then
			return
		end
	end
	LockRemindersMisc.curveShown = false
	local healthLow = LockRemindersMisc.healthDown
	local manaLow = LockRemindersMisc.manaDown
	local sound
	if not healthOn then
		healthLow = false
		LockRemindersMisc.healthDown = false
	elseif hp ~= nil then
		if LockRemindersMisc.healthDown then
			healthLow = hp <= healthPct + 3
		else
			healthLow = hp <= healthPct
		end
		if healthLow and not LockRemindersMisc.healthDown then
			sound = db.healthSound or "pulse"
		end
		LockRemindersMisc.healthDown = healthLow
	end
	if not manaOn then
		manaLow = false
		LockRemindersMisc.manaDown = false
	elseif mp ~= nil then
		if LockRemindersMisc.manaDown then
			manaLow = mp <= manaPct + 3
		else
			manaLow = mp <= manaPct
		end
		if manaLow and not LockRemindersMisc.manaDown then
			if not sound then
				sound = db.manaSound or "drip"
			end
		end
		LockRemindersMisc.manaDown = manaLow
	end
	if not healthLow and not manaLow then
		LockRemindersMisc.vitalUntil = nil
		LockRemindersSyncVital(false, false, nil, false)
		return
	end
	local now = GetTime()
	if sound then
		LockRemindersMisc.vitalUntil = now + LockRemindersVitalHold()
	end
	if not LockRemindersMisc.vitalUntil or now >= LockRemindersMisc.vitalUntil then
		LockRemindersSyncVital(false, false, nil, false)
		return
	end
	LockRemindersSyncVital(healthLow, manaLow, sound, false)
end

function LockRemindersVitalHold()
	local hold = tonumber(db and db.vitalHold) or 3
	if hold < 1 then
		hold = 1
	elseif hold > 8 then
		hold = 8
	end
	return hold
end

function LockRemindersStartMisc()
	if LockRemindersMisc.ticker or not C_Timer then
		return
	end
	if C_Timer.NewTicker then
		LockRemindersMisc.ticker = C_Timer.NewTicker(0.1, function()
			pcall(LockRemindersMiscTick)
		end)
		return
	end
	local function again()
		pcall(LockRemindersMiscTick)
		C_Timer.After(0.1, again)
	end
	C_Timer.After(0.1, again)
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
	if bar.vitalSize then
		bar.vitalSize:SetText(tostring(tonumber(db.vitalSize) or 32))
	end
	if bar.holdText then
		bar.holdText:SetText(string.format("%.1f", LockRemindersVitalHold()))
	end
	if bar.healthText then
		bar.healthText:SetText(tostring(tonumber(db.healthPct) or 35) .. "%")
	end
	if bar.manaText then
		bar.manaText:SetText(tostring(tonumber(db.manaPct) or 25) .. "%")
	end
	if bar.speedMove then
		bar.speedMove.label:SetText(LockRemindersMisc.speedMoving and "Done" or "Move")
	end
	if bar.vitalMove then
		bar.vitalMove.label:SetText(LockRemindersMisc.vitalMoving and "Done" or "Move")
	end
	if bar.healthLabelBox and not bar.healthLabelBox:HasFocus() then
		bar.healthLabelBox.quiet = true
		bar.healthLabelBox:SetText(LockRemindersVitalLabel("health"))
		bar.healthLabelBox.quiet = nil
	end
	if bar.manaLabelBox and not bar.manaLabelBox:HasFocus() then
		bar.manaLabelBox.quiet = true
		bar.manaLabelBox:SetText(LockRemindersVitalLabel("mana"))
		bar.manaLabelBox.quiet = nil
	end
	LockRemindersPaintChoiceRow(bar.effectButtons, db.vitalStyle or "none")
	LockRemindersPaintToggle(bar.speedToggle, db.speedShow ~= false)
	LockRemindersPaintToggle(bar.healthToggle, db.healthAlert ~= false)
	LockRemindersPaintToggle(bar.manaToggle, db.manaAlert ~= false)
	if bar.refreshHealth then
		bar.refreshHealth()
	end
	if bar.refreshMana then
		bar.refreshMana()
	end
end

function LockRemindersMakeSoundRow(parent, y, read, write)
	local choices = {
		{ "None", "none" },
		{ "Pulse", "pulse" },
		{ "Drip", "drip" },
		{ "Knock", "knock" },
		{ "Chime", "chime" },
		{ "Bloom", "bloom" },
		{ "Rise", "rise" },
		{ "Tick", "tick" },
		{ "Hum", "hum" },
		{ "Spark", "spark" },
		{ "Glass", "glass" },
		{ "Beep", "beep" },
		{ "Buzz", "buzz" },
		{ "Chirp", "chirp" },
		{ "Pop", "pop" },
		{ "Ding", "ding" },
		{ "Sweep", "sweep" },
		{ "Clap", "clap" },
		{ "Warp", "warp" },
	}
	local buttons = {}
	local function refresh()
		local selected = read()
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
	for index = 1, #choices do
		local text, id = choices[index][1], choices[index][2]
		local col = (index - 1) % 10
		local row = math.floor((index - 1) / 10)
		local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
		button:SetSize(64, 22)
		button:SetPoint("TOPLEFT", 8 + col * 68, y - row * 26)
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button.label:SetText(text)
		button.choiceId = id
		button:SetScript("OnClick", function(self)
			write(self.choiceId)
			if self.choiceId ~= "none" then
				LockRemindersPlaySoundId(self.choiceId)
			end
			refresh()
		end)
		button:SetScript("OnEnter", function(self)
			if not self.picked then
				self:SetBackdropColor(0.24, 0.16, 0.34, 1)
			end
		end)
		button:SetScript("OnLeave", function()
			refresh()
		end)
		buttons[#buttons + 1] = button
	end
	return refresh
end

function LockRemindersOpenSettings(owner, key)
	local bar = CreateFrame("Frame", nil, owner)
	bar:SetPoint("TOPLEFT", 14, -180)
	bar:SetPoint("BOTTOMRIGHT", -16, 36)
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
	local function wheel(_, delta)
		local range = scroll:GetVerticalScrollRange() or 0
		local value = scroll:GetVerticalScroll() - delta * 36
		if value < 0 then
			value = 0
		end
		if value > range then
			value = range
		end
		scroll:SetVerticalScroll(value)
	end
	bar.wheel = wheel
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", wheel)
	body:EnableMouseWheel(true)
	body:SetScript("OnMouseWheel", wheel)
	bar:SetScript("OnShow", function(self)
		local width = self:GetWidth()
		if width and width > 40 then
			self.body:SetWidth(width)
		end
	end)
	return bar
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
	bar.body:SetHeight(math.max(40, -bar.cursor + 12))
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

function LockRemindersSettingsEdit(parent, anchor, field, fallback, width, onApply)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width or 140, 22)
	box:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(24)
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
		if text == "" then
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
	local speed = LockRemindersSettingsCard(bar, 50, "Interface\\Icons\\Ability_Rogue_Sprint", "Speed", "You / target")
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

	LockRemindersSettingsHead(bar, "Alerts")
	local health = LockRemindersSettingsCard(bar, 136, "Interface\\Icons\\INV_Potion_54", "Low health", "You")
	bar.healthToggle = toggle(health, "healthAlert", 176, -14)
	local healthBelow = LockRemindersSettingsCaption(health, bar.healthToggle, "Below", 12)
	local healthPlus
	healthPlus, bar.healthText = LockRemindersSettingsStepper(health, healthBelow, 8, function()
		return db.healthPct or 35
	end, function(value)
		db.healthPct = value
		LockRemindersRefreshMisc()
	end, 5, 90, 5)
	local healthTest = LockRemindersSettingsButton(health, healthPlus, "Test", 12, function()
		LockRemindersPreviewVital("health")
	end)
	local healthTextLabel = LockRemindersSettingsCaption(health, health, "Text", 0)
	healthTextLabel:ClearAllPoints()
	healthTextLabel:SetPoint("TOPLEFT", 176, -50)
	bar.healthLabelBox = LockRemindersSettingsEdit(health, healthTextLabel, "healthLabel", "LOW HEALTH", 160, LockRemindersApplyVitalLook)
	bar.refreshHealth = LockRemindersMakeSoundRow(health, -78, function()
		return db and db.healthSound or "pulse"
	end, function(id)
		db.healthSound = id
	end)

	local mana = LockRemindersSettingsCard(bar, 136, "Interface\\Icons\\INV_Potion_76", "Low mana", "You")
	bar.manaToggle = toggle(mana, "manaAlert", 176, -14)
	local manaBelow = LockRemindersSettingsCaption(mana, bar.manaToggle, "Below", 12)
	local manaPlus
	manaPlus, bar.manaText = LockRemindersSettingsStepper(mana, manaBelow, 8, function()
		return db.manaPct or 25
	end, function(value)
		db.manaPct = value
		LockRemindersRefreshMisc()
	end, 5, 90, 5)
	local manaTest = LockRemindersSettingsButton(mana, manaPlus, "Test", 12, function()
		LockRemindersPreviewVital("mana")
	end)
	local manaTextLabel = LockRemindersSettingsCaption(mana, mana, "Text", 0)
	manaTextLabel:ClearAllPoints()
	manaTextLabel:SetPoint("TOPLEFT", 176, -50)
	bar.manaLabelBox = LockRemindersSettingsEdit(mana, manaTextLabel, "manaLabel", "LOW MANA", 160, LockRemindersApplyVitalLook)
	bar.refreshMana = LockRemindersMakeSoundRow(mana, -78, function()
		return db and db.manaSound or "drip"
	end, function(id)
		db.manaSound = id
	end)

	LockRemindersSettingsHead(bar, "Look")
	local vital = LockRemindersSettingsCard(bar, 84, "Interface\\Icons\\INV_Misc_Note_01", "Alert text", "Both lines")
	local vitalSizeLabel = vital:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vitalSizeLabel:SetPoint("TOPLEFT", 176, -14)
	vitalSizeLabel:SetText("Size")
	vitalSizeLabel:SetTextColor(0.9, 0.84, 1)
	local vitalPlus
	vitalPlus, bar.vitalSize = LockRemindersSettingsStepper(vital, vitalSizeLabel, 8, function()
		return db.vitalSize or 32
	end, function(value)
		db.vitalSize = value
		LockRemindersApplyVitalLook()
		LockRemindersRefreshMisc()
	end, 16, 64, 2)
	local holdLabel = LockRemindersSettingsCaption(vital, vitalPlus, "Seconds", 12)
	local holdPlus
	holdPlus, bar.holdText = LockRemindersSettingsStepper(vital, holdLabel, 8, function()
		return LockRemindersVitalHold()
	end, function(value)
		db.vitalHold = value
		LockRemindersRefreshMisc()
	end, 1, 8, 0.5)
	bar.vitalMove = LockRemindersSettingsButton(vital, holdPlus, "Move", 12, function()
		LockRemindersSetVitalMove(not LockRemindersMisc.vitalMoving)
		LockRemindersRefreshMisc()
	end)
	local effectLabel = vital:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	effectLabel:SetPoint("TOPLEFT", 176, -50)
	effectLabel:SetText("Effect")
	effectLabel:SetTextColor(0.9, 0.84, 1)
	local effectChoices = {
		{ "None", "none" },
		{ "Pulse", "pulse" },
		{ "Shake", "shake" },
		{ "Bounce", "bounce" },
		{ "Flash", "flash" },
		{ "Pop", "pop" },
	}
	bar.effectButtons = {}
	for index = 1, #effectChoices do
		local button = CreateFrame("Button", nil, vital, "BackdropTemplate")
		button:SetSize(64, 22)
		button:SetPoint("LEFT", effectLabel, "RIGHT", 8 + (index - 1) * 68, 0)
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button.label:SetText(effectChoices[index][1])
		button.choiceId = effectChoices[index][2]
		button:SetScript("OnClick", function(self)
			db.vitalStyle = self.choiceId
			LockRemindersApplyVitalFace()
			if not LockRemindersMisc.vitalMoving then
				LockRemindersMisc.previewUntil = GetTime() + math.max(LockRemindersVitalHold(), 2)
				LockRemindersSyncVital(true, true, nil, true)
			end
			LockRemindersRefreshMisc()
		end)
		button:SetScript("OnEnter", function(self)
			if not self.picked then
				self:SetBackdropColor(0.24, 0.16, 0.34, 1)
			end
		end)
		button:SetScript("OnLeave", function(self)
			if self.picked then
				self:SetBackdropColor(0.32, 0.22, 0.08, 1)
			else
				self:SetBackdropColor(0.14, 0.1, 0.2, 1)
			end
		end)
		bar.effectButtons[index] = button
	end
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
	LockRemindersMisc.speed = speed
	LockRemindersApplySpeedLook()
	LockRemindersApplyNamedPoint(speed, "speedPoint", { "CENTER", "CENTER", 0, -160 })

	local vital = CreateFrame("Frame", "LockRemindersVital", UIParent, "BackdropTemplate")
	vital:SetFrameStrata("HIGH")
	vital:SetClampedToScreen(true)
	vital:SetMovable(true)
	vital:EnableMouse(true)
	vital:RegisterForDrag("LeftButton")
	vital:SetScript("OnDragStart", function(self)
		if LockRemindersMisc.vitalMoving then
			self:StartMoving()
		end
	end)
	vital:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		LockRemindersSaveNamedPoint(self, "vitalPoint")
	end)
	vital:SetBackdrop(BACKDROP)
	vital:SetBackdropColor(0, 0, 0, 0)
	vital:SetBackdropBorderColor(0, 0, 0, 0)
	vital.ornament = vital:CreateTexture(nil, "ARTWORK")
	vital.ornament:SetPoint("CENTER")
	vital.ornament:Hide()
	vital.health = vital:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	vital.health:SetJustifyH("CENTER")
	vital.health:SetText("LOW HEALTH")
	vital.health:SetTextColor(1, 0.22, 0.18)
	vital.health:SetShadowColor(0, 0, 0, 1)
	vital.health:SetShadowOffset(2, -2)
	vital.mana = vital:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	vital.mana:SetJustifyH("CENTER")
	vital.mana:SetText("LOW MANA")
	vital.mana:SetTextColor(0.45, 0.72, 1)
	vital.mana:SetShadowColor(0, 0, 0, 1)
	vital.mana:SetShadowOffset(2, -2)
	vital:SetScript("OnUpdate", LockRemindersStepVitalMotion)
	vital.hint = vital:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	vital.hint:SetPoint("TOP", vital, "BOTTOM", 0, -2)
	vital.hint:SetText("Drag")
	vital.hint:SetTextColor(1, 0.7, 0.65)
	vital.hint:Hide()
	vital:EnableMouse(false)
	LockRemindersMisc.vital = vital
	LockRemindersAttachPop(vital, function()
		if LockRemindersMisc.vitalMoving then
			return true
		end
		if LockRemindersMisc.previewUntil and GetTime() < LockRemindersMisc.previewUntil then
			return true
		end
		return LockRemindersMisc.healthDown or LockRemindersMisc.manaDown
	end)
	LockRemindersApplyVitalLook()
	LockRemindersApplyNamedPoint(vital, "vitalPoint", { "CENTER", "CENTER", 0, 60 })
	vital:Hide()
	LockRemindersUpdateSpeed()
end

function LockRemindersSecret(value)
	if value == nil or not issecretvalue then
		return false
	end
	local ok, secret = pcall(issecretvalue, value)
	return not ok or secret and true or false
end

function LockRemindersIsInterrupt(spellID, spellName)
	spellID = tonumber(spellID)
	if spellID == 19244 or spellID == 19647 or spellID == 19648 or spellID == 19650 or spellID == 20433 or spellID == 20434 or spellID == 24259 or spellID == 119910 or spellID == 132409 then
		return true
	end
	local wanted = Normalize(spellName or "")
	return wanted == "spell lock"
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
	if wanted:find("^curse of ", 1, true) or wanted:find("^maldicion de ", 1, true) or wanted:find("^corruption", 1, true) or wanted:find("^corrupcion", 1, true) then
		return true
	end
	if wanted == "immolate" or wanted == "inmolar" or wanted == "unstable affliction" or wanted == "afliccion inestable" then
		return true
	end
	spellID = tonumber(spellID)
	return spellID == 5782 or spellID == 6213 or spellID == 6215 or spellID == 5484 or spellID == 17928 or spellID == 710 or spellID == 18647 or spellID == 6358
end

function LockRemindersSpellTravels(spellID, spellName)
	local wanted = Normalize(spellName or "")
	if wanted == "" and spellID then
		wanted = Normalize(SpellName(spellID) or "")
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
	return spellID == 348 or spellID == 707 or spellID == 1094 or spellID == 2941
		or spellID == 11665 or spellID == 11667 or spellID == 11668 or spellID == 25309
		or spellID == 27215 or spellID == 47810 or spellID == 47811
		or spellID == 27243 or spellID == 47835 or spellID == 47836
end

function LockRemindersNoteCast(unit, first, second, third)
	if unit ~= "player" and unit ~= "pet" then
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
	elseif spellID then
		spellName = SpellName(spellID)
	end
	if not spellID and (type(spellName) ~= "string" or spellName == "") then
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
	local aim = unit == "pet" and "pettarget" or "target"
	local target
	if UnitGUID and UnitExists and UnitExists(aim) then
		local ok, guid = pcall(UnitGUID, aim)
		if ok and type(guid) == "string" and guid ~= "" and not LockRemindersSecret(guid) then
			target = guid
		end
	end
	kept[#kept + 1] = {
		spellID = spellID,
		name = spellName,
		kind = unit == "pet" and "pet" or "player",
		at = now,
		target = target,
		interrupt = LockRemindersIsInterrupt(spellID, spellName) or nil,
		aura = LockRemindersIsAuraSpell(spellID, spellName) or nil,
		travel = LockRemindersSpellTravels(spellID, spellName) or nil,
		aoe = LockRemindersIsAoeSpell(spellID, spellName) or nil,
	}
	LockRemindersMiss.casts = kept
	if unit == "player" and target and LockRemindersBanishMatch(spellID, spellName) then
		LockRemindersWarlock.ends = LockRemindersWarlock.ends or {}
		LockRemindersWarlock.guess = LockRemindersWarlock.guess or {}
		LockRemindersWarlock.ends[target] = now + (spellID == 710 and 20 or 30)
		LockRemindersWarlock.guess[target] = true
		if UnitName then
			local ok, name = pcall(UnitName, aim)
			if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
				LockRemindersWarlock.names = LockRemindersWarlock.names or {}
				LockRemindersWarlock.names[target] = name
			end
		end
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
	local ok, value = pcall(curve.Evaluate, curve, amount)
	if ok and value ~= nil and not LockRemindersSecret(value) then
		value = tonumber(value)
		if value then
			return value >= 0.5
		end
	end
	if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
		local proved, bit = pcall(function()
			return C_CurveUtil.EvaluateColorValueFromBoolean(amount == 0, 1, 0)
		end)
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

function LockRemindersTargetHasDot(unit)
	if not unit or not UnitExists or not UnitExists(unit) then
		return false
	end
	if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, index)
			if not ok or aura == nil or aura == false or LockRemindersSecret(aura) then
				break
			end
			if LockRemindersDebuffIsDot(aura.name) then
				return true
			end
		end
	end
	if UnitDebuff then
		for index = 1, 40 do
			local ok, name = pcall(UnitDebuff, unit, index)
			if not ok or name == nil or name == false or name == "" or LockRemindersSecret(name) then
				break
			end
			if LockRemindersDebuffIsDot(name) then
				return true
			end
		end
	end
	return false
end

function LockRemindersNewestDirectCast(unit)
	local guid = LockRemindersMissGuid(unit)
	local now = GetTime()
	local casts = LockRemindersMiss.casts or {}
	for index = #casts, 1, -1 do
		local cast = casts[index]
		local aimed = cast.aoe or not cast.target or not guid or cast.target == guid
		if not cast.used and not cast.landed and not cast.interrupt and (not cast.aura or cast.travel) and aimed and now - (cast.at or 0) <= 3.5 and LockRemindersMissSpellSaved(cast.spellID, cast.name) then
			return cast
		end
	end
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
	local casts = LockRemindersMiss.casts or {}
	for index = #casts, 1, -1 do
		local cast = casts[index]
		if now - (cast.at or 0) > 1 then
			return
		end
		local aimed = cast.aoe or not cast.target or not guid or cast.target == guid
		if cast.aura and not cast.landed and aimed then
			local landed = false
			if type(added) == "table" then
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

function LockRemindersTakeMissCast(unit, spellSchool)
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
		elseif cast.aura and not cast.travel then
			limit = 0.8
		end
		local instant = (cast.aura or cast.interrupt) and not cast.travel
		local swing = not spellSchool and instant and age > 0.35
		if not swing and not cast.used and not cast.landed and aimed and age <= limit and LockRemindersMissSpellSaved(cast.spellID, cast.name) and LockRemindersMissUnit(unit, cast.kind) then
			if LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, cast.at, true) then
				cast.landed = true
			else
				cast.used = true
				if cast.target and LockRemindersBanishMatch(cast.spellID, cast.name) then
					if LockRemindersWarlock.ends then
						LockRemindersWarlock.ends[cast.target] = nil
					end
					if LockRemindersWarlock.guess then
						LockRemindersWarlock.guess[cast.target] = nil
					end
				end
				return cast
			end
		end
	end
end

function LockRemindersNoteInterrupted(unit)
	if type(unit) ~= "string" or unit == "" or unit == "player" or unit == "pet" or LockRemindersSecret(unit) then
		return
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

function LockRemindersHandleUnitCombat(unit, action, flag, amount, school)
	if not db or LockRemindersSecret(unit) or LockRemindersSecret(action) then
		return
	end
	if not LockRemindersMissUnit(unit) then
		return
	end
	if LockRemindersSecret(flag) then
		flag = nil
	end
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
	end
	if LockRemindersSecret(school) then
		school = nil
	end
	action = type(action) == "string" and action:upper() or nil
	flag = type(flag) == "string" and flag:upper() or nil
	school = tonumber(school)
	if not amountSecret then
		amount = tonumber(amount)
	end
	if not LockRemindersMissFlags then
		LockRemindersMissFlags = {
			ABSORB = true, BLOCK = true, IMMUNE = true, DODGE = true,
			PARRY = true, DEFLECT = true, EVADE = true, REFLECT = true,
		}
	end
	-- A partial resist still deals damage. Only a plain zero is a full miss,
	-- and that zero often arrives with an empty tag. Dodge, parry, absorb and
	-- block are not a failed spell. Immune is its own alert and covers every
	-- spell. A secret zero is read with a curve; a secret positive number is
	-- a hit. A damage tick while a DoT is already up does not belong to a
	-- bolt still in the air.
	local immuneEvent = action == "IMMUNE" or flag == "IMMUNE"
	if immuneEvent and school ~= 1 and (action ~= "WOUND" or amount == 0 or amount == nil) then
		LockRemindersShowImmune(unit)
		return
	end
	if action == "WOUND" then
		local ignored = flag and LockRemindersMissFlags[flag]
		local fullMiss = amount == 0 and not ignored
		if not fullMiss and (flag == "MISS" or flag == "MISSED" or flag == "RESIST") and amount == nil and not ignored then
			fullMiss = true
		end
		if not fullMiss then
			local connected = type(amount) == "number" and amount ~= 0 and school ~= 1 and not ignored
			if connected then
				local direct = LockRemindersNewestDirectCast(unit)
				local young = direct and (GetTime() - (direct.at or 0)) <= 0.4
				local dot = LockRemindersTargetHasDot(unit)
				if not dot or young or flag == "RESIST" then
					local now = GetTime()
					LockRemindersMiss.hitAt = now
					LockRemindersMiss.hitUnit = unit
					LockRemindersMiss.hitGuid = LockRemindersMissGuid(unit)
					local held = LockRemindersMiss.held
					if held and not held.interrupt and not held.aura and LockRemindersMissSame(held.unit, unit, held.guid, LockRemindersMiss.hitGuid) and math.abs(now - held.at) <= 0.08 then
						held.cancel = true
					end
					LockRemindersScheduleHitRetire(unit, direct)
				end
			end
			return
		end
		action = flag == "RESIST" and "RESIST" or "MISS"
	end
	local missType
	if action == "MISS" or action == "MISSED" then
		missType = "MISS"
	elseif action == "RESIST" or action == "RESISTED" then
		missType = "RESIST"
	end
	if not missType then
		return
	end
	local spellSchool = school ~= nil and school ~= 1
	local cast = LockRemindersTakeMissCast(unit, spellSchool)
	if not cast then
		return
	end
	local now = GetTime()
	local guid = LockRemindersMissGuid(unit)
	LockRemindersMiss.missAt = now
	LockRemindersMiss.missGuid = guid
	if not cast.interrupt and not cast.aura and LockRemindersMiss.hitAt and LockRemindersMissSame(LockRemindersMiss.hitUnit, unit, LockRemindersMiss.hitGuid, guid) and math.abs(now - LockRemindersMiss.hitAt) <= 0.08 then
		cast.used = nil
		cast.landed = true
		return
	end
	if cast.landed then
		return
	end
	local freshOnly = (now - (cast.at or now)) <= 0.45
	LockRemindersMiss.held = { unit = unit, guid = guid, at = now, interrupt = cast.interrupt, aura = cast.aura, freshOnly = freshOnly, cast = cast }
	local held = LockRemindersMiss.held
	if C_Timer and C_Timer.After then
		C_Timer.After(0.3, function()
			if held.cancel or cast.landed then
				return
			end
			if not cast.interrupt and not cast.aura and LockRemindersMiss.hitAt and LockRemindersMissSame(LockRemindersMiss.hitUnit, unit, LockRemindersMiss.hitGuid, guid) and math.abs(LockRemindersMiss.hitAt - held.at) <= 0.08 then
				return
			end
			if LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, cast.at, true) then
				return
			end
			LockRemindersShowMissCast(cast, unit, missType)
		end)
		return
	end
	if LockRemindersUnitHasSpell(unit, cast.spellID, cast.name, cast.at, true) then
		return
	end
	LockRemindersShowMissCast(cast, unit, missType)
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
		elseif cast.aura then
			limit = 0.8
		end
		if not cast.used and not cast.landed and aimed and age <= limit and LockRemindersMissUnit(unit, cast.kind) then
			cast.used = true
			if cast.target and LockRemindersBanishMatch(cast.spellID, cast.name) then
				if LockRemindersWarlock.ends then
					LockRemindersWarlock.ends[cast.target] = nil
				end
				if LockRemindersWarlock.guess then
					LockRemindersWarlock.guess[cast.target] = nil
				end
			end
			return cast
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
		local ok, name = pcall(UnitName, unit)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
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

function LockRemindersCooldownLeft(spellID)
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, first, second = pcall(C_Spell.GetSpellCooldown, spellID)
		if ok and type(first) == "table" then
			start = tonumber(first.startTime) or tonumber(first.start)
			duration = tonumber(first.duration)
		elseif ok then
			start = tonumber(first)
			duration = tonumber(second)
		end
	end
	if (not duration or duration <= 5) and GetSpellCooldown then
		local ok, first, second = pcall(GetSpellCooldown, spellID)
		if ok then
			start = tonumber(first)
			duration = tonumber(second)
		end
	end
	if start and duration and duration > 5 and start > 0 then
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

function LockRemindersReadBuff(unit, index)
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, unit, index)
		if ok and type(aura) == "table" and not LockRemindersSecret(aura) then
			local spellID = aura.spellId or aura.spellID
			local name = aura.name
			local duration = aura.duration
			local expires = aura.expirationTime
			local icon = aura.icon
			local caster = aura.sourceUnit
			local casterName = aura.sourceName
			if LockRemindersSecret(spellID) then
				spellID = nil
			end
			if LockRemindersSecret(name) then
				name = nil
			end
			if LockRemindersSecret(duration) then
				duration = nil
			end
			if LockRemindersSecret(expires) then
				expires = nil
			end
			if LockRemindersSecret(icon) then
				icon = nil
			end
			if LockRemindersSecret(caster) then
				caster = nil
			end
			if LockRemindersSecret(casterName) or type(casterName) ~= "string" or casterName == "" then
				casterName = nil
			end
			if not name and not tonumber(spellID) then
				return nil
			end
			return {
				spellID = tonumber(spellID),
				name = type(name) == "string" and name or nil,
				icon = icon,
				duration = tonumber(duration),
				expires = tonumber(expires),
				caster = type(caster) == "string" and caster or nil,
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
	if LockRemindersSecret(duration) then
		duration = nil
	end
	if LockRemindersSecret(expires) then
		expires = nil
	end
	if LockRemindersSecret(icon) then
		icon = nil
	end
	if LockRemindersSecret(caster) then
		caster = nil
	end
	return {
		name = name,
		icon = icon,
		duration = tonumber(duration),
		expires = tonumber(expires),
		caster = type(caster) == "string" and caster or nil,
	}
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
	local useSpell = spellID and LockRemindersSoulAura[spellID]
	if not useSpell and type(spellName) == "string" then
		local lowered = Normalize(spellName)
		useSpell = LockRemindersIsSoulName(spellName) and not lowered:find("create", 1, true) and not lowered:find("crear", 1, true)
	end
	if not useSpell then
		return
	end
	local aim = unit == "player" and "target" or (unit .. "target")
	if not UnitExists or not UnitExists(aim) then
		return
	end
	local targetKey = LockRemindersUnitKey(aim)
	if not targetKey then
		return
	end
	local casterClass
	if UnitClass then
		local ok, _, classFile = pcall(UnitClass, unit)
		if ok and type(classFile) == "string" and not LockRemindersSecret(classFile) then
			casterClass = classFile
		end
	end
	LockRemindersSoul.applied = LockRemindersSoul.applied or {}
	LockRemindersSoul.applied[targetKey] = {
		name = LockRemindersUnitLabel(unit, db and db.soulFullName ~= false),
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
	pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", unpack(units))
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
				if buff.expires and buff.expires > 0 then
					ends = buff.expires
					LockRemindersSoul.timers[info.key] = ends
				elseif LockRemindersSoul.timers[info.key] and LockRemindersSoul.timers[info.key] > GetTime() then
					ends = LockRemindersSoul.timers[info.key]
				end
				if ends then
					left = ends - GetTime()
					duration = buff.duration
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
			if UnitIsUnit and UnitIsUnit(info.unit, "player") then
				left, duration = LockRemindersPlayerSoulLeft()
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

function LockRemindersLayoutSoulRow(row)
	row:SetHeight(40)
	row.icon:SetSize(28, 28)
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
	local left = tonumber(info.ends) and (info.ends - GetTime()) or tonumber(info.left)
	if left and left < 0 then
		left = 0
	end
	local duration = tonumber(info.duration) or 0
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
	frame:SetSize(math.max(size + 24, math.floor(size * 2.4)), size + 30)
	frame.icon:SetSize(size - 4, size - 4)
	frame.glow:SetSize(size * 1.7, size * 1.7)
	local font = frame.label:GetFont()
	if type(font) ~= "string" or font == "" then
		font = "Fonts\\FRIZQT__.TTF"
	end
	frame.label:SetFont(font, math.max(10, math.floor(size * 0.28)), "OUTLINE")
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
		if not LockRemindersSoul.alertPlayed then
			LockRemindersSoul.alertPlayed = true
			LockRemindersPlaySoundId(db and db.soulSound or "chime")
		end
	end
	if frame.glow.ag and not frame.glow.ag:IsPlaying() then
		frame.glow.ag:Play()
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
	local y = -26
	local rowIndex = 0
	local function place(list, kind, title)
		if #list == 0 then
			title:Hide()
			return
		end
		title:Show()
		title:ClearAllPoints()
		title:SetPoint("TOPLEFT", 10, y)
		y = y - 16
		for index = 1, #list do
			rowIndex = rowIndex + 1
			local row = LockRemindersSoulRow(rowIndex)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 8, y)
			LockRemindersPaintSoulRow(row, list[index], kind)
			y = y - row:GetHeight() - 4
		end
	end
	place(active, "active", frame.activeTitle)
	place(unused, "ready", frame.readyTitle)
	for index = rowIndex + 1, #LockRemindersSoul.rows do
		LockRemindersSoul.rows[index]:Hide()
	end
	local widest = 80
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
	end
	local width = math.max(260, math.min(460, widest + 130))
	frame:SetWidth(width)
	for index = 1, rowIndex do
		local row = LockRemindersSoul.rows[index]
		row:SetWidth(width - 16)
		local barWidth = math.max(80, width - 16 - 48)
		row.track:SetWidth(barWidth)
		row.name:SetWidth(math.max(widest + 4, 60))
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
		if LockRemindersWarlock.shards then
			LockRemindersWarlock.shards:Hide()
		end
		return
	end
	LockRemindersUpdateClassAlerts()
	LockRemindersUpdateSoulTracker()
	local frame = LockRemindersSoul.alert
	if not frame or LockRemindersSoul.moving then
		return
	end
	if LockRemindersSoul.previewUntil and GetTime() < LockRemindersSoul.previewUntil then
		return
	end
	local show = db.soulAlert ~= false and ScopeActive(db.soulScope or { always = true }) and not LockRemindersHasSoulstone() and not Blocked()
	LockRemindersSoul.missing = show
	if show then
		LockRemindersShowSoulAlert(false)
	else
		LockRemindersHideSoulAlert()
	end
end

function LockRemindersStartSoul()
	if LockRemindersSoul.ticker or not C_Timer or not LockRemindersIsWarlock() then
		return
	end
	LockRemindersSoul.ticker = C_Timer.NewTicker(0.25, function()
		pcall(LockRemindersUpdateSoul)
	end)
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
	LockRemindersPaintToggle(bar.alertToggle, db.soulAlert ~= false)
	LockRemindersPaintToggle(bar.trackToggle, db.soulTrack ~= false)
	LockRemindersPaintToggle(bar.banishToggle, db.banishAlert ~= false)
	LockRemindersPaintToggle(bar.shardToggle, db.shardShow ~= false)
	if bar.banishChecks then
		bar.banishChecks.refresh()
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
	if bar.shardSize then
		bar.shardSize:SetText(tostring(tonumber(db.shardSize) or 40))
	end
	if bar.banishLabel and bar.banishLabel.SetText and not bar.banishLabel:HasFocus() then
		bar.banishLabel.quiet = true
		bar.banishLabel:SetText(LockRemindersClassLabel("banishLabel", "BANISH"))
		bar.banishLabel.quiet = nil
	end
	if bar.shardLabel and bar.shardLabel.SetText and not bar.shardLabel:HasFocus() then
		bar.shardLabel.quiet = true
		bar.shardLabel:SetText(LockRemindersClassLabel("shardLabel", "NO SHARDS"))
		bar.shardLabel.quiet = nil
	end
	if bar.banishMove and bar.banishMove.label then
		bar.banishMove.label:SetText(LockRemindersWarlock.banishMoving and "Done" or "Move")
	end
	if bar.shardMove and bar.shardMove.label then
		bar.shardMove.label:SetText(LockRemindersWarlock.shardMoving and "Done" or "Move")
	end
	if bar.refreshSound then
		bar.refreshSound()
	end
end

function LockRemindersMakeScopeChecks(parent, anchor, field)
	local specs = {
		{ "raid", "Raid" },
		{ "party", "Party" },
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
			local always, party, raid = ScopeFlags(db[field])
			local scope = { always = always, party = party, raid = raid }
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
		local always, party, raid = ScopeFlags(db and db[field])
		boxes.raid:SetChecked(raid)
		boxes.party:SetChecked(party)
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
		return box
	end

	local function step(parent, anchor, read, write, low, high, stepSize)
		return LockRemindersSettingsStepper(parent, anchor, 8, read, write, low, high, stepSize)
	end

	LockRemindersSettingsHead(bar, "Soulstone")
	local missing = LockRemindersSettingsCard(bar, 112, LockRemindersSoulIcon(), "Missing stone", "No stone")
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
	bar.refreshSound = LockRemindersMakeSoundRow(missing, -56, function()
		return db and db.soulSound or "chime"
	end, function(id)
		db.soulSound = id
	end)

	LockRemindersSettingsHead(bar, "Tracker")
	local track = LockRemindersSettingsCard(bar, 82, "Interface\\Icons\\INV_Misc_GroupNeedMore", "On screen", "Active stones")
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
	bar.fullName = checkBox(track, 176, -50, "Full name", "soulFullName")
	bar.trackFrame = checkBox(track, 280, -50, "Frame", "soulTrackFrame", LockRemindersApplySoulTrackLook)

	LockRemindersSettingsHead(bar, "Banish")
	local banish = LockRemindersSettingsCard(bar, 82, "Interface\\Icons\\Spell_Shadow_Cripple", "Banish", "Countdown")
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
	end)
	bar.banishMove = LockRemindersSettingsButton(banish, bar.banishLabel, "Move", 10, function()
		LockRemindersCreateClassAlerts()
		LockRemindersWarlock.banishMoving = not LockRemindersWarlock.banishMoving
		if LockRemindersWarlock.banishMoving then
			LockRemindersWarlock.banishPreview = nil
		end
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)
	bar.banishTest = LockRemindersSettingsButton(banish, bar.banishMove, "Test", 8, function()
		LockRemindersCreateClassAlerts()
		LockRemindersWarlock.banishMoving = false
		LockRemindersWarlock.banishPreview = GetTime() + math.max(2, tonumber(db.banishWarn) or 5)
		LockRemindersUpdateClassAlerts()
		LockRemindersRefreshSoul()
	end)

	LockRemindersSettingsHead(bar, "Soul shards")
	local shards = LockRemindersSettingsCard(bar, 82, "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", "Soul shards", "In your bags")
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
	end)
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
	LockRemindersSettingsFinish(bar)
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

function LockRemindersReadBanish(unit)
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
		if not LockRemindersBanishMatch(id, name) then
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

function LockRemindersSoonestBanish()
	local bestLeft, bestEnds, bestName, bestGuid
	local seen = {}
	local function rememberName(guid, unit)
		if not guid or not UnitName then
			return
		end
		local ok, name = pcall(UnitName, unit)
		if ok and type(name) == "string" and name ~= "" and not LockRemindersSecret(name) then
			LockRemindersWarlock.names = LockRemindersWarlock.names or {}
			LockRemindersWarlock.names[guid] = name
		end
	end
	local function scan(unit)
		local left, ends = LockRemindersReadBanish(unit)
		local guid = LockRemindersMissGuid(unit)
		if left == false then
			if guid and LockRemindersWarlock.ends then
				LockRemindersWarlock.ends[guid] = nil
			end
			if guid and LockRemindersWarlock.guess then
				LockRemindersWarlock.guess[guid] = nil
			end
			return
		end
		if guid then
			seen[guid] = true
		end
		if type(left) == "number" and ends then
			if guid then
				LockRemindersWarlock.ends = LockRemindersWarlock.ends or {}
				LockRemindersWarlock.ends[guid] = ends
				if LockRemindersWarlock.guess then
					LockRemindersWarlock.guess[guid] = nil
				end
				rememberName(guid, unit)
			end
		elseif guid and LockRemindersWarlock.ends and LockRemindersWarlock.ends[guid] then
			ends = LockRemindersWarlock.ends[guid]
			left = ends - GetTime()
			rememberName(guid, unit)
		else
			return
		end
		if left <= 0 then
			if guid and LockRemindersWarlock.ends then
				LockRemindersWarlock.ends[guid] = nil
			end
			return
		end
		if not bestLeft or left < bestLeft then
			bestLeft, bestEnds, bestGuid = left, ends, guid
			bestName = LockRemindersWarlock.names and guid and LockRemindersWarlock.names[guid] or nil
		end
	end
	scan("target")
	scan("focus")
	for index = 1, 30 do
		scan("nameplate" .. index)
	end
	local endsMap = LockRemindersWarlock.ends
	if endsMap then
		for guid, expires in pairs(endsMap) do
			local guessed = LockRemindersWarlock.guess and LockRemindersWarlock.guess[guid]
			if guessed and not seen[guid] then
				endsMap[guid] = nil
				LockRemindersWarlock.guess[guid] = nil
			else
				local left = (tonumber(expires) or 0) - GetTime()
				if left <= 0 then
					endsMap[guid] = nil
				elseif not bestLeft or left < bestLeft then
					bestLeft, bestEnds, bestGuid = left, expires, guid
					bestName = LockRemindersWarlock.names and LockRemindersWarlock.names[guid] or nil
				end
			end
		end
	end
	return bestLeft, bestEnds, bestName, bestGuid
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
		return fallback
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
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

function LockRemindersApplyClassLook()
	local banish = LockRemindersWarlock.banish
	local shards = LockRemindersWarlock.shards
	if banish and banish.icon then
		local size = tonumber(db and db.banishSize) or 48
		if size < 32 then
			size = 32
		elseif size > 96 then
			size = 96
		end
		if db then
			db.banishSize = size
		end
		banish.icon:SetSize(size, size)
		banish.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(12, math.floor(size * 0.42)), "OUTLINE")
		banish.text:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, math.floor(size * 0.28)), "OUTLINE")
		banish.sub:SetFont("Fonts\\FRIZQT__.TTF", math.max(9, math.floor(size * 0.22)), "OUTLINE")
		banish:SetSize(math.max(size + 20, 88), size + math.floor(size * 0.72))
		local icon = SpellIcon(18647)
		if not icon or icon == 134400 then
			icon = SpellIcon(710)
		end
		banish.icon:SetTexture(icon or "Interface\\Icons\\Spell_Shadow_Cripple")
	end
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
		shards.icon:SetSize(size, size)
		shards.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(12, math.floor(size * 0.46)), "OUTLINE")
		shards.text:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, math.floor(size * 0.28)), "OUTLINE")
		shards:SetSize(math.max(size + 36, 88), size + math.floor(size * 0.5))
		shards.icon:SetTexture(ItemIcon(6265) or "Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
	end
end

function LockRemindersUpdateClassAlerts()
	local banish = LockRemindersWarlock.banish
	local shards = LockRemindersWarlock.shards
	if not banish or not shards or not db then
		return
	end
	local now = GetTime()
	banish:EnableMouse(LockRemindersWarlock.banishMoving and true or false)
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
		edge(banish, LockRemindersWarlock.banishMoving)
		edge(shards, LockRemindersWarlock.shardMoving)
	else
		banish:SetBackdropColor(0, 0, 0, 0)
		banish:SetBackdropBorderColor(0, 0, 0, 0)
		shards:SetBackdropColor(0, 0, 0, 0)
		shards:SetBackdropBorderColor(0, 0, 0, 0)
	end
	local function paintBanish(seconds, sub)
		LockRemindersApplyClassLook()
		banish.count:SetText(tostring(math.max(1, math.ceil(seconds))))
		banish.text:SetText(LockRemindersClassLabel("banishLabel", "BANISH"))
		banish.sub:SetText(sub or "")
		banish:Show()
	end
	local function paintShards(count, zero)
		LockRemindersApplyClassLook()
		shards.count:SetText(tostring(count))
		if zero then
			shards.count:SetTextColor(1, 0.35, 0.25)
			shards.text:SetText(LockRemindersClassLabel("shardLabel", "NO SHARDS"))
			shards.text:Show()
		else
			shards.count:SetTextColor(1, 0.97, 0.86)
			shards.text:SetText("")
			shards.text:Hide()
		end
		shards:Show()
	end
	if LockRemindersWarlock.banishMoving then
		paintBanish(5, "Drag")
	elseif LockRemindersWarlock.banishPreview and now < LockRemindersWarlock.banishPreview then
		paintBanish(LockRemindersWarlock.banishPreview - now, "Target")
	elseif not LockRemindersClassShown("banishAlert", "banishScope") then
		banish:Hide()
	else
		local left, ends, name, guid = LockRemindersSoonestBanish()
		local warn = tonumber(db.banishWarn) or 5
		if left and left <= warn then
			paintBanish(left, name or "")
			local key = tostring(guid or name or "banish") .. ":" .. tostring(math.floor(ends or 0))
			if key ~= LockRemindersWarlock.banishKey then
				LockRemindersWarlock.banishKey = key
				LockRemindersPlaySoundId(db.soulSound or "chime")
			end
		else
			banish:Hide()
			if not left then
				LockRemindersWarlock.banishKey = nil
			end
		end
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
	else
		local crossed = LockRemindersWarlock.lastShards and LockRemindersWarlock.lastShards > 0 and count == 0
		LockRemindersWarlock.lastShards = count
		if crossed and LockRemindersClassShown("shardShow", "shardScope") then
			LockRemindersPlaySoundId(db.soulSound or "knock")
		end
	end
	if count == nil or not LockRemindersClassShown("shardShow", "shardScope") then
		shards:Hide()
		return
	end
	paintShards(count, count == 0)
end

function LockRemindersCreateClassAlerts()
	if LockRemindersWarlock.banish or not LockRemindersIsWarlock() then
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
	local banish = movable("LockRemindersBanish", "banishPoint", "banishMoving")
	banish.icon = banish:CreateTexture(nil, "ARTWORK")
	banish.icon:SetPoint("TOP", 0, 0)
	banish.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	banish.count = banish:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	banish.count:SetPoint("CENTER", banish.icon, "CENTER", 1, 0)
	banish.count:SetTextColor(1, 0.95, 0.75)
	banish.count:SetShadowColor(0, 0, 0, 1)
	banish.count:SetShadowOffset(1, -1)
	banish.text = banish:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	banish.text:SetPoint("TOP", banish.icon, "BOTTOM", 0, -2)
	banish.text:SetTextColor(0.86, 0.72, 1)
	banish.text:SetShadowColor(0, 0, 0, 1)
	banish.text:SetShadowOffset(1, -1)
	banish.sub = banish:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	banish.sub:SetPoint("TOP", banish.text, "BOTTOM", 0, -1)
	banish.sub:SetTextColor(0.9, 0.84, 1)
	LockRemindersWarlock.banish = banish
	local shards = movable("LockRemindersShards", "shardPoint", "shardMoving")
	shards.icon = shards:CreateTexture(nil, "ARTWORK")
	shards.icon:SetPoint("TOP", 0, 0)
	shards.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	shards.count = shards:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	shards.count:SetPoint("CENTER", shards.icon, "CENTER", 1, 0)
	shards.count:SetTextColor(1, 0.97, 0.86)
	shards.count:SetShadowColor(0, 0, 0, 1)
	shards.count:SetShadowOffset(1, -1)
	shards.text = shards:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	shards.text:SetPoint("TOP", shards.icon, "BOTTOM", 0, -2)
	shards.text:SetTextColor(1, 0.45, 0.35)
	shards.text:SetShadowColor(0, 0, 0, 1)
	shards.text:SetShadowOffset(1, -1)
	LockRemindersWarlock.shards = shards
	LockRemindersApplyClassLook()
	LockRemindersApplyNamedPoint(banish, "banishPoint", { "CENTER", "CENTER", 180, 210 })
	LockRemindersApplyNamedPoint(shards, "shardPoint", { "CENTER", "CENTER", -180, -80 })
	banish:Hide()
	shards:Hide()
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
	frame.glow = CreateFrame("Frame", nil, frame)
	frame.glow:SetPoint("CENTER", frame.icon, "CENTER", 0, 0)
	frame.glow.tex = frame.glow:CreateTexture(nil, "OVERLAY")
	frame.glow.tex:SetAllPoints()
	frame.glow.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	frame.glow.tex:SetBlendMode("ADD")
	frame.glow.tex:SetVertexColor(0.72, 0.4, 1)
	local glow = frame.glow:CreateAnimationGroup()
	glow:SetLooping("BOUNCE")
	local alpha = glow:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.25)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.45)
	alpha:SetSmoothing("IN_OUT")
	frame.glow.ag = glow
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
	Paint(tracker, 0.06, 0.05, 0.08, 0.92, 0.45, 0.32, 0.62, 1)
	tracker.title = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tracker.title:SetPoint("TOPLEFT", 10, -8)
	tracker.title:SetText("Soulstone")
	tracker.title:SetTextColor(0.86, 0.72, 1)
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
	foodFrame = CreateFrame("Frame", "LockRemindersFoodAlert", UIParent)
	foodFrame:SetFrameStrata("HIGH")
	foodFrame:SetClampedToScreen(true)
	foodFrame:SetMovable(true)
	foodFrame:EnableMouse(true)
	foodFrame:RegisterForDrag("LeftButton")
	foodFrame:SetScript("OnDragStart", function(self)
		if self.moving then
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
	foodFrame.glow = CreateFrame("Frame", nil, foodFrame)
	foodFrame.glow:SetPoint("CENTER")
	foodFrame.glow.tex = foodFrame.glow:CreateTexture(nil, "OVERLAY")
	foodFrame.glow.tex:SetAllPoints()
	foodFrame.glow.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	foodFrame.glow.tex:SetBlendMode("ADD")
	foodFrame.glow.tex:SetVertexColor(1, 0.82, 0.35)
	local glow = foodFrame.glow:CreateAnimationGroup()
	glow:SetLooping("BOUNCE")
	local alpha = glow:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.2)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.45)
	alpha:SetSmoothing("IN_OUT")
	foodFrame.glow.ag = glow
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
	talentFrame.ornament = talentFrame:CreateTexture(nil, "OVERLAY")
	talentFrame.ornament:SetPoint("CENTER")
	talentFrame.ornament:SetBlendMode("ADD")
	talentFrame.ornament:Hide()
	talentFrame.glow = CreateFrame("Frame", nil, talentFrame)
	talentFrame.glow:SetPoint("CENTER")
	talentFrame.glow.tex = talentFrame.glow:CreateTexture(nil, "OVERLAY")
	talentFrame.glow.tex:SetAllPoints()
	talentFrame.glow.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	talentFrame.glow.tex:SetBlendMode("ADD")
	talentFrame.glow.tex:SetVertexColor(1, 0.82, 0.35)
	local glow = talentFrame.glow:CreateAnimationGroup()
	glow:SetLooping("BOUNCE")
	local alpha = glow:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0.2)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.28)
	alpha:SetSmoothing("IN_OUT")
	talentFrame.glow.ag = glow
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
			talentFrame:Hide()
			talentFrame:SetAlpha(1)
		end
	end)
	talentFrame.fade = fade
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
	panel:SetSize(740, 600)
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
	MakeTab("Powers", "powers", 14, 136)
	MakeTab("Consumables", "food", 158, 136)
	MakeTab("Talents", "talents", 302, 136)
	MakeTab("Spell alerts", "spells", 446, 136)
	MakeTab("Miscellaneous", "misc", 590, 136)
	if LockRemindersIsWarlock() then
		MakeTab("Soulstone", "soul", 732, 130)
	end

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
	raidCheck:SetPoint("TOPLEFT", 112, -148)
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
	raidCheck.labelButton:SetPoint("TOPLEFT", 16, -148)
	raidCheck.labelButton:SetSize(88, 22)
	raidCheck.labelButton.label = raidCheck.labelButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	raidCheck.labelButton.label:SetPoint("LEFT")
	raidCheck.labelButton.label:SetText("When adding")
	raidCheck.labelButton:SetScript("OnClick", function()
		raidCheck:Click()
	end)

	modeHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	modeHint:SetPoint("TOPLEFT", 16, -148)
	modeHint:SetWidth(520)
	modeHint:SetJustifyH("LEFT")
	modeHint:SetTextColor(0.75, 0.7, 0.84)
	modeHint:Hide()

	panel.alertButton = CreateFrame("Button", nil, panel, "BackdropTemplate")
	panel.alertButton:SetSize(140, 22)
	panel.alertButton:SetPoint("TOPRIGHT", -16, -146)
	Paint(panel.alertButton, 0.14, 0.1, 0.2, 1, 0.95, 0.78, 0.35, 1)
	panel.alertButton.label = panel.alertButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.alertButton.label:SetPoint("CENTER")
	panel.alertButton.label:SetText("Configure alert")
	panel.alertButton:SetScript("OnClick", function()
		if activeTab == "powers" or activeTab == "food" or activeTab == "talents" or activeTab == "spells" then
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
	talentBar:SetHeight(470)
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

	panel.spellBar = CreateFrame("Frame", nil, panel)
	panel.spellBar:SetPoint("TOPLEFT", 14, -112)
	panel.spellBar:SetPoint("TOPRIGHT", -16, -112)
	panel.spellBar:SetHeight(132)
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
		ChangeMissHold(-0.4)
	end)
	panel.spellBar.holdText = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.spellBar.holdText:SetPoint("LEFT", missHoldMinus, "RIGHT", 6, 0)
	panel.spellBar.holdText:SetWidth(32)
	panel.spellBar.holdText:SetJustifyH("CENTER")
	local missHoldPlus = StepButton(panel.spellBar, "+")
	missHoldPlus:SetPoint("LEFT", panel.spellBar.holdText, "RIGHT", 2, 0)
	missHoldPlus:SetScript("OnClick", function()
		ChangeMissHold(0.4)
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
		ShowSpellMiss(686, "Shadow Bolt", 136235, "player", "RESIST", "Target")
	end)
	panel.spellBar.testButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.42, 0.16, 0.14, 1)
	end)
	panel.spellBar.testButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)
	local immuneLabel = panel.spellBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	immuneLabel:SetPoint("LEFT", panel.spellBar.testButton, "RIGHT", 16, 0)
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
	panel.spellBar.sounds = {}
	local function missSoundButton(text, id, x, y)
		local button = CreateFrame("Button", nil, panel.spellBar, "BackdropTemplate")
		button:SetSize(60, 22)
		button:SetPoint("TOPLEFT", x, y or -68)
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button.label:SetText(text)
		button.choiceId = id
		button:SetScript("OnClick", function()
			db.missSound = id
			LockRemindersPlayMissSound()
			if panel.spellBar.refresh then
				panel.spellBar.refresh()
			end
		end)
		button:SetScript("OnEnter", function(self)
			if not self.picked then
				self:SetBackdropColor(0.24, 0.16, 0.34, 1)
			end
		end)
		button:SetScript("OnLeave", function(self)
			if panel.spellBar.refresh then
				panel.spellBar.refresh()
			end
		end)
		panel.spellBar.sounds[#panel.spellBar.sounds + 1] = button
	end
	local missSounds = {
		{ "None", "none" },
		{ "Alarm", "alarm" },
		{ "Ping", "ping" },
		{ "Pulse", "pulse" },
		{ "Drip", "drip" },
		{ "Knock", "knock" },
		{ "Chime", "chime" },
		{ "Bloom", "bloom" },
		{ "Rise", "rise" },
		{ "Tick", "tick" },
		{ "Hum", "hum" },
		{ "Spark", "spark" },
		{ "Glass", "glass" },
		{ "Beep", "beep" },
		{ "Buzz", "buzz" },
		{ "Chirp", "chirp" },
		{ "Pop", "pop" },
		{ "Ding", "ding" },
		{ "Sweep", "sweep" },
		{ "Clap", "clap" },
		{ "Warp", "warp" },
	}
	for index = 1, #missSounds do
		local col = (index - 1) % 11
		local row = math.floor((index - 1) / 11)
		missSoundButton(missSounds[index][1], missSounds[index][2], 4 + col * 64, -68 - row * 26)
	end
	panel.spellBar.refresh = function()
		LockRemindersPaintToggle(panel.spellBar.immuneToggle, not db or db.immuneAlert ~= false)
		local selected = db and db.missSound or "ping"
		for index = 1, #panel.spellBar.sounds do
			local button = panel.spellBar.sounds[index]
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
		local spellID
		if db and type(db.talents) == "table" then
			for key in pairs(db.talents) do
				spellID = key
				break
			end
		end
		PlayTalent(spellID, true)
	end)
	testButton:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.28, 0.2, 0.42, 1)
	end)
	testButton:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.14, 0.1, 0.2, 1)
	end)

	local function choiceButton(text, x, y)
		local button = CreateFrame("Button", nil, talentBar, "BackdropTemplate")
		button:SetSize(164, 24)
		button:SetPoint("TOPLEFT", x, y)
		Paint(button, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER")
		button.label:SetText(text)
		button:SetScript("OnEnter", function(self)
			if not self.picked then
				self:SetBackdropColor(0.24, 0.16, 0.34, 1)
			end
		end)
		button:SetScript("OnLeave", function(self)
			if self.picked then
				self:SetBackdropColor(0.32, 0.22, 0.08, 1)
			else
				self:SetBackdropColor(0.14, 0.1, 0.2, 1)
			end
		end)
		return button
	end

	local function markChoices(buttons, selected)
		for index = 1, #buttons do
			local picked = buttons[index].choiceId == selected
			buttons[index].picked = picked
			if picked then
				Paint(buttons[index], 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
				buttons[index].label:SetTextColor(1, 0.93, 0.72)
			else
				Paint(buttons[index], 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
				buttons[index].label:SetTextColor(0.86, 0.82, 0.94)
			end
		end
	end

	holdLabel:Hide()
	local secondsButton = choiceButton("Seconds", 168, -4)
	secondsButton:SetSize(84, 22)
	secondsButton.choiceId = "seconds"
	holdMinus:ClearAllPoints()
	holdMinus:SetPoint("LEFT", secondsButton, "RIGHT", 6, 0)
	local untilButton = choiceButton("Until the buff ends", 348, -4)
	untilButton:SetSize(168, 22)
	untilButton.choiceId = "until"
	secondsButton:SetScript("OnClick", function()
		db.talentUntilEnd = false
		if talentBar.refresh then
			talentBar.refresh()
		end
	end)
	untilButton:SetScript("OnClick", function()
		db.talentUntilEnd = true
		if talentBar.refresh then
			talentBar.refresh()
		end
	end)

	local effectLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	effectLabel:SetPoint("TOPLEFT", 4, -70)
	effectLabel:SetText("Effect")
	effectLabel:SetTextColor(0.9, 0.84, 1)
	local effectIds = { "icon", "ring", "star", "flash", "lozenge", "glow" }
	local effectNames = { "Icon", "Ring", "Star", "Flash", "Diamond", "Glow" }
	local effectButtons = {}
	for index = 1, #effectIds do
		local col = (index - 1) % 3
		local row = math.floor((index - 1) / 3)
		local button = choiceButton(effectNames[index], 4 + col * 172, -92 - row * 30)
		button.choiceId = effectIds[index]
		button:SetScript("OnClick", function(self)
			db.talentStyle = self.choiceId
			if talentFrame and (talentMoving or talentFrame:IsShown()) then
				ApplyTalentFace()
				talentFrame:Show()
			end
			if talentBar.refresh then
				talentBar.refresh()
			end
		end)
		effectButtons[#effectButtons + 1] = button
	end

	local soundLabel = talentBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	soundLabel:SetPoint("TOPLEFT", 4, -160)
	soundLabel:SetText("Sound")
	soundLabel:SetTextColor(0.9, 0.84, 1)
	local soundIds = { "none", "alarm", "bell", "level", "coin", "ping", "tell", "invite", "clock", "pulse", "drip", "knock", "chime", "bloom", "rise", "tick", "hum", "spark", "glass", "beep", "buzz", "chirp", "pop", "ding", "sweep", "clap", "warp" }
	local soundNames = { "None", "Alarm", "Bell", "Level up", "Coin", "Ping", "Whisper", "Invite", "Clock", "Pulse", "Drip", "Knock", "Chime", "Bloom", "Rise", "Tick", "Hum", "Spark", "Glass", "Beep", "Buzz", "Chirp", "Pop", "Ding", "Sweep", "Clap", "Warp" }
	local soundButtons = {}
	for index = 1, #soundIds do
		local col = (index - 1) % 4
		local row = math.floor((index - 1) / 4)
		local button = choiceButton(soundNames[index], 4 + col * 176, -182 - row * 30)
		button.choiceId = soundIds[index]
		button:SetScript("OnClick", function(self)
			db.talentSound = self.choiceId
			PlayAlertSound()
			if talentBar.refresh then
				talentBar.refresh()
			end
		end)
		soundButtons[#soundButtons + 1] = button
	end

	talentBar.flashCheck = CreateFrame("Button", nil, talentBar, "BackdropTemplate")
	talentBar.flashCheck:SetSize(22, 22)
	talentBar.flashCheck:SetPoint("TOPLEFT", 4, -400)
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
	talentBar.flashNote = talentBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	talentBar.flashNote:SetPoint("TOPLEFT", talentBar.flashCheck, "BOTTOMLEFT", 0, -6)
	talentBar.flashNote:SetWidth(500)
	talentBar.flashNote:SetJustifyH("LEFT")
	talentBar.flashNote:SetText("A flash across the whole screen when the buff activates. On by default.")
	talentBar.flashNote:SetTextColor(0.7, 0.66, 0.78)
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
		markChoices(effectButtons, db.talentStyle or "icon")
		markChoices(soundButtons, db.talentSound or "none")
		local untilEnd = db.talentUntilEnd and true or false
		markChoices({ secondsButton, untilButton }, untilEnd and "until" or "seconds")
		holdMinus:SetShown(not untilEnd)
		talentHoldText:SetShown(not untilEnd)
		holdPlus:SetShown(not untilEnd)
		local on = db.talentScreenFlash ~= false
		talentBar.flashCheck.mark:SetShown(on)
		if on then
			Paint(talentBar.flashCheck, 0.32, 0.22, 0.08, 1, 0.95, 0.78, 0.35, 1)
		else
			Paint(talentBar.flashCheck, 0.14, 0.1, 0.2, 1, 0.45, 0.35, 0.62, 1)
		end
	end

	scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", 14, -180)
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
	end)

	if not tContains(UISpecialFrames, "LockRemindersPanel") then
		tinsert(UISpecialFrames, "LockRemindersPanel")
	end

	LockRemindersBuildMisc(panel)
	if LockRemindersIsWarlock() then
		LockRemindersBuildSoul(panel)
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
	Print("Click the minimap icon to add powers and food.")
	Print("Drag the alert border to move it. /lr lock keeps it still.")
	Print("Each module has its own alert. Configure alert opens its size and position.")
	Print("Talents lists the buff from the talent. Nightfall shows Shadow Trance.")
	Print("Spell alerts: add a spell or a pet spell. Only those miss and resist.")
	Print("Miscellaneous: speed, low health, and low mana. /lr misc")
	Print("Soulstone tracker is for warlocks. /lr soul")
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
		db.columns = 0
		db.order = {}
		db.talents = {}
		db.talentPoint = { "CENTER", "CENTER", 0, 140 }
		db.talentSize = 72
		db.talentHold = 2.2
		db.missPlayer = false
		db.missPet = false
		db.missSpells = {}
		db.missPoint = { "CENTER", "CENTER", 0, 260 }
		db.missSize = 40
		db.missHold = 2.2
		db.missSound = "ping"
		db.immuneAlert = true
		db.speedShow = true
		db.speedSize = 18
		db.speedPoint = { "CENTER", "CENTER", 0, -160 }
		db.healthAlert = true
		db.healthPct = 35
		db.healthSound = "pulse"
		db.manaAlert = true
		db.manaPct = 25
		db.manaSound = "drip"
		db.vitalSize = 32
		db.vitalHold = 3
		db.healthLabel = "LOW HEALTH"
		db.manaLabel = "LOW MANA"
		db.vitalStyle = "none"
		db.vitalPoint = { "CENTER", "CENTER", 0, 60 }
		LockRemindersMisc.vitalUntil = nil
		LockRemindersMisc.speedMoving = false
		LockRemindersMisc.vitalMoving = false
		LockRemindersMisc.healthDown = false
		LockRemindersMisc.manaDown = false
		LockRemindersMisc.previewUntil = nil
		db.soulAlert = true
		db.soulScope = { always = true, party = false, raid = false }
		db.soulSize = 48
		db.soulPoint = { "CENTER", "CENTER", 0, 180 }
		db.soulSound = "chime"
		db.soulTrack = true
		db.soulTrackScope = { always = true, party = false, raid = false }
		db.soulTrackSize = 100
		db.soulFullName = true
		db.soulTrackFrame = true
		db.soulTrackPoint = { "CENTER", "CENTER", -280, 40 }
		db.banishAlert = true
		db.banishWarn = 5
		db.banishSize = 48
		db.banishLabel = "BANISH"
		db.banishScope = { always = true, party = false, raid = false }
		db.banishPoint = { "CENTER", "CENTER", 180, 210 }
		db.shardShow = true
		db.shardSize = 40
		db.shardLabel = "NO SHARDS"
		db.shardScope = { always = true, party = false, raid = false }
		db.shardPoint = { "CENTER", "CENTER", -180, -80 }
		LockRemindersWarlock.banishMoving = false
		LockRemindersWarlock.shardMoving = false
		LockRemindersWarlock.banishPreview = nil
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
			LockRemindersSetSpeedMove(false)
		end
		if LockRemindersMisc.vital then
			LockRemindersApplyVitalLook()
			LockRemindersApplyNamedPoint(LockRemindersMisc.vital, "vitalPoint", db.vitalPoint)
			LockRemindersMisc.vital:Hide()
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
	if type(db.columns) ~= "number" then
		db.columns = 0
	end
	if type(db.order) ~= "table" then
		db.order = {}
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
	if type(db.talentStyle) ~= "string" then
		db.talentStyle = "icon"
	end
	if type(db.talentSound) ~= "string" then
		db.talentSound = "none"
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
	if type(db.missPoint) ~= "table" then
		db.missPoint = { "CENTER", "CENTER", 0, 260 }
	end
	if type(db.missSize) ~= "number" then
		db.missSize = 40
	end
	if type(db.missHold) ~= "number" then
		db.missHold = 2.2
	end
	if type(db.missSound) ~= "string" then
		db.missSound = "ping"
	end
	if type(db.immuneAlert) ~= "boolean" then
		db.immuneAlert = true
	end
	if type(db.speedShow) ~= "boolean" then
		db.speedShow = true
	end
	if type(db.speedSize) ~= "number" then
		db.speedSize = 18
	end
	if type(db.speedPoint) ~= "table" then
		db.speedPoint = { "CENTER", "CENTER", 0, -160 }
	end
	if type(db.healthAlert) ~= "boolean" then
		db.healthAlert = true
	end
	if type(db.healthPct) ~= "number" then
		db.healthPct = 35
	end
	if type(db.healthSound) ~= "string" then
		db.healthSound = "pulse"
	end
	if type(db.manaAlert) ~= "boolean" then
		db.manaAlert = true
	end
	if type(db.manaPct) ~= "number" then
		db.manaPct = 25
	end
	if type(db.manaSound) ~= "string" then
		db.manaSound = "drip"
	end
	if type(db.vitalSize) ~= "number" then
		db.vitalSize = 32
	end
	if type(db.vitalHold) ~= "number" then
		db.vitalHold = 3
	end
	if type(db.vitalPoint) ~= "table" then
		db.vitalPoint = { "CENTER", "CENTER", 0, 60 }
	end
	if type(db.healthLabel) ~= "string" then
		db.healthLabel = "LOW HEALTH"
	end
	if type(db.manaLabel) ~= "string" then
		db.manaLabel = "LOW MANA"
	end
	if type(db.vitalStyle) ~= "string" then
		db.vitalStyle = "none"
	elseif db.vitalStyle == "ring" or db.vitalStyle == "star" or db.vitalStyle == "lozenge" or db.vitalStyle == "glow" or db.vitalStyle == "icon" then
		db.vitalStyle = "pulse"
	end
	if type(db.soulAlert) ~= "boolean" then
		db.soulAlert = true
	end
	if type(db.soulScope) == "string" or type(db.soulScope) ~= "table" then
		local always, party, raid = ScopeFlags(db.soulScope)
		db.soulScope = { always = always, party = party, raid = raid }
	end
	if type(db.soulSize) ~= "number" then
		db.soulSize = 48
	end
	if type(db.soulPoint) ~= "table" then
		db.soulPoint = { "CENTER", "CENTER", 0, 180 }
	end
	if type(db.soulSound) ~= "string" then
		db.soulSound = "chime"
	end
	if type(db.soulTrack) ~= "boolean" then
		db.soulTrack = true
	end
	if type(db.soulTrackScope) == "string" or type(db.soulTrackScope) ~= "table" then
		local always, party, raid = ScopeFlags(db.soulTrackScope)
		db.soulTrackScope = { always = always, party = party, raid = raid }
	end
	if type(db.soulTrackSize) ~= "number" then
		db.soulTrackSize = 100
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
	if type(db.banishLabel) ~= "string" then
		db.banishLabel = "BANISH"
	end
	if type(db.banishScope) == "string" or type(db.banishScope) ~= "table" then
		local always, party, raid = ScopeFlags(db.banishScope)
		db.banishScope = { always = always, party = party, raid = raid }
	end
	if type(db.banishPoint) ~= "table" then
		db.banishPoint = { "CENTER", "CENTER", 180, 210 }
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
	if type(db.shardScope) == "string" or type(db.shardScope) ~= "table" then
		local always, party, raid = ScopeFlags(db.shardScope)
		db.shardScope = { always = always, party = party, raid = raid }
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
pcall(events.RegisterEvent, events, "SPELL_ACTIVATION_OVERLAY_SHOW")
pcall(events.RegisterEvent, events, "UNIT_SPELLCAST_SUCCEEDED")
pcall(events.RegisterEvent, events, "PLAYER_TARGET_CHANGED")
if events.RegisterUnitEvent then
	pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
end

function MarkCastBuff(spellID, spellName)
	LockRemindersCastSeen = LockRemindersCastSeen or {}
	spellID = tonumber(spellID)
	if spellID and spellID > 0 and not (issecretvalue and issecretvalue(spellID)) then
		local aliases = SpellAliases(spellID)
		for index = 1, #aliases do
			LockRemindersCastSeen[aliases[index]] = true
		end
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
		return
	end
	if not db or type(db.auras) ~= "table" then
		return
	end
	for key in pairs(db.auras) do
		local saved = tonumber(key)
		if saved and Normalize(SpellName(saved) or "") == wanted then
			LockRemindersCastSeen[saved] = true
		end
	end
end

function WatchCombatAlerts()
	if not events or events.combatTicker then
		return
	end
	events.combatTicker = C_Timer.NewTicker(0.25, function()
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
		CreateUI()
		CreatePanel()
		CreateTalentAlert()
		CreateFoodAlert()
		CreateSpellMissAlert()
		CreateMiscAlerts()
		LockRemindersStartMisc()
		CreateSoulAlerts()
		LockRemindersStartSoul()
		LockRemindersRegisterCastUnits()
		CreateMinimapButton()
		Refresh()
		C_Timer.After(1, function()
			pcall(WatchTalents, true)
		end)
		return
	end
	if event == "PLAYER_TALENT_UPDATE" or event == "SPELLS_CHANGED" or event == "SPELL_DATA_LOAD_RESULT" then
		InvalidateSpellbook()
		if UpdateListNow then
			UpdateListNow()
		end
	end
	if event == "SPELL_ACTIVATION_OVERLAY_SHOW" then
		pcall(TriggerTalent, arg1)
		pcall(QuietScreenFlash)
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		pcall(LockRemindersUpdateSpeed)
	end
	if event == "PLAYER_ENTERING_WORLD" then
		pcall(LockRemindersRegisterCastUnits)
		PlaceMinimapButton()
		C_Timer.After(1, function()
			pcall(WatchTalents, true)
		end)
	end
	if event == "PLAYER_REGEN_DISABLED" then
		WatchCombatAlerts()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if events.combatTicker then
			events.combatTicker:Cancel()
			events.combatTicker = nil
		end
		if LockRemindersCastSeen then
			for key in pairs(LockRemindersCastSeen) do
				LockRemindersCastSeen[key] = nil
			end
		end
	end
	if event == "UNIT_COMBAT" then
		pcall(LockRemindersHandleUnitCombat, arg1, arg2, arg3, arg4, arg5)
		return
	end
	if event == "UNIT_SPELLCAST_INTERRUPTED" then
		pcall(LockRemindersNoteInterrupted, arg1)
		return
	end
	if event == "GROUP_ROSTER_UPDATE" then
		pcall(LockRemindersRegisterCastUnits)
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		pcall(LockRemindersNoteSoulCast, arg1, arg2, arg3, arg4)
		if arg1 == "player" or arg1 == "pet" then
			pcall(LockRemindersNoteCast, arg1, arg2, arg3, arg4)
		end
		if arg1 and arg1 ~= "player" then
			return
		end
		local castID = tonumber(arg3) or tonumber(arg4) or tonumber(arg2)
		local castName = type(arg2) == "string" and not arg2:find("-", 1, true) and arg2 or nil
		if (not castID or (issecretvalue and issecretvalue(castID))) and type(arg3) == "string" then
			castName = castName or arg3
		end
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
		local added = arg2.addedAuras
		if type(added) == "table" then
			for index = 1, #added do
				local aura = added[index]
				if type(aura) == "table" then
					MarkCastBuff(aura.spellId or aura.spellID, aura.name)
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
	end
	pcall(Refresh)
	if event == "UNIT_AURA" or event == "BAG_UPDATE_DELAYED" or event == "SPELL_DATA_LOAD_RESULT" or event == "ITEM_DATA_LOAD_RESULT" then
		QueueListRefresh()
	end
end)

SLASH_LOCKREMINDERS1 = "/lr"
SLASH_LOCKREMINDERS2 = "/lockreminders"
SlashCmdList.LOCKREMINDERS = Command
