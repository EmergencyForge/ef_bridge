-- Admin panel (/efbridge) and console command. Everything here needs the
-- ACE from Config.Admin.Ace (ef_bridge.admin), checked again on every
-- event: a client can fire any event, the panel being closed is no
-- protection.
--
-- Console (txAdmin, server terminal), the way to set up a server before
-- anyone can join:
--   efbridge status                   what runs, which keys are set
--   efbridge list [group]             every setting with its value
--   efbridge get <setting>            one setting
--   efbridge set <setting> <value>    change it (lists: comma separated)
--   efbridge reset <setting>          back to the default
--   efbridge key <ignis|lex> <key>    set an API key, `clear` removes it
--   efbridge import                   take over config files from the folder
--   efbridge export                   changed settings to settings-export.json
--   efbridge lexsync                  full sync with Lex now
--   efbridge test                     check the connection to ignis and Lex

local function Status()
    local _, frameworkName = Bridge.Framework()
    return {
        version = Bridge.Version,
        resource = Bridge.Resource,
        framework = frameworkName or false,
        database = Bridge.HasDatabase(),
        ignisKeySet = Bridge.IgnisKeySet(),
        emd = ServerConfig.EMDSync.Enabled == true,
        billing = ServerConfig.ENOTFBilling.Enabled == true,
        lex = LexSync.Status(),
    }
end

-- The schema without functions, ready for json
local function SchemaForPanel()
    local list = {}
    for _, entry in ipairs(Settings.Schema) do
        list[#list + 1] = {
            key = entry.key, scope = entry.scope, type = entry.type, group = entry.group,
            label = entry.label, help = entry.help or false, options = entry.options or false,
            min = entry.min or false, max = entry.max or false,
            restart = entry.restart == true, optional = entry.optional == true,
            advanced = entry.advanced == true,
        }
    end
    return list
end

local function TestIgnis()
    if (Config.Ignis.BaseURL or '') == '' then
        return false, 'Die Adresse von ignis fehlt.'
    end
    if not Bridge.IgnisKeySet() then
        return false, 'Der API-Schlüssel von ignis fehlt.'
    end
    -- identify without a session: ignis checks the key first (403 when
    -- wrong, 503 when ignis has none) and then rejects the empty body with
    -- 422, so nothing changes in ignis
    local status = Bridge.Request(BuildURL('api/character/identify.php'), 'POST', { intraRP_API_Key = Bridge.IgnisKey() })
    if status == 0 then
        return false, 'ignis ist nicht erreichbar (' .. BuildURL('') .. ').'
    elseif status == 403 or status == 401 then
        return false, 'ignis lehnt den Schlüssel ab. Trag im Panel unter ignis den Schlüssel aus ignis ein.'
    elseif status == 503 then
        return false, 'In ignis ist noch kein API-Schlüssel gesetzt.'
    elseif status == 404 then
        return false, 'Unter dieser Adresse antwortet kein ignis (404).'
    elseif status >= 500 then
        return false, 'ignis antwortet mit ' .. status .. '.'
    end
    return true, 'ignis erreichbar, Schlüssel passt.'
end

local actions = {
    testIgnis = TestIgnis,
    testLex = function() return LexSync.Test() end,
    lexSync = function()
        if LexSync.StartFullSync('panel') then
            return true, 'Vollständiger Abgleich mit Lex gestartet. Das Ergebnis steht gleich im Status.'
        end
        return false, 'Ein Abgleich läuft gerade.'
    end,
    emdSync = function()
        if not ServerConfig.EMDSync.Enabled then
            return false, 'EMD-Sync ist aus.'
        end
        PerformHeartbeat(0)
        return true, 'EMD-Abgleich angestoßen.'
    end,
}

local function Deny(src)
    TriggerClientEvent('ef_bridge:admin:denied', src)
    Bridge.Warn(('admin panel denied for source %s (%s), missing ACE %s'):format(src, tostring(GetPlayerName(src)), Config.Admin.Ace))
end

RegisterNetEvent('ef_bridge:admin:open')
AddEventHandler('ef_bridge:admin:open', function()
    local src = source
    if not Bridge.IsAdmin(src) then
        return Deny(src)
    end
    TriggerClientEvent('ef_bridge:admin:data', src, {
        schema = SchemaForPanel(),
        state = Bridge.SettingsState(),
        status = Status(),
    })
end)

RegisterNetEvent('ef_bridge:admin:save')
AddEventHandler('ef_bridge:admin:save', function(changes, resets)
    local src = source
    if not Bridge.IsAdmin(src) then
        return Deny(src)
    end
    local applied, errors, restart = Bridge.ApplySettings(changes, resets, tostring(GetPlayerName(src)) .. ' (' .. src .. ')')
    TriggerClientEvent('ef_bridge:admin:saved', src, {
        applied = applied,
        errors = errors,
        restart = restart,
        state = Bridge.SettingsState(),
        status = Status(),
    })
end)

-- Import from the panel: the pasted text (or the files in the folder when
-- empty). apply = false only answers with the preview. Latent event: a
-- config file is bigger than a normal event should be.
RegisterNetEvent('ef_bridge:admin:import')
AddEventHandler('ef_bridge:admin:import', function(text, apply)
    local src = source
    if not Bridge.IsAdmin(src) then
        return Deny(src)
    end

    local sources
    if type(text) == 'string' and text:match('%S') then
        sources = { { name = 'eingefügt', code = text } }
    else
        sources = Import.FolderSources()
    end

    local plan = Import.Plan(sources)
    local applied, restart = {}, false
    if apply == true then
        applied, restart = Import.Apply(plan, tostring(GetPlayerName(src)) .. ' (' .. src .. ') import')
    end

    local errors = {}
    for key, message in pairs(plan.errors) do
        errors[#errors + 1] = { key = key, label = Settings.ByKey[key] and Settings.ByKey[key].label or key, message = message }
    end

    TriggerClientEvent('ef_bridge:admin:imported', src, {
        found = #sources,
        preview = plan.preview,
        errors = errors,
        notes = plan.notes,
        problems = plan.problems,
        applied = applied,
        restart = restart,
        state = Bridge.SettingsState(),
        status = Status(),
    })
end)

RegisterNetEvent('ef_bridge:admin:action')
AddEventHandler('ef_bridge:admin:action', function(name)
    local src = source
    if not Bridge.IsAdmin(src) then
        return Deny(src)
    end
    local action = actions[name]
    if not action then
        return
    end
    local ok, message = action()
    TriggerClientEvent('ef_bridge:admin:result', src, { action = name, ok = ok, message = message, status = Status() })
end)

-- ========================================
-- CONSOLE
-- ========================================

local function Show(value, entry)
    if entry and entry.type == 'secret' then
        return value and 'set' or 'not set'
    end
    if type(value) == 'table' then
        return table.concat(value, ', ')
    end
    if value == false then
        return 'false'
    end
    return tostring(value)
end

local function Parse(entry, raw)
    if entry.type == 'boolean' then
        if raw == 'true' or raw == 'on' or raw == '1' then return true end
        if raw == 'false' or raw == 'off' or raw == '0' then return false end
        return raw
    end
    if entry.type == 'list' then
        local list = {}
        for item in (raw or ''):gmatch('[^,]+') do
            list[#list + 1] = item
        end
        return list
    end
    return raw or ''
end

local function Reply(src, message)
    if src == 0 then
        Bridge.Print(message)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^2[ef_bridge]', message } })
    end
end

RegisterCommand(Config.Admin.Command, function(src, args)
    if src ~= 0 then
        -- players get the panel, client/admin.lua handles that
        return
    end

    local sub = args[1]
    if sub == 'status' or sub == nil then
        local s = Status()
        Reply(src, ('version %s, framework %s, database %s'):format(s.version, tostring(s.framework), s.database and 'yes' or 'no'))
        Reply(src, ('ignis key %s, EMD sync %s, billing %s'):format(s.ignisKeySet and 'set' or 'MISSING', s.emd and 'on' or 'off', s.billing and 'on' or 'off'))
        Reply(src, ('Lex %s, key %s, last full sync %s'):format(s.lex.enabled and 'on' or 'off', s.lex.keySet and 'set' or 'MISSING', s.lex.last and s.lex.last.at or 'never'))
        if s.lex.lastError then
            Reply(src, 'Lex last error ' .. s.lex.lastError.at .. ': ' .. s.lex.lastError.message)
        end
    elseif sub == 'get' and args[2] then
        local entry = Settings.ByKey[args[2]]
        Reply(src, entry and (args[2] .. ' = ' .. Show(Settings.Read(entry), entry)) or ('unknown setting ' .. args[2]))
    elseif sub == 'set' and args[2] then
        local entry = Settings.ByKey[args[2]]
        if not entry then
            return Reply(src, 'unknown setting ' .. args[2])
        end
        if entry.type == 'secret' then
            return Reply(src, 'API keys: ' .. Config.Admin.Command .. ' key ignis|lex <key>')
        end
        local raw = table.concat(args, ' ', 3)
        local _, errors, restart = Bridge.ApplySettings({ [args[2]] = Parse(entry, raw) }, nil, 'console')
        if errors[args[2]] then
            Reply(src, args[2] .. ': ' .. errors[args[2]])
        else
            Reply(src, args[2] .. ' = ' .. Show(Settings.Read(entry), entry) .. (restart and ' (takes effect after restart ' .. Bridge.Resource .. ')' or ''))
        end
    elseif sub == 'reset' and args[2] then
        if not Settings.ByKey[args[2]] then
            return Reply(src, 'unknown setting ' .. args[2])
        end
        Bridge.ApplySettings(nil, { args[2] }, 'console')
        Reply(src, args[2] .. ' = ' .. Show(Settings.Read(Settings.ByKey[args[2]]), Settings.ByKey[args[2]]))
    elseif sub == 'list' then
        local group = args[2] and table.concat(args, ' ', 2):lower()
        for _, entry in ipairs(Settings.Schema) do
            if not group or entry.group:lower() == group then
                Reply(src, ('%-40s %s'):format(entry.key, Show(Settings.Read(entry), entry)))
            end
        end
    elseif sub == 'key' and (args[2] == 'ignis' or args[2] == 'lex') and args[3] then
        local key = args[2] == 'ignis' and 'Ignis.APIKey' or 'Lex.APIKey'
        if args[3] == 'clear' then
            Bridge.ApplySettings(nil, { key }, 'console')
            return Reply(src, args[2] .. ' API key removed')
        end
        local _, errors = Bridge.ApplySettings({ [key] = args[3] }, nil, 'console')
        Reply(src, errors[key] and (args[2] .. ': ' .. errors[key]) or (args[2] .. ' API key set'))
    elseif sub == 'import' then
        local sources = Import.FolderSources()
        if #sources == 0 then
            return Reply(src, 'no config.lua, config_server.lua or settings-export.json in the resource folder')
        end
        local plan = Import.Plan(sources)
        local applied, restart = Import.Apply(plan, 'console import')
        Import.Report(plan, applied)
        if restart then
            Reply(src, 'some of it takes effect after restart ' .. Bridge.Resource)
        end
    elseif sub == 'export' then
        local ok, name = Import.Export()
        Reply(src, ok and ('changed settings written to ' .. name .. ' (without API keys)') or 'export failed')
    elseif sub == 'lexsync' then
        local started = LexSync.StartFullSync('console')
        Reply(src, started and 'Lex full sync started' or 'a Lex sync is already running')
    elseif sub == 'test' then
        CreateThread(function()
            local okI, msgI = TestIgnis()
            Reply(src, 'ignis: ' .. (okI and 'ok' or 'FAILED') .. ' - ' .. msgI)
            local okL, msgL = LexSync.Test()
            Reply(src, 'Lex: ' .. (okL and 'ok' or 'FAILED') .. ' - ' .. msgL)
        end)
    else
        Reply(src, 'usage: ' .. Config.Admin.Command .. ' status | list [group] | get <setting> | set <setting> <value> | reset <setting> | key <ignis|lex> <key|clear> | import | export | lexsync | test')
    end
end, true)
