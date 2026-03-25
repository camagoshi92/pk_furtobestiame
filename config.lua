Config = {}

-- ========== ANIMALI / MISSIONE ==========
Config.SheepModel      = `A_C_Sheep_01`
Config.SheepCount      = 1
Config.DeliveryRadius  = 6.0
Config.CitySellRadius  = 6.0
Config.MissionTimeout  = 900
Config.RanchCooldown   = 1200

-- ========== NOTIFICHE / ANNUNCI ==========
Config.NotifyOk        = 'vorp:Tip'
Config.NotifyError     = 'vorp:Tip'
Config.BlipFadeSeconds = 60
Config.EnableAlertBlip = true
Config.DeliveryAreaMul = 1.8

Config.UseClientBanner = true
Config.BannerDuration  = 4000
Config.BannerTexts     = {
  title    = "HAI LIBERATO GLI ANIMALI",
  subtitle = "Porta il gregge al bracconiere"
}

-- ========== MARKER 3D ==========
Config.DeliveryMarker = {
  enabled   = true,
  radiusMul = 1.2,
  height    = 1.8,
  color     = {255, 215, 0, 180}
}

-- ========== RICOMPENSE GENERICHE ==========
Config.DefaultReward = { money = 20, gold = 0, items = {} }

-- ========== HERDING ==========
Config.Herd = {
  DriveDistance    = 6.0,
  StepTowardTarget = 4.0,
  BaseSpeed        = 1.5,
  PanicSpeed       = 2.4,
  WanderDelay      = {min=4, max=9},
  RepathIntervalMs = 1500,
  AimPanic         = true
}

-- ========== ECONOMIA RANCH / TIMERS ==========
-- Contadino
Config.FarmerBuyCooldownSec   = 60 * 30   -- ogni 30 min può COMPRARE stock
Config.FarmerSellCooldownSec  = 60 * 10   -- cooldown tra consegne
Config.MinWaitAfterBuySec     = 60 * 1    -- **NUOVO**: attesa minima dopo un acquisto prima di poter vendere
Config.FarmerSellBatch        = 1         -- capi richiesti per una consegna
Config.FarmerBuyCost          = 20        -- costo per “acquisto stock” (tasche del contadino)

-- Ladro
Config.ThiefCooldownSec       = 60 * 8
Config.DefenseBonus           = { enabled = true, money = 8 }

-- Blip icona
Config.BlipStyleDelivery      = 90287351

-- Furto
Config.RequireStockForTheft   = true
Config.TheftBatch             = 1
Config.AllowEmployeesSteal    = false

-- Spawn estetico gregge dopo acquisto
Config.DefaultHerdSpawnCount  = 3
Config.DefaultHerdSpawnRadius = 6.0

-- ========== RANCH CONFIG ==========
-- campi:
--   start       -> prompt ladro
--   delivery    -> consegna ladro
--   farmerPoint -> posizione dei prompt “E Compra / R Vendi”
--   citySell    -> destinazione consegna contadino
--   herdSpawn   -> (opzionale) dove spawna il gregge di bellezza dopo l’acquisto
--   herdSpawnCount -> (opzionale) quanti capi estetici spawna
--   reward / farmerReward / initialStock / stockPerBuy / buyCost / notify

Config.Ranches = {
  {
    id    = "ranch_valentine_sud",
    label = "Valentine Ranch",

    start       = vector3(-859.676, 336.501, 96.426),
    delivery    = vector3(-806.258, 228.653, 95.620),

    farmerPoint = vector3(-857.5, 327.63, 96.06),
    citySell    = vector3(-809.85, 327.64, 95.53),

    herdSpawn   = vector3(-855.03, 320.21, 95.67),
    herdSpawnCount = 4,

    notify = { job = "ranch_valentine_sud", ranks = { "0", "1", "2" } },

    reward        = { money = 25, gold = 0, items = {} },
    farmerReward  = { money = 50, gold = 0, items = {} },

    initialStock = 1,
    stockPerBuy  = 6,
    buyCost      = 30
  },

  {
    id    = "emerald_ranch",
    label = "Emerald Ranch",

    start       = vector3(1411.6, 284.9, 89.5),
    delivery    = vector3(1229.2, -132.5, 96.7),

    farmerPoint = vector3(1418.0, 300.0, 89.6),
    citySell    = vector3(1355.2, -1379.8, 79.9),

    herdSpawn   = vector3(1413.2, 297.8, 89.5),

    notify = { job = "rancher", ranks = { "hand", "boss" } },

    reward        = { money = 30, gold = 0, items = {} },
    farmerReward  = { money = 55, gold = 0, items = {} },

    initialStock = 0,
    stockPerBuy  = 5,
    buyCost      = 25
  }
}
