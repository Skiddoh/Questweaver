local function parseOffer(text)
  local offer = {}
  for entry in string.gmatch(text or "", "[^;]+") do
    local id, count = string.match(entry, "^([^,]+),(%d+)$")
    count = tonumber(count)
    if not id or QW.StrLen(id) > 120 or not count or count < 1 or count > 999 then return nil end
    offer[QW.Count(offer)+1] = { id=id, count=count }
    if QW.Count(offer) > 12 then return nil end
  end
  return offer
end
local function formatOffer(offer)
  local out={}; for i,v in ipairs(offer) do out[i]=v.id..","..v.count end; return table.concat(out,";")
end
function QW:SerializeItem(item)
  if type(item) ~= "table" then return "" end
  local loot={}; for i,rule in ipairs(item.lootChances or {}) do loot[i]=tostring(rule.npcID)..","..tostring(rule.chance) end
  return table.concat({self:Escape(item.id),self:Escape(item.name),self:Escape(item.icon),self:Escape(item.description),self:Escape(item.maxStack or 1),self:Escape(item.category or "misc"),self:Escape(table.concat(loot,";"))}, "~")
end
function QW:ParseItem(text)
  local p, start = {}, 1
  while true do
    local at=string.find(text or "","~",start,true)
    if not at then p[QW.Count(p)+1]=string.sub(text or "",start); break end
    p[QW.Count(p)+1]=string.sub(text,start,at-1); start=at+1
    if QW.Count(p)>7 then return nil end
  end
  if QW.Count(p)~=5 and QW.Count(p)~=6 and QW.Count(p)~=7 then return nil end
  local i; for i=1,4 do p[i]=self:Unescape(p[i]); if not p[i] then return nil end end
  local n=tonumber(self:Unescape(p[5]) or ""); if not n then return nil end
  local category=p[6] and self:NormalizeItemCategory(self:Unescape(p[6])) or "misc"; if not category then return nil end
  local lootChances={}
  if p[7] then
    local parsed,err=self:ParseLootChances(self:Unescape(p[7]) or "")
    if not parsed then return nil end
    lootChances=parsed
  end
  return {id=p[1],name=p[2],icon=QW:NormalizeIcon(p[3]),description=p[4],maxStack=n,category=category,lootChances=lootChances,version=1}
end
function QW:RegisterTrade() end
function QW:StartTrade(target, itemID, count)
  count=tonumber(count)
  if not self:ValidateString(target,80) or not self:HasItem(itemID,count) then return nil,"Choose an online addon user and an available item quantity." end
  local trade={id=self:NewID("trade"), target=target, offer={{id=itemID,count=count}}, revision=1, localConfirmed=false, remoteConfirmed=false, state="offered", incoming=false}
  self.db.trades[trade.id]=trade; self:SendTradeOffer(trade); return trade.id
end
function QW:SendTradeOffer(trade)
  local definitions={}; for i,v in ipairs(trade.offer) do definitions[i]=self:SerializeItem(self.db.items[v.id]) end
  self:Send("TRADE_OFFER",trade.target,{trade.id,trade.revision,formatOffer(trade.offer),table.concat(definitions,";")})
end
function QW:ReceiveTradeOffer(f,sender)
  local id,rev=f[3],tonumber(f[4]); local offer=parseOffer(f[5]); if not self:ValidateString(id,120) or not rev or rev<1 or not offer then return end
  local defs={}; for raw in string.gmatch(f[6] or "", "[^;]+") do local d=self:ParseItem(raw); if not d then return end; defs[d.id]=d end
  for _,v in ipairs(offer) do if not defs[v.id] then return end end
  local trade=self.db.trades[id]
  if trade and (trade.state=="complete" or trade.state=="cancelled" or (trade.incoming and trade.revision >= rev)) then return end -- duplicate/replayed offers never clear consent
  if not trade then trade={id=id,incoming=true,target=sender}; self.db.trades[id]=trade end
  if trade.target~=sender or (trade.state=="committed") then return end
  trade.offer,trade.revision,trade.definitions,trade.localConfirmed,trade.remoteConfirmed,trade.state=offer,rev,defs,false,false,"offered"
  self.db.inbox[self.Count(self.db.inbox)+1]="Trade offer from "..sender..": "..id
  if self.ShowTradeWindow then self:ShowTradeWindow(id) end
end
function QW:UpdateTrade(id,itemID,count)
  local trade=self.db.trades[id]; count=tonumber(count)
  if not trade or trade.incoming or trade.state~="offered" or not self:HasItem(itemID,count) then return false,"Only an unconfirmed outgoing offer can change." end
  trade.offer={{id=itemID,count=count}}; trade.revision=trade.revision+1; trade.localConfirmed=false; trade.remoteConfirmed=false
  self:SendTradeOffer(trade); return true
end
function QW:ConfirmTrade(id)
  local trade=self.db.trades[id]; if not trade or trade.state~="offered" then return false,"Trade is not awaiting confirmation." end
  if not trade.incoming and not self:HasItem(trade.offer[1].id,trade.offer[1].count) then return false,"The offered item is no longer available." end
  trade.localConfirmed=true; self:Send("TRADE_CONFIRM",trade.target,{id,trade.revision})
  if trade.remoteConfirmed and not trade.incoming then self:CommitTrade(trade) end
  return true
end
function QW:ReceiveTradeConfirm(f,sender)
  local trade=self.db.trades[f[3]]; if not trade or trade.target~=sender or trade.revision~=tonumber(f[4]) or trade.state~="offered" then return end
  trade.remoteConfirmed=true
  if trade.localConfirmed and not trade.incoming then self:CommitTrade(trade) end
  if self.RefreshTradeWindow then self:RefreshTradeWindow() end
end
function QW:CommitTrade(trade)
  if trade.state~="offered" or not self:HasItem(trade.offer[1].id,trade.offer[1].count) then return end
  trade.state="committed"; self:Send("TRADE_COMMIT",trade.target,{trade.id,trade.revision,formatOffer(trade.offer)})
end
function QW:ReceiveTradeCommit(f,sender)
  local trade=self.db.trades[f[3]]; if not trade or not trade.incoming or trade.target~=sender or trade.revision~=tonumber(f[4]) or not trade.localConfirmed or not trade.remoteConfirmed then return end
  if not self.db.processed.transfers[trade.id] then
    local offer=parseOffer(f[5]); if not offer then return end
    for _,v in ipairs(offer) do if not self:AddItem(trade.definitions[v.id],v.count) then return end end
    self.db.processed.transfers[trade.id]=true
  end
  trade.state="complete"; self:Send("TRADE_ACK",sender,{trade.id,trade.revision})
  if self.RefreshTradeWindow then self:RefreshTradeWindow() end
end
function QW:ReceiveTradeAck(f,sender)
  local trade=self.db.trades[f[3]]; if not trade or trade.incoming or trade.target~=sender or trade.revision~=tonumber(f[4]) or trade.state~="committed" then return end
  for _,v in ipairs(trade.offer) do if not self:TakeItem(v.id,v.count) then trade.state="unresolved"; return end end
  trade.state="complete"
  if self.RefreshTradeWindow then self:RefreshTradeWindow() end
end
function QW:CancelTrade(id)
  local t=self.db.trades[id]; if not t or t.state=="complete" or t.state=="committed" then return false end
  t.state="cancelled"; self:Send("TRADE_CANCEL",t.target,{id,t.revision}); return true
end
function QW:ReceiveTradeCancel(f,sender)
  local t=self.db.trades[f[3]]; if t and t.target==sender and t.state~="complete" and t.state~="committed" then t.state="cancelled"; if self.RefreshTradeWindow then self:RefreshTradeWindow() end end
end
function QW:ResendTrade(id)
  local t=self.db.trades[id]; if t and t.state=="committed" and not t.incoming then self:Send("TRADE_COMMIT",t.target,{t.id,t.revision,formatOffer(t.offer)}); return true end; return false
end
