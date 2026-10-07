-- Import of old config files and of exports.
--
-- ef_bridge has no config files any more. Who comes from ignisTab or the
-- first ef_bridge layout drops config.lua and config_server.lua into the
-- resource folder: on a server that never saved a setting they are taken
-- over once at start, later with `efbridge import` or in the panel (paste
-- the file, look at the preview, apply). An export (`efbridge export`,
-- settings-export.json) comes back the same way.
--
-- The files are run as plain Lua text in an empty environment: no access
-- to natives, exports, globals or the file system, and a step limit
-- against endless loops. They are not part of the manifest, so they never
-- reach a player.

Import = {}

local Files = { 'config.lua', 'config_server.lua', 'settings-export.json' }
local MaxSize = 64 * 1024
local ExportFormat = 'ef_bridge-settings'

-- placeholders from the shipped config files mean "not set"
local placeholders = {
    ['CHANGE_ME'] = true,
    ['https://deine-url.de/'] = true,
    ['https://deine-ignis-url.de/'] = true,
    ['https://deine-lex-url.de/'] = true,
}

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function Merge(into, from)
    for k, v in pairs(from) do
        if type(v) == 'table' and type(into[k]) == 'table' and #v == 0 then
            Merge(into[k], v)
        else
            into[k] = v
        end
    end
end

-- Runs a config file as data. Returns its environment or nil and a message.
local function RunLua(code, name)
    local env = {}
    local chunk, err = load(code, '@' .. name, 't', env)
    if not chunk then
        return nil, name .. ': lässt sich nicht lesen (' .. tostring(err) .. ')'
    end

    local hooked = false
    if debug and debug.sethook then
        hooked = pcall(debug.sethook, function() error('zu viele Schritte, ist das eine config-Datei?', 0) end, '', 1000000)
    end
    local ok, runErr = pcall(chunk)
    if hooked then
        debug.sethook()
    end
    if not ok then
        return nil, name .. ': ' .. tostring(runErr)
    end
    return env
end

-- Reads the sources ({ name, code } each) into the two config tables.
local function Collect(sources)
    local cfg, srv, flat, problems = {}, {}, {}, {}

    for _, source in ipairs(sources) do
        local code = source.code or ''
        if #code > MaxSize then
            problems[#problems + 1] = source.name .. ': größer als 64 KB'
        elseif code:match('^%s*{') then
            local ok, data = pcall(json.decode, code)
            if ok and type(data) == 'table' and data.format == ExportFormat and type(data.settings) == 'table' then
                for key, value in pairs(data.settings) do
                    flat[key] = value
                end
            else
                problems[#problems + 1] = source.name .. ': kein Export von ef_bridge'
            end
        elseif code:match('%S') then
            local env, err = RunLua(code, source.name)
            if not env then
                problems[#problems + 1] = err
            else
                if type(env.Config) == 'table' then Merge(cfg, env.Config) end
                if type(env.ServerConfig) == 'table' then Merge(srv, env.ServerConfig) end
            end
        end
    end

    local notes = Settings.MigrateLegacy(cfg, srv)
    return cfg, srv, flat, notes, problems
end

local function Shown(entry, value)
    if entry.type == 'secret' then
        return value and 'gesetzt' or 'leer'
    end
    if type(value) == 'table' then
        return table.concat(value, ', ')
    end
    if value == nil or value == false and entry.type ~= 'boolean' then
        return 'leer'
    end
    return tostring(value)
end

-- Works out what an import would change. Nothing is applied here.
-- Returns { changes = {key = value}, preview = {...}, errors = {key = msg},
-- notes = {...}, problems = {...} }.
function Import.Plan(sources)
    local cfg, srv, flat, notes, problems = Collect(sources)
    local plan = { changes = {}, preview = {}, errors = {}, notes = notes, problems = problems }

    for _, entry in ipairs(Settings.Schema) do
        local value = flat[entry.key]
        if value == nil then
            value = Settings.Get(entry.scope == 'server' and srv or cfg, entry.key)
        end
        if entry.type == 'secret' and flat[entry.key] ~= nil then
            value = nil -- exports never carry keys
        end

        if value ~= nil and not placeholders[value] then
            local clean, message = Settings.Validate(entry, value)
            if clean == nil then
                plan.errors[entry.key] = message
            elseif not Same(clean, Settings.Raw(entry)) then
                plan.changes[entry.key] = clean
                plan.preview[#plan.preview + 1] = {
                    key = entry.key,
                    label = entry.label,
                    group = entry.group,
                    from = Shown(entry, Settings.Read(entry)),
                    to = entry.type == 'secret' and 'neuer Schlüssel' or Shown(entry, clean),
                }
            end
        end
    end

    table.sort(plan.preview, function(a, b) return a.key < b.key end)
    return plan
end

-- The import files lying in the resource folder
function Import.FolderSources()
    local sources = {}
    for _, name in ipairs(Files) do
        local code = LoadResourceFile(Bridge.Resource, name)
        if code and code ~= '' then
            sources[#sources + 1] = { name = name, code = code }
        end
    end
    return sources
end

function Import.Apply(plan, actor)
    local applied, errors, restart = Bridge.ApplySettings(plan.changes, nil, actor)
    for key, message in pairs(errors) do
        plan.errors[key] = message
    end
    return applied, restart
end

-- Every changed setting without the API keys, as JSON in the resource
-- folder. Takes them to another server or back after a reset.
function Import.Export()
    local settings, state = {}, Bridge.SettingsState()
    for _, entry in ipairs(Settings.Schema) do
        if entry.type ~= 'secret' and state[entry.key].changed then
            settings[entry.key] = Settings.Raw(entry)
        end
    end
    local body = json.encode({ format = ExportFormat, version = Bridge.Version, settings = settings })
    local ok = SaveResourceFile(Bridge.Resource, 'settings-export.json', body, -1)
    return ok ~= false, 'settings-export.json'
end

local function Report(plan, applied)
    for _, note in ipairs(plan.notes) do
        Bridge.Print('import: old layout ' .. note)
    end
    for _, problem in ipairs(plan.problems) do
        Bridge.Warn('import: ' .. problem)
    end
    for key, message in pairs(plan.errors) do
        Bridge.Warn('import: ' .. key .. ' skipped, ' .. message)
    end
    Bridge.Print(('import: %d setting(s) taken over'):format(#applied))
end
Import.Report = Report

-- ========================================
-- ON START
-- ========================================

do
    local sources = Import.FolderSources()
    local names = {}
    for _, source in ipairs(sources) do
        if source.name ~= 'settings-export.json' then
            names[#names + 1] = source.name
        end
    end

    if #names > 0 and not Bridge.HasStoredSettings then
        Bridge.Print('first start with ' .. table.concat(names, ' and ') .. ' in the folder, importing')
        local plan = Import.Plan(sources)
        local applied = Import.Apply(plan, 'import')
        Bridge.MarkSettingsStored()
        Report(plan, applied)
        Bridge.Print('ef_bridge no longer reads these files. Check the result with /' .. Config.Admin.Command .. ' and delete them.')
    elseif #names > 0 then
        Bridge.Print(table.concat(names, ' and ') .. ' still in the folder but no longer read. `' .. Config.Admin.Command .. ' import` takes them over again, otherwise delete them.')
    end
end

-- Hints for a server that isn't set up yet
if not Bridge.HasStoredSettings then
    Bridge.Print('no settings yet. Open the panel with /' .. Config.Admin.Command .. ' (ACE ' .. Config.Admin.Ace .. ') or use `' .. Config.Admin.Command .. ' help` in this console.')
end
if (Config.Ignis.BaseURL or '') ~= '' and not Bridge.IgnisKeySet() then
    Bridge.Warn('the ignis address is set but no API key, ignis will reject every request. `' .. Config.Admin.Command .. ' key ignis <key>` or the panel sets it.')
end
if ServerConfig.Lex.Enabled and not Bridge.LexKeySet() then
    Bridge.Warn('Lex sync is on but has no API key. `' .. Config.Admin.Command .. ' key lex <key>` or the panel sets it.')
end
