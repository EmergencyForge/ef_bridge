Config = {}

-- Framework detection ('auto' picks up QBCore or ESX on its own)
Config.Framework = 'auto' -- 'auto', 'qbcore' or 'esx'

-- ========================================
-- URL & API
-- ========================================
-- Base URL of your ignis installation, e.g.
--   https://your-domain.tld/
--   https://your-domain.tld/ignis/
Config.BaseURL = 'https://deine-url.de/' -- keep the trailing slash

-- API key used by all modules (must match the key set in ignis)
Config.APIKey = 'CHANGE_ME'

Config.Debug = false

-- ========================================
-- ENOTF TABLET
-- ========================================
Config.eNOTF = {
    Enabled = true,
    Command = 'enotf',
    OpenKey = 'F9', -- default key, nil = players bind it themselves
    AllowedJobs = {
        'ambulance',
        'admin'
    },
    RequireItem = false,
    RequiredItem = 'tablet',
    UseProp = true,
    Prop = {
        model = 'notfpad',
        bone = 18905,
        offset = {
            x = 0.1240,
            y = 0.0550,
            z = 0.1550,
            xRot = -76.0,
            yRot = -186.0,
            zRot = 58.3
        }
    }
}

-- ========================================
-- FIRETAB TABLET
-- ========================================
Config.FireTab = {
    Enabled = true,
    Command = 'firetab',
    OpenKey = nil, -- default key, nil = players bind it themselves
    AllowedJobs = {
        'fire',
        'admin'
    },
    RequireItem = false,
    RequiredItem = 'tablet',
    UseProp = true,
    Prop = {
        model = 'firetab',
        bone = 18905,
        offset = {
            x = 0.1240,
            y = 0.0450,
            z = 0.1550,
            xRot = 18.0,
            yRot = -186.0,
            zRot = 58.3
        }
    }
}

-- ========================================
-- EMD SYNC
-- ========================================
Config.EMDSync = {
    Enabled = false,
    HeartbeatInterval = 5000, -- base tick in ms (default: 5000 = 5s)

    -- Dispatch data (vehicles, mission details, patients)
    DispatchSync = {
        Enabled = true,
        TickMultiplier = 6 -- every 6 ticks = every 30s at a 5s heartbeat
    },

    -- Realtime status sync (both ways: FiveM <-> web)
    StatusSync = {
        Enabled = true,
        SyncStatuses = {'C', '1', '2', '3', '4', '7', '8'}, -- statuses to sync
        SourceTable = 'emd_dispatchlog', -- table holding the status messages
        TickMultiplier = 1 -- every tick = every 5s at a 5s heartbeat
    },

    -- Situation reports per mission
    LagemeldungSync = {
        Enabled = true,
        TickMultiplier = 6
    }
}

-- ========================================
-- ENOTF BILLING
-- ========================================
Config.ENOTFBilling = {
    Enabled = false,

    AutoSync = false, -- sync in the background automatically
    SyncInterval = 900000, -- ms between syncs (default: 15 min)

    -- Skip protocols that already exist in the FiveM DB
    -- (needs the enotf_billing table).
    -- Note: name + 123, name + 123_1, name + 123_2 count as one billing —
    -- the base number before the "_" is what matters.
    FilterProcessed = true
}

-- ========================================
-- TABLET ANIMATION
-- ========================================
Config.Animation = {
    dict = "amb@world_human_seat_wall_tablet@female@base",
    anim = "base",
    flag = 50
}
