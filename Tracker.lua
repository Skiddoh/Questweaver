-- Questweaver's custom quests cannot be inserted into Blizzard's server-backed
-- quest log. This compact in-game tracker mirrors active RP objectives instead.
function QW:GetQuestTrackerEntries()
  local entries={}
  local id,run
  for id,run in pairs(self.db.questRuns or {}) do
    if run.state=="active" or run.state=="awaiting approval" or run.state=="ready_to_turn_in" then
      local objective
      if run.state=="ready_to_turn_in" then objective="Objectives complete - return for your reward"
      elseif run.state=="awaiting approval" then objective="Waiting for quest approval"
      elseif run.steps then
        local current=self:GetCurrentObjectiveIndices(run); local active={}
        for _,index in ipairs(current) do
          local step=run.steps[index]; local text="[Step "..self:ObjectiveStepNumber(step,index).."] "..(step.text or "Current objective")
          if step.type=="kill" then local progress=math.min((run.killProgress and run.killProgress[index]) or 0,step.count or 0); text=text.." ("..progress.."/"..(step.count or 0)..")"
          elseif step.type=="collect" or step.type=="loot" then text=text.." - "..(step.count or 1).." item(s)"
          elseif step.type=="possess" or step.type=="deliver" then
            local progress={}; for _,item in ipairs(self:GetObjectiveItemProgress(run,step,index)) do
              local row=item.name.." "..item.have.."/"..item.required
              if step.type=="deliver" then row=row.." satchel | hand to the target NPC" end
              progress[self.Count(progress)+1]=row
            end
            text=text.." - "..table.concat(progress,"; ")
          elseif step.type=="visit" then text=text.." - visit the location"
          elseif step.type=="dialogue" then text=text.." - speak with the NPC" end
          active[self.Count(active)+1]=text
        end
        objective=#active>0 and table.concat(active,"; ") or "Quest objectives complete"
      else objective="Quest objectives complete" end
      entries[self.Count(entries)+1]={id=id,title=run.title or id,objective=objective,state=run.state}
    end
  end
  table.sort(entries,function(a,b) return a.title<b.title end)
  return entries
end

function QW:CreateQuestTracker()
  if self.questTracker then return end
  local f=CreateFrame("Frame","QuestweaverObjectiveTracker",UIParent)
  self.questTracker=f; f:SetWidth(270); f:SetHeight(72); f:SetFrameStrata("MEDIUM"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  local saved=self.db.ui and self.db.ui.questTracker
  local anchor=ObjectiveTrackerFrame or WatchFrame
  if saved and saved.x and saved.y then f:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",saved.x,saved.y)
  elseif anchor then f:SetPoint("TOPRIGHT",anchor,"BOTTOMRIGHT",0,-8)
  else f:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-30,-240) end
  f.back=f:CreateTexture(nil,"BACKGROUND"); f.back:SetAllPoints(f); f.back:SetTexture("Interface\\Buttons\\WHITE8X8"); f.back:SetVertexColor(.035,.025,.015,.82)
  f.header=CreateFrame("Button",nil,f)
  f.header:SetPoint("TOPLEFT",f,"TOPLEFT",8,-6); f.header:SetWidth(254); f.header:SetHeight(20)
  f.title=f.header:CreateFontString(nil,"OVERLAY","GameFontNormal")
  f.title:SetAllPoints(f.header); f.title:SetJustifyH("LEFT"); f.title:SetText("Questweaver")
  f.header:SetScript("OnClick",function()
    if f.moved then f.moved=nil; return end
    QW.db.ui=QW.db.ui or {}; QW.db.ui.questTrackerCollapsed=not QW.db.ui.questTrackerCollapsed
    QW:RefreshQuestTracker()
  end)
  f.header:RegisterForDrag("LeftButton")
  local function startMoving()
    if IsShiftKeyDown and IsShiftKeyDown() then f.moving=true; f:StartMoving() end
  end
  local function stopMoving()
    if not f.moving then return end
    f:StopMovingOrSizing()
    local left,top=f:GetLeft(),f:GetTop()
    if left and top then
      f:ClearAllPoints(); f:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
      QW.db.ui=QW.db.ui or {}; QW.db.ui.questTracker={x=left,y=top}
    end
    f.moving=nil; f.moved=true
  end
  f:SetScript("OnDragStart",startMoving); f:SetScript("OnDragStop",stopMoving)
  f.header:SetScript("OnDragStart",startMoving); f.header:SetScript("OnDragStop",stopMoving)
  f.rows={}
  f:SetScript("OnShow",function() QW:RefreshQuestTracker() end)
  self:RefreshQuestTracker()
end

function QW:RefreshQuestTracker()
  local f=self.questTracker; if not f then return end
  local entries=self:GetQuestTrackerEntries()
  f.title:SetText((self.db.ui and self.db.ui.questTrackerCollapsed and "+ " or "- ").."Questweaver ("..self.Count(entries)..")")
  for i=1,self.Count(f.rows) do f.rows[i]:Hide() end
  if self.db.ui and self.db.ui.questTrackerCollapsed then f:SetHeight(34); return end
  if self.Count(entries)==0 then
    if not f.empty then f.empty=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.empty:SetPoint("TOPLEFT",10,-32); f.empty:SetWidth(250); f.empty:SetJustifyH("LEFT") end
    f.empty:SetText("No active RP quests"); f.empty:Show(); f:SetHeight(56); return
  end
  if f.empty then f.empty:Hide() end
  local visible=math.min(self.Count(entries),8)
  local i
  for i=1,visible do
    local entry=entries[i]; local row=f.rows[i]
    if not row then
      row=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.rows[i]=row
      row:SetWidth(250); row:SetJustifyH("LEFT"); row:SetJustifyV("TOP")
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT",10,-30-((i-1)*35))
    row:SetText("|cffffd100"..entry.title.."|r\n"..entry.objective); row:Show()
  end
  f:SetHeight(34+(visible*35))
end
