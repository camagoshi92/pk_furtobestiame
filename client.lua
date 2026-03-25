-- client.lua - vorp_ranchrob
-- Prompt contadino a due righe (E compra / R vendi) + countdown nel gruppo.
-- NIENTE testo giallo al centro schermo.

local RanchPrompts = {}
local InMission, MissionRole = false, nil -- "thief" | "farmer"
local Sheep = {}
local DeliveryPoint, ActiveRanchId = nil, nil
local DeliveryBlipPair, AlertBlipPair = nil, nil
local StartTime = 0

-- === CONTROLLI ===
local PROMPT_CONTROL_E = 0xCEFD9220 -- E
local PROMPT_CONTROL_R = 0xE30CD707 -- R
local PROMPT_CONTROL_ALT = 0x8AAA0AD4 -- fallback

-- === BLIP natives ===
local N_BLIP_ADD_FOR_COORDS = 0x554D9D53F696D002
local N_BLIP_ADD_FOR_RADIUS = 0x45F13B7E0A15C880
local N_SET_BLIP_NAME       = 0x9CB1A1623062F402
local N_REMOVE_BLIP         = 0x86A652570E5F25DD
local N_BLIP_SET_MODIFIER   = 0x662D364ABF16DE2F

local BLIP_STYLE_OBJECTIVE  = 1664425300
local BLIP_STYLE_SEARCH     = 1223143800
local BLIP_STYLE_AREA       = -276343508
local BLIP_STYLE_DELIVERY   = (Config.BlipStyleDelivery or BLIP_STYLE_OBJECTIVE)

local MODIFIER_AREA_YELLOW  = 0x0A53C7C7
local MODIFIER_FADE_SLOW    = 0x00D2F4B2

-- === INIT NUI (no banner center se non richiesto) ===
CreateThread(function()
  SetNuiFocus(false, false)
  SendNUIMessage({ action = "hideAnnouncement" })
end)

AddEventHandler("onResourceStart", function(res)
  if res == GetCurrentResourceName() then
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "hideAnnouncement" })
    TriggerServerEvent("vorp_ranchrob:requestJob")
  end
end)

-- === RUOLO LOCALE ===
local CurrentJob, CurrentRank = "", ""
RegisterNetEvent("vorp_ranchrob:setJob", function(data)
  CurrentJob  = (data and data.job)  or ""
  CurrentRank = (data and data.rank) or ""
end)
CreateThread(function()
  Wait(3000)
  TriggerServerEvent("vorp_ranchrob:requestJob")
  while true do
    Wait(60000)
    TriggerServerEvent("vorp_ranchrob:requestJob")
  end
end)

local function isEmployeeFor(ranch)
  if not ranch or not ranch.notify then return false end
  if ranch.notify.job and tostring(CurrentJob) ~= tostring(ranch.notify.job) then return false end
  if ranch.notify.ranks and #ranch.notify.ranks > 0 then
    local r = tostring(CurrentRank or "")
    for _, allowed in ipairs(ranch.notify.ranks) do
      if r == tostring(allowed) then return true end
    end
    return false
  end
  return true
end

-- === COOLDOWN VENDITA (solo HUD nel gruppo prompt) ===
local SellCooldownByRanch = {}  -- [ranchId] = seconds
RegisterNetEvent("vorp_ranchrob:setSellCooldown", function(ranchId, seconds)
  if ranchId then SellCooldownByRanch[ranchId] = math.max(0, tonumber(seconds or 0)) end
end)
RegisterNetEvent("vorp_ranchrob:clearSellCooldown", function(ranchId)
  if ranchId then SellCooldownByRanch[ranchId] = 0 end
end)
-- tick che scala ogni secondo
CreateThread(function()
  while true do
    for id, sec in pairs(SellCooldownByRanch) do
      if sec and sec > 0 then SellCooldownByRanch[id] = sec - 1 end
    end
    Wait(1000)
  end
end)

local function fmtMMSS(sec)
  sec = math.max(0, math.floor(sec or 0))
  local m = math.floor(sec/60); local s = sec % 60
  return string.format("%02d:%02d", m, s)
end

-- === BLIP helpers ===
local function _setName(blip, name)
  if not blip or blip == 0 or not name then return end
  Citizen.InvokeNative(N_SET_BLIP_NAME, blip, CreateVarString(10, "LITERAL_STRING", name))
end
local function createAreaPair(coords, radius, name)
  local r = radius or 20.0
  local area = Citizen.InvokeNative(N_BLIP_ADD_FOR_RADIUS, BLIP_STYLE_AREA, coords.x, coords.y, coords.z, r)
  local center = Citizen.InvokeNative(N_BLIP_ADD_FOR_COORDS, BLIP_STYLE_DELIVERY, coords.x, coords.y, coords.z)
  if not center or center == 0 then center = Citizen.InvokeNative(N_BLIP_ADD_FOR_COORDS, BLIP_STYLE_OBJECTIVE, coords.x, coords.y, coords.z) end
  pcall(function() Citizen.InvokeNative(N_BLIP_SET_MODIFIER, area, MODIFIER_AREA_YELLOW) end)
  pcall(function() Citizen.InvokeNative(N_BLIP_SET_MODIFIER, area, MODIFIER_FADE_SLOW)   end)
  _setName(area, name); _setName(center, name)
  return { area = area, center = center }
end
local function createSearchPair(coords, name)
  local center = Citizen.InvokeNative(N_BLIP_ADD_FOR_COORDS, BLIP_STYLE_SEARCH, coords.x, coords.y, coords.z)
  if not center or center == 0 then center = Citizen.InvokeNative(N_BLIP_ADD_FOR_COORDS, BLIP_STYLE_OBJECTIVE, coords.x, coords.y, coords.z) end
  _setName(center, name); return { center = center }
end
local function removePair(pair)
  if not pair then return end
  if pair.area   and pair.area   ~= 0 then if RemoveBlip then RemoveBlip(pair.area)   else Citizen.InvokeNative(N_REMOVE_BLIP, pair.area)   end end
  if pair.center and pair.center ~= 0 then if RemoveBlip then RemoveBlip(pair.center) else Citizen.InvokeNative(N_REMOVE_BLIP, pair.center) end end
end

-- === NUI (solo per banner opzionale) ===
local function uiShow(duration, title, subtitle)
  SendNUIMessage({ action="showAnnouncement", duration=tonumber(duration or Config.BannerDuration or 6000) or 6000,
                   title=tostring(title or ""), subtitle=tostring(subtitle or "") })
end
local function uiHide() SendNUIMessage({ action = "hideAnnouncement" }) end
RegisterNetEvent("vorp_ranchrob:banner", function(title, subtitle, duration)
  uiShow(duration, title, subtitle)
  local dur = tonumber(duration or Config.BannerDuration or 6000) or 6000
  CreateThread(function() Wait(dur + 1000); uiHide() end)
end)

-- === Marker 3D ===
local N_DRAW_MARKER = 0x2A32FAA57B937173
local function groundZAt(x, y, zHint)
  local found, z = GetGroundZFor_3dCoord(x, y, zHint or 1000.0, false)
  return found and z or (zHint or 0.0)
end
local function drawDeliveryMarker(pos)
  if not Config.DeliveryMarker or not Config.DeliveryMarker.enabled then return end
  local r,g,b,a = table.unpack(Config.DeliveryMarker.color or {255,215,0,180})
  local radius  = (Config.DeliveryRadius or 6.0) * (Config.DeliveryMarker.radiusMul or 1.0)
  local h       = Config.DeliveryMarker.height or 1.8
  local gz = groundZAt(pos.x, pos.y, pos.z + 50.0) + 0.05
  Citizen.InvokeNative(N_DRAW_MARKER, 28, pos.x, pos.y, gz, 0,0,0, 0,0,0, radius, radius, h, r,g,b,a, false,false,2,false, 0,0,false)
  Citizen.InvokeNative(N_DRAW_MARKER, 28, pos.x, pos.y, gz, 0,0,0, 0,0,0, radius*1.02, radius*1.02, 0.15, 255,255,0,200, false,false,2,false, 0,0,false)
end

-- === Helpers ===
local function tip(msg, t) TriggerEvent(Config.NotifyOk, msg, t or 5000) end
local function loadModel(hash)
  if not IsModelValid(hash) then return false end
  RequestModel(hash)
  local timeout = GetGameTimer() + 10000
  while not HasModelLoaded(hash) do Wait(50); if GetGameTimer() > timeout then return false end end
  return true
end

-- === Prompt ===
local function createPrompt(label, groupHash, control)
  local prompt = PromptRegisterBegin()
  PromptSetControlAction(prompt, control or PROMPT_CONTROL_E)
  PromptSetText(prompt, CreateVarString(10, "LITERAL_STRING", label))
  PromptSetEnabled(prompt, true)
  PromptSetVisible(prompt, true)
  PromptSetStandardMode(prompt, true)
  PromptSetHoldMode(prompt, false)
  PromptSetGroup(prompt, groupHash)
  PromptRegisterEnd(prompt)
  return prompt
end
local GROUP_ROB  = GetHashKey("RANCH_ROB_GROUP")
local GROUP_MGMT = GetHashKey("RANCH_FARMER_MGMT")

-- === LOOP PROMPTS ===
CreateThread(function()
  local groupStrRob = CreateVarString(10, "LITERAL_STRING", "Avvia")

  for _, r in ipairs(Config.Ranches) do
    RanchPrompts[r.id] = RanchPrompts[r.id] or { data = r }
    RanchPrompts[r.id].promptRob = createPrompt("Ruba bestiame", GROUP_ROB, PROMPT_CONTROL_E)
    if r.farmerPoint then
      RanchPrompts[r.id].promptBuy  = createPrompt("Compra bestiame", GROUP_MGMT, PROMPT_CONTROL_E)
      RanchPrompts[r.id].promptSell = createPrompt("Vendi bestiame",  GROUP_MGMT, PROMPT_CONTROL_R)
    end
  end

  while true do
    local sleep = 750
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)

    -- LADRO (non dipendenti)
    if not InMission then
      for id, R in pairs(RanchPrompts) do
        local dist = #(pcoords - R.data.start)
        if dist < 3.0 and not isEmployeeFor(R.data) then
          sleep = 0
          PromptSetActiveGroupThisFrame(GROUP_ROB, groupStrRob)
          if PromptHasStandardModeCompleted(R.promptRob) then
            TriggerServerEvent("vorp_ranchrob:tryStart", id)
          end
        end
      end
    end

    -- CONTADINO: E compra / R vendi + countdown nel titolo gruppo
    for id, R in pairs(RanchPrompts) do
      if R.data.farmerPoint and R.promptBuy and R.promptSell then
        local distM = #(pcoords - R.data.farmerPoint)
        if distM < 3.0 and isEmployeeFor(R.data) and not InMission then
          sleep = 0
          local left = math.max(0, SellCooldownByRanch[id] or 0)
          local header = (left > 0)
            and CreateVarString(10, "LITERAL_STRING", ("Gestisci bestiame\nConsegna tra %s"):format(fmtMMSS(left)))
            or  CreateVarString(10, "LITERAL_STRING", "Gestisci bestiame")
          PromptSetActiveGroupThisFrame(GROUP_MGMT, header)

          -- E = Compra
          if PromptHasStandardModeCompleted(R.promptBuy) then
            TriggerServerEvent("vorp_ranchrob:farmerBuyAndSpawn", id)
            Wait(350)
          end
          -- R = Vendi
          if PromptHasStandardModeCompleted(R.promptSell) then
            TriggerServerEvent("vorp_ranchrob:farmerStartDelivery", id)
            Wait(350)
          end
        end
      end
    end

    Wait(sleep)
  end
end)

-- === Spawn estetico dopo acquisto ===
RegisterNetEvent("vorp_ranchrob:spawnHerdAt", function(data)
  local pos    = data and data.coords
  local count  = (data and tonumber(data.count)) or Config.DefaultHerdSpawnCount or 3
  local radius = (data and tonumber(data.radius)) or Config.DefaultHerdSpawnRadius or 6.0
  local model  = (data and data.model) or Config.SheepModel
  if not pos then return end
  if not loadModel(model) then return end
  for i=1, math.max(1, count) do
    local angle = math.random()*math.pi*2
    local r = math.random()*radius
    local x = pos.x + math.cos(angle)*r
    local y = pos.y + math.sin(angle)*r
    local z = pos.z
    local s = CreatePed(model, x, y, z, 0.0, true, false, false, false)
    SetEntityAsMissionEntity(s, true, true)
    TaskWanderStandard(s, 6.0, 2)
    SetPedOutfitPreset(s, 0)
  end
  SetModelAsNoLongerNeeded(model)
  TriggerEvent(Config.NotifyOk, "Nuovo gregge arrivato al ranch.", 3500)
end)

-- === AVVIO MISSIONE LADRO ===
RegisterNetEvent("vorp_ranchrob:startClient", function(ranchId, delivery)
  if InMission then return end
  InMission, MissionRole = true, "thief"
  ActiveRanchId, DeliveryPoint = ranchId, delivery
  if not DeliveryPoint then InMission=false return end

  if Config.UseClientBanner then
    local title = (Config.BannerTexts and Config.BannerTexts.title)    or "FURTO BESTIAME AVVIATO"
    local sub   = (Config.BannerTexts and Config.BannerTexts.subtitle) or "Porta il gregge alla consegna"
    uiShow(Config.BannerDuration or 6000, title, sub)
    CreateThread(function() Wait((Config.BannerDuration or 6000) + 3000); uiHide() end)
  end

  StartTime = GetGameTimer()
  Sheep = {}

  if DeliveryBlipPair then removePair(DeliveryBlipPair) end
  local radius = (Config.DeliveryRadius or 12.0) * (Config.DeliveryAreaMul or 1.8)
  DeliveryBlipPair = createAreaPair(DeliveryPoint, radius, "Consegna")

  local ped = PlayerPedId()
  local model = Config.SheepModel
  if not loadModel(model) then TriggerEvent(Config.NotifyError, "Modello animale non disponibile.", 6000) InMission=false return end
  for i=1, Config.SheepCount do
    local o = GetOffsetFromEntityInWorldCoords(ped, math.random(-6,6)+0.0, math.random(-6,6)+0.0, 0.0)
    local s = CreatePed(model, o.x, o.y, o.z, GetEntityHeading(ped), true, false, false, false)
    SetEntityAsMissionEntity(s, true, true)
    SetPedOutfitPreset(s, 0)
    TaskWanderStandard(s, 10.0, 10)
    table.insert(Sheep, s)
  end
  SetModelAsNoLongerNeeded(model)

  CreateThread(function()
    local nextRepath = 0
    while InMission and MissionRole == "thief" do
      local p = PlayerPedId()
      local pcoords = GetEntityCoords(p)
      drawDeliveryMarker(DeliveryPoint)

      if Config.MissionTimeout > 0 and (GetGameTimer() - StartTime)/1000 >= Config.MissionTimeout then
        uiHide(); TriggerServerEvent("vorp_ranchrob:thiefFailed", ActiveRanchId)
        for _, s in ipairs(Sheep) do if DoesEntityExist(s) then DeletePed(s) end end
        Sheep = {}; if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
        InMission=false; break
      end

      local now = GetGameTimer()
      if now >= nextRepath then
        nextRepath = now + ((Config.Herd and Config.Herd.RepathIntervalMs) or 1500)
        local isAiming = (Config.Herd and Config.Herd.AimPanic) and (IsPlayerFreeAiming(PlayerId()) or IsPedArmed(p, 6))
        local driveDist = (Config.Herd and Config.Herd.DriveDistance) or 6.0
        local stepDist  = (Config.Herd and Config.Herd.StepTowardTarget) or 4.0
        local baseSpd   = (Config.Herd and Config.Herd.BaseSpeed) or 1.8
        local panicSpd  = (Config.Herd and Config.Herd.PanicSpeed) or 2.8

        for _, s in ipairs(Sheep) do
          if DoesEntityExist(s) then
            local sc = GetEntityCoords(s)
            local dx = (DeliveryPoint.x - sc.x); local dy = (DeliveryPoint.y - sc.y)
            local d  = math.sqrt(dx*dx + dy*dy)
            local tx = (d>0) and (dx/d) or 0.0; local ty = (d>0) and (dy/d) or 0.0
            local pd = #(sc - pcoords)
            if pd <= driveDist then
              local step = math.min(stepDist, d)
              TaskGoStraightToCoord(s, sc.x + tx*step, sc.y + ty*step, sc.z, isAiming and panicSpd or baseSpd, 3000, 0.0, 0.0)
            elseif math.random() < 0.25 then
              TaskWanderStandard(s, 6.0, 2)
            end
          end
        end
      end

      -- >>> FAIL se muore una pecora
      local allIn = true
      local r = (Config.DeliveryRadius or 6.0)
      for _, s in ipairs(Sheep) do
        if DoesEntityExist(s) then
          if IsPedDeadOrDying(s, true) then
            tip("Consegna fallita: una pecora è morta.", 6000)
            allIn=false
            uiHide()
            if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
            TriggerServerEvent("vorp_ranchrob:thiefFailed", ActiveRanchId)
            InMission=false
            break
          end
          if #(GetEntityCoords(s) - DeliveryPoint) > r then allIn=false break end
        else
          allIn=false
          uiHide()
          if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
          TriggerServerEvent("vorp_ranchrob:thiefFailed", ActiveRanchId)
          InMission=false
          break
        end
      end

      if not InMission then break end
      if allIn and #Sheep>0 then
        uiHide()
        for _, s in ipairs(Sheep) do if DoesEntityExist(s) then DeletePed(s) end end
        Sheep = {}; if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
        TriggerServerEvent("vorp_ranchrob:deliveredAll", ActiveRanchId)
        InMission=false; MissionRole=nil; break
      end

      Wait(200)
    end
  end)
end)

-- === AVVIO MISSIONE CONTADINO ===
RegisterNetEvent("vorp_ranchrob:startFarmerDelivery", function(ranchId, citySellPoint, batch)
  if InMission then return end
  InMission, MissionRole = true, "farmer"
  ActiveRanchId, DeliveryPoint = ranchId, citySellPoint
  if not DeliveryPoint then InMission=false return end

  if Config.UseClientBanner then
    uiShow(Config.BannerDuration or 6000, "CONSEGNA BESTIAME", "Porta il gregge al mercato in città")
    CreateThread(function() Wait((Config.BannerDuration or 6000) + 2000); uiHide() end)
  end

  StartTime = GetGameTimer()
  Sheep = {}

  if DeliveryBlipPair then removePair(DeliveryBlipPair) end
  local radius = (Config.CitySellRadius or Config.DeliveryRadius or 6.0) * (Config.DeliveryAreaMul or 1.8)
  DeliveryBlipPair = createAreaPair(DeliveryPoint, radius, "Mercato cittadino")

  local count = math.max(tonumber(batch or Config.FarmerSellBatch or 1) or 1, 1)
  local ped = PlayerPedId()
  local model = Config.SheepModel
  if not loadModel(model) then TriggerEvent(Config.NotifyError, "Modello animale non disponibile.", 6000) InMission=false return end
  for i=1, count do
    local o = GetOffsetFromEntityInWorldCoords(ped, math.random(-6,6)+0.0, math.random(-6,6)+0.0, 0.0)
    local s = CreatePed(model, o.x, o.y, o.z, GetEntityHeading(ped), true, false, false, false)
    SetEntityAsMissionEntity(s, true, true)
    SetPedOutfitPreset(s, 0)
    TaskWanderStandard(s, 10.0, 10)
    table.insert(Sheep, s)
  end
  SetModelAsNoLongerNeeded(model)

  CreateThread(function()
    local nextRepath = 0
    while InMission and MissionRole == "farmer" do
      local p = PlayerPedId()
      local pcoords = GetEntityCoords(p)
      drawDeliveryMarker(DeliveryPoint)

      if Config.MissionTimeout > 0 and (GetGameTimer() - StartTime)/1000 >= Config.MissionTimeout then
        uiHide(); TriggerServerEvent("vorp_ranchrob:farmerDeliveryFailed", ActiveRanchId)
        for _, s in ipairs(Sheep) do if DoesEntityExist(s) then DeletePed(s) end end
        Sheep = {}; if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
        InMission=false; MissionRole=nil; break
      end

      local now = GetGameTimer()
      if now >= nextRepath then
        nextRepath = now + ((Config.Herd and Config.Herd.RepathIntervalMs) or 1500)
        local isAiming = (Config.Herd and Config.Herd.AimPanic) and (IsPlayerFreeAiming(PlayerId()) or IsPedArmed(p, 6))
        local driveDist = (Config.Herd and Config.Herd.DriveDistance) or 6.0
        local stepDist  = (Config.Herd and Config.Herd.StepTowardTarget) or 4.0
        local baseSpd   = (Config.Herd and Config.Herd.BaseSpeed) or 1.8
        local panicSpd  = (Config.Herd and Config.Herd.PanicSpeed) or 2.8

        for _, s in ipairs(Sheep) do
          if DoesEntityExist(s) then
            local sc = GetEntityCoords(s)
            local dx = (DeliveryPoint.x - sc.x); local dy = (DeliveryPoint.y - sc.y)
            local d  = math.sqrt(dx*dx + dy*dy)
            local tx = (d>0) and (dx/d) or 0.0; local ty = (d>0) and (dy/d) or 0.0
            local pd = #(sc - pcoords)
            if pd <= driveDist then
              local step = math.min(stepDist, d)
              TaskGoStraightToCoord(s, sc.x + tx*step, sc.y + ty*step, sc.z, isAiming and panicSpd or baseSpd, 3000, 0.0, 0.0)
            elseif math.random() < 0.25 then
              TaskWanderStandard(s, 6.0, 2)
            end
          end
        end
      end

      -- >>> FAIL se muore una pecora
      local allIn = true
      local r = (Config.CitySellRadius or Config.DeliveryRadius or 6.0)
      for _, s in ipairs(Sheep) do
        if DoesEntityExist(s) then
          if IsPedDeadOrDying(s, true) then
            tip("Consegna fallita: una pecora è morta.", 6000)
            allIn=false
            uiHide(); if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
            TriggerServerEvent("vorp_ranchrob:farmerDeliveryFailed", ActiveRanchId)
            InMission=false
            break
          end
          if #(GetEntityCoords(s) - DeliveryPoint) > r then allIn=false break end
        else
          allIn=false
          uiHide(); if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
          TriggerServerEvent("vorp_ranchrob:farmerDeliveryFailed", ActiveRanchId)
          InMission=false
          break
        end
      end

      if not InMission then break end
      if allIn and #Sheep>0 then
        uiHide()
        for _, s in ipairs(Sheep) do if DoesEntityExist(s) then DeletePed(s) end end
        Sheep = {}; if DeliveryBlipPair then removePair(DeliveryBlipPair) end; DeliveryBlipPair=nil
        TriggerServerEvent("vorp_ranchrob:farmerDelivered", ActiveRanchId)
        InMission=false; MissionRole=nil; break
      end

      Wait(200)
    end
  end)
end)

-- === ALERT DIPENDENTI ===
RegisterNetEvent("vorp_ranchrob:receiveAlert", function(ranchLabel, coords)
  tip(("Allarme furto al %s!"):format(ranchLabel), 7000)
  if AlertBlipPair then removePair(AlertBlipPair) end
  AlertBlipPair = createSearchPair(coords, ranchLabel)
  CreateThread(function()
    local t = (Config.BlipFadeSeconds or 60)
    while t > 0 do Wait(1000); t = t - 1 end
    removePair(AlertBlipPair); AlertBlipPair = nil
  end)
end)

-- === CLEANUP ===
AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  if InMission and ActiveRanchId then
    if MissionRole == "thief" then
      TriggerServerEvent("vorp_ranchrob:thiefFailed", ActiveRanchId)
    elseif MissionRole == "farmer" then
      TriggerServerEvent("vorp_ranchrob:farmerDeliveryFailed", ActiveRanchId)
    end
  end
  if DeliveryBlipPair then removePair(DeliveryBlipPair) end
  if AlertBlipPair    then removePair(AlertBlipPair)    end
  for _, s in ipairs(Sheep) do if DoesEntityExist(s) then DeletePed(s) end end
  InMission=false; MissionRole=nil; Sheep = {}
  DeliveryBlipPair, AlertBlipPair = nil, nil
  DeliveryPoint, ActiveRanchId = nil, nil
end)
