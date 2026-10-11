QW.DEFAULT_TOKEN_ID="item:questweaver:rp-token"
QW.ITEM_CATEGORIES={"quest","reward","misc","weapon","armor","food"}
local allowedCategories={quest=true,reward=true,misc=true,weapon=true,armor=true,food=true}
function QW:NormalizeItemCategory(category)
  category=string.lower(tostring(category or "misc"))
  return allowedCategories[category] and category or nil
end
function QW:RegisterInventory() end
function QW:EnsureDefaultItems()
  local id=self.DEFAULT_TOKEN_ID
  if not self.db.items[id] then
    self.db.items[id]={id=id,name="Questweaver RP Token",icon="Interface\\Icons\\INV_Misc_Coin_09",description="A standard Questweaver token, awarded by RP quests.",maxStack=999,category="reward",creator="Questweaver",version=1,default=true}
  else
    self.db.items[id].maxStack=999
    self.db.items[id].category="reward"
  end
  local itemID,item
  for itemID,item in pairs(self.db.items) do item.category=self:NormalizeItemCategory(item.category) or (item.default and "reward" or "misc") end
  return id
end
function QW:GetDefaultTokenID()
  return self:EnsureDefaultItems()
end
function QW:GetRPTokenCount()
  local id=self:GetDefaultTokenID()
  return self.db.inventory[id] or 0
end
function QW:NormalizeIcon(icon)
  if type(icon)=="string" and string.match(icon,"^%d+$") then return tonumber(icon) end
  return icon
end
function QW:ValidateIcon(icon)
  icon=self:NormalizeIcon(icon)
  if type(icon)=="number" then return icon>0 end
  return self:ValidateString(icon,160)
end
function QW:CreateItem(name, icon, description, stack, category)
  icon=self:NormalizeIcon(icon)
  stack = tonumber(stack) or 1
  category=self:NormalizeItemCategory(category or "misc")
  if not self:ValidateString(name, 80) or not self:ValidateIcon(icon) or not self:ValidateString(description, 500) or stack < 1 or stack > 999 or not category then return nil, "Use a name, icon, description, max stack (1-999), and valid category." end
  local id = self:NewID("item")
  self.db.items[id] = { id=id, name=name, icon=icon, description=description, maxStack=stack, category=category, creator=self.db.playerID, version=1 }
  if self.RefreshMakerInventory then self:RefreshMakerInventory() end
  return id
end
function QW:BuildItemHyperlink(itemID)
  local item=self.db.items[itemID]
  if not item then return nil,"Unknown RP item ID." end
  local safeName=string.gsub(item.name,"|","||")
  local link="|Hquestweaver:item:"..self:SerializeItem(item).."|h["..safeName.."]|h"
  if self.StrLen(link)>240 then return nil,"This item's definition is too long for a chat link. Shorten its description or icon path." end
  return link
end
function QW:ParseChatItemLink(link)
  local data=type(link)=="string" and string.match(link,"^questweaver:item:(.+)$")
  if not data or self.StrLen(data)>1800 then return nil end
  local item=self:ParseItem(data)
  if not item or not self:ValidateString(item.id,120) or not self:ValidateString(item.name,80) or not self:ValidateIcon(item.icon) or not self:ValidateString(item.description,500) or item.maxStack<1 or item.maxStack>999 then return nil end
  return self.db.items[item.id] or item
end
function QW:HasItem(id, amount) return type(id)=="string" and (self.db.inventory[id] or 0) >= (tonumber(amount) or 0) end
function QW:AddItem(def, amount)
  amount = tonumber(amount)
  local category=type(def)=="table" and self:NormalizeItemCategory(def.category) or nil
  if type(def) ~= "table" or not self:ValidateString(def.id, 120) or not self:ValidateString(def.name, 80) or not self:ValidateIcon(def.icon) or not self:ValidateString(def.description, 500) or not category or not amount or amount < 1 or amount > 999 then return false end
  def.category=category
  if not self.db.items[def.id] then self.db.items[def.id] = self:Copy(def) end
  self.db.inventory[def.id] = (self.db.inventory[def.id] or 0) + amount
  if self.RefreshQuickAccessButton then self:RefreshQuickAccessButton() end
  return true
end
function QW:GrantMakerItem(id,amount)
  amount=tonumber(amount); local item=self.db.items[id]
  if not item or not amount or amount<1 or amount>999 or amount~=math.floor(amount) then return false,"Choose an item and a whole quantity from 1 to 999." end
  if item.category=="quest" or item.category=="reward" then return false,"Quest items and rewards can only enter the RP satchel through quest actions." end
  if amount>(tonumber(item.maxStack) or 1) then return false,"That amount exceeds this item's max stack." end
  if not self:AddItem(item,amount) then return false,"The item could not be added to the RP satchel." end
  return true,"Added "..amount.." x "..item.name.." to your RP satchel."
end
function QW:CanDeleteMakerItem(id)
  local item=self.db.items[id]
  if not item then return false,"That Maker Inventory item no longer exists." end
  if id==self.DEFAULT_TOKEN_ID or item.default then return false,"The default RP token definition cannot be deleted." end
  if (self.db.inventory[id] or 0)>0 then return false,"Remove this item from your RP satchel before deleting its definition." end
  for _,set in pairs(self.db.sets or {}) do for _,itemID in ipairs(set.itemIDs or {}) do if itemID==id then return false,"Remove this item from its Questweaver Sets first." end end end
  for _,quest in pairs(self.db.quests or {}) do
    if quest.rewardID==id or (quest.itemDefinitions and quest.itemDefinitions[id]) then return false,"This item is referenced by a quest definition." end
    for _,step in ipairs(quest.steps or {}) do if step.itemID==id then return false,"This item is referenced by a quest objective." end end
  end
  for _,run in pairs(self.db.questRuns or {}) do if run.itemDefinitions and run.itemDefinitions[id] then return false,"This item is retained by an accepted or completed quest." end end
  for _,offer in pairs(self.db.questOffers or {}) do if offer.itemDefinitions and offer.itemDefinitions[id] then return false,"This item is referenced by a pending quest offer." end end
  for _,trade in pairs(self.db.trades or {}) do
    if trade.state~="complete" and trade.state~="cancelled" then
      for _,entry in ipairs(trade.offer or {}) do if entry.id==id then return false,"This item is referenced by an unresolved trade." end end
    end
  end
  return true
end
function QW:DeleteMakerItem(id)
  local ok,message=self:CanDeleteMakerItem(id); if not ok then return false,message end
  self.db.items[id]=nil; if self.RefreshMakerInventory then self:RefreshMakerInventory() end
  return true,"Maker item definition deleted."
end
function QW:TakeItem(id, amount)
  amount = tonumber(amount)
  if not amount or amount < 1 or not self:HasItem(id, amount) then return false end
  self.db.inventory[id] = self.db.inventory[id] - amount
  if self.db.inventory[id] == 0 then self.db.inventory[id] = nil end
  if self.RefreshQuickAccessButton then self:RefreshQuickAccessButton() end
  return true
end
function QW:RemoveRPItem(id, amount)
  amount=tonumber(amount)
  if type(id)~="string" or not self.db.items[id] or not amount or amount<1 or amount>999 or amount~=math.floor(amount) then
    return false,"Choose an RP item and a whole quantity from 1 to 999."
  end
  if not self:HasItem(id,amount) then return false,"You do not have that many of this RP item." end
  if not self:TakeItem(id,amount) then return false,"The RP item could not be removed." end
  return true,"Removed "..amount.." x "..self.db.items[id].name.." from your RP inventory."
end
function QW:InventoryLines()
  local lines = {}
  for id, count in pairs(self.db.inventory) do local item=self.db.items[id]; if item then lines[self.Count(lines)+1] = item.name .. " x" .. count .. " [" .. id .. "]" end end
  table.sort(lines); return lines
end
