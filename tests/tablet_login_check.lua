-- Loads the tablet login code (server/main.lua, client/main.lua) with
-- stubbed FiveM natives and walks it through its branches. Server and
-- client events are wired to each other like in the game.
--
--   lua tests/tablet_login_check.lua    (Lua 5.4, no FiveM needed)
local root = arg[0]:gsub("[^/\\]+$", "") .. "../"

local handlers, clientEvents, serverEvents, nuiMessages = {}, {}, {}, {}
local printed, requests, notifications = {}, {}, {}
local identifiers = {}
local nextResponse = { 200, "" }
local decoded = {}

-- natives the scripts touch while loading or opening a tablet
for _, name in ipairs({
    "CreateThread", "RegisterNUICallback", "RegisterCommand", "RegisterKeyMapping",
    "SetNuiFocus", "SetNuiFocusKeepInput", "SetNotificationTextEntry", "DrawNotification",
    "PlayerPedId", "StopAnimTask", "IsEntityPlayingAnim", "ClearPedSecondaryTask", "ClearPedTasks",
}) do
    _G[name] = function() end
end
function RegisterServerEvent() end
function RegisterNetEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function AddTextComponentString(text) notifications[#notifications + 1] = text end
function SendNUIMessage(msg) nuiMessages[#nuiMessages + 1] = msg end
function GetPlayerIdentifierByType(src, kind) return identifiers[src] end
function PerformHttpRequest(url, cb, method, body, headers)
    requests[#requests + 1] = { url = url, method = method, body = body, headers = headers }
    cb(nextResponse[1], nextResponse[2], {})
end
-- server -> client and back, the game client is always source 1
function TriggerClientEvent(name, src, ...)
    clientEvents[#clientEvents + 1] = { name = name, src = src, args = { ... } }
    if handlers[name] then handlers[name](...) end
end
function TriggerServerEvent(name, ...)
    serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
    source = 1
    if handlers[name] then handlers[name](...) end
end
json = {
    encode = function(t)
        local parts = {}
        for k, v in pairs(t) do parts[#parts + 1] = string.format('"%s":"%s"', k, tostring(v)) end
        return "{" .. table.concat(parts, ",") .. "}"
    end,
    decode = function(s)
        if decoded[s] == nil then error("invalid json") end
        return decoded[s]
    end,
}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

dofile(root .. "config.lua")
dofile(root .. "config_server.lua")
dofile(root .. "shared/url.lua")
Config.BaseURL = "http://ignis.test/"
ServerConfig.APIKey = "secret-key"
Config.TabletLogin.Enabled = true
Config.eNOTF.UseProp = false
Config.FireTab.UseProp = false
dofile(root .. "server/main.lua")
dofile(root .. "client/main.lua")
GetPlayerCharacterData = function()
    return { firstName = "Max", lastName = "Muster", cid = "C1", job = "admin" }
end

local failed = 0
local function check(label, cond)
    realPrint((cond and "ok   " or "FAIL ") .. label)
    if not cond then failed = failed + 1 end
end

local function reset(status, body, value)
    clientEvents, serverEvents, nuiMessages = {}, {}, {}
    printed, requests, notifications = {}, {}, {}
    nextResponse = { status, body }
    if body then decoded[body] = value end
end

-- one tablet login request as the server sees it
local function run(src, status, body, value)
    reset(status, body, value)
    source = src
    handlers['ignisTab:requestTabletLogin']('eNOTF')
    return clientEvents[1]
end

local function printedContains(text)
    for _, line in ipairs(printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

-- ===== server =====

local okBody = { success = true, token = "TOKEN_abc-123", expires_in = 60, login_url = "http://ignis.test/auth/tablet" }

identifiers[1] = "discord:123456789012345678"
local ev = run(1, 200, "ok", okBody)
check("request goes to api/tablet/login-token", requests[1].url == "https://ignis.test/api/tablet/login-token")
check("request carries X-API-Key", requests[1].headers['X-API-Key'] == "secret-key")
check("request body carries discord_id", requests[1].body == '{"discord_id":"123456789012345678"}')
check("no API key in the body", not requests[1].body:find("secret"))
check("link goes to the requesting source only", ev.name == 'ignisTab:tabletLogin' and ev.src == 1 and #clientEvents == 1)
check("link is https login_url with token", ev.args[2] == "https://ignis.test/auth/tablet?token=TOKEN_abc-123")
check("tablet type passed back", ev.args[1] == 'eNOTF')

Config.Debug = true
run(1, 200, "ok", okBody)
Config.Debug = false
check("token never printed (debug on)", #printed > 0 and not printedContains("TOKEN_abc"))

identifiers[2] = nil
ev = run(2, 200, "ok", okBody)
check("no discord: no request", #requests == 0)
check("no discord: failure to source", ev.name == 'ignisTab:tabletLoginFailed' and ev.src == 2 and ev.args[2]:find("Discord"))

identifiers[3] = "discord:abc"
ev = run(3, 200, "ok", okBody)
check("malformed discord id: no request", #requests == 0 and ev.name == 'ignisTab:tabletLoginFailed')

ev = run(1, 404, "unknown", { success = false, error = "unknown_user" })
check("404 unknown_user message", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[2]:find("kein aktives ignis%-Konto"))
ev = run(1, 404, "disabled", { success = false, error = "disabled" })
check("404 disabled = setting off", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[2]:find("nicht aktiviert"))
ev = run(1, 404, "<html>not found</html>", nil)
check("404 without JSON (older ignis) = setting off", ev.args[2]:find("nicht aktiviert"))
ev = run(1, 429, "limit", { success = false })
check("429 message", ev.args[2]:find("Zu viele"))
ev = run(1, 403, "denied", { success = false, message = "Zugriff verweigert" })
check("403 generic player message", ev.args[2]:find("nicht verfügbar"))
check("403 admin hint", printedContains("API key rejected"))
ev = run(1, 0, nil, nil)
check("network error handled", ev.name == 'ignisTab:tabletLoginFailed')
ev = run(1, 200, "notoken", { success = true })
check("200 without token is a failure", ev.name == 'ignisTab:tabletLoginFailed')

Config.TabletLogin.Enabled = false
ev = run(1, 200, "ok", okBody)
check("disabled: nothing happens", ev == nil and #requests == 0)
Config.TabletLogin.Enabled = true

Config.APIKey = "secret-key"
ev = run(1, 200, "ok", okBody)
check("key in config.lua: no request, failure", #requests == 0 and ev.name == 'ignisTab:tabletLoginFailed')
Config.APIKey = nil

-- ===== client =====

reset(200, "ok", okBody)
OpenTablet('eNOTF')
check("opening asks the server for a login link", #serverEvents == 1 and serverEvents[1].name == 'ignisTab:requestTabletLogin')
check("NUI gets the tablet page first", nuiMessages[1] and nuiMessages[1].type == "openTablet")
local login = nuiMessages[2]
check("NUI gets the login link", login and login.type == "tabletLogin" and login.tabletType == "eNOTF"
    and login.url == "https://ignis.test/auth/tablet?token=TOKEN_abc-123")
CloseTablet()

reset(200, "ok", okBody)
OpenTablet('eNOTF')
check("second opening: no new request", #serverEvents == 0)
CloseTablet()

realPrint(failed == 0 and "all checks passed" or (failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
