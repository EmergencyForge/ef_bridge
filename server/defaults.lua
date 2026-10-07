-- Built-in defaults for the server-only modules. Never sent to clients.
-- API keys start empty and are set in the admin panel or with
-- `efbridge key ignis|lex <key>` in the server console.
ServerConfig = {
    Ignis = {
        APIKey = ''
    },

    EMDSync = {
        Enabled = false,
        HeartbeatInterval = 5000,
        DispatchSync = { Enabled = true, TickMultiplier = 6 },
        StatusSync = {
            Enabled = true,
            SyncStatuses = { 'C', '1', '2', '3', '4', '7', '8' },
            SourceTable = 'emd_dispatchlog',
            TickMultiplier = 1
        },
        LagemeldungSync = { Enabled = true, TickMultiplier = 6 }
    },

    ENOTFBilling = {
        Enabled = false,
        AutoSync = false,
        SyncInterval = 900000,
        FilterProcessed = true
    },

    Lex = {
        Enabled = false,
        BaseURL = '',
        APIKey = '',
        Persons = true,
        Vehicles = true,
        SyncOnLogin = true,
        FullSync = {
            OnStart = true,
            IntervalMinutes = 360,
            RetireMissingVehicles = true
        },
        BatchSize = 100
    }
}
