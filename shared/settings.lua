-- Every setting of ef_bridge, shared between client and server. There are
-- no config files: the defaults live in shared/defaults.lua and
-- server/defaults.lua, changes come from the admin panel (/efbridge), the
-- console command efbridge or an import of an old config file.
--
-- Every entry names a path below Config (scope 'shared', the clients get
-- it too) or below ServerConfig (scope 'server', never leaves the
-- server). Entries with restart = true take effect after
-- `restart ef_bridge`, everything else applies right away.
-- type = 'secret' (the API keys) can be set and cleared, but no value is
-- ever sent back, not even to admins.

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
        { key = base .. 'Prop.model', scope = 'shared', type = 'string', group = group, label = 'Modell in der Hand', pattern = '^[%w_%-]+$', max = 60, advanced = true },
        { key = base .. 'Prop.bone', scope = 'shared', type = 'number', group = group, label = 'Knochen (Bone-ID)', min = 0, max = 65535, advanced = true },
        { key = base .. 'Prop.offset.x', scope = 'shared', type = 'float', group = group, label = 'Versatz X', min = -2, max = 2, advanced = true },
        { key = base .. 'Prop.offset.y', scope = 'shared', type = 'float', group = group, label = 'Versatz Y', min = -2, max = 2, advanced = true },
        { key = base .. 'Prop.offset.z', scope = 'shared', type = 'float', group = group, label = 'Versatz Z', min = -2, max = 2, advanced = true },
        { key = base .. 'Prop.offset.xRot', scope = 'shared', type = 'float', group = group, label = 'Drehung X', min = -360, max = 360, advanced = true },
        { key = base .. 'Prop.offset.yRot', scope = 'shared', type = 'float', group = group, label = 'Drehung Y', min = -360, max = 360, advanced = true },
        { key = base .. 'Prop.offset.zRot', scope = 'shared', type = 'float', group = group, label = 'Drehung Z', min = -360, max = 360, advanced = true },
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

    { key = 'Animation.dict', scope = 'shared', type = 'string', group = 'Allgemein', label = 'Animation: Dictionary', pattern = '^[%w_@%-%.]+$', max = 120, advanced = true },
    { key = 'Animation.anim', scope = 'shared', type = 'string', group = 'Allgemein', label = 'Animation: Name', pattern = '^[%w_%-%.]+$', max = 60, advanced = true },
    { key = 'Animation.flag', scope = 'shared', type = 'number', group = 'Allgemein', label = 'Animation: Flag', min = 0, max = 65535, advanced = true },

    { key = 'Ignis.BaseURL', scope = 'shared', type = 'url', group = 'ignis', label = 'Adresse von ignis', help = 'Mit https:// und / am Ende. Leer: ignis wird nicht genutzt.', optional = true },
    { key = 'Ignis.APIKey', scope = 'server', type = 'secret', group = 'ignis', label = 'API-Schlüssel', help = 'In ignis unter Einstellungen › System-Konfiguration › Technik.' },
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
    { key = 'Lex.BaseURL', scope = 'server', type = 'url', group = 'Lex', label = 'Adresse von Lex', help = 'Mit https:// und / am Ende. Lex zeigt sie unter Einstellungen › FiveM-Abgleich.', optional = true },
    { key = 'Lex.APIKey', scope = 'server', type = 'secret', group = 'Lex', label = 'API-Schlüssel', help = 'Lex zeigt ihn einmal beim Erzeugen unter Einstellungen › FiveM-Abgleich.' },
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

    if t == 'float' then
        local n = tonumber(value)
        if not n or n ~= n or n == math.huge or n == -math.huge then
            return nil, 'Erwartet: eine Zahl.'
        end
        if (entry.min and n < entry.min) or (entry.max and n > entry.max) then
            return nil, ('Erlaubt: %s bis %s.'):format(entry.min, entry.max)
        end
        return n + 0.0
    end

    if t == 'secret' then
        if type(value) ~= 'string' then
            return nil, 'Erwartet: Text.'
        end
        value = value:match('^%s*(.-)%s*$')
        if value == '' then
            return nil, 'Darf nicht leer sein. Zum Löschen „Schlüssel löschen“ nehmen.'
        end
        if #value > 200 or value:find('[%s%c]') then
            return nil, 'Ein Schlüssel hat keine Leerzeichen und höchstens 200 Zeichen.'
        end
        return value
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
                -- an empty address means "not used", a string keeps
                -- BuildURL from falling back to another base
                return t == 'url' and '' or false
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
    if entry.type == 'secret' then
        -- only whether it is set; the key itself stays where it is
        return type(value) == 'string' and value ~= '' and value ~= 'CHANGE_ME'
    end
    if value == nil and entry.optional then
        return false
    end
    return value
end

-- The stored value itself, secrets included. Server only.
function Settings.Raw(entry)
    local root = entry.scope == 'server' and ServerConfig or Config
    return root and Settings.Get(root, entry.key)
end

function Settings.Write(entry, value)
    local root = entry.scope == 'server' and ServerConfig or Config
    if value == false and entry.optional then
        value = nil
    end
    Settings.Set(root, entry.key, value)
end

-- Moves the keys of older config files (ignisTab and the first ef_bridge
-- layout) to their current places. Works on the tables an imported file
-- filled, never on the live Config. Returns notes for the console.
function Settings.MigrateLegacy(cfg, srv)
    local notes = {}
    cfg.Ignis = type(cfg.Ignis) == 'table' and cfg.Ignis or {}
    srv.Ignis = type(srv.Ignis) == 'table' and srv.Ignis or {}

    if cfg.BaseURL then
        cfg.Ignis.BaseURL = cfg.BaseURL
        notes[#notes + 1] = 'Config.BaseURL -> Ignis.BaseURL'
    end
    if type(cfg.TabletLogin) == 'table' then
        cfg.Ignis.TabletLogin = cfg.TabletLogin.Enabled == true
        notes[#notes + 1] = 'Config.TabletLogin.Enabled -> Ignis.TabletLogin'
    end

    cfg.Tablets = type(cfg.Tablets) == 'table' and cfg.Tablets or {}
    for _, name in ipairs({ 'eNOTF', 'FireTab' }) do
        if type(cfg[name]) == 'table' then
            cfg.Tablets[name] = cfg[name]
            notes[#notes + 1] = 'Config.' .. name .. ' -> Tablets.' .. name
        end
    end

    -- the very old place: config.lua, readable by every player
    if cfg.APIKey and not srv.Ignis.APIKey and not srv.APIKey then
        srv.Ignis.APIKey = cfg.APIKey
        notes[#notes + 1] = 'Config.APIKey -> Ignis.APIKey (this key was public, better create a new one in ignis)'
    end
    if srv.APIKey then
        srv.Ignis.APIKey = srv.Ignis.APIKey or srv.APIKey
        notes[#notes + 1] = 'ServerConfig.APIKey -> Ignis.APIKey'
    end
    for _, name in ipairs({ 'EMDSync', 'ENOTFBilling' }) do
        if type(cfg[name]) == 'table' and srv[name] == nil then
            srv[name] = cfg[name]
            notes[#notes + 1] = 'Config.' .. name .. ' -> ' .. name
        end
    end

    return notes
end
