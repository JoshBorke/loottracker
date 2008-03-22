-- [[ LootTrack Debug Levels ]]--
local _version = "1.08-20200"
--[[ Localisations ]]--
local L = LootTrackerLocals
--[[ Variables ]]--
local _
local _db -- to hold the list database
local _itemCache
local _playerName = UnitName('player') -- available at login
local _server = GetRealmName()
local _bagItems, _bankItems = {}, {}
local _bankOpen
local _hooked = false
local _equippedSlots = {
	HeadSlot = false,
	NeckSlot = false,
	ShoulderSlot = false,
	BackSlot = false,
	ChestSlot = false,
	ShirtSlot = false,
	TabardSlot = false,
	WristSlot = false,
	HandsSlot = false,
	WaistSlot = false,
	LegsSlot = false,
	FeetSlot = false,
	Finger0Slot = false,
	Finger1Slot = false,
	Trinket0Slot = false,
	Trinket1Slot = false,
	MainHandSlot = false,
	SecondaryHandSlot = false,
	RangedSlot = false,
}

local MAXITEMS = 40000
local ClickTip = LibStub:GetLibrary("ClickTip-Beta0", true)

-- Binding Variables
BINDING_HEADER_LOOTTRACKER = "LootTracker (".._version..")"
BINDING_NAME_LTTOGGLECONFIG = L["Toggle Config"]
BINDING_NAME_LTTOGGLETRACK = L["Toggle Tracker"]


--[[ For OH Stuff ]]--
local OH = LibStub:GetLibrary("OptionHouse-1.1")
local ui = OH:RegisterAddOn("LootTracker", "LootTracker", "JoshBorke", _version)
local ohpar = OH and OH:GetFrame("addon")

local configFrame, visFrame
local currentSet-- current set means we've selected a set as a sub cat
local selectedSet -- selectSet is the ID of the line we've currently selected
local selectedLine -- selectedLine is the index of the line we've currently selected

LootTracker = DongleStub("Dongle-1.0"):New("LootTracker")
local LootTracker = LootTracker
--[[ Local functions ]]--
--[[ Function to handle initialization ]]--
function LootTracker:Initialize()
	self.defaults = {
		profile = {
			positions = {},
			trackedLists = {},
			tracker = {
				old = {
					alpha = 1,
					scale = 1,
					combatHidden = false,
					locked = false,
					squish = false,
				},
				new = {
					alpha = 1,
					scale = 1,
					combatHidden = false,
					locked = false,
					squish = false,
				},
				ctc = false,
				hideifnone = false,
				collapsed = {},
			}
		},
		global = {
			lists = {}, -- for storing lists
			cache = {}, -- for storing bag/bank items
			items ={}, -- for storing item->name conversions
		},
	}
	self:CreateSlashCommands()
	if (not _hooked) then
		hooksecurefunc('SetItemRef',
			function(link, text, button)
				if (not link) then return end
				if (self.inputItemFrame and self.inputItemFrame:IsShown()) then
					if (IsShiftKeyDown()) then
						local name,link = GetItemInfo(link)
						self.inputItemFrame.item:SetText(link)
					end
				end
			end )
		hooksecurefunc('ChatEdit_InsertLink',
			function(text)
				if (not text) then return end
				if (self.inputItemFrame and self.inputItemFrame:IsShown()) then
					if (IsShiftKeyDown()) then
						local name,link = GetItemInfo(text)
						self.inputItemFrame.item:SetText(link)
					end
				end
			end )
		_hooked = true
	end
	for name in pairs(_equippedSlots) do
		_equippedSlots[name] = GetInventorySlotInfo(name)
	end
end

function LootTracker:Enable()
	self.db = self:InitializeDB("LootTrackerDB", self.defaults)
	_db = self.db
	_itemCache = self.db.global.cache
	if (not _itemCache[_server]) then
		_itemCache[_server] = {
			[_playerName] = {}
		}
	elseif (not _itemCache[_server][_playerName]) then
		_itemCache[_server][_playerName] = {}
	end
	self:UpdateItemIDs()
	self:RegisterEvent("BANKFRAME_OPENED", "UpdateBankItemCounts")
	self:RegisterEvent("BANKFRAME_CLOSED", function() _bankOpen = false end)
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "UpdateBankItemCounts")
	self:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", "UpdateBankItemCounts")
	self:RegisterEvent("BAG_UPDATE", "UpdateBagItemCounts")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
			local options = _db.profile.tracker
			if options.old.combatHidden and self.oldTracker then self.oldTracker:Hide() end
			if options.new.combatHidden and self.newTracker then self.newTracker:Hide() end
		end )
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
			local options = _db.profile.tracker
			if options.old.shown and self.oldTracker then self:ShowTracker() end
			if options.new.shown and self.newTracker then self.newTracker:Show() end
		end)
	self:UpdateBagItemCounts()
	self:PruneSets()
	if not ClickTip then
		_db.profile.tracker.new.shown = false
	end
	if (_db.profile.tracker.old.shown) then
		self:ShowTracker()
	end
	if (_db.profile.tracker.new.shown) then
		self:ShowNewTracker()
	end
	ui:RegisterCategory(L["Visuals"], self, "CreateRandomConfigs")
	ui:RegisterCategory(L["Sets"], self, "PopulateOHFrame", true) -- don't cache the frame
	local sets = _db.global.lists
	for i = 1, #sets do
		ui:RegisterSubCategory(L["Sets"], sets[i], self, "PopulateOHFrame", true) -- don't cache the frame
	end
end

function LootTracker:Disable()
	--self:SavePosition("LootTrackerTrackingFrame")
	self:SavePosition("LootTrackerConfigFrame")
end

function LootTracker:CreateSlashCommands()
	local cmd = self:InitializeSlashCommand("LootTracker Slash Command", "LOOTTRACKER", "loottracker", "lt", "ltr")
	local ShowConfig = function(opt)
		local tolower = string.lower
		if tolower(opt) == 'vis' then
			OH:Open("LootTracker",L["Visuals"])
		elseif tolower(opt) == ' sets' then
			OH:Open("LootTracker",L["Sets"])
		else
			OH:Open("LootTracker")
		end
	end
	cmd:RegisterSlashHandler("config - Show configuration frame", "^config(.*)$", ShowConfig)
	cmd:RegisterSlashHandler("sets - Show the sets configuration", "^sets$", function() OH:Open("LootTracker",L["Sets"]) end)
	cmd:RegisterSlashHandler("visuals - Show the visual configurations", "^vis.*$", function() OH:Open("LootTracker",L["Visuals"]) end)
	local Reset = function()
		self:ResetOptions()
		_db:ResetDB()
		_itemCache = _db.global.cache
		self.currentSet = nil
		if (self.configFrame) then
			self:UpdateSetScroll()
			self:UpdateItemScroll()
		end
	end
	local ResetCache = function()
		_db.global.cache = {}
		_itemCache = _db.global.cache
		self:UpdateBagItemCounts()
		if (self.configFrame) then
			self:UpdateItemScroll()
		end
		self:PopulateTrackerFrame()
		self:PopulateNewTracker()
	end
	cmd:RegisterSlashHandler("reset - Reset the configuration", "^reset$", Reset)
	cmd:RegisterSlashHandler("resetCache - Reset the item count totals", "^resetCache$", ResetCache)
end

function LootTracker:UpdateBagItemCounts()
	local match = string.match
	local itemLink, itemID, count
	local cache = _itemCache[_server][_playerName]
	local name
	if (not cache) then
		cache = {}
		_itemCache[_server][_playerName] = cache
	end
	local bagItems = cache.bagItems
	if (not bagItems) then
		bagItems = {}
		cache.bagItems = bagItems
	end
	for item, count in pairs(bagItems) do
		bagItems[item] = 0
	end
	for name, id in pairs(_equippedSlots) do
		itemLink = GetInventoryItemLink("player", id)
		if (itemLink) then
			name = GetItemInfo(itemLink)
			if (name) then
				count = GetInventoryItemCount("player", id)
				bagItems[name] = count + (bagItems[name] or 0)
			end
		end
	end
	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			itemLink = GetContainerItemLink(bag, slot)
			if (itemLink) then
				--itemID = match(itemLink, "item:(%-?%d+)")
				name = GetItemInfo(itemLink)
				if (name) then
					_, count = GetContainerItemInfo(bag, slot)
					--bagItems[itemID] = count + (bagItems[itemID] or 0)
					bagItems[name] = count + (bagItems[name] or 0)
				end
			end
		end
	end
	if (_bankOpen) then
		self:UpdateBankItemCounts() -- no event fires for putting an item in the bank
	end
	if (self.oldTracker and self.oldTracker:IsShown()) then
		self:PopulateTrackerFrame() -- update the tracker frame
		self:PopulateNewTracker() -- update the tracker frame
	end
end

function LootTracker:UpdateBankItemCounts()
	local match = string.match
	local itemLink, itemID, count
	local cache = _itemCache[_server][_playerName]
	local name
	if (not cache) then
		cache = {}
		_itemCache[_server][_playerName] = cache
	end
	local bankItems = cache.bankItems
	if (not bankItems) then
		bankItems = {}
		cache.bankItems = bankItems
	end
	for item, count in pairs(bankItems) do
		bankItems[item] = 0
	end
	local bag = -1
	_bankOpen = true
	local bankSlots = GetNumBankSlots()
	for slot = 1, GetContainerNumSlots(bag) do
		itemLink = GetContainerItemLink(bag, slot)
		if (itemLink) then
			--itemID = match(itemLink, "item:(%-?%d+)")
			name = GetItemInfo(itemLink)
			_, count = GetContainerItemInfo(bag, slot)
			--bankItems[itemID] = count + (bankItems[itemID] or 0)
			bankItems[name] = count + (bankItems[name] or 0)
		end
	end
	if (bankSlots > 0) then
		for cbag = 1, bankSlots do
			bag = cbag + 4
			for slot = 1, GetContainerNumSlots(bag) do
				itemLink = GetContainerItemLink(bag, slot)
				if (itemLink) then
					--itemID = match(itemLink, "item:(%-?%d+)")
					_, count = GetContainerItemInfo(bag, slot)
					name = GetItemInfo(itemLink)
					--bankItems[itemID] = count + (bankItems[itemID] or 0)
					bankItems[name] = count + (bankItems[name] or 0)
					--self:Print(string.format("%s: %s", name, count))
				end
			end
		end
	end
	if (self.oldTracker and self.oldTracker:IsShown()) then
		self:PopulateTrackerFrame() -- update the tracker frame
		self:PopulateNewTracker() -- update the tracker frame
	end
end

function LootTracker:GetItemCount(name, player)
	local cache = _itemCache[_server]
	if (not cache) then return 0 end
	local total = 0
	if (_db.profile.tracker.ctc and not player) then
		player = _playerName
	end
	if (player) then
		cache = cache[player]
		if (not cache) then return total end
		for bag, items in pairs(cache) do
			if (items[name]) then
				total = items[name] + total
			end
		end
	else
		for player, bags in pairs(cache) do
			for bag, items in pairs(bags) do
				if (items[name]) then
					total = items[name] + total
				end
			end
		end
	end
	return total
end

function LootTracker:UpdateSetName(setName)
	if (self.newSet) then
		self:CreateNewSet(setName)
		return
	else
		local lists = _db.global.lists
		if (not _db.global) then _db.global = {} end
		if (not _db.global.lists) then
			_db.global.lists = {}
			lists = _db.global.lists
		end
		ui:RemoveSubCategory(L["Sets"], self.currentSet) -- remove the current set name
		ui:RegisterSubCategory(L["Sets"], setName, self, "PopulateOHFrame", true) -- don't cache the frame
		if (lists[self.currentSet]) then
			lists[setName] = lists[self.currentSet]
			lists[self.currentSet] = nil
			table.insert(lists, setName)
			for index, set in pairs(lists) do
				if (set == self.currentSet) then
					table.remove(lists, index)
				end
			end
			table.sort(lists)
		end
	end
end

function LootTracker:CreateNewSet(setName)
	local _lists = _db.global.lists
	if (not _db.global) then _db.global = {} end
	if (not _db.global.lists) then
		_db.global.lists = {}
		_lists = _db.global.lists
	end
	if (not _lists[setName]) then
		_lists[setName] = {}
		table.insert(_lists, setName)
		table.sort(_lists)
		ui:RegisterSubCategory(L["Sets"], setName, self, "PopulateOHFrame", true) -- don't cache the frame
		self:updateScrollList()
	end
end

function LootTracker:RemoveSet(setName)
	local _lists = _db.global.lists
	if (not _db.global) then _db.global = {} end
	if (not _db.global.lists) then
		_db.global.lists = {}
		_lists = _db.global.lists
	end
	if (_lists[setName]) then
		_lists[setName] = nil
		for index, set in pairs(_lists) do
			if (set == setName) then
				table.remove(_lists, index)
			end
		end
		-- make sure to remove it from the tracked list
		local tracked = _db.profile.trackedLists
		if tracked then
			for i=1,#tracked do
				local list = tracked[i]
				if list == setName then
					table.remove(tracked, i)
				end
			end
		end
	end
	return true
end

-- called to prune out previously removed sets
function LootTracker:PruneSets()
	local tracked = _db.profile.trackedLists
	local lists = _db.global.lists
	local list
	local i, max = 1, #tracked
	while (true) do
		list = tracked[i]
		if (list and not lists[list]) then
			table.remove(tracked,i)
		else
			i = i+1
		end
		if (i > max) then break end
	end
end

local function myListSort(id1, id2)
	local name1, name2
	if (id1) then
		name1 = GetItemInfo(id1)
	end
	if (id2) then
		name2 = GetItemInfo(id2)
	end
	if (not name1 or not name2) then return end
	return name1 < name2
end

function LootTracker:UpdateItemIDs()
	-- here we update the items lookup table in case we don't have one generated already
	local cache = _itemCache[_server]
	local itemsDB = _db.global.items
	local name, link, itemID
	local name2, link2, found
	local MAXITEMS = 40000
	for player, bags in pairs(cache) do
		for bag, items in pairs(bags) do
			for item, count in pairs(items) do
				name, link = GetItemInfo(item)
				if (not name) then
					found = false
					for i=1, MAXITEMS do
						if (not found) then
							name2, link2 = GetItemInfo(i)
							if (name == name2) then
								name = name2
								link = link2
								found = true
							end
						end
					end
				end
				if (name and link) then
					itemID = string.match(link, "item:(%-?%d+)")
					itemsDB[name] = itemID
					itemsDB[itemID] = name
				end
			end
		end
	end
end

function LootTracker:GetItemID(name,id)
	local db = _db.global.items
	local res
	local name2, link, itemID
	if (name) then
		res = db[name]
	elseif (id) then
		res = db[id]
	end
	if (not res) then
		for i=1, MAXITEMS do
			name2, link = GetItemInfo(i)
			if (name == name2) then
				break
			end
		end
		itemID = string.match(link, "item:(%-?%d+)")
		res = itemID
	end
	return res
end

function LootTracker:GetItemNameFromInput(input)
	local name
	local lower = string.lower
	local linput = lower(input)
	local itemID = string.match(input, "item:(%-?%d+)")
	if (not itemID) then
		local db = _db.global.items
		-- find the itemID...
		if db[input] then
			local name, itemLink = GetItemInfo(db[input])
			if name then
				return name, string.match(itemLink, "item:(%-?%d+)")
			end
		end
		for i=1, MAXITEMS do
			local name, itemLink = GetItemInfo(i)
			if name then
				if lower(name or '') == lower(input) or string.match(itemLink, "item:(%-?%d+)") == input then
					return name, string.match(itemLink, "item:(%-?%d+)")
				end
			end
		end
	else
		name = GetItemInfo(itemID)
	end
	return name, itemID
end

function LootTracker:UpdateItem(itemLink, count)
	local list = _db.global.lists[currentSet]
	local name, itemID = self:GetItemNameFromInput(itemLink)
	local found
	if (not name) then return false end
	if (not list) then return false end
	if (not itemID) then return false end
	if (count == '') then count = nil end
	for index, ID in pairs(list) do
		if (ID == name) then
			found = true
		end
	end
	if (not found) then
		_db.global.items[itemID] = name
		_db.global.items[name] = itemID
		table.insert(list, name)
		table.sort(list, myListSort)
	end
	list[name] = count --or 0
	return true
end

function LootTracker:RemoveItem(itemID, set)
	local list = _db.global.lists[set]
	if (not list or not itemID) then return false end
	list[itemID] = nil
	for index, ID in pairs(list) do
		if (ID == itemID) then
			table.remove(list, index)
		end
	end
	return true
end

function LootTracker:IsSetTracked(setName)
	local lists = _db.profile.trackedLists
	for index, list in pairs(lists) do
		if (list == setName) then
			return true
		end
	end
end

function LootTracker:ToggleTrackSet(setName)
	local lists = _db.profile.trackedLists
	local found = false
	for index, list in pairs(lists) do
		if (list == setName) then
			found = true
			table.remove(lists, index) -- removing from a sorted lists leaves it sorted
		end
	end
	if (found) then return false end -- if we removed, return false
	table.insert(lists, setName)
	table.sort(lists)
	return true -- adding = return true
end

--[[ Frame Functions ]]--

function LootTracker:AddToTip(itemName)
	local cache = _itemCache[_server]
	if (not cache) then return end
	local count
	local txt = ''
	for player in pairs(cache) do
		count = self:GetItemCount(itemName, player)
		if (count and count > 0) then
			GameTooltip:AddLine(string.format("%s: %d", player, self:GetItemCount(itemName, player)))
		end
	end
end

local TL, TR, BL, BR = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"
-- copied from PerfectRaid, credit goes to cladhaire
function LootTracker:SavePosition(name)
    local f = getglobal(name)
	if (not f) then return end
    local x,y = f:GetCenter()
	local anchor = 'CENTER'
    local s = f:GetEffectiveScale()

    --x,y = x*s,y*s

	local opt = _db.profile.positions[name]
	if not opt then
		_db.profile.positions[name] = {}
		opt = _db.profile.positions[name]
	end
	local h, w = UIParent:GetHeight(), UIParent:GetWidth()
	local xOff, yOff, anchor = 0, 0, 'CENTER'
	local fW, fH = f:GetWidth() / 2, f:GetHeight() / 2
	local left, top, right, bottom = x - fW, y + fH, x + fW, y - fH
	if (x > w/2) then -- on the right half of the screen
		if (y > h/2) then -- top half
			xOff = -(w - right)
			yOff = -(h - top)
			anchor = TR
		else -- bottom half
			xOff = -(w - right)
			yOff = bottom
			anchor = BR
		end
	else -- on the left half of the screen
		if (y > h/2) then -- top half
			xOff = left
			yOff = -(h - top)
			anchor = TL
		else -- bottom half
			xOff = left
			yOff = bottom
			anchor = BL
		end
	end
    opt.PosX = xOff*s
    opt.PosY = yOff*s
	opt.anchor = anchor
end

-- copied from PerfectRaid, credit goes to cladhaire
function LootTracker:RestorePosition(name)
	local f = getglobal(name)
	local opt = _db.profile.positions[name]
	if not opt then
		_db.profile.positions[name] = {}
		opt = _db.profile.positions[name]
	end
	local h, w = UIParent:GetHeight(), UIParent:GetWidth()

	local x = opt.PosX
	local y = opt.PosY
	local anchor = opt.anchor

    local s = f:GetEffectiveScale()

    if not x or not y or not anchor then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    x,y = x/s,y/s
	f:ClearAllPoints()
	f:SetPoint(anchor, UIParent, anchor, x, y)
end

function LootTracker:CreateTrackerFrame()
	if (self.oldTracker) then return end
	local tooltip = CreateFrame('GameTooltip', 'LootTrackerTrackingFrame', UIParent, 'GameTooltipTemplate')
	tooltip:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
    tooltip:SetBackdropColor(24/255, 24/255, 24/255, 1)
	tooltip:EnableMouse(true)
	tooltip:SetMovable(true)
	--tooltip:RegisterForDrag("LeftButton")
	tooltip:SetScript("OnMouseDown",function(this, button) tooltip:StartMoving() end)
	tooltip:SetScript("OnMouseUp",function() self:SavePosition(tooltip:GetName()); tooltip:StopMovingOrSizing() end)
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetClampedToScreen(true)
	tooltip:SetFrameStrata("BACKGROUND")
	tooltip:Show()
	tooltip:SetScript("OnShow", function() self:PopulateTrackerFrame() end)
	self.oldTracker = tooltip
	return tooltip
end

function LootTracker:CreateSetInputFrame()
	if (self.inputSetFrame) then return end
	local frame = CreateFrame('Frame', nil, OH:GetFrame("addon"))
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(frame:GetFrameLevel()+6)
	frame:SetWidth(250)
	frame:SetHeight(75)
	frame:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	frame:ClearAllPoints()
	frame:SetBackdropColor(24/255, 24/255, 24/255)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:Show()
	frame:SetScript("OnDragStart", function() this:StartMoving() end)
	frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	frame:SetClampedToScreen(true)
	local e = CreateFrame('EditBox','LootTrackerSetEditBox',frame,'InputBoxTemplate')
	local f = frame:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
	e.label = f
	e:SetHeight(26)
	e:SetWidth(225)
	f:SetPoint('BOTTOMLEFT',e,'TOPLEFT',-2,0)
	e:SetAutoFocus(true)
	e:SetFont("Fonts\\FRIZQT__.TTF", 16)
	e:SetTextColor(1,1,1)
	f:SetText('Set Name')
	e:SetPoint('TOPLEFT', frame, 'TOPLEFT', 15, -23)
	frame.ok = self:CreateButton(frame, 75, 20, 'Ok', 'BOTTOMLEFT', frame, 'BOTTOMLEFT', 10, 5)
	frame.cancel = self:CreateButton(frame, 75, 20, 'Cancel', 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -10, 5)
	frame:SetScript("OnHide", function(this) e:SetText('') end)
	frame.editBox = e
	frame.editBox:SetScript("OnEnterPressed",
		function(this)
			self:UpdateSetName(e:GetText())
			selectedLine = nil
			self:updateScrollList(true)
			frame:Hide()
		end )
	frame.cancel:SetScript("OnClick", function(this) frame:Hide() end)
	frame.editBox:SetScript("OnEscapePressed", function(this) frame:Hide() end)
	frame.ok:SetScript("OnClick",
		function(this)
			self:UpdateSetName(e:GetText())
			selectedLine = nil
			self:updateScrollList(true)
			frame:Hide()
		end )
	frame:SetPoint('CENTER')
	self.inputSetFrame = frame
end

function LootTracker:CreateItemInputFrame()
	if (self.inputItemFrame) then return end
	local frame = CreateFrame('Frame', nil, OH:GetFrame("addon"))
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(frame:GetFrameLevel()+7)
	frame:SetWidth(250)
	frame:SetHeight(75)
	frame:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	frame:ClearAllPoints()
	frame:SetBackdropColor(24/255, 24/255, 24/255)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:Show()
	frame:SetScript("OnDragStart", function() this:StartMoving() end)
	frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	frame:SetClampedToScreen(true)
	local e = CreateFrame('EditBox','LootTrackerItemCountEditBox',frame,'InputBoxTemplate')
	local f = frame:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
	e.label = f
	e:SetHeight(26)
	e:SetWidth(45)
	f:SetPoint('BOTTOMLEFT',e,'TOPLEFT',-2,0)
	e:SetAutoFocus(false)
	e:SetFont("Fonts\\FRIZQT__.TTF", 16)
	e:SetTextColor(1,1,1)
	f:SetText('Goal')
	e:SetPoint('TOPLEFT', frame, 'TOPLEFT', 15, -23)
	frame.num = e
	f = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	f:SetText('x')
	f:SetPoint('LEFT', frame.num, 'RIGHT', 1, 0)
	e:SetNumeric(true)
	e:SetMaxLetters(4)

	e = CreateFrame('EditBox','LootTrackerItemNameEditBox',frame,'InputBoxTemplate')
	e:SetPoint('LEFT', frame.num, 'RIGHT', 12, 0)
	e:SetHeight(26)
	e:SetWidth(165)
	e:SetAutoFocus(false)
	e:SetFont("Fonts\\FRIZQT__.TTF", 16)
	e:SetTextColor(1,1,1)
	f = frame:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
	e.label = f
	f:SetPoint('BOTTOMLEFT',e,'TOPLEFT',-2,0)
	f:SetText('Item')
	frame.item = e
	frame.ok = self:CreateButton(frame, 75, 20, 'Ok', 'BOTTOMLEFT', frame, 'BOTTOMLEFT', 10, 5)
	frame.cancel = self:CreateButton(frame, 75, 20, 'Cancel', 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -10, 5)
	frame.num:SetScript("OnTabPressed", function(this) frame.item:SetFocus() end)
	frame.item:SetScript("OnEnterPressed",
		function(this)
			local result = self:UpdateItem(frame.item:GetText(), frame.num:GetText())
			if result then
				frame.item:SetText('')
				frame.num:SetText('')
				self:updateScrollList()
				self:PopulateTrackerFrame()
				self:PopulateNewTracker()
				if (not IsShiftKeyDown()) then
					frame:Hide()
				end
			else
				UIErrorsFrame:AddMessage(L['LootTracker: Invalid item entered.'])
			end
		end )
	frame:SetScript("OnHide", function(this)
				frame.item:SetText('')
				frame.num:SetText('')
			end )
	frame.cancel:SetScript("OnClick",function(this) frame:Hide() end)
	frame.item:SetScript("OnEscapePressed", function(this) frame:Hide() end)
	frame.ok:SetScript("OnClick",
		function(this)
			local result = self:UpdateItem(frame.item:GetText(), frame.num:GetText())
			if result then
				frame.item:SetText('')
				frame.num:SetText('')
				self:updateScrollList()
				self:PopulateTrackerFrame()
				self:PopulateNewTracker()
				if (not IsShiftKeyDown()) then
					frame:Hide()
				end
			else
				UIErrorsFrame:AddMessage('LootTracker: Invalid item entered.')
			end
		end )
	frame:SetPoint('CENTER')
	self.inputItemFrame = frame
end

-- idea (and most of the code) taken from KC_Items2
function LootTracker:CreateButton(parent, width, height, text, ...)
	local button = CreateFrame('Button', nil, parent, 'OptionsButtonTemplate')
    button:SetWidth(width)
    button:SetHeight(height)

    button:SetFont("Fonts\\FRIZQT__.TTF", 12)
    --button:SetTextColor(1,1,1)
    button:SetText(text)

    if select("#",...) > 0 then button:SetPoint(...) end

    return button
end

function LootTracker:ShowTracker()
	_db.profile.tracker.old.shown = true
	if (not self.oldTracker) then
		self:CreateTrackerFrame()
		if (_db.profile.tracker.old.lock) then
			self.oldTracker:SetBackdropBorderColor(24/255, 24/255, 24/255, 0)
			self.oldTracker:EnableMouse(false)
		end
	end
	self.oldTracker:Show()
	self.oldTracker:SetOwner(UIParent, "ANCHOR_NONE")
	self.oldTracker:SetScale(_db.profile.tracker.old.scale)
	self.oldTracker:SetAlpha(_db.profile.tracker.old.alpha)
	self:PopulateTrackerFrame()
end

function LootTracker:ToggleConfig()
	OH:Open("LootTracker")
end

function LootTracker:ToggleTracker()
	if (LootTrackerTrackingFrame) then
		if (LootTrackerTrackingFrame:IsVisible()) then
			LootTrackerTrackingFrame:Hide()
			return
		end
	end
	LootTracker:ShowTracker()
end

function LootTracker:ShowSetInputFrame(text)
	if (not self.inputSetFrame) then
		self:CreateSetInputFrame()
	end
	if (text) then
		self.inputSetFrame.editBox:SetText(text)
	end
	self.inputSetFrame:Show()
end

function LootTracker:ShowItemInputFrame(text, count)
	if (not self.inputItemFrame) then
		self:CreateItemInputFrame()
	end
	if (text) then
		self.inputItemFrame.item:SetText(text)
	end
	if (count) then
		self.inputItemFrame.num:SetText(count)
	end
	self.inputItemFrame:Show()
end

-- follwing bit of code taken from tablet-2.0.  credit goes to them
local getLine, freeLine
do
	local tinsert, tremove = table.insert, table.remove
	local textures = {}
	getLine = function(parent)
		local t = tremove(textures)
		if (not t) then
			t = parent:CreateFontString(nil, 'ARTWORK')
			t:SetFontObject(GameTooltipText)
		end
		t:Show()
		t:SetParent(parent)
		return t
	end
	freeLine = function(t)
		t:SetText('')
		t:SetParent(UIParent)
		t:Hide()
		tinsert(textures, t)
	end
end

function LootTracker:AddLineToTracker(text, r, g, b)
	local frame = self.oldTracker
	local prev = frame.prev
	local offset = frame.offset or 1
	local line = frame.lines[offset] or getLine(frame)
	frame.lines[offset] = line
	if (prev and prev ~= line) then
		line:SetPoint('TOPLEFT', prev, 'BOTTOMLEFT')
	else
		line:SetPoint('TOPLEFT', frame, 'TOPLEFT', 6, -5)
	end
	line:SetText(text)
	line:SetTextColor(r, g, b)
	line:Show()
	frame.offset = offset + 1
	frame.prev = line
end

function LootTracker:PopulateTrackerFrame()
	local tracked = _db.profile.trackedLists
	local lists = _db.global.lists
	local options = _db.profile.tracker.old
	local list, items, name, item
	local tip = self.oldTracker
	local text
	local count
	if (not tip) then return end -- jump out if we aren't showing anything
	if (not options.shown) then tip:Hide() return end -- it's hidden, don't show it
	tip:ClearLines()
	local hideifnone = _db.profile.tracker.hideifnone
	local hideincomplete = _db.profile.tracker.hideincomplete
	local hidecomplete = _db.profile.tracker.hidecomplete
	local squish = options.squish
	local continue
	--tip:SetScale(options.scale)
	if (options.lock) then
		tip:SetBackdropBorderColor(24/255, 24/255, 24/255, 0)
		tip:EnableMouse(false)
	end
	tip:AddLine("LootTracker", 0.75, 0.61, 0)
	for i=1, #tracked do
		list = tracked[i]
		tip:AddLine(list, 0.75, 0.61, 0)
		items = lists[list]
		for j=1, #items do
			continue = false
			name = items[j]
			count = self:GetItemCount(name)
			if hideifnone and count == 0 then
				continue = true
			end
			if (items[name]) then
				if hideincomplete and count < tonumber(items[name]) then continue = true end
				if hidecomplete and count >= tonumber(items[name]) then continue = true end
				text = string.format("%d/%d", count, items[name])
			else
				text = count
			end
			if not continue then
				if (squish) then
					text = string.format(" - %s: %s", name or 'name', text or 'text')
					tip:AddLine(text, 0.8, 0.8, 0.8)
				else
					tip:AddDoubleLine(' - '..name..':', text, 0.8, 0.8, 0.8)
				end
			end
		end
	end
	tip:Show()
	local r, g, b = tip:GetBackdropColor()
	tip:SetBackdropColor(r, g, b, options.alpha)
	self:RestorePosition(tip:GetName())
end

--[[ all new stuff ]]--

function LootTracker:IsSetCollapsed(set)
	return _db.profile.tracker.collapsed[set]
end

function LootTracker:CollapseSet(set, collapse)
	_db.profile.tracker.collapsed[set] = collapse
end

function LootTracker:ToggleCollapsedSet(set)
	_db.profile.tracker.collapsed[set] = not _db.profile.tracker.collapsed[set]
end

function LootTracker:CreateNewTracker()
	if (self.newTracker) then return end
	local tooltip = ClickTip:GetTip("LTAdvancedTracker", UIParent)
	tooltip:EnableMouse(true)
	tooltip:SetMovable(true)
	tooltip:SetScript("OnMouseDown",function(this, button) this:StartMoving() end)
	tooltip:SetScript("OnMouseUp",function() self:SavePosition(tooltip:GetName()); tooltip:StopMovingOrSizing() end)
	self.newTracker = tooltip
	tooltip:SetScript("OnShow", function() self:PopulateNewTracker() end)
	tooltip:SetClampedToScreen(true)
	return tooltip
end

local clickers = {
	SetClicker = function(set)
		if (set) then
			LootTracker:ToggleCollapsedSet(set)
			LootTracker:PopulateNewTracker()
		end
	end,
	--ItemClicker = function() return end,
}

local function ClickHandler(line, button)
	local f = line.ltType
	local func = clickers[f]
	if (func and type(func) == "function") then
		func(line.ltParam)
	else
		-- clicked on a item
		--ChatFrame1:AddMessage("Clicked!")
	end
end

function LootTracker:ShowNewTracker()
	_db.profile.tracker.new.shown = true
	if (not self.newTracker) then
		self:CreateNewTracker()
		if (_db.profile.tracker.new.lock) then
			self.newTracker:SetBackdropBorderColor(24/255, 24/255, 24/255, 0)
			self.newTracker:EnableMouse(false)
		end
	end
	self.newTracker:Show()
	self.newTracker:SetScale(_db.profile.tracker.new.scale)
	self.newTracker:SetAlpha(_db.profile.tracker.new.alpha)
	self:PopulateNewTracker()
end
local tipLines = {}
function LootTracker:PopulateNewTracker()
	local tracked = _db.profile.trackedLists
	local lists = _db.global.lists
	local options = _db.profile.tracker
	local list, items, name, item
	local tip = self.newTracker
	local text
	local cLineN = 1
	local collapsed
	if (not tip) then return end -- jump out if we aren't showing anything
	if (not options.new.shown) then tip:Hide() return end -- it's hidden, don't show it
	local squish = options.new.squish
	local hideifnone = options.hideifnone
	local hideincomplete = options.hideincomplete
	tip:SetScale(options.new.scale)
	if (options.new.lock) then
		tip:SetBackdropBorderColor(24/255, 24/255, 24/255, 0)
		tip:EnableMouse(false)
	end
	local line, entries = tip:GetLine(cLineN)
	if (entries and entries > 1) then
		tip:ChangeLine(line, 1)
		tip:ChangeEntry(line, 1, "LootTracker", 0.75, 0.61, 0, GameTooltipHeaderText)
	elseif (entries) then
		tip:ChangeEntry(line, 1, "LootTracker", 0.75, 0.61, 0, GameTooltipHeaderText)
	else
		line = tip:AddLine("LootTracker", 0.75, 0.61, 0, GameTooltipHeaderText)
	end
	line:EnableMouse(nil)
	cLineN = cLineN + 1
	for i=1, #tracked do
		list = tracked[i]
		line, entries = tip:GetLine(cLineN)
		collapsed = self:IsSetCollapsed(list)
		text = (collapsed and "+ " or "- ") .. list
		if (entries) then
			if (entries > 1) then
				tip:ChangeLine(line, 1)
				tip:ChangeEntry(line, 1, text, 0.75, 0.61, 0, GameTooltipText)
			else
				tip:ChangeEntry(line, 1, text, 0.75, 0.61, 0, GameTooltipText)
			end
		else
			line = tip:AddLine(text, 0.75, 0.61, 0, GameTooltipText)
			line:SetScript("OnClick", ClickHandler)
			line:SetMovable(true)
			line:RegisterForDrag('LeftButton')
			line:SetScript('OnDragStart', function(this, button) tip:StartMoving() end)
			line:SetScript('OnDragStop', function(this) self:SavePosition(tip:GetName()); tip:StopMovingOrSizing() end)
		end
		line.ltType = "SetClicker"
		line.ltParam = list
		line:EnableMouse(true)
		cLineN = cLineN + 1
		if (not collapsed) then
			items = lists[list]
			for j=1, #items do
				local continue = false
				line, entries = tip:GetLine(cLineN)
				name = items[j]
				local count = self:GetItemCount(name)
				if hideifnone and count == 0 then continue = true end
				if (items[name]) then
					if hideincomplete and count < tonumber(items[name]) then continue = true end
					text = string.format("%d/%d", count, items[name])
				else
					text = count
				end
				if not continue then
					if (squish) then
						text = string.format(" - %s: %s", name or 'name', text or 'text')
						if (entries) then
							if (entries > 1) then
								tip:ChangeLine(line, 1)
								tip:ChangeEntry(line, 1, text, nil, nil, nil, GameTooltipText)
							else
								tip:ChangeEntry(line, 1, text, nil, nil, nil, GameTooltipText)
							end
						else
							line = tip:AddLine(text, nil, nil, nil, GameTooltipText)
							line:SetScript("OnClick", ClickHandler)
							line:EnableMouse(true)
						end
					else
						if (entries) then
							if (entries ~= 2) then
								tip:ChangeLine(line, 2)
								tip:ChangeEntry(line, 1, ' - '..name..':', 0.8, 0.8, 0.8, GameTooltipText)
								tip:ChangeEntry(line, 2, text, 0.75, 0.61, 0, GameTooltipText)
							else
								tip:ChangeEntry(line, 1, ' - '..name..':', 0.8, 0.8, 0.8, GameTooltipText)
								tip:ChangeEntry(line, 2, text, 0.75, 0.61, 0, GameTooltipText)
							end
						else
							line = tip:AddDoubleLine(' - '..name..':', text, 0.8, 0.8, 0.8, 0.75, 0.61, 0, GameTooltipText, GameTooltipText)
							line:SetScript("OnClick", ClickHandler)
							line:SetMovable(true)
							line:RegisterForDrag('LeftButton')
							line:SetScript('OnDragStart', function(this, button) tip:StartMoving() end)
							line:SetScript('OnDragStop', function(this) self:SavePosition(tip:GetName()); tip:StopMovingOrSizing() end)
						end
					end
					line.ltType = "ItemClicker"
					line.ltParam = name
					cLineN = cLineN + 1
				end
			end
		end
	end
	tip:ClearLines(cLineN)
	tip:Show()
	local r, g, b = tip:GetBackdropColor()
	tip:SetBackdropColor(r, g, b, options.alpha)
	self:RestorePosition(tip:GetName())
end

--[[ OH Frame stuff]]--
--[[ frame generalization stuff ]]--
-- for the tooltip stuff
local RegisterCheckOption, RegisterSliderOption
do
	local helps = {} -- for storing help stuff
	-- timeout is how long before we forget we were showing, timeToShow is how
	-- long before we actually show, these values seem fairly sane
	local timeOut, timeToShow = 2.0, 0.5
	local totalElapsed, showTooltip, state = 0
	local onUpdate = function(frame, elapsed)
		totalElapsed = totalElapsed + elapsed
		if showTooltip then
			if totalElapsed > timeToShow and state == 1 then -- actually show stuff
				helps[showTooltip](showTooltip)
				state = 2
				totalElapsed = 0
			end
			if totalElapsed < timeOut and state == 2 then -- we need to reshow the tooltip quickly
				helps[showTooltip](showTooltip)
				state = 2
				totalElapsed = 0
			end
		else
			if totalElapsed > timeOut then -- reset our timeout
				state = 1
				visFrame:SetScript("OnUpdate", nil)
			end
		end
	end
	local registerHelp = function(frame, helpFunc)
		helps[frame] = helpFunc
	end
	local showHelp = function(frame)
		showTooltip = frame
		totalElapsed = 0
		if state ~= 2 then state = 1 end
		if visFrame then
			visFrame:SetScript("OnUpdate", onUpdate)
		end
	end
	local hideHelp = function()
		totalElapsed = 0
		showTooltip = nil
		state = 2
		GameTooltip:Hide()
	end
	RegisterCheckOption = function(frame, get, set, help)
		frame:SetScript("OnClick", function(self) set(self:GetChecked() or false) end )
		frame:SetScript("OnShow", function(self) self:SetChecked(get()) end )
		if help then
			registerHelp(frame, help)
			frame:SetScript("OnEnter", showHelp)
			frame:SetScript("OnLeave", hideHelp)
		end
	end
	RegisterSliderOption = function(frame, get, set, help)
		frame:SetScript("OnValueChanged", function(self) set(self:GetValue()) end )
		frame:SetScript("OnShow", function(self) self:SetValue(get()) end )
		if help then
			registerHelp(frame, help)
			frame:SetScript("OnEnter", showHelp)
			frame:SetScript("OnLeave", hideHelp)
		end
	end
end

local function CreateCheckButton(par)
	local f = CreateFrame('CheckButton', nil, par)
	f:SetHeight(32)
	f:SetWidth(32)
	f.text = f:CreateFontString(nil, nil, "GameFontNormalSmall")
	f.text:SetPoint("LEFT", f, "RIGHT", -2, 0)
	local t = f:CreateTexture()
	f:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	f:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	f:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
	f:GetHighlightTexture():SetBlendMode("ADD")
	f:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	f:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disable")
	f:SetHitRectInsets(0, -100, 0, 0)
	f:SetScript("OnEnter", function(self)
		if self.tooltipText then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(this.tooltipText, nil, nil, nil, nil, 1)
		end
		if self.tooltipRequirement then
			GameTooltip:AddLine(this.tooltipRequirement, "", 1.0, 1.0, 1.0)
			GameTooltip:Show()
		end
	end )
	f:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
	return f
end

local bg = {
	bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
	edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
	tile = true,
	tileSize = 8,
	edgeSize = 8,
	insets = { left = 3, right = 3, top = 6, bottom = 6 }
}
local function CreateSlider(par)
	local f = CreateFrame('Slider', nil, par)
	f:SetBackdrop(bg)
	f:SetWidth(128)
	f:SetHeight(17)
	f:SetOrientation("HORIZONTAL")
	f:SetHitRectInsets(0, 0, -10, -10)
	local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	fs:SetPoint('BOTTOM', f, "TOP", 0, 2)
	f.text = fs
	fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, 3)
	f.low = fs
	fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -2, 3)
	f.high = fs
	local text = f:CreateTexture()
	text:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	text:SetHeight(32)
	text:SetWidth(32)
	f:SetThumbTexture(text)
	f.thumb = text
	f:SetScript("OnEnter", function(self)
		if self.tooltipText then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(this.tooltipText, nil, nil, nil, nil, 1)
		end
		if self.tooltipRequirement then
			GameTooltip:AddLine(this.tooltipRequirement, "", 1.0, 1.0, 1.0)
			GameTooltip:Show()
		end
	end )
	f:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
	return f
end

local boxBG = {
	--bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", --options frame background
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground", -- kc_linkview frame background
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 }
}

function LootTracker:CreateRandomConfigs()
	local frame = CreateFrame('Frame', nil, OH:GetFrame("addon"))
	frame:Show()
	visFrame = frame
	local options = _db.profile
	local box, check, slider

	box = CreateFrame('Frame', nil, frame)
	box:SetBackdrop(boxBG)
	box:SetBackdropBorderColor(0.4, 0.4, 0.4)
	box:SetBackdropColor(24/255, 24/255, 24/255)
	box:SetHeight(80)
	box:SetWidth(10)
	box:SetPoint("TOPLEFT", 5, -15)
	box:SetPoint("TOPRIGHT", frame, -5, -15)
	box.title = box:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
	box.title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 9, 0)
	box.title:SetText(L["Standard Tracker Options"])
	self.oldTrackerBox = box

	check = CreateCheckButton(box)
	check:SetPoint("TOPLEFT", 5, -5)
	check.text:SetText(L["Show normal tracker"])
	RegisterCheckOption(check, function() return options.tracker.old.shown end,
		function(val)
			options.tracker.old.shown = val
			if val then self:ShowTracker() elseif self.oldTracker then self.oldTracker:Hide() end
		end, function(this)
			GameTooltip:SetOwner(this, "ANCHOR_LEFT")
			if this:GetChecked() then
				GameTooltip:SetText(L['Use this checkbox to hide the normal tracker'])
			else
				GameTooltip:SetText(L['Use this checkbox to show the normal tracker'])
			end
			GameTooltip:Show()
		end)
	self.showOldTracker = check

	check = CreateCheckButton(frame)
	check:SetPoint("TOPLEFT", self.showOldTracker, "TOPRIGHT", 200, 0)
	check.text:SetText(L["Hide in combat"])
	RegisterCheckOption(check, function() return options.tracker.old.combatHidden end,
		function(val)
			options.tracker.old.combatHidden = val
			if val and InCombatLockdown() and self.oldTracker then
				self.oldTracker:Hide()
			end
		end, function(this)
			GameTooltip:SetOwner(this, "ANCHOR_LEFT")
			GameTooltip:SetText(L['Hide in combat'])
			if this:GetChecked() then
				GameTooltip:AddLine(L['Use this checkbox to show the tracker while in combat'], nil, nil, nil, 1)
			else
				GameTooltip:AddLine(L['Use this checkbox to hide the tracker while in combat'], nil, nil, nil, 1)
			end
			GameTooltip:Show()
		end )
	self.hideInCombatOld = check

	check = CreateCheckButton(frame)
	check:SetPoint("TOPLEFT", self.hideInCombatOld, "TOPRIGHT", 200, 0)
	check.text:SetText(L["Lock Tracker"])
	RegisterCheckOption(check, function() return options.tracker.old.lock end,
	    function(val)
			options.tracker.old.lock = val
			if self.oldTracker then
				self.oldTracker:SetBackdropBorderColor(24/255, 24/255, 24/255, options.tracker.old.lock and 0 or 1)
				self.oldTracker:EnableMouse(not options.tracker.old.lock)
			end
		end, function(this)
			GameTooltip:SetOwner(this, "ANCHOR_LEFT")
			GameTooltip:SetText(L['Lock Tracker'])
			GameTooltip:AddLine()
			if this:GetChecked() then
				GameTooltip:AddLine(L['Use this checkbox to unlock the tracker'], nil, nil, nil, 1)
			else
				GameTooltip:AddLine(L['Use this checkbox to lock the tracker in its current position'], nil, nil, nil, 1)
			end
			GameTooltip:Show()
		end )
	self.lockOldTracker = check

	check = CreateCheckButton(frame)
	check:SetPoint("TOPLEFT", self.showOldTracker, "BOTTOMLEFT", 0, 0)
	check.text:SetText(L["Squish numbers to name"])
	RegisterCheckOption(check, function() return options.tracker.old.squish end,
		function(val)
			options.tracker.old.squish = val
			self:PopulateTrackerFrame()
			self:PopulateNewTracker()
		end, function(this)
			GameTooltip:SetOwner(this, "ANCHOR_LEFT")
			GameTooltip:SetText(L['Squish numbers to name'])
			GameTooltip:AddLine()
			if this:GetChecked() then
				GameTooltip:AddLine(L['Use this checkbox to separate item counts from the item name'], nil, nil, nil, 1)
			else
				GameTooltip:AddLine(L['Use this checkbox to force item counts next to the item name'], nil, nil, nil, 1)
			end
			GameTooltip:Show()
		end )
	self.squishOld = check

	slider = CreateSlider(frame)
	slider:SetPoint("TOPLEFT", self.squishOld, "TOPRIGHT", 200, -10)
	slider.text:SetText(L["Background Alpha"])
	slider.low:SetText(0)
	slider.high:SetText(100)
	slider:SetMinMaxValues(0, 100)
	slider:SetValueStep(5)
	RegisterSliderOption(slider, function() return options.tracker.old.alpha*100 end, function(val)
		local alpha = val/100
		options.tracker.old.alpha = alpha
		if self.oldTracker then
			local r, g, b = self.oldTracker:GetBackdropColor()
			self.oldTracker:SetBackdropColor(r, g, b, alpha)
			r, g, b = self.oldTracker:GetBackdropBorderColor()
			self.oldTracker:SetBackdropBorderColor(r, g, b, alpha)
		end
	end, function()
		GameTooltip:SetOwner(slider, "ANCHOR_LEFT")
		GameTooltip:SetText(L['Background Alpha'])
		GameTooltip:AddLine()
		GameTooltip:AddLine(L['Use this slider to change the transparency of the background for the tracker'], nil, nil, nil, 1)
		GameTooltip:Show()
	end)
	self.alphaOld = slider

	--[[slider = CreateSlider(frame)
	slider:SetPoint("TOPLEFT", self.alphaOld, "TOPRIGHT", 108, 0)
	slider.text:SetText(L["Scale"])
	slider.low:SetText(1)
	slider.high:SetText(200)
	slider:SetMinMaxValues(1, 200)
	slider:SetValueStep(20)
	RegisterSliderOption(slider, function() return options.tracker.old.scale*100 end, function(val)
		scale = val/100
		options.tracker.old.scale = scale
		if self.oldTracker then
			self:SavePosition('LootTrackerTrackingFrame')
			self.oldTracker:SetScale(scale)
			self:RestorePosition('LootTrackerTrackingFrame')
		end
	end)
	self.scaleOld = slider]]--

	if ClickTip then
		box = CreateFrame('Frame', nil, frame)
		box:SetBackdrop(boxBG)
		box:SetBackdropBorderColor(0.4, 0.4, 0.4)
		box:SetBackdropColor(24/255, 24/255, 24/255)
		box:SetHeight(80)
		box:SetWidth(10)
		box:SetPoint("TOPLEFT", self.oldTrackerBox, "BOTTOMLEFT", 0, -15)
		box:SetPoint("TOPRIGHT", self.oldTrackerBox, "BOTTOMRIGHT", 0, -15)
		box.title = box:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
		box.title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 9, 0)
		box.title:SetText(L["Advanced Tracker Options"])
		self.newTrackerBox = box

		check = CreateCheckButton(box)
		check:SetPoint("TOPLEFT", 5, -5)
		check.text:SetText(L["Show advanced tracker"])
		RegisterCheckOption(check, function() return options.tracker.new.shown end,
			function(val)
				options.tracker.new.shown = val
				if val then self:ShowNewTracker() elseif self.newTracker then self.newTracker:Hide() end
			end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				if this:GetChecked() then
					GameTooltip:SetText(L['Use this checkbox to hide the advanced tracker'])
				else
					GameTooltip:SetText(L['Use this checkbox to show the advanced tracker'])
				end
				GameTooltip:Show()
			end)
		self.showNewTracker = check

		check = CreateCheckButton(frame)
		check:SetPoint("TOPLEFT", self.showNewTracker, "TOPRIGHT", 200, 0)
		check.text:SetText(L["Hide in combat"])
		RegisterCheckOption(check, function() return options.tracker.new.combatHidden end,
			function(val)
				options.tracker.new.combatHidden = val
				if val and InCombatLockdown() and self.newTracker then
					self.newTracker:Hide()
				end
			end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Hide in combat'])
				if this:GetChecked() then
					GameTooltip:AddLine(L['Use this checkbox to show the tracker while in combat'], nil, nil, nil, 1)
				else
					GameTooltip:AddLine(L['Use this checkbox to hide the tracker while in combat'], nil, nil, nil, 1)
				end
				GameTooltip:Show()
			end )
		self.hideInCombatNew = check

		check = CreateCheckButton(frame)
		check:SetPoint("TOPLEFT", self.hideInCombatNew, "TOPRIGHT", 200, 0)
		check.text:SetText(L["Lock advanced tracker"])
		RegisterCheckOption(check, function() return options.tracker.new.lock end,
			function(val)
				options.tracker.new.lock = val
				if self.newTracker then
					self.newTracker:SetBackdropBorderColor(24/255, 24/255, 24/255, options.tracker.new.lock and 0 or 1)
					self.newTracker:EnableMouse(not options.tracker.new.lock)
				end
			end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Lock Tracker'])
				GameTooltip:AddLine()
				if this:GetChecked() then
					GameTooltip:AddLine(L['Use this checkbox to unlock the tracker'], nil, nil, nil, 1)
				else
					GameTooltip:AddLine(L['Use this checkbox to lock the tracker in its current position'], nil, nil, nil, 1)
				end
				GameTooltip:Show()
			end )
		self.lockNewTracker = check

		check = CreateCheckButton(frame)
		check:SetPoint("TOPLEFT", self.showNewTracker, "BOTTOMLEFT", 0, 0)
		check.text:SetText(L["Squish numbers to name"])
		RegisterCheckOption(check, function() return options.tracker.new.squish end,
			function(val)
				options.tracker.new.squish = val
				self:PopulateTrackerFrame()
				self:PopulateNewTracker()
			end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Squish numbers to name'])
				GameTooltip:AddLine()
				if this:GetChecked() then
					GameTooltip:AddLine(L['Use this checkbox to separate item counts from the item name'], nil, nil, nil, 1)
				else
					GameTooltip:AddLine(L['Use this checkbox to force item counts next to the item name'], nil, nil, nil, 1)
				end
				GameTooltip:Show()
			end )
		self.squishNew = check

		slider = CreateSlider(frame)
		slider:SetPoint("TOPLEFT", self.squishNew, "TOPRIGHT", 200, -10)
		slider.text:SetText(L["Background Alpha"])
		slider.low:SetText(0)
		slider.high:SetText(100)
		slider:SetMinMaxValues(0, 100)
		slider:SetValueStep(5)
		RegisterSliderOption(slider, function() return options.tracker.new.alpha*100 end,
			function(val)
				local alpha = val/100
				options.tracker.new.alpha = alpha
				if self.newTracker then
					local r, g, b = self.newTracker:GetBackdropColor()
					self.newTracker:SetBackdropColor(r, g, b, alpha)
					r, g, b = self.newTracker:GetBackdropBorderColor()
					self.newTracker:SetBackdropBorderColor(r, g, b, alpha)
				end
			end, function()
				GameTooltip:SetOwner(slider, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Background Alpha'])
				GameTooltip:AddLine()
				GameTooltip:AddLine(L['Use this slider to change the transparency of the background for the tracker'], nil, nil, nil, 1)
				GameTooltip:Show()
			end)
		self.alphaNew = slider

		--[[slider = CreateSlider(frame)
		slider:SetPoint("TOPLEFT", self.alphaOld, "TOPRIGHT", 108, 0)
		slider.text:SetText(L["Scale"])
		slider.low:SetText(1)
		slider.high:SetText(200)
		slider:SetMinMaxValues(1, 200)
		slider:SetValueStep(20)
		RegisterSliderOption(slider, function() return options.tracker.old.scale*100 end, function(val)
			scale = val/100
			options.tracker.old.scale = scale
			if self.oldTracker then
				self:SavePosition('LootTrackerTrackingFrame')
				self.oldTracker:SetScale(scale)
				self:RestorePosition('LootTrackerTrackingFrame')
			end
		end)
		self.scaleOld = slider]]--
	end

	box = CreateFrame('Frame', nil, frame)
	box:SetBackdrop(boxBG)
	box:SetBackdropBorderColor(0.4, 0.4, 0.4)
	box:SetBackdropColor(24/255, 24/255, 24/255)
	box:SetHeight(80)
	box:SetWidth(10)
	box:SetPoint("TOPLEFT", self.newTrackerBox or self.oldTrackerBox, "BOTTOMLEFT", 0, -15)
	box:SetPoint("TOPRIGHT", self.newTrackerBox or self.oldTrackerBox, "BOTTOMRIGHT", 0, -15)
	box.title = box:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
	box.title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 9, 0)
	box.title:SetText(L["Global Tracker Options"])
	self.newTrackerBox = box

	check = CreateCheckButton(box)
	check:SetPoint("TOPLEFT", 5, -5)
	check.text:SetText(L["Hide if no items available"])
	RegisterCheckOption(check, function() return options.tracker.hideifnone end,
		function(val)
			options.tracker.hideifnone = val
			self:PopulateTrackerFrame()
			self:PopulateNewTracker()
		end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Hide if no items available'])
				GameTooltip:AddLine()
				if this:GetChecked() then
					GameTooltip:AddLine(L['Use this checkbox to show the item in the tracker even if there are no items available'], nil, nil, nil, 1)
				else
					GameTooltip:AddLine(L['Use this checkbox to hide the item in the tracker if there are no items available'], nil, nil, nil, 1)
				end
				GameTooltip:Show()
		end)
	self.hideIfNone = check

	check = CreateCheckButton(box)
	check:SetPoint("TOPLEFT", self.hideIfNone, "BOTTOMLEFT", 0, 0)
	check.text:SetText(L["Hide if incomplete"])
	RegisterCheckOption(check, function() return options.tracker.hideincomplete end,
		function(val)
			options.tracker.hideincomplete = val
			self:PopulateTrackerFrame()
			self:PopulateNewTracker()
		end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Hide if incomplete'])
				GameTooltip:AddLine()
				if this:GetChecked() then
					GameTooltip:AddLine(L['Use this checkbox to show the item in the tracker even if the goal has not been met'], nil, nil, nil, 1)
				else
					GameTooltip:AddLine(L['Use this checkbox to hide the item in the tracker if the goal has not been met'], nil, nil, nil, 1)
				end
				GameTooltip:Show()
		end)
	self.hideIncomplete = check

	check = CreateCheckButton(box)
	check:SetPoint("TOPLEFT", 5, -5)
	check.text:SetText(L["Current toon count only"])
	check:SetPoint("TOPLEFT", self.hideIfNone, "TOPRIGHT", 200, 0)
	RegisterCheckOption(check, function() return options.tracker.ctc end,
		function(val)
			options.tracker.ctc = val
			self:PopulateTrackerFrame()
			self:PopulateNewTracker()
		end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Current toon count only'])
				GameTooltip:AddLine()
				if this:GetChecked() then
					GameTooltip:AddLine(L['Use this checkbox to show item totals from all toons'], nil, nil, nil, 1)
				else
					GameTooltip:AddLine(L['Use this checkbox to only show item totals from current toon'], nil, nil, nil, 1)
				end
				GameTooltip:Show()
		end)
	self.currentToonCount = check

	check = CreateCheckButton(box)
	check:SetPoint("TOPLEFT", self.currentToonCount, "BOTTOMLEFT", 0, 0)
	check.text:SetText(L["Hide if complete"])
	RegisterCheckOption(check, function() return options.tracker.hidecomplete end,
		function(val)
			options.tracker.hidecomplete = val
			self:PopulateTrackerFrame()
			self:PopulateNewTracker()
		end, function(this)
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				GameTooltip:SetText(L['Hide complete'])
				GameTooltip:AddLine()
				if this:GetChecked() then
					GameTooltip:AddLine(L['Use this checkbox to show the item in the tracker only if the goal has not been met'], nil, nil, nil, 1)
				else
					GameTooltip:AddLine(L['Use this checkbox to hide the item in the tracker only if the goal has been met'], nil, nil, nil, 1)
				end
				GameTooltip:Show()
		end)
	self.hidecomplete = check

	return frame
end

local function updateTextures(show)
	for i = 1, #configFrame.rows do
		local button = configFrame.rows[i]
		if show then
			button.item:Show()
			button.left:ClearAllPoints()
			button.left:SetPoint('LEFT', button, 'LEFT', 34, 2)
			--button.highlight:ClearAllPoints()
			button.highlight:SetPoint('TOPLEFT', button, 'TOPLEFT', 33, 0)
			button.name:ClearAllPoints()
			button.name:SetPoint("TOPLEFT", button, "TOPLEFT", 43, 0)
			button.count:SetText('Item')
			button.count:Show()
		else
			button.item:Hide()
			button.left:ClearAllPoints()
			button.left:SetPoint('LEFT', button, 'LEFT', 2, 2)
			--button.highlight:ClearAllPoints()
			button.highlight:SetPoint('TOPLEFT', button, 'TOPLEFT', 1, 0)
			button.name:ClearAllPoints()
			button.name:SetPoint("TOPLEFT", button, "TOPLEFT", 9, 0)
			button.count:SetText('')
			button.count:Hide()
		end
	end
end

local function updateButtons()
	if not configFrame.curBtn then
		configFrame.RemoveX:Disable()
		configFrame.EditX:Disable()
	else
		configFrame.RemoveX:Enable()
		configFrame.EditX:Enable()
	end
end

local function trackList(row)
	local button = configFrame.rows[row]
	local set = _db.global.lists[button.index]
	local added = LootTracker:ToggleTrackSet(set)
	LootTracker:PopulateTrackerFrame()
	LootTracker:PopulateNewTracker()
	if (added) then
		button.check:Show()
		button.check:ClearAllPoints()
		button.check:SetPoint("LEFT", button, 'LEFT', button.name:GetStringWidth()+24, 0)
	else
		button.check:Hide()
	end
end

local function onLeave() GameTooltip:Hide() end

local function onEnter(this)
	if this.link then
		if this.link ~= true then
			GameTooltip:SetOwner(this,"ANCHOR_LEFT")
			GameTooltip:SetHyperlink(this.link)
			LootTracker:AddToTip(this.itemName)
			GameTooltip:Show()
		else
			GameTooltip:SetOwner(this,"ANCHOR_LEFT")
			GameTooltip:SetText(this.name:GetText())
			LootTracker:AddToTip(this.itemName)
			GameTooltip:Show()
		end
	elseif this.itemName then
		GameTooltip:SetOwner(this,"ANCHOR_LEFT")
		LootTracker:AddToTip(this.itemName)
		GameTooltip:Show()
	else -- it is a set, add the number of items
		local set = _db.global.lists[this.index]
		local items = _db.global.lists[set]
		local numItems = items and #items or 0
		GameTooltip:SetOwner(this,"ANCHOR_LEFT")
		GameTooltip:SetText(set)
		local name, link, rarity, level, minlevel, itype, subtype, stackCount, equipLoc, text
		local item, itemID
		for i=1, numItems do
			item = items[i]
			itemID = LootTracker:GetItemID(item)
			name, link, rarity, level, minlevel, itype, subtype, stackCount, equipLoc, text = GetItemInfo(itemID)
			if (items[name]) then
				GameTooltip:AddDoubleLine(name or item, string.format("%d/%d", LootTracker:GetItemCount(name), items[name]))
			else
				GameTooltip:AddDoubleLine(name or item, LootTracker:GetItemCount(name))
			end
		end
		GameTooltip:AddLine()
		if (LootTracker:IsSetTracked(set)) then
			GameTooltip:AddLine(L["Hint:  Shift click to remove from tracker"], 0, 1, 0, 1)
		else
			GameTooltip:AddLine(L["Hint:  Shift click to add to tracker"], 0, 1, 0, 1)
		end
		GameTooltip:Show()
	end
end

local function updateHighlights(clickedRow, reset)
	if reset and configFrame.curBtn then
		configFrame.curBtn:UnlockHighlight()
		configFrame.curBtn = nil
	end

	if clickedRow then
		local button = configFrame.rows[clickedRow]
		if button == configFrame.curBtn then
			button:UnlockHighlight()
			configFrame.curBtn = nil
		else
			if configFrame.curBtn then configFrame.curBtn:UnlockHighlight() end
			configFrame.curBtn = button
			button:LockHighlight()
		end
		selectedLine = button.index
	end
	updateButtons()
end

function LootTracker:updateScrollList(resetHighlights)
	local scrollFrame = configFrame.scroll
	local itemID
	if resetHighlights then updateHighlights(nil, true) end
	if not currentSet then
		local sets, numSets = _db.global.lists
		local offset = FauxScrollFrame_GetOffset(scrollFrame)
		numSets = #sets
		local resize = numSets <= 8
		local buttons, maxButtons = configFrame.rows, #configFrame.rows
		FauxScrollFrame_Update(scrollFrame, numSets, maxButtons, scrollFrame.buttonHeight)
		local i, j, button
		for i=1,maxButtons do
			j=i + offset
			button = buttons[i]
			button.link = nil
			button.itemName = nil
			if j <= numSets then
				button.name:SetText(sets[j])
				if (self:IsSetTracked(sets[j])) then
					button.check:SetPoint('LEFT', button, 'LEFT', button.name:GetStringWidth()+24,0)
					button.check:Show()
				else
					button.check:Hide()
				end
				if resize then
					button:SetWidth(625)
				else
					button:SetWidth(600)
				end
				button:Show()
				button.index = j
				if j == selectedLine then
					button:LockHighlight()
					configFrame.curBtn = button
				end
			else
				button.index = nil
				button:SetText('')
				button:Hide()
			end
		end
	else
		local buttons, maxButtons = configFrame.rows, #configFrame.rows
		local highlights = scrollFrame.highlights
		local numItems, items = 0
		items = _db.global.lists[currentSet]
		if (items) then numItems = #items end
		local resize = numItems <= 8
		FauxScrollFrame_Update(scrollFrame, numItems, maxButtons, scrollFrame.buttonHeight)
		local i, j, item, link, name, itemID
		local name, link, rarity, level, minlevel, itype, subtype, stackCount, equipLoc, text
		local offset = FauxScrollFrame_GetOffset(scrollFrame)
		local button
		for i=1,maxButtons do
			j=i + offset
			button = buttons[i]
			if j <= numItems then
				item = items[j]
				itemID = self:GetItemID(item)
				name, link, rarity, level, minlevel, itype, subtype, stackCount, equipLoc, text = GetItemInfo(itemID)
				button.name:SetText(link or name or item or 'Error')
				if (items[name]) then
					button.count:SetText(string.format("%d/%d", self:GetItemCount(name), items[name]))
				else
					button.count:SetText(self:GetItemCount(name))
				end
				if text then
					button.texture:SetTexture(text)
				else
					button.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				end
				if resize then
					button:SetWidth(625)
				else
					button:SetWidth(600)
				end
				button.index = j
				button.link = link or true
				button.itemName = name
				button:Show()
			else
				button.index = nil
				button.link = nil
				button.itemName = nil
				button:SetText('')
				button:Hide()
			end
			button.check:Hide()
		end
	end
end

local function createConfigFrame(self)
	local name = "LTOHConfig"

	local frame = CreateFrame('Frame', name, OH:GetFrame("addon"))
	frame:SetToplevel(true)
	frame:SetAllPoints()

	local RemoveX = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	RemoveX:SetWidth(80)
	RemoveX:SetHeight(22)
	RemoveX:SetPoint("BOTTOMRIGHT", OH:GetFrame("main"), "BOTTOMRIGHT", -8, 14)
	RemoveX:SetText(L["Remove Set"])
	frame.RemoveX = RemoveX
	RemoveX:SetScript("OnClick", function(f)
		if not currentSet then -- current set means we've selected a set as a sub cat
			local setName = _db.global.lists[selectedLine]
			local removed = self:RemoveSet(setName)
			if removed then
				selectedLine = nil
				ui:RemoveSubCategory(L["Sets"], setName) -- remove the sub cat
				updateHighlights(nil, true)
				self:updateScrollList()
			end
		else
			local set = _db.global.lists[currentSet]
			local item = set[selectedLine]
			local removed = self:RemoveItem(item, currentSet)
			if removed then
				selectedLine = nil
				updateHighlights(nil, true)
				self:updateScrollList()
			end
		end
	end)

	local EditX = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	EditX:SetWidth(80)
	EditX:SetHeight(22)
	EditX:SetPoint("RIGHT", RemoveX, "LEFT")
	EditX:SetText(L["Rename Set"])
	EditX:SetScript("OnClick", function() end)
	frame.EditX = EditX
	EditX:SetScript('OnClick',
		function(f)
			if not currentSet then
				self.newSet = nil
				self.currentSet = _db.global.lists[selectedLine]
				self:ShowSetInputFrame(_db.global.lists[selectedLine])
			else
				local set = _db.global.lists[currentSet]
				local name = set[selectedLine]
				local item = self:GetItemID(name)
				local count = set[name]
				local n2, link = GetItemInfo(item)
				if not n2 then
					self:ShowItemInputFrame(item, count)
				else
					self:ShowItemInputFrame(link, count)
				end
			end
		end)

	local AddX = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	AddX:SetWidth(80)
	AddX:SetHeight(22)
	AddX:SetPoint("RIGHT", EditX, "LEFT")
	AddX:SetText(L["Add Set"])
	frame.AddX = AddX
	AddX:SetScript("OnClick",
		function(f)
			if not currentSet then
				self.newSet = true
				self:ShowSetInputFrame()
			else
				self:ShowItemInputFrame()
			end
		end)

	-- stolen from optionhouse and modified to look like AH
	frame.rows = {}
	for i=1, 8 do
		local button = CreateFrame("Button", nil, frame)
		button:SetWidth(597)
		button:SetHeight(37)
		local texture = button:CreateTexture(nil, "BACKGROUND")
		texture:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
		button.right = texture
		texture:SetTexCoord(0.75, 0.828125, 0, 1.0)
		texture:SetPoint("RIGHT", button, "RIGHT", 0, 2)
		texture:SetWidth(10)
		texture:SetHeight(32)
		local texture = button:CreateTexture(nil, "BACKGROUND")
		texture:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
		button.left = texture
		texture:SetTexCoord(0, 0.078125, 0, 1.0)
		texture:SetPoint("Left", button, "LEFT", 34, 2)
		texture:SetWidth(10)
		texture:SetHeight(32)
		local texture = button:CreateTexture(nil, "BACKGROUND")
		texture:SetTexture("Interface\\AuctionFrame\\UI-AuctionItemNameFrame")
		button.center = texture
		texture:SetTexCoord(0.078125, 0.75, 0, 1.0)
		texture:SetPoint("LEFT", button.left, "RIGHT", 0, 0)
		texture:SetPoint("RIGHT", button.right, "LEFT", 0, 0)
		texture:SetWidth(10)
		texture:SetHeight(32)
		local name = button:CreateFontString(nil, "BACKGROUND", 'GameFontNormal')
		button.name = name
		name:SetPoint("TOPLEFT", button, "TOPLEFT", 43, 0)
		name:SetHeight(32)
		name:SetWidth(167)
		name:SetJustifyH("LEFT")
		name:SetText("Button: "..i)
		name:SetTextColor(1,1,1)
		button.check = button:CreateTexture('BACKGROUND')
		button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		button.check:SetHeight(16)
		button.check:SetWidth(16)
		button.check:Show()
		button.check:SetPoint('LEFT', name, 'RIGHT', 0, 0)
		local count = button:CreateFontString(nil, "BACKGROUND", 'GameFontNormal')
		button.count = count
		count:SetHeight(32)
		count:SetWidth(167)
		count:SetJustifyH("RIGHT")
		count:SetPoint("TOPRIGHT", button, "TOPRIGHT", -5, 0)
		count:SetText("Count: "..i)
		local item = CreateFrame('Button', nil, button)
		local texture = item:CreateTexture(nil, 'BORDER')
		texture:SetHeight(60)
		texture:SetWidth(60)
		texture:SetTexture("Interface\\Buttons\\UI-QuickSlot2")
		texture:SetPoint("CENTER", item, "CENTER", 0, 0)
		item:SetHeight(32)
		item:SetWidth(32)
		item:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
		item:SetNormalTexture(texture)
		item:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		button.item = item
		button.texture = item:CreateTexture(nil, "ARTWORK")
		button.texture:SetAllPoints(item)

		local texture = button:CreateTexture(nil, 'HIGHLIGHT')
		texture:SetWidth(597)
		texture:SetHeight(32)
		texture:SetPoint('TOPLEFT', button, 'TOPLEFT', 33, 0)
		texture:SetPoint('TOPRIGHT', button, 'TOPRIGHT', 0, 0)
		texture:SetTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
		texture:SetTexCoord(0, 1, 0, 0.578125)
		texture:SetBlendMode("add")
		button.highlight = texture
		button:SetHighlightTexture(texture)
		button:SetHighlightTexture("Interface\\HelpFrame\\HelpFrameButton-Highlight")
		button:SetScript("OnClick", function(self, button)
			if IsShiftKeyDown() and not currentSet then
				trackList(i)
				return
			end
			updateHighlights(i)
		end)
		button:SetScript("OnEnter", onEnter)
		button:SetScript("OnLeave", onLeave)
		if( i > 1 ) then
			button:SetPoint("TOPLEFT", frame.rows[i-1], "BOTTOMLEFT", 0, 0)
		else
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", 195, -110)
		end
		frame.rows[i] = button
	end

	frame.scroll = CreateFrame("ScrollFrame", name.."Scroll", frame, "FauxScrollFrameTemplate")
	frame.scroll.buttonHeight = 37
	frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -105)
	frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 38)
	frame.scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(frame.scroll.buttonHeight, function() self:updateScrollList() end) end)

	local texture = frame.scroll:CreateTexture(nil, "BACKGROUND")
	texture:SetWidth(31)
	texture:SetHeight(256)
	texture:SetPoint("TOPLEFT", frame.scroll, "TOPRIGHT", -2, 5)
	texture:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
	texture:SetTexCoord(0, 0.484375, 0, 1.0)

	local texture = frame.scroll:CreateTexture(nil, "BACKGROUND")
	texture:SetWidth(31)
	texture:SetHeight(106)
	texture:SetPoint("BOTTOMLEFT", frame.scroll, "BOTTOMRIGHT", -2, -2)
	texture:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
	texture:SetTexCoord(0.515625, 1.0, 0, 0.4140625)
	return frame
end

function LootTracker:PopulateOHFrame(cat, subcat)
	if not configFrame then
		configFrame = createConfigFrame(self)
	end
	if cat and subcat == '' then
		currentSet = nil
	elseif cat and subcat ~= '' then
		if cat == L["Sets"] then
			currentSet = subcat
		end
	end
	if not currentSet then
		configFrame.AddX:SetText(L["Add Set"])
		configFrame.EditX:SetText(L["Rename Set"])
		configFrame.RemoveX:SetText(L["Remove Set"])
	else
		configFrame.AddX:SetText(L["Add Item"])
		configFrame.EditX:SetText(L["Edit Item"])
		configFrame.RemoveX:SetText(L["Del Item"])
	end
	updateTextures(currentSet)
	updateHighlights(nil, true)
	self:updateScrollList()
	configFrame:Show()
	return configFrame
end

function LootTracker:ResetOptions()
	local sets = _db.global.lists
	local ui = ui
	for i = 1, #sets do
		ui:RemoveSubCategory(L["Sets"], sets[i]) -- remove the sub cat
	end
end
