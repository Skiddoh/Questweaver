local function splitUI(value)
  local out={}; for part in string.gmatch(value or "","[^|]+") do out[QW.Count(out)+1]=part end; return out
end
local function text(parent,label,x,y,w,h)
  local e=CreateFrame("EditBox",nil,parent,"InputBoxTemplate"); e:SetPoint("TOPLEFT",x,y); e:SetWidth(w); e:SetHeight(h or 20); e:SetAutoFocus(false)
  if label then local l=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); l:SetPoint("BOTTOMLEFT",e,"TOPLEFT",0,2); l:SetText(label); e.label=l end
  return e
end
local function button(parent,label,x,y,w,fn)
  local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate"); b:SetPoint("TOPLEFT",x,y); b:SetWidth(w); b:SetHeight(22); b:SetText(label); b:SetScript("OnClick",fn); return b
end
local function escapePattern(value)
  return string.gsub(value,"([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1")
end
local FALLBACK_ICONS={
  "Interface\\Icons\\INV_Misc_Coin_01","Interface\\Icons\\INV_Misc_Coin_02","Interface\\Icons\\INV_Misc_Coin_03","Interface\\Icons\\INV_Misc_Coin_04","Interface\\Icons\\INV_Misc_Coin_05","Interface\\Icons\\INV_Misc_Coin_06",
  "Interface\\Icons\\INV_Misc_Book_01","Interface\\Icons\\INV_Misc_Book_02","Interface\\Icons\\INV_Misc_Book_03","Interface\\Icons\\INV_Misc_Book_04","Interface\\Icons\\INV_Misc_Book_05","Interface\\Icons\\INV_Misc_Book_06","Interface\\Icons\\INV_Misc_Book_07","Interface\\Icons\\INV_Misc_Book_08","Interface\\Icons\\INV_Misc_Book_09","Interface\\Icons\\INV_Misc_Book_10","Interface\\Icons\\INV_Misc_Book_11","Interface\\Icons\\INV_Misc_Book_12",
  "Interface\\Icons\\INV_Letter_01","Interface\\Icons\\INV_Letter_02","Interface\\Icons\\INV_Letter_03","Interface\\Icons\\INV_Letter_04","Interface\\Icons\\INV_Letter_05","Interface\\Icons\\INV_Letter_06","Interface\\Icons\\INV_Letter_07","Interface\\Icons\\INV_Letter_08","Interface\\Icons\\INV_Letter_15",
  "Interface\\Icons\\INV_Misc_Note_01","Interface\\Icons\\INV_Misc_Note_02","Interface\\Icons\\INV_Misc_Note_03","Interface\\Icons\\INV_Misc_Note_05","Interface\\Icons\\INV_Misc_Key_01","Interface\\Icons\\INV_Misc_Key_02","Interface\\Icons\\INV_Misc_Key_03","Interface\\Icons\\INV_Misc_Bag_08","Interface\\Icons\\INV_Misc_Map_01","Interface\\Icons\\INV_Misc_Map_02","Interface\\Icons\\INV_Misc_Gem_Amethyst_01","Interface\\Icons\\INV_Misc_Gem_Pearl_01","Interface\\Icons\\INV_Misc_Food_15","Interface\\Icons\\INV_Misc_Organ_02","Interface\\Icons\\INV_Chest_Chain","Interface\\Icons\\INV_Weapon_ShortBlade_01"
}
function QW:GetIconLibrary()
  local icons,seen={},{}
  local function add(icon)
    if not QW:ValidateIcon(icon) or seen[tostring(icon)] then return end
    seen[tostring(icon)]=true; icons[QW.Count(icons)+1]=icon
  end
  local i; for i=1,QW.Count(FALLBACK_ICONS) do add(FALLBACK_ICONS[i]) end
  local function addMacroIcons(api)
    if not api then return end
    local ok,result=pcall(api)
    if ok and type(result)=="table" then for _,icon in pairs(result) do add(icon) end end
  end
  addMacroIcons(GetMacroIcons); addMacroIcons(GetMacroItemIcons)
  table.sort(icons,function(a,b) return tostring(a)<tostring(b) end)
  return icons
end
function QW:FilterItemLinkMessage(_,event,message,...)
  if type(message)~="string" then return false end
  local trailing=arg or {}; local trailingCount=trailing.n or self.Count(trailing)
  local replaced=string.gsub(message,"|Hquestweaver:item:([^|]+)|h.-|h",function(data)
    local item=self:ParseChatItemLink("questweaver:item:"..data)
    if not item then return "[RP item]" end
    local name=string.gsub(item.name,"|","||")
    return "|Hquestweaver:item:"..data.."|h|T"..tostring(item.icon)..":16:16|t "..name.."|h"
  end)
  -- Never send addon-only hyperlink escapes over player chat. Outgoing chat
  -- contains the plain [Item Name] marker; each addon client turns it into a
  -- local clickable preview only if it knows that RP item definition.
  for id,item in pairs(self.db.items) do
    local safeName=string.gsub(item.name,"|","||"); local label="["..safeName.."]"
    local pattern=escapePattern(label)
    local texture="|Hquestweaver:item:"..self:SerializeItem(item).."|h|T"..tostring(item.icon)..":16:16|t "..safeName.."|h"
    replaced=string.gsub(replaced,pattern,function() return texture end)
  end
  if replaced==message then return false end
  return false,replaced,unpack(trailing,1,trailingCount)
end
function QW:CreateItemPreviewWindow()
  local f=CreateFrame("Frame","QuestweaverItemPreviewFrame",UIParent,"UIPanelDialogTemplate"); self.itemPreview=f
  f:SetWidth(430); f:SetHeight(270); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); f:Hide()
  f.title=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); f.title:SetPoint("TOP",0,-12)
  f.icon=f:CreateTexture(nil,"ARTWORK"); f.icon:SetPoint("TOPLEFT",26,-58); f.icon:SetWidth(64); f.icon:SetHeight(64)
  f.description=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); f.description:SetPoint("TOPLEFT",108,-62); f.description:SetWidth(295); f.description:SetHeight(135); f.description:SetJustifyH("LEFT"); f.description:SetJustifyV("TOP")
  f.id=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.id:SetPoint("BOTTOMLEFT",24,42); f.id:SetWidth(380); f.id:SetJustifyH("LEFT")
  button(f,"Close",165,-235,100,function() f:Hide() end)
  local original=SetItemRef
  if original and not self.itemLinkHooked then
    self.originalSetItemRef=original
    SetItemRef=function(link,textValue,mouseButton,chatFrame)
      local item=QW:ParseChatItemLink(link)
      if item then QW:ShowItemPreview(item); return end
      return QW.originalSetItemRef(link,textValue,mouseButton,chatFrame)
    end
    self.itemLinkHooked=true
  end
  if ChatFrame_AddMessageEventFilter and not self.itemLinkFiltersRegistered then
    local events={"CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER","CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER","CHAT_MSG_GUILD","CHAT_MSG_OFFICER","CHAT_MSG_WHISPER","CHAT_MSG_WHISPER_INFORM","CHAT_MSG_CHANNEL"}
    local i; for i=1,self.Count(events) do pcall(ChatFrame_AddMessageEventFilter,events[i],function(...) return QW:FilterItemLinkMessage(...) end) end
    self.itemLinkFiltersRegistered=true
  end
end
function QW:ShowItemPreview(itemOrID)
  local item=type(itemOrID)=="table" and itemOrID or self.db.items[itemOrID]
  if type(item)~="table" then self:Print("This item definition is not available on your client."); return false end
  local f=self.itemPreview; if not f then return false end
  f.title:SetText(item.name); f.icon:SetTexture(item.icon); f.description:SetText(item.description); f.id:SetText(item.id); f:Show(); return true
end
function QW:InsertItemLinkIntoChat(itemID)
  local item=self.db.items[itemID]
  if not item then self:Print("Unknown RP item ID."); return false end
  local plainName="["..string.gsub(item.name,"|","||").."]"
  local activeChat=ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if ChatEdit_InsertText and (activeChat or not ChatEdit_GetActiveWindow) then
    local ok=pcall(ChatEdit_InsertText,plainName)
    if ok then return true end
  end
  return self:PrintItemLinkForChat(itemID)
end
function QW:PrintItemLinkForChat(itemID)
  local item=self.db.items[itemID]
  if not item then self:Print("Unknown RP item ID."); return false end
  DEFAULT_CHAT_FRAME:AddMessage("["..string.gsub(item.name,"|","||").."]")
  self:Print("Only the item name was printed. Right-click its Inventory icon while chat is open to insert it safely.")
  return true
end
function QW:CreateUI()
  local f=CreateFrame("Frame","QuestweaverMainFrame",UIParent,"UIPanelDialogTemplate"); self.ui=f; f:SetWidth(620); f:SetHeight(520); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); f:Hide(); f.title=f:CreateFontString(nil,"OVERLAY","GameFontHighlight"); f.title:SetPoint("TOP",0,-10); f.title:SetText("Questweaver v"..QW.RELEASE.." - cooperative RP inventory")
  local tabs={"RP Satchel","Maker","Quests","Create","Sets"}; f.pages={}
  for i,name in ipairs(tabs) do
    local p=CreateFrame("Frame",nil,f); p:SetPoint("TOPLEFT",12,-45); p:SetPoint("BOTTOMRIGHT",-12,12); p:Hide(); f.pages[i]=p
    local tabIndex=i
    if name=="Quests" then button(f,name,15+(i-1)*95,-25,90,function() QW:ShowQuestJournal() end) else button(f,name,15+(i-1)*95,-25,90,function() QW:ShowPage(tabIndex) end) end
  end
  self:BuildInventoryPage(f.pages[1]); self:BuildMakerPage(f.pages[2]); self:BuildQuestPage(f.pages[3]); self:BuildCreatePage(f.pages[4]); self:BuildSetPage(f.pages[5]); self:CreateNPCInteractionWindow(); self:CreateItemPreviewWindow(); self:CreateItemCreator(); self:CreateQuestCreator(); self:CreateNPCDialogueCreator(); self:CreateSetCreator(); self:CreateReferencePicker(); self:CreateIconPicker(); self:CreateTradeWindow(); self:CreateQuickAccessButton(); self:CreateQuestQuickAccessButton(); self:CreateInteractQuickAccessButton(); self:CreateTokenAccessButton(); self:CreateQuestTracker(); self:ShowPage(1)
end
function QW:CreateNPCInteractionWindow()
  local f=CreateFrame("Frame","QuestweaverNPCInteractionFrame",UIParent,"UIPanelDialogTemplate"); self.npcInteraction=f
  f:SetWidth(540); f:SetHeight(650); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); f:Hide()
  f.title=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); f.title:SetPoint("TOP",0,-10); f.title:SetText("Questweaver - NPC interaction")
  f.npcName=f:CreateFontString(nil,"OVERLAY","GameFontNormal"); f.npcName:SetPoint("TOPLEFT",20,-48); f.npcName:SetWidth(500); f.npcName:SetJustifyH("LEFT")
  f.headerRows={}; f.optionRows={}; f.selected=nil; f.collapsed={done=true,repeatQuests=true}
  f.detailTitle=f:CreateFontString(nil,"OVERLAY","GameFontHighlight"); f.detailTitle:SetPoint("TOPLEFT",22,-495); f.detailTitle:SetWidth(490); f.detailTitle:SetJustifyH("LEFT")
  f.detail=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); f.detail:SetPoint("TOPLEFT",22,-520); f.detail:SetWidth(490); f.detail:SetHeight(76); f.detail:SetJustifyH("LEFT"); f.detail:SetJustifyV("TOP"); f.detail:SetText("")
  f.status=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.status:SetPoint("BOTTOMLEFT",22,18); f.status:SetWidth(320); f.status:SetJustifyH("LEFT")
  f.action=button(f,"Choose an interaction",365,-608,145,function()
    local option=f.selected
    if not option then return end
    local ok,message=QW:PerformNPCInteraction(option,f.npcID)
    f.status:SetText(message or (ok and "Interaction complete." or "Interaction unavailable."))
    if message and ok then QW:Print(message) end
    QW:RefreshNPCInteraction()
    if QW.RefreshUI then QW:RefreshUI() end
  end)
  button(f,"Close",20,-608,90,function() f:Hide() end)
end
function QW:RefreshNPCInteraction()
  local f=self.npcInteraction; if not f or not f.npcID then return end
  local groups=self:GetNPCInteractionOptions(f.npcID)
  local active={}; local i
  for i=1,self.Count(groups.progress) do active[self.Count(active)+1]=groups.progress[i] end
  for i=1,self.Count(groups.ready) do active[self.Count(active)+1]=groups.ready[i] end
  local specs={{"NEW QUESTS","new",groups.new},{"ACTIVE QUESTS","active",active},{"COMPLETED QUESTS","done",groups.done},{"REPEAT QUESTS","repeatQuests",groups.repeatQuests},{"CUSTOM DIALOGUE","custom",groups.custom}}
  for i=1,self.Count(f.headerRows) do f.headerRows[i]:Hide() end
  for i=1,self.Count(f.optionRows) do f.optionRows[i]:Hide() end
  local headerIndex,optionIndex=0,0; local y=-70
  local function addHeader(label)
    headerIndex=headerIndex+1; local fs=f.headerRows[headerIndex]
    if not fs then fs=CreateFrame("Button",nil,f); f.headerRows[headerIndex]=fs; fs:SetWidth(490); fs:SetHeight(20); fs.label=fs:CreateFontString(nil,"OVERLAY","GameFontNormal"); fs.label:SetAllPoints(); fs.label:SetJustifyH("LEFT") end
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT",22,y); fs.label:SetText(label); fs:Show(); y=y-20
    fs:SetScript("OnClick",nil)
  end
  local function addOption(option)
    optionIndex=optionIndex+1; local b=f.optionRows[optionIndex]
    if not b then b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); f.optionRows[optionIndex]=b; b:SetWidth(490); b:SetHeight(22) end
    local captured=option
    b:ClearAllPoints(); b:SetPoint("TOPLEFT",22,y); b:SetText(captured.title or captured.id); b:SetScript("OnClick",function() f.selected=captured; QW:RefreshNPCInteraction() end); b:Show(); y=y-24
  end
  local si,entry
  for si=1,self.Count(specs) do
    local spec=specs[si]; local list=spec[3] or {}
    if self.Count(list)>0 then
      addHeader((f.collapsed[spec[2]] and "+ " or "- ")..spec[1].." ("..self.Count(list)..")")
      local header=f.headerRows[headerIndex]; local category=spec[2]
      header:SetScript("OnClick",function() f.collapsed[category]=not f.collapsed[category]; QW:RefreshNPCInteraction() end)
      if not f.collapsed[spec[2]] then
        local shown=math.min(self.Count(list),12)
        for i=1,shown do addOption(list[i]) end
        if self.Count(list)>shown then addHeader("Collapse another section to make room for more quests.") end
      end
    end
  end
  if headerIndex==0 then addHeader("NO QUESTWEAVER INTERACTIONS") end
  local found=false
  if f.selected then
    for _,list in pairs(groups) do for i=1,self.Count(list) do if list[i].id==f.selected.id and list[i].kind==f.selected.kind then f.selected=list[i]; found=true end end end
  end
  if not found then
    f.selected=nil
    for si=1,self.Count(specs) do local list=specs[si][3]; if list and self.Count(list)>0 then f.selected=list[1]; break end end
  end
  local selected=f.selected
  if selected then
    f.detailTitle:SetText(selected.title or "Interaction")
    local detail=selected.dialogue and selected.dialogue~="" and selected.dialogue or selected.text or ""
    if selected.kind=="dialogquest" and selected.text and selected.text~="" then detail=detail.."\n\nQuest: "..selected.text end
    f.detail:SetText(detail)
    local actionLabels={offer="Accept quest",quest="Accept quest",dialogquest="Accept quest",custom="Listen",npcdialogue="Listen",turnin="Receive reward",objective="Continue quest",delivery="Hand over items",active="Open quest journal",done="Completed",["repeat"]="Accept again"}
    f.action:SetText(actionLabels[selected.kind] or "Choose an interaction")
    if selected.kind=="done" then f.action:Disable() else f.action:Enable() end
  else
    f.detailTitle:SetText(""); f.detail:SetText("This NPC has no quests or custom dialogue in Questweaver."); f.action:SetText("No interaction available"); f.action:Disable()
  end
end
function QW:ShowNPCInteraction(npcID,npcName)
  local f=self.npcInteraction; if not f then return false end
  f.npcID=npcID; f.npcGUID=UnitGUID and UnitGUID("target"); f.npcName:SetText("Target: "..(npcName or "NPC").." (ID "..npcID..")"); f.status:SetText(""); f.selected=nil
  self:RefreshNPCInteraction(); f:Show(); return true
end
function QW:ShowPage(index) for i,p in ipairs(self.ui.pages) do if i==index then p:Show() else p:Hide() end end; self:RefreshUI() end
function QW:ToggleUI() if self.ui:IsShown() then self.ui:Hide() else self.ui:Show(); self:RefreshUI() end end
function QW:ShowRPInventory()
  if not self.ui then return end
  self.ui:Show(); self:ShowPage(1)
end
function QW:ShowMakerInventory() if not self.ui then return end; self.ui:Show(); self:ShowPage(2) end
function QW:Status(page,message) page.status:SetText(message or "") end
function QW:BuildMakerPage(p)
  p.heading=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.heading:SetPoint("TOPLEFT",8,-8); p.heading:SetText("MAKER INVENTORY - item definitions")
  p.buttons={}
  for i=1,8 do
    local b=button(p,"",8,-30-(i-1)*28,245,function(self) p.selectedID=self.itemID; p.deleteArmed=nil; QW:RefreshMakerInventory() end)
    b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetWidth(20); b.icon:SetHeight(20); b.icon:SetPoint("LEFT",5,0); p.buttons[i]=b
  end
  p.detailTitle=p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); p.detailTitle:SetPoint("TOPLEFT",275,-35); p.detailTitle:SetWidth(300); p.detailTitle:SetJustifyH("LEFT")
  p.detail=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.detail:SetPoint("TOPLEFT",275,-62); p.detail:SetWidth(300); p.detail:SetHeight(160); p.detail:SetJustifyH("LEFT"); p.detail:SetJustifyV("TOP")
  p.amount=text(p,"Quantity to add",275,-250,80); p.amount:SetText("1")
  p.grant=button(p,"Add to RP satchel",365,-250,145,function()
    if not p.selectedID then QW:Status(p,"Select a Maker Inventory item first."); return end
    local ok,message=QW:GrantMakerItem(p.selectedID,p.amount:GetText()); QW:Status(p,message); QW:RefreshInventoryGrid(QW.ui.pages[1])
  end)
  p.delete=button(p,"Delete definition",275,-290,145,function()
    if not p.selectedID then QW:Status(p,"Select a Maker Inventory item first."); return end
    if not p.deleteArmed or p.deleteArmed~=p.selectedID then p.deleteArmed=p.selectedID; p.delete:SetText("Confirm delete"); QW:Status(p,"Click again to delete this definition. Quest/set references, owned satchel stacks, and the default token are protected."); return end
    local id=p.selectedID; local ok,message=QW:DeleteMakerItem(id); p.deleteArmed=nil; p.delete:SetText("Delete definition"); if ok then p.selectedID=nil end; QW:Status(p,message); QW:RefreshMakerInventory()
  end)
  p.prev=button(p,"<",8,-263,38,function() p.page=math.max(1,(p.page or 1)-1); p.selectedID=nil; QW:RefreshMakerInventory() end)
  p.pageText=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.pageText:SetPoint("TOPLEFT",52,-268); p.pageText:SetWidth(55); p.pageText:SetJustifyH("CENTER")
  p.next=button(p,">",111,-263,38,function() p.page=(p.page or 1)+1; p.selectedID=nil; QW:RefreshMakerInventory() end)
  p.status=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.status:SetPoint("TOPLEFT",8,-350); p.status:SetWidth(570); p.status:SetJustifyH("LEFT")
end
function QW:RefreshMakerInventory()
  if not self.ui or not self.ui.pages[2] then return end
  local p=self.ui.pages[2]; local items={}; for id,item in pairs(self.db.items) do items[self.Count(items)+1]=item end
  table.sort(items,function(a,b) return a.name<b.name end)
  local pageCount=math.max(1,math.ceil(self.Count(items)/self.Count(p.buttons))); p.page=math.min(math.max(1,p.page or 1),pageCount); p.pageText:SetText(p.page.." / "..pageCount); if p.page>1 then p.prev:Enable() else p.prev:Disable() end; if p.page<pageCount then p.next:Enable() else p.next:Disable() end
  local offset=(p.page-1)*self.Count(p.buttons)
  local selected
  for i=1,self.Count(items) do if items[i].id==p.selectedID then selected=items[i]; break end end
  if not selected and items[offset+1] then selected=items[offset+1]; p.selectedID=selected.id end
  for i=1,self.Count(p.buttons) do
    local b=p.buttons[i]; local item=items[offset+i]
    if item then local category=item.category or "misc"; if category=="quest" then category="quest item" end; b.itemID=item.id; b.icon:SetTexture(item.icon); b:SetText("  "..item.name.."  ["..category.."]"); b:Show()
    else b.itemID=nil; b.icon:SetTexture(nil); b:Hide() end
  end
  if selected then
    local category=selected.category or "misc"; local label=category=="quest" and "quest item" or category
    local detail="Category: "..label.."\nMax stack: "..(selected.maxStack or 1).."\nDefinition ID: "..selected.id.."\n\n"..(selected.description or "")
    if (category=="quest" or category=="reward") and not QW.DEV_MAKER_SATCHEL_GRANTS then detail=detail.."\n\nQuest items and rewards enter the Satchel only through quests." elseif (category=="quest" or category=="reward") then detail=detail.."\n\nDevelopment mode: this item may be added directly to the Satchel." end
    p.detailTitle:SetText(selected.name); p.detail:SetText(detail)
    local allowed=QW.DEV_MAKER_SATCHEL_GRANTS or (category~="quest" and category~="reward" and not selected.default)
    if allowed then p.grant:Enable() else p.grant:Disable() end
    local canDelete,reason=QW:CanDeleteMakerItem(selected.id); if canDelete then p.delete:Enable() else p.delete:Disable(); p.detail:SetText(detail.."\n\nDelete unavailable: "..reason) end
    p.delete:SetText(p.deleteArmed==selected.id and "Confirm delete" or "Delete definition")
  else p.selectedID=nil; p.detailTitle:SetText("No maker items"); p.detail:SetText("Create an item definition from the Create tab. Definitions do not automatically enter your satchel."); p.delete:Disable(); p.grant:Disable() end
end
function QW:BuildInventoryPage(p)
  p.list=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.list:SetPoint("TOPLEFT",8,-8); p.list:SetJustifyH("LEFT"); p.list:SetWidth(580); p.list:SetText("RP SATCHEL - click an item, then open the trade window to offer it")
  p.filterCategories={"all"}; for _,category in ipairs(QW.ITEM_CATEGORIES) do p.filterCategories[#p.filterCategories+1]=category end; p.filterIndex=1; p.filterCategory="all"
  p.filterButton=button(p,"Filter: All",410,-27,170,function()
    p.filterIndex=p.filterIndex%QW.Count(p.filterCategories)+1; p.filterCategory=p.filterCategories[p.filterIndex]
    local label=p.filterCategory=="all" and "All" or (p.filterCategory=="quest" and "Quest item" or p.filterCategory)
    p.filterButton:SetText("Filter: "..label); QW:RefreshInventoryGrid(p)
  end)
  p.bag=CreateFrame("Frame",nil,p); p.bag:SetPoint("TOPLEFT",8,-56); p.bag:SetWidth(388); p.bag:SetHeight(212)
  p.bag.bg=p.bag:CreateTexture(nil,"BACKGROUND"); p.bag.bg:SetAllPoints(p.bag); p.bag.bg:SetTexture("Interface\\Buttons\\WHITE8X8"); p.bag.bg:SetVertexColor(.10,.055,.025,.96)
  local function bagEdge()
    local edge=p.bag:CreateTexture(nil,"BORDER"); edge:SetTexture("Interface\\Buttons\\WHITE8X8"); edge:SetVertexColor(.55,.34,.14,1); return edge
  end
  p.bag.top=bagEdge(); p.bag.top:SetPoint("TOPLEFT",p.bag,"TOPLEFT",0,0); p.bag.top:SetPoint("TOPRIGHT",p.bag,"TOPRIGHT",0,0); p.bag.top:SetHeight(2)
  p.bag.bottom=bagEdge(); p.bag.bottom:SetPoint("BOTTOMLEFT",p.bag,"BOTTOMLEFT",0,0); p.bag.bottom:SetPoint("BOTTOMRIGHT",p.bag,"BOTTOMRIGHT",0,0); p.bag.bottom:SetHeight(2)
  p.bag.left=bagEdge(); p.bag.left:SetPoint("TOPLEFT",p.bag,"TOPLEFT",0,0); p.bag.left:SetPoint("BOTTOMLEFT",p.bag,"BOTTOMLEFT",0,0); p.bag.left:SetWidth(2)
  p.bag.right=bagEdge(); p.bag.right:SetPoint("TOPRIGHT",p.bag,"TOPRIGHT",0,0); p.bag.right:SetPoint("BOTTOMRIGHT",p.bag,"BOTTOMRIGHT",0,0); p.bag.right:SetWidth(2)
  p.bag.title=p.bag:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.bag.title:SetPoint("TOPLEFT",12,-8); p.bag.title:SetText("RP ITEMS")
  p.slots={}
  local i
  for i=1,32 do
    local slot=CreateFrame("Button",nil,p.bag); slot:SetWidth(42); slot:SetHeight(42)
    if slot.RegisterForClicks then slot:RegisterForClicks("LeftButtonUp","RightButtonUp") end
    local column=(i-1)%8; local row=math.floor((i-1)/8); slot:SetPoint("TOPLEFT",12+column*46,-28-row*45)
    slot.border=slot:CreateTexture(nil,"BACKGROUND"); slot.border:SetAllPoints(slot); slot.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    slot.selection={}
    local function selectionEdge(point1,relativePoint1,point2,relativePoint2,width,height)
      local edge=slot:CreateTexture(nil,"OVERLAY"); edge:SetTexture("Interface\\Buttons\\WHITE8X8"); edge:SetVertexColor(1,.72,.15,1)
      if point2 then edge:SetPoint(point1,slot,relativePoint1); edge:SetPoint(point2,slot,relativePoint2) else edge:SetPoint(point1,slot,relativePoint1) end
      if width then edge:SetWidth(width) end; if height then edge:SetHeight(height) end
      edge:Hide(); return edge
    end
    slot.selection.top=selectionEdge("TOPLEFT","TOPLEFT","TOPRIGHT","TOPRIGHT",nil,2)
    slot.selection.bottom=selectionEdge("BOTTOMLEFT","BOTTOMLEFT","BOTTOMRIGHT","BOTTOMRIGHT",nil,2)
    slot.selection.left=selectionEdge("TOPLEFT","TOPLEFT","BOTTOMLEFT","BOTTOMLEFT",2,nil)
    slot.selection.right=selectionEdge("TOPRIGHT","TOPRIGHT","BOTTOMRIGHT","BOTTOMRIGHT",2,nil)
    slot.icon=slot:CreateTexture(nil,"ARTWORK"); slot.icon:SetPoint("TOPLEFT",slot,"TOPLEFT",4,-4); slot.icon:SetPoint("BOTTOMRIGHT",slot,"BOTTOMRIGHT",-4,4)
    slot.count=slot:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall"); slot.count:SetPoint("BOTTOMRIGHT",slot,"BOTTOMRIGHT",-3,3)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    slot:SetScript("OnEnter",function(self)
      if not self.item then return end
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.item.name)
      GameTooltip:AddLine(self.item.description,1,1,1,true); GameTooltip:AddLine("RP quantity: "..self.quantity,.8,.8,.8)
      GameTooltip:AddLine(self.item.id,.5,.5,.5); GameTooltip:AddLine("Right-click to insert an item link in chat",.7,.7,.7); GameTooltip:Show()
    end)
    slot:SetScript("OnLeave",function() GameTooltip:Hide() end)
    slot:SetScript("OnClick",function(self,mouseButton)
      mouseButton=mouseButton or arg1
      if not self.item then return end
      if mouseButton=="RightButton" then QW:InsertItemLinkIntoChat(self.item.id)
      else p.selectedItem=self.item; p.removeArmed=nil; p.removeButton:SetText("Remove selected"); p.removeQuantity:SetText("1"); QW:RefreshInventorySelection(p); QW:Status(p,"Selected "..self.item.name..". Open RP trade or remove a quantity.") end
    end)
    p.slots[QW.Count(p.slots)+1]=slot
  end
  button(p,"Open RP trade",8,-280,145,function() QW:ShowTradeWindow(); if p.selectedItem then QW.tradeWindow.selectedItem=p.selectedItem; QW:RefreshTradeWindow() end end)
  p.removeButton=button(p,"Remove selected",160,-280,130,function()
    if not p.selectedItem then QW:Status(p,"Select an RP inventory item first."); return end
    local amount=tonumber(p.removeQuantity:GetText())
    if not p.removeArmed then
      p.removeArmed={id=p.selectedItem.id,amount=p.removeQuantity:GetText()}; p.removeButton:SetText("Confirm removal")
      QW:Status(p,"Click Confirm removal again to delete "..tostring(p.removeQuantity:GetText()).." from your RP inventory."); return
    end
    if p.removeArmed.id~=p.selectedItem.id or p.removeArmed.amount~=p.removeQuantity:GetText() then
      p.removeArmed=nil; p.removeButton:SetText("Remove selected"); QW:Status(p,"Selection or quantity changed. Click Remove selected again to confirm."); return
    end
    local ok,message=QW:RemoveRPItem(p.selectedItem.id,amount); p.removeArmed=nil; p.removeButton:SetText("Remove selected")
    if ok and (QW.db.inventory[p.selectedItem.id] or 0)==0 then p.selectedItem=nil end
    QW:Status(p,message); QW:RefreshInventoryGrid(p); QW:RefreshQuickAccessButton()
  end)
  p.removeQuantity=text(p,"Quantity",302,-279,48); p.removeQuantity:SetText("1")
  p.removeQuantity:SetScript("OnTextChanged",function() p.removeArmed=nil; p.removeButton:SetText("Remove selected") end)
  p.status=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.status:SetPoint("TOPLEFT",8,-308); p.status:SetWidth(570); p.status:SetJustifyH("LEFT")
  p.tradeList=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.tradeList:SetPoint("TOPLEFT",8,-336); p.tradeList:SetWidth(570); p.tradeList:SetJustifyH("LEFT")
end
function QW:RefreshInventoryGrid(p)
  local entries=self:GetRPInventoryItems(p.filterCategory)
  local i
  for i=1,self.Count(p.slots) do
    local slot=p.slots[i]; local entry=entries[i]
    if entry then
      slot.item=entry.item; slot.quantity=entry.quantity; slot.icon:SetTexture(entry.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"); slot.count:SetText(entry.quantity>1 and entry.quantity or ""); slot:Show()
    else
      slot.item=nil; slot.quantity=nil; slot.icon:SetTexture(nil); slot.count:SetText(""); slot:Show()
    end
  end
  if p.selectedItem and not self.db.inventory[p.selectedItem.id] then p.selectedItem=nil end
  if p.selectedItem and p.filterCategory~="all" and self:NormalizeItemCategory(p.selectedItem.category)~=p.filterCategory then p.selectedItem=nil end
  self:RefreshInventorySelection(p)
  local label=p.filterCategory=="all" and "All types" or (p.filterCategory=="quest" and "Quest items" or (p.filterCategory.." items"))
  if self.Count(entries)>self.Count(p.slots) then p.list:SetText("RP SATCHEL - "..label..", first "..self.Count(p.slots).." item types shown") else p.list:SetText("RP SATCHEL - "..label.." - click an item, then open the trade window to offer it") end
end
function QW:RefreshInventorySelection(p)
  if not p or not p.slots then return end
  local i,edge
  for i=1,self.Count(p.slots) do
    local slot=p.slots[i]; local selected=p.selectedItem and slot.item and slot.item.id==p.selectedItem.id
    for _,edge in pairs(slot.selection or {}) do if selected then edge:Show() else edge:Hide() end end
  end
end
function QW:CreateQuickAccessButton()
  local f=CreateFrame("Button","QuestweaverQuickAccessButton",UIParent); self.quickAccess=f
  f:SetWidth(42); f:SetHeight(42); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  local saved=self.db.ui and self.db.ui.quickAccess
  if saved and saved.point and saved.relativePoint and saved.x and saved.y then f:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y) else f:SetPoint("RIGHT",UIParent,"RIGHT",-22,0) end
  f.border=f:CreateTexture(nil,"BACKGROUND"); f.border:SetAllPoints(f); f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  f.icon=f:CreateTexture(nil,"ARTWORK"); f.icon:SetPoint("TOPLEFT",f,"TOPLEFT",4,-4); f.icon:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,4); f.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_05")
  f.count=f:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall"); f.count:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-3,3)
  f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  f:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:SetText("Questweaver RP Satchel"); GameTooltip:AddLine("Left-click: open RP inventory",1,1,1); GameTooltip:AddLine("Shift + left-drag: move this button",.7,.7,.7); GameTooltip:Show()
  end)
  f:SetScript("OnLeave",function() GameTooltip:Hide() end)
  f:SetScript("OnClick",function(_,mouseButton)
    mouseButton=mouseButton or arg1
    if f.moved then f.moved=nil; return end
    if mouseButton=="LeftButton" and not IsShiftKeyDown() then QW:ShowRPInventory() end
  end)
  f:SetScript("OnDragStart",function(self) if IsShiftKeyDown() then self.moving=true; self:StartMoving() end end)
  f:SetScript("OnDragStop",function(self)
    if not self.moving then return end
    self:StopMovingOrSizing()
    local point,_,relativePoint,x,y=self:GetPoint()
    QW.db.ui=QW.db.ui or {}; QW.db.ui.quickAccess={point=point,relativePoint=relativePoint,x=x,y=y}
    self.moving=nil; self.moved=true
  end)
  self:RefreshQuickAccessButton()
end
function QW:RefreshQuickAccessButton()
  local f=self.quickAccess; if not f or not self.db then return end
  local types=0; for id,quantity in pairs(self.db.inventory) do if quantity>0 and self.db.items[id] then types=types+1 end end
  f.count:SetText(types>0 and types or "")
  self:RefreshTokenAccessButton()
end
function QW:CreateTokenAccessButton()
  local f=CreateFrame("Button","QuestweaverTokenAccessButton",UIParent); self.tokenAccess=f
  f:SetWidth(42); f:SetHeight(42); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  local saved=self.db.ui and self.db.ui.tokenAccess
  if saved and saved.point and saved.relativePoint and saved.x and saved.y then f:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y)
  else f:SetPoint("RIGHT",UIParent,"RIGHT",-22,-156) end
  f.border=f:CreateTexture(nil,"BACKGROUND"); f.border:SetAllPoints(f); f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  f.icon=f:CreateTexture(nil,"ARTWORK"); f.icon:SetPoint("TOPLEFT",f,"TOPLEFT",4,-4); f.icon:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,4); f.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_09")
  f.count=f:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall"); f.count:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-2,2)
  f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  f:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:SetText("Questweaver RP Tokens"); GameTooltip:AddLine("In your RP inventory: "..QW:GetRPTokenCount(),1,1,1); GameTooltip:AddLine("Left-click: open RP inventory",.8,.8,.8); GameTooltip:AddLine("Shift + left-drag: move this counter",.7,.7,.7); GameTooltip:Show()
  end)
  f:SetScript("OnLeave",function() GameTooltip:Hide() end)
  f:SetScript("OnClick",function(_,mouseButton)
    mouseButton=mouseButton or arg1
    if f.moved then f.moved=nil; return end
    if mouseButton=="LeftButton" and not IsShiftKeyDown() then QW:ShowRPInventory() end
  end)
  f:SetScript("OnDragStart",function(self) if IsShiftKeyDown() then self.moving=true; self:StartMoving() end end)
  f:SetScript("OnDragStop",function(self)
    if not self.moving then return end
    self:StopMovingOrSizing()
    local point,_,relativePoint,x,y=self:GetPoint()
    QW.db.ui=QW.db.ui or {}; QW.db.ui.tokenAccess={point=point,relativePoint=relativePoint,x=x,y=y}
    self.moving=nil; self.moved=true
  end)
  self:RefreshTokenAccessButton()
end
function QW:RefreshTokenAccessButton()
  local f=self.tokenAccess; if not f or not self.db then return end
  local count=self:GetRPTokenCount()
  f.count:SetText(count>0 and (count>999 and "999+" or count) or "0")
end
function QW:CreateQuestQuickAccessButton()
  local f=CreateFrame("Button","QuestweaverQuestAccessButton",UIParent); self.questAccess=f
  f:SetWidth(42); f:SetHeight(42); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  local saved=self.db.ui and self.db.ui.questAccess
  if saved and saved.point and saved.relativePoint and saved.x and saved.y then f:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y) else f:SetPoint("RIGHT",UIParent,"RIGHT",-22,-52) end
  f.border=f:CreateTexture(nil,"BACKGROUND"); f.border:SetAllPoints(f); f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  f.icon=f:CreateTexture(nil,"ARTWORK"); f.icon:SetPoint("TOPLEFT",f,"TOPLEFT",4,-4); f.icon:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,4); f.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  f.count=f:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall"); f.count:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-3,3)
  f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  f:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:SetText("Questweaver Active Quests"); GameTooltip:AddLine("Left-click: open accepted RP quests",1,1,1); GameTooltip:AddLine("Shift + left-drag: move this button",.7,.7,.7); GameTooltip:Show()
  end)
  f:SetScript("OnLeave",function() GameTooltip:Hide() end)
  f:SetScript("OnClick",function(_,mouseButton)
    mouseButton=mouseButton or arg1
    if f.moved then f.moved=nil; return end
    if mouseButton=="LeftButton" and not IsShiftKeyDown() then QW:ShowActiveQuests() end
  end)
  f:SetScript("OnDragStart",function(self) if IsShiftKeyDown() then self.moving=true; self:StartMoving() end end)
  f:SetScript("OnDragStop",function(self)
    if not self.moving then return end
    self:StopMovingOrSizing()
    local point,_,relativePoint,x,y=self:GetPoint()
    QW.db.ui=QW.db.ui or {}; QW.db.ui.questAccess={point=point,relativePoint=relativePoint,x=x,y=y}
    self.moving=nil; self.moved=true
  end)
  self:RefreshQuestQuickAccessButton()
end
function QW:CreateInteractQuickAccessButton()
  local f=CreateFrame("Button","QuestweaverInteractAccessButton",UIParent); self.interactAccess=f
  f:SetWidth(42); f:SetHeight(42); f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  local saved=self.db.ui and self.db.ui.interactAccess
  if saved and saved.point and saved.relativePoint and saved.x and saved.y then f:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y) else f:SetPoint("RIGHT",UIParent,"RIGHT",-22,-104) end
  f.border=f:CreateTexture(nil,"BORDER"); f.border:SetAllPoints(f); f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  f.icon=f:CreateTexture(nil,"ARTWORK"); f.icon:SetPoint("TOPLEFT",f,"TOPLEFT",4,-4); f.icon:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,4); f.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
  f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  f:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:SetText("Questweaver NPC interaction"); GameTooltip:AddLine("Target an NPC to browse its quests and custom dialogue.",1,1,1,true); GameTooltip:AddLine("Equivalent to /qw interact",.7,.7,.7); GameTooltip:AddLine("Shift + left-drag: move this button",.7,.7,.7); GameTooltip:Show()
  end)
  f:SetScript("OnLeave",function() GameTooltip:Hide() end)
  f:SetScript("OnClick",function(_,mouseButton)
    mouseButton=mouseButton or arg1
    if f.moved then f.moved=nil; return end
    if mouseButton=="LeftButton" and not IsShiftKeyDown() then
    local ok,message=QW:InteractWithTarget(); if not ok then QW:Print(message or "Could not open NPC interactions.") end; QW:RefreshUI()
    end
  end)
  f:SetScript("OnDragStart",function(self) if IsShiftKeyDown() then self.moving=true; self:StartMoving() end end)
  f:SetScript("OnDragStop",function(self)
    if not self.moving then return end
    self:StopMovingOrSizing()
    local point,_,relativePoint,x,y=self:GetPoint()
    QW.db.ui=QW.db.ui or {}; QW.db.ui.interactAccess={point=point,relativePoint=relativePoint,x=x,y=y}
    self.moving=nil; self.moved=true
  end)
end
function QW:RefreshQuestQuickAccessButton()
  local f=self.questAccess; if not f or not self.db then return end
  local active=0; for _,run in pairs(self.db.questRuns) do if run.state=="active" or run.state=="awaiting approval" or run.state=="ready_to_turn_in" then active=active+1 end end
  f.count:SetText(active>0 and active or "")
end
function QW:RefreshInteractQuickAccessButton()
  local f=self.interactAccess; if not f then return end
  -- Kept as a dedicated refresh point so future NPC-offer indicators can be added
  -- without changing the quick-access button's interaction behavior.
end
function QW:BuildQuestPage(p)
  p.heading=p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); p.heading:SetPoint("TOPLEFT",8,-8); p.heading:SetText("Quest Journal")
  p.questSections={}
  local categories={{key="yours",label="YOUR QUESTS"},{key="completed",label="COMPLETED"},{key="open",label="OPEN QUESTS"}}
  for i=1,3 do
    local category=categories[i]
    local header=button(p,"",8,0,245,function(self)
      p.collapsed=p.collapsed or {}; local expand=p.collapsed[category.key]; for _,other in ipairs({"yours","completed","open"}) do p.collapsed[other]=other~=category.key end; p.collapsed[category.key]=not expand; QW:RefreshQuestJournal()
    end)
    p.questSections[category.key]={category=category,header=header,entries={}}
  end
  p.questButtons={}
  local i
  for i=1,8 do
    local entry=button(p,"",8,0,245,function(self) p.selectedKey=self.questKey; p.deleteArmed=nil; QW:RefreshQuestJournal() end)
    entry:SetWidth(245); entry.questKey=nil; entry:Hide(); p.questButtons[QW.Count(p.questButtons)+1]=entry
  end
  p.empty=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.empty:SetPoint("TOPLEFT",8,-35); p.empty:SetWidth(245); p.empty:SetJustifyH("LEFT")
  p.detailTitle=p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); p.detailTitle:SetPoint("TOPLEFT",275,-32); p.detailTitle:SetWidth(300); p.detailTitle:SetJustifyH("LEFT")
  p.detail=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.detail:SetPoint("TOPLEFT",275,-62); p.detail:SetWidth(300); p.detail:SetJustifyH("LEFT")
  p.primary=button(p,"Select a quest",275,-285,145,function() end)
  p.resend=button(p,"Resend delivery",430,-285,125,function() end); p.resend:Hide()
  p.deleteQuest=button(p,"Delete quest",430,-344,125,function()
    local id=p.selectedQuestID; if not id then return end
    if p.deleteArmed~=id then p.deleteArmed=id; p.deleteQuest:SetText("Confirm delete"); QW:Status(p,"Click again to delete. Active runs and Set references must be removed first."); return end
    local ok,message=QW:DeleteQuest(id); p.deleteArmed=nil; QW:Status(p,message); QW:RefreshQuestJournal()
  end); p.deleteQuest:ClearAllPoints(); p.deleteQuest:SetPoint("TOPLEFT",430,-334); p.deleteQuest:Hide()
  p.clearAccepted=button(p,"Remove accepted quests",8,-310,180,function()
    if p.clearArmed then
      local ok,message=QW:ClearAcceptedQuests(); p.clearArmed=false; QW:Status(p,message); QW:RefreshQuestJournal()
    else
      local count=QW.Count(QW.db.questRuns); p.clearArmed=true; p.clearAccepted:SetText("Click again: confirm"); QW:Status(p,"Click Remove accepted quests again to remove "..count.." accepted quest record"..(count==1 and "." or "s."))
    end
  end)
  p.shareTarget=text(p,"Share with (character name)",275,-310,280); p.shareTarget:Hide(); p.shareTarget.label:Hide()
  p.approval=text(p,"Approve: quest ID | step | player",8,-355,410); button(p,"Approve",430,-358,80,function() local a=splitUI(p.approval:GetText()); local ok,msg=QW:ApproveQuest(a[1],a[2],a[3]); QW:Status(p,msg or (ok and "Approved.")) end)
  p.inbox=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.inbox:SetPoint("TOPLEFT",8,-395); p.inbox:SetWidth(560); p.inbox:SetJustifyH("LEFT")
  p.status=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.status:SetPoint("TOPLEFT",8,-445); p.status:SetWidth(570); p.status:SetJustifyH("LEFT")
end
function QW:ShowQuestJournal()
  if not self.ui then return end
  self.questJournalMode="all"
  self.ui:Show(); self:ShowPage(3)
end
function QW:ShowSets()
  if not self.ui then return end
  self.ui:Show(); self:ShowPage(5)
end
function QW:ShowActiveQuests()
  if not self.ui then return end
  self.questJournalMode="active"
  self.ui:Show(); self:ShowPage(3)
end
function QW:OpenQuestForSharing(id)
  local q=self.db.quests[id]
  if not q or not self.questCreator then return false end
  local f=self.questCreator; local stepLines={}; local placeLines={}; local extra={}; local used={}
  for _,reward in ipairs(self:GetQuestRewards(q)) do used[reward.id]=true end
  for _,step in ipairs(q.steps or {}) do
    local itemIDs=self:ObjectiveItemIDs(step)
    stepLines[self.Count(stepLines)+1]=table.concat({self:Escape(step.type or ""),self:Escape(itemIDs[1] or ""),self:Escape(step.count or ""),self:Escape(step.placeID or ""),self:Escape(step.mobName or ""),self:Escape(step.text or ""),self:Escape(step.stepNumber or self:Count(stepLines)+1),self:Escape(table.concat(itemIDs,","))},"~")
    for _,itemID in ipairs(itemIDs) do used[itemID]=true end
  end
  for _,place in ipairs(q.places or {}) do placeLines[self.Count(placeLines)+1]=table.concat({self:Escape(place.id),self:Escape(place.zone),self:Escape(place.x or ""),self:Escape(place.y or ""),self:Escape(place.radius or ""),self:Escape(place.description or "")},"~") end
  for itemID in pairs(q.itemDefinitions or {}) do if not used[itemID] then extra[self.Count(extra)+1]=itemID end end
  table.sort(extra)
  f.qtitle:SetText(q.title or ""); f.qdesc:SetText(q.description or ""); f.rewardItems=self:Copy(self:GetQuestRewards(q)); for _,reward in ipairs(f.rewardItems) do reward.item=nil end; f.selectedReward=nil; f.rewardQuantity:SetText("1"); f:RefreshQuestRewardItems(); f.giverPlaceIDValue=q.giverPlaceID or ""; f.objectiveSteps=self:Copy(q.steps or {}); f.selectedObjective=nil; f:Show(); f.steps:SetText(table.concat(stepLines,";")); f.places:SetText(table.concat(placeLines,";")); f.questItems:SetText(table.concat(extra,",")); self:SyncObjectiveEditor()
  f.suggestedLevel:SetText(q.suggestedLevel and tostring(q.suggestedLevel) or "")
  f.suggestedPlayers:SetText(q.suggestedPlayers and tostring(q.suggestedPlayers) or "")
  f.followUp:SetText(q.followUpQuestID or ""); f.predecessor:SetText(q.predecessorQuestID or ""); f.giverTarget:SetText(q.giverNPCID and ("npc:"..q.giverNPCID) or ""); f.giverDialogue:SetText(q.giverDialogue or ""); f.turnInTarget:SetText(q.turnInNPCID and ("npc:"..q.turnInNPCID) or ""); f.qid:SetText(q.id); f.qtarget:SetText(""); f.editingID=q.id; f.createButton:SetText("Save changes")
  f.repeatable=q.repeatable==true; f.repeatableButton:SetText("Repeatable: "..(f.repeatable and "Yes" or "No"))
  f.generalSection:Show(); f.objectiveSection:Hide(); f.generalTab:SetText("[ General ]"); f.objectiveTab:SetText("Objectives")
  f:Show(); f:Raise(); f.qtitle:SetFocus()
  return true
end
function QW:RefreshQuestJournal()
  self:RefreshQuestQuickAccessButton()
  local p=self.ui.pages[3]; local entries={}; local categories={yours={},completed={},open={}}; local id,run
  local activeOnly=self.questJournalMode=="active"
  for id,run in pairs(self.db.questRuns) do
    local entry={key="run:"..id,kind="run",id=id,data=run}
    if run.state=="complete" then categories.completed[self.Count(categories.completed)+1]=entry
    elseif not activeOnly or run.state=="active" or run.state=="awaiting approval" or run.state=="ready_to_turn_in" then categories.open[self.Count(categories.open)+1]=entry end
  end
  local quest
  for id,quest in pairs(self.db.questOffers) do categories.open[self.Count(categories.open)+1]={key="offer:"..id,kind="offer",id=id,data=quest} end
  for id,quest in pairs(self.db.quests) do categories.yours[self.Count(categories.yours)+1]={key="quest:"..id,kind="quest",id=id,data=quest} end
  local categoryOrder={"open","yours","completed"}; local renderOrder={"yours","completed","open"}
  local all={}
  for _,categoryKey in ipairs(categoryOrder) do
    table.sort(categories[categoryKey],function(a,b) return (a.data.title or "")<(b.data.title or "") end)
    for _,entry in ipairs(categories[categoryKey]) do all[self.Count(all)+1]=entry end
  end
  entries=all
  p.collapsed=p.collapsed or {yours=true,completed=true,open=false}
  if not p.collapsedInitialized and not activeOnly then
    if self.Count(categories.open)==0 and self.Count(categories.yours)>0 then p.collapsed.yours=false; p.collapsed.open=true
    elseif self.Count(categories.open)==0 and self.Count(categories.yours)==0 and self.Count(categories.completed)>0 then p.collapsed.completed=false; p.collapsed.open=true end
    p.collapsedInitialized=true
  end
  if activeOnly then p.collapsed.yours=true; p.collapsed.completed=true; p.collapsed.open=false end
  local selected
  if p.selectedKey then for i=1,self.Count(entries) do if entries[i].key==p.selectedKey then selected=entries[i]; break end end end
  if not selected and entries[1] then selected=entries[1]; p.selectedKey=selected.key end
  p.selectedRunID=selected and selected.kind=="run" and selected.id or nil
  local row=0; local buttonIndex=0
  for _,entry in ipairs(p.questButtons) do entry.questKey=nil; entry:Hide() end
  for _,categoryKey in ipairs(renderOrder) do
    local section=p.questSections[categoryKey]; local group=categories[categoryKey]
    section.header:ClearAllPoints(); section.header:SetPoint("TOPLEFT",8,-32-row*25); section.header:SetText((p.collapsed[categoryKey] and "+ " or "- ")..section.category.label.." ("..self.Count(group)..")"); section.header:Show(); row=row+1
    if not p.collapsed[categoryKey] then
      for _,data in ipairs(group) do
        buttonIndex=buttonIndex+1; local entry=p.questButtons[buttonIndex]; if not entry then break end
        entry:ClearAllPoints(); entry:SetPoint("TOPLEFT",19,-32-row*25); entry:SetWidth(234); entry.questKey=data.key
        if data.kind=="run" then entry:SetText("["..string.upper(data.data.state).."] "..string.sub(data.data.title,1,25))
        elseif data.kind=="offer" then entry:SetText("[OFFER] "..string.sub(data.data.title,1,29))
        else entry:SetText(string.sub(data.data.title,1,34)) end
        entry:Show(); row=row+1
      end
    end
  end
  p.heading:SetText(activeOnly and "Active Quests - accepted quests you are currently following" or "Quest Journal - expand a section and select a quest")
  p.empty:SetText(""); p.empty:Hide()
  if not p.clearArmed then p.clearAccepted:SetText("Remove accepted quests") end
  p.primary:Enable(); p.resend:Hide(); p.deleteQuest:Hide(); p.selectedQuestID=nil; p.shareTarget:Hide(); p.shareTarget.label:Hide()
  if not selected then
    p.detailTitle:SetText("Select a quest"); p.detail:SetText("Expand Your Quests to edit or share quests you authored. Open Quests contains accepted and offered quests; Completed keeps finished quest records for reference.")
    p.primary:SetText("Select a quest"); p.primary:Disable(); p.primary:SetScript("OnClick",function() end)
  elseif selected.kind=="quest" then
    local q=selected.data; local rewardText="Rewards: "..self:DescribeQuestRewards(q)
    p.selectedQuestID=q.id; p.deleteQuest:Show(); p.deleteQuest:SetText(p.deleteArmed==q.id and "Confirm delete" or "Delete quest")
    local lines={q.description,"","Status: YOUR QUEST - this is a definition you created.","Suggested level: "..(q.suggestedLevel and tostring(q.suggestedLevel) or "Any"),"Suggested player count: "..(q.suggestedPlayers and tostring(q.suggestedPlayers) or "Any"),"Repeatable: "..(q.repeatable and "Yes" or "No"),"Enter a recipient below, then use Share quest.","Steps: "..self.Count(q.steps),rewardText,"Quest ID: "..q.id}
    if q.predecessorQuestID then lines[self.Count(lines)+1]="Predecessor: "..q.predecessorQuestID end
    if q.followUpQuestID then lines[self.Count(lines)+1]="Follow-up: "..q.followUpQuestID end
    if q.turnInNPCID then lines[self.Count(lines)+1]="Reward turn-in NPC ID: "..q.turnInNPCID end
    p.detailTitle:SetText(q.title); p.detail:SetText(table.concat(lines,"\n"))
    p.shareTarget:Show(); p.shareTarget.label:Show()
    p.primary:SetText("Edit quest"); p.primary:SetScript("OnClick",function() QW:OpenQuestForSharing(q.id) end)
    p.resend:SetText("Share quest"); p.resend:Show(); p.resend:SetScript("OnClick",function()
      local ok,message=QW:ShareQuest(q.id,p.shareTarget:GetText())
      QW:Status(p,message or (ok and "Quest shared with "..p.shareTarget:GetText().."."))
    end)
  elseif selected.kind=="offer" then
    local o=selected.data; local lines={o.description,"","Status: NPC QUEST OFFER","Suggested level: "..(o.suggestedLevel and tostring(o.suggestedLevel) or "Any"),"Suggested player count: "..(o.suggestedPlayers and tostring(o.suggestedPlayers) or "Any"),"Repeatable: "..(o.repeatable and "Yes" or "No")}
    lines[self.Count(lines)+1]="Rewards: "..self:DescribeQuestRewards(o)
    if o.giverDialogue and o.giverDialogue~="" then lines[self.Count(lines)+1]="Dialogue: \""..o.giverDialogue.."\"" end
    if o.giverNPCID then lines[self.Count(lines)+1]="Quest giver NPC ID: "..o.giverNPCID end
    if o.turnInNPCID then lines[self.Count(lines)+1]="Reward turn-in NPC ID: "..o.turnInNPCID end
    lines[self.Count(lines)+1]="Target the quest giver (NPC proximity is checked by the game), then accept this offer."
    p.detailTitle:SetText(o.title); p.detail:SetText(table.concat(lines,"\n"))
    p.primary:SetText("Talk / accept quest"); p.primary:SetScript("OnClick",function()
      local ok,message=QW:AcceptQuestOffer(o.id); QW:Status(p,message or (ok and "Quest accepted.")); QW:RefreshQuestJournal()
    end)
  else
    local r=selected.data; local current=self:GetCurrentObjectiveIndices(r); local objectiveIndex,objectiveTotal=self:GetQuestStepProgress(r); local lines={r.description,"","Status: "..r.state,"Suggested level: "..(r.suggestedLevel and tostring(r.suggestedLevel) or "Any"),"Suggested player count: "..(r.suggestedPlayers and tostring(r.suggestedPlayers) or "Any"),"Repeatable: "..(r.repeatable and "Yes" or "No"),"Objectives complete: "..objectiveIndex.." / "..objectiveTotal}
    for _,stepIndex in ipairs(current) do
      local step=r.steps[stepIndex]; lines[self.Count(lines)+1]="[Step "..self:ObjectiveStepNumber(step,stepIndex).."] "..step.text
      local place=r.placeByID and r.placeByID[step.placeID]
      if place then local location="Location: "..place.zone; if place.x then location=location.." - "..place.x..", "..place.y.." (radius "..place.radius..")" end; lines[self.Count(lines)+1]=location end
      if step.npcID then lines[self.Count(lines)+1]="Target NPC ID: "..step.npcID elseif step.mobName and step.mobName~="" then lines[self.Count(lines)+1]="Target: "..step.mobName end
      if step.type=="kill" then lines[self.Count(lines)+1]="Kills: "..math.min((r.killProgress and r.killProgress[stepIndex]) or 0,step.count).." / "..step.count end
      local objectiveItems={}; for _,itemID in ipairs(self:ObjectiveItemIDs(step)) do local def=self.db.items[itemID]; objectiveItems[self.Count(objectiveItems)+1]=def and def.name or itemID end
      if #objectiveItems>0 then lines[self.Count(lines)+1]="RP items: "..table.concat(objectiveItems,", ").." x"..(step.count or 1).." each" end
      if step.type=="deliver" or step.type=="possess" then
        for _,itemProgress in ipairs(self:GetObjectiveItemProgress(r,step,stepIndex)) do
          local status="Satchel: "..itemProgress.have.." / "..itemProgress.required
          if step.type=="deliver" then status=status.." | Hand these to the target NPC" end
          lines[self.Count(lines)+1]=itemProgress.name.." - "..status
        end
      end
    end
    if #current==0 then lines[self.Count(lines)+1]="All objectives complete." end
    if r.turnInNPCID then lines[self.Count(lines)+1]="Reward turn-in NPC ID: "..r.turnInNPCID end
    lines[self.Count(lines)+1]="Rewards: "..self:DescribeQuestRewards(r)
    if r.followUpQuestID then lines[self.Count(lines)+1]="Follow-up on completion: "..r.followUpQuestID end
    p.detailTitle:SetText(r.title); p.detail:SetText(table.concat(lines,"\n"))
    if r.state=="active" then
      p.primary:SetText("Progress active objectives")
      p.primary:SetScript("OnClick",function()
        local ok,message=QW:AdvanceQuest(r.id)
        QW:Status(p,message or (ok and "Objective advanced.")); QW:RefreshQuestJournal()
      end)
    elseif r.state=="ready_to_turn_in" then
      p.primary:SetText("Talk / receive reward"); p.primary:SetScript("OnClick",function()
        local ok,message=QW:InteractWithTarget(); QW:Status(p,message or (ok and "Quest reward received.")); QW:RefreshQuestJournal()
      end)
    elseif r.state=="complete" then
      p.primary:SetText("Quest completed"); p.primary:Disable(); p.primary:SetScript("OnClick",function() end)
    else
      p.primary:SetText("Awaiting approval"); p.primary:Disable(); p.primary:SetScript("OnClick",function() end)
    end
  end
  local inbox={"RECENT REQUESTS:"}; local start=math.max(1,self.Count(self.db.inbox)-2)
  for i=start,self.Count(self.db.inbox) do inbox[self.Count(inbox)+1]=self.db.inbox[i] end
  p.inbox:SetText(table.concat(inbox,"\n"))
end
function QW:BuildSetPage(p)
  p.heading=p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); p.heading:SetPoint("TOPLEFT",8,-8); p.heading:SetText("Questweaver Sets - authored RP questlines and stories")
  p.setButtons={}; local i
  for i=1,8 do
    local entry=button(p,"",8,-32-(i-1)*34,245,function(self) p.selectedSetID=self.setID; p.deleteArmed=nil; QW:RefreshSetPage() end)
    entry.setID=nil; entry:Hide(); p.setButtons[QW.Count(p.setButtons)+1]=entry
  end
  p.empty=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.empty:SetPoint("TOPLEFT",8,-35); p.empty:SetWidth(245); p.empty:SetJustifyH("LEFT")
  p.detailTitle=p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); p.detailTitle:SetPoint("TOPLEFT",275,-32); p.detailTitle:SetWidth(300); p.detailTitle:SetJustifyH("LEFT")
  p.detail=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.detail:SetPoint("TOPLEFT",275,-62); p.detail:SetWidth(300); p.detail:SetJustifyH("LEFT")
  p.primary=button(p,"Create Questweaver Set",275,-270,175,function() QW.setCreator:Show(); QW.setCreator:Raise() end)
  p.edit=button(p,"Edit set",460,-270,95,function() end); p.edit:Hide()
  p.delete=button(p,"Delete set",460,-300,95,function()
    local id=p.selectedSetID; if not id then return end
    if p.deleteArmed~=id then p.deleteArmed=id; p.delete:SetText("Confirm"); QW:Status(p,"Click again to delete this Set; its quests/items are unchanged."); return end
    local ok,message=QW:DeleteSet(id); p.deleteArmed=nil; QW:Status(p,message); if ok then p.selectedSetID=nil end; QW:RefreshSetPage()
  end); p.delete:Hide()
  p.status=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.status:SetPoint("TOPLEFT",8,-335); p.status:SetWidth(570); p.status:SetJustifyH("LEFT")
end
function QW:OpenSetEditor(id)
  local set=self.db.sets[id]; local f=self.setCreator
  if not set or not f then return false end
  f.sid:SetText(set.id); f.stitle:SetText(set.title); f.sdesc:SetText(set.description); f.squests:SetText(table.concat(set.questIDs or {},",")); f.sitems:SetText(table.concat(set.itemIDs or {},",")); f:Show(); f:Raise(); return true
end
function QW:RefreshSetPage()
  if not self.ui then return end
  local p=self.ui.pages[5]; local entries={}; local id,set
  for id,set in pairs(self.db.sets) do entries[self.Count(entries)+1]=set end
  table.sort(entries,function(a,b) return a.title<b.title end)
  local selected=self.db.sets[p.selectedSetID]
  if not selected and entries[1] then selected=entries[1]; p.selectedSetID=selected.id end
  local i
  for i=1,self.Count(p.setButtons) do
    local entry=p.setButtons[i]; local data=entries[i]
    if data then entry.setID=data.id; entry:SetText("[SET] "..string.sub(data.title,1,29)); entry:Show() else entry.setID=nil; entry:Hide() end
  end
  p.empty:SetText(self.Count(entries)==0 and "No Questweaver Sets yet. Create one to organize your story." or "")
  if not selected then
    p.detailTitle:SetText("Select a Questweaver Set"); p.detail:SetText("A Set keeps an ordered questline and supporting RP items together."); p.edit:Hide(); p.delete:Hide()
  else
    p.detailTitle:SetText(selected.title); p.detail:SetText(table.concat(self:GetSetLines(selected),"\n")); p.edit:Show(); p.delete:Show(); p.delete:SetText(p.deleteArmed==selected.id and "Confirm" or "Delete set"); p.edit:SetScript("OnClick",function() QW:OpenSetEditor(selected.id) end)
  end
end
function QW:BuildCreatePage(p)
  p.help=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.help:SetPoint("TOPLEFT",20,-35); p.help:SetWidth(520); p.help:SetJustifyH("LEFT"); p.help:SetText("Create items, quests, NPC dialogue stories, and Questweaver story sets in focused editors.")
  button(p,"Create RP item",25,-90,210,function() QW.itemCreator:Show(); QW.itemCreator:Raise() end)
  button(p,"Create quest",250,-90,210,function() QW:OpenNewQuestCreator() end)
  button(p,"Create Questweaver Set",25,-180,210,function() QW.setCreator:Show(); QW.setCreator:Raise() end)
  button(p,"NPC dialogue stories",250,-180,210,function() QW:OpenNewNPCDialogue() end)
  button(p,"Create sealed-letter demo",25,-135,210,function()
    local letter,quest=QW:CreateDemo()
    if quest then local ok,message=QW:AssignQuestToCurrentPlayer(quest); QW:Status(p,message or (ok and "Demo quest assigned.")); QW:ShowActiveQuests() else QW:Status(p,"Could not create the demo.") end
  end)
  button(p,"Create Aldrassil boar demo",250,-135,210,function()
    local quest=QW:CreateBoarDemo()
    if quest then local ok,message=QW:AssignQuestToCurrentPlayer(quest); QW:Status(p,message or (ok and "Boar demo quest assigned.")); QW:ShowActiveQuests() else QW:Status(p,"Could not create the boar demo.") end
  end)
  p.status=p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); p.status:SetPoint("TOPLEFT",25,-220); p.status:SetWidth(540); p.status:SetJustifyH("LEFT")
end
function QW:NewCreatorWindow(name,title,width,height)
  local f=CreateFrame("Frame",name,UIParent,"UIPanelDialogTemplate"); f:SetWidth(width); f:SetHeight(height); f:SetPoint("CENTER"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing); f:Hide()
  f.title=f:CreateFontString(nil,"OVERLAY","GameFontHighlight"); f.title:SetPoint("TOP",0,-12); f.title:SetText(title)
  button(f,"Close",width-82,-32,65,function() f:Hide() end)
  return f
end
function QW:UpdateItemIconPreview(f)
  local icon=self:NormalizeIcon(f.iconPath:GetText())
  if not self:ValidateIcon(icon) then icon="Interface\\Icons\\INV_Misc_QuestionMark" end
  f.preview:SetTexture(icon)
end
function QW:CreateItemCreator()
  local f=self:NewCreatorWindow("QuestweaverItemCreatorFrame","Create RP item",500,365); self.itemCreator=f
  f:SetScript("OnHide",function() f.onItemCreated=nil end)
  f.previewBorder=f:CreateTexture(nil,"BACKGROUND"); f.previewBorder:SetPoint("TOPLEFT",25,-58); f.previewBorder:SetWidth(84); f.previewBorder:SetHeight(84); f.previewBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  f.preview=f:CreateTexture(nil,"ARTWORK"); f.preview:SetPoint("TOPLEFT",f.previewBorder,"TOPLEFT",8,-8); f.preview:SetPoint("BOTTOMRIGHT",f.previewBorder,"BOTTOMRIGHT",-8,8); f.preview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  f.name=text(f,"Item name",130,-62,320); f.iconPath=text(f,"Selected icon path (or choose Browse icons)",130,-108,240); f.iconPath:SetScript("OnTextChanged",function() QW:UpdateItemIconPreview(f) end)
  button(f,"Browse icons",380,-111,90,function() QW:ShowIconPicker(f) end)
  f.desc=text(f,"Description",25,-185,440); f.stack=text(f,"Max stack size",25,-230,80); f.stack:SetText("1"); f.category="misc"
  f.categoryButton=button(f,"Category: misc",135,-230,130,function()
    f.categoryIndex=(f.categoryIndex or 3)%QW.Count(QW.ITEM_CATEGORIES)+1; f.category=QW.ITEM_CATEGORIES[f.categoryIndex]; f.categoryButton:SetText("Category: "..(f.category=="quest" and "quest item" or f.category))
  end); f.categoryIndex=3
  f.categoryHelp=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.categoryHelp:SetPoint("TOPLEFT",275,-230); f.categoryHelp:SetWidth(195); f.categoryHelp:SetText("Quest/reward items enter via quests only.")
  f.lootToggle=button(f,"Add Loot Chance",25,-265,145,function()
    if f.lootSection:IsShown() then
      f.lootSection:Hide(); f.lootToggle:SetText("Add Loot Chance"); f:SetHeight(365)
      f.createButton:ClearAllPoints(); f.createButton:SetPoint("TOPLEFT",25,-280); f.status:ClearAllPoints(); f.status:SetPoint("TOPLEFT",155,-283)
    else
      f.lootSection:Show(); f.lootToggle:SetText("Hide Loot Chance"); f:SetHeight(465)
      f.createButton:ClearAllPoints(); f.createButton:SetPoint("TOPLEFT",25,-405); f.status:ClearAllPoints(); f.status:SetPoint("TOPLEFT",155,-405)
    end
  end)
  f.lootSection=CreateFrame("Frame",nil,f); f.lootSection:SetPoint("TOPLEFT",20,-294); f.lootSection:SetWidth(460); f.lootSection:SetHeight(93); f.lootSection:Hide()
  f.lootHint=f.lootSection:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.lootHint:SetPoint("TOPLEFT",5,-2); f.lootHint:SetWidth(440); f.lootHint:SetJustifyH("LEFT"); f.lootHint:SetText("When you personally kill a matching NPC, this item can drop. NPC template IDs are language-independent.")
  f.lootNPCs=text(f.lootSection,"NPC IDs (comma separated)",5,-42,245); f.lootChance=text(f.lootSection,"Chance per kill %",270,-42,110); f.lootChance:SetText("25")
  f.createButton=button(f,"Create item",25,-280,120,function()
    local lootChances={}
    if f.lootSection:IsShown() then
      local npcIDs={}; for value in string.gmatch(f.lootNPCs:GetText() or "","[^,%s]+") do npcIDs[#npcIDs+1]=value end
      local rules={}; local chance=f.lootChance:GetText() or ""
      for _,npcID in ipairs(npcIDs) do rules[#rules+1]=npcID.."~"..chance end
      local parseError; lootChances,parseError=QW:ParseLootChances(table.concat(rules,";"))
      if not lootChances then QW:Status(f,parseError or "Enter valid NPC IDs and a whole chance from 1 to 100."); return end
      if #npcIDs==0 then QW:Status(f,"Enter at least one NPC ID, or hide Loot Chance to create a normal item."); return end
    end
    local id,message=QW:CreateItem(f.name:GetText(),QW:NormalizeIcon(f.iconPath:GetText()),f.desc:GetText(),f.stack:GetText(),f.category,lootChances)
    QW:Status(f,message or ("Created Maker definition: "..id)); if id then QW:RefreshUI(); if f.onItemCreated then local callback=f.onItemCreated; f.onItemCreated=nil; f:Hide(); callback(id) end end
  end)
  f.status=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.status:SetPoint("TOPLEFT",155,-283); f.status:SetWidth(310); f.status:SetJustifyH("LEFT")
end
function QW:CreateQuestCreator()
  local f=self:NewCreatorWindow("QuestweaverQuestCreatorFrame","Create and share quest",620,770); self.questCreator=f
  local general=CreateFrame("Frame",nil,f); general:SetPoint("TOPLEFT",f,"TOPLEFT",18,-62); general:SetWidth(584); general:SetHeight(560); f.generalSection=general
  local objectives=CreateFrame("Frame",nil,f); objectives:SetPoint("TOPLEFT",f,"TOPLEFT",18,-62); objectives:SetWidth(584); objectives:SetHeight(560); f.objectiveSection=objectives
  general.heading=general:CreateFontString(nil,"OVERLAY","GameFontNormal"); general.heading:SetPoint("TOPLEFT",4,-10); general.heading:SetText("GENERAL QUEST DETAILS")
  objectives.heading=objectives:CreateFontString(nil,"OVERLAY","GameFontNormal"); objectives.heading:SetPoint("TOPLEFT",4,-10); objectives.heading:SetText("OBJECTIVES — complete in this order")
  f.generalTab=button(f,"General",18,-36,125,function() general:Show(); objectives:Hide(); f.generalTab:SetText("[ General ]"); f.objectiveTab:SetText("Objectives") end)
  f.objectiveTab=button(f,"Objectives",151,-36,125,function() general:Hide(); objectives:Show(); f.generalTab:SetText("General"); f.objectiveTab:SetText("[ Objectives ]") end)
  f.qtitle=text(general,"Quest title",18,-55,205); f.qdesc=text(general,"Quest description",235,-55,330)
  f.rewardItems={}; f.rewardRows={}; f.selectedReward=nil
  f.rewardLabel=general:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.rewardLabel:SetPoint("TOPLEFT",18,-100); f.rewardLabel:SetText("Rewards (each reward can have its own quantity):")
  f.rewardScroll=CreateFrame("ScrollFrame","QuestweaverRewardScroll",general,"UIPanelScrollFrameTemplate"); f.rewardScroll:SetPoint("TOPLEFT",18,-115); f.rewardScroll:SetWidth(365); f.rewardScroll:SetHeight(54)
  f.rewardContent=CreateFrame("Frame",nil,f.rewardScroll); f.rewardContent:SetWidth(340); f.rewardContent:SetHeight(1); f.rewardScroll:SetScrollChild(f.rewardContent)
  f.rewardQuantity=text(general,"Selected quantity",400,-115,100); f.rewardQuantity:SetText("1")
  local function refreshRewards()
    local content=f.rewardContent; content:SetHeight(math.max(1,QW.Count(f.rewardItems)*24))
    for i=1,QW.Count(f.rewardRows) do f.rewardRows[i]:Hide() end
    for i,reward in ipairs(f.rewardItems) do
      local row=f.rewardRows[i]
      if not row then row=CreateFrame("Button",nil,content,"UIPanelButtonTemplate"); row:SetWidth(330); row:SetHeight(22); row:SetScript("OnClick",function(self) f.selectedReward=self.rewardIndex; local selected=f.rewardItems[self.rewardIndex]; f.rewardQuantity:SetText(selected and tostring(selected.count) or "1"); refreshRewards() end); f.rewardRows[i]=row end
      local item=QW.db.items[reward.id]; row.rewardIndex=i; row:ClearAllPoints(); row:SetPoint("TOPLEFT",content,"TOPLEFT",0,-((i-1)*24)); row:SetText((f.selectedReward==i and "[x] " or "[ ] ")..(item and item.name or reward.id).." x"..reward.count); row:Show()
    end
  end
  f.RefreshQuestRewardItems=refreshRewards
  f.addRewardButton=button(general,"Select reward item",18,-177,135,function()
    QW:ShowReferencePicker("item",nil,"append",function(itemID)
      for _,reward in ipairs(f.rewardItems) do if reward.id==itemID then QW:Status(f,"That item is already a reward."); return end end
      if QW.Count(f.rewardItems)>=12 then QW:Status(f,"A quest can have at most 12 rewards."); return end
      f.rewardItems[QW.Count(f.rewardItems)+1]={id=itemID,count=1}; f.selectedReward=QW.Count(f.rewardItems); f.rewardQuantity:SetText("1"); refreshRewards()
    end)
  end)
  f.removeRewardButton=button(general,"Remove selected",160,-177,125,function() if f.selectedReward then table.remove(f.rewardItems,f.selectedReward); f.selectedReward=nil; f.rewardQuantity:SetText("1"); refreshRewards() end end)
  f.setRewardCountButton=button(general,"Set quantity",400,-177,100,function()
    local count=tonumber(f.rewardQuantity:GetText()); local reward=f.selectedReward and f.rewardItems[f.selectedReward]
    if not reward then QW:Status(f,"Select a reward first."); return end
    if not count or count<1 or count>999 or count~=math.floor(count) then QW:Status(f,"Reward quantity must be a whole number from 1-999."); return end
    reward.count=count; refreshRewards()
  end)
  f.places=text(general,"Real locations: placeId~zone~x~y~radius~description ; ...",18,-222,545)
  f.questItems=text(general,"Additional quest item IDs (comma separated)",18,-267,220)
  f.suggestedLevel=text(general,"Suggested level (optional, 1-999)",250,-267,150)
  f.suggestedPlayers=text(general,"Suggested player count (optional, 1-40)",415,-267,150)
  f.followUp=text(general,"Follow-up quest ID (optional)",18,-312,260)
  f.predecessor=text(general,"Predecessor quest ID (optional)",300,-312,265)
  f.giverTarget=text(general,"Quest giver NPC ID (optional)",18,-357,185)
  f.giverDialogue=text(general,"Quest giver dialogue (for NPC offer)",18,-402,545)
  f.turnInTarget=text(general,"Reward turn-in NPC ID (optional)",18,-447,200)
  f.qid=text(general,"Quest ID",18,-492,240); f.qtarget=text(general,"Recipient (for sharing)",300,-492,265)
  f.steps=text(objectives,nil,18,-285,545); f.steps:Hide()
  local function browseOnRightClick(field,kind,mode)
    field:SetScript("OnMouseDown",function(_,mouseButton)
      mouseButton=mouseButton or arg1
      if mouseButton=="RightButton" then QW:ShowReferencePicker(kind,field,mode) end
    end)
  end
  browseOnRightClick(f.questItems,"item","append")
  local objectiveTypes={"kill","collect","loot","dialogue","deliver","possess","visit","manual"}; f.objectiveTypeIndex=1
  local objectiveLabels={kill="Kill NPC",collect="Collect item at place",loot="Loot item from mob",dialogue="Talk to NPC",deliver="Deliver item",possess="Have item",visit="Visit place",manual="Manual approval"}
  f.objectiveSteps={}; f.selectedObjective=nil
  local objectiveScroll=CreateFrame("ScrollFrame","QuestweaverObjectiveScroll",objectives,"UIPanelScrollFrameTemplate")
  objectiveScroll:SetPoint("TOPLEFT",18,-48); objectiveScroll:SetWidth(535); objectiveScroll:SetHeight(205)
  local objectiveContent=CreateFrame("Frame",nil,objectiveScroll); objectiveContent:SetWidth(510); objectiveContent:SetHeight(1); objectiveScroll:SetScrollChild(objectiveContent); f.objectiveContent=objectiveContent; f.objectiveRows={}
  local function refreshObjectiveList()
    for i=1,QW.Count(f.objectiveRows) do f.objectiveRows[i]:Hide(); f.objectiveRows[i].remove:Hide() end
    local count=QW.Count(f.objectiveSteps); objectiveContent:SetHeight(math.max(1,count*34))
    if count==0 then
      if not f.objectiveEmpty then f.objectiveEmpty=objectiveContent:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); f.objectiveEmpty:SetPoint("TOPLEFT",8,-8); f.objectiveEmpty:SetText("No objectives yet. Click Add objective to choose a type.") end
      f.objectiveEmpty:Show()
    else
      if f.objectiveEmpty then f.objectiveEmpty:Hide() end
      for i=1,count do
        local row=f.objectiveRows[i]
        if not row then
          row=CreateFrame("Button",nil,objectiveContent,"UIPanelButtonTemplate"); row:SetWidth(440); row:SetHeight(28)
          row.remove=button(objectiveContent,"X",0,0,28,function(self) local at=self.objectiveIndex; if at then table.remove(f.objectiveSteps,at); f.selectedObjective=nil; refreshObjectiveList(); QW:SyncObjectiveEditor() end end)
          row:SetScript("OnClick",function(self) f.selectedObjective=self.objectiveIndex; QW:SyncObjectiveEditor() end); f.objectiveRows[i]=row
        end
        local objective=f.objectiveSteps[i]; local stepNumber=tonumber(objective.stepNumber) or i
        row.objectiveIndex=i; row:ClearAllPoints(); row:SetPoint("TOPLEFT",objectiveContent,"TOPLEFT",0,-((i-1)*34)); row:SetText("Step "..stepNumber.." | "..(objectiveLabels[objective.type] or objective.type).." - "..(objective.text or "")); row:Show()
        row.remove.objectiveIndex=i; row.remove:ClearAllPoints(); row.remove:SetPoint("LEFT",row,"RIGHT",4,0); row.remove:Show()
      end
    end
    local encoded={}; for i=1,count do local step=f.objectiveSteps[i]; local itemIDs=QW:ObjectiveItemIDs(step); encoded[i]=table.concat({QW:Escape(step.type or ""),QW:Escape(itemIDs[1] or ""),QW:Escape(step.count or ""),QW:Escape(step.placeID or ""),QW:Escape(step.mobName or ""),QW:Escape(step.text or ""),QW:Escape(step.stepNumber or i),QW:Escape(table.concat(itemIDs,","))},"~") end
    f.steps:SetText(table.concat(encoded,";"))
  end
  QW.RefreshObjectiveList=refreshObjectiveList
  f.objectiveGroup=text(objectives,"Step number (same number = parallel)",18,-320,95); f.objectiveGroup:SetText("1")
  f.objectiveText=text(objectives,"Objective text",125,-320,438); f.objectiveText:SetText("")
  f.objectiveItemIDs={}; f.objectiveItemRows={}; f.selectedObjectiveItem=nil
  f.objectiveItemsLabel=objectives:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.objectiveItemsLabel:SetPoint("TOPLEFT",18,-350); f.objectiveItemsLabel:SetText("RP items (count applies to each item):")
  f.objectiveItemsScroll=CreateFrame("ScrollFrame","QuestweaverObjectiveItemsScroll",objectives,"UIPanelScrollFrameTemplate"); f.objectiveItemsScroll:SetPoint("TOPLEFT",18,-365); f.objectiveItemsScroll:SetWidth(535); f.objectiveItemsScroll:SetHeight(62)
  f.objectiveItemsContent=CreateFrame("Frame",nil,f.objectiveItemsScroll); f.objectiveItemsContent:SetWidth(510); f.objectiveItemsContent:SetHeight(1); f.objectiveItemsScroll:SetScrollChild(f.objectiveItemsContent)
  local function refreshObjectiveItems()
    local kind=objectiveTypes[f.objectiveTypeIndex]; local needsItems=kind=="collect" or kind=="loot" or kind=="deliver" or kind=="possess"
    if needsItems then f.objectiveItemsLabel:Show(); f.objectiveItemsScroll:Show(); f.addObjectiveItemButton:Show(); f.removeObjectiveItemButton:Show()
    else f.objectiveItemsLabel:Hide(); f.objectiveItemsScroll:Hide(); f.addObjectiveItemButton:Hide(); f.removeObjectiveItemButton:Hide() end
    if f.objectiveCount and f.objectiveCount.label then f.objectiveCount.label:SetText(needsItems and "Count per item" or "Count") end
    local content=f.objectiveItemsContent; content:SetHeight(math.max(1,QW.Count(f.objectiveItemIDs)*24))
    for i=1,QW.Count(f.objectiveItemRows) do f.objectiveItemRows[i]:Hide() end
    for i,itemID in ipairs(f.objectiveItemIDs) do
      local row=f.objectiveItemRows[i]
      if not row then row=CreateFrame("Button",nil,content,"UIPanelButtonTemplate"); row:SetWidth(490); row:SetHeight(22); row:SetScript("OnClick",function(self) f.selectedObjectiveItem=self.itemIndex; refreshObjectiveItems() end); f.objectiveItemRows[i]=row end
      local def=QW.db.items[itemID]; row.itemIndex=i; row:ClearAllPoints(); row:SetPoint("TOPLEFT",content,"TOPLEFT",0,-((i-1)*24)); row:SetText((f.selectedObjectiveItem==i and "[x] " or "[ ] ")..(def and def.name or "Missing item").."  ["..itemID.."]"); row:Show()
    end
  end
  f.RefreshObjectiveItems=refreshObjectiveItems
  f.addObjectiveItemButton=button(objectives,"Add RP item",18,-435,125,function()
    QW:ShowReferencePicker("item",nil,"append",function(itemID)
      for _,existing in ipairs(f.objectiveItemIDs) do if existing==itemID then QW:Status(f,"That item is already in this objective."); return end end
      if QW.Count(f.objectiveItemIDs)>=12 then QW:Status(f,"An objective can use at most 12 items."); return end
      f.objectiveItemIDs[QW.Count(f.objectiveItemIDs)+1]=itemID; f.selectedObjectiveItem=QW.Count(f.objectiveItemIDs); refreshObjectiveItems()
    end)
  end)
  f.removeObjectiveItemButton=button(objectives,"Remove selected",150,-435,135,function()
    if f.selectedObjectiveItem then table.remove(f.objectiveItemIDs,f.selectedObjectiveItem); f.selectedObjectiveItem=nil; refreshObjectiveItems() end
  end)
  f.objectiveCount=text(objectives,"Count per item",18,-485,100); f.objectiveCount:SetText("1")
  f.objectivePlace=text(objectives,"Place ID",135,-485,220)
  f.targetSpec=text(objectives,"Target NPC ID (kill / dialogue / deliver)",18,-530,230)
  button(objectives,"Use targeted NPC",260,-533,145,function()
    local npcID,npcName=QW:GetTargetNPCInfo()
    if not npcID then QW:Status(f,npcName); return end
    if objectiveTypes[f.objectiveTypeIndex]=="loot" then f.targetSpec:SetText(npcName) else f.targetSpec:SetText("npc:"..npcID) end
    QW:Status(f,"Selected NPC "..npcID.." ("..npcName..").")
  end)
  function QW:SyncObjectiveEditor()
    local step=f.selectedObjective and f.objectiveSteps[f.selectedObjective]
    if step then
      f.objectiveTypeIndex=1; for i=1,QW.Count(objectiveTypes) do if objectiveTypes[i]==step.type then f.objectiveTypeIndex=i end end
      f.objectiveText:SetText(step.text or ""); f.objectiveGroup:SetText(tostring(step.stepNumber or f.selectedObjective)); f.objectiveItemIDs=QW:Copy(QW:ObjectiveItemIDs(step)); f.selectedObjectiveItem=nil; f.objectiveCount:SetText(step.count and tostring(step.count) or ""); f.objectivePlace:SetText(step.placeID or ""); f.targetSpec:SetText(step.mobName or "")
      f.applyObjectiveButton:SetText("Update objective")
    else
      local nextGroup=1; for i=1,QW.Count(f.objectiveSteps) do nextGroup=math.max(nextGroup,tonumber(f.objectiveSteps[i].stepNumber) or i) end; nextGroup=QW.Count(f.objectiveSteps)>0 and nextGroup+1 or 1
      f.objectiveText:SetText(""); f.objectiveGroup:SetText(tostring(nextGroup)); f.objectiveItemIDs={}; f.selectedObjectiveItem=nil; f.objectiveCount:SetText("1"); f.objectivePlace:SetText(""); f.targetSpec:SetText(""); f.applyObjectiveButton:SetText("Add to objective list")
    end
    f.objectiveTypeLabel:SetText("Type: "..(objectiveLabels[objectiveTypes[f.objectiveTypeIndex]] or "Choose a type")); refreshObjectiveItems(); refreshObjectiveList()
  end
  local function applyObjective()
    local kind=objectiveTypes[f.objectiveTypeIndex]; local objective=f.objectiveText:GetText(); local itemIDs=QW:Copy(f.objectiveItemIDs or {}); local itemID=itemIDs[1] or ""; local count=tonumber(f.objectiveCount:GetText()); local placeID=f.objectivePlace:GetText(); local target=f.targetSpec:GetText(); local stepNumber=tonumber(f.objectiveGroup:GetText())
    local function clean(value,allowEmpty) return (allowEmpty and value=="") or (QW:ValidateString(value,300) and not string.find(value,"[;~]")) end
    if not clean(objective,false) or not clean(placeID,true) or not clean(target,true) then QW:Status(f,"Objective fields cannot be blank where required or contain ; or ~."); return end
    if not stepNumber or stepNumber<1 or stepNumber>99 or stepNumber~=math.floor(stepNumber) then QW:Status(f,"Step number must be a whole number from 1 to 99."); return end
    if not f.selectedObjective and QW.Count(f.objectiveSteps)>=12 then QW:Status(f,"A quest can have at most 12 objectives."); return end
    if (kind=="kill" or kind=="collect" or kind=="loot" or kind=="deliver" or kind=="possess") and (not count or count<1 or count>999) then QW:Status(f,"This objective needs a count from 1-999."); return end
    if (kind=="collect" or kind=="loot" or kind=="deliver" or kind=="possess") and #itemIDs<1 then QW:Status(f,"Add at least one RP item to this objective."); return end
    if (kind=="collect" or kind=="visit") and not QW:ValidateString(placeID,80) then QW:Status(f,"This objective needs a defined place ID."); return end
    if (kind=="kill" or kind=="deliver") and not string.match(target,"^npc:%d+$") then QW:Status(f,"Target an NPC, then use Use targeted NPC before adding this objective."); return end
    if kind=="loot" and target=="" then QW:Status(f,"This loot objective needs the exact mob name in the target field."); return end
    if target~="" and kind~="loot" and not string.match(target,"^npc:%d+$") then QW:Status(f,"Use Targeted NPC to set an NPC ID, or leave the target field empty."); return end
    if kind=="kill" or kind=="dialogue" or kind=="visit" or kind=="manual" then itemIDs={}; itemID="" end
    if kind=="dialogue" or kind=="visit" or kind=="manual" then count=nil end
    if kind~="kill" and kind~="dialogue" and kind~="deliver" and kind~="loot" then target="" end
    local step={type=kind,itemID=itemID,itemIDs=itemIDs,count=count,placeID=placeID,mobName=target,text=objective,stepNumber=stepNumber}
    if f.selectedObjective then f.objectiveSteps[f.selectedObjective]=step else f.objectiveSteps[QW.Count(f.objectiveSteps)+1]=step end
    f.selectedObjective=nil; refreshObjectiveList(); QW:SyncObjectiveEditor(); QW:Status(f,"Objective saved to the list.")
  end
  f.objectiveTypeLabel=objectives:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.objectiveTypeLabel:SetPoint("TOPLEFT",290,-275); f.objectiveTypeLabel:SetText("Type: choose one")
  f.applyObjectiveButton=button(objectives,"Add to objective list",420,-275,145,applyObjective)
  local typePicker=CreateFrame("Frame","QuestweaverObjectiveTypePicker",objectives,"BackdropTemplate"); typePicker:SetPoint("TOPLEFT",18,-275); typePicker:SetWidth(220); typePicker:SetHeight(220); typePicker:SetFrameStrata("DIALOG"); typePicker:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}}); typePicker:Hide(); f.objectiveTypePicker=typePicker
  for i=1,QW.Count(objectiveTypes) do
    local kind=objectiveTypes[i]; local selectedIndex=i; button(typePicker,objectiveLabels[kind],8,-8-((i-1)*24),195,function()
      f.objectiveTypeIndex=selectedIndex; f.selectedObjective=nil; f.objectiveTypePicker:Hide()
      local defaults={kill="Defeat the targeted NPC.",collect="Collect the item at this location.",loot="Loot the item from this mob.",dialogue="Speak to the targeted NPC.",deliver="Deliver the RP item.",possess="Carry the required RP item.",visit="Visit this location.",manual="Request manual approval."}
      local nextGroup=1; for i=1,QW.Count(f.objectiveSteps) do nextGroup=math.max(nextGroup,tonumber(f.objectiveSteps[i].stepNumber) or i) end; nextGroup=QW.Count(f.objectiveSteps)>0 and nextGroup+1 or 1
      f.objectiveText:SetText(defaults[kind]); f.objectiveGroup:SetText(tostring(nextGroup)); f.objectiveItemIDs={}; f.selectedObjectiveItem=nil; refreshObjectiveItems(); f.objectiveCount:SetText((kind=="kill" or kind=="collect" or kind=="loot" or kind=="deliver" or kind=="possess") and "1" or ""); f.objectivePlace:SetText(""); f.targetSpec:SetText("")
      f.objectiveTypeLabel:SetText("Type: "..objectiveLabels[kind]); f.applyObjectiveButton:SetText("Add to objective list")
    end)
  end
  button(objectives,"Add objective",18,-275,130,function() f.objectiveTypePicker:Show(); f.objectiveTypePicker:Raise() end)
  button(objectives,"New objective",154,-275,120,function() f.selectedObjective=nil; QW:SyncObjectiveEditor() end)
  refreshObjectiveList()
  browseOnRightClick(f.followUp,"quest","replace"); browseOnRightClick(f.predecessor,"quest","replace")
  button(general,"Use NPC",215,-360,100,function()
    local npcID,npcName=QW:GetTargetNPCInfo()
    if not npcID then QW:Status(f,npcName); return end
    f.giverTarget:SetText("npc:"..npcID); QW:Status(f,"Quest giver set to "..npcName.." (NPC "..npcID..").")
  end)
  button(general,"Use giver",230,-450,95,function()
    local giver=f.giverTarget:GetText()
    if not string.match(giver or "","^npc:%d+$") then QW:Status(f,"Set a quest giver NPC first, or enter the turn-in NPC ID."); return end
    f.turnInTarget:SetText(giver); QW:Status(f,"Reward will be granted by the quest giver.")
  end)
  button(general,"Use target",335,-450,95,function()
    local npcID,npcName=QW:GetTargetNPCInfo()
    if not npcID then QW:Status(f,npcName); return end
    f.turnInTarget:SetText("npc:"..npcID); QW:Status(f,"Reward will be granted by "..npcName.." (NPC "..npcID..").")
  end)
  f.repeatable=false
  f.repeatableButton=button(general,"Repeatable: No",440,-450,125,function()
    f.repeatable=not f.repeatable; f.repeatableButton:SetText("Repeatable: "..(f.repeatable and "Yes" or "No"))
  end)
  f.createButton=button(f,"Create quest",18,-595,120,function()
    local steps=QW:ParseSteps(f.steps:GetText()); local places=QW:ParsePlaces(f.places:GetText()); local ids=QW:ParseItemIDs(f.questItems:GetText())
    local wasEditing=f.editingID~=nil
    local id,message=QW:CreateQuest(f.qtitle:GetText(),f.qdesc:GetText(),steps or {},f.rewardItems or {},nil,places or {},ids or {},f.followUp:GetText(),f.predecessor:GetText(),f.giverTarget:GetText(),f.giverPlaceIDValue or "",f.giverDialogue:GetText(),f.turnInTarget:GetText(),f.editingID,f.repeatable==true,f.suggestedLevel:GetText(),f.suggestedPlayers:GetText())
    if id then f.qid:SetText(id); if wasEditing then f.createButton:SetText("Save changes") end end; QW:Status(f,message or ((wasEditing and "Updated quest: " or "Created quest: ")..id)); QW:RefreshUI()
  end)
  general:Show(); objectives:Hide(); f.generalTab:SetText("[ General ]")
  f.createButton:ClearAllPoints(); f.createButton:SetPoint("TOPLEFT",f,"TOPLEFT",18,-641)
  button(f,"Share active",150,-641,105,function() local ok,message=QW:ShareQuest(f.qid:GetText(),f.qtarget:GetText()); QW:Status(f,message or (ok and "Quest shared.")) end)
  button(f,"Send NPC offer",265,-641,130,function() local ok,message=QW:OfferQuest(f.qid:GetText(),f.qtarget:GetText()); QW:Status(f,message or (ok and "NPC quest offer sent.")) end)
  f.hint=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.hint:SetPoint("TOPLEFT",18,-686); f.hint:SetWidth(560); f.hint:SetJustifyH("LEFT"); f.hint:SetText("NPC interactions check the selected NPC ID; proximity is handled by the game. Turn-in NPC: use giver to require returning to the quest giver, or enter another NPC ID. Target that NPC and use /qw interact after the final objective. Right-click Item/Quest ID fields to browse choices.")
  f.status=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.status:SetPoint("TOPLEFT",18,-726); f.status:SetWidth(560); f.status:SetJustifyH("LEFT")
end
function QW:OpenNewQuestCreator()
  local f=self.questCreator; if not f then return end
  f.editingID=nil; f.rewardItems={{id=self.DEFAULT_TOKEN_ID,count=1}}; f.selectedReward=1; f.rewardQuantity:SetText("1"); f:RefreshQuestRewardItems(); f.giverPlaceIDValue=""; f.repeatable=false; f.repeatableButton:SetText("Repeatable: No"); f.qtitle:SetText(""); f.qdesc:SetText(""); f.objectiveSteps={}; f.selectedObjective=nil; f.steps:SetText(""); self:SyncObjectiveEditor(); f.places:SetText(""); f.questItems:SetText(""); f.suggestedLevel:SetText(""); f.suggestedPlayers:SetText(""); f.followUp:SetText(""); f.predecessor:SetText(""); f.giverTarget:SetText(""); f.giverDialogue:SetText(""); f.turnInTarget:SetText(""); f.qid:SetText(""); f.qtarget:SetText(""); f.createButton:SetText("Create quest")
  f.generalSection:Show(); f.objectiveSection:Hide(); f.generalTab:SetText("[ General ]"); f.objectiveTab:SetText("Objectives")
  f:Show(); f:Raise(); f.qtitle:SetFocus()
end
function QW:CreateNPCDialogueCreator()
  local f=self:NewCreatorWindow("QuestweaverNPCDialogueCreatorFrame","NPC dialogue & story editor",620,580); self.npcDialogueCreator=f
  f.dialogueID=text(f,"Narrative ID (blank creates a new one)",18,-62,285)
  f.npcID=text(f,"NPC ID",18,-108,155)
  button(f,"Use targeted NPC",185,-111,140,function()
    local npcID,npcName=QW:GetTargetNPCInfo()
    if not npcID then QW:Status(f,npcName); return end
    f.npcID:SetText("npc:"..npcID); f.npcName:SetText(npcName)
  end)
  f.npcName=text(f,"NPC name",18,-153,285)
  f.dialogueTitle=text(f,"Story title",18,-198,285)
  f.dialogueText=text(f,"NPC narrative / dialogue (up to 500 characters)",18,-243,285,70); if f.dialogueText.SetMultiLine then f.dialogueText:SetMultiLine(true) end; if f.dialogueText.SetMaxLetters then f.dialogueText:SetMaxLetters(500) end
  f.questIDs=text(f,"Optional linked quest offers",18,-338,285)
  button(f,"Choose quests",18,-363,140,function() QW:ShowReferencePicker("quest",f.questIDs,"append") end)
  f.shareTarget=text(f,"Share story with player",18,-404,285)
  button(f,"Save narrative",18,-443,140,function()
    local quests=QW:ParseSetQuestIDs(f.questIDs:GetText())
    if not quests then QW:Status(f,"Choose up to 12 unique quest definitions."); return end
    local id,message=QW:SaveNPCDialogue(f.dialogueID:GetText(),f.npcID:GetText(),f.npcName:GetText(),f.dialogueTitle:GetText(),f.dialogueText:GetText(),quests)
    if id then f.dialogueID:SetText(id); f.deleteArmed=nil; QW:RefreshNPCDialogueList() end
    QW:Status(f,message or "Could not save narrative.")
  end)
  button(f,"Save + share",168,-443,140,function()
    local quests=QW:ParseSetQuestIDs(f.questIDs:GetText())
    if not quests then QW:Status(f,"Choose up to 12 unique quest definitions."); return end
    local id,message=QW:SaveNPCDialogue(f.dialogueID:GetText(),f.npcID:GetText(),f.npcName:GetText(),f.dialogueTitle:GetText(),f.dialogueText:GetText(),quests)
    if not id then QW:Status(f,message); return end
    f.dialogueID:SetText(id); f.deleteArmed=nil; QW:RefreshNPCDialogueList()
    local ok,shareMessage=QW:ShareNPCDialogue(id,f.shareTarget:GetText())
    QW:Status(f,shareMessage or message or (ok and "Narrative shared."))
  end)
  f.deleteButton=button(f,"Delete",18,-474,90,function()
    local id=f.dialogueID:GetText()
    if not id or id=="" then QW:Status(f,"Choose a saved NPC story first."); return end
    if f.deleteArmed~=id then f.deleteArmed=id; f.deleteButton:SetText("Confirm delete"); QW:Status(f,"Click Delete again to remove this NPC story."); return end
    local ok,message=QW:DeleteNPCDialogue(id); f.deleteArmed=nil; f.deleteButton:SetText("Delete"); QW:Status(f,message)
    if ok then QW:OpenNewNPCDialogue() end
    QW:RefreshNPCDialogueList()
  end)
  f.status=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.status:SetPoint("TOPLEFT",18,-510); f.status:SetWidth(285); f.status:SetJustifyH("LEFT")
  f.savedHeading=f:CreateFontString(nil,"OVERLAY","GameFontNormal"); f.savedHeading:SetPoint("TOPLEFT",340,-58); f.savedHeading:SetText("SAVED NPC STORIES")
  f.savedButtons={}
  for i=1,12 do
    local entry=button(f,"",340,-82-(i-1)*25,245,function(self) QW:OpenNPCDialogueEditor(self.dialogueID) end)
    entry.dialogueID=nil; entry:Hide(); f.savedButtons[i]=entry
  end
end
function QW:RefreshNPCDialogueList()
  local f=self.npcDialogueCreator; if not f then return end
  local entries={}; for _,dialogue in pairs(self.db.npcDialogs or {}) do entries[self.Count(entries)+1]=dialogue end
  table.sort(entries,function(a,b) if a.npcName==b.npcName then return a.title<b.title end return a.npcName<b.npcName end)
  for i=1,self.Count(f.savedButtons) do
    local buttonRow=f.savedButtons[i]; local dialogue=entries[i]
    if dialogue then buttonRow.dialogueID=dialogue.id; buttonRow:SetText(string.sub(dialogue.npcName..": "..dialogue.title,1,36)); buttonRow:Show()
    else buttonRow.dialogueID=nil; buttonRow:Hide() end
  end
end
function QW:OpenNPCDialogueEditor(id)
  local f=self.npcDialogueCreator; local dialogue=id and self.db.npcDialogs[id]
  if not f then return false end
  if not dialogue then return self:OpenNewNPCDialogue() end
  f.dialogueID:SetText(dialogue.id); f.npcID:SetText("npc:"..dialogue.npcID); f.npcName:SetText(dialogue.npcName); f.dialogueTitle:SetText(dialogue.title); f.dialogueText:SetText(dialogue.dialogue); f.questIDs:SetText(table.concat(dialogue.questIDs or {},",")); f.deleteArmed=nil; f.deleteButton:SetText("Delete")
  f:Show(); f:Raise(); return true
end
function QW:OpenNewNPCDialogue()
  local f=self.npcDialogueCreator; if not f then return false end
  f.dialogueID:SetText(""); f.npcID:SetText(""); f.npcName:SetText(""); f.dialogueTitle:SetText(""); f.dialogueText:SetText(""); f.questIDs:SetText(""); f.shareTarget:SetText(""); f.deleteArmed=nil; f.deleteButton:SetText("Delete")
  local npcID,npcName=self:GetTargetNPCInfo()
  if npcID then f.npcID:SetText("npc:"..npcID); f.npcName:SetText(npcName) end
  self:RefreshNPCDialogueList(); f:Show(); f:Raise(); f.dialogueTitle:SetFocus(); return true
end
function QW:CreateSetCreator()
  local f=self:NewCreatorWindow("QuestweaverSetCreatorFrame","Create Questweaver Set",600,475); self.setCreator=f
  f.sid=text(f,"Set ID (leave empty for a new set)",18,-62,560)
  f.stitle=text(f,"Set title",18,-108,250); f.sdesc=text(f,"Story description",285,-108,290)
  f.squests=text(f,"Quest chapter IDs, in story order (comma separated)",18,-154,560)
  button(f,"Choose quest chapters",18,-180,160,function() QW:ShowReferencePicker("quest",f.squests,"append") end)
  f.sitems=text(f,"Supporting RP item IDs (comma separated)",18,-220,560)
  button(f,"Choose supporting items",18,-246,170,function() QW:ShowReferencePicker("item",f.sitems,"append") end)
  f.help=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.help:SetPoint("TOPLEFT",18,-282); f.help:SetWidth(550); f.help:SetJustifyH("LEFT"); f.help:SetText("Choose chapters and items from the browser. A Set references their stable IDs without duplicating them, so its chapter order describes your RP story.")
  button(f,"Save Questweaver Set",18,-350,170,function()
    local quests=QW:ParseSetQuestIDs(f.squests:GetText()); local items=QW:ParseItemIDs(f.sitems:GetText())
    if not quests or not items then QW:Status(f,"Use unique, comma-separated quest and item IDs."); return end
    local id,message=QW:SaveSet(f.sid:GetText(),f.stitle:GetText(),f.sdesc:GetText(),quests,items)
    if id then f.sid:SetText(id) end; QW:Status(f,message or ("Saved Questweaver Set: "..id)); QW:RefreshUI()
  end)
  f.status=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.status:SetPoint("TOPLEFT",205,-353); f.status:SetWidth(360); f.status:SetJustifyH("LEFT")
end
function QW:CreateReferencePicker()
  local f=self:NewCreatorWindow("QuestweaverReferencePickerFrame","Choose a Questweaver reference",560,430); self.referencePicker=f; f.entries={}; f.page=1
  f.search=text(f,"Search by item or quest name / ID",18,-58,510); f.search:SetScript("OnTextChanged",function() QW:RefreshReferencePicker(true) end)
  f.caption=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); f.caption:SetPoint("TOPLEFT",18,-85); f.caption:SetWidth(510); f.caption:SetJustifyH("LEFT")
  local i
  for i=1,9 do
    local entry=button(f,"",18,-108-(i-1)*28,510,function(self)
      if not self.referenceID then return end
      if f.onSelect then f.onSelect(self.referenceID)
      elseif f.target then
        local current=f.target:GetText()
        if f.mode=="append" and current~="" then
          local exists=false; for value in string.gmatch(current,"[^,]+") do if value==self.referenceID then exists=true end end
          if not exists then f.target:SetText(current..","..self.referenceID) end
        else f.target:SetText(self.referenceID) end
      end
      f:Hide()
    end)
    entry.referenceID=nil; f.entries[QW.Count(f.entries)+1]=entry
  end
  button(f,"Previous",18,-375,85,function() if f.page>1 then f.page=f.page-1; QW:RefreshReferencePicker() end end)
  button(f,"Next",112,-375,85,function() if f.page<(math.ceil(QW.Count(f.references or {})/QW.Count(f.entries))) then f.page=f.page+1; QW:RefreshReferencePicker() end end)
  f.createItemButton=button(f,"Create new item",210,-375,135,function()
    if f.kind~="item" or not f.onSelect then return end
    QW.itemCreator.onItemCreated=f.onSelect; f:Hide(); QW.itemCreator:Show(); QW.itemCreator:Raise()
  end)
end
function QW:ShowReferencePicker(kind,target,mode,onSelect)
  local f=self.referencePicker; if not f or (not target and not onSelect) then return end
  f.kind=kind; f.target=target; f.mode=mode or "replace"; f.onSelect=onSelect; f.references={}
  local id,value
  if kind=="item" then
    for id,value in pairs(self.db.items) do f.references[self.Count(f.references)+1]={id=id,label=value.name.."  ["..id.."]"} end
  else
    for id,value in pairs(self.db.quests) do f.references[self.Count(f.references)+1]={id=id,label=value.title.."  ["..id.."]"} end
  end
  table.sort(f.references,function(a,b) return a.label<b.label end); f.allReferences=f.references; f.page=1; f.search:SetText(""); self:RefreshReferencePicker(true); f:Show(); f:Raise()
end
function QW:RefreshReferencePicker(resetPage)
  local f=self.referencePicker; if not f then return end
  if resetPage then
    local filtered={}; local query=string.lower(f.search and f.search:GetText() or "")
    for _,entry in ipairs(f.allReferences or f.references or {}) do if query=="" or string.find(string.lower(entry.label),query,1,true) or string.find(string.lower(entry.id),query,1,true) then filtered[#filtered+1]=entry end end
    f.references=filtered; f.page=1
  end
  local start=(f.page-1)*QW.Count(f.entries); local i
  for i=1,QW.Count(f.entries) do
    local entry=f.entries[i]; local reference=f.references[start+i]
    if reference then entry.referenceID=reference.id; entry:SetText(reference.label); entry:Show() else entry.referenceID=nil; entry:Hide() end
  end
  local total=QW.Count(f.references); local pages=math.max(1,math.ceil(total/QW.Count(f.entries)))
  f.caption:SetText((f.kind=="item" and "Choose an RP item" or "Choose an authored quest").." - page "..f.page.." of "..pages..". Click to "..(f.mode=="append" and "add it" or "use it")..".")
  if f.createItemButton then if f.kind=="item" and f.onSelect then f.createItemButton:Show() else f.createItemButton:Hide() end end
end
function QW:CreateIconPicker()
  local f=self:NewCreatorWindow("QuestweaverIconPickerFrame","Choose an item icon",540,425); self.iconPicker=f; f.slots={}; f.page=1
  f.search=text(f,"Search icons",18,-62,400)
  f.search:SetScript("OnTextChanged",function() QW:FilterIconPicker() end)
  button(f,"Clear",426,-65,90,function() f.search:SetText(""); f.search:SetFocus() end)
  local i
  for i=1,48 do
    local slot=CreateFrame("Button",nil,f); slot:SetWidth(42); slot:SetHeight(42); local column=(i-1)%12; local row=math.floor((i-1)/12); slot:SetPoint("TOPLEFT",18+column*42,-104-row*52)
    slot.border=slot:CreateTexture(nil,"BACKGROUND"); slot.border:SetAllPoints(slot); slot.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    slot.icon=slot:CreateTexture(nil,"ARTWORK"); slot.icon:SetPoint("TOPLEFT",slot,"TOPLEFT",4,-4); slot.icon:SetPoint("BOTTOMRIGHT",slot,"BOTTOMRIGHT",-4,4)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    slot:SetScript("OnClick",function(self)
      if not self.iconValue or not f.target then return end
      f.target.iconPath:SetText(tostring(self.iconValue)); QW:UpdateItemIconPreview(f.target); f:Hide()
    end)
    slot:SetScript("OnEnter",function(self) if self.iconValue then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(tostring(self.iconValue)); GameTooltip:Show() end end)
    slot:SetScript("OnLeave",function() GameTooltip:Hide() end)
    f.slots[QW.Count(f.slots)+1]=slot
  end
  button(f,"Previous",18,-345,85,function() if f.page>1 then f.page=f.page-1; QW:RefreshIconPicker() end end)
  button(f,"Next",112,-345,85,function() if f.page<(math.ceil(QW.Count(f.icons or {})/QW.Count(f.slots))) then f.page=f.page+1; QW:RefreshIconPicker() end end)
  f.caption=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.caption:SetPoint("TOPLEFT",215,-348); f.caption:SetWidth(300); f.caption:SetJustifyH("LEFT")
end
function QW:ShowIconPicker(target)
  local f=self.iconPicker; f.target=target; f.allIcons=self:GetIconLibrary(); f.search:SetText(""); self:FilterIconPicker(); f:Show(); f:Raise()
end
function QW:FilterIconPicker()
  local f=self.iconPicker; if not f or not f.allIcons then return end
  local query=string.lower(f.search:GetText() or ""); f.icons={}
  local i
  for i=1,QW.Count(f.allIcons) do
    local icon=f.allIcons[i]
    if query=="" or string.find(string.lower(tostring(icon)),query,1,true) then f.icons[QW.Count(f.icons)+1]=icon end
  end
  f.page=1; self:RefreshIconPicker()
end
function QW:RefreshIconPicker()
  local f=self.iconPicker; local start=(f.page-1)*QW.Count(f.slots)
  local i
  for i=1,QW.Count(f.slots) do
    local slot=f.slots[i]; local icon=f.icons[start+i]
    if icon then slot.iconValue=icon; slot.icon:SetTexture(icon); slot:Show() else slot.iconValue=nil; slot.icon:SetTexture(nil); slot:Hide() end
  end
  local total=QW.Count(f.icons); local pages=math.max(1,math.ceil(total/QW.Count(f.slots)))
  if total==0 then f.caption:SetText("No icons match your search.") else f.caption:SetText("Page "..f.page.." of "..pages.." - "..total.." matching icons") end
end
function QW:CreateTradeOfferSlot(parent,title,x,y)
  local slot=CreateFrame("Button",nil,parent); slot:SetWidth(210); slot:SetHeight(170); slot:SetPoint("TOPLEFT",x,y)
  slot.border=slot:CreateTexture(nil,"BACKGROUND"); slot.border:SetAllPoints(slot); slot.border:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
  slot.title=slot:CreateFontString(nil,"OVERLAY","GameFontHighlight"); slot.title:SetPoint("TOP",0,-10); slot.title:SetText(title)
  slot.icon=slot:CreateTexture(nil,"ARTWORK"); slot.icon:SetWidth(84); slot.icon:SetHeight(84); slot.icon:SetPoint("TOP",0,-35)
  slot.count=slot:CreateFontString(nil,"OVERLAY","NumberFontNormalLarge"); slot.count:SetPoint("BOTTOMRIGHT",slot.icon,"BOTTOMRIGHT",0,2)
  slot.name=slot:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); slot.name:SetPoint("TOP",slot.icon,"BOTTOM",0,-10); slot.name:SetWidth(190)
  slot:SetScript("OnEnter",function(self) if self.item then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.item.name); GameTooltip:AddLine(self.item.description,1,1,1,true); GameTooltip:AddLine("RP quantity: "..self.quantity,.8,.8,.8); GameTooltip:Show() end end)
  slot:SetScript("OnLeave",function() GameTooltip:Hide() end)
  return slot
end
function QW:SetTradeOfferSlot(slot,item,quantity)
  slot.item=item; slot.quantity=quantity
  if item then slot.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"); slot.count:SetText(quantity); slot.name:SetText(item.name) else slot.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); slot.count:SetText(""); slot.name:SetText("Empty") end
end
function QW:CreateTradeWindow()
  local f=self:NewCreatorWindow("QuestweaverTradeFrame","Questweaver RP Trade",650,500); self.tradeWindow=f; f.inventorySlots={}
  f.target=text(f,"Trading with (character name)",22,-60,230); f.tradeID=text(f,"Trade ID (load an offer)",355,-60,210)
  button(f,"Load",575,-63,50,function() f.activeTradeID=f.tradeID:GetText(); QW:RefreshTradeWindow() end)
  f.yourSlot=self:CreateTradeOfferSlot(f,"Your offer",45,-110); f.theirSlot=self:CreateTradeOfferSlot(f,"Their offer",390,-110)
  f.arrow=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); f.arrow:SetPoint("TOP",0,-175); f.arrow:SetText("<--->")
  f.selection=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.selection:SetPoint("TOPLEFT",22,-305); f.selection:SetWidth(590); f.selection:SetJustifyH("LEFT"); f.selection:SetText("Select an item below, then set quantity and offer it.")
  f.quantity=text(f,"Offer quantity",22,-345,70); f.quantity:SetText("1")
  button(f,"Offer / update",105,-348,120,function()
    if not f.selectedItem then QW:Status(f,"Select an item from your RP inventory first."); return end
    local trade=QW:GetTradeWindowTrade()
    local ok,message
    if trade and not trade.incoming and trade.state=="offered" then
      ok,message=QW:UpdateTrade(trade.id,f.selectedItem.id,f.quantity:GetText()); if ok then f.activeTradeID=trade.id end
    else
      local id; id,message=QW:StartTrade(f.target:GetText(),f.selectedItem.id,f.quantity:GetText()); ok=id~=nil; if ok then f.activeTradeID=id; f.tradeID:SetText(id) end
    end
    QW:Status(f,ok and "Offer sent. Both players must confirm." or message); QW:RefreshTradeWindow()
  end)
  button(f,"Confirm",240,-348,85,function()
    local trade=QW:GetTradeWindowTrade(); local ok,message
    if trade then ok,message=QW:ConfirmTrade(trade.id) else ok,message=false,"Load a trade first." end
    QW:Status(f,message or (ok and "Confirmation sent.")); QW:RefreshTradeWindow()
  end)
  button(f,"Cancel",335,-348,75,function() local trade=QW:GetTradeWindowTrade(); local ok=trade and QW:CancelTrade(trade.id); QW:Status(f,ok and "Trade cancelled." or "Committed or completed trades cannot be cancelled."); QW:RefreshTradeWindow() end)
  button(f,"Resend",420,-348,75,function() local trade=QW:GetTradeWindowTrade(); local ok=trade and QW:ResendTrade(trade.id); QW:Status(f,ok and "Commit resent." or "Only an unresolved outgoing commit can be resent.") end)
  f.status=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); f.status:SetPoint("TOPLEFT",22,-385); f.status:SetWidth(590); f.status:SetJustifyH("LEFT")
  f.inventoryLabel=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); f.inventoryLabel:SetPoint("TOPLEFT",22,-415); f.inventoryLabel:SetText("Your RP inventory (click an item to add it to your offer)")
  local i
  for i=1,10 do
    local slot=CreateFrame("Button",nil,f); slot:SetWidth(46); slot:SetHeight(46); slot:SetPoint("TOPLEFT",22+(i-1)*56,-438)
    slot.border=slot:CreateTexture(nil,"BACKGROUND"); slot.border:SetAllPoints(slot); slot.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    slot.icon=slot:CreateTexture(nil,"ARTWORK"); slot.icon:SetPoint("TOPLEFT",slot,"TOPLEFT",4,-4); slot.icon:SetPoint("BOTTOMRIGHT",slot,"BOTTOMRIGHT",-4,4)
    slot.count=slot:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall"); slot.count:SetPoint("BOTTOMRIGHT",slot,"BOTTOMRIGHT",-3,3)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    slot:SetScript("OnEnter",function(self) if self.item then GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.item.name); GameTooltip:AddLine(self.item.description,1,1,1,true); GameTooltip:AddLine("Available: "..self.quantity,.8,.8,.8); GameTooltip:Show() end end)
    slot:SetScript("OnLeave",function() GameTooltip:Hide() end)
    slot:SetScript("OnClick",function(self) if self.item then f.selectedItem=self.item; f.quantity:SetText("1"); QW:Status(f,"Selected "..self.item.name.."."); QW:RefreshTradeWindow() end end)
    f.inventorySlots[QW.Count(f.inventorySlots)+1]=slot
  end
end
function QW:GetTradeWindowTrade()
  local f=self.tradeWindow; if not f then return nil end
  if f.activeTradeID and self.db.trades[f.activeTradeID] then return self.db.trades[f.activeTradeID] end
  local id=f.tradeID:GetText(); if id~="" and self.db.trades[id] then f.activeTradeID=id; return self.db.trades[id] end
  local id,trade; for id,trade in pairs(self.db.trades) do if trade.state=="offered" or trade.state=="committed" or trade.state=="unresolved" then f.activeTradeID=id; return trade end end
  return nil
end
function QW:RefreshTradeWindow()
  local f=self.tradeWindow; if not f then return end
  local trade=self:GetTradeWindowTrade(); local ours,theirs
  if trade then
    f.tradeID:SetText(trade.id); f.target:SetText(trade.target)
    if trade.incoming then theirs=trade else ours=trade end
  end
  local function firstOffer(current)
    if not current or not current.offer or not current.offer[1] then return nil,nil end
    local offered=current.offer[1]; local defs=current.incoming and current.definitions or self.db.items
    return defs and defs[offered.id],offered.count
  end
  local item,count=firstOffer(ours); self:SetTradeOfferSlot(f.yourSlot,item,count)
  item,count=firstOffer(theirs); self:SetTradeOfferSlot(f.theirSlot,item,count)
  if trade then
    f.selection:SetText("Trade "..trade.id.." - "..trade.state..". Your confirmation: "..(trade.localConfirmed and "yes" or "no").."; other player's confirmation: "..(trade.remoteConfirmed and "yes" or "no")..".")
  elseif f.selectedItem then f.selection:SetText("Selected: "..f.selectedItem.name..". Enter a character name and quantity, then offer it.") else f.selection:SetText("Select an item below, then set quantity and offer it.") end
  local entries={}; for id,quantity in pairs(self.db.inventory) do local invItem=self.db.items[id]; if invItem then entries[self.Count(entries)+1]={item=invItem,quantity=quantity} end end; table.sort(entries,function(a,b) return a.item.name<b.item.name end)
  local i; for i=1,self.Count(f.inventorySlots) do local slot=f.inventorySlots[i]; local entry=entries[i]; if entry then slot.item=entry.item; slot.quantity=entry.quantity; slot.icon:SetTexture(entry.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"); slot.count:SetText(entry.quantity); slot:Show() else slot.item=nil; slot.quantity=nil; slot.icon:SetTexture(nil); slot.count:SetText(""); slot:Hide() end end
end
function QW:ShowTradeWindow(tradeID)
  local f=self.tradeWindow; if tradeID then f.activeTradeID=tradeID end; f:Show(); f:Raise(); self:RefreshTradeWindow()
end
function QW:RefreshUI()
  self:RefreshQuickAccessButton()
  self:RefreshQuestQuickAccessButton()
  self:RefreshInteractQuickAccessButton()
  self:RefreshTokenAccessButton()
  self:RefreshQuestTracker()
  if not self.ui or not self.ui:IsShown() then return end
  local inv=self.ui.pages[1]; self:RefreshInventoryGrid(inv); local lines={"TRADES (keep committed/unresolved trades visible until acknowledged):"}; for id,t in pairs(self.db.trades) do lines[QW.Count(lines)+1]=id.." - "..t.state.." - "..t.target end; inv.tradeList:SetText(table.concat(lines,"\n"))
  self:RefreshMakerInventory()
  self:RefreshQuestJournal()
  self:RefreshSetPage()
  if self.tradeWindow and self.tradeWindow:IsShown() then self:RefreshTradeWindow() end
end
