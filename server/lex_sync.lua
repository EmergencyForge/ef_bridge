-- Lex: characters become persons, owned vehicles become vehicles with
-- their owner. Lex takes what the game says for name, birth date, gender
-- and phone of a person and plate, model, class and owner of a vehicle;
-- everything else in Lex stays untouched.
--
-- Two ways in:
--   * a character logs in: that character and their vehicles go to Lex a
--     few seconds later (queued, so a server start with 60 players makes a
--     handful of requests instead of 60)
--   * full sync: every character and vehicle in the framework database,
--     in batches, on start, every few hours and by hand. At the end Lex
--     can mark vehicles it no longer saw as "abgemeldet".
--
-- Data comes from the framework tables, not from online players:
--   QBCore/Qbox  players (citizenid, charinfo), player_vehicles
--   ESX          users (identifier, firstname, ...), owned_vehicles

LexSync = {}

local Tag = '^5[Lex-Sync]^7 '
local state = {
    running = false,
    last = nil,       -- summary of the last full sync for the panel
    lastError = nil,
    lastLive = nil,
}

local function Info(message)
    print(Tag .. message)
end

local function Cfg()
    return ServerConfig.Lex
end

local function Active()
    local cfg = Cfg()
    return cfg and cfg.Enabled and (cfg.BaseURL or '') ~= '' and Bridge.LexKeySet()
end

-- ========================================
-- LEX API
-- ========================================

local errorHints = {
    not_configured = 'In Lex ist noch kein Schlüssel erzeugt (Einstellungen > FiveM-Abgleich).',
    invalid_key = 'Lex lehnt den Schlüssel ab. Trag im Panel unter Lex den Schlüssel aus Lex ein (oder efbridge key lex <Schlüssel>).',
    sync_disabled = 'Der FiveM-Abgleich ist in Lex ausgeschaltet (Einstellungen > FiveM-Abgleich).',
}

-- POST to /api/v1/fivem/<path>. Returns ok, data, a message for the
-- console and the panel on failure.
function LexSync.Call(path, body)
    local url = BuildURL('api/v1/fivem/' .. path, Cfg().BaseURL)
    local status, data, raw = Bridge.Request(url, 'POST', body or {}, {
        ['X-API-Key'] = Cfg().APIKey
    })

    if status >= 200 and status < 300 and data.success then
        return true, data, nil
    end

    local message
    if status == 0 then
        message = 'Lex ist nicht erreichbar (' .. url .. ').'
    elseif data.error and errorHints[data.error] then
        message = errorHints[data.error]
    elseif data.message then
        message = 'Lex: ' .. tostring(data.message) .. ' (' .. status .. ')'
    else
        message = 'Lex antwortet mit ' .. status .. (raw and raw ~= '' and (': ' .. tostring(raw):sub(1, 120)) or '')
    end
    return false, data, message
end

-- ========================================
-- MAPPING (framework -> Lex)
-- ========================================

local function Text(value)
    if value == nil then return nil end
    value = tostring(value):match('^%s*(.-)%s*$')
    return value ~= '' and value or nil
end

local function DecodeJson(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or nil
end

-- Birth dates arrive as YYYY-MM-DD, DD/MM/YYYY, DD.MM.YYYY or MM/DD/YYYY
-- (ESX setups differ). Ambiguous slashes are read day first unless the
-- first number can't be a day.
local function BirthDate(value)
    value = Text(value)
    if not value then return nil end

    local y, m, d = value:match('^(%d%d%d%d)%-(%d%d?)%-(%d%d?)')
    if not y then
        local a, b, year = value:match('^(%d%d?)[%./](%d%d?)[%./](%d%d%d%d)$')
        if a then
            a, b = tonumber(a), tonumber(b)
            if b > 12 and a <= 12 then
                m, d = a, b
            else
                d, m = a, b
            end
            y = year
        end
    end
    if not y then return nil end

    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return ('%04d-%02d-%02d'):format(y, m, d)
end

-- QBCore: 0 = male, 1 = female. ESX: 'm' / 'f'.
local function Gender(value)
    if value == 0 or value == '0' or value == 'm' or value == 'M' then return 'm' end
    if value == 1 or value == '1' or value == 'f' or value == 'F' or value == 'w' then return 'w' end
    return nil
end

-- Vehicle class from the framework category
local classByCategory = {
    motorcycles = 'motorrad',
    commercial = 'lkw', industrial = 'lkw',
    cycles = 'sonstiges', boats = 'sonstiges', helicopters = 'sonstiges', planes = 'sonstiges',
    trains = 'sonstiges', military = 'sonstiges',
}

local function ClassFor(category, kind)
    if kind == 'boat' or kind == 'heli' or kind == 'plane' or kind == 'aircraft' then
        return 'sonstiges'
    end
    if category then
        return classByCategory[tostring(category):lower()] or 'pkw'
    end
    return nil
end

-- ========================================
-- QBCORE / QBOX
-- ========================================

local function QbVehicleCatalog()
    if GetResourceState('qbx_core') == 'started' then
        local ok, list = pcall(function() return exports.qbx_core:GetVehiclesByName() end)
        if ok and type(list) == 'table' then return list end
    end
    local core = Bridge.Framework()
    return core and core.Shared and core.Shared.Vehicles or {}
end

local function QbPerson(citizenid, charinfo)
    charinfo = DecodeJson(charinfo) or {}
    return {
        char_id = Text(citizenid),
        first_name = Text(charinfo.firstname),
        last_name = Text(charinfo.lastname),
        birth_date = BirthDate(charinfo.birthdate),
        gender = Gender(charinfo.gender),
        phone = Text(charinfo.phone),
    }
end

local function QbVehicle(row, catalog)
    local spawn = Text(row.vehicle) or ''
    local info = catalog[spawn] or catalog[spawn:lower()]
    local label = info and Text(((info.brand or '') .. ' ' .. (info.name or ''))) or nil
    return {
        external_id = 'qb:' .. tostring(row.id),
        plate = Text(row.plate),
        model = label or (spawn ~= '' and spawn or 'Unbekannt'),
        vehicle_class = ClassFor(info and info.category, nil),
        owner_char_id = Text(row.citizenid),
    }
end

local QB = {}

function QB.Persons(where, params)
    local rows = Bridge.Query('SELECT citizenid, charinfo FROM players' .. (where or ''), params) or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[#list + 1] = QbPerson(row.citizenid, row.charinfo)
    end
    return list
end

function QB.Vehicles(where, params)
    local rows = Bridge.Query('SELECT id, citizenid, vehicle, plate FROM player_vehicles' .. (where or ''), params) or {}
    local catalog = QbVehicleCatalog()
    local list = {}
    for _, row in ipairs(rows) do
        list[#list + 1] = QbVehicle(row, catalog)
    end
    return list
end

function QB.CharIdOf(src)
    local core = Bridge.Framework()
    local player = core and core.Functions.GetPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid
end

-- ========================================
-- ESX
-- ========================================

local ESX = {}

local function Unsigned(hash)
    hash = tonumber(hash)
    if not hash then return nil end
    return math.tointeger(hash % 4294967296)
end

-- model hash -> { name, category } from esx_vehicleshop's vehicles table
local function EsxVehicleCatalog()
    local catalog = {}
    if not Bridge.HasTable('vehicles') then
        return catalog
    end
    local hasCategory = Bridge.HasColumn('vehicles', 'category')
    local rows = Bridge.Query('SELECT name, model' .. (hasCategory and ', category' or '') .. ' FROM vehicles') or {}
    for _, row in ipairs(rows) do
        if row.model then
            catalog[Unsigned(GetHashKey(row.model))] = { name = Text(row.name), category = row.category }
        end
    end
    return catalog
end

function ESX.Persons(where, params)
    local phone = Bridge.HasColumn('users', 'phone_number') and ', phone_number' or ''
    local rows = Bridge.Query('SELECT identifier, firstname, lastname, dateofbirth, sex' .. phone .. ' FROM users' .. (where or ''), params) or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[#list + 1] = {
            char_id = Text(row.identifier),
            first_name = Text(row.firstname),
            last_name = Text(row.lastname),
            birth_date = BirthDate(row.dateofbirth),
            gender = Gender(row.sex),
            phone = Text(row.phone_number),
        }
    end
    return list
end

function ESX.Vehicles(where, params)
    local kind = Bridge.HasColumn('owned_vehicles', 'type') and ', type' or ''
    local rows = Bridge.Query('SELECT owner, plate, vehicle' .. kind .. ' FROM owned_vehicles' .. (where or ''), params) or {}
    local catalog = EsxVehicleCatalog()
    local list = {}
    for _, row in ipairs(rows) do
        local props = DecodeJson(row.vehicle) or {}
        local info = catalog[Unsigned(props.model)]
        local plate = Text(row.plate) or Text(props.plate)
        list[#list + 1] = {
            external_id = 'esx:' .. tostring(plate or ''):gsub('%s+', ''),
            plate = plate,
            model = (info and info.name) or (props.model and ('Modell ' .. tostring(props.model))) or 'Unbekannt',
            vehicle_class = ClassFor(info and info.category, row.type),
            owner_char_id = Text(row.owner),
        }
    end
    return list
end

function ESX.CharIdOf(src)
    local core = Bridge.Framework()
    local xPlayer = core and core.GetPlayerFromId(src)
    return xPlayer and xPlayer.identifier
end

local function Adapter()
    local _, name = Bridge.Framework()
    if name == 'qbcore' then return QB, 'citizenid', 'citizenid' end
    if name == 'esx' then return ESX, 'identifier', 'owner' end
    return nil
end

-- ========================================
-- SENDING
-- ========================================

local function Skipped(kind, result)
    local skipped = result.skipped or {}
    if #skipped == 0 then return 0 end
    local reasons = {}
    for _, item in ipairs(skipped) do
        reasons[item.reason] = (reasons[item.reason] or 0) + 1
        Bridge.Debug(('Lex skipped %s %s: %s'):format(kind, tostring(item.id), tostring(item.reason)))
    end
    local parts = {}
    for reason, count in pairs(reasons) do
        parts[#parts + 1] = reason .. ' ' .. count
    end
    table.sort(parts)
    Info(('%d %s skipped by Lex (%s)'):format(#skipped, kind, table.concat(parts, ', ')))
    return #skipped
end

-- Sends a list in batches. Returns ok, totals, error message.
local function SendAll(kind, records, run)
    local size = math.max(10, math.min(200, tonumber(Cfg().BatchSize) or 100))
    local totals = { created = 0, linked = 0, updated = 0, unchanged = 0, skipped = 0 }

    for i = 1, #records, size do
        local batch = {}
        for j = i, math.min(i + size - 1, #records) do
            batch[#batch + 1] = records[j]
        end
        local ok, data, message = LexSync.Call(kind, { run = run, [kind] = batch })
        if not ok then
            return false, totals, message
        end
        for key in pairs(totals) do
            if key ~= 'skipped' then
                totals[key] = totals[key] + (tonumber(data[key]) or 0)
            end
        end
        totals.skipped = totals.skipped + Skipped(kind, data)
    end

    return true, totals, nil
end

-- ========================================
-- FULL SYNC
-- ========================================

function LexSync.FullSync(trigger)
    if state.running then
        return false, 'Ein Abgleich läuft gerade.'
    end
    if not Active() then
        return false, 'Lex-Abgleich ist aus, oder Adresse bzw. Schlüssel von Lex fehlen.'
    end
    local adapter = Adapter()
    if not adapter then
        return false, 'Kein QBCore, Qbox oder ESX gefunden.'
    end
    if not Bridge.HasDatabase() then
        return false, 'Keine Datenbank (oxmysql) gefunden.'
    end

    state.running = true
    local started = os.time()
    local ok, err = pcall(function()
        local opened, data, message = LexSync.Call('runs', { server_name = GetConvar('sv_projectName', GetConvar('sv_hostname', '')) })
        if not opened then error(message, 0) end
        local run = data.run

        local cfg = Cfg()
        local persons, vehicles = {}, {}
        if cfg.Persons then persons = adapter.Persons() end
        if cfg.Vehicles then vehicles = adapter.Vehicles() end
        Info(('full sync (%s): %d characters, %d vehicles'):format(trigger or 'manual', #persons, #vehicles))

        local sent, pTotals, pMessage = SendAll('persons', persons, run)
        if not sent then error(pMessage, 0) end
        local sentV, vTotals, vMessage = SendAll('vehicles', vehicles, run)
        if not sentV then error(vMessage, 0) end

        local finished, summary, fMessage = LexSync.Call('runs/' .. run .. '/finish', {
            retire_missing = cfg.Vehicles and cfg.FullSync.RetireMissingVehicles == true
        })
        if not finished then error(fMessage, 0) end

        state.last = {
            at = os.date('%Y-%m-%d %H:%M:%S'),
            seconds = os.time() - started,
            trigger = trigger or 'manual',
            persons = { seen = #persons, created = pTotals.created, updated = pTotals.updated + pTotals.linked, skipped = pTotals.skipped },
            vehicles = { seen = #vehicles, created = vTotals.created, updated = vTotals.updated + vTotals.linked, skipped = vTotals.skipped },
            retired = summary.run and summary.run.vehicles_retired or 0,
        }
        state.lastError = nil
        Info(('full sync done in %ds: persons %d new, %d changed; vehicles %d new, %d changed, %d retired'):format(
            state.last.seconds, pTotals.created, pTotals.updated + pTotals.linked,
            vTotals.created, vTotals.updated + vTotals.linked, state.last.retired))
    end)
    state.running = false

    if not ok then
        state.lastError = { at = os.date('%Y-%m-%d %H:%M:%S'), message = tostring(err) }
        Bridge.Warn('Lex sync failed: ' .. tostring(err))
        return false, tostring(err)
    end
    return true, state.last
end

-- ========================================
-- LIVE (login)
-- ========================================

local queue = { persons = {}, vehicles = {} }
local queued = false

-- Character ids to send with the next flush
local function Enqueue(charId)
    if charId and charId ~= '' then
        queue.persons[charId] = true
        queued = true
    end
end

local function Flush()
    if not queued or state.running or not Active() then
        return
    end
    local adapter, personKey, ownerKey = Adapter()
    if not adapter then return end

    local ids = {}
    for id in pairs(queue.persons) do ids[#ids + 1] = id end
    queue.persons, queued = {}, false

    local placeholders = {}
    for i = 1, #ids do placeholders[i] = '?' end
    local inList = ' WHERE ' .. '%s IN (' .. table.concat(placeholders, ',') .. ')'

    local cfg = Cfg()
    if cfg.Persons then
        local ok, _, message = SendAll('persons', adapter.Persons(inList:format(personKey), ids), nil)
        if not ok then
            Bridge.Warn('Lex live sync failed: ' .. tostring(message))
            state.lastError = { at = os.date('%Y-%m-%d %H:%M:%S'), message = tostring(message) }
            return
        end
    end
    if cfg.Vehicles then
        local ok, _, message = SendAll('vehicles', adapter.Vehicles(inList:format(ownerKey), ids), nil)
        if not ok then
            Bridge.Warn('Lex live sync failed: ' .. tostring(message))
            state.lastError = { at = os.date('%Y-%m-%d %H:%M:%S'), message = tostring(message) }
            return
        end
    end
    state.lastLive = { at = os.date('%Y-%m-%d %H:%M:%S'), characters = #ids }
    Bridge.Debug('Lex live sync: ' .. #ids .. ' character(s)')
end

LexSync.Flush = Flush

-- Exported: other scripts call this after a purchase, a name change or
-- anything else that should reach Lex now instead of with the next full
-- sync. Takes a player source or a character id.
function LexSync.Character(srcOrCharId)
    local charId = srcOrCharId
    if type(srcOrCharId) == 'number' then
        local adapter = Adapter()
        charId = adapter and adapter.CharIdOf(srcOrCharId)
    end
    Enqueue(charId and tostring(charId))
end

local function OnLogin(charId)
    if Active() and Cfg().SyncOnLogin then
        Enqueue(charId and tostring(charId))
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    OnLogin(player and player.PlayerData and player.PlayerData.citizenid)
end)

AddEventHandler('esx:playerLoaded', function(_, xPlayer)
    OnLogin(xPlayer and xPlayer.identifier)
end)

CreateThread(function()
    while true do
        Wait(5000)
        local ok, err = pcall(Flush)
        if not ok then
            Bridge.Warn('Lex live sync error: ' .. tostring(err))
        end
    end
end)

-- ========================================
-- SCHEDULE
-- ========================================

CreateThread(function()
    Wait(60000) -- the framework and the database need a moment
    local cfg = Cfg()
    if Active() and cfg.FullSync.OnStart then
        LexSync.FullSync('start')
    end

    local lastFull = os.time()
    while true do
        Wait(60000)
        cfg = Cfg()
        local minutes = tonumber(cfg.FullSync.IntervalMinutes) or 0
        if Active() and minutes > 0 and os.time() - lastFull >= minutes * 60 then
            lastFull = os.time()
            LexSync.FullSync('interval')
        end
    end
end)

-- ========================================
-- STATUS, TEST, EXPORTS
-- ========================================

function LexSync.Status()
    return {
        enabled = Cfg().Enabled == true,
        keySet = Bridge.LexKeySet(),
        running = state.running,
        last = state.last,
        lastError = state.lastError,
        lastLive = state.lastLive,
    }
end

function LexSync.Test()
    if (Cfg().BaseURL or '') == '' then
        return false, 'Die Adresse von Lex fehlt.'
    end
    if not Bridge.LexKeySet() then
        return false, 'Der API-Schlüssel von Lex fehlt.'
    end
    local ok, data, message = LexSync.Call('ping', {})
    if ok then
        return true, ('Lex %s erreichbar, Schlüssel passt.'):format(tostring(data.version or '?'))
    end
    return false, message
end

-- Runs the full sync in its own thread, so exports and events return at
-- once
function LexSync.StartFullSync(trigger)
    if state.running then
        return false
    end
    CreateThread(function()
        LexSync.FullSync(trigger)
    end)
    return true
end

exports('LexSyncCharacter', LexSync.Character)
exports('LexFullSync', function() return LexSync.StartFullSync('export') end)
