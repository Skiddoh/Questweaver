local function split(text, separator, max)
  local out, start = {}, 1
  while true do
    local at = string.find(text, separator, start, true)
    if not at or (QW.Count(out) + 1) == max then out[QW.Count(out)+1]=string.sub(text,start); break end
    out[QW.Count(out)+1]=string.sub(text,start,at-1); start=at+1
  end
  return out
end
local function serialiseSteps(steps)
  local out={}
  for i,s in ipairs(steps) do out[i]=table.concat({QW:Escape(s.type or ""),QW:Escape(s.itemID or ""),QW:Escape(s.count or ""),QW:Escape(s.placeID or ""),QW:Escape(s.mobName or ""),QW:Escape(s.text or "")}, "~") end
  return table.concat(out,";")
end
local function parseSteps(raw)
  local out={}
  for line in string.gmatch(raw or "", "[^;]+") do
    local p=split(line,"~",6); local fields=QW.Count(p)
    -- Version 1 quests had four fields: type, item, count, text.
    if fields==4 then p[6]=p[4]; p[4]=""; p[5]="" elseif fields~=6 then return nil end
    local i; for i=1,6 do p[i]=QW:Unescape(p[i]); if not p[i] then return nil end end; local count=tonumber(p[3] or "")
    if (p[1]~="dialogue" and p[1]~="possess" and p[1]~="deliver" and p[1]~="manual" and p[1]~="visit" and p[1]~="loot" and p[1]~="collect" and p[1]~="kill") or not QW:ValidateString(p[6],300) then return nil end
    if (p[1]=="possess" or p[1]=="deliver" or p[1]=="loot" or p[1]=="collect") and (not QW:ValidateString(p[2],120) or not count or count<1 or count>999) then return nil end
    if p[1]=="visit" and not QW:ValidateString(p[4],80) then return nil end
    if p[1]=="loot" and (not QW:ValidateString(p[4],80) or not QW:ValidateString(p[5],100)) then return nil end
    if p[1]=="collect" and not QW:ValidateString(p[4],80) then return nil end
    local npcID=tonumber(string.match(p[5] or "","^npc:(%d+)$")); local hasNPCPrefix=string.find(p[5] or "","^npc:")
    if hasNPCPrefix and not npcID then return nil end
    if p[1]=="kill" and (not count or count<1 or count>999 or not QW:ValidateString(p[5],100)) then return nil end
    out[QW.Count(out)+1]={type=p[1],itemID=p[2],count=count,placeID=p[4],mobName=p[5],npcID=npcID,text=p[6]}; if QW.Count(out)>12 then return nil end
  end
  return QW.Count(out)>0 and out or nil
end
function QW:ParseSteps(raw) return parseSteps(raw) end
local function serialisePlaces(places)
  local out={}; for i,p in ipairs(places or {}) do out[i]=table.concat({QW:Escape(p.id or ""),QW:Escape(p.zone or ""),QW:Escape(p.x or ""),QW:Escape(p.y or ""),QW:Escape(p.radius or ""),QW:Escape(p.description or "")}, "~") end; return table.concat(out,";")
end
local function parsePlaces(raw)
  local out, ids={},{}
  if raw=="" or raw==nil then return out,ids end
  for line in string.gmatch(raw,"[^;]+") do
    local p=split(line,"~",6); if QW.Count(p)~=6 then return nil end
    local i; for i=1,6 do p[i]=QW:Unescape(p[i]); if not p[i] then return nil end end
    local x,y,radius=tonumber(p[3]),tonumber(p[4]),tonumber(p[5])
    if not QW:ValidateString(p[1],80) or not QW:ValidateString(p[2],100) or not QW:ValidateString(p[6],300) or ids[p[1]] then return nil end
    if (p[3]=="") ~= (p[4]=="") or (p[3]=="" and p[5]~="") then return nil end
    if p[3]~="" and (not x or not y or not radius or x<0 or x>100 or y<0 or y>100 or radius<=0 or radius>100) then return nil end
    local place={id=p[1],zone=p[2],x=x,y=y,radius=radius,description=p[6]}; out[QW.Count(out)+1]=place; ids[place.id]=place
    if QW.Count(out)>12 then return nil end
  end
  return out,ids
end
function QW:ParsePlaces(raw) return parsePlaces(raw) end
function QW:AtPlace(place)
  if not place then return false,"This objective has no valid location." end
  local zone=(GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText())
  local subZone=GetSubZoneText and GetSubZoneText() or nil
  if zone~=place.zone and subZone~=place.zone then return false,"Travel to "..place.zone.." before completing this objective." end
  if not place.x then return true end
  -- Never call SetMapToCurrentZone here: on Forever that mutates Blizzard's
  -- protected map UI and can produce the "blocked" action warning. Read the
  -- coordinates the client already exposes; if its map isn't initialized,
  -- tell the player rather than changing protected UI state.
  if not GetPlayerMapPosition then return false,"This client cannot read map coordinates for this objective." end
  local x,y=GetPlayerMapPosition("player")
  if type(x)~="number" or type(y)~="number" or (x==0 and y==0) then return false,"Your map position is unavailable in this zone." end
  local dx,dy=x*100-place.x,y*100-place.y
  if math.sqrt(dx*dx+dy*dy)>place.radius then return false,"Move within "..place.radius.." map units of "..place.zone.." ("..place.x..", "..place.y..")." end
  return true
end
function QW:ParseItemIDs(raw)
  local ids, seen={},{}
  if raw=="" or raw==nil then return ids end
  for id in string.gmatch(raw,"[^,]+") do
    if not self:ValidateString(id,120) or seen[id] then return nil end
    ids[self.Count(ids)+1]=id; seen[id]=true
  end
  return ids
end
local function definitionWire(definitions)
  local out={}; for _,item in pairs(definitions) do out[QW.Count(out)+1]=QW:SerializeItem(item) end; return table.concat(out,";")
end
local function parseDefinitions(raw)
  local definitions, count={},0
  for entry in string.gmatch(raw or "","[^;]+") do
    local item=QW:ParseItem(entry); if not item or definitions[item.id] then return nil end
    definitions[item.id]=item; count=count+1
    if count>24 then return nil end
  end
  return definitions
end
function QW:RegisterQuest()
  -- Keep registration results so kill diagnostics can distinguish an event
  -- API mismatch from a target/matching problem instead of silently failing.
  self.killEventRegistration={}
  -- This Forever client rejects combat-chat events (those were removed from
  -- newer UI APIs). Use structured kill events only.
  local events={"PARTY_KILL","COMBAT_LOG_EVENT_UNFILTERED"}
  for i=1,QW.Count(events) do
    local eventName=events[i]
    local ok,result=pcall(self.frame.RegisterEvent,self.frame,eventName)
    self.killEventRegistration[eventName]={ok=ok,error=not ok and tostring(result) or nil}
  end
end
local function optionalQuestID(value)
  if value==nil or value=="" then return nil end
  if not QW:ValidateString(value,120) then return false end
  return value
end
local function optionalNPCID(value)
  if value==nil or value=="" then return nil end
  local id=tonumber(string.match(tostring(value),"^npc:(%d+)$"))
  return id and id>0 and id or false
end
local function shareFields(q)
  local reward=QW.db.items[q.rewardID]
  if not reward then return nil,"The quest reward definition is missing." end
  local j; for j=1,QW.Count(q.places or {}) do if not q.places[j].zone then return nil,"This older quest uses RP-only places; recreate it with a real zone/location." end end
  q.places=q.places or {}; q.itemDefinitions=q.itemDefinitions or {}; q.itemDefinitions[q.rewardID]=q.itemDefinitions[q.rewardID] or reward
  local i; for i=1,QW.Count(q.steps or {}) do local itemID=q.steps[i].itemID; if itemID~="" then q.itemDefinitions[itemID]=q.itemDefinitions[itemID] or QW.db.items[itemID] end end
  local followUpID=optionalQuestID(q.followUpQuestID)
  if followUpID==false then return nil,"The follow-up quest ID is invalid." end
  local giverNPCID=q.giverNPCID
  if giverNPCID and (type(giverNPCID)~="number" or giverNPCID<1) then return nil,"The quest giver NPC ID is invalid." end
  if ((q.giverPlaceID and q.giverPlaceID~="") or (q.giverDialogue and q.giverDialogue~="")) and not giverNPCID then return nil,"Quest giver dialogue needs a quest giver NPC." end
  if q.giverPlaceID and q.giverPlaceID~="" and not QW:ValidateString(q.giverPlaceID,80) then return nil,"The quest giver place ID is invalid." end
  if q.giverDialogue and q.giverDialogue~="" and not QW:ValidateString(q.giverDialogue,500) then return nil,"The quest giver dialogue is invalid." end
  local turnInNPCID=q.turnInNPCID
  if turnInNPCID and (type(turnInNPCID)~="number" or turnInNPCID<1) then return nil,"The reward NPC ID is invalid." end
  return {q.id,q.version,q.title,q.description,serialiseSteps(q.steps),QW:SerializeItem(reward),q.rewardCount,serialisePlaces(q.places),definitionWire(q.itemDefinitions),followUpID or "",giverNPCID and ("npc:"..giverNPCID) or "",q.giverPlaceID or "",q.giverDialogue or "",turnInNPCID and ("npc:"..turnInNPCID) or ""}
end
local function decodeSharedQuest(f,offset,sender)
  if QW.Count(f)<offset+8 or QW.Count(f)>offset+13 then return nil end
  local id,ver=f[offset],tonumber(f[offset+1]); local steps=parseSteps(f[offset+4]); local reward=QW:ParseItem(f[offset+5]); local count=tonumber(f[offset+6]); local places,placeByID=parsePlaces(f[offset+7]); local definitions=parseDefinitions(f[offset+8]); local followUpID=optionalQuestID(f[offset+9])
  local giverNPCID=optionalNPCID(f[offset+10]); local giverPlaceID=f[offset+11] or ""; local giverDialogue=f[offset+12] or ""; local turnInNPCID=optionalNPCID(f[offset+13])
  if not QW:ValidateString(id,120) or not ver or not QW:ValidateString(f[offset+2] or "",100) or not QW:ValidateString(f[offset+3] or "",500) or not steps or not reward or not count or count<1 or count>999 or not places or not definitions or followUpID==false or followUpID==id or giverNPCID==false or turnInNPCID==false or (giverNPCID==nil and (giverPlaceID~="" or giverDialogue~="")) or (giverPlaceID~="" and not QW:ValidateString(giverPlaceID,80)) or (giverDialogue~="" and not QW:ValidateString(giverDialogue,500)) then return nil end
  definitions[reward.id]=definitions[reward.id] or reward
  local i; for i=1,QW.Count(steps) do
    local step=steps[i]
    if step.placeID~="" and not placeByID[step.placeID] then return nil end
    if step.itemID~="" and not definitions[step.itemID] then definitions[step.itemID]=QW.db.items[step.itemID]; if not definitions[step.itemID] then return nil end end
  end
  reward.category="reward"
  for i=1,QW.Count(steps) do local itemID=steps[i].itemID; if itemID~="" and definitions[itemID] then definitions[itemID].category="quest" end end
  if giverPlaceID~="" and not placeByID[giverPlaceID] then return nil end
  return {id=id,owner=sender,title=f[offset+2],description=f[offset+3],steps=steps,places=places,placeByID=placeByID,itemDefinitions=definitions,reward=reward,rewardCount=count,version=ver,followUpQuestID=followUpID,giverNPCID=giverNPCID,giverPlaceID=giverPlaceID,giverDialogue=giverDialogue,turnInNPCID=turnInNPCID}
end
function QW:CreateQuest(title, description, steps, rewardID, rewardCount, places, extraItemIDs, followUpQuestID, predecessorQuestID, giverNPCSpec, giverPlaceID, giverDialogue, turnInNPCSpec, existingID)
  rewardCount=tonumber(rewardCount) or 1
  local checkedSteps=parseSteps(serialiseSteps(steps)); local checkedPlaces, placeByID=parsePlaces(serialisePlaces(places))
  local followUpID=optionalQuestID(followUpQuestID); local predecessorID=optionalQuestID(predecessorQuestID)
  local giverNPCID=optionalNPCID(giverNPCSpec); local turnInNPCID=optionalNPCID(turnInNPCSpec); giverPlaceID=giverPlaceID or ""; giverDialogue=giverDialogue or ""
  if not self:ValidateString(title,100) or not self:ValidateString(description,500) or not checkedSteps or not checkedPlaces or not self.db.items[rewardID] or rewardCount<1 or rewardCount>999 or followUpID==false or predecessorID==false or giverNPCID==false or turnInNPCID==false or (giverNPCID==nil and (giverPlaceID~="" or giverDialogue~="")) or (giverPlaceID~="" and not self:ValidateString(giverPlaceID,80)) or (giverDialogue~="" and not self:ValidateString(giverDialogue,500)) then return nil,"Quest details are invalid." end
  if giverPlaceID~="" and not placeByID[giverPlaceID] then return nil,"The quest giver place must be defined in Real locations." end
  if followUpID and not self.db.quests[followUpID] then return nil,"The selected follow-up quest does not exist." end
  if predecessorID and not self.db.quests[predecessorID] then return nil,"The selected predecessor quest does not exist." end
  if predecessorID and self.db.quests[predecessorID].followUpQuestID and self.db.quests[predecessorID].followUpQuestID~="" and self.db.quests[predecessorID].followUpQuestID~=existingID then return nil,"That predecessor already has a follow-up quest." end
  if followUpID and self.db.quests[followUpID].predecessorQuestID and self.db.quests[followUpID].predecessorQuestID~="" and self.db.quests[followUpID].predecessorQuestID~=existingID then return nil,"That follow-up quest already has a predecessor." end
  local definitions={[rewardID]=self.db.items[rewardID]}
  local i; for i=1,self.Count(checkedSteps) do
    local step=checkedSteps[i]
    if step.placeID~="" and not placeByID[step.placeID] then return nil,"A step refers to a place that is not defined." end
    if step.itemID~="" then if not self.db.items[step.itemID] then return nil,"A step refers to an unknown RP item." end; definitions[step.itemID]=self.db.items[step.itemID] end
  end
  for i=1,self.Count(extraItemIDs or {}) do local itemID=extraItemIDs[i]; if not self.db.items[itemID] then return nil,"An assigned quest item does not exist." end; definitions[itemID]=self.db.items[itemID] end
  self.db.items[rewardID].category="reward"
  for i=1,self.Count(checkedSteps) do local itemID=checkedSteps[i].itemID; if itemID~="" then self.db.items[itemID].category="quest" end end
  local previous=existingID and self.db.quests[existingID]
  if existingID and (not previous or previous.owner~=self:PlayerName()) then return nil,"Only your own quest can be edited." end
  local id=existingID or self:NewID("quest")
  if previous then
    if previous.predecessorQuestID and self.db.quests[previous.predecessorQuestID] and self.db.quests[previous.predecessorQuestID].followUpQuestID==id then self.db.quests[previous.predecessorQuestID].followUpQuestID=nil end
    if previous.followUpQuestID and self.db.quests[previous.followUpQuestID] and self.db.quests[previous.followUpQuestID].predecessorQuestID==id then self.db.quests[previous.followUpQuestID].predecessorQuestID=nil end
  end
  self.db.quests[id]={id=id,owner=self:PlayerName(),title=title,description=description,steps=checkedSteps,places=checkedPlaces,itemDefinitions=definitions,rewardID=rewardID,rewardCount=rewardCount,followUpQuestID=followUpID,predecessorQuestID=predecessorID,giverNPCID=giverNPCID,giverPlaceID=giverPlaceID,giverDialogue=giverDialogue,turnInNPCID=turnInNPCID,version=(previous and (previous.version or 1)+1 or 8)}
  if predecessorID then self.db.quests[predecessorID].followUpQuestID=id end
  if followUpID then self.db.quests[followUpID].predecessorQuestID=id end
  return id
end
function QW:DeleteQuest(id)
  local quest=self.db.quests[id]
  if not quest or quest.owner~=self:PlayerName() then return false,"Only your own quest definition can be deleted." end
  for _,run in pairs(self.db.questRuns or {}) do if run.id==id and run.state~="complete" then return false,"This quest still has an open run. Finish or remove it before deleting the definition." end end
  for _,set in pairs(self.db.sets or {}) do for _,questID in ipairs(set.questIDs or {}) do if questID==id then return false,"Remove this quest from its Questweaver Set first." end end end
  if quest.predecessorQuestID and self.db.quests[quest.predecessorQuestID] and self.db.quests[quest.predecessorQuestID].followUpQuestID==id then self.db.quests[quest.predecessorQuestID].followUpQuestID=nil end
  if quest.followUpQuestID and self.db.quests[quest.followUpQuestID] and self.db.quests[quest.followUpQuestID].predecessorQuestID==id then self.db.quests[quest.followUpQuestID].predecessorQuestID=nil end
  self.db.quests[id]=nil
  if self.RefreshUI then self:RefreshUI() end
  return true,"Quest definition deleted. Completed quest records are retained."
end
function QW:ShareQuestWithKind(id,target,firstKind)
  local q=self.db.quests[id]
  if not q or not self:ValidateString(target,80) then return false,"Choose a quest and recipient." end
  local chain,seen={},{}
  local current=q; local depth
  for depth=1,6 do
    if seen[current.id] then return false,"The follow-up quest chain contains a loop." end
    seen[current.id]=true
    local fields,message=shareFields(current); if not fields then return false,message end
    chain[self.Count(chain)+1]={quest=current,fields=fields}
    local nextID=optionalQuestID(current.followUpQuestID)
    if nextID==false then return false,"The follow-up quest ID is invalid." end
    if not nextID then break end
    current=self.db.quests[nextID]; if not current then return false,"The linked follow-up quest is not available." end
  end
  if current.followUpQuestID and current.followUpQuestID~="" then return false,"A shared follow-up chain is limited to six quests." end
  local i
  for i=1,self.Count(chain) do
    local kind,fields=firstKind,chain[i].fields
    if i>1 then
      kind="QUEST_FOLLOWUP"; local linked={chain[i-1].quest.id}; local j; for j=1,self.Count(fields) do linked[self.Count(linked)+1]=fields[j] end; fields=linked
    end
    local packet=self:Pack(kind,fields); if self.StrLen(packet)>4096 then return false,"A quest in this chain is too large to share." end
    chain[i].kind,chain[i].sendFields=kind,fields
  end
  for i=1,self.Count(chain) do self:QueuePacket(target,self:Pack(chain[i].kind,chain[i].sendFields)) end
  return true,(firstKind=="QUEST_OFFER" and "Quest offer sent" or "Quest shared")..(self.Count(chain)>1 and (" with "..(self.Count(chain)-1).." follow-up quest"..(self.Count(chain)==2 and "." or "s.")) or ".")
end
function QW:ShareQuest(id,target)
  return self:ShareQuestWithKind(id,target,"QUEST_SHARE")
end
function QW:OfferQuest(id,target)
  local q=self.db.quests[id]
  if not q or not q.giverNPCID or not q.giverDialogue or q.giverDialogue=="" then return false,"Set a quest giver NPC and dialogue before sending an NPC quest offer." end
  return self:ShareQuestWithKind(id,target,"QUEST_OFFER")
end
function QW:ReceiveQuest(f,sender)
  local run=decodeSharedQuest(f,3,sender); if not run then return end
  local existing=self.db.questRuns[run.id]
  if existing and existing.version>=run.version then return end
  run.index=1; run.state="active"; run.delivered={}; self.db.questRuns[run.id]=run
  self.db.inbox[self.Count(self.db.inbox)+1]="Quest received from "..sender..": "..run.title
end
function QW:ReceiveQuestOffer(f,sender)
  local offer=decodeSharedQuest(f,3,sender); if not offer then return end
  if not offer.giverNPCID or not offer.giverDialogue or offer.giverDialogue=="" then return end
  local existing=self.db.questOffers[offer.id]
  if existing and existing.version>=offer.version then return end
  if self.db.questRuns[offer.id] then return end
  self.db.questOffers[offer.id]=offer
  self.db.inbox[self.Count(self.db.inbox)+1]="NPC quest offer received from "..sender..": "..offer.title
end
function QW:ReceiveFollowUpQuest(f,sender)
  local parentID=f[3]; if not self:ValidateString(parentID or "",120) then return end
  local quest=decodeSharedQuest(f,4,sender); if not quest or quest.id==parentID then return end
  local parent=self.db.questRuns[parentID] or self.db.questOffers[parentID]
  if parent and (parent.owner~=sender or parent.followUpQuestID~=quest.id) then return end
  local existing=self.db.followUpDefinitions[parentID]
  if existing and existing.version>=quest.version then return end
  self.db.followUpDefinitions[parentID]=quest
  self.db.inbox[self.Count(self.db.inbox)+1]="Follow-up received for "..parentID..": "..quest.title
  if parent and parent.state=="complete" then self:ActivateFollowUp(parent) end
end
function QW:AssignQuestToCurrentPlayer(id)
  local q=self.db.quests[id]
  if not q then return false,"Quest definition was not found." end
  if self.db.questRuns[id] then return true,"Quest is already active for this character." end
  local places=self:Copy(q.places or {}); local placeByID={}; local i
  for i=1,self.Count(places) do placeByID[places[i].id]=places[i] end
  local definitions=self:Copy(q.itemDefinitions or {}); local reward=definitions[q.rewardID] or self:Copy(self.db.items[q.rewardID])
  if not reward then return false,"Quest reward definition was not found." end
  definitions[q.rewardID]=reward
  self.db.questRuns[id]={id=id,owner=q.owner or self:PlayerName(),title=q.title,description=q.description,steps=self:Copy(q.steps),places=places,placeByID=placeByID,itemDefinitions=definitions,reward=reward,rewardCount=q.rewardCount,version=q.version,followUpQuestID=q.followUpQuestID,turnInNPCID=q.turnInNPCID,index=1,state="active",delivered={},assignedLocally=true}
  self.db.inbox[self.Count(self.db.inbox)+1]="Demo quest assigned to you: "..q.title
  return true,"Quest assigned to this character."
end
function QW:AcceptQuestOffer(id)
  local offer=self.db.questOffers[id]
  if not offer then return false,"That NPC quest offer is no longer available." end
  if self.db.questRuns[id] then self.db.questOffers[id]=nil; return false,"This quest is already active." end
  if offer.giverNPCID then
    local targetNPCID=self:GetTargetNPCInfo()
    if targetNPCID~=offer.giverNPCID then return false,"Target quest giver NPC "..offer.giverNPCID.." to accept this quest." end
  end
  -- NPC selection/interaction already implies proximity; giver acceptance
  -- must not depend on this client's optional map-coordinate API.
  local places=self:Copy(offer.places or {}); local placeByID={}; local i
  for i=1,self.Count(places) do placeByID[places[i].id]=places[i] end
  local definitions=self:Copy(offer.itemDefinitions or {}); local reward=self:Copy(offer.reward or definitions[offer.rewardID])
  if not reward then return false,"This NPC quest offer has invalid reward data." end
  definitions[reward.id]=definitions[reward.id] or reward
  self.db.questRuns[id]={id=offer.id,owner=offer.owner,title=offer.title,description=offer.description,steps=self:Copy(offer.steps),places=places,placeByID=placeByID,itemDefinitions=definitions,reward=reward,rewardCount=offer.rewardCount,version=offer.version,followUpQuestID=offer.followUpQuestID,turnInNPCID=offer.turnInNPCID,index=1,state="active",delivered={},acceptedFromNPC=offer.giverNPCID}
  self.db.questOffers[id]=nil
  self.db.inbox[self.Count(self.db.inbox)+1]="Accepted NPC quest: "..offer.title
  return true,(offer.giverDialogue and offer.giverDialogue~="" and offer.giverDialogue.." " or "").."Quest accepted."
end
function QW:GetNPCInteractionOptions(npcID)
  local groups={new={},custom={},ready={},progress={},done={},repeatQuests={}}
  if npcID==2079 then self:CreateBoarDemo() end
  local id,quest,run,offer
  for id,offer in pairs(self.db.questOffers) do
    if offer.giverNPCID==npcID and not self.db.questRuns[id] then
      groups.new[self.Count(groups.new)+1]={kind="offer",id=id,title=offer.title,text=offer.description,dialogue=offer.giverDialogue}
      if offer.giverDialogue and offer.giverDialogue~="" then groups.custom[self.Count(groups.custom)+1]={kind="custom",id=id,title=offer.title,text=offer.giverDialogue} end
    end
  end
  for id,quest in pairs(self.db.quests) do
    if quest.giverNPCID==npcID then
      run=self.db.questRuns[id]
      if not run then groups.new[self.Count(groups.new)+1]={kind="quest",id=id,title=quest.title,text=quest.description,dialogue=quest.giverDialogue}
      elseif run.state=="complete" then
        groups.done[self.Count(groups.done)+1]={kind="done",id=id,title=run.title or quest.title,text="You have already completed this quest."}
      elseif run.state=="active" then
        local current=run.steps and run.steps[run.index]
        if not current or current.type~="dialogue" or not current.mobName or current.mobName=="" or not self:TargetMatchesStep(current) then
          groups.progress[self.Count(groups.progress)+1]={kind="active",id=id,title=run.title or quest.title,text="This quest is already in your quest journal."}
        end
      end
      if quest.giverDialogue and quest.giverDialogue~="" then
        groups.custom[self.Count(groups.custom)+1]={kind="custom",id=id,title=quest.title,text=quest.giverDialogue}
      end
    end
  end
  for id,run in pairs(self.db.questRuns) do
    if run.turnInNPCID==npcID and run.state=="ready_to_turn_in" then
      groups.ready[self.Count(groups.ready)+1]={kind="turnin",id=id,title=run.title or id,text="Your objectives are complete. Receive your reward."}
    elseif run.state=="complete" and (run.turnInNPCID==npcID or run.giverNPCID==npcID or run.acceptedFromNPC==npcID) then
      local known=false; local i
      for i=1,self.Count(groups.done) do if groups.done[i].id==id then known=true end end
      if not known then
        groups.done[self.Count(groups.done)+1]={kind="done",id=id,title=run.title or id,text="You have already completed this quest."}
      end
      if run.giverNPCID==npcID or run.acceptedFromNPC==npcID then groups.repeatQuests[self.Count(groups.repeatQuests)+1]={kind="repeat",id=id,title=run.title or id,text="Completed before. Accept this quest again?"} end
    end
    local step=run.steps and run.steps[run.index]
    if run.state=="active" and step and step.type=="dialogue" and step.mobName and step.mobName~="" and self:TargetMatchesStep(step) then
      groups.progress[self.Count(groups.progress)+1]={kind="objective",id=id,title=run.title or id,text=step.text or "Speak with this character to continue."}
    end
  end
  local categories={"new","custom","ready","progress","done","repeatQuests"}; local i
  for i=1,self.Count(categories) do
    table.sort(groups[categories[i]],function(a,b) return (a.title or "")<(b.title or "") end)
  end
  return groups
end
function QW:PerformNPCInteraction(option,npcID)
  if not option then return false,"Choose an interaction first." end
  local targetID,targetName=self:GetTargetNPCInfo()
  if not targetID or targetID~=npcID then return false,"Target the same NPC before choosing this interaction." end
  if option.kind=="offer" then return self:AcceptQuestOffer(option.id)
  elseif option.kind=="quest" then
    local ok,message=self:AssignQuestToCurrentPlayer(option.id)
    if ok and option.dialogue and option.dialogue~="" then return true,option.dialogue.." Quest accepted." end
    return ok,message
  elseif option.kind=="custom" then return true,option.text
  elseif option.kind=="turnin" then
    local run=self.db.questRuns[option.id]; if not run then return false,"This quest is no longer available." end
    return self:CompleteQuest(run)
  elseif option.kind=="objective" then
    local ok,message=self:AdvanceQuest(option.id)
    if ok then return true,"["..(option.title or option.id).."] "..(message or "Dialogue objective complete.") end
    return false,message
  elseif option.kind=="active" then
    if self.ShowQuestJournal then self:ShowQuestJournal() end
    return true,"Opened your Questweaver quest journal."
  elseif option.kind=="repeat" then
    local run=self.db.questRuns[option.id]
    if not run or run.state~="complete" then return false,"This quest is no longer available to repeat." end
    run.index=1; run.state="active"; run.delivered={}; run.pendingDelivery=nil; run.completedAt=nil
    self.db.inbox[self.Count(self.db.inbox)+1]="Repeated quest: "..(run.title or run.id)
    return true,"Quest accepted again."
  end
  return false,option.text or "This interaction has no action."
end
function QW:InteractWithTarget()
  local npcID,npcName=self:GetTargetNPCInfo()
  if not npcID then return false,npcName end
  if not self.ShowNPCInteraction then return false,"The NPC interaction window is not ready. Use /reload and try again." end
  self:ShowNPCInteraction(npcID,npcName)
  return true,"Interaction window opened for "..npcName.."."
end
function QW:IsNPCInteractionInRange(npcID,npcGUID)
  local currentID=self:GetTargetNPCInfo()
  if not currentID or currentID~=npcID then return false end
  local currentGUID=UnitGUID and UnitGUID("target")
  if npcGUID and currentGUID and npcGUID~=currentGUID then return false end
  if not CheckInteractDistance then return nil end
  if (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown()) then return nil end
  local ok,inRange=pcall(CheckInteractDistance,"target",3)
  if not ok then return nil end
  return not not inRange
end
function QW:UpdateNPCInteractionRange()
  local f=self.npcInteraction
  if not f or not f:IsShown() then return end
  local inRange=self:IsNPCInteractionInRange(f.npcID,f.npcGUID)
  if inRange==false then f:Hide() end
end
function QW:ClearAcceptedQuests()
  local count=0
  for _,run in pairs(self.db.questRuns) do
    if run.pendingDelivery then return false,"Resolve or resend the pending delivery before removing accepted quests." end
    count=count+1
  end
  self.db.questRuns={}
  return true,"Removed "..count.." accepted quest record"..(count==1 and "." or "s.")
end
function QW:AdvanceQuest(id)
  local run=self.db.questRuns[id]; if not run or run.state~="active" then return false,"This quest is not active." end
  local step=run.steps[run.index]; if not step then return false end
  -- Dialogue is a target-and-interact objective; proximity is enforced by
  -- selecting the NPC in-game, not by map coordinates or zone text.
  if step.placeID~="" and step.type~="dialogue" then
    local ok,message=self:AtPlace(run.placeByID and run.placeByID[step.placeID])
    if not ok then return false,message end
  end
  if (step.type=="dialogue" or step.type=="deliver") and step.mobName~="" then
    local ok,message=self:TargetMatchesStep(step); if not ok then return false,message end
  end
  if step.type=="dialogue" then return self:FinishStep(run)
  elseif step.type=="possess" then if not self:HasItem(step.itemID,step.count) then return false,"Required RP item is not in your inventory." end; return self:FinishStep(run)
  elseif step.type=="visit" then return self:FinishStep(run)
  elseif step.type=="collect" then
    local definition=run.itemDefinitions[step.itemID]
    if not definition or not self:AddItem(definition,step.count) then return false,"This quest's collection item definition is invalid." end
    return self:FinishStep(run)
  elseif step.type=="loot" then
    local targetName=UnitName("target")
    if targetName~=step.mobName then return false,"Target the defined mob ("..step.mobName..") before collecting this RP loot." end
    local definition=run.itemDefinitions[step.itemID]
    if not definition or not self:AddItem(definition,step.count) then return false,"This quest's loot definition is invalid." end
    return self:FinishStep(run)
  elseif step.type=="kill" then return false,"Defeat "..step.mobName.." to update this objective."
  elseif step.type=="manual" then
    run.state="awaiting approval"; self:Send("QUEST_APPROVAL",run.owner,{run.id,run.index})
    self:Print("["..(run.title or run.id).."] Approval requested for: "..step.text)
    return true,"Approval request sent to the quest owner."
  elseif step.type=="deliver" then
    if not self:HasItem(step.itemID,step.count) then return false,"Required RP item is not in your inventory." end
    local deliveryID=self:NewID("delivery"); local def=self.db.items[step.itemID]
    if not self:TakeItem(step.itemID,step.count) then return false end
    run.pendingDelivery={id=deliveryID,index=run.index,itemID=step.itemID,count=step.count,definition=def}
    self:Send("QUEST_DELIVERY",run.owner,{deliveryID,run.id,run.index,step.itemID,step.count,self:SerializeItem(def)})
    self:Print("["..(run.title or run.id).."] Delivery sent for: "..step.text)
    return true,"Delivery sent; it will finish when the owner acknowledges it."
  end
end
function QW:NPCIDFromGUID(guid)
  if type(guid)~="string" then return nil end
  -- WoW Forever's ClassicAPI reads the entry correctly from its raw 1.12
  -- GUID layout. Prefer it when the client exposes the compatibility API.
  if C_CreatureInfo and C_CreatureInfo.GetCreatureID then
    local ok,creatureID=pcall(C_CreatureInfo.GetCreatureID,guid)
    if ok and type(creatureID)=="number" and creatureID>0 then return creatureID end
  end
  local _,id=string.match(guid,"^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if not id then _,id=string.match(guid,"^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") end
  if id then return tonumber(id) end
  -- WoW 1.12-era clients use 0xF130 + six hexadecimal entry-ID digits
  -- instead of the modern Creature-... GUID format.
  local legacyID=string.match(guid,"^0[xX][fF]130(%x%x%x%x%x%x)")
  return legacyID and tonumber(legacyID,16) or nil
end
function QW:RememberNPCName(npcID,name)
  if npcID and type(name)=="string" and name~="" and self:ValidateString(name,100) then
    self.db.npcNames=self.db.npcNames or {}
    self.db.npcNames[name]=npcID
  end
end
function QW:NPCIDFromName(name)
  if type(name)~="string" then return nil end
  local remembered=self.db.npcNames and self.db.npcNames[name]
  if remembered then return remembered end
  -- The built-in boar demo supports the two client languages confirmed for
  -- this NPC. Other localized names are learned from /qw npcid or the editor.
  if name=="Young Thistle Boar" or name=="Junger Disteleber" then return 1984 end
  return nil
end
function QW:GetTargetNPCInfo()
  local guid=UnitGUID and UnitGUID("target"); local npcID=self:NPCIDFromGUID(guid)
  local name=UnitName and UnitName("target") or nil
  -- Some Forever/1.12 clients do not expose UnitGUID. Keep the built-in
  -- Ilthalaine demo usable there while custom NPC objectives still use IDs.
  if not npcID and (name=="Conservator Ilthalaine" or name=="Konservator Ilthalaine") then npcID=2079 end
  if not npcID then
    if type(name)=="string" and name~="" then return nil,"Questweaver could not read an NPC ID for "..name..". Target a creature or NPC first." end
    return nil,"Target a creature or NPC first."
  end
  if type(name)~="string" or name=="" then name="NPC "..npcID end
  self:RememberNPCName(npcID,name)
  return npcID,name
end
function QW:DescribeTargetNPC()
  local npcID,npcName=self:GetTargetNPCInfo()
  if not npcID then return false,npcName end
  return true,"Selected NPC: "..npcName.." (ID: "..npcID..")."
end
function QW:TargetMatchesStep(step)
  if not step.mobName or step.mobName=="" then return true end
  if step.npcID then
    local npcID=self:NPCIDFromGUID(UnitGUID and UnitGUID("target"))
    if npcID==step.npcID then return true end
    return false,"Target NPC "..step.npcID.." before completing this objective."
  end
  if UnitName("target")==step.mobName then return true end
  return false,"Target "..step.mobName.." before completing this objective."
end
function QW:RecordKill(targetName,targetGUID,targetNPCIDOverride)
  local targetNPCID=targetNPCIDOverride or self:NPCIDFromGUID(targetGUID) or self:NPCIDFromName(targetName)
  if not self:ValidateString(targetName or "",100) and not targetNPCID then return false end
  local updated=false
  for _,run in pairs(self.db.questRuns) do
    local step=run.steps and run.steps[run.index]
    local matches=step and step.type=="kill" and ((step.npcID and step.npcID==targetNPCID) or (not step.npcID and step.mobName==targetName))
    if run.state=="active" and matches then
      -- Kill objectives are identity based: a matching NPC template ID counts
      -- wherever it is killed. Location requirements belong to visit/collect
      -- objectives and must not suppress combat-log progress.
      run.killProgress=run.killProgress or {}; local progress=math.min((run.killProgress[run.index] or 0)+1,step.count); run.killProgress[run.index]=progress; updated=true
      if progress>=step.count then
        self:FinishStep(run)
      else
        self:Print("["..(run.title or run.id).."] Kills: "..progress.." / "..step.count.." - "..step.text)
      end
    end
  end
  if updated then
    self.lastCombatKill={name=targetName,npcID=targetNPCID,time=(GetTime and GetTime()) or self.now()}
    if self.RefreshUI then self:RefreshUI() end
  end
  return updated
end
function QW:HandleCombatLogKill()
  if not CombatLogGetCurrentEventInfo then
    if self.debugKills then self:Print("This client did not provide CombatLogGetCurrentEventInfo for the combat-log event.") end
    return false
  end
  local _,subevent,_,sourceGUID,sourceName,_,_,destGUID,destName=CombatLogGetCurrentEventInfo()
  if subevent~="PARTY_KILL" then
    if self.debugKills then self:Print("Combat event ignored: "..tostring(subevent).." (waiting for PARTY_KILL).") end
    return false
  end
  local npcID=self:NPCIDFromGUID(destGUID)
  if self.debugKills then self:Print("Combat PARTY_KILL: target="..tostring(destName)..", NPC ID="..tostring(npcID)..", source="..tostring(sourceName)..".") end
  if not self:ValidateString(destName or "",100) and not npcID then return false end
  local playerGUID=UnitGUID and UnitGUID("player")
  local credited=playerGUID and sourceGUID==playerGUID or (not playerGUID and sourceName==UnitName("player"))
  if not credited then
    if self.debugKills then self:Print("Kill ignored: combat log does not credit the player as the killer.") end
    return false
  end
  local counted=self:RecordKill(destName,destGUID)
  if self.debugKills and not counted then self:Print("Kill event received but no active kill objective matched this NPC ID/name.") end
  return counted
end
function QW:HandlePartyKill(attackerGUID,targetGUID)
  if not attackerGUID or not targetGUID then
    if self.debugKills then self:Print("PARTY_KILL event received without readable attacker/target GUIDs.") end
    return false
  end
  local playerGUID=UnitGUID and UnitGUID("player")
  local petGUID=UnitGUID and UnitGUID("pet")
  if attackerGUID~=playerGUID and attackerGUID~=petGUID then
    if self.debugKills then self:Print("PARTY_KILL ignored: attacker is not this player or their pet.") end
    return false
  end
  local npcID=self:NPCIDFromGUID(targetGUID)
  local targetName
  if UnitGUID and UnitGUID("target")==targetGUID then targetName=UnitName and UnitName("target") end
  if not targetName or targetName=="" then targetName=npcID and ("NPC "..npcID) or nil end
  if self.debugKills then self:Print("PARTY_KILL received: target="..tostring(targetName)..", NPC ID="..tostring(npcID)..".") end
  if not targetName and not npcID then return false end
  local counted=self:RecordKill(targetName or ("NPC "..npcID),targetGUID,npcID)
  if self.debugKills and not counted then self:Print("PARTY_KILL received but no active kill objective matched this NPC ID/name.") end
  return counted
end
function QW:HandleLegacyKillMessage(message)
  local format=YOU_HAVE_SLAIN
  if type(message)~="string" then
    if self.debugKills then self:Print("Combat chat kill event had no text; YOU_HAVE_SLAIN="..tostring(format)..".") end
    return false
  end
  local target
  if type(format)=="string" then
    local before,after=string.match(format,"^(.-)%%s(.-)$")
    if before then
      local function literal(value) return (string.gsub(value,"([^%w])","%%%1")) end
      target=string.match(message,"^"..literal(before).."(.+)"..literal(after).."$")
    end
  end
  -- WoW Forever's German combat log reports the local player's killing blow
  -- as "Euer Charakter besiegt <NPC>". Prefer the selected unit's exact
  -- localized name/GUID so combat-log annotations do not break NPC-ID checks.
  if not target then
    local tail=string.match(message,"^Euer Charakter besiegt (.+)$")
    if tail then
      local selectedName=UnitName and UnitName("target")
      if selectedName and string.find(tail,selectedName,1,true) then target=selectedName
      else target=tail end
    end
  end
  if not target then
    if self.debugKills and (string.find(message,"besiegt",1,true) or type(format)~="string") then
      self:Print("Combat message was not recognized as a player killing blow. Format="..tostring(format).."; message="..message)
    end
    return false
  end
  local last=self.lastCombatKill
  local now=(GetTime and GetTime()) or self.now()
  if last and last.name==target and now-last.time<1 then
    if self.debugKills then self:Print("Ignored duplicate chat notification for the same kill.") end
    return true
  end
  -- In the older client path the combat chat event may be all that is
  -- available. Prefer the still-selected target's GUID, then names previously
  -- learned through /qw npcid or the target-NPC quest editor button.
  local targetGUID=UnitGUID and UnitGUID("target")
  local targetNPCID
  if UnitName and UnitName("target")==target then targetNPCID=self:NPCIDFromGUID(targetGUID) end
  targetNPCID=targetNPCID or self:NPCIDFromName(target)
  local counted=self:RecordKill(target,targetGUID,targetNPCID)
  if self.debugKills and not counted then self:Print("Player kill message received but no active name-based kill objective matched "..target..".") end
  return counted
end
function QW:GetQuestStepProgress(run)
  local total=run and run.steps and self.Count(run.steps) or 0
  if total<1 then return 0,0 end
  return math.min(math.max(tonumber(run.index) or 1,1),total),total
end
function QW:FinishStep(run)
  local step=run.steps[run.index]
  local objective=(step and step.text) or "Objective"
  run.index=run.index+1
  local ok,message
  if run.index>self.Count(run.steps) then
    if run.turnInNPCID then
      run.state="ready_to_turn_in"; ok=true; message="Objectives complete. Return to NPC "..run.turnInNPCID.." and use /qw interact to receive your reward."
    else ok,message=self:CompleteQuest(run) end
  else ok,message=true,"Objective complete." end
  if ok then self:Print("["..(run.title or run.id).."] "..objective.." complete. "..(message or "")) end
  if self.RefreshQuestTracker then self:RefreshQuestTracker() end
  return ok,message
end
function QW:CompleteQuest(run)
  if run.state=="complete" then return true end
  if not self:AddItem(run.reward,run.rewardCount) then return false,"Reward data was invalid." end
  self.db.questHistory=self.db.questHistory or {}
  self.db.questHistory[#self.db.questHistory+1]={id=run.id,title=run.title,completedAt=self.now(),owner=run.owner}
  run.state="complete"; run.completedAt=self.now()
  local followUpMessage=self:ActivateFollowUp(run)
  return true,"Quest complete! Reward added to RP inventory."..(followUpMessage and (" "..followUpMessage) or "")
end
function QW:ActivateFollowUp(run)
  local followUpID=optionalQuestID(run.followUpQuestID)
  if followUpID==false then return "Follow-up quest link is invalid." end
  if not followUpID then return nil end
  local nextQuest=self.db.followUpDefinitions[run.id] or self.db.quests[followUpID]
  if not nextQuest or nextQuest.id~=followUpID or (nextQuest.owner and nextQuest.owner~=run.owner) then
    self.db.inbox[self.Count(self.db.inbox)+1]="Follow-up for "..run.title.." was not received. Ask the quest owner to share the chain again."
    return "Follow-up quest is not available yet."
  end
  if self.db.questRuns[followUpID] then return "Follow-up quest was already active." end
  local places=self:Copy(nextQuest.places or {}); local placeByID={}; local i
  for i=1,self.Count(places) do placeByID[places[i].id]=places[i] end
  local definitions=self:Copy(nextQuest.itemDefinitions or {}); local reward=self:Copy(nextQuest.reward or definitions[nextQuest.rewardID] or self.db.items[nextQuest.rewardID])
  if not reward then
    self.db.inbox[self.Count(self.db.inbox)+1]="Follow-up for "..run.title.." has invalid reward data."
    return "Follow-up quest could not be activated."
  end
  definitions[reward.id]=definitions[reward.id] or reward
  self.db.questRuns[followUpID]={id=nextQuest.id,owner=nextQuest.owner,title=nextQuest.title,description=nextQuest.description,steps=self:Copy(nextQuest.steps),places=places,placeByID=placeByID,itemDefinitions=definitions,reward=reward,rewardCount=nextQuest.rewardCount,version=nextQuest.version,followUpQuestID=nextQuest.followUpQuestID,turnInNPCID=nextQuest.turnInNPCID,index=1,state="active",delivered={},activatedFrom=run.id}
  self.db.followUpDefinitions[run.id]=nil
  self.db.inbox[self.Count(self.db.inbox)+1]="Follow-up quest activated: "..nextQuest.title
  return "Follow-up activated: "..nextQuest.title.."."
end
function QW:ReceiveApproval(f,sender)
  local q=self.db.quests[f[3]]; local index=tonumber(f[4])
  if not q or q.owner~=self:PlayerName() or not index or not q.steps[index] or q.steps[index].type~="manual" then return end
  local approvalValue=q.id.." | "..index.." | "..sender
  self.db.inbox[self.Count(self.db.inbox)+1]="Approval requested by "..sender.." for "..q.title
  self.db.inbox[self.Count(self.db.inbox)+1]="Approve with: "..approvalValue
  if self.ui and self.ui.pages and self.ui.pages[2] then self.ui.pages[2].approval:SetText(approvalValue) end
end
function QW:ApproveQuest(id,index,target)
  local q=self.db.quests[id]; index=tonumber(index)
  if not q or not index or not self:ValidateString(target,80) then return false,"Invalid approval." end
  self:Send("QUEST_APPROVED",target,{id,index}); return true
end
function QW:ReceiveApprovalResult(f,sender)
  local run=self.db.questRuns[f[3]]; local index=tonumber(f[4])
  if not run or run.owner~=sender or run.state~="awaiting approval" or run.index~=index then return end
  run.state="active"; self:FinishStep(run)
end
function QW:ReceiveDelivery(f,sender)
  local deliveryID,questID,index,itemID,count=f[3],f[4],tonumber(f[5]),f[6],tonumber(f[7]); local def=self:ParseItem(f[8])
  local q=self.db.quests[questID]
  if not self:ValidateString(deliveryID,120) or not q or q.owner~=self:PlayerName() or not index or not count or not def or def.id~=itemID or not q.steps[index] then return end
  local step=q.steps[index]; if step.type~="deliver" or step.itemID~=itemID or step.count~=count then return end
  if not self.db.processed.deliveries[deliveryID] then
    if not self:AddItem(def,count) then return end
    self.db.processed.deliveries[deliveryID]=true
  end
  self:Send("QUEST_DELIVERY_ACK",sender,{deliveryID,questID,index})
end
function QW:ReceiveDeliveryAck(f,sender)
  local run=self.db.questRuns[f[4]]; local index=tonumber(f[5]); if not run or run.owner~=sender or not run.pendingDelivery or run.pendingDelivery.id~=f[3] or run.pendingDelivery.index~=index then return end
  run.pendingDelivery=nil; self:FinishStep(run)
end
function QW:ResendDelivery(id)
  local run=self.db.questRuns[id]; local d=run and run.pendingDelivery
  if not d then return false end
  return self:Send("QUEST_DELIVERY",run.owner,{d.id,run.id,d.index,d.itemID,d.count,self:SerializeItem(d.definition)})
end
-- A complete two-person teaching scenario. Create it once, trade the letter, then share its quest.
function QW:CreateDemo()
  self.db.demo=self.db.demo or {}
  local demo=self.db.demo
  local function existingItem(id,name)
    if id and self.db.items[id] then return id end
    local itemID,item
    for itemID,item in pairs(self.db.items) do if item.name==name and item.creator==self.db.playerID then return itemID end end
  end
  local letter=existingItem(demo.letter,"Sealed Letter")
  if not letter then letter=self:CreateItem("Sealed Letter","Interface\\Icons\\INV_Letter_15","A wax-sealed letter intended for a trusted courier.",1) end
  local token=self:GetDefaultTokenID()
  if not letter or not token then return nil end
  local quest=demo.quest
  if not quest or not self.db.quests[quest] then
    local questID,definition
    for questID,definition in pairs(self.db.quests) do if definition.title=="Return of the Sealed Letter" and definition.owner==self:PlayerName() then quest=questID; break end end
  end
  if not quest then quest=self:CreateQuest("Return of the Sealed Letter","Carry the letter, return it through a delivery objective, then await approval.",{{type="dialogue",text="The courier's task begins."},{type="possess",itemID=letter,count=1,text="Carry the sealed letter."},{type="deliver",itemID=letter,count=1,text="Deliver the sealed letter back to its author."},{type="manual",text="The author confirms the return."}},token,1) end
  demo.letter,demo.token,demo.quest=letter,token,quest
  return letter,quest,token
end
function QW:CreateBoarDemo()
  self.db.demo=self.db.demo or {}; local demo=self.db.demo; local token=self:GetDefaultTokenID(); local quest=demo.boarQuest
  if not quest or not self.db.quests[quest] then
    local questID,definition
    for questID,definition in pairs(self.db.quests) do
      if definition.title=="Aldrassil Boar Hunt" and definition.owner==self:PlayerName() then quest=questID; break end
    end
  end
  if not quest then
    local places={{id="ilthalaine",zone="Teldrassil",x=58.7,y=44.3,radius=5,description="Conservator Ilthalaine in Shadowglen."},{id="aldrassil",zone="Shadowglen",description="Shadowglen around Aldrassil."}}
    local steps={{type="kill",itemID="",count=5,placeID="",mobName="npc:1984",text="Defeat five Young Thistle Boars."}}
    -- Targeting the exact NPC is already an interaction check. Do not gate
    -- this demo giver on map coordinates unavailable in some Forever clients.
    quest=self:CreateQuest("Aldrassil Boar Hunt","Help keep the paths around Aldrassil safe by defeating five young thistle boars.",steps,token,1,places,nil,nil,nil,"npc:2079","","The balance of nature is delicate, traveler. Defeat five young thistle boars near Aldrassil and report your success through Questweaver.","npc:2079")
  end
  local function migrateDemo(record)
    local step=record and record.steps and record.steps[1]
    if not record then return end
    if step and step.type=="kill" then step.mobName="npc:1984"; step.npcID=1984; step.placeID=""; step.text="Defeat five Young Thistle Boars." end
    record.places=record.places or {}; local giverPlace; local killPlace
    local i; for i=1,self.Count(record.places) do
      if record.places[i].id=="ilthalaine" then giverPlace=record.places[i] end
      if record.places[i].id=="aldrassil" then killPlace=record.places[i] end
    end
    if not giverPlace then giverPlace={id="ilthalaine",zone="Teldrassil",x=58.7,y=44.3,radius=5,description="Conservator Ilthalaine in Shadowglen."}; record.places[self.Count(record.places)+1]=giverPlace end
    if not killPlace then killPlace={id="aldrassil"}; record.places[self.Count(record.places)+1]=killPlace end
    killPlace.zone="Shadowglen"; killPlace.x=nil; killPlace.y=nil; killPlace.radius=nil; killPlace.description="Shadowglen around Aldrassil."
    if record.placeByID then record.placeByID.ilthalaine=giverPlace end
    if record.placeByID then record.placeByID.aldrassil=killPlace end
    -- Migrate prior demo definitions/runs away from a coordinate-gated giver.
    record.giverNPCID=2079; record.giverPlaceID=""; record.giverDialogue="The balance of nature is delicate, traveler. Defeat five young thistle boars near Aldrassil and report your success through Questweaver."; record.turnInNPCID=2079; record.version=8
  end
  migrateDemo(self.db.quests[quest]); migrateDemo(self.db.questRuns[quest])
  demo.boarQuest=quest
  return quest,token
end
