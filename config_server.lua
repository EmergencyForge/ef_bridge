-- ef_bridge: server-only settings. Every player downloads config.lua
-- along with the resource, this file never leaves the server. Secrets and
-- the modules that only run on the server belong here.
--
-- Everything except the API keys can also be changed ingame with
-- /efbridge (ACE ef_bridge.admin).
ServerConfig = {}

-- ========================================
-- IGNIS
-- ========================================
ServerConfig.Ignis = {
    -- ignis > Einstellungen > System-Konfiguration > Technik > API-Schlüssel
    APIKey = 'CHANGE_ME'
}

-- EMD sync: vehicles, status and situation reports between
-- emergencydispatch and ignis. Needs emergencydispatch and oxmysql.
ServerConfig.EMDSync = {
    Enabled = false,
    HeartbeatInterval = 5000, -- base tick in ms

    -- Dispatch data (vehicles, mission details, patients)
    DispatchSync = {
        Enabled = true,
        TickMultiplier = 6 -- every 6 ticks = every 30s at a 5s heartbeat
    },

    -- Realtime status sync (both ways: FiveM <-> web)
    StatusSync = {
        Enabled = true,
        SyncStatuses = { 'C', '1', '2', '3', '4', '7', '8' },
        SourceTable = 'emd_dispatchlog', -- table holding the status messages
        TickMultiplier = 1
    },

    -- Situation reports per mission
    LagemeldungSync = {
        Enabled = true,
        TickMultiplier = 6
    }
}

-- eNOTF billing: released eNOTF protocols for your billing script
-- (server/billing-custom.lua). Needs ignis 2026.0.26-beta and oxmysql.
ServerConfig.ENOTFBilling = {
    Enabled = false,
    AutoSync = false,      -- fetch in the background
    SyncInterval = 900000, -- ms between fetches (15 min)
    -- Skip protocols already stored in the enotf_billing table.
    -- name + 123, name + 123_1 and name + 123_2 count as one billing.
    FilterProcessed = true
}

-- ========================================
-- LEX (person and vehicle sync)
-- ========================================
-- Characters become persons in Lex, owned vehicles become vehicles with
-- their owner. Needs oxmysql and QBCore/Qbox or ESX.
ServerConfig.Lex = {
    Enabled = false,

    -- Lex > Einstellungen > FiveM-Abgleich shows the address and creates
    -- the key
    BaseURL = 'https://deine-lex-url.de/',
    APIKey = 'CHANGE_ME',

    Persons = true,  -- characters -> persons
    Vehicles = true, -- owned vehicles -> vehicles with owner

    -- A character that logs in is sent right away, together with their
    -- vehicles
    SyncOnLogin = true,

    -- Full sync of every character and vehicle in the framework database
    FullSync = {
        OnStart = true,        -- once, a minute after the resource started
        IntervalMinutes = 360, -- 0 = only on start and by hand
        -- Vehicles Lex knows from the game but the database no longer has
        -- (sold, deleted) get "abgemeldet" in Lex
        RetireMissingVehicles = true
    },

    BatchSize = 100 -- records per request, Lex takes at most 200
}
