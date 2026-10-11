-- Minimal non-client regression tests. Run: lua tests/core_logic.lua
local now = 1000
local chatMessages={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) chatMessages[table.getn(chatMessages)+1]=message end}; UIParent={}; SlashCmdList={}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end,GetScript=function() return function() end end} end
local targetName
local playerGUID="Player-0000-00000001"
function UnitName(unit) if unit=="target" then return targetName end; return "Tester", "" end
local targetGUID
function UnitGUID(unit) if unit=="target" then return targetGUID elseif unit=="player" then return playerGUID end end
local currentZone, playerX, playerY="Stormwind City",.52,.64
function GetRealZoneText() return currentZone end
local setMapCalls=0
function SetMapToCurrentZone() setMapCalls=setMapCalls+1; error("must not mutate Blizzard map UI") end
function GetPlayerMapPosition() return playerX,playerY end
function time() return now end
function SendAddonMessage() end
assert(loadfile("Core.lua"))(); assert(loadfile("Protocol.lua"))(); assert(loadfile("Inventory.lua"))(); assert(loadfile("Trade.lua"))(); assert(loadfile("Quest.lua"))(); assert(loadfile("Tracker.lua"))(); assert(loadfile("Sets.lua"))()
QW:InitDB()
assert(QW.db.version==7)
local shownNPC
function QW:ShowNPCInteraction(npcID,npcName) shownNPC={id=npcID,name=npcName} end
local function optionByID(list,id,kind) for _,option in ipairs(list or {}) do if option.id==id and option.kind==kind then return option end end end
local defaultToken=QW:GetDefaultTokenID(); assert(defaultToken=="item:questweaver:rp-token" and QW.db.items[defaultToken] and QW.db.items[defaultToken].maxStack==999 and not QW:HasItem(defaultToken,1))
assert(QW:GetRPTokenCount()==0 and QW:AddItem(QW.db.items[defaultToken],5) and QW:GetRPTokenCount()==5)
assert(QW:TakeItem(defaultToken,2) and QW:GetRPTokenCount()==3 and QW:TakeItem(defaultToken,3) and QW:GetRPTokenCount()==0)
local item=QW:CreateItem("Letter","Interface\\Icons\\INV_Letter_15","Test item",2,"misc"); assert(item and not QW:HasItem(item,1) and QW.db.items[item].category=="misc")
assert(QW:GrantMakerItem(item,2) and QW:HasItem(item,2)); assert(not QW:GrantMakerItem(item,3))
local miscSatchel=QW:GetRPInventoryItems("misc"); local allSatchel=QW:GetRPInventoryItems("all"); local sawItem=false
for _,entry in ipairs(miscSatchel) do if entry.item.id==item then sawItem=true; assert(entry.quantity==2) end end
assert(sawItem and #allSatchel>=#miscSatchel and #QW:GetRPInventoryItems("not-a-category")==0 and QW.db.inventory[item]==2)
assert(not QW:DeleteMakerItem(item) and not QW:DeleteMakerItem(defaultToken))
local itemLink,itemLinkError=QW:BuildItemHyperlink(item); assert(itemLink and string.find(itemLink,"|Hquestweaver:item:",1,true),itemLinkError)
local linkData=string.match(itemLink,"|H(questweaver:item:[^|]+)|h"); local linkedItem=QW:ParseChatItemLink(linkData)
assert(linkedItem and linkedItem.id==item and linkedItem.name=="Letter" and linkedItem.description=="Test item")
assert(not QW:BuildItemHyperlink("item:missing") and not QW:ParseChatItemLink("questweaver:item:malformed"))
assert(QW:Escape("a|b%") == "a%7Cb%25"); assert(QW:Unescape("a%7Cb%25") == "a|b%")
assert(not QW:CreateItem("", "x", "x", 1)); assert(QW:TakeItem(item,1)); assert(QW:HasItem(item,1))
local def=QW.db.items[item]; assert(QW:AddItem(def,1)); assert(QW:HasItem(item,2))
assert(QW:RemoveRPItem(item,1) and QW.db.inventory[item]==1)
assert(not QW:RemoveRPItem(item,1.5) and not QW:RemoveRPItem(item,2) and QW.db.inventory[item]==1)
local encoded=QW:SerializeItem({id="item:punct",name="A;B~C",icon="Interface\\Icons\\INV_Letter_15",description="A | B % C",maxStack=1,category="food"})
local decoded=QW:ParseItem(encoded); assert(decoded and decoded.name=="A;B~C" and decoded.description=="A | B % C" and decoded.category=="food")
assert(QW:ParseItem("old~Old%20Item~Interface%5CIcons%5CINV_Letter_15~Legacy~5").category=="misc")
local lootRules=assert(QW:ParseLootChances("1984~25;2079~100")); assert(#lootRules==2 and lootRules[1].npcID==1984 and lootRules[1].chance==25)
assert(not QW:ParseLootChances("1984~101") and not QW:ParseLootChances("1984~25;1984~50") and not QW:ParseLootChances("npc:1984~25"))
local chanceItem=assert(QW:CreateItem("Boar Drop","Interface\\Icons\\INV_Misc_Note_01","A chance drop.",20,"misc",lootRules))
local chanceDef=QW.db.items[chanceItem]; local chanceRoundtrip=QW:ParseItem(QW:SerializeItem(chanceDef))
assert(chanceRoundtrip and #chanceRoundtrip.lootChances==2 and chanceRoundtrip.lootChances[2].npcID==2079 and chanceRoundtrip.lootChances[2].chance==100)
local chanceBefore=QW.db.inventory[chanceItem] or 0
assert(QW:RollItemDrops(1984,"drop-guid-success",1)==1 and QW.db.inventory[chanceItem]==chanceBefore+1)
assert(QW:RollItemDrops(1984,"drop-guid-success",1)==0 and QW.db.inventory[chanceItem]==chanceBefore+1) -- duplicate kill event cannot duplicate loot
assert(QW:RollItemDrops(1984,"drop-guid-fail",100)==0 and QW.db.inventory[chanceItem]==chanceBefore+1)
assert(QW:ValidateIcon(134400)); assert(QW:NormalizeIcon("134400")==134400)
local rewardItem=QW:CreateItem("Test reward","Interface\\Icons\\INV_Misc_Coin_01","Quest-only reward.",1)
local q=QW:CreateQuest("Q","D",{{type="possess",itemID=item,count=1,text="Hold it"}},rewardItem,1); assert(q)
assert(QW.db.items[item].category=="quest" and QW:GrantMakerItem(item,1) and QW.db.items[rewardItem].category=="reward" and QW:GrantMakerItem(rewardItem,1))
assert(QW:TakeItem(item,1) and QW:TakeItem(rewardItem,1))
QW.DEV_MAKER_SATCHEL_GRANTS=false
assert(not QW:GrantMakerItem(item,1) and not QW:GrantMakerItem(rewardItem,1))
QW.DEV_MAKER_SATCHEL_GRANTS=true
local set=QW:SaveSet(nil,"Letter Story","A small two-part story.",{q},{item}); assert(set and QW.db.sets[set] and QW.db.sets[set].questIDs[1]==q and QW.db.sets[set].itemIDs[1]==item)
assert(not QW:ParseSetQuestIDs(q..","..q)); assert(QW:SaveSet(set,"Letter Story","Updated story.",{q},{item}))
assert(not QW:DeleteQuest(q)); assert(QW:DeleteSet(set) and not QW.db.sets[set] and QW.db.quests[q]); QW.db.questRuns[q]={id=q,state="active"}; assert(not QW:DeleteQuest(q)); QW.db.questRuns[q]=nil
assert(QW:DeleteQuest(q) and not QW.db.quests[q]); assert(QW:DeleteMakerItem(rewardItem))
-- A quest may award several different items, each with an independent count.
local multiRewardOne=assert(QW:CreateItem("Reward One","Interface\\Icons\\INV_Misc_Coin_01","First multi reward.",10))
local multiRewardTwo=assert(QW:CreateItem("Reward Two","Interface\\Icons\\INV_Misc_Coin_02","Second multi reward.",10))
local multiRewardQuest=assert(QW:CreateQuest("Multiple rewards","D",{{type="manual",text="Confirm."}},{{id=multiRewardOne,count=2},{id=multiRewardTwo,count=3}}))
assert(#QW.db.quests[multiRewardQuest].rewards==2 and QW.db.quests[multiRewardQuest].rewards[2].count==3)
assert(QW:AssignQuestToCurrentPlayer(multiRewardQuest)); assert(QW:CompleteQuest(QW.db.questRuns[multiRewardQuest]))
assert(QW.db.inventory[multiRewardOne]==2 and QW.db.inventory[multiRewardTwo]==3)
QW.outbox={}; assert(QW:ShareQuest(multiRewardQuest,"Other"))
local multiRewardChunks={}; for _,entry in ipairs(QW.outbox) do local _,part,_,payload=string.match(entry.wire,"^([^,]+),(%d+),(%d+),(.+)$"); multiRewardChunks[tonumber(part)]=payload end
local kind,multiRewardFields=QW:Unpack(table.concat(multiRewardChunks)); assert(kind=="QUEST_SHARE" and multiRewardFields[20] and string.find(multiRewardFields[20],multiRewardTwo,1,true))
QW.db.questRuns[multiRewardQuest]=nil; QW:ReceiveQuest(multiRewardFields,"Other"); assert(#QW.db.questRuns[multiRewardQuest].rewards==2 and QW.db.questRuns[multiRewardQuest].rewards[2].count==3)
local disposable=QW:CreateItem("Disposable","Interface\\Icons\\INV_Misc_Note_01","Unused maker definition.",1,"misc")
assert(disposable and not QW:HasItem(disposable,1) and QW:DeleteMakerItem(disposable) and not QW.db.items[disposable])
QW.db.questRuns.run={id="run",owner="Other",steps={{type="possess",itemID=item,count=1,text="Hold"}},reward=def,rewardCount=1,index=1,state="active"}
assert(QW:AdvanceQuest("run")); assert(QW.db.questRuns.run.state=="complete")
local packet=QW:Pack("TRADE_ACK",{"trade:one",1}); local kind,fields=QW:Unpack(packet); assert(kind=="TRADE_ACK" and fields[3]=="trade:one")
-- Replaying an accepted commit must not add a second item.
QW.db.trades.inbound={id="inbound",incoming=true,target="Other",revision=1,localConfirmed=true,remoteConfirmed=true,state="offered",offer={{id=item,count=1}},definitions={[item]=def}}
local before=QW.db.inventory[item]
local commit={"1","TRADE_COMMIT","inbound","1",item..",1"}
QW:ReceiveTradeCommit(commit,"Other"); QW:ReceiveTradeCommit(commit,"Other")
assert(QW.db.inventory[item]==before+1 and QW.db.trades.inbound.state=="complete")
-- Delivery acceptance is likewise idempotent and returns an acknowledgement safely.
local deliveryQuest=QW:CreateQuest("Return","D",{{type="deliver",itemID=item,count=1,mobName="npc:1984",text="Return it"}},item,1); assert(deliveryQuest)
local deliveryBefore=QW.db.inventory[item]
local delivery={"1","QUEST_DELIVERY","delivery:1",deliveryQuest,"1",item,"1",QW:SerializeItem(def)}
QW:ReceiveDelivery(delivery,"Other"); QW:ReceiveDelivery(delivery,"Other")
assert(QW.db.inventory[item]==deliveryBefore+1)
-- Places and an assigned quest-item definition survive creation; targeted loot grants once.
local loot=QW:CreateItem("Librarian's Seal","Interface\\Icons\\INV_Misc_Note_01","Found on the librarian.",1)
local places=QW:ParsePlaces("library~Stormwind City~52~64~3~At the library")
assert(QW:AtPlace(places[1]) and setMapCalls==0) -- Location validation never invokes Blizzard's protected map UI.
local lootQuest=QW:CreateQuest("Library Search","D",{{type="loot",itemID=loot,count=1,placeID="library",mobName="Dusty Librarian",text="Search the librarian."}},item,1,places,{loot}); assert(lootQuest)
local lootBefore=QW.db.inventory[loot] or 0
QW.db.questRuns.lootRun={id="lootRun",owner="Other",steps={{type="loot",itemID=loot,count=1,placeID="library",mobName="Dusty Librarian",text="Search"}},places=places,placeByID={library=places[1]},itemDefinitions={[loot]=QW.db.items[loot]},reward=def,rewardCount=1,index=1,state="active"}
currentZone="Elwynn Forest"; assert(not QW:AdvanceQuest("lootRun")); currentZone="Stormwind City"
targetName="Dusty Librarian"; assert(QW:AdvanceQuest("lootRun")); assert(QW.db.inventory[loot]==lootBefore+1)
-- A collect objective awards its defined item at the location without requiring a target.
local book=QW:CreateItem("Library Book","Interface\\Icons\\INV_Misc_Book_09","Taken from the shelf.",1)
local bookBefore=QW.db.inventory[book] or 0
QW.db.questRuns.collectRun={id="collectRun",owner="Other",steps={{type="collect",itemID=book,count=1,placeID="library",mobName="",text="Take the book"}},places=places,placeByID={library=places[1]},itemDefinitions={[book]=QW.db.items[book]},reward=def,rewardCount=1,index=1,state="active"}
assert(QW:AdvanceQuest("collectRun")); assert(QW.db.inventory[book]==bookBefore+1)
local scroll=QW:CreateItem("Library Scroll","Interface\\Icons\\INV_Misc_Note_01","A second library find.",5)
local multiQuest=QW:CreateQuest("Gather two things","Collect both library finds.",{{type="collect",itemIDs={book,scroll},count=2,placeID="library",text="Collect both items."}},defaultToken,1,places,{book,scroll})
assert(multiQuest and #QW.db.quests[multiQuest].steps[1].itemIDs==2)
local multiStepWire=QW:Escape("collect").."~"..QW:Escape(book).."~2~"..QW:Escape("library").."~~"..QW:Escape("Collect both").."~1~"..QW:Escape(book..","..scroll)
local multiParsed=QW:ParseSteps(multiStepWire); assert(multiParsed and #multiParsed[1].itemIDs==2 and multiParsed[1].itemIDs[2]==scroll)
local multiBookBefore=QW.db.inventory[book] or 0; local multiScrollBefore=QW.db.inventory[scroll] or 0
assert(QW:AssignQuestToCurrentPlayer(multiQuest)); assert(QW:AdvanceQuest(multiQuest))
assert(QW.db.inventory[book]==multiBookBefore+2 and QW.db.inventory[scroll]==multiScrollBefore+2 and QW.db.questRuns[multiQuest].state=="complete")
local deliveryMulti=QW:CreateQuest("Deliver both","Return both library finds.",{{type="deliver",itemIDs={book,scroll},count=1,mobName="npc:1984",text="Return both items."}},defaultToken,1,nil,{book,scroll})
assert(deliveryMulti and QW:AssignQuestToCurrentPlayer(deliveryMulti))
local deliverRun=QW.db.questRuns[deliveryMulti]; local returnBefore=QW.db.inventory[book]
local beforeDeliveryProgress=QW:GetObjectiveItemProgress(deliverRun,deliverRun.steps[1],1); assert(beforeDeliveryProgress[1].have==returnBefore and beforeDeliveryProgress[1].required==1 and beforeDeliveryProgress[1].delivered==0)
local deliveryTracker; for _,entry in ipairs(QW:GetQuestTrackerEntries()) do if entry.id==deliveryMulti then deliveryTracker=entry end end
assert(deliveryTracker and string.find(deliveryTracker.objective,QW.db.items[book].name.." "..returnBefore.."/1",1,true))
targetGUID="Creature-0-1-0-47-1984-0000000003"; targetName="Delivery NPC"
local deliveryOptions=QW:GetNPCInteractionOptions(1984)
assert(optionByID(deliveryOptions.progress,deliveryMulti,"delivery"))
assert(QW:PerformNPCInteraction(optionByID(deliveryOptions.progress,deliveryMulti,"delivery"),1984) and not deliverRun.pendingDelivery and deliverRun.state=="complete" and QW.db.inventory[book]==returnBefore-1)
assert(QW.db.inventory[scroll]==multiScrollBefore+1)
assert(not QW:CreateQuest("No NPC delivery","D",{{type="deliver",itemID=book,count=1,text="This must fail."}},defaultToken,1,nil,{book}))
-- An upgrade returns an unacknowledged old author-transfer to the recipient,
-- preventing that delivery from permanently blocking the quest.
local recoveryBefore=QW.db.inventory[item] or 0
assert(QW:AddItem(def,5) and QW:TakeItem(item,5))
QW.db.questRuns.oldDelivery={id="oldDelivery",title="Old delivery",state="active",steps={{type="deliver",itemID=item,itemIDs={item},count=5,mobName="npc:1984",npcID=1984,text="Hand these over."}},itemDefinitions={[item]=def},pendingDelivery={id="delivery:old",index=1,itemID=item,count=5,definition=def}}
QW:MigrateDeliveriesToNPCHandoffs()
assert(QW.db.questRuns.oldDelivery.deliveryMode=="npc" and not QW.db.questRuns.oldDelivery.pendingDelivery and QW.db.inventory[item]==recoveryBefore+5)
QW.db.questRuns.oldDelivery=nil
-- Automatic kill objectives count exact player kill names and finish without approval.
local killSteps=QW:ParseSteps("kill~~5~~Junger Disteleber~Defeat five boars")
assert(killSteps and killSteps[1].type=="kill" and killSteps[1].count==5 and killSteps[1].mobName=="Junger Disteleber")
assert(not QW:ParseSteps("kill~~~~Junger Disteleber~Missing count"))
QW.db.questRuns.killRun={id="killRun",owner="Other",steps=killSteps,reward=def,rewardCount=1,index=1,state="active"}
for i=1,4 do assert(QW:RecordKill("Junger Disteleber")) end
assert(QW.db.questRuns.killRun.killProgress[1]==4 and QW.db.questRuns.killRun.state=="active")
assert(string.find(chatMessages[table.getn(chatMessages)],"Kills: 4 / 5",1,true))
assert(QW:RecordKill("Junger Disteleber") and QW.db.questRuns.killRun.state=="complete")
local finishedSteps,totalSteps=QW:GetQuestStepProgress(QW.db.questRuns.killRun); assert(finishedSteps==1 and totalSteps==1) -- Journal must not show 2/1 after the final objective.
QW.db.questRuns.trackerTest={id="trackerTest",title="Tracker Kill",state="active",index=1,steps={{type="kill",count=5,text="Defeat boars"}},killProgress={[1]=3}}
local trackerEntries=QW:GetQuestTrackerEntries(); local trackerEntry
for i=1,QW.Count(trackerEntries) do if trackerEntries[i].id=="trackerTest" then trackerEntry=trackerEntries[i] end end
assert(trackerEntry and string.find(trackerEntry.objective,"3/5",1,true)); QW.db.questRuns.trackerTest.state="complete"
assert(not QW:RecordKill("Different Boar"))
local npcKillSteps=QW:ParseSteps("kill~~1~~npc:1984~Defeat one boar")
assert(npcKillSteps and npcKillSteps[1].npcID==1984)
targetName="Localized Boar"; targetGUID="Creature-0-1-0-47-1984-0000000001"
local targetNPCID,targetNPCName=QW:GetTargetNPCInfo(); assert(targetNPCID==1984 and targetNPCName=="Localized Boar")
local rangeAnswer=true
CheckInteractDistance=function(unit,index) assert(unit=="target" and index==3); return rangeAnswer end
assert(QW:IsNPCInteractionInRange(1984,"Creature-0-1-0-47-1984-0000000001"))
rangeAnswer=false; assert(QW:IsNPCInteractionInRange(1984,"Creature-0-1-0-47-1984-0000000001")==false)
assert(QW:IsNPCInteractionInRange(2079,"Creature-0-1-0-47-1984-0000000001")==false)
local described,description=QW:DescribeTargetNPC(); assert(described and string.find(description,"ID: 1984",1,true))
assert(QW:NPCIDFromGUID("0xF1300007C0000001")==1984) -- Forever/1.12 creature GUID format
-- Legacy localized kill chat can use a target GUID or an NPC name learned via /qw npcid.
local legacyRun={id="legacyRun",owner="Other",steps=npcKillSteps,reward=def,rewardCount=1,index=1,state="active"}
QW.db.questRuns.legacyRun=legacyRun; YOU_HAVE_SLAIN="You have slain %s."; QW.lastCombatKill=nil
targetName="Localized Boar"; targetGUID="Creature-0-1-0-47-1984-0000000001"
assert(QW:HandleLegacyKillMessage("You have slain Localized Boar.") and legacyRun.state=="complete")
local legacyMapped=QW:ParseSteps("kill~~1~~npc:1984~Mapped legacy kill")
QW.db.questRuns.legacyMapped={id="legacyMapped",owner="Other",steps=legacyMapped,reward=def,rewardCount=1,index=1,state="active"}
targetName="Localized Boar"; targetGUID=nil; QW.lastCombatKill=nil
assert(QW:HandleLegacyKillMessage("You have slain Localized Boar.") and QW.db.questRuns.legacyMapped.state=="complete")
local germanBoar=QW:ParseSteps("kill~~1~~npc:1984~German legacy kill")
QW.db.questRuns.germanBoar={id="germanBoar",owner="Other",steps=germanBoar,reward=def,rewardCount=1,index=1,state="active"}
targetName=nil; targetGUID=nil; QW.lastCombatKill=nil
assert(QW:HandleLegacyKillMessage("You have slain Junger Disteleber.") and QW.db.questRuns.germanBoar.state=="complete")
local germanCombat=QW:ParseSteps("kill~~1~~npc:1984~German combat-log kill")
QW.db.questRuns.germanCombat={id="germanCombat",owner="Other",steps=germanCombat,reward=def,rewardCount=1,index=1,state="active"}
targetName="Junger Disteleber"; targetGUID="Creature-0-1-0-47-1984-0000000003"; QW.lastCombatKill=nil
assert(QW:HandleLegacyKillMessage("Euer Charakter besiegt Junger Disteleber") and QW.db.questRuns.germanCombat.state=="complete")
C_CreatureInfo={GetCreatureID=function(guid) return guid=="forever-creature-guid" and 1984 or nil end}
assert(QW:NPCIDFromGUID("forever-creature-guid")==1984) -- Forever's preferred creature-ID API
C_CreatureInfo=nil
targetGUID=nil; targetName="Konservator Ilthalaine"; assert(QW:GetTargetNPCInfo()==2079) -- No-UnitGUID fallback for the built-in demo
targetGUID="Creature-0-1-0-47-1984-0000000001"; targetName="Localized Boar"
QW.db.questRuns.npcKillRun={id="npcKillRun",owner="Other",steps=npcKillSteps,reward=def,rewardCount=1,index=1,state="active"}
assert(QW:RecordKill("Any localized name","Creature-0-1-0-47-1984-0000000001") and QW.db.questRuns.npcKillRun.state=="complete")
local eventKill=QW:ParseSteps("kill~~1~~npc:1984~Party kill event")
QW.db.questRuns.eventKill={id="eventKill",owner="Other",steps=eventKill,reward=def,rewardCount=1,index=1,state="active"}
targetGUID="Creature-0-1-0-47-1984-0000000002"; targetName="Localized Boar"
assert(QW:HandlePartyKill(playerGUID,targetGUID) and QW.db.questRuns.eventKill.state=="complete")
-- A reward turn-in holds the reward until the selected NPC is interacted with.
local turnInQuest=QW:CreateQuest("Report to the Captain","Return for your reward.",{{type="dialogue",text="The task is finished."}},item,1,nil,nil,nil,nil,nil,nil,nil,"npc:1984")
assert(turnInQuest and QW:AssignQuestToCurrentPlayer(turnInQuest) and QW:AdvanceQuest(turnInQuest))
assert(QW.db.questRuns[turnInQuest].state=="ready_to_turn_in")
targetName="Captain"; assert(QW:InteractWithTarget() and shownNPC.id==1984 and QW.db.questRuns[turnInQuest].state=="ready_to_turn_in")
local turnInOptions=QW:GetNPCInteractionOptions(1984); assert(QW:PerformNPCInteraction(optionByID(turnInOptions.ready,turnInQuest,"turnin"),1984) and QW.db.questRuns[turnInQuest].state=="complete")
-- NPC turn-ins are surfaced as Active interactions; completed quests are retained
-- in history and can be restarted from the Repeat category.
local repeatQuest=QW:CreateQuest("Repeatable errand","A short errand.",{{type="dialogue",text="Report back."}},item,1,nil,nil,nil,nil,"npc:1984",nil,"Take this errand.",nil,nil,true,12,4)
assert(repeatQuest and QW:AssignQuestToCurrentPlayer(repeatQuest) and QW:AdvanceQuest(repeatQuest))
local repeatGroups=QW:GetNPCInteractionOptions(1984)
assert(optionByID(repeatGroups.done,repeatQuest,"done") and optionByID(repeatGroups.repeatQuests,repeatQuest,"repeat"))
assert(QW:PerformNPCInteraction(optionByID(repeatGroups.repeatQuests,repeatQuest,"repeat"),1984))
assert(QW.db.quests[repeatQuest].repeatable and QW.db.quests[repeatQuest].suggestedLevel==12 and QW.db.quests[repeatQuest].suggestedPlayers==4 and QW.db.questRuns[repeatQuest].repeatable and QW.db.questRuns[repeatQuest].suggestedLevel==12 and QW.db.questRuns[repeatQuest].suggestedPlayers==4 and QW.db.questRuns[repeatQuest].state=="active" and QW.db.questRuns[repeatQuest].index==1 and QW.Count(QW.db.questHistory)>=1)
local onceQuest=QW:CreateQuest("One-time errand","This one should stay completed.",{{type="dialogue",text="Report back once."}},item,1,nil,nil,nil,nil,"npc:1984",nil,"A one-time task.")
assert(onceQuest and QW:AssignQuestToCurrentPlayer(onceQuest) and QW:AdvanceQuest(onceQuest))
local onceGroups=QW:GetNPCInteractionOptions(1984)
assert(optionByID(onceGroups.done,onceQuest,"done") and not optionByID(onceGroups.repeatQuests,onceQuest,"repeat"))
assert(not QW:PerformNPCInteraction({kind="repeat",id=onceQuest},1984) and QW.db.questRuns[onceQuest].state=="complete")
local wireReward=QW:SerializeItem(QW.db.items[item])
QW:ReceiveQuest({"6","QUEST_SHARE","repeat-wire-test","1","Shared repeat test","Shared quest.","dialogue~~~~~Speak.",wireReward,"1","","","","","","1","16","3"},"Remote")
assert(QW.db.questRuns["repeat-wire-test"] and QW.db.questRuns["repeat-wire-test"].repeatable==true and QW.db.questRuns["repeat-wire-test"].suggestedLevel==16 and QW.db.questRuns["repeat-wire-test"].suggestedPlayers==3 and QW.db.questRuns["repeat-wire-test"].steps[1].stepNumber==1)
assert(not QW:CreateQuest("Invalid level","Bad suggestion.",{{type="dialogue",text="Speak."}},item,1,nil,nil,nil,nil,nil,nil,nil,nil,nil,false,"12.5"))
assert(not QW:CreateQuest("Invalid player count","Bad suggestion.",{{type="dialogue",text="Speak."}},item,1,nil,nil,nil,nil,nil,nil,nil,nil,nil,false,nil,"0"))
-- Ordered objectives can mix a combat-log NPC kill, position collection, and an NPC dialogue.
local multiSteps=QW:ParseSteps("kill~~1~~npc:1984~Defeat the boar;collect~"..book.."~1~library~~Take the book;dialogue~~~library~npc:1984~Bring the book to the captain")
assert(multiSteps and QW.Count(multiSteps)==3 and multiSteps[1].npcID==1984 and multiSteps[3].npcID==1984 and multiSteps[1].stepNumber==1 and multiSteps[3].stepNumber==3)
local multiQuest=QW:CreateQuest("Three-part library errand","Defeat, collect, then report.",multiSteps,item,1,places,{book})
assert(multiQuest and QW.Count(QW.db.quests[multiQuest].steps)==3)
local oldQuestVersion=QW.db.quests[multiQuest].version
local updatedQuest=QW:CreateQuest("Three-part library errand: revised","Updated story.",multiSteps,item,1,places,{book},nil,nil,nil,nil,nil,nil,multiQuest)
assert(updatedQuest==multiQuest and QW.db.quests[multiQuest].title=="Three-part library errand: revised" and QW.db.quests[multiQuest].version==oldQuestVersion+1)
assert(not QW:CreateQuest("Stolen edit","Not the owner.",multiSteps,item,1,places,{book},nil,nil,nil,nil,nil,nil,"quest:missing"))
local multiBookBefore=QW.db.inventory[book]
QW.db.questRuns.multiRun={id="multiRun",owner="Other",steps=multiSteps,places=places,placeByID={library=places[1]},itemDefinitions={[book]=QW.db.items[book]},reward=def,rewardCount=1,index=1,state="active"}
assert(QW:RecordKill("Localized Boar","Creature-0-1-0-47-1984-0000000001") and QW.db.questRuns.multiRun.index==2)
assert(QW:AdvanceQuest("multiRun") and QW.db.questRuns.multiRun.index==3 and QW.db.inventory[book]==multiBookBefore+1)
targetGUID="Creature-0-1-0-47-1985-0000000001"; assert(not QW:AdvanceQuest("multiRun"))
targetGUID="Creature-0-1-0-47-1984-0000000001"; assert(QW:AdvanceQuest("multiRun") and QW.db.questRuns.multiRun.state=="complete")
-- Same-numbered objectives run in parallel; a higher number stays locked until all siblings finish.
local parallelSteps={{type="dialogue",text="Question the guard.",stepNumber=1},{type="dialogue",text="Search the desk.",stepNumber=1},{type="dialogue",text="Report to the captain.",stepNumber=2}}
local parallelQuest=QW:CreateQuest("Parallel investigation","Complete both first tasks before reporting.",parallelSteps,item,1)
assert(parallelQuest and QW.db.quests[parallelQuest].steps[1].stepNumber==1 and QW.db.quests[parallelQuest].steps[2].stepNumber==1 and QW.db.quests[parallelQuest].steps[3].stepNumber==2)
assert(QW:AssignQuestToCurrentPlayer(parallelQuest))
local parallelRun=QW.db.questRuns[parallelQuest]
assert(not QW:FinishStep(parallelRun,3) and parallelRun.state=="active")
local parallelCurrent=QW:GetCurrentObjectiveIndices(parallelRun); assert(QW.Count(parallelCurrent)==2 and parallelCurrent[1]==1 and parallelCurrent[2]==2)
assert(QW:FinishStep(parallelRun,2) and parallelRun.completedObjectives[2] and parallelRun.index==1)
parallelCurrent=QW:GetCurrentObjectiveIndices(parallelRun); assert(QW.Count(parallelCurrent)==1 and parallelCurrent[1]==1)
assert(QW:FinishStep(parallelRun,1) and parallelRun.completedObjectives[1] and parallelRun.index==3)
parallelCurrent=QW:GetCurrentObjectiveIndices(parallelRun); assert(QW.Count(parallelCurrent)==1 and parallelCurrent[1]==3)
assert(QW:AdvanceQuest(parallelQuest) and parallelRun.state=="complete")
assert(not QW:ParseSteps("dialogue~~~~~Invalid step~0") and not QW:ParseSteps("dialogue~~~~~Invalid step~1.5"))
-- A later quest can point to its predecessor; completion activates it exactly once.
local chainParent=QW:CreateQuest("Chain: first","Finish this first.",{{type="dialogue",text="Begin the story."}},item,1)
local chainChild=QW:CreateQuest("Chain: second","This is unlocked by the first quest.",{{type="dialogue",text="Continue the story."}},item,1,nil,nil,nil,chainParent)
assert(chainParent and chainChild and QW.db.quests[chainParent].followUpQuestID==chainChild and QW.db.quests[chainChild].predecessorQuestID==chainParent)
local queuedBefore=QW.Count(QW.outbox); assert(QW:ShareQuest(chainParent,"Other") and QW.Count(QW.outbox)>queuedBefore)
assert(QW:AssignQuestToCurrentPlayer(chainParent)); assert(QW:AdvanceQuest(chainParent))
assert(QW.db.questRuns[chainParent].state=="complete" and QW.db.questRuns[chainChild] and QW.db.questRuns[chainChild].state=="active")
assert(QW:CompleteQuest(QW.db.questRuns[chainParent]) and QW.db.questRuns[chainChild].state=="active")
-- A shared follow-up remains deferred until its received predecessor completes.
local remoteParent="quest:remote:parent"; local remoteChild="quest:remote:child"; local remoteDefinition=QW:SerializeItem(def)
QW:ReceiveQuest({"2","QUEST_SHARE",remoteParent,"6","Remote part one","First part.","dialogue~~~~~Begin.",remoteDefinition,"1","",remoteDefinition,remoteChild},"Remote")
assert(QW.db.questRuns[remoteParent] and not QW.db.questRuns[remoteChild])
assert(QW:AdvanceQuest(remoteParent) and QW.db.questRuns[remoteParent].state=="complete" and not QW.db.questRuns[remoteChild])
QW:HandleMessage("QUEST_FOLLOWUP",{"2","QUEST_FOLLOWUP",remoteParent,remoteChild,"6","Remote part two","Second part.","dialogue~~~~~Continue.",remoteDefinition,"1","",remoteDefinition,""},"Remote")
assert(not QW.db.followUpDefinitions[remoteParent] and QW.db.questRuns[remoteChild] and QW.db.questRuns[remoteChild].state=="active")
-- NPC quest offers keep custom dialogue deferred until the recipient targets the configured quest giver.
local npcOfferQuest=QW:CreateQuest("Librarian's Request","A librarian needs help.",{{type="dialogue",text="Accept the librarian's request."}},item,1,places,nil,nil,nil,"npc:1984","library","Welcome, traveler. I have a task for you.")
assert(npcOfferQuest and QW.db.quests[npcOfferQuest].giverNPCID==1984)
local offerQueued=QW.Count(QW.outbox); assert(QW:OfferQuest(npcOfferQuest,"Other") and QW.Count(QW.outbox)>offerQueued)
local remoteOffer="quest:remote:librarian"
QW:HandleMessage("QUEST_OFFER",{"2","QUEST_OFFER",remoteOffer,"7","Remote librarian request","A custom NPC offer.","dialogue~~~~~Accept the task.",remoteDefinition,"1","library~Stormwind City~52~64~3~At the library",remoteDefinition,"","npc:1984","library","Welcome, traveler. I have a task for you."},"Remote")
assert(QW.db.questOffers[remoteOffer] and not QW.db.questRuns[remoteOffer])
local offeredGroups=QW:GetNPCInteractionOptions(1984)
assert(optionByID(offeredGroups.new,remoteOffer,"offer") and optionByID(offeredGroups.custom,remoteOffer,"custom"))
local conversationID=QW:SaveNPCDialogue(nil,"npc:1984","Librarian","A quiet request","Greetings, traveler.",{npcOfferQuest})
assert(conversationID and QW.db.npcDialogs[conversationID].npcID==1984)
local conversationOutbox=QW.Count(QW.outbox); assert(QW:ShareNPCDialogue(conversationID,"Other") and QW.Count(QW.outbox)>conversationOutbox)
local conversationGroups=QW:GetNPCInteractionOptions(1984)
assert(optionByID(conversationGroups.custom,conversationID,"npcdialogue") and optionByID(conversationGroups.new,npcOfferQuest,"dialogquest"))
targetName="Librarian"; targetGUID="Creature-0-1-0-47-1984-0000000002"
assert(QW:PerformNPCInteraction(optionByID(conversationGroups.custom,conversationID,"npcdialogue"),1984))
assert(QW:PerformNPCInteraction(optionByID(conversationGroups.new,npcOfferQuest,"dialogquest"),1984) and QW.db.questRuns[npcOfferQuest].acceptedFromNPC==1984)
-- Standalone NPC narratives do not require, create, or share quest offers.
local narrativeID=QW:SaveNPCDialogue(nil,"npc:1984","Librarian","The old archive","The dust remembers\r\nevery name.",{})
assert(narrativeID and #QW.db.npcDialogs[narrativeID].questIDs==0 and QW.db.npcDialogs[narrativeID].dialogue=="The dust remembers\nevery name.")
local narrativeOutbox=QW.Count(QW.outbox); assert(QW:ShareNPCDialogue(narrativeID,"Other") and QW.Count(QW.outbox)>narrativeOutbox)
QW:HandleMessage("NPC_DIALOGUE",{"9","NPC_DIALOGUE","npcdialog:remote-story","2","npc:1984","Librarian","A shared archive","A visitor left this account for you."},"Remote")
assert(QW.db.npcDialogs["npcdialog:remote-story"] and QW.db.npcDialogs["npcdialog:remote-story"].owner=="Remote")
local narrativeGroups=QW:GetNPCInteractionOptions(1984)
assert(optionByID(narrativeGroups.custom,narrativeID,"npcdialogue") and optionByID(narrativeGroups.custom,"npcdialog:remote-story","npcdialogue"))
targetGUID="Creature-0-1-0-47-1985-0000000001"; assert(not QW:AcceptQuestOffer(remoteOffer))
targetGUID="Creature-0-1-0-47-1984-0000000001"; assert(QW:AcceptQuestOffer(remoteOffer) and QW.db.questRuns[remoteOffer] and not QW.db.questOffers[remoteOffer])
-- NPC quest acceptance and dialogue objectives use the targeted NPC, never map coordinates.
local savedMapPosition=GetPlayerMapPosition; GetPlayerMapPosition=nil; currentZone="Elwynn Forest"
local dialogueSteps=QW:ParseSteps("dialogue~~~library~npc:1987~Speak to the librarian")
QW.db.questRuns.dialogueAtNPC={id="dialogueAtNPC",owner="Other",steps=dialogueSteps,places=places,placeByID={library=places[1]},reward=def,rewardCount=1,index=1,state="active"}
targetGUID="Creature-0-1-0-47-1987-0000000001"; targetName="Librarian"
local dialogueOptions=QW:GetNPCInteractionOptions(1987)
assert(optionByID(dialogueOptions.progress,"dialogueAtNPC","objective") and QW:PerformNPCInteraction(optionByID(dialogueOptions.progress,"dialogueAtNPC","objective"),1987) and QW.db.questRuns.dialogueAtNPC.state=="complete")
GetPlayerMapPosition=savedMapPosition; currentZone="Stormwind City"
-- The teaching demo is idempotent: a second click reuses the same definitions and quest.
local demoLetter,demoQuest,demoToken=QW:CreateDemo(); local demoLetter2,demoQuest2,demoToken2=QW:CreateDemo()
assert(demoLetter==demoLetter2 and demoQuest==demoQuest2 and demoToken==demoToken2 and demoToken==defaultToken and QW:HasItem(demoLetter,1))
local boarDemo,boarToken=QW:CreateBoarDemo(); local boarDemo2=QW:CreateBoarDemo()
assert(boarDemo==boarDemo2 and boarToken==defaultToken and QW.db.quests[boarDemo].steps[1].type=="kill" and QW.db.quests[boarDemo].steps[1].npcID==1984 and QW.db.quests[boarDemo].giverNPCID==2079)
currentZone="Teldrassil"; playerX,playerY=.587,.443; targetGUID="Creature-0-1-0-47-2079-0000000001"; targetName="Conservator Ilthalaine"
assert(QW:InteractWithTarget() and shownNPC.id==2079 and not QW.db.questRuns[boarDemo])
local demoOptions=QW:GetNPCInteractionOptions(2079)
assert(optionByID(demoOptions.new,boarDemo,"quest") and QW:PerformNPCInteraction(optionByID(demoOptions.new,boarDemo,"quest"),2079) and QW.db.questRuns[boarDemo].assignedLocally and QW.db.questRuns[boarDemo].state=="active")
assert(QW:InteractWithTarget()); demoOptions=QW:GetNPCInteractionOptions(2079); assert(not optionByID(demoOptions.new,boarDemo,"quest")) -- No duplicate offer after acceptance.
assert(QW:ClearAcceptedQuests() and not QW.db.questRuns[boarDemo])
QW.db.questRuns.pending={pendingDelivery={id="delivery:pending"}}
assert(QW:ClearAcceptedQuests()) -- Legacy pending states no longer block clearing accepted quests.
print("Questweaver core logic tests passed")
