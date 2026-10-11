-- Questweaver Sets group authored items and ordered quests into reusable RP stories.
local function parseIDs(raw, max)
  local ids,seen={},{}
  if raw==nil or raw=="" then return ids end
  for id in string.gmatch(raw,"[^,]+") do
    if not QW:ValidateString(id,120) or seen[id] then return nil end
    ids[QW.Count(ids)+1]=id; seen[id]=true
    if QW.Count(ids)>max then return nil end
  end
  return ids
end
function QW:ParseSetQuestIDs(raw) return parseIDs(raw,24) end
function QW:SaveSet(id,title,description,questIDs,itemIDs)
  if id~=nil and id~="" and not self:ValidateString(id,120) then return nil,"The Questweaver Set ID is invalid." end
  if not self:ValidateString(title,100) or not self:ValidateString(description,500) or type(questIDs)~="table" or type(itemIDs)~="table" then return nil,"Set details are invalid." end
  local i
  for i=1,self.Count(questIDs) do if not self.db.quests[questIDs[i]] then return nil,"A Questweaver Set quest ID was not found." end end
  for i=1,self.Count(itemIDs) do if not self.db.items[itemIDs[i]] then return nil,"A Questweaver Set item ID was not found." end end
  local set=id and self.db.sets[id]
  if id and id~="" and (not set or set.owner~=self:PlayerName()) then return nil,"Only your own Questweaver Set can be edited." end
  if not set then id=self:NewID("set"); set={id=id,owner=self:PlayerName(),version=0}; self.db.sets[id]=set end
  set.title=title; set.description=description; set.questIDs=self:Copy(questIDs); set.itemIDs=self:Copy(itemIDs); set.version=(set.version or 0)+1; set.updatedAt=self.now()
  return id,"Questweaver Set saved."
end
function QW:DeleteSet(id)
  local set=self.db.sets[id]
  if not set or set.owner~=self:PlayerName() then return false,"Only your own Questweaver Set can be deleted." end
  self.db.sets[id]=nil
  if self.RefreshUI then self:RefreshUI() end
  return true,"Questweaver Set deleted. Its quests and items were not changed."
end
function QW:GetSetLines(set)
  local lines={set.description or "","","Chapters: "..self.Count(set.questIDs or {}),"Supporting items: "..self.Count(set.itemIDs or {}),"Set ID: "..set.id}
  local i
  for i=1,self.Count(set.questIDs or {}) do
    local q=self.db.quests[set.questIDs[i]]; lines[self.Count(lines)+1]=i..". "..(q and q.title or ("Missing quest: "..set.questIDs[i]))
  end
  for i=1,self.Count(set.itemIDs or {}) do
    local item=self.db.items[set.itemIDs[i]]; lines[self.Count(lines)+1]="Item: "..(item and item.name or ("Missing item: "..set.itemIDs[i]))
  end
  return lines
end
