-- Shared server plumbing for every module: version, console output,
-- framework, database, HTTP and the settings that the admin panel can
-- change at runtime.

Bridge = {}

Bridge.Resource = GetCurrentResourceName()
-- Release builds get the version from the tag (build-release.yml)
Bridge.Version = GetResourceMetadata(Bridge.Resource, 'version', 0) or 'dev'
Bridge.UserAgent = 'FiveM-ef_bridge/' .. Bridge.Version

function Bridge.Print(message)
    print('^2[ef_bridge]^7 ' .. message)
end

function Bridge.Warn(message)
    print('^1[ef_bridge]^7 ' .. message)
end

function Bridge.Debug(message)
    if Config.Debug then
        print('^3[ef_bridge]^7 ' .. message)
    end
end

-- ========================================
-- API KEYS
-- ========================================

local function KeySet(key)
    return type(key) == 'string' and key ~= '' and key ~= 'CHANGE_ME'
end

function Bridge.IgnisKey()
    return ServerConfig.Ignis and ServerConfig.Ignis.APIKey
end

function Bridge.IgnisKeySet()
    return KeySet(Bridge.IgnisKey())
end

function Bridge.LexKeySet()
    return KeySet(ServerConfig.Lex and ServerConfig.Lex.APIKey)
end

-- ========================================
-- PERMISSIONS
-- ========================================

-- The server console (source 0) may always
function Bridge.IsAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.Admin.Ace)
end

-- ========================================
-- FRAMEWORK
-- ========================================
-- Detected on first use, because ef_bridge may start before qb-core or
-- es_extended. Qbox ships a qb-core bridge and counts as QBCore.

local Framework, FrameworkName

function Bridge.Framework()
    if not FrameworkName then
        local wanted = Config.Framework
        if wanted == 'qbcore' or (wanted == 'auto' and GetResourceState('qb-core') == 'started') then
            Framework, FrameworkName = exports['qb-core']:GetCoreObject(), 'qbcore'
        elseif wanted == 'esx' or (wanted == 'auto' and GetResourceState('es_extended') == 'started') then
            Framework, FrameworkName = exports['es_extended']:getSharedObject(), 'esx'
        end
    end
    return Framework, FrameworkName
end

-- Name, job and character id from the framework on the server, never
-- from the client
function Bridge.GetCharacter(src)
    local core, name = Bridge.Framework()

    if name == 'qbcore' then
        local player = core.Functions.GetPlayer(src)
        local data = player and player.PlayerData
        if data and data.charinfo then
            return {
                name = (data.charinfo.firstname or '') .. ' ' .. (data.charinfo.lastname or ''),
                job = data.job and data.job.name or '',
                cid = data.citizenid
            }
        end
    elseif name == 'esx' then
        local xPlayer = core.GetPlayerFromId(src)
        if xPlayer then
            local first, last = xPlayer.get('firstName'), xPlayer.get('lastName')
            return {
                name = (first and last) and (first .. ' ' .. last) or xPlayer.getName(),
                job = xPlayer.job and xPlayer.job.name or '',
                cid = xPlayer.identifier
            }
        end
    end

    return nil
end

-- ========================================
-- DATABASE
-- ========================================

function Bridge.HasDatabase()
    return GetResourceState('oxmysql') == 'started' or (MySQL ~= nil and MySQL.Async ~= nil)
end

-- Rows for a SELECT, nil without a database or on an error
function Bridge.Query(query, parameters)
    local p = promise.new()
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute(query, parameters or {}, function(result)
            p:resolve(result)
        end)
    elseif MySQL and MySQL.Async then
        -- mysql-async fallback for older ESX setups
        MySQL.Async.fetchAll(query, parameters or {}, function(result)
            p:resolve(result)
        end)
    else
        Bridge.Debug('no MySQL resource found, install oxmysql')
        p:resolve(nil)
    end
    return Citizen.Await(p)
end

local columnCache = {}

-- Whether a table has a column. Framework tables differ between versions
-- and add-ons (phone_number in ESX users, for one).
function Bridge.HasColumn(tableName, column)
    local key = tableName .. '.' .. column
    if columnCache[key] == nil then
        local rows = Bridge.Query([[
            SELECT COUNT(*) AS count FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
        ]], { tableName, column })
        columnCache[key] = rows ~= nil and rows[1] ~= nil and tonumber(rows[1].count) > 0
    end
    return columnCache[key]
end

function Bridge.HasTable(tableName)
    local rows = Bridge.Query([[
        SELECT COUNT(*) AS count FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { tableName })
    return rows ~= nil and rows[1] ~= nil and tonumber(rows[1].count) > 0
end

-- ========================================
-- HTTP
-- ========================================

-- JSON request, waits for the answer. Returns status code, decoded body
-- (a table, empty if the body was no JSON object) and the raw body.
function Bridge.Request(url, method, body, headers)
    local p = promise.new()
    local sendHeaders = {
        ['Content-Type'] = 'application/json',
        ['Accept'] = 'application/json',
        ['User-Agent'] = Bridge.UserAgent
    }
    for k, v in pairs(headers or {}) do
        sendHeaders[k] = v
    end

    PerformHttpRequest(url, function(status, response)
        local ok, data = pcall(json.decode, response or '')
        p:resolve({ tonumber(status) or 0, (ok and type(data) == 'table') and data or {}, response })
    end, method or 'POST', body ~= nil and json.encode(body) or '', sendHeaders)

    local result = Citizen.Await(p)
    return result[1], result[2], result[3]
end

-- ========================================
-- SETTINGS
-- ========================================
-- The defaults come from shared/defaults.lua and server/defaults.lua, the
-- admin panel, the console and imports lay their changes over them. Changes
-- live in the server's resource KVP store, so they survive a restart and
-- an update that replaces the resource folder. API keys are stored there
-- too; KVP never leaves the server.

local OverridesKvp = 'settings:overrides'
local defaults = {}
local overrides = {}

local function Copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Copy(v)
    end
    return copy
end
Bridge.Copy = Copy

for _, entry in ipairs(Settings.Schema) do
    defaults[entry.key] = Copy(Settings.Raw(entry))
end

local function SaveOverrides()
    SetResourceKvp(OverridesKvp, json.encode(overrides))
end

-- true once anything was ever saved; a fresh server may import old files
Bridge.HasStoredSettings = GetResourceKvpString(OverridesKvp) ~= nil

-- after an automatic import that changed nothing: don't import again on
-- every start
function Bridge.MarkSettingsStored()
    if not Bridge.HasStoredSettings then
        SaveOverrides()
        Bridge.HasStoredSettings = true
    end
end

do
    local raw = GetResourceKvpString(OverridesKvp)
    local ok, stored = pcall(json.decode, raw or '')
    if ok and type(stored) == 'table' then
        for key, value in pairs(stored) do
            local entry = Settings.ByKey[key]
            local clean = entry and Settings.Validate(entry, value)
            if clean ~= nil then
                overrides[key] = clean
                Settings.Write(entry, clean)
            end
        end
    end
end

-- Values of every shared entry, for the clients
function Bridge.SharedSettings()
    local values = {}
    for _, entry in ipairs(Settings.Schema) do
        if entry.scope == 'shared' then
            values[entry.key] = Settings.Read(entry)
        end
    end
    return values
end

-- What the panel shows per entry. Secrets come as "set or not", their
-- default as false.
function Bridge.SettingsState()
    local state = {}
    for _, entry in ipairs(Settings.Schema) do
        local default = defaults[entry.key]
        if entry.type == 'secret' then
            default = false
        elseif default == nil then
            default = false
        end
        state[entry.key] = {
            value = Settings.Read(entry),
            default = default,
            changed = overrides[entry.key] ~= nil
        }
    end
    return state
end

-- Applies changes. `changes` maps keys to new values, `resets` lists keys
-- that go back to the default (for a key: cleared). Returns the applied
-- keys, the errors per key and whether a restart is needed. The log names
-- the keys, never a value.
function Bridge.ApplySettings(changes, resets, actor)
    local applied, errors, restart = {}, {}, false

    local function apply(entry, value, isReset)
        Settings.Write(entry, value)
        if isReset then
            overrides[entry.key] = nil
        else
            overrides[entry.key] = value
        end
        applied[#applied + 1] = entry.key
        if entry.restart then
            restart = true
        end
    end

    for _, key in ipairs(type(resets) == 'table' and resets or {}) do
        local entry = Settings.ByKey[key]
        if entry then
            local value = Copy(defaults[key])
            apply(entry, value == nil and false or value, true)
        end
    end

    for key, value in pairs(type(changes) == 'table' and changes or {}) do
        local entry = Settings.ByKey[key]
        if not entry then
            errors[key] = 'Diese Einstellung gibt es nicht.'
        else
            local clean, message = Settings.Validate(entry, value)
            if clean == nil then
                errors[key] = message
            else
                apply(entry, clean, false)
            end
        end
    end

    if #applied > 0 then
        SaveOverrides()
        Bridge.HasStoredSettings = true
        TriggerClientEvent('ef_bridge:settings', -1, Bridge.SharedSettings())
        table.sort(applied)
        Bridge.Print(('%s changed %s'):format(actor or 'console', table.concat(applied, ', ')))
    end

    return applied, errors, restart
end

-- Clients ask once when their script starts
local settingsAsked = {}
RegisterNetEvent('ef_bridge:settings:request')
AddEventHandler('ef_bridge:settings:request', function()
    local src = source
    if settingsAsked[src] and os.time() - settingsAsked[src] < 10 then
        return
    end
    settingsAsked[src] = os.time()
    TriggerClientEvent('ef_bridge:settings', src, Bridge.SharedSettings())
end)

AddEventHandler('playerDropped', function()
    settingsAsked[source] = nil
end)
