-- ef_bridge: shared settings. Every player downloads this file with the
-- resource, so nothing secret goes in here. API keys and server-only
-- modules live in config_server.lua.
--
-- Most values can also be changed ingame with /efbridge (ACE
-- ef_bridge.admin). Ingame changes are stored on the server and win over
-- this file until they are reset in the panel.
Config = {}

-- 'auto' picks up QBCore (or Qbox) or ESX on its own
Config.Framework = 'auto' -- 'auto', 'qbcore' or 'esx'

Config.Debug = false

-- ========================================
-- ADMIN PANEL
-- ========================================
Config.Admin = {
    Command = 'efbridge',     -- /efbridge opens the panel
    Ace = 'ef_bridge.admin'   -- add_ace group.admin ef_bridge.admin allow
}

-- ========================================
-- IGNIS (tablets, EMD sync, billing)
-- ========================================
Config.Ignis = {
    -- Base URL of your ignis installation, with the trailing slash, e.g.
    --   https://your-domain.tld/
    --   https://your-domain.tld/ignis/
    BaseURL = 'https://deine-ignis-url.de/',

    -- The Discord login of ignis doesn't work in the game browser. With
    -- this on, the server fetches a one-time login link from ignis for the
    -- player's Discord ID the first time a tablet loads. Needs:
    --   * ignis: system setting TABLET_LOGIN_ENABLED switched on
    --   * ServerConfig.Ignis.APIKey set in config_server.lua
    --   * FiveM: Discord as required identifier, only then does FiveM
    --     hand out a verified Discord ID
    TabletLogin = false
}

-- ========================================
-- TABLETS
-- ========================================
Config.Tablets = {
    eNOTF = {
        Enabled = true,
        Command = 'enotf',
        OpenKey = 'F9', -- default key, nil = players bind it themselves
        Path = 'enotf/overview.php', -- page inside ignis
        AllowedJobs = { 'ambulance', 'admin' },
        RequireItem = false,
        RequiredItem = 'tablet',
        UseProp = true,
        Prop = {
            model = 'notfpad',
            bone = 18905,
            offset = { x = 0.1240, y = 0.0550, z = 0.1550, xRot = -76.0, yRot = -186.0, zRot = 58.3 }
        }
    },

    FireTab = {
        Enabled = true,
        Command = 'firetab',
        OpenKey = nil,
        Path = 'einsatz/list.php',
        AllowedJobs = { 'fire', 'admin' },
        RequireItem = false,
        RequiredItem = 'tablet',
        UseProp = true,
        Prop = {
            model = 'firetab',
            bone = 18905,
            offset = { x = 0.1240, y = 0.0450, z = 0.1550, xRot = 18.0, yRot = -186.0, zRot = 58.3 }
        }
    }
}

Config.Animation = {
    dict = "amb@world_human_seat_wall_tablet@female@base",
    anim = "base",
    flag = 50
}
