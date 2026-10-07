-- Settings, admin panel and the Lex sync with stubbed FiveM natives, a
-- stubbed framework database and a stubbed Lex.
--
--   lua tests/bridge_check.lua    (Lua 5.4, no FiveM needed)
local root = arg[0]:gsub("[^/\\]+$", "") .. "../"

local handlers, clientEvents, printed, requests, commands = {}, {}, {}, {}, {}
local kvp, aceAllowed = {}, {}
local now = 1000000
os.time = function() return now end

for _, name in ipairs({ "CreateThread", "RegisterKeyMapping", "SetNuiFocus", "SetNuiFocusKeepInput" }) do
    _G[name] = function() end
end
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterServerEvent() end
function RegisterNetEvent() end
local listeners = {}
function AddEventHandler(name, fn)
    local file = debug.getinfo(2, 'S').source
    listeners[name] = listeners[name] or {}
    listeners[name][file] = fn
    handlers[name] = function(...)
        for _, f in pairs(listeners[name]) do f(...) end
    end
end
function TriggerClientEvent(name, target, ...)
    clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } }
end
function TriggerEvent() end
function IsPlayerAceAllowed(src, perm) return aceAllowed[src] == perm end
function GetPlayerName(src) return "Spieler" .. src end
function GetCurrentResourceName() return "ef_bridge" end
function GetResourceMetadata() return '2026.3.0' end
function SetResourceKvp(key, value) kvp[key] = value end
function GetResourceKvpString(key) return kvp[key] end
function GetConvar(_, default) return default end
function GetPlayerIdentifierByType() return nil end
function GetHashKey(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 4294967296 end
    return h - (h >= 2147483648 and 4294967296 or 0) -- signed like the native
end

-- promises resolve synchronously here, every callback runs right away
promise = { new = function() return { resolve = function(self, v) self.value = v end } end }
Citizen = { Await = function(p) return p.value end }

-- json: encode stores the table and hands out a token, decode gives it
-- back. Tests look at the tables, not at JSON text.
local store, counter = {}, 0
json = {
    encode = function(t)
        counter = counter + 1
        local token = "json#" .. counter
        store[token] = t
        return token
    end,
    decode = function(s)
        if store[s] == nil then error("invalid json") end
        return store[s]
    end,
}

-- framework database
local started = { ['qb-core'] = true, oxmysql = true }
function GetResourceState(name) return started[name] and 'started' or 'missing' end
local tables = {}
local queries = {}
local function answer(query, params)
    queries[#queries + 1] = { query = query, params = params }
    if query:find('information_schema.COLUMNS', 1, true) then
        local t = tables[params[1]]
        return { { count = (t and t.columns and t.columns[params[2]]) and 1 or 0 } }
    end
    if query:find('information_schema.TABLES', 1, true) then
        return { { count = tables[params[1]] and 1 or 0 } }
    end
    for name, t in pairs(tables) do
        if query:find('FROM ' .. name, 1, true) then
            if params and #params > 0 and t.key then
                local wanted, rows = {}, {}
                for _, p in ipairs(params) do wanted[p] = true end
                for _, row in ipairs(t.rows) do
                    if wanted[row[t.key]] then rows[#rows + 1] = row end
                end
                return rows
            end
            return t.rows
        end
    end
    return {}
end
local QBCore = { Functions = { GetPlayer = function() return nil end }, Shared = { Vehicles = {
    sultan = { brand = 'Karin', name = 'Sultan', category = 'sports' },
    bati = { brand = 'Pegassi', name = 'Bati 801', category = 'motorcycles' },
} } }
local ESX = { GetPlayerFromId = function() return nil end }
exports = setmetatable({
    ['qb-core'] = { GetCoreObject = function() return QBCore end },
    ['es_extended'] = { getSharedObject = function() return ESX end },
    oxmysql = { execute = function(_, query, params, cb) cb(answer(query, params)) end },
}, { __call = function() end })

-- Lex
local lex = {}
function PerformHttpRequest(url, cb, method, body, headers)
    local decoded = store[body] or {}
    requests[#requests + 1] = { url = url, body = decoded, headers = headers }
    local path = url:match('/api/v1/fivem/(.*)$') or url
    local status, response = 200, { success = true }
    local handler = lex[path] or (path:match('/finish$') and lex.finish)
    if handler then status, response = handler(decoded) end
    cb(status, json.encode(response), {})
end

local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local failed = 0
local function check(label, cond)
    realPrint((cond and "ok   " or "FAIL ") .. label)
    if not cond then failed = failed + 1 end
end
local function printedContains(text)
    for _, line in ipairs(printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
local function lastEvent(name)
    for i = #clientEvents, 1, -1 do
        if clientEvents[i].name == name then return clientEvents[i] end
    end
end

local function boot()
    dofile(root .. "config.lua")
    dofile(root .. "config_server.lua")
    dofile(root .. "shared/url.lua")
    dofile(root .. "shared/settings.lua")
    Config.Ignis.BaseURL = "https://ignis.test/"
    ServerConfig.Ignis.APIKey = "ignis-key"
    ServerConfig.Lex.Enabled = true
    ServerConfig.Lex.BaseURL = "https://lex.test/"
    ServerConfig.Lex.APIKey = "lex_key"
    for _, file in ipairs({ "core", "main", "emd_sync", "enotf_billing", "billing-custom", "lex_sync", "admin" }) do
        dofile(root .. "server/" .. file .. ".lua")
    end
end
boot()

-- ===== validation =====

local V = Settings.Validate
local by = Settings.ByKey
check("url needs https", V(by['Ignis.BaseURL'], 'http://ignis.test/') == nil)
check("url gets its trailing slash", V(by['Ignis.BaseURL'], 'https://ignis.test') == 'https://ignis.test/')
check("url rejects quotes", V(by['Lex.BaseURL'], 'https://lex.test/"><x') == nil)
check("number below min", V(by['Lex.BatchSize'], 5) == nil)
check("number above max", V(by['Lex.BatchSize'], 500) == nil)
check("number from text", V(by['Lex.BatchSize'], '50') == 50)
check("no fractions", V(by['EMDSync.HeartbeatInterval'], 1500.5) == nil)
check("boolean must be boolean", V(by['Debug'], 'yes') == nil and V(by['Debug'], false) == false)
check("select must be an option", V(by['Framework'], 'vrp') == nil and V(by['Framework'], 'esx') == 'esx')
local jobs = V(by['Tablets.eNOTF.AllowedJobs'], { ' ambulance ', '', 'doj' })
check("list trims and drops empty lines", jobs and #jobs == 2 and jobs[1] == 'ambulance')
check("list rejects odd characters", V(by['Tablets.eNOTF.AllowedJobs'], { 'a b' }) == nil)
check("table name can't carry SQL", V(by['EMDSync.StatusSync.SourceTable'], 'emd_dispatchlog; DROP TABLE users') == nil)
check("optional string may be empty", V(by['Tablets.eNOTF.OpenKey'], '') == false)
check("required string may not be empty", V(by['Tablets.eNOTF.Command'], ' ') == nil)
check("no API key in the schema", by['Ignis.APIKey'] == nil and by['Lex.APIKey'] == nil)

-- ===== admin panel =====

clientEvents = {}
source = 5
handlers['ef_bridge:admin:open']()
check("panel: no ACE, no data", lastEvent('ef_bridge:admin:data') == nil and lastEvent('ef_bridge:admin:denied').target == 5)
handlers['ef_bridge:admin:save']({ Debug = true }, {})
check("panel: no ACE, nothing saved", Config.Debug == false and kvp['settings:overrides'] == nil)

aceAllowed[6] = 'ef_bridge.admin'
source = 6
handlers['ef_bridge:admin:open']()
local data = lastEvent('ef_bridge:admin:data')
check("panel: with ACE the data goes to that player", data and data.target == 6)
data = data and data.args[1] or {}
check("panel: status says the keys are set", data.status and data.status.ignisKeySet and data.status.lex.keySet)
local leaked = false
for _, entry in ipairs(data.schema or {}) do
    if entry.key:find('APIKey') then leaked = true end
end
check("panel: schema without API keys", #(data.schema or {}) > 20 and not leaked)

clientEvents = {}
handlers['ef_bridge:admin:save']({
    ['Tablets.eNOTF.AllowedJobs'] = { 'ambulance', 'doj' },
    ['Tablets.eNOTF.Command'] = 'notarzt',
    ['Lex.BatchSize'] = 500,
    ['Lex.FullSync.IntervalMinutes'] = 60,
    ['Nope'] = 1,
}, {})
local saved = lastEvent('ef_bridge:admin:saved').args[1]
check("save: valid values applied", Config.Tablets.eNOTF.AllowedJobs[2] == 'doj' and ServerConfig.Lex.FullSync.IntervalMinutes == 60)
check("save: invalid value refused with a message", saved.errors['Lex.BatchSize'] and ServerConfig.Lex.BatchSize == 100)
check("save: unknown key refused", saved.errors['Nope'] ~= nil)
check("save: command change needs a restart", saved.restart == true)
check("save: state marks the change", saved.state['Lex.FullSync.IntervalMinutes'].changed == true
    and saved.state['Lex.FullSync.IntervalMinutes'].default == 360)
local broadcast = lastEvent('ef_bridge:settings')
check("save: shared values go to every client", broadcast and broadcast.target == -1
    and broadcast.args[1]['Tablets.eNOTF.Command'] == 'notarzt')
check("save: server values stay on the server", broadcast.args[1]['Lex.FullSync.IntervalMinutes'] == nil
    and broadcast.args[1]['Lex.BaseURL'] == nil)
check("save: logged with the player", printedContains("Spieler6 (6) changed"))

boot()
check("restart: changes come back from the KVP store", Config.Tablets.eNOTF.Command == 'notarzt'
    and ServerConfig.Lex.FullSync.IntervalMinutes == 60)

source = 6
handlers['ef_bridge:admin:save']({}, { 'Tablets.eNOTF.Command' })
check("reset: back to the config file", Config.Tablets.eNOTF.Command == 'enotf')
boot()
check("reset: stays reset after a restart", Config.Tablets.eNOTF.Command == 'enotf')

commands['efbridge'](0, { 'set', 'Debug', 'on' })
check("console: set", Config.Debug == true)
commands['efbridge'](0, { 'set', 'Tablets.FireTab.AllowedJobs', 'fire,', 'thw' })
check("console: lists comma separated", Config.Tablets.FireTab.AllowedJobs[2] == 'thw')
commands['efbridge'](0, { 'set', 'Lex.BatchSize', '9999' })
check("console: invalid value reported", printedContains("Lex.BatchSize: Erlaubt"))
commands['efbridge'](0, { 'reset', 'Debug' })
check("console: reset", Config.Debug == false)

-- ===== legacy config =====

dofile(root .. "config.lua")
dofile(root .. "config_server.lua")
Config.Ignis, Config.Tablets = nil, nil
Config.BaseURL = "https://old.test/"
Config.TabletLogin = { Enabled = true }
Config.eNOTF = { Enabled = true, Command = 'enotf', AllowedJobs = { 'ambulance' } }
Config.EMDSync = { Enabled = true, HeartbeatInterval = 5000 }
ServerConfig.Ignis, ServerConfig.EMDSync = nil, nil
ServerConfig.APIKey = "old-key"
local notes = Settings.MigrateLegacy(true)
check("legacy: base url moved", Config.Ignis.BaseURL == "https://old.test/" and Config.BaseURL == nil)
check("legacy: tablet login moved", Config.Ignis.TabletLogin == true)
check("legacy: tablet moved and gets its page", Config.Tablets.eNOTF.Command == 'enotf' and Config.Tablets.eNOTF.Path == 'enotf/overview.php')
check("legacy: missing FireTab is off", Config.Tablets.FireTab.Enabled == false)
check("legacy: EMD sync moved to the server", ServerConfig.EMDSync.Enabled == true and Config.EMDSync == nil)
check("legacy: key moved", ServerConfig.Ignis.APIKey == "old-key")
check("legacy: every move is reported", #notes >= 5)
boot()

-- ===== Lex full sync =====

tables.players = { key = 'citizenid', rows = {} }
for i = 1, 25 do
    tables.players.rows[i] = { citizenid = 'C' .. i, charinfo = { firstname = 'Max' .. i, lastname = 'Muster', birthdate = '15/01/1990', gender = 1, phone = '555' .. i } }
end
tables.player_vehicles = { key = 'citizenid', rows = {
    { id = 7, citizenid = 'C1', vehicle = 'sultan', plate = 'AB 123' },
    { id = 8, citizenid = 'C2', vehicle = 'bati', plate = 'CD 456' },
    { id = 9, citizenid = 'C3', vehicle = 'unknowncar', plate = 'EF 789' },
} }
lex.runs = function() return 201, { success = true, run = 'abc' } end
lex.persons = function(body) return 200, { success = true, created = #body.persons, skipped = {} } end
lex.vehicles = function(body)
    return 200, { success = true, created = #body.vehicles - 1, updated = 1, skipped = { { index = 0, id = 'qb:9', reason = 'plate_taken' } } }
end
lex.finish = function() return 200, { success = true, run = { vehicles_retired = 2 } } end

ServerConfig.Lex.BatchSize = 10
requests, printed = {}, {}
local ok, summary = LexSync.FullSync('test')
check("full sync succeeds", ok == true)
local paths = {}
for _, r in ipairs(requests) do paths[#paths + 1] = r.url:match('fivem/(.*)$') end
check("order: run, persons in batches, vehicles, finish", table.concat(paths, ',') == 'runs,persons,persons,persons,vehicles,runs/abc/finish')
check("Lex url and key header", requests[1].url == 'https://lex.test/api/v1/fivem/runs' and requests[1].headers['X-API-Key'] == 'lex_key')
check("batches carry the run", requests[2].body.run == 'abc' and #requests[2].body.persons == 10 and #requests[4].body.persons == 5)
local p = requests[2].body.persons[1]
check("person mapping", p.char_id == 'C1' and p.first_name == 'Max1' and p.birth_date == '1990-01-15' and p.gender == 'w' and p.phone == '5551')
local v = requests[5].body.vehicles
check("vehicle mapping", v[1].external_id == 'qb:7' and v[1].model == 'Karin Sultan' and v[1].plate == 'AB 123'
    and v[1].owner_char_id == 'C1' and v[1].vehicle_class == 'pkw')
check("motorcycle class", v[2].vehicle_class == 'motorrad')
check("unknown model falls back to the spawn name", v[3].model == 'unknowncar' and v[3].vehicle_class == nil)
check("finish asks to retire missing vehicles", requests[6].body.retire_missing == true)
check("summary for the panel", summary.persons.created == 25 and summary.vehicles.skipped == 1 and summary.retired == 2)
check("skips are reported in the console", printedContains("1 vehicles skipped by Lex (plate_taken 1)"))

ServerConfig.Lex.FullSync.RetireMissingVehicles = false
requests = {}
LexSync.FullSync('test')
check("retire switch off", requests[#requests].body.retire_missing == false)
ServerConfig.Lex.FullSync.RetireMissingVehicles = true

lex.persons = function() return 401, { success = false, error = 'invalid_key', message = 'Der Schlüssel passt nicht.' } end
requests = {}
ok, summary = LexSync.FullSync('test')
check("rejected key: sync fails with a hint", ok == false and summary:find('ServerConfig.Lex.APIKey', 1, true))
check("rejected key: no finish", not requests[#requests].url:find('finish'))
check("rejected key: shown in the status", LexSync.Status().lastError.message:find('ServerConfig.Lex.APIKey', 1, true) ~= nil)
lex.persons = function(body) return 200, { success = true, created = #body.persons, skipped = {} } end

ServerConfig.Lex.Enabled = false
requests = {}
ok = LexSync.FullSync('test')
check("switched off: nothing sent", ok == false and #requests == 0)
ServerConfig.Lex.Enabled = true

-- ===== Lex live sync =====

requests, queries = {}, {}
handlers['QBCore:Server:PlayerLoaded']({ PlayerData = { source = 3, citizenid = 'C3' } })
check("login: nothing sent right away", #requests == 0)
LexSync.Flush()
check("login: the character and their vehicles go out", #requests == 2 and requests[1].body.run == nil
    and #requests[1].body.persons == 1 and requests[1].body.persons[1].char_id == 'C3'
    and #requests[2].body.vehicles == 1 and requests[2].body.vehicles[1].external_id == 'qb:9')
local usedWhere = false
for _, q in ipairs(queries) do
    if q.query:find('WHERE citizenid IN (?)', 1, true) and q.params[1] == 'C3' then usedWhere = true end
end
check("login: only that character is read from the database", usedWhere)
requests = {}
LexSync.Flush()
check("login: queue is empty afterwards", #requests == 0)

ServerConfig.Lex.SyncOnLogin = false
handlers['QBCore:Server:PlayerLoaded']({ PlayerData = { source = 4, citizenid = 'C4' } })
LexSync.Flush()
check("login sync switched off", #requests == 0)
ServerConfig.Lex.SyncOnLogin = true

handlers['esx:playerLoaded'](4, { identifier = 'C4' })
LexSync.Flush()
check("ESX login event queues the identifier", #requests >= 1 and requests[1].body.persons[1].char_id == 'C4')

-- ===== ESX =====

started['qb-core'], started['es_extended'] = nil, true
tables.players, tables.player_vehicles = nil, nil
boot()
tables.users = { key = 'identifier', columns = { phone_number = true }, rows = {
    { identifier = 'char1:abc', firstname = 'Erika', lastname = 'Brand', dateofbirth = '1985-03-02', sex = 'f', phone_number = 5551234 },
} }
tables.owned_vehicles = { key = 'owner', columns = { type = true }, rows = {
    { owner = 'char1:abc', plate = 'XY 12 ', vehicle = { model = GetHashKey('blista'), plate = 'XY 12' }, type = 'car' },
    { owner = 'char1:abc', plate = 'BOAT1', vehicle = { model = 123 }, type = 'boat' },
} }
tables.vehicles = { columns = { category = true }, rows = { { name = 'Dinka Blista', model = 'blista', category = 'compacts' } } }
requests = {}
ok = LexSync.FullSync('test')
check("ESX: full sync succeeds", ok == true)
p = requests[2].body.persons[1]
check("ESX: person mapping", p.char_id == 'char1:abc' and p.gender == 'w' and p.birth_date == '1985-03-02' and p.phone == '5551234')
v = requests[3].body.vehicles
check("ESX: model name from the vehicles table by hash", v[1].model == 'Dinka Blista' and v[1].vehicle_class == 'pkw')
check("ESX: external id from the plate", v[1].external_id == 'esx:XY12' and v[1].owner_char_id == 'char1:abc')
check("ESX: boats are 'sonstiges'", v[2].vehicle_class == 'sonstiges' and v[2].model == 'Modell 123')

realPrint(failed == 0 and "all checks passed" or (failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
