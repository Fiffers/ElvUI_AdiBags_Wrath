--[[
AdiBags - Adirelle's bag addon.
Copyright 2010-2014 Adirelle (adirelle@gmail.com)
All rights reserved.

This file is part of AdiBags.

AdiBags is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

AdiBags is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with AdiBags.  If not, see <http://www.gnu.org/licenses/>.
--]]

local addonName, addon = ...

--<GLOBALS
local _G = _G
local BankButtonIDToInvSlotID = _G.BankButtonIDToInvSlotID
local BANK_CONTAINER = _G.BANK_CONTAINER
local ContainerFrame_UpdateCooldown = _G.ContainerFrame_UpdateCooldown
local format = _G.format
local GetContainerItemID = _G.GetContainerItemID
local GetContainerItemInfo = _G.GetContainerItemInfo
local GetContainerItemLink = _G.GetContainerItemLink
local GetContainerItemQuestInfo = _G.GetContainerItemQuestInfo
local GetContainerNumFreeSlots = _G.GetContainerNumFreeSlots
local GetItemInfo = _G.GetItemInfo
local GetItemQualityColor = _G.GetItemQualityColor
local hooksecurefunc = _G.hooksecurefunc
local IsInventoryItemLocked = _G.IsInventoryItemLocked
local ITEM_QUALITY_POOR = _G.LE_ITEM_QUALITY_POOR
local ITEM_QUALITY_UNCOMMON = _G.LE_ITEM_QUALITY_UNCOMMON
local next = _G.next
local pairs = _G.pairs
local select = _G.select
local SetItemButtonDesaturated = _G.SetItemButtonDesaturated
local StackSplitFrame = _G.StackSplitFrame
local TEXTURE_ITEM_QUEST_BANG = _G.TEXTURE_ITEM_QUEST_BANG
local TEXTURE_ITEM_QUEST_BORDER = _G.TEXTURE_ITEM_QUEST_BORDER
local tostring = _G.tostring
local wipe = _G.wipe
--GLOBALS>

local GetSlotId = addon.GetSlotId
local GetBagSlotFromId = addon.GetBagSlotFromId

local ITEM_SIZE = addon.ITEM_SIZE

--------------------------------------------------------------------------------
-- Button initialization
--------------------------------------------------------------------------------

local buttonClass, buttonProto = addon:NewClass("ItemButton", "ItemButton", "ContainerFrameItemButtonTemplate", "ABEvent-1.0")

local childrenNames = { "Cooldown", "IconTexture", "IconQuestTexture", "Count", "Stock", "NormalTexture", "NewItemTexture" }

function buttonProto:OnCreate()
	local name = self:GetName()
	for i, childName in pairs(childrenNames ) do
		if not self[childName] then
			self[childName] = _G[name..childName]
		end
	end
	self:RegisterForDrag("LeftButton")
	self:RegisterForClicks("LeftButtonUp","RightButtonUp")
	self:SetScript('OnShow', self.OnShow)
	self:SetScript('OnHide', self.OnHide)
	self:SetWidth(ITEM_SIZE)
	self:SetHeight(ITEM_SIZE)
	if self.NewItemTexture then
		self.NewItemTexture:Hide()
	end
	self.SplitStack = nil -- Remove the function set up by the template
end

function buttonProto:OnAcquire(container, bag, slot)
	self.container = container
	self.bag = bag
	self.slot = slot
	self.stack = nil
	self:SetParent(addon.itemParentFrames[bag])
	self:SetID(slot)
	self:FullUpdate()
end

function buttonProto:OnRelease()
	self:SetSection(nil)
	self.container = nil
	self.itemId = nil
	self.itemLink = nil
	self.hasItem = nil
	self.texture = nil
	self.bagFamily = nil
	self.stack = nil
end

function buttonProto:ToString()
	return format("Button-%s-%s", tostring(self.bag), tostring(self.slot))
end

function buttonProto:IsLocked()
	return select(3, GetContainerItemInfo(self.bag, self.slot))
end

function buttonProto:SplitStack(split)
	SplitContainerItem(self.bag, self.slot, split)
end

--------------------------------------------------------------------------------
-- Generic bank button sub-type
--------------------------------------------------------------------------------

local bankButtonClass, bankButtonProto = addon:NewClass("BankItemButton", "ItemButton")
bankButtonClass.frameTemplate = "BankItemButtonGenericTemplate"

function bankButtonProto:OnAcquire(container, bag, slot)
	self.GetInventorySlot = nil -- Remove the method added by the template
	self.inventorySlot = bag == REAGENTBANK_CONTAINER and ReagentBankButtonIDToInvSlotID(slot) or BankButtonIDToInvSlotID(slot)
	return buttonProto.OnAcquire(self, container, bag, slot)
end

function bankButtonProto:IsLocked()
	return IsInventoryItemLocked(self.inventorySlot)
end

function bankButtonProto:UpdateNew()
	-- Not supported
end

function bankButtonProto:GetInventorySlot()
	return self.inventorySlot
end

function bankButtonProto:UpdateUpgradeIcon()
	if self.bag ~= BANK_CONTAINER and self.bag ~= REAGENTBANK_CONTAINER then
		buttonProto.UpdateUpgradeIcon(self)
	end
end

--------------------------------------------------------------------------------
-- Pools and acquistion
--------------------------------------------------------------------------------

local containerButtonPool = addon:CreatePool(buttonClass)
local bankButtonPool = addon:CreatePool(bankButtonClass)

function addon:AcquireItemButton(container, bag, slot)
	if bag == BANK_CONTAINER or bag == REAGENTBANK_CONTAINER then
		return bankButtonPool:Acquire(container, bag, slot)
	else
		return containerButtonPool:Acquire(container, bag, slot)
	end
end

-- Pre-spawn a bunch of buttons, when we are out of combat
-- because buttons created in combat do not work well
hooksecurefunc(addon, 'OnInitialize', function()
	addon:Debug('Prespawning buttons')
	containerButtonPool:PreSpawn(160)
end)

--------------------------------------------------------------------------------
-- Model data
--------------------------------------------------------------------------------

function buttonProto:SetSection(section)
	local oldSection = self.section
	if oldSection ~= section then
		self.section = section
		if oldSection then
			oldSection:RemoveItemButton(self)
		end
		return true
	end
end

function buttonProto:GetSection()
	return self.section
end

function buttonProto:GetItemId()
	return self.itemId
end

function buttonProto:GetItemLink()
	return self.itemLink
end

function buttonProto:GetCount()
	return select(2, GetContainerItemInfo(self.bag, self.slot)) or 0
end

function buttonProto:GetBagFamily()
	return self.bagFamily
end

local BANK_BAG_IDS = addon.BAG_IDS.BANK
function buttonProto:IsBank()
	return not not BANK_BAG_IDS[self.bag]
end

function buttonProto:IsStack()
	return false
end

function buttonProto:GetRealButton()
	return self
end

function buttonProto:SetStack(stack)
	self.stack = stack
end

function buttonProto:GetStack()
	return self.stack
end

local function SimpleButtonSlotIterator(self, slotId)
	if not slotId and self.bag and self.slot then
		return GetSlotId(self.bag, self.slot), self.bag, self.slot, self.itemId, self.stack
	end
end

function buttonProto:IterateSlots()
	return SimpleButtonSlotIterator, self
end

--------------------------------------------------------------------------------
-- Scripts & event handlers
--------------------------------------------------------------------------------

function buttonProto:OnShow()
	self:RegisterEvent('BAG_UPDATE_COOLDOWN', 'UpdateCooldown')
	self:RegisterEvent('ITEM_LOCK_CHANGED', 'UpdateLock')
	self:RegisterEvent('QUEST_ACCEPTED', 'UpdateBorder')
	self:RegisterEvent('BAG_NEW_ITEMS_UPDATED', 'UpdateNew')
	self:RegisterEvent('PLAYER_EQUIPMENT_CHANGED', 'FullUpdate')
	if self.UpdateSearch then
		self:RegisterEvent('INVENTORY_SEARCH_UPDATE', 'UpdateSearch')
	end
	self:RegisterEvent('UNIT_QUEST_LOG_CHANGED')
	self:RegisterMessage('AdiBags_UpdateAllButtons', 'Update')
	self:RegisterMessage('AdiBags_GlobalLockChanged', 'UpdateLock')
	self:FullUpdate()
end

function buttonProto:OnHide()
	self:UnregisterAllEvents()
	self:UnregisterAllMessages()
	if self.hasStackSplit and self.hasStackSplit == 1 then
		StackSplitFrame:Hide()
	end
end

function buttonProto:UNIT_QUEST_LOG_CHANGED(event, unit)
	if unit == "player" then
		self:UpdateBorder(event)
		self:UpdateElvUISkin()
	end
end

--------------------------------------------------------------------------------
-- Display updating
--------------------------------------------------------------------------------

function buttonProto:CanUpdate()
	if not self:IsVisible() or addon.holdYourBreath then
		return false
	end
	return true
end

function buttonProto:FullUpdate()
	local bag, slot = self.bag, self.slot
	self.itemId = GetContainerItemID(bag, slot)
	self.itemLink = GetContainerItemLink(bag, slot)
	self.hasItem = not not self.itemId
	self.texture = GetContainerItemInfo(bag, slot)
	self.bagFamily = select(2, GetContainerNumFreeSlots(bag))
	self:Update()
end

function buttonProto:Update()
	if not self:CanUpdate() then return end
	local icon = self.IconTexture
	if self.texture then
		icon:SetTexture(self.texture)
		--icon:SetTexCoord(0,1,0,1)
		icon:SetTexCoord(unpack(ElvUI[1].TexCoords)) -- ElvUI Mod!
		icon:SetInside()
	else
		--icon:SetTexture([[Interface\BUTTONS\UI-EmptySlot]])
		--icon:SetTexCoord(12/64, 51/64, 12/64, 51/64)
		icon:SetTexture() -- ElvUI Mod!
		icon:SetTexCoord(unpack(ElvUI[1].TexCoords)) -- ElvUI Mod!
		icon:SetInside()
	end
	local tag = (not self.itemId or addon.db.profile.showBagType) and addon:GetFamilyTag(self.bagFamily)
	if tag then
		self.Stock:SetText(tag)
		self.Stock:Show()
	else
		self.Stock:Hide()
	end
	self:UpdateCount()
	self:UpdateBorder()
	self:UpdateCooldown()
	self:UpdateLock()
	self:UpdateNew()
	self:UpdateUpgradeIcon()
	self:CreateScrapIcon()
	if self.UpdateSearch then
		self:UpdateSearch()
	end

	self:UpdateElvUISkin() -- ElvUI Mod!

	addon:SendMessage('AdiBags_UpdateButton', self)
end

-- ElvUI Mod!
function buttonProto:UpdateElvUISkin()
	self:SetTemplate(nil, true)
	self:StyleButton()
	self:SetNormalTexture(nil)

	if IsAddOnLoaded("ElvUI_KlixUI") then
		ElvUI_KlixUI[1]:GetModule("KuiButtonStyle"):StyleButton(self)
	end
	if self.IconQuestTexture:GetBlendMode() == "ADD" then
		if self.texture then -- Fix for free space button border when rebuying items with a border!
			self:SetBackdropBorderColor(self.IconQuestTexture:GetVertexColor())
		else
			self:SetBackdropBorderColor(0, 0, 0, 0)
		end
		self.IconQuestTexture:Hide()
	else
		if self.texture and addon.db.profile.allHighlight then
			self:SetBackdropBorderColor(1, 1, 1)
		end
		self.IconQuestTexture:Show()
	end

	self:SetBackdropBorderColor(ElvUI[1].media.bordercolor)

	local bag, slot = self.bag, self.slot
	if addon.db.profile.questIndicator then
		local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
		if questId and not isActive then
			self:SetBackdropBorderColor(1, 1, 0)
			self.IconQuestTexture:Show()
		elseif questId or isQuestItem then
			self:SetBackdropBorderColor(1, 0.3, 0.3)
			self.IconQuestTexture:Hide()
		end
	end

	if addon.db.profile.qualityOpacity then
		local _, _, _, quality = GetContainerItemInfo(bag, slot)
		if quality and addon.db.profile.allHighlight or quality and quality > LE_ITEM_QUALITY_COMMON then
			local r, g, b = GetItemQualityColor(quality)
			self:SetBackdropBorderColor(r, g, b)
		end
	end
end

function buttonProto:CreateScrapIcon()
	if not self.ScrapIcon then
		self.ScrapIcon = self:CreateTexture(nil, "ARTWORK")
		self.ScrapIcon:SetAtlas("bags-icon-scrappable")
		self.ScrapIcon:SetSize(14, 12)
		self.ScrapIcon:SetPoint("TOPRIGHT", -2, -2)
	end

	if self.ScrapIcon then
		local itemLocation = _G.ItemLocation:CreateFromBagAndSlot(self.bag, self.slot)
		if itemLocation then
			if C_Item.DoesItemExist(itemLocation) and C_Item.CanScrapItem(itemLocation) and addon.db.profile.scrapIndicator then
				self.ScrapIcon:SetShown(itemLocation)
			else
				self.ScrapIcon:SetShown(false)
			end
		end
	end

	if not addon.db.profile.scrapIndicator then
		self.ScrapIcon:SetShown(false)
	end
end

function buttonProto:UpdateCount()
	local count = self:GetCount() or 0
	self.count = count
	if count > 1 then
		self.Count:SetText(count)
		self.Count:Show()
	else
		self.Count:Hide()
	end
end

function buttonProto:UpdateLock(isolatedEvent)
	if addon.globalLock then
		SetItemButtonDesaturated(self, true)
		self:Disable()
	else
		self:Enable()
		SetItemButtonDesaturated(self, self:IsLocked())
	end
	if isolatedEvent then
		addon:SendMessage('AdiBags_UpdateLock', self)
	end
end

function buttonProto:UpdateSearch()
	local _, _, _, _, _, _, _, isFiltered = GetContainerItemInfo(self.bag, self.slot)
	if isFiltered then
		self.searchOverlay:Show();
		self:SetAlpha(0.2) -- ElvUI Mod!
	else
		self.searchOverlay:Hide();
		self:SetAlpha(1) -- ElvUI Mod!
	end
end

function buttonProto:UpdateCooldown()
	ElvUI[1]:RegisterCooldown(_G[self:GetName().."Cooldown"]) -- ElvUI Mod!
	_G[self:GetName().."Cooldown"]:SetOutside(self, 1, 0) -- ElvUI Mod!
	return ContainerFrame_UpdateCooldown(self.bag, self)
end

function buttonProto:UpdateNew()
	self.BattlepayItemTexture:SetShown(IsBattlePayItem(self.bag, self.slot))
end

function buttonProto:UpdateUpgradeIcon()
	self.UpgradeIcon:SetShown(IsContainerItemAnUpgrade(self.bag, self.slot) or false)
end

local function GetBorder(bag, slot, itemId, settings)
	if settings.questIndicator then
		local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
		if questId and not isActive then
			return TEXTURE_ITEM_QUEST_BANG
		end
		if questId or isQuestItem then
			--return TEXTURE_ITEM_QUEST_BORDER
		end
	end
	if not settings.qualityHighlight then
		return
	end
	local _, _, _, quality = GetContainerItemInfo(bag, slot)
	if quality == LE_ITEM_QUALITY_POOR and settings.dimJunk then
		local v = 1 - 0.5 * settings.qualityOpacity
		return true, v, v, v, 1, nil, nil, nil, nil, "MOD"
	end
	local color = quality ~= LE_ITEM_QUALITY_COMMON and BAG_ITEM_QUALITY_COLORS[quality]
	if color then
		return [[Interface\Buttons\UI-ActionButton-Border]], color.r, color.g, color.b, settings.qualityOpacity, 14/64, 49/64, 15/64, 50/64, "ADD"
	end
end

function buttonProto:UpdateBorder(isolatedEvent)
	local texture, r, g, b, a, x1, x2, y1, y2, blendMode
	if self.hasItem then
		texture, r, g, b, a, x1, x2, y1, y2, blendMode = GetBorder(self.bag, self.slot, self.itemLink or self.itemId, addon.db.profile)
	end
	if not texture then
		self.IconQuestTexture:Hide()
	else
		local border = self.IconQuestTexture
		if texture == true then
			border:SetVertexColor(1, 1, 1, 1)
			border:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
		else
			border:SetTexture(texture)
			border:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
		end
		border:SetBlendMode(blendMode or "BLEND")
		border:Show()
	end
	if self.JunkIcon then
		local quality = self.hasItem and select(3, GetItemInfo(self.itemLink or self.itemId))
		self.JunkIcon:SetShown(quality == LE_ITEM_QUALITY_POOR and addon:GetInteractingWindow() == "MERCHANT")
	end
	if isolatedEvent then
		addon:SendMessage('AdiBags_UpdateBorder', self)
	end
end

--------------------------------------------------------------------------------
-- Item stack button
--------------------------------------------------------------------------------

local stackClass, stackProto = addon:NewClass("StackButton", "Frame", "ABEvent-1.0")
addon:CreatePool(stackClass, "AcquireStackButton")

function stackProto:OnCreate()
	self:SetWidth(ITEM_SIZE)
	self:SetHeight(ITEM_SIZE)
	self.slots = {}
	self:SetScript('OnShow', self.OnShow)
	self:SetScript('OnHide', self.OnHide)
	self.GetCountHook = function()
		return self.count
	end
end

function stackProto:OnAcquire(container, key)
	self.container = container
	self.key = key
	self.count = 0
	self.dirtyCount = true
	self:SetParent(container)
end

function stackProto:OnRelease()
	self:SetVisibleSlot(nil)
	self:SetSection(nil)
	self.key = nil
	self.container = nil
	wipe(self.slots)
end

function stackProto:GetCount()
	return self.count
end

function stackProto:IsStack()
	return true
end

function stackProto:GetRealButton()
	return self.button
end

function stackProto:GetKey()
	return self.key
end

function stackProto:UpdateVisibleSlot()
	local bestLockedId, bestLockedCount
	local bestUnlockedId, bestUnlockedCount
	if self.slotId and self.slots[self.slotId] then
		local _, count, locked = GetContainerItemInfo(GetBagSlotFromId(self.slotId))
		count = count or 1
		if locked then
			bestLockedId, bestLockedCount = self.slotId, count
		else
			bestUnlockedId, bestUnlockedCount = self.slotId, count
		end
	end
	for slotId in pairs(self.slots) do
		local _, count, locked = GetContainerItemInfo(GetBagSlotFromId(slotId))
		count = count or 1
		if locked then
			if not bestLockedId or count > bestLockedCount then
				bestLockedId, bestLockedCount = slotId, count
			end
		else
			if not bestUnlockedId or count > bestUnlockedCount then
				bestUnlockedId, bestUnlockedCount = slotId, count
			end
		end
	end
	return self:SetVisibleSlot(bestUnlockedId or bestLockedId)
end

function stackProto:ITEM_LOCK_CHANGED()
	return self:Update()
end

function stackProto:AddSlot(slotId)
	local slots = self.slots
	if not slots[slotId] then
		slots[slotId] = true
		self.dirtyCount = true
		self:Update()
	end
end

function stackProto:RemoveSlot(slotId)
	local slots = self.slots
	if slots[slotId] then
		slots[slotId] = nil
		self.dirtyCount = true
		self:Update()
	end
end

function stackProto:IsEmpty()
	return not next(self.slots)
end

function stackProto:OnShow()
	self:RegisterMessage('AdiBags_UpdateAllButtons', 'Update')
	self:RegisterMessage('AdiBags_PostContentUpdate')
	self:RegisterEvent('ITEM_LOCK_CHANGED')
	if self.button then
		self.button:Show()
	end
	self:Update()
end

function stackProto:OnHide()
	if self.button then
		self.button:Hide()
	end
	self:UnregisterAllEvents()
	self:UnregisterAllMessages()
end

function stackProto:SetVisibleSlot(slotId)
	if slotId == self.slotId then return end
	self.slotId = slotId
	local button = self.button
	local mouseover = false
	if button then
		if button:IsMouseOver() then
			mouseover = true
			button:GetScript('OnLeave')(button)
		end
		button.GetCount = nil
		button:Release()
	end
	if slotId then
		button = addon:AcquireItemButton(self.container, GetBagSlotFromId(slotId))
		button.GetCount = self.GetCountHook
		button:SetAllPoints(self)
		button:SetStack(self)
		button:Show()
		if mouseover then
			button:GetScript('OnEnter')(button)
		end
	else
		button = nil
	end
	self.button = button
	return true
end

function stackProto:Update()
	if not self:CanUpdate() then return end
	self:UpdateVisibleSlot()
	self:UpdateCount()
	if self.button then
		self.button:Update()
	end
end

stackProto.FullUpdate = stackProto.Update

function stackProto:UpdateCount()
	local count = 0
	for slotId in pairs(self.slots) do
		count = count + (select(2, GetContainerItemInfo(GetBagSlotFromId(slotId))) or 1)
	end
	self.count = count
	self.dirtyCount = nil
end

function stackProto:AdiBags_PostContentUpdate()
	if self.dirtyCount then
		self:UpdateCount()
	end
end

function stackProto:GetItemId()
	return self.button and self.button:GetItemId()
end

function stackProto:GetItemLink()
	return self.button and self.button:GetItemLink()
end

function stackProto:IsBank()
	return self.button and self.button:IsBank()
end

function stackProto:GetBagFamily()
	return self.button and self.button:GetBagFamily()
end

local function StackSlotIterator(self, previous)
	local slotId = next(self.slots, previous)
	if slotId then
		local bag, slot = GetBagSlotFromId(slotId)
		local _, count = GetContainerItemInfo(bag, slot)
		return slotId, bag, slot, self:GetItemId(), count
	end
end

function stackProto:IterateSlots()
	return StackSlotIterator, self
end

-- Reuse button methods
stackProto.CanUpdate = buttonProto.CanUpdate
stackProto.SetSection = buttonProto.SetSection
stackProto.GetSection = buttonProto.GetSection
