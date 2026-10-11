local function split(text, separator, max)
  local out, start = {}, 1
  while true do
    local at = string.find(text, separator, start, true)
    if not at or (QW.Count(out) + 1) == max then out[QW.Count(out)+1]=string.sub(text,start); break end
    out[QW.Count(out)+1]=string.sub(text,start,at-1); start=at+1
  end
  return out
end
local function normaliseNarrative(value)
  if type(value)~="string" then return nil end
  value=string.gsub(value,"\r\n","\n"); value=string.gsub(value,"\r","\n")
  if QW.StrLen(value)<1 or QW.StrLen(value)>500 or string.find(string.gsub(value,"\n",""),"[%c]") then return nil end
  return value
end
local function serialiseSteps(steps)
  local out={}
  for i,s in ipairs(steps) do
    local ids=s.itemIDs or (s.itemID and s.itemID~="" and {s.itemID} or {})
    out[i]=table.concat({QW:Escape(s.type or ""),QW:Escape(s.itemID or ids[1] or ""),QW:Escape(s.count or ""),QW:Escape(s.placeID or ""),QW:Escape(s.mobName or ""),QW:Escape(s.text or ""),QW:Escape(s.stepNumber or i),QW:Escape(table.concat(ids,","))}, "~")
  end
  return table.concat(out,";")
end
local function parseSteps(raw)
  local out={}
  for line in string.gmatch(raw or "", "[^;]+") do
    local p=split(line,"~",8); local fields=QW.Count(p)
    -- Version 1 quests had four fields: type, item, count, text.
    if fields==4 then p[6]=p[4]; p[4]=""; p[5]=""; p[7]=""; p[8]=""
    elseif fields==6 then p[7]=""; p[8]=""
    elseif fields==7 then p[8]=""
    elseif fields~=8 then return nil end
    local i; for i=1,6 do p[i]=QW:Unescape(p[i]); if not p[i] then return nil end end; local count=tonumber(p[3] or "")
    p[8]=QW:Unescape(p[8] or ""); if not p[8] then return nil end
    local itemIDs,seen={},{}
    if p[8]~="" then for id in string.gmatch(p[8],"[^,]+") do if not QW:ValidateString(id,120) or seen[id] then return nil end; itemIDs[#itemIDs+1]=id; seen[id]=true; if #itemIDs>12 then return nil end end end
    if #itemIDs==0 and p[2]~="" then itemIDs[1]=p[2] end
    if (p[1]~="dialogue" and p[1]~="possess" and p[1]~="deliver" and p[1]~="manual" and p[1]~="visit" and p[1]~="loot" and p[1]~="collect" and p[1]~="kill") or not QW:ValidateString(p[6],300) then return nil end
    if (p[1]=="possess" or p[1]=="deliver" or p[1]=="loot" or p[1]=="collect") and (#itemIDs<1 or not count or count<1 or count>999) then return nil end
    if p[1]~="possess" and p[1]~="deliver" and p[1]~="loot" and p[1]~="collect" and #itemIDs>0 then return nil end
    if p[1]=="visit" and not QW:ValidateString(p[4],80) then return nil end
    if p[1]=="loot" and (not QW:ValidateString(p[4],80) or not QW:ValidateString(p[5],100)) then return nil end
    if p[1]=="collect" and not QW:ValidateString(p[4],80) then return nil end
    local npcID=tonumber(string.match(p[5] or "","^npc:(%d+)$")); local hasNPCPrefix=string.find(p[5] or "","^npc:")
    local stepNumber=tonumber(p[7]); if p[7]=="" then stepNumber=QW.Count(out)+1 end
    if not stepNumber or stepNumber<1 or stepNumber>99 or stepNumber~=math.floor(stepNumber) then return nil end
    if hasNPCPrefix and not npcID then return nil end
    if p[1]=="kill" and (not count or count<1 or count>999 or not QW:ValidateString(p[5],100)) then return nil end
    out[QW.Count(out)+1]={type=p[1],itemID=itemIDs[1] or "",itemIDs=itemIDs,count=count,placeID=p[4],mobName=p[5],npcID=npcID,text=p[6],stepNumber=stepNumber}; if QW.Count(out)>12 then return nil end
  end
  return QW.Count(out)>0 and out or nil
end
function QW:ParseSteps(raw) return parseSteps(raw) end
function QW:ObjectiveItemIDs(step)
  if type(step)~="table" then return {} end
  if type(step.itemIDs)=="table" and #step.itemIDs>0 then return step.itemIDs end
  if type(step.itemID)=="string" and step.itemID~="" then return {step.itemID} end
  return {}
end
function QW:GetObjectiveItemProgress(run,step,index)
  local rows={}; local delivered=run and run.deliveryProgress and run.deliveryProgress[index] or {}
  for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do
    local def=(run and run.itemDefinitions and run.itemDefinitions[itemID]) or self.db.items[itemID]
    local pending=run and run.pendingDelivery and run.pendingDelivery.index==index and run.pendingDelivery.itemID==itemID
    rows[#rows+1]={id=itemID,name=def and def.name or itemID,have=self.db.inventory[itemID] or 0,required=tonumber(step and step.count) or 1,delivered=delivered[itemID] and (tonumber(step and step.count) or 1) or 0,pending=pending and true or false}
  end
  return rows
end
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
-- Rewards are canonicalized as {id=..., count=...}.  Keep reading the old
-- rewardID/rewardCount pair so existing SavedVariables and incoming v9 quests
-- continue to work as a one-item reward list.
function QW:GetQuestRewards(record)
  local out={}
  if type(record)=="table" and type(record.rewards)=="table" and self.Count(record.rewards)>0 then
    for _,reward in ipairs(record.rewards) do
      local id=reward.id or reward.itemID
      local count=tonumber(reward.count)
      if self:ValidateString(id or "",120) and count and count>=1 and count<=999 and count==math.floor(count) then out[self.Count(out)+1]={id=id,count=count,item=reward.item or (record.itemDefinitions and record.itemDefinitions[id]) or self.db.items[id]} end
    end
  elseif type(record)=="table" then
    local id=record.rewardID or (record.reward and record.reward.id)
    local count=tonumber(record.rewardCount) or 1
    if self:ValidateString(id or "",120) and count>=1 and count<=999 and count==math.floor(count) then out[1]={id=id,count=count,item=record.reward or (record.itemDefinitions and record.itemDefinitions[id]) or self.db.items[id]} end
  end
  return out
end
function QW:DescribeQuestRewards(record)
  local lines={}
  for _,reward in ipairs(self:GetQuestRewards(record)) do
    local item=reward.item or self.db.items[reward.id]
    lines[self.Count(lines)+1]=(item and item.name or reward.id).." x"..reward.count
  end
  return self.Count(lines)>0 and table.concat(lines,", ") or "Reward data unavailable"
end
local function validateRewards(rewards)
  local checked,seen={},{}
  if type(rewards)~="table" or QW.Count(rewards)<1 or QW.Count(rewards)>12 then return nil end
  for _,reward in ipairs(rewards) do
    local id=reward.id or reward.itemID; local count=tonumber(reward.count) or 1
    if not QW:ValidateString(id or "",120) or not QW.db.items[id] or seen[id] or count<1 or count>999 or count~=math.floor(count) then return nil end
    checked[QW.Count(checked)+1]={id=id,count=count}; seen[id]=true
  end
  return checked
end
local function serialiseRewards(rewards)
  local out={}; for i,reward in ipairs(rewards) do out[i]=reward.id..","..reward.count end; return table.concat(out,";")
end
local function parseRewards(raw,definitions,legacyReward,legacyCount)
  if raw==nil or raw=="" then return {{id=legacyReward.id,count=legacyCount,item=legacyReward}} end
  local out,seen={},{}
  for entry in string.gmatch(raw,"[^;]+") do
    local id,count=string.match(entry,"^([^,]+),(%d+)$"); count=tonumber(count)
    local item=definitions[id]
    if not QW:ValidateString(id or "",120) or not item or seen[id] or not count or count<1 or count>999 then return nil end
    out[QW.Count(out)+1]={id=id,count=count,item=item}; seen[id]=true
    if QW.Count(out)>12 then return nil end
  end
  return QW.Count(out)>0 and out or nil
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
function QW:EnsureQuestItemCategories()
  local function classify(record,rewardID)
    if not record then return end
    if not record.rewards and rewardID then record.rewards={{id=rewardID,count=record.rewardCount or 1}} end
    for _,reward in ipairs(self:GetQuestRewards(record)) do
      if reward.item then reward.item.category="reward" end
      if self.db.items[reward.id] then self.db.items[reward.id].category="reward" end
    end
    for _,step in ipairs(record.steps or {}) do
      for _,id in ipairs(self:ObjectiveItemIDs(step)) do
        if record.itemDefinitions and record.itemDefinitions[id] then record.itemDefinitions[id].category="quest" end
        if self.db.items[id] then self.db.items[id].category="quest" end
      end
    end
    -- A reward remains a reward when it is also mentioned by an objective.
    for _,reward in ipairs(self:GetQuestRewards(record)) do if self.db.items[reward.id] then self.db.items[reward.id].category="reward" end end
  end
  for id,quest in pairs(self.db.quests or {}) do
    classify(quest,quest.rewardID)
    if quest.repeatable==nil then quest.repeatable=quest.giverNPCID~=nil end
    local run=self.db.questRuns[id]
    if run and run.repeatable==nil then run.repeatable=quest.repeatable end
  end
  for id,run in pairs(self.db.questRuns or {}) do
    classify(run)
    if run.repeatable==nil then
      local definition=self.db.quests[id]
      if definition then run.repeatable=definition.repeatable
      else run.repeatable=run.giverNPCID~=nil or run.acceptedFromNPC~=nil end
    end
  end
  for _,offer in pairs(self.db.questOffers or {}) do
    classify(offer)
    if offer.repeatable==nil then offer.repeatable=offer.giverNPCID~=nil end
  end
  for _,quest in pairs(self.db.followUpDefinitions or {}) do
    classify(quest)
    if quest.repeatable==nil then quest.repeatable=quest.giverNPCID~=nil end
  end
  self:MigrateDeliveriesToNPCHandoffs()
end

-- Delivery used to be a background transfer to the quest author.  That made
-- a recipient's quest wait indefinitely when the author was unavailable, and
-- did not represent handing an item to the NPC in the story.  Recover an
-- unacknowledged old transfer once, then use local handoffs.  Runs that
-- predate NPC delivery targets remain journal-completable for compatibility.
-- Already acknowledged items cannot safely be recovered here.
function QW:MigrateDeliveriesToNPCHandoffs()
  for _,run in pairs(self.db.questRuns or {}) do
    if run.state=="active" and not run.deliveryMode then
      local hasUntargetedDelivery=false
      for _,step in ipairs(run.steps or {}) do if step.type=="deliver" and not step.npcID then hasUntargetedDelivery=true end end
      local recovered=false
      local pending=run.pendingDelivery
      if pending then
        local definition=pending.definition or (run.itemDefinitions and run.itemDefinitions[pending.itemID]) or self.db.items[pending.itemID]
        if definition and self:AddItem(definition,pending.count) then recovered=true end
        run.pendingDelivery=nil
      end
      run.deliveryProgress={}
      run.deliveryMode=hasUntargetedDelivery and "legacy_local" or "npc"
      if recovered then
        self.db.inbox[self.Count(self.db.inbox)+1]="Recovered an unacknowledged delivery for "..(run.title or run.id)..". "..(hasUntargetedDelivery and "This older quest has no target NPC; progress it from the journal." or "Hand it to the objective NPC to continue.")
      end
    end
  end
end
function QW:KeepQuestItemDefinitions(record)
  for id,item in pairs(record and record.itemDefinitions or {}) do
    if not self.db.items[id] then self.db.items[id]=self:Copy(item)
    elseif item.category=="quest" or item.category=="reward" then self.db.items[id].category=item.category end
  end
end
function QW:RegisterQuest()
  self:EnsureQuestItemCategories()
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
local function optionalSuggestedLevel(value)
  if value==nil or value=="" then return nil end
  local level=tonumber(value)
  if not level or level<1 or level>999 or level~=math.floor(level) then return false end
  return level
end
local function optionalSuggestedPlayers(value)
  if value==nil or value=="" then return nil end
  local players=tonumber(value)
  if not players or players<1 or players>40 or players~=math.floor(players) then return false end
  return players
end
local function shareFields(q,giverOverride)
  local rewards=QW:GetQuestRewards(q)
  if QW.Count(rewards)<1 then return nil,"The quest reward definition is missing." end
  local reward=QW.db.items[rewards[1].id]
  if not reward then return nil,"The quest reward definition is missing." end
  local j; for j=1,QW.Count(q.places or {}) do if not q.places[j].zone then return nil,"This older quest uses RP-only places; recreate it with a real zone/location." end end
  q.places=q.places or {}; q.itemDefinitions=q.itemDefinitions or {}
  for _,entry in ipairs(rewards) do
    local item=QW.db.items[entry.id]
    if not item then return nil,"A quest reward definition is missing." end
    q.itemDefinitions[entry.id]=q.itemDefinitions[entry.id] or item; q.itemDefinitions[entry.id].category="reward"
  end
  local i; for i=1,QW.Count(q.steps or {}) do for _,itemID in ipairs(QW:ObjectiveItemIDs(q.steps[i])) do q.itemDefinitions[itemID]=q.itemDefinitions[itemID] or QW.db.items[itemID] end end
  for i=1,QW.Count(q.steps or {}) do if q.steps[i].type=="deliver" and not q.steps[i].npcID then return nil,"Each delivery objective needs a targeted NPC." end end
  local i; for i=1,QW.Count(q.steps or {}) do for _,itemID in ipairs(QW:ObjectiveItemIDs(q.steps[i])) do q.itemDefinitions[itemID]=q.itemDefinitions[itemID] or QW.db.items[itemID] end end
  local followUpID=optionalQuestID(q.followUpQuestID)
  if followUpID==false then return nil,"The follow-up quest ID is invalid." end
  local giverNPCID=giverOverride and giverOverride.npcID or q.giverNPCID
  if giverNPCID and (type(giverNPCID)~="number" or giverNPCID<1) then return nil,"The quest giver NPC ID is invalid." end
  local giverPlaceID=giverOverride and "" or q.giverPlaceID or ""
  local giverDialogue=giverOverride and giverOverride.dialogue or q.giverDialogue or ""
  if ((giverPlaceID and giverPlaceID~="") or (giverDialogue and giverDialogue~="")) and not giverNPCID then return nil,"Quest giver dialogue needs a quest giver NPC." end
  if giverPlaceID and giverPlaceID~="" and not QW:ValidateString(giverPlaceID,80) then return nil,"The quest giver place ID is invalid." end
  if giverDialogue and giverDialogue~="" and not QW:ValidateString(giverDialogue,500) then return nil,"The quest giver dialogue is invalid." end
  local turnInNPCID=q.turnInNPCID
  if turnInNPCID and (type(turnInNPCID)~="number" or turnInNPCID<1) then return nil,"The reward NPC ID is invalid." end
  return {q.id,q.version,q.title,q.description,serialiseSteps(q.steps),QW:SerializeItem(reward),rewards[1].count,serialisePlaces(q.places),definitionWire(q.itemDefinitions),followUpID or "",giverNPCID and ("npc:"..giverNPCID) or "",giverPlaceID or "",giverDialogue or "",turnInNPCID and ("npc:"..turnInNPCID) or "",q.repeatable and "1" or "0",q.suggestedLevel or "",q.suggestedPlayers or "",serialiseRewards(rewards)}
end
local function decodeSharedQuest(f,offset,sender)
  if QW.Count(f)<offset+8 or QW.Count(f)>offset+17 then return nil end
  local id,ver=f[offset],tonumber(f[offset+1]); local steps=parseSteps(f[offset+4]); local reward=QW:ParseItem(f[offset+5]); local count=tonumber(f[offset+6]); local places,placeByID=parsePlaces(f[offset+7]); local definitions=parseDefinitions(f[offset+8]); local followUpID=optionalQuestID(f[offset+9])
  local giverNPCID=optionalNPCID(f[offset+10]); local giverPlaceID=f[offset+11] or ""; local giverDialogue=f[offset+12] or ""; local turnInNPCID=optionalNPCID(f[offset+13])
  local repeatField=f[offset+14]
  if repeatField~=nil and repeatField~="0" and repeatField~="1" then return nil end
  local repeatable
  if repeatField~=nil then repeatable=repeatField=="1" else repeatable=giverNPCID~=nil end
  local suggestedLevel=optionalSuggestedLevel(f[offset+15])
  if suggestedLevel==false then return nil end
  local suggestedPlayers=optionalSuggestedPlayers(f[offset+16])
  if suggestedPlayers==false then return nil end
  if not QW:ValidateString(id,120) or not ver or not QW:ValidateString(f[offset+2] or "",100) or not QW:ValidateString(f[offset+3] or "",500) or not steps or not reward or not count or count<1 or count>999 or not places or not definitions or followUpID==false or followUpID==id or giverNPCID==false or turnInNPCID==false or (giverNPCID==nil and (giverPlaceID~="" or giverDialogue~="")) or (giverPlaceID~="" and not QW:ValidateString(giverPlaceID,80)) or (giverDialogue~="" and not QW:ValidateString(giverDialogue,500)) then return nil end
  definitions[reward.id]=definitions[reward.id] or reward
  local rewards=parseRewards(f[offset+17],definitions,reward,count)
  if not rewards then return nil end
  local i; for i=1,QW.Count(steps) do
    local step=steps[i]
    if step.placeID~="" and not placeByID[step.placeID] then return nil end
    for _,itemID in ipairs(QW:ObjectiveItemIDs(step)) do if not definitions[itemID] then definitions[itemID]=QW.db.items[itemID]; if not definitions[itemID] then return nil end end end
  end
  reward.category="reward"
  for _,entry in ipairs(rewards) do definitions[entry.id].category="reward" end
  for i=1,QW.Count(steps) do for _,itemID in ipairs(QW:ObjectiveItemIDs(steps[i])) do if definitions[itemID] then definitions[itemID].category="quest" end end end
  for _,entry in ipairs(rewards) do definitions[entry.id].category="reward" end
  if giverPlaceID~="" and not placeByID[giverPlaceID] then return nil end
  return {id=id,owner=sender,title=f[offset+2],description=f[offset+3],steps=steps,places=places,placeByID=placeByID,itemDefinitions=definitions,rewards=rewards,reward=reward,rewardID=reward.id,rewardCount=count,version=ver,followUpQuestID=followUpID,giverNPCID=giverNPCID,giverPlaceID=giverPlaceID,giverDialogue=giverDialogue,turnInNPCID=turnInNPCID,repeatable=repeatable,suggestedLevel=suggestedLevel,suggestedPlayers=suggestedPlayers}
end
function QW:CreateQuest(title, description, steps, rewardID, rewardCount, places, extraItemIDs, followUpQuestID, predecessorQuestID, giverNPCSpec, giverPlaceID, giverDialogue, turnInNPCSpec, existingID, repeatable, suggestedLevel, suggestedPlayers)
  local rewards=validateRewards(type(rewardID)=="table" and rewardID or {{id=rewardID,count=rewardCount}})
  local checkedSteps=parseSteps(serialiseSteps(steps)); local checkedPlaces, placeByID=parsePlaces(serialisePlaces(places))
  local followUpID=optionalQuestID(followUpQuestID); local predecessorID=optionalQuestID(predecessorQuestID)
  local giverNPCID=optionalNPCID(giverNPCSpec); local turnInNPCID=optionalNPCID(turnInNPCSpec); giverPlaceID=giverPlaceID or ""; giverDialogue=giverDialogue or ""
  local checkedSuggestedLevel=optionalSuggestedLevel(suggestedLevel)
  local checkedSuggestedPlayers=optionalSuggestedPlayers(suggestedPlayers)
  if repeatable~=nil and type(repeatable)~="boolean" then return nil,"Repeatable must be enabled or disabled." end
  if checkedSuggestedLevel==false then return nil,"Suggested level must be a whole number from 1 to 999." end
  if checkedSuggestedPlayers==false then return nil,"Suggested player count must be a whole number from 1 to 40." end
  if not self:ValidateString(title,100) or not self:ValidateString(description,500) or not checkedSteps or not checkedPlaces or not rewards or followUpID==false or predecessorID==false or giverNPCID==false or turnInNPCID==false or (giverNPCID==nil and (giverPlaceID~="" or giverDialogue~="")) or (giverPlaceID~="" and not self:ValidateString(giverPlaceID,80)) or (giverDialogue~="" and not self:ValidateString(giverDialogue,500)) then return nil,"Quest details are invalid." end
  if giverPlaceID~="" and not placeByID[giverPlaceID] then return nil,"The quest giver place must be defined in Real locations." end
  if followUpID and not self.db.quests[followUpID] then return nil,"The selected follow-up quest does not exist." end
  if predecessorID and not self.db.quests[predecessorID] then return nil,"The selected predecessor quest does not exist." end
  if predecessorID and self.db.quests[predecessorID].followUpQuestID and self.db.quests[predecessorID].followUpQuestID~="" and self.db.quests[predecessorID].followUpQuestID~=existingID then return nil,"That predecessor already has a follow-up quest." end
  if followUpID and self.db.quests[followUpID].predecessorQuestID and self.db.quests[followUpID].predecessorQuestID~="" and self.db.quests[followUpID].predecessorQuestID~=existingID then return nil,"That follow-up quest already has a predecessor." end
  local definitions={}; for _,reward in ipairs(rewards) do definitions[reward.id]=self.db.items[reward.id] end
  local i; for i=1,self.Count(checkedSteps) do
    local step=checkedSteps[i]
    if step.placeID~="" and not placeByID[step.placeID] then return nil,"A step refers to a place that is not defined." end
    if step.type=="deliver" and not step.npcID then return nil,"Each delivery objective needs a targeted NPC." end
    for _,itemID in ipairs(step.itemIDs or {}) do if not self.db.items[itemID] then return nil,"A step refers to an unknown RP item." end; definitions[itemID]=self.db.items[itemID] end
  end
  for i=1,self.Count(extraItemIDs or {}) do local itemID=extraItemIDs[i]; if not self.db.items[itemID] then return nil,"An assigned quest item does not exist." end; definitions[itemID]=self.db.items[itemID] end
  local definitionCount=0; for _ in pairs(definitions) do definitionCount=definitionCount+1 end
  if definitionCount>24 then return nil,"A quest can include at most 24 distinct item definitions, including its reward." end
  for i=1,self.Count(checkedSteps) do for _,itemID in ipairs(checkedSteps[i].itemIDs or {}) do self.db.items[itemID].category="quest" end end
  for _,reward in ipairs(rewards) do self.db.items[reward.id].category="reward" end
  local previous=existingID and self.db.quests[existingID]
  if existingID and (not previous or previous.owner~=self:PlayerName()) then return nil,"Only your own quest can be edited." end
  if repeatable==nil then repeatable=previous and previous.repeatable or false end
  local id=existingID or self:NewID("quest")
  if previous then
    if previous.predecessorQuestID and self.db.quests[previous.predecessorQuestID] and self.db.quests[previous.predecessorQuestID].followUpQuestID==id then self.db.quests[previous.predecessorQuestID].followUpQuestID=nil end
    if previous.followUpQuestID and self.db.quests[previous.followUpQuestID] and self.db.quests[previous.followUpQuestID].predecessorQuestID==id then self.db.quests[previous.followUpQuestID].predecessorQuestID=nil end
  end
  self.db.quests[id]={id=id,owner=self:PlayerName(),title=title,description=description,steps=checkedSteps,places=checkedPlaces,itemDefinitions=definitions,rewards=rewards,rewardID=rewards[1].id,rewardCount=rewards[1].count,followUpQuestID=followUpID,predecessorQuestID=predecessorID,giverNPCID=giverNPCID,giverPlaceID=giverPlaceID,giverDialogue=giverDialogue,turnInNPCID=turnInNPCID,repeatable=repeatable,suggestedLevel=checkedSuggestedLevel,suggestedPlayers=checkedSuggestedPlayers,version=(previous and (previous.version or 1)+1 or 9)}
  if predecessorID then self.db.quests[predecessorID].followUpQuestID=id end
  if followUpID then self.db.quests[followUpID].predecessorQuestID=id end
  return id
end
function QW:DeleteQuest(id)
  local quest=self.db.quests[id]
  if not quest or quest.owner~=self:PlayerName() then return false,"Only your own quest definition can be deleted." end
  for _,run in pairs(self.db.questRuns or {}) do if run.id==id and run.state~="complete" then return false,"This quest still has an open run. Finish or remove it before deleting the definition." end end
  for _,set in pairs(self.db.sets or {}) do for _,questID in ipairs(set.questIDs or {}) do if questID==id then return false,"Remove this quest from its Questweaver Set first." end end end
  for _,dialogue in pairs(self.db.npcDialogs or {}) do for _,questID in ipairs(dialogue.questIDs or {}) do if questID==id then return false,"Remove this quest from its NPC conversation first." end end end
  if quest.predecessorQuestID and self.db.quests[quest.predecessorQuestID] and self.db.quests[quest.predecessorQuestID].followUpQuestID==id then self.db.quests[quest.predecessorQuestID].followUpQuestID=nil end
  if quest.followUpQuestID and self.db.quests[quest.followUpQuestID] and self.db.quests[quest.followUpQuestID].predecessorQuestID==id then self.db.quests[quest.followUpQuestID].predecessorQuestID=nil end
  self.db.quests[id]=nil
  if self.RefreshUI then self:RefreshUI() end
  return true,"Quest definition deleted. Completed quest records are retained."
end
function QW:ShareQuestWithKind(id,target,firstKind,giverOverride)
  local q=self.db.quests[id]
  if not q or not self:ValidateString(target,80) then return false,"Choose a quest and recipient." end
  local chain,seen={},{}
  local current=q; local depth
  for depth=1,6 do
    if seen[current.id] then return false,"The follow-up quest chain contains a loop." end
    seen[current.id]=true
    local fields,message=shareFields(current,depth==1 and giverOverride or nil); if not fields then return false,message end
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
function QW:SaveNPCDialogue(id,npcSpec,npcName,title,dialogue,questIDs)
  if id=="" then id=nil end
  local npcID=optionalNPCID(npcSpec); dialogue=normaliseNarrative(dialogue)
  if not npcID or not self:ValidateString(npcName or "NPC",100) or not self:ValidateString(title,100) or not dialogue or type(questIDs)~="table" or self.Count(questIDs)>12 then return nil,"NPC narrative details are invalid." end
  local previous=id and self.db.npcDialogs[id]
  if id and (not previous or previous.owner~=self:PlayerName()) then return nil,"Only your own NPC narrative can be edited." end
  local seen={}
  for i=1,self.Count(questIDs) do
    local questID=questIDs[i]; local quest=self.db.quests[questID]
    if not quest or quest.owner~=self:PlayerName() or seen[questID] then return nil,"Choose only your own quests, with no duplicates." end
    seen[questID]=true
  end
  id=id or self:NewID("npcdialog")
  self.db.npcDialogs[id]={id=id,owner=self:PlayerName(),npcID=npcID,npcName=npcName,title=title,dialogue=dialogue,questIDs=self:Copy(questIDs),version=(previous and (previous.version or 0)+1 or 1)}
  return id,"NPC narrative saved."
end
function QW:DeleteNPCDialogue(id)
  local dialogue=self.db.npcDialogs[id]
  if not dialogue or dialogue.owner~=self:PlayerName() then return false,"Only your own NPC narrative can be deleted." end
  self.db.npcDialogs[id]=nil
  return true,"NPC narrative deleted. Its quest definitions were not changed."
end
function QW:ShareNPCDialogue(id,target)
  local dialogue=self.db.npcDialogs[id]
  if not dialogue or not self:ValidateString(target,80) then return false,"Choose a saved NPC narrative and recipient." end
  if self.Count(dialogue.questIDs or {})==0 then
    local fields={dialogue.id,dialogue.version or 1,"npc:"..dialogue.npcID,dialogue.npcName,dialogue.title,dialogue.dialogue}
    if self.StrLen(self:Pack("NPC_DIALOGUE",fields))>4096 then return false,"This NPC narrative is too large to share." end
    if not self:Send("NPC_DIALOGUE",target,fields) then return false,"Could not share the NPC narrative." end
    return true,"NPC narrative shared."
  end
  local sent=0
  for i=1,self.Count(dialogue.questIDs) do
    local ok,message=self:ShareQuestWithKind(dialogue.questIDs[i],target,"QUEST_OFFER",{npcID=dialogue.npcID,dialogue=dialogue.dialogue})
    if not ok then return false,"Shared "..sent.." quest offer(s); stopped because: "..tostring(message) end
    sent=sent+1
  end
  return true,"NPC narrative shared with "..sent.." quest offer(s)."
end
function QW:ReceiveNPCDialogue(f,sender)
  if self.Count(f)~=8 then return end
  local id,version=f[3],tonumber(f[4]); local npcID=optionalNPCID(f[5])
  local npcName,title,dialogue=f[6],f[7],normaliseNarrative(f[8])
  if not self:ValidateString(id,120) or not version or version<1 or version~=math.floor(version) or not npcID or not self:ValidateString(npcName,100) or not self:ValidateString(title,100) or not dialogue then return end
  local existing=self.db.npcDialogs[id]
  if existing and (existing.owner==self:PlayerName() or (existing.version or 0)>=version) then return end
  self.db.npcDialogs[id]={id=id,owner=sender,npcID=npcID,npcName=npcName,title=title,dialogue=dialogue,questIDs={},version=version}
  self.db.inbox[self.Count(self.db.inbox)+1]="NPC narrative received from "..sender..": "..title
end
function QW:ReceiveQuest(f,sender)
  local run=decodeSharedQuest(f,3,sender); if not run then return end
  local existing=self.db.questRuns[run.id]
  if existing and existing.version>=run.version then return end
  self:KeepQuestItemDefinitions(run)
  run.index=1; run.completedObjectives={}; run.pendingApprovals={}; run.state="active"; run.delivered={}; self.db.questRuns[run.id]=run
  self.db.inbox[self.Count(self.db.inbox)+1]="Quest received from "..sender..": "..run.title
end
function QW:ReceiveQuestOffer(f,sender)
  local offer=decodeSharedQuest(f,3,sender); if not offer then return end
  if not offer.giverNPCID or not offer.giverDialogue or offer.giverDialogue=="" then return end
  local existing=self.db.questOffers[offer.id]
  if existing and existing.version>=offer.version then return end
  if self.db.questRuns[offer.id] then return end
  self:KeepQuestItemDefinitions(offer)
  self.db.questOffers[offer.id]=offer
  self.db.inbox[self.Count(self.db.inbox)+1]="NPC quest offer received from "..sender..": "..offer.title
end
function QW:ReceiveFollowUpQuest(f,sender)
  local parentID=f[3]; if not self:ValidateString(parentID or "",120) then return end
  local quest=decodeSharedQuest(f,4,sender); if not quest or quest.id==parentID then return end
  self:KeepQuestItemDefinitions(quest)
  local parent=self.db.questRuns[parentID] or self.db.questOffers[parentID]
  if parent and (parent.owner~=sender or parent.followUpQuestID~=quest.id) then return end
  local existing=self.db.followUpDefinitions[parentID]
  if existing and existing.version>=quest.version then return end
  self.db.followUpDefinitions[parentID]=quest
  self.db.inbox[self.Count(self.db.inbox)+1]="Follow-up received for "..parentID..": "..quest.title
  if parent and parent.state=="complete" then self:ActivateFollowUp(parent) end
end
local function copyRewardsToRun(source,definitions)
  local rewards={}
  for _,entry in ipairs(QW:GetQuestRewards(source)) do
    local item=definitions[entry.id] or QW.db.items[entry.id]
    if not item then return nil end
    item.category="reward"; definitions[entry.id]=item
    rewards[QW.Count(rewards)+1]={id=entry.id,count=entry.count,item=item}
  end
  return QW.Count(rewards)>0 and rewards or nil
end
function QW:AssignQuestToCurrentPlayer(id)
  local q=self.db.quests[id]
  if not q then return false,"Quest definition was not found." end
  if self.db.questRuns[id] then return true,"Quest is already active for this character." end
  local places=self:Copy(q.places or {}); local placeByID={}; local i
  for i=1,self.Count(places) do placeByID[places[i].id]=places[i] end
  local definitions=self:Copy(q.itemDefinitions or {}); local rewards=copyRewardsToRun(q,definitions)
  if not rewards then return false,"Quest reward definition was not found." end
  for _,step in ipairs(q.steps or {}) do for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do if definitions[itemID] then definitions[itemID].category="quest" end end end
  for _,entry in ipairs(rewards) do definitions[entry.id].category="reward" end
  self.db.questRuns[id]={id=id,owner=q.owner or self:PlayerName(),title=q.title,description=q.description,steps=self:Copy(q.steps),places=places,placeByID=placeByID,itemDefinitions=definitions,rewards=rewards,reward=rewards[1].item,rewardID=rewards[1].id,rewardCount=rewards[1].count,version=q.version,followUpQuestID=q.followUpQuestID,turnInNPCID=q.turnInNPCID,repeatable=q.repeatable==true,suggestedLevel=q.suggestedLevel,suggestedPlayers=q.suggestedPlayers,giverNPCID=q.giverNPCID,index=1,completedObjectives={},pendingApprovals={},state="active",delivered={},assignedLocally=true}
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
  local definitions=self:Copy(offer.itemDefinitions or {}); local rewards=copyRewardsToRun(offer,definitions)
  if not rewards then return false,"This NPC quest offer has invalid reward data." end
  for _,step in ipairs(offer.steps or {}) do for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do if definitions[itemID] then definitions[itemID].category="quest" end end end
  for _,entry in ipairs(rewards) do definitions[entry.id].category="reward" end
  self.db.questRuns[id]={id=offer.id,owner=offer.owner,title=offer.title,description=offer.description,steps=self:Copy(offer.steps),places=places,placeByID=placeByID,itemDefinitions=definitions,rewards=rewards,reward=rewards[1].item,rewardID=rewards[1].id,rewardCount=rewards[1].count,version=offer.version,followUpQuestID=offer.followUpQuestID,turnInNPCID=offer.turnInNPCID,repeatable=offer.repeatable==true,suggestedLevel=offer.suggestedLevel,suggestedPlayers=offer.suggestedPlayers,giverNPCID=offer.giverNPCID,index=1,completedObjectives={},pendingApprovals={},state="active",delivered={},acceptedFromNPC=offer.giverNPCID}
  self.db.questOffers[id]=nil
  self.db.inbox[self.Count(self.db.inbox)+1]="Accepted NPC quest: "..offer.title
  return true,(offer.giverDialogue and offer.giverDialogue~="" and offer.giverDialogue.." " or "").."Quest accepted."
end
function QW:GetNPCInteractionOptions(npcID)
  local groups={new={},custom={},ready={},progress={},done={},repeatQuests={}}
  if npcID==2079 then self:CreateBoarDemo() end
  local id,quest,run,offer
  local function addCustom(option)
    for _,existing in ipairs(groups.custom) do if existing.text==option.text then return end end
    groups.custom[self.Count(groups.custom)+1]=option
  end
  for id,dialogue in pairs(self.db.npcDialogs or {}) do
    if dialogue.npcID==npcID then
      addCustom({kind="npcdialogue",id=id,title=dialogue.title,text=dialogue.dialogue})
      for _,questID in ipairs(dialogue.questIDs or {}) do
        quest=self.db.quests[questID]; run=self.db.questRuns[questID]
        local alreadyListed=false
        for _,entry in ipairs(groups.new) do if entry.id==questID then alreadyListed=true end end
        if quest and not run and not alreadyListed then
          groups.new[self.Count(groups.new)+1]={kind="dialogquest",id=questID,title=quest.title,text=(quest.description or "").."\n\nRewards: "..self:DescribeQuestRewards(quest),dialogue=dialogue.dialogue}
        end
      end
    end
  end
  for id,offer in pairs(self.db.questOffers) do
    if offer.giverNPCID==npcID and not self.db.questRuns[id] then
      groups.new[self.Count(groups.new)+1]={kind="offer",id=id,title=offer.title,text=(offer.description or "").."\n\nRewards: "..self:DescribeQuestRewards(offer),dialogue=offer.giverDialogue}
      if offer.giverDialogue and offer.giverDialogue~="" then addCustom({kind="custom",id=id,title=offer.title,text=offer.giverDialogue}) end
    end
  end
  for id,quest in pairs(self.db.quests) do
    if quest.giverNPCID==npcID then
      run=self.db.questRuns[id]
      if not run then
        local alreadyListed=false
        for _,entry in ipairs(groups.new) do if entry.id==id then alreadyListed=true end end
        if not alreadyListed then groups.new[self.Count(groups.new)+1]={kind="quest",id=id,title=quest.title,text=(quest.description or "").."\n\nRewards: "..self:DescribeQuestRewards(quest),dialogue=quest.giverDialogue} end
      elseif run.state=="complete" then
        groups.done[self.Count(groups.done)+1]={kind="done",id=id,title=run.title or quest.title,text="You have already completed this quest."}
      elseif run.state=="active" then
        local currentIndices=self:GetCurrentObjectiveIndices(run); local matchingInteraction=false
        for _,stepIndex in ipairs(currentIndices) do local current=run.steps[stepIndex]; if (current.type=="dialogue" or current.type=="deliver") and current.mobName and current.mobName~="" and self:TargetMatchesStep(current) then matchingInteraction=true end end
        if not matchingInteraction then
          groups.progress[self.Count(groups.progress)+1]={kind="active",id=id,title=run.title or quest.title,text="This quest is already in your quest journal."}
        end
      end
      if quest.giverDialogue and quest.giverDialogue~="" then
        addCustom({kind="custom",id=id,title=quest.title,text=quest.giverDialogue})
      end
    end
  end
  for id,run in pairs(self.db.questRuns) do
    if run.turnInNPCID==npcID and run.state=="ready_to_turn_in" then
      groups.ready[self.Count(groups.ready)+1]={kind="turnin",id=id,title=run.title or id,text="Your objectives are complete. Receive your rewards: "..self:DescribeQuestRewards(run).."."}
    elseif run.state=="complete" and (run.turnInNPCID==npcID or run.giverNPCID==npcID or run.acceptedFromNPC==npcID) then
      local known=false; local i
      for i=1,self.Count(groups.done) do if groups.done[i].id==id then known=true end end
      if not known then
        groups.done[self.Count(groups.done)+1]={kind="done",id=id,title=run.title or id,text="You have already completed this quest."}
      end
      if run.repeatable==true and (run.giverNPCID==npcID or run.acceptedFromNPC==npcID) then groups.repeatQuests[self.Count(groups.repeatQuests)+1]={kind="repeat",id=id,title=run.title or id,text="Completed before. Accept this quest again?"} end
    end
    local currentIndices=self:GetCurrentObjectiveIndices(run)
    if run.state=="active" then for _,stepIndex in ipairs(currentIndices) do
      local step=run.steps[stepIndex]
      if (step.type=="dialogue" or step.type=="deliver") and step.mobName and step.mobName~="" and self:TargetMatchesStep(step) then
        local isDelivery=step.type=="deliver"
        groups.progress[self.Count(groups.progress)+1]={kind=isDelivery and "delivery" or "objective",id=id,stepIndex=stepIndex,title=(run.title or id).." - Step "..tostring(self:ObjectiveStepNumber(step,stepIndex)),text=step.text or (isDelivery and "Hand over the required RP items." or "Speak with this character to continue.")}
      end
    end
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
  elseif option.kind=="dialogquest" then
    local ok,message=self:AssignQuestToCurrentPlayer(option.id)
    if ok then
      local run=self.db.questRuns[option.id]; run.giverNPCID=npcID; run.acceptedFromNPC=npcID
      if option.dialogue and option.dialogue~="" then return true,option.dialogue.." Quest accepted." end
    end
    return ok,message
  elseif option.kind=="npcdialogue" then
    return true,option.text
  elseif option.kind=="custom" then return true,option.text
  elseif option.kind=="turnin" then
    local run=self.db.questRuns[option.id]; if not run then return false,"This quest is no longer available." end
    return self:CompleteQuest(run)
  elseif option.kind=="objective" then
    local ok,message=self:AdvanceQuest(option.id,option.stepIndex)
    if ok then return true,"["..(option.title or option.id).."] "..(message or "Dialogue objective complete.") end
    return false,message
  elseif option.kind=="delivery" then
    local ok,message=self:AdvanceQuest(option.id,option.stepIndex,true)
    if ok then return true,"["..(option.title or option.id).."] "..(message or "Items handed over.") end
    return false,message
  elseif option.kind=="active" then
    if self.ShowQuestJournal then self:ShowQuestJournal() end
    return true,"Opened your Questweaver quest journal."
  elseif option.kind=="repeat" then
    local run=self.db.questRuns[option.id]
    if not run or run.state~="complete" then return false,"This quest is no longer available to repeat." end
    if run.repeatable~=true then return false,"This quest cannot be repeated." end
    run.index=1; run.completedObjectives={}; run.pendingApprovals={}; run.killProgress={}; run.state="active"; run.delivered={}; run.pendingDelivery=nil; run.deliveryProgress={}; run.completedAt=nil
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
  for _ in pairs(self.db.questRuns) do count=count+1 end
  self.db.questRuns={}
  return true,"Removed "..count.." accepted quest record"..(count==1 and "." or "s.")
end
function QW:IsObjectiveComplete(run,index)
  if run.completedObjectives then return run.completedObjectives[index]==true end
  return index<(tonumber(run.index) or 1)
end
function QW:ObjectiveStepNumber(step,index)
  return tonumber(step and step.stepNumber) or index
end
function QW:GetCurrentObjectiveIndices(run)
  local indices,number={},nil
  if not run or not run.steps then return indices end
  for i=1,self.Count(run.steps) do if not self:IsObjectiveComplete(run,i) then local stepNumber=self:ObjectiveStepNumber(run.steps[i],i); if not number or stepNumber<number then number=stepNumber end end end
  if not number then return indices end
  for i=1,self.Count(run.steps) do if not self:IsObjectiveComplete(run,i) and self:ObjectiveStepNumber(run.steps[i],i)==number then indices[self.Count(indices)+1]=i end end
  return indices,number
end
function QW:UpdateRunIndex(run)
  run.index=self.Count(run.steps or {})+1
  for i=1,self.Count(run.steps or {}) do if not self:IsObjectiveComplete(run,i) then run.index=i; break end end
end
function QW:AdvanceObjective(run,index)
  local step=run.steps[index]; if not step or self:IsObjectiveComplete(run,index) then return false,"This objective is not active." end
  local current=self:GetCurrentObjectiveIndices(run); local unlocked=false
  for _,currentIndex in ipairs(current) do if currentIndex==index then unlocked=true end end
  if not unlocked then return false,"This objective is locked until earlier steps are complete." end
  -- Dialogue is a target-and-interact objective; proximity is enforced by
  -- selecting the NPC in-game, not by map coordinates or zone text.
  if step.placeID~="" and step.type~="dialogue" then
    local ok,message=self:AtPlace(run.placeByID and run.placeByID[step.placeID])
    if not ok then return false,message end
  end
  if (step.type=="dialogue" or step.type=="deliver") and step.mobName~="" then
    local ok,message=self:TargetMatchesStep(step); if not ok then return false,message end
  end
  if step.type=="dialogue" then return self:FinishStep(run,index)
  elseif step.type=="possess" then
    for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do if not self:HasItem(itemID,step.count) then return false,"Required RP item is not in your inventory." end end
    return self:FinishStep(run,index)
  elseif step.type=="visit" then return self:FinishStep(run,index)
  elseif step.type=="collect" then
    for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do
      local definition=run.itemDefinitions[itemID]; if definition then definition.category="quest" end
      if not definition or not self:AddItem(definition,step.count) then return false,"This quest's collection item definition is invalid." end
    end
    return self:FinishStep(run,index)
  elseif step.type=="loot" then
    local targetName=UnitName("target")
    if targetName~=step.mobName then return false,"Target the defined mob ("..step.mobName..") before collecting this RP loot." end
    for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do
      local definition=run.itemDefinitions[itemID]; if definition then definition.category="quest" end
      if not definition or not self:AddItem(definition,step.count) then return false,"This quest's loot definition is invalid." end
    end
    return self:FinishStep(run,index)
  elseif step.type=="kill" then return false,"Defeat "..step.mobName.." to update this objective."
  elseif step.type=="manual" then
    run.pendingApprovals=run.pendingApprovals or {}; if run.pendingApprovals[index] then return false,"Approval is already pending for this objective." end
    run.pendingApprovals[index]=true; self:Send("QUEST_APPROVAL",run.owner,{run.id,index})
    self:Print("["..(run.title or run.id).."] Approval requested for: "..step.text)
    return true,"Approval request sent to the quest owner."
  elseif step.type=="deliver" then
    for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do if not self:HasItem(itemID,step.count) then return false,"Required RP item is not in your inventory: "..(self.db.items[itemID] and self.db.items[itemID].name or itemID).."." end end
    for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do
      if not self:TakeItem(itemID,step.count) then return false,"The RP item could not be handed over." end
    end
    run.deliveryMode="npc"; run.deliveryProgress=run.deliveryProgress or {}; run.deliveryProgress[index]=run.deliveryProgress[index] or {}
    for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do run.deliveryProgress[index][itemID]=true end
    local ok,message=self:FinishStep(run,index)
    if ok then return true,"Items handed to the NPC. "..(message or "") end
    return false,message
  end
end
function QW:SendNextObjectiveDelivery(run,index)
  if not run or run.pendingDelivery then return false end
  local step=run.steps[index]; if not step or step.type~="deliver" then return false end
  run.deliveryProgress=run.deliveryProgress or {}; run.deliveryProgress[index]=run.deliveryProgress[index] or {}
  for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do
    if not run.deliveryProgress[index][itemID] then
      local def=self.db.items[itemID]
      if not def or not self:TakeItem(itemID,step.count) then return false end
      local deliveryID=self:NewID("delivery")
      run.pendingDelivery={id=deliveryID,index=index,itemID=itemID,count=step.count,definition=def}
      return self:Send("QUEST_DELIVERY",run.owner,{deliveryID,run.id,index,itemID,step.count,self:SerializeItem(def)})
    end
  end
  return true
end
function QW:AdvanceQuest(id,onlyIndex,fromNPCInteraction)
  local run=self.db.questRuns[id]; if not run or run.state~="active" then return false,"This quest is not active." end
  local indices=self:GetCurrentObjectiveIndices(run)
  if onlyIndex then local found=false; for _,index in ipairs(indices) do if index==onlyIndex then found=true end end; if not found then return false,"That objective is not in the active step." end; indices={onlyIndex} end
  local progressed,firstError=0,nil
  for _,index in ipairs(indices) do
    if not self:IsObjectiveComplete(run,index) then
      local step=run.steps[index]
      if step.type=="kill" then if not firstError then firstError="Defeat "..step.mobName.." to update this objective." end
      elseif step.type=="manual" and run.pendingApprovals and run.pendingApprovals[index] then if not firstError then firstError="Approval is already pending for this objective." end
      elseif step.type=="deliver" and not fromNPCInteraction and run.deliveryMode~="legacy_local" then if not firstError then firstError="Talk to the target NPC and choose Hand over items to complete this delivery." end
      else
        local ok,message=self:AdvanceObjective(run,index)
        if ok then progressed=progressed+1 elseif not firstError then firstError=message end
      end
    end
  end
  if progressed>0 then return true,progressed==1 and "Objective progressed." or (progressed.." parallel objectives progressed.") end
  return false,firstError or "No objective in this step could be progressed."
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
  self:RollItemDrops(targetNPCID,targetGUID)
  local updated=false
  for _,run in pairs(self.db.questRuns) do
    if run.state=="active" then
      local indices=self:GetCurrentObjectiveIndices(run)
      for _,index in ipairs(indices) do
        local step=run.steps[index]
        local matches=step and step.type=="kill" and ((step.npcID and step.npcID==targetNPCID) or (not step.npcID and step.mobName==targetName))
        if matches then
          -- Matching kill objectives in the active parallel group all progress.
          run.killProgress=run.killProgress or {}; local progress=math.min((run.killProgress[index] or 0)+1,step.count); run.killProgress[index]=progress; updated=true
          if progress>=step.count then self:FinishStep(run,index)
          else self:Print("["..(run.title or run.id).."] Kills: "..progress.." / "..step.count.." - "..step.text) end
        end
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
  local done=0; for i=1,total do if self:IsObjectiveComplete(run,i) then done=done+1 end end
  return done,total
end
function QW:FinishStep(run,index)
  index=index or run.index
  local step=run.steps[index]
  if not step or self:IsObjectiveComplete(run,index) then return false,"This objective is already complete or unavailable." end
  local currentIndices=self:GetCurrentObjectiveIndices(run); local isCurrent=false
  for _,currentIndex in ipairs(currentIndices) do if currentIndex==index then isCurrent=true end end
  if not isCurrent then return false,"This objective is locked until earlier steps are complete." end
  local objective=(step and step.text) or "Objective"
  run.completedObjectives=run.completedObjectives or {}
  if not next(run.completedObjectives) then local oldIndex=tonumber(run.index) or 1; for i=1,oldIndex-1 do run.completedObjectives[i]=true end end
  run.completedObjectives[index]=true
  self:UpdateRunIndex(run)
  local ok,message
  if run.index>self.Count(run.steps) then
    if run.turnInNPCID then
      run.state="ready_to_turn_in"; ok=true; message="Objectives complete. Return to NPC "..run.turnInNPCID.." and use /qw interact to receive your reward."
    else ok,message=self:CompleteQuest(run) end
  else
    local currentIndices,currentNumber=self:GetCurrentObjectiveIndices(run)
    local oldNumber=self:ObjectiveStepNumber(step,index)
    if self.Count(currentIndices)>0 and currentNumber==oldNumber then ok,message=true,"Objective complete. Other objectives in step "..tostring(currentNumber).." remain."
    elseif self.Count(currentIndices)>0 then ok,message=true,"Objective complete. Step "..tostring(currentNumber).." is now active."
    else ok,message=true,"Objective complete." end
  end
  if ok then self:Print("["..(run.title or run.id).."] "..objective.." complete. "..(message or "")) end
  if self.RefreshQuestTracker then self:RefreshQuestTracker() end
  return ok,message
end
function QW:CompleteQuest(run)
  if run.state=="complete" then return true end
  local rewards=self:GetQuestRewards(run); local totals={}
  if self.Count(rewards)<1 then return false,"Reward data was invalid." end
  for _,reward in ipairs(rewards) do
    local item=reward.item or (run.itemDefinitions and run.itemDefinitions[reward.id]) or self.db.items[reward.id]
    if not item then return false,"Reward data was invalid." end
    totals[reward.id]=(totals[reward.id] or 0)+reward.count
    if totals[reward.id]>item.maxStack or (self.db.inventory[reward.id] or 0)+totals[reward.id]>item.maxStack then return false,"Your RP Satchel does not have room for all rewards." end
  end
  for _,reward in ipairs(rewards) do
    local item=reward.item or (run.itemDefinitions and run.itemDefinitions[reward.id]) or self.db.items[reward.id]
    item.category="reward"
    if not self:AddItem(item,reward.count) then return false,"Reward data was invalid." end
  end
  self.db.questHistory=self.db.questHistory or {}
  self.db.questHistory[#self.db.questHistory+1]={id=run.id,title=run.title,completedAt=self.now(),owner=run.owner}
  run.state="complete"; run.completedAt=self.now()
  local followUpMessage=self:ActivateFollowUp(run)
  return true,"Quest complete! Rewards added to RP inventory."..(followUpMessage and (" "..followUpMessage) or "")
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
  local definitions=self:Copy(nextQuest.itemDefinitions or {}); local rewards=copyRewardsToRun(nextQuest,definitions)
  if not rewards then
    self.db.inbox[self.Count(self.db.inbox)+1]="Follow-up for "..run.title.." has invalid reward data."
    return "Follow-up quest could not be activated."
  end
  self.db.questRuns[followUpID]={id=nextQuest.id,owner=nextQuest.owner,title=nextQuest.title,description=nextQuest.description,steps=self:Copy(nextQuest.steps),places=places,placeByID=placeByID,itemDefinitions=definitions,rewards=rewards,reward=rewards[1].item,rewardID=rewards[1].id,rewardCount=rewards[1].count,version=nextQuest.version,followUpQuestID=nextQuest.followUpQuestID,turnInNPCID=nextQuest.turnInNPCID,repeatable=nextQuest.repeatable==true,suggestedLevel=nextQuest.suggestedLevel,suggestedPlayers=nextQuest.suggestedPlayers,giverNPCID=nextQuest.giverNPCID,index=1,completedObjectives={},pendingApprovals={},state="active",delivered={},activatedFrom=run.id}
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
  if self.ui and self.ui.pages and self.ui.pages[3] then self.ui.pages[3].approval:SetText(approvalValue) end
end
function QW:ApproveQuest(id,index,target)
  local q=self.db.quests[id]; index=tonumber(index)
  if not q or not index or not self:ValidateString(target,80) then return false,"Invalid approval." end
  self:Send("QUEST_APPROVED",target,{id,index}); return true
end
function QW:ReceiveApprovalResult(f,sender)
  local run=self.db.questRuns[f[3]]; local index=tonumber(f[4])
  if not run or run.owner~=sender or not index then return end
  run.pendingApprovals=run.pendingApprovals or {}
  if run.state=="awaiting approval" and not next(run.pendingApprovals) then run.pendingApprovals[run.index]=true end
  if not run.pendingApprovals[index] then return end
  run.pendingApprovals[index]=nil; run.state="active"; self:FinishStep(run,index)
end
function QW:ReceiveDelivery(f,sender)
  local deliveryID,questID,index,itemID,count=f[3],f[4],tonumber(f[5]),f[6],tonumber(f[7]); local def=self:ParseItem(f[8])
  local q=self.db.quests[questID]
  if not self:ValidateString(deliveryID,120) or not q or q.owner~=self:PlayerName() or not index or not count or not def or def.id~=itemID or not q.steps[index] then return end
  local step=q.steps[index]; local included=false
  for _,stepItemID in ipairs(self:ObjectiveItemIDs(step)) do if stepItemID==itemID then included=true end end
  if step.type~="deliver" or not included or step.count~=count then return end
  def.category="quest"
  if not self.db.processed.deliveries[deliveryID] then
    if not self:AddItem(def,count) then return end
    self.db.processed.deliveries[deliveryID]=true
  end
  self:Send("QUEST_DELIVERY_ACK",sender,{deliveryID,questID,index})
end
function QW:ReceiveDeliveryAck(f,sender)
  local run=self.db.questRuns[f[4]]; local index=tonumber(f[5]); if not run or run.owner~=sender or not run.pendingDelivery or run.pendingDelivery.id~=f[3] or run.pendingDelivery.index~=index then return end
  local deliveredItem=run.pendingDelivery.itemID
  run.pendingDelivery=nil; run.deliveryProgress=run.deliveryProgress or {}; run.deliveryProgress[index]=run.deliveryProgress[index] or {}; run.deliveryProgress[index][deliveredItem]=true
  local complete=true; for _,itemID in ipairs(self:ObjectiveItemIDs(run.steps[index])) do if not run.deliveryProgress[index][itemID] then complete=false end end
  if complete then self:FinishStep(run,index) else self:SendNextObjectiveDelivery(run,index) end
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
  -- Seed the teaching scenario through the same allowed Maker-to-satchel path
  -- before the quest marks this definition as a quest item.
  if not self:HasItem(letter,1) and self.db.items[letter].category~="quest" and self.db.items[letter].category~="reward" then self:GrantMakerItem(letter,1) end
  local quest=demo.quest
  if not quest or not self.db.quests[quest] then
    local questID,definition
    for questID,definition in pairs(self.db.quests) do if definition.title=="Return of the Sealed Letter" and definition.owner==self:PlayerName() then quest=questID; break end end
  end
  if not quest then quest=self:CreateQuest("Return of the Sealed Letter","Carry the letter, hand it to the courier NPC, then await approval.",{{type="dialogue",text="The courier's task begins."},{type="possess",itemID=letter,count=1,text="Carry the sealed letter."},{type="deliver",itemID=letter,count=1,mobName="npc:2079",text="Hand the sealed letter to Conservator Ilthalaine."},{type="manual",text="The author confirms the return."}},token,1) end
  local function migrateLegacyDemoDelivery(record)
    local step=record and record.steps and record.steps[3]
    if step and step.type=="deliver" and not step.npcID then
      step.mobName="npc:2079"; step.npcID=2079; step.text="Hand the sealed letter to Conservator Ilthalaine."
      record.version=(record.version or 1)+1; record.deliveryMode="npc"
    end
  end
  migrateLegacyDemoDelivery(self.db.quests[quest]); migrateLegacyDemoDelivery(self.db.questRuns[quest])
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
