-- server.lua - vorp_ranchrob
-- Allineato al client:
--  - Countdown vendita: vorp_ranchrob:setSellCooldown(ranchId, seconds)
--  - Clear countdown:   vorp_ranchrob:clearSellCooldown(ranchId)

local VorpCore = {}
TriggerEvent("getCore", function(core) VorpCore = core end)

-- Re-link del core quando riavvii SOLO questa risorsa
AddEventHandler("onResourceStart", function(res)
  if res == GetCurrentResourceName() then
    TriggerEvent("getCore", function(core) VorpCore = core end)
    print("[vorp_ranchrob] Core re-linked on resource start")
  end
end)

local ActiveRanches  = {}
local PlayerMissions = {}
local PlayerThiefCD  = {}
local RanchState     = {}

-- ===== Notifiche/Banner =====
local function notify(src, msg, isError)
  local ev = isError and Config.NotifyError or Config.NotifyOk
  TriggerClientEvent(ev, src, tostring(msg or ""), 5000)
end
local function announceCenter(src, msg, duration)
  local dur = tonumber(duration or 8000) or 8000
  local ok = pcall(function() TriggerClientEvent("vorp:NotifyCenter", src, tostring(msg or ""), dur) end)
  if not ok then notify(src, msg, false) end
end
local function sendBanner(src, title, subtitle, duration)
  local dur = tonumber(duration or Config.BannerDuration or 6000) or 6000
  if Config.UseClientBanner then
    TriggerClientEvent("vorp_ranchrob:banner", src, tostring(title or ""), tostring(subtitle or ""), dur)
  else
    announceCenter(src, (tostring(title or "") .. (subtitle and ("\n" .. tostring(subtitle)) or "")), dur)
  end
end

-- ===== Helpers Ranch/Char =====
local function getRanchById(ranchId)
  for _, r in ipairs(Config.Ranches or {}) do if r.id == ranchId then return r end end
  return nil
end
local function getCharacter(User)
  if not User then return nil end
  local c = User.getUsedCharacter
  if type(c) == "function" then local ok, res = pcall(c, User); if ok then return res end; return nil end
  return c
end
local function getCharInfo(src)
  local User = VorpCore.getUser(tonumber(src)); if not User then return nil end
  local Char = getCharacter(User); if not Char then return nil end
  return { job=Char.job, rank=Char.jobGrade or Char.jobgrade or Char.rank, group=Char.group, metadata=Char.metadata or Char.meta or {} }
end
local function isEmployeeOfRanch(charInfo, notifyRule)
  if not charInfo or not notifyRule then return false end
  if notifyRule.society then
    local m = charInfo.metadata or {}; local charSoc = m.society or m.ranchId or m.company
    return (charSoc and tostring(charSoc) == tostring(notifyRule.society)) or false
  end
  if notifyRule.job and charInfo.job ~= notifyRule.job then return false end
  if notifyRule.ranks and #notifyRule.ranks > 0 then
    local r = tostring(charInfo.rank or ""); for _, allowed in ipairs(notifyRule.ranks) do if r == tostring(allowed) then return true end end
    return false
  end
  return true
end
local function alertRanchEmployees(ranch, coords)
  for _, playerSrc in ipairs(GetPlayers()) do
    local info = getCharInfo(playerSrc)
    if isEmployeeOfRanch(info, ranch.notify) then
      sendBanner(tonumber(playerSrc), "ALLERTA RANCH", ("Furto bestiame al %s"):format(ranch.label))
      if Config.EnableAlertBlip then TriggerClientEvent("vorp_ranchrob:receiveAlert", tonumber(playerSrc), ranch.label, coords) end
    end
  end
end

-- ===== Money helpers =====
local function getCash(Char)
  local ok, cash
  if Char.getMoney then ok, cash = pcall(function() return Char.getMoney() end); if ok and type(cash)=="number" then return cash end end
  if Char.getCurrency then ok, cash = pcall(function() return Char.getCurrency(0) end); if ok and type(cash)=="number" then return cash end end
  return 0
end
local function addMoney(Char, src, amount)
  if not amount or amount <= 0 then return true end
  local ok, res
  if Char.addMoney     then ok, res = pcall(function() return Char.addMoney(amount) end);     if ok and (res==true or res==nil) then return true end end
  if Char.addCurrency  then ok, res = pcall(function() return Char.addCurrency(0, amount) end);if ok and (res==true or res==nil) then return true end end
  ok = pcall(function() TriggerEvent("vorp:addMoney", src, amount) end); return ok
end
local function subMoney(Char, src, amount)
  if not amount or amount <= 0 then return true end
  local cash = getCash(Char); if cash>0 and cash<amount then return false end
  local ok, res
  if Char.removeMoney    then ok, res = pcall(function() return Char.removeMoney(amount) end);    if ok and (res==true or res==nil) then return true end end
  if Char.removeCurrency then ok, res = pcall(function() return Char.removeCurrency(0, amount) end);if ok and (res==true or res==nil) then return true end end
  ok = pcall(function() TriggerEvent("vorp:subMoney", src, amount) end); return ok
end
local function giveReward(src, reward)
  local User = VorpCore.getUser(src); if not User then return end
  local Char = getCharacter(User);    if not Char then return end
  local r = reward or Config.DefaultReward or {}
  addMoney(Char, src, r.money or 0)
  if r.gold and r.gold > 0 then
    local ok=false
    if Char.addGold then ok = pcall(function() Char.addGold(r.gold) end) end
    if not ok and Char.addCurrency then ok = pcall(function() Char.addCurrency(1, r.gold) end) end
    if not ok then ok = pcall(function() TriggerEvent("vorp:addGold", src, r.gold) end) end
  end
  if r.items and type(r.items)=="table" then
    for _, it in ipairs(r.items) do
      local name, count = it.name, it.count or 1
      if name and count>0 then
        local ok=false
        if Char.addItem then ok = pcall(function() Char.addItem(name, count) end) end
        if not ok and exports and exports.vorp_inventory and exports.vorp_inventory.addItem then ok = pcall(function() exports.vorp_inventory:addItem(src, name, count) end) end
        if not ok then ok = pcall(function() TriggerEvent("vorp:Inventory_addItem", src, name, count) end) end
      end
    end
  end
end

-- ===== Stato Ranch =====
CreateThread(function()
  for _, r in ipairs(Config.Ranches or {}) do
    RanchState[r.id] = { stock = r.initialStock or 0, reserved = 0, lastBuy = 0, lastSell = 0 }
  end
end)
local function getRanchState(rid)
  RanchState[rid] = RanchState[rid] or { stock = 0, reserved = 0, lastBuy = 0, lastSell = 0 }
  return RanchState[rid]
end
local function availableStock(rid)
  local st = getRanchState(rid); return (st.stock or 0) - (st.reserved or 0)
end

-- ===== Cooldowns =====
local function canThiefStart(src)
  local last = PlayerThiefCD[src] or 0; local now=os.time(); local cd=Config.ThiefCooldownSec or 0
  if cd>0 and (now-last)<cd then return false, ("Puoi tentare un altro furto tra %d sec."):format(cd-(now-last)) end
  return true
end
local function canFarmerBuy(rid)
  local st=getRanchState(rid); local now=os.time(); local cd=Config.FarmerBuyCooldownSec or 0
  if cd>0 and (now-st.lastBuy)<cd then return false, ("Potrai comprare di nuovo tra %d sec."):format(cd-(now-st.lastBuy)) end
  return true
end
-- ritorna: ok, msg, seconds_left
local function canFarmerSell(rid)
  local st=getRanchState(rid)
  local batch=Config.FarmerSellBatch or 1
  if (st.stock or 0) < batch then return false, "Non hai abbastanza capi in stock.", 0 end
  local now=os.time()
  local cd = Config.FarmerSellCooldownSec or 0
  if cd>0 and (now-st.lastSell)<cd then
    local left = cd - (now - st.lastSell)
    return false, ("Potrai avviare una consegna tra %d sec."):format(left), left
  end
  local waitAfter = Config.MinWaitAfterBuySec or 0
  if waitAfter>0 and (now - (st.lastBuy or 0)) < waitAfter then
    local left = waitAfter - (now - (st.lastBuy or 0))
    return false, ("Devi attendere ancora %d sec. dopo l'ultimo acquisto."):format(left), left
  end
  return true, nil, 0
end

local function rewardDefenders(ranch)
  if not (Config.DefenseBonus and Config.DefenseBonus.enabled) then return end
  for _, playerSrc in ipairs(GetPlayers()) do
    local info = getCharInfo(playerSrc)
    if isEmployeeOfRanch(info, ranch.notify) then
      giveReward(tonumber(playerSrc), { money = Config.DefenseBonus.money or 5 })
      notify(playerSrc, "Avete difeso il gregge! Ricompensa ricevuta.", false)
    end
  end
end

-- ===== Job sync → client =====
RegisterNetEvent("vorp_ranchrob:requestJob", function()
  local src=source; local info=getCharInfo(src) or {}
  TriggerClientEvent("vorp_ranchrob:setJob", src, { job=tostring(info.job or ""), rank=tostring(info.rank or "") })
end)

-- ====== LADRO ======
RegisterNetEvent("vorp_ranchrob:tryStart", function(ranchId)
  local src=source; local ranch=getRanchById(ranchId); if not ranch then return notify(src,"Ranch non valido.",true) end
  if PlayerMissions[src] then return notify(src, "Hai già una missione in corso.", true) end
  if not Config.AllowEmployeesSteal then
    local info=getCharInfo(src); if info and isEmployeeOfRanch(info, ranch.notify) then return notify(src,"Non puoi rubare: lavori per questo ranch.",true) end
  end
  local ok,msg = canThiefStart(src); if not ok then return notify(src,msg,true) end

  local now=os.time(); local stat=ActiveRanches[ranchId]
  if stat and stat.lastStart and (now-stat.lastStart) < (Config.RanchCooldown or 0) then
    local left=(Config.RanchCooldown or 0)-(now-stat.lastStart)
    return notify(src,("Il ranch è in allerta. Riprova tra %d sec."):format(left),true)
  end

  local req=tonumber(Config.TheftBatch or 1)
  if Config.RequireStockForTheft then
    local avail=availableStock(ranchId); if avail<req then return notify(src,("Nessun bestiame disponibile (richiesti %d, disponibili %d)."):format(req,avail),true) end
  end

  ActiveRanches[ranchId] = ActiveRanches[ranchId] or {}
  ActiveRanches[ranchId].lastStart = now
  ActiveRanches[ranchId].players   = ActiveRanches[ranchId].players or {}
  ActiveRanches[ranchId].players[src] = true

  local st=getRanchState(ranchId); st.reserved = math.max((st.reserved or 0) + req, 0)
  PlayerMissions[src] = { role="thief", ranchId=ranchId, startedAt=now, theftBatch=req }

  TriggerClientEvent("vorp_ranchrob:startClient", src, ranchId, ranch.delivery)
  sendBanner(src, (Config.BannerTexts and Config.BannerTexts.title) or "HAI LIBERATO GLI ANIMALI",
                 (Config.BannerTexts and Config.BannerTexts.subtitle) or "Porta il gregge al bracconiere",
                 Config.BannerDuration)
  alertRanchEmployees(ranch, ranch.start)
end)

RegisterNetEvent("vorp_ranchrob:deliveredAll", function(ranchId)
  local src=source; local mission=PlayerMissions[src]
  if not mission or mission.ranchId~=ranchId or mission.role~="thief" then return end
  local ranch=getRanchById(ranchId); local st=getRanchState(ranchId)
  local req=tonumber(mission.theftBatch or Config.TheftBatch or 1)
  giveReward(src, ranch and ranch.reward or Config.DefaultReward)
  notify(src,"Consegna riuscita! Ricompensa ottenuta.",false)
  st.stock = math.max((st.stock or 0) - req, 0)
  st.reserved = math.max((st.reserved or 0) - req, 0)
  PlayerThiefCD[src]=os.time(); PlayerMissions[src]=nil
  if ActiveRanches[ranchId] then ActiveRanches[ranchId].players[src]=nil end
end)

RegisterNetEvent("vorp_ranchrob:thiefFailed", function(ranchId)
  local src=source; local ranch=getRanchById(ranchId); if not ranch then return end
  local st=getRanchState(ranchId); local mission=PlayerMissions[src]
  local req=(mission and mission.theftBatch) or (Config.TheftBatch or 1)
  rewardDefenders(ranch)
  st.reserved = math.max((st.reserved or 0) - req, 0)
  PlayerThiefCD[src]=os.time(); PlayerMissions[src]=nil
  if ActiveRanches[ranchId] and ActiveRanches[ranchId].players then ActiveRanches[ranchId].players[src]=nil end
end)

-- ====== CONTADINO ======

-- E = Compra e spawn estetico (+ countdown attesa minima dopo acquisto)
RegisterNetEvent("vorp_ranchrob:farmerBuyAndSpawn", function(ranchId)
  local src=source; local ranch=getRanchById(ranchId); if not ranch then return notify(src,"Ranch non valido.",true) end
  local info=getCharInfo(src); if not isEmployeeOfRanch(info, ranch.notify) then return notify(src,"Non lavori per questo ranch.",true) end
  local ok,msg=canFarmerBuy(ranchId); if not ok then return notify(src,msg,true) end

  local User=VorpCore.getUser(src); if not User then return notify(src,"Utente non trovato.",true) end
  local Char=getCharacter(User);    if not Char then return notify(src,"Character non trovato.",true) end

  local cost=tonumber(ranch.buyCost or Config.FarmerBuyCost or 0) or 0
  if cost>0 then local paid=subMoney(Char,src,cost); if not paid then return notify(src,"Fondi insufficienti per l'acquisto.",true) end end

  local st=getRanchState(ranchId)
  st.stock   = (st.stock or 0) + (ranch.stockPerBuy or 4)
  st.lastBuy = os.time()

  notify(src, ("Hai acquistato capi di bestiame. Stock attuale: %d"):format(st.stock), false)

  -- Avvia countdown "attesa minima dopo acquisto" (se previsto)
  local waitAfter = Config.MinWaitAfterBuySec or 0
  if waitAfter > 0 then
    TriggerClientEvent("vorp_ranchrob:setSellCooldown", src, ranchId, waitAfter)
  else
    TriggerClientEvent("vorp_ranchrob:clearSellCooldown", src, ranchId)
  end

  -- Spawn estetico
  local herdPos   = ranch.herdSpawn or ranch.farmerPoint or ranch.start
  local herdCount = ranch.herdSpawnCount or Config.DefaultHerdSpawnCount or 3
  local herdRadius= Config.DefaultHerdSpawnRadius or 6.0
  TriggerClientEvent("vorp_ranchrob:spawnHerdAt", src,
    { coords=herdPos, count=herdCount, radius=herdRadius, model=Config.SheepModel })
end)

-- R = Avvia consegna in città (con attese e riserva)
RegisterNetEvent("vorp_ranchrob:farmerStartDelivery", function(ranchId)
  local src=source; local ranch=getRanchById(ranchId); if not ranch then return notify(src,"Ranch non valido.",true) end
  if PlayerMissions[src] then return notify(src,"Hai già una missione in corso.",true) end
  local info=getCharInfo(src); if not isEmployeeOfRanch(info, ranch.notify) then return notify(src,"Non lavori per questo ranch.",true) end

  local ok,msg,left = canFarmerSell(ranchId)
  if not ok then
    notify(src,msg,true)
    if left and left > 0 then
      TriggerClientEvent("vorp_ranchrob:setSellCooldown", src, ranchId, left)
    end
    return
  end

  local st=getRanchState(ranchId)
  local batch=tonumber(Config.FarmerSellBatch or 1)
  st.reserved = math.max((st.reserved or 0) + batch, 0)
  st.lastSell = os.time()

  PlayerMissions[src] = { role="farmer", ranchId=ranchId, batch=batch, startedAt=os.time() }

  TriggerClientEvent("vorp_ranchrob:startFarmerDelivery", src, ranchId, ranch.citySell, batch)
  TriggerClientEvent("vorp_ranchrob:clearSellCooldown", src, ranchId)

  notify(src, ("Consegna avviata: guida %d capi al mercato in città."):format(batch), false)
end)

RegisterNetEvent("vorp_ranchrob:farmerDelivered", function(ranchId)
  local src=source; local mission=PlayerMissions[src]
  if not mission or mission.role~="farmer" or mission.ranchId~=ranchId then return end
  local ranch=getRanchById(ranchId); if not ranch then return end
  local st=getRanchState(ranchId); local batch=tonumber(mission.batch or Config.FarmerSellBatch or 1)
  st.stock    = math.max((st.stock or 0) - batch, 0)
  st.reserved = math.max((st.reserved or 0) - batch, 0)

  giveReward(src, ranch.farmerReward or { money = 40 })
  notify(src, "Vendita completata! Pagamento ricevuto.", false)

  local cd = Config.FarmerSellCooldownSec or 0
  if cd > 0 then
    local now = os.time()
    local left = math.max(0, cd - (now - (st.lastSell or now)))
    if left > 0 then
      TriggerClientEvent("vorp_ranchrob:setSellCooldown", src, ranchId, left)
    else
      TriggerClientEvent("vorp_ranchrob:clearSellCooldown", src, ranchId)
    end
  else
    TriggerClientEvent("vorp_ranchrob:clearSellCooldown", src, ranchId)
  end

  PlayerMissions[src] = nil
end)

RegisterNetEvent("vorp_ranchrob:farmerDeliveryFailed", function(ranchId)
  local src=source; local mission=PlayerMissions[src]
  if not mission or mission.role~="farmer" or mission.ranchId~=ranchId then return end
  local st=getRanchState(ranchId); local batch=tonumber(mission.batch or Config.FarmerSellBatch or 1)
  st.reserved = math.max((st.reserved or 0) - batch, 0)

  notify(src, "Consegna fallita. Il bestiame è tornato disponibile al ranch.", true)

  local cd = Config.FarmerSellCooldownSec or 0
  if cd > 0 then
    local now = os.time()
    local left = math.max(0, cd - (now - (st.lastSell or now)))
    if left > 0 then
      TriggerClientEvent("vorp_ranchrob:setSellCooldown", src, ranchId, left)
    else
      TriggerClientEvent("vorp_ranchrob:clearSellCooldown", src, ranchId)
    end
  else
    TriggerClientEvent("vorp_ranchrob:clearSellCooldown", src, ranchId)
  end

  PlayerMissions[src] = nil
end)

-- ===== Disconnect Cleanup =====
AddEventHandler("playerDropped", function()
  local src=source; local mission=PlayerMissions[src]; if not mission then return end
  local st=getRanchState(mission.ranchId)
  if mission.role=="thief" then
    local req=mission.theftBatch or Config.TheftBatch or 1
    st.reserved = math.max((st.reserved or 0) - req, 0)
  elseif mission.role=="farmer" then
    local batch=mission.batch or Config.FarmerSellBatch or 1
    st.reserved = math.max((st.reserved or 0) - batch, 0)
  end
  PlayerMissions[src]=nil
  if ActiveRanches[mission.ranchId] and ActiveRanches[mission.ranchId].players then ActiveRanches[mission.ranchId].players[src]=nil end
end)
