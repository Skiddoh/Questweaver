-- Wire format is escaped text, never Lua. Every received field is length-limited.
local function hex(n) return string.format("%02X", n) end
function QW:Escape(value)
  value = tostring(value or "")
  return (string.gsub(value, "[^%w%-%._ ]", function(c) return "%" .. hex(string.byte(c)) end))
end
function QW:Unescape(value)
  if type(value) ~= "string" or self.StrLen(value) > 4096 then return nil end
  return (string.gsub(value, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
function QW:Pack(kind, fields)
  local parts = { tostring(self.PROTOCOL), kind }
  local i
  for i = 1, self.Count(fields) do parts[self.Count(parts) + 1] = self:Escape(fields[i]) end
  return table.concat(parts, "|")
end
function QW:Unpack(packet)
  if type(packet) ~= "string" or self.StrLen(packet) > 4096 then return nil end
  local fields, start = {}, 1
  while true do
    local p = string.find(packet, "|", start, true)
    if not p then fields[self.Count(fields) + 1] = string.sub(packet, start); break end
    fields[self.Count(fields) + 1] = string.sub(packet, start, p - 1); start = p + 1
    if self.Count(fields) > 20 then return nil end
  end
  if fields[1] ~= tostring(self.PROTOCOL) or not self:ValidateString(fields[2], 32) then return nil end
  local i
  for i = 3, self.Count(fields) do fields[i] = self:Unescape(fields[i]); if fields[i] == nil then return nil end end
  return fields[2], fields
end
function QW:QueuePacket(target, packet)
  if not self:ValidateString(target, 80) or self.StrLen(packet) > 4096 then return false end
  local transferID = self:NewID("m")
  local size, count = 180, math.ceil(self.StrLen(packet) / 180)
  if count > 24 then self:Print("Message too large to send."); return false end
  local i
  for i = 1, count do
    self.outbox[self.Count(self.outbox) + 1] = { target = target, wire = transferID .. "," .. i .. "," .. count .. "," .. string.sub(packet, (i-1)*size+1, i*size) }
  end
  return true
end
function QW:Send(kind, target, fields)
  return self:QueuePacket(target, self:Pack(kind, fields))
end
function QW:OnUpdate()
  local clockNow=(GetTime and GetTime()) or self.now()
  if not self.lastInteractionRangeCheck or clockNow-self.lastInteractionRangeCheck>=.25 then
    self.lastInteractionRangeCheck=clockNow
    if self.UpdateNPCInteractionRange then self:UpdateNPCInteractionRange() end
  end
  local now = self.now()
  if self.lastSend and now - self.lastSend < .35 then return end -- one chunk / .35s
  local entry = table.remove(self.outbox, 1)
  if entry then
    self:SendAddonWire(entry.wire, entry.target)
    self.lastSend = now
  end
  for id, entry in pairs(self.incomingChunks) do
    if now - entry.at > 90 then self.incomingChunks[id] = nil end
  end
end
function QW:RegisterAddonPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(self.PREFIX)
  end
end
function QW:SendAddonWire(wire, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(self.PREFIX, wire, self.CHANNEL, target)
  else
    SendAddonMessage(self.PREFIX, wire, self.CHANNEL, target)
  end
end
function QW:RegisterProtocol()
  self.frame:RegisterEvent("CHAT_MSG_ADDON")
  local old = self.frame:GetScript("OnEvent")
  self.frame:SetScript("OnEvent", function(selfFrame, receivedEvent, first, second, third, fourth)
    receivedEvent=receivedEvent or event
    if receivedEvent == "CHAT_MSG_ADDON" then
      QW:ReceiveWire(first or arg1, second or arg2, fourth or arg4)
    else
      old(selfFrame, receivedEvent, first, second, third, fourth)
    end
  end)
end
function QW:ReceiveWire(prefix, wire, sender)
  if prefix ~= self.PREFIX or not self:ValidateString(sender or "", 100) or type(wire) ~= "string" or self.StrLen(wire) > 260 then return end
  local id, part, count, payload = string.match(wire, "^([^,]+),(%d+),(%d+),(.+)$")
  part, count = tonumber(part), tonumber(count)
  if not id or self.StrLen(id) > 80 or not part or not count or part < 1 or count < part or count > 24 then return end
  local entry = self.incomingChunks[id]
  if not entry then entry = { sender = sender, count = count, parts = {}, at = self.now() }; self.incomingChunks[id] = entry end
  if entry.sender ~= sender or entry.count ~= count then return end
  entry.parts[part], entry.at = payload, self.now()
  local i; for i = 1, count do if not entry.parts[i] then return end end
  self.incomingChunks[id] = nil
  local kind, fields = self:Unpack(table.concat(entry.parts))
  if kind then self:HandleMessage(kind, fields, sender) end
end
function QW:HandleMessage(kind, fields, sender)
  local handlers = { TRADE_OFFER="ReceiveTradeOffer", TRADE_CONFIRM="ReceiveTradeConfirm", TRADE_COMMIT="ReceiveTradeCommit", TRADE_ACK="ReceiveTradeAck", TRADE_CANCEL="ReceiveTradeCancel", QUEST_SHARE="ReceiveQuest", QUEST_OFFER="ReceiveQuestOffer", QUEST_FOLLOWUP="ReceiveFollowUpQuest", QUEST_APPROVAL="ReceiveApproval", QUEST_APPROVED="ReceiveApprovalResult", QUEST_DELIVERY="ReceiveDelivery", QUEST_DELIVERY_ACK="ReceiveDeliveryAck", NPC_DIALOGUE="ReceiveNPCDialogue" }
  local name = handlers[kind]
  if name and self[name] then self[name](self, fields, sender); if self.RefreshUI then self:RefreshUI() end end
end
