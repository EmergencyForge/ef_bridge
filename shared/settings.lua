-- Settings that can be changed ingame (admin panel, /efbridge), shared
-- between client and server.
--
-- Every entry names a path below Config (scope 'shared', the clients get
-- it too) or below ServerConfig (scope 'server', never leaves the
-- server). The server keeps the values from the config files, lays the
-- ingame changes over them and sends the shared ones to every client.
-- Entries with restart = true take effect after `restart ef_bridge`,
-- everything else applies right away. API keys are not in here on purpose:
-- they stay in config_server.lua and the panel only shows whether they are
-- set.

Settings = {}

local function tablet(name, label)
    local base = 'Tablets.' .. name .. '.'
    local group = label
    return {
        { key = base .. 'Enabled', scope = 'shared', type = 'boolean', group = group, label = 'Tablet aktiv' },
        { key = base .. 'AllowedJobs', scope = 'shared', type = 'list', group = group, label = 'Erlaubte Jobs', help = 'Jobnamen genau wie im Framework, einer pro Zeile.' },
        { key = base .. 'RequireItem', scope = 'shared', type = 'boolean', group = group, label = 'Nur mit Gegenstand im Inventar' },
        { key = base .. 'RequiredItem', scope = 'shared', type = 'string', group = group, label = 'Gegenstand', pattern = '^[%w_%-]+$', max = 60 },
        { key = base .. 'UseProp', scope = 'shared', type = 'boolean', group = group, label = 'Tablet in der Hand zeigen' },
        { key = base .. 'Path', scope = 'shared', type = 'string', group = group, label = 'Seite in ignis', help = 'Pfad hinter der ignis-Adresse.', pattern = '^[%w_%-%./%?=&]*$', max = 120 },
        { key = base .. 'Command', scope = 'shared', type = 'string', group = group, label = 'Chatbefehl', pattern = '^[%w_%-]+$', max = 32, restart = true },
        { key = base .. 'OpenKey', scope = 'shared', type = 'string', group = group, label = 'Standardtaste', help = 'Zum Beispiel F9. Leer: keine Taste vorbelegt. Spieler können sie selbst ändern.', pattern = '^[%w_]*$', max = 20, optional = true, restart = true },
    }
end

Settings.Schema = {}

local function add(entries)
    for _, entry in ipairs(entries) do
        Settings.Schema[#Settings.Schema + 1] = entry
    end
end

add({
    { key = 'Debug', scope = 'shared', type = 'boolean', group = 'Allgemein', label = 'Ausführliche Meldungen in der Konsole' },
    { key = 'Framework', scope = 'shared', type = 'select', group = 'Allgemein', label = 'Framework', options = { 'auto', 'qbcore', 'esx' }, restart = true },

    { key = 'Ignis.BaseURL', scope = 'shared', type = 'url', group = 'ignis', label = 'Adresse von ignis', help = 'Mit https:// und / am Ende.' },
    { key = 'Ignis.TabletLogin', scope = 'shared', type = 'boolean', group = 'ignis', label = 'Tablet-Login über Discord-ID', help = 'In ignis muss „Anmeldung über ef_bridge“ eingeschaltet sein.' },
})
add(tablet('eNOTF', 'eNOTF-Tablet'))
add(tablet('FireTab', 'FireTab'))
add({
    { key = 'EMDSync.Enabled', scope = 'server', type = 'boolean', group = 'EMD-Sync', label = 'EMD-Sync aktiv', help = 'Braucht emergencydispatch und oxmysql.' },
    { key = 'EMDSync.HeartbeatInterval', scope = 'server', type = 'number', group = 'EMD-Sync', label = 'Grundtakt (ms)', min = 1000, max = 60000 },
    { key = 'EMDSync.DispatchSync.Enabled', scope = 'server', type = 'boolean', group = 'EMD-Sync', label = 'Einsatzdaten' },
    { key = 'EMDSync.DispatchSync.TickMultiplier', scope = 'server', type = 'number', group = 'EMD-Sync', label = 'Einsatzdaten alle … Takte', min = 1, max = 120 },
    { key = 'EMDSync.StatusSync.Enabled', scope = 'server', type = 'boolean', group = 'EMD-Sync', label = 'Status' },
    { key = 'EMDSync.StatusSync.TickMultiplier', scope = 'server', type = 'number', group = 'EMD-Sync', label = 'Status alle … Takte', min = 1, max = 120 },
    { key = 'EMDSync.StatusSync.SyncStatuses', scope = 'server', type = 'list', group = 'EMD-Sync', label = 'Abgeglichene Status', item = '^[%w]+$' },
    { key = 'EMDSync.StatusSync.SourceTable', scope = 'server', type = 'string', group = 'EMD-Sync', label = 'Tabelle mit den Statusmeldungen', pattern = '^[%w_]+$', max = 64, restart = true },
    { key = 'EMDSync.LagemeldungSync.Enabled', scope = 'server', type = 'boolean', group = 'EMD-Sync', label = 'Lagemeldungen' },
    { key = 'EMDSync.LagemeldungSync.TickMultiplier', scope = 'server', type = 'number', group = 'EMD-Sync', label = 'Lagemeldungen alle … Takte', min = 1, max = 120 },

    { key = 'ENOTFBilling.Enabled', scope = 'server', type = 'boolean', group = 'eNOTF-Abrechnung', label = 'Abrechnung aktiv' },
    { key = 'ENOTFBilling.AutoSync', scope = 'server', type = 'boolean', group = 'eNOTF-Abrechnung', label = 'Im Hintergrund abrufen' },
    { key = 'ENOTFBilling.SyncInterval', scope = 'server', type = 'number', group = 'eNOTF-Abrechnung', label = 'Abstand (ms)', min = 60000, max = 86400000 },
    { key = 'ENOTFBilling.FilterProcessed', scope = 'server', type = 'boolean', group = 'eNOTF-Abrechnung', label = 'Schon abgerechnete Protokolle überspringen' },

    { key = 'Lex.Enabled', scope = 'server', type = 'boolean', group = 'Lex', label = 'Abgleich mit Lex aktiv', help = 'In Lex unter Einstellungen › FiveM-Abgleich einschalten und den Schlüssel erzeugen.' },
    { key = 'Lex.BaseURL', scope = 'server', type = 'url', group = 'Lex', label = 'Adresse von Lex', help = 'Mit https:// und / am Ende.' },
    { key = 'Lex.Persons', scope = 'server', type = 'boolean', group = 'Lex', label = 'Charaktere als Personen' },
    { key = 'Lex.Vehicles', scope = 'server', type = 'boolean', group = 'Lex', label = 'Fahrzeuge mit Halter' },
    { key = 'Lex.SyncOnLogin', scope = 'server', type = 'boolean', group = 'Lex', label = 'Beim Einloggen sofort abgleichen' },
    { key = 'Lex.FullSync.IntervalMinutes', scope = 'server', type = 'number', group = 'Lex', label = 'Vollständiger Abgleich alle … Minuten', help = '0: nur beim Start und von Hand.', min = 0, max = 10080 },
    { key = 'Lex.FullSync.OnStart', scope = 'server', type = 'boolean', group = 'Lex', label = 'Vollständiger Abgleich beim Start' },
    { key = 'Lex.FullSync.RetireMissingVehicles', scope = 'server', type = 'boolean', group = 'Lex', label = 'Verschwundene Fahrzeuge abmelden', help = 'Fahrzeuge, die der vollständige Abgleich nicht mehr findet, bekommen in Lex „abgemeldet“.' },
    { key = 'Lex.BatchSize', scope = 'server', type = 'number', group = 'Lex', label = 'Datensätze pro Anfrage', min = 10, max = 200 },
})

Settings.ByKey = {}
for _, entry in ipairs(Settings.Schema) do
    Settings.ByKey[entry.key] = entry
end

local function split(path)
    local parts = {}
    for part in path:gmatch('[^%.]+') do
        parts[#parts + 1] = part
    end
    return parts
end

function Settings.Get(root, path)
    local node = root
    for _, part in ipairs(split(path)) do
        if type(node) ~= 'table' then
            return nil
        end
        node = node[part]
    end
    return node
end

function Settings.Set(root, path, value)
    local parts = split(path)
    local node = root
    for i = 1, #parts - 1 do
        if type(node[parts[i]]) ~= 'table' then
            node[parts[i]] = {}
        end
        node = node[parts[i]]
    end
    node[parts[#parts]] = value
end

-- Checks a value from the panel against its entry. Returns the cleaned
-- value, or nil and a message for the panel. Optional strings come back
-- as false when empty, so "no key" survives JSON (nil would vanish).
function Settings.Validate(entry, value)
    local t = entry.type

    if t == 'boolean' then
        if type(value) ~= 'boolean' then
            return nil, 'Erwartet: an oder aus.'
        end
        return value
    end

    if t == 'number' then
        local n = tonumber(value)
        if not n or n ~= math.floor(n) then
            return nil, 'Erwartet: eine ganze Zahl.'
        end
        if (entry.min and n < entry.min) or (entry.max and n > entry.max) then
            return nil, ('Erlaubt: %d bis %d.'):format(entry.min or 0, entry.max or n)
        end
        return math.tointeger(n) or n
    end

    if t == 'select' then
        for _, option in ipairs(entry.options) do
            if value == option then
                return value
            end
        end
        return nil, 'Unbekannte Auswahl.'
    end

    if t == 'list' then
        if type(value) ~= 'table' then
            return nil, 'Erwartet: eine Liste.'
        end
        local clean = {}
        for _, item in ipairs(value) do
            if type(item) ~= 'string' then
                return nil, 'Erwartet: Text pro Zeile.'
            end
            item = item:match('^%s*(.-)%s*$')
            if item ~= '' then
                if #item > 60 or not item:match(entry.item or '^[%w_%-%.]+$') then
                    return nil, ('„%s“ enthält Zeichen, die hier nicht erlaubt sind.'):format(item)
                end
                clean[#clean + 1] = item
            end
        end
        return clean
    end

    if t == 'string' or t == 'url' then
        if value == false or value == nil then
            value = ''
        end
        if type(value) ~= 'string' then
            return nil, 'Erwartet: Text.'
        end
        value = value:match('^%s*(.-)%s*$')
        if value == '' then
            if entry.optional then
                return false
            end
            return nil, 'Darf nicht leer sein.'
        end
        if #value > (entry.max or 255) then
            return nil, ('Höchstens %d Zeichen.'):format(entry.max or 255)
        end
        if t == 'url' then
            if not value:lower():match('^https://[%w%-%.]+[%w]') or value:find('[%s"\'<>]') then
                return nil, 'Erwartet: eine Adresse mit https://.'
            end
            if value:sub(-1) ~= '/' then
                value = value .. '/'
            end
        elseif entry.pattern and not value:match(entry.pattern) then
            return nil, 'Enthält Zeichen, die hier nicht erlaubt sind.'
        end
        return value
    end

    return nil, 'Unbekannter Typ.'
end

-- Config values as the panel and the clients see them: optional strings
-- that are unset come out as false instead of nil.
function Settings.Read(entry)
    local root = entry.scope == 'server' and ServerConfig or Config
    local value = root and Settings.Get(root, entry.key)
    if value == nil and entry.optional then
        return false
    end
    return value
end

function Settings.Write(entry, value)
    local root = entry.scope == 'server' and ServerConfig or Config
    if value == false and entry.optional then
        value = nil
    end
    Settings.Set(root, entry.key, value)
end

-- Older ignisTab config files keep working: their keys are moved to the
-- new places. Returns the notes for the console. Runs on the server after
-- config_server.lua and on the client after config.lua.
function Settings.MigrateLegacy(isServer)
    local notes = {}

    Config.Ignis = Config.Ignis or {}
    if Config.BaseURL then
        Config.Ignis.BaseURL = Config.BaseURL
        notes[#notes + 1] = 'Config.BaseURL -> Config.Ignis.BaseURL'
    end
    if type(Config.TabletLogin) == 'table' then
        Config.Ignis.TabletLogin = Config.TabletLogin.Enabled == true
        notes[#notes + 1] = 'Config.TabletLogin.Enabled -> Config.Ignis.TabletLogin'
    end
    Config.Ignis.BaseURL = Config.Ignis.BaseURL or ''
    Config.Ignis.TabletLogin = Config.Ignis.TabletLogin == true

    Config.Tablets = Config.Tablets or {}
    for name, path in pairs({ eNOTF = 'enotf/overview.php', FireTab = 'einsatz/list.php' }) do
        if type(Config[name]) == 'table' then
            Config.Tablets[name] = Config[name]
            notes[#notes + 1] = 'Config.' .. name .. ' -> Config.Tablets.' .. name
        end
        local t = Config.Tablets[name] or { Enabled = false, Command = name:lower() }
        Config.Tablets[name] = t
        t.Path = t.Path or path
        t.AllowedJobs = t.AllowedJobs or {}
        t.RequiredItem = t.RequiredItem or 'tablet'
    end
    Config.Admin = Config.Admin or {}
    Config.Admin.Command = Config.Admin.Command or 'efbridge'
    Config.Admin.Ace = Config.Admin.Ace or 'ef_bridge.admin'

    if isServer then
        ServerConfig = ServerConfig or {}
        if ServerConfig.APIKey then
            ServerConfig.Ignis = ServerConfig.Ignis or {}
            ServerConfig.Ignis.APIKey = ServerConfig.Ignis.APIKey or ServerConfig.APIKey
            notes[#notes + 1] = 'ServerConfig.APIKey -> ServerConfig.Ignis.APIKey'
        end
        ServerConfig.Ignis = ServerConfig.Ignis or {}
        for _, name in ipairs({ 'EMDSync', 'ENOTFBilling' }) do
            if type(Config[name]) == 'table' and not ServerConfig[name] then
                ServerConfig[name] = Config[name]
                notes[#notes + 1] = 'Config.' .. name .. ' -> ServerConfig.' .. name
            end
        end
        ServerConfig.EMDSync = ServerConfig.EMDSync or { Enabled = false }
        ServerConfig.ENOTFBilling = ServerConfig.ENOTFBilling or { Enabled = false }
        ServerConfig.Lex = ServerConfig.Lex or { Enabled = false }
        ServerConfig.Lex.FullSync = ServerConfig.Lex.FullSync or {}
    end

    -- the old tables would still be readable through Config and confuse
    -- whoever looks there later
    Config.BaseURL, Config.TabletLogin, Config.eNOTF, Config.FireTab = nil, nil, nil, nil
    Config.EMDSync, Config.ENOTFBilling = nil, nil

    return notes
end
