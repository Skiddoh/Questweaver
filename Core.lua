-- Questweaver: deliberately small, data-only cooperative RP addon.
QW = QW or {}
QW.RELEASE = "0.3.44"
QW.VERSION = 6
QW.PROTOCOL = 7
QW.PREFIX = "QW1"
QW.CHANNEL = "WHISPER"
QW.now = function() return time() end
-- WoW 1.12 embeds Lua 5.0. Keep this MVP loadable there as well as in later clients.
QW.StrLen = string.len
QW.Count = table.getn or function(t)
  local n = 0
  while t[n + 1] ~= nil do n = n + 1 end
  return n
end
if not string.gmatch then string.gmatch = string.gfind end

function QW:Print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffQuestweaver:|r " .. tostring(message))
end

function QW:PlayerName()
  local name, realm = UnitName("player")
  if realm and realm ~= "" then return name .. "-" .. realm end
  return name or "Unknown"
end

function QW:NewID(kind)
  self.db.sequence = (self.db.sequence or 0) + 1
  return kind .. ":" .. self.db.playerID .. ":" .. self.db.sequence
end

function QW:InitDB()
  if type(QW_DB) ~= "table" then QW_DB = {} end
  self.db = QW_DB
  self.db.version = self.db.version or self.VERSION
  self.db.playerID = self.db.playerID or ("p" .. tostring(self.now()) .. tostring(math.random(1000, 9999)))
  self.db.sequence = self.db.sequence or 0
  self.db.items = self.db.items or {}
  self.db.inventory = self.db.inventory or {}
  self.db.trades = self.db.trades or {}
  self.db.quests = self.db.quests or {}
  self.db.sets = self.db.sets or {}
  self.db.questRuns = self.db.questRuns or {}
  self.db.questHistory = self.db.questHistory or {}
  self.db.npcNames = self.db.npcNames or {}
  self.db.npcDialogs = self.db.npcDialogs or {}
  self.db.questOffers = self.db.questOffers or {}
  self.db.followUpDefinitions = self.db.followUpDefinitions or {}
  self.db.processed = self.db.processed or { transfers = {}, deliveries = {} }
  self.db.processed.transfers = self.db.processed.transfers or {}
  self.db.processed.deliveries = self.db.processed.deliveries or {}
  self.db.inbox = self.db.inbox or {}
  self.outbox, self.incomingChunks = {}, {}
  if self.EnsureDefaultItems then self:EnsureDefaultItems() end
  self.db.version=self.VERSION
end

function QW:ValidateString(value, max)
  return type(value) == "string" and self.StrLen(value) > 0 and self.StrLen(value) <= max and not string.find(value, "[%c]")
end

function QW:Copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = self:Copy(v) end
  return out
end

function QW:OnLoad()
  self:InitDB()
  self:RegisterAddonPrefix()
  self:RegisterProtocol()
  self:RegisterInventory()
  self:RegisterTrade()
  self:RegisterQuest()
  SLASH_QUESTWEAVER1 = "/qw"
  SlashCmdList.QUESTWEAVER = function(message)
    -- SlashCmdList passes the text as an argument in modern clients, while
    -- older Forever clients may expose it through the global `msg`/`arg1`.
    message=message or msg or arg1 or ""
    local rawCommand=string.gsub(message,"^%s*(.-)%s*$","%1")
    rawCommand=string.gsub(rawCommand,"^/qw%s+","")
    local command=string.lower(rawCommand)
    if command=="inventory" or command=="inv" then QW:ShowRPInventory()
    elseif command=="maker" or command=="maker inventory" then QW:ShowMakerInventory()
    elseif command=="trade" then QW:ShowTradeWindow()
    elseif string.match(command,"^link%s+") then local itemID=string.match(rawCommand,"^%S+%s+(.+)$"); if itemID and QW.PrintItemLinkForChat then QW:PrintItemLinkForChat(itemID) else QW:Print("Usage: /qw link <RP item ID>") end
    elseif command=="active" or command=="activequests" then QW:ShowActiveQuests()
    elseif command=="quest" or command=="quests" then QW:ShowQuestJournal()
    elseif command=="sets" or command=="set" then QW:ShowSets()
    elseif command=="conversation" or command=="conversations" then QW:OpenNewNPCDialogue()
    elseif command=="interact" then local ok,message=QW:InteractWithTarget(); QW:Print(message or (ok and "Quest interaction complete.")); if QW.RefreshUI then QW:RefreshUI() end
    elseif command=="npcid" then local ok,message=QW:DescribeTargetNPC(); QW:Print(message or (ok and "NPC ID found."))
    elseif command=="killdebug" or command=="killdebug on" then
      QW.debugKills=true
      QW:Print("Kill event diagnostics ON. Registration status:")
      local eventName,status
      for eventName,status in pairs(QW.killEventRegistration or {}) do
        QW:Print(eventName..": "..(status.ok and "registered" or ("FAILED - "..tostring(status.error))))
      end
      QW:Print("Kill something now; use /qw killdebug off to disable.")
    elseif command=="killdebug off" then QW.debugKills=false; QW:Print("Kill event diagnostics OFF.")
    else QW:ToggleUI() end
  end
  self.frame:SetScript("OnUpdate", function() QW:OnUpdate() end)
  -- Keep slash diagnostics registered even if this client's UI API rejects a
  -- frame operation during construction. Surface Lua errors instead of
  -- silently losing the command handler before it is installed.
  local uiOK,uiError=pcall(self.CreateUI,self)
  if not uiOK then self:Print("UI startup failed: "..tostring(uiError)) end
  self:Print("Loaded. Use /qw to open.")
end

QW.frame = CreateFrame("Frame", "QuestweaverEventFrame")
QW.frame:RegisterEvent("ADDON_LOADED")
QW.frame:SetScript("OnEvent", function(_, receivedEvent, addonName, second)
  receivedEvent=receivedEvent or event; addonName=addonName or arg1
  if receivedEvent == "ADDON_LOADED" and addonName == "Questweaver" then QW:OnLoad() end
  if receivedEvent=="PARTY_KILL" then QW:HandlePartyKill(addonName or arg1,second or arg2)
  elseif receivedEvent=="COMBAT_LOG_EVENT_UNFILTERED" then QW:HandleCombatLogKill()
  end
end)
