-- Built-in defaults for everything clients need. There is no config file:
-- server owners change these in the admin panel (/efbridge) or with the
-- console command efbridge; the server keeps the changes and sends the
-- shared ones to every client.
Config = {
    Framework = 'auto', -- 'auto', 'qbcore', 'esx' or 'standalone'
    Debug = false,

    -- Fixed on purpose: you need them to reach the panel in the first place
    Admin = {
        Command = 'efbridge',
        Ace = 'ef_bridge.admin'
    },

    Ignis = {
        BaseURL = '', -- empty: ignis not used
        TabletLogin = false
    },

    Tablets = {
        eNOTF = {
            Enabled = false,
            Command = 'enotf',
            OpenKey = 'F9',
            Path = 'enotf/overview.php',
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
            Enabled = false,
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
                offset = { x = 0.1188, y = 0.0535, z = 0.1545, xRot = 18.0, yRot = -186.0, zRot = 58.3 }
            }
        }
    },

    Animation = {
        dict = 'amb@world_human_seat_wall_tablet@female@base',
        anim = 'base',
        flag = 50
    }
}
