-- Loads the tablet login code (server/main.lua, client/main.lua) and the
-- billing events with stubbed FiveM natives and walks it through its
-- branches. Server and client events are wired to each other like in the
-- game.
--
--   lua tests/tablet_login_check.lua    (Lua 5.4, no FiveM needed)
local root = arg[0]:gsub("[^/\\]+$", "") .. "../"

local handlers, clientEvents, serverEvents, nuiMessages = {}, {}, {}, {}
local printed, requests, notifications = {}, {}, {}
local identifiers = {}
local nextResponse = { 200, "" }
local decoded = {}
local now = 1000000
os.time = function() return now end

-- natives the scripts touch while loading or opening a tablet
for _, name in ipairs({
    "CreateThread", "RegisterCommand", "RegisterKeyMapping",
    "SetNuiFocus", "SetNuiFocusKeepInput", "SetNotificationTextEntry", "DrawNotification",
    "PlayerPedId", "StopAnimTask", "IsEntityPlayingAnim", "ClearPedSecondaryTask", "ClearPedTasks",
}) do
    _G[name] = function() end
end
local nuiCallbacks = {}
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
-- events a client may trigger
local netEvents = {}
function RegisterServerEvent(name) netEvents[name] = true end
function RegisterNetEvent(name) netEvents[name] = true end
function AddEventHandler(name, fn) handlers[name] = fn end
function AddTextComponentString(text) notifications[#notifications + 1] = text end
function SendNUIMessage(msg) nuiMessages[#nuiMessages + 1] = msg end
function GetPlayerIdentifierByType(src, kind) return identifiers[src] end
local aceAllowed = {}
function IsPlayerAceAllowed(src, perm) return aceAllowed[src] == perm end
function GetPlayerName(src) return "Spieler" .. src end
function GetCurrentResourceName() return "ignisTab" end
function GetResourceMetadata(resource, key) return key == 'version' and '2026.2.0' or nil end
-- framework on the server: QBCore players by source, ESX the same
local startedResources = { ['qb-core'] = true }
function GetResourceState(name) return startedResources[name] and 'started' or 'missing' end
local qbPlayers, esxPlayers = {}, {}
local QBCore = { Functions = { GetPlayer = function(src) return qbPlayers[src] end } }
local ESX = { GetPlayerFromId = function(src) return esxPlayers[src] end }
exports = setmetatable({
    ['qb-core'] = { GetCoreObject = function() return QBCore end },
    ['es_extended'] = { getSharedObject = function() return ESX end },
}, { __call = function() end })
local function qbPlayer(first, last, job, citizenid)
    return { PlayerData = { charinfo = { firstname = first, lastname = last }, job = { name = job }, citizenid = citizenid } }
end
qbPlayers[1] = qbPlayer("Max", "Muster", "ambulance", "ABC12345")
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
dofile(root .. "server/enotf_billing.lua")
dofile(root .. "server/billing-custom.lua")
-- fresh client state, like a player joining
local function loadClient()
    dofile(root .. "client/main.lua")
    GetPlayerCharacterData = function()
        return { firstName = "Max", lastName = "Muster", cid = "C1", job = "admin" }
    end
end
loadClient()

local failed = 0
local function check(label, cond)
    realPrint((cond and "ok   " or "FAIL ") .. label)
    if not cond then failed = failed + 1 end
end

-- wait: seconds since the last request, past the cooldown by default
local function reset(status, body, value, wait)
    now = now + (wait or 60)
    clientEvents, serverEvents, nuiMessages = {}, {}, {}
    printed, requests, notifications = {}, {}, {}
    nextResponse = { status, body }
    if body then decoded[body] = value end
end

-- one tablet login request as the server sees it
local function run(src, status, body, value, wait)
    reset(status, body, value, wait)
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
check("User-Agent carries the manifest version", requests[1].headers['User-Agent'] == "FiveM-ignisTab/2026.2.0")
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
check("no discord: not retried", not ev.args[3])

identifiers[3] = "discord:abc"
ev = run(3, 200, "ok", okBody)
check("malformed discord id: no request", #requests == 0 and ev.name == 'ignisTab:tabletLoginFailed')

ev = run(1, 404, "unknown", { success = false, error = "unknown_user" })
check("404 unknown_user message", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[2]:find("kein aktives ignis%-Konto"))
check("404 unknown_user is not retried", not ev.args[3])
ev = run(1, 404, "disabled", { success = false, error = "disabled" })
check("404 disabled = setting off", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[2]:find("nicht aktiviert"))
ev = run(1, 404, "<html>not found</html>", nil)
check("404 without JSON (older ignis) = setting off", ev.args[2]:find("nicht aktiviert"))
ev = run(1, 409, "ambiguous", { success = false, error = "ambiguous_user" })
check("409 ambiguous_user message", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[2]:find("mehreren ignis%-Konten"))
check("409 is not retried", not ev.args[3])
ev = run(1, 422, "invalid", { success = false, error = "invalid_discord_id" })
check("422 message", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[2]:find("nicht angenommen"))
check("422 is not retried", not ev.args[3])
ev = run(1, 429, "limit", { success = false })
check("429 message", ev.args[2]:find("Zu viele"))
check("429 may be retried", ev.args[3] == true)
ev = run(1, 502, "<html>bad gateway</html>", nil)
check("5xx may be retried", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[3] == true)
ev = run(1, 403, "denied", { success = false, message = "Zugriff verweigert" })
check("403 generic player message", ev.args[2]:find("nicht verfügbar"))
check("403 admin hint", printedContains("API key rejected"))
check("403 is not retried", not ev.args[3])
ev = run(1, 0, nil, nil)
check("network error handled", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[3] == true)
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

-- a modified client firing the event in a loop
identifiers[4] = "discord:223456789012345678"
run(4, 200, "ok", okBody)
ev = run(4, 200, "ok", okBody, 5)
check("cooldown: no second request to ignis within 15 s", #requests == 0)
check("cooldown: player gets the rate limit notice", ev.name == 'ignisTab:tabletLoginFailed' and ev.args[2]:find("Zu viele"))
check("cooldown may be retried", ev.args[3] == true)
run(4, 200, "ok", okBody, 10)
check("cooldown counts from the last request that went through", #requests == 1)
run(1, 200, "ok", okBody, 0)
check("cooldown is per player", #requests == 1)
run(4, 200, "ok", okBody, 1)
source = 4
handlers['playerDropped']()
run(4, 200, "ok", okBody, 1)
check("cooldown cleared when the player leaves", #requests == 1)

-- character identify
local charData = { firstName = "Max", lastName = "Muster", job = "admin" }
reset(403, "denied", { success = false, message = "Zugriff verweigert" })
source = 1
handlers['ignisTab:identifyCharacter']("sess-0123456789abcdef", charData)
check("identify: rejected key (403) points to config_server.lua", printedContains("config_server.lua"))

-- a session ID in the log is enough to take over the ignis session
local sessionId = "0123456789abcdefghijklmnopqrstuv"
reset(200, "ok", { success = true })
Config.Debug = true
nuiCallbacks.sessionIdentify({ session_id = sessionId }, function() end)
Config.Debug = false
check("identify reaches ignis", #requests == 1 and requests[1].body:find(sessionId, 1, true))
check("session ID never printed in full (debug on)", #printed > 0 and not printedContains(sessionId)
    and printedContains("01234567..."))

-- name and job come from the framework, whatever the client sends
reset(200, "ok", { success = true })
source = 1
handlers['ignisTab:identifyCharacter']("forged-session-0001", { firstName = "Fake", lastName = "Name", job = "police" })
local body = requests[1] and requests[1].body or ""
check("identify: name from the framework", body:find('"char_name":"Max Muster"', 1, true) ~= nil)
check("identify: job from the framework", body:find('"char_job":"ambulance"', 1, true) ~= nil)
check("identify: client data ignored", not body:find("Fake") and not body:find("police"))
check("identify: QBCore citizen id is no char_id", not body:find("char_id"))

reset(200, "ok", { success = true })
source = 9
handlers['ignisTab:identifyCharacter']("session-without-character")
check("identify: no character on the server, no request", #requests == 0)

reset(200, "ok", { success = true })
source = 1
handlers['ignisTab:identifyCharacter']("forged-session-0001")
check("identify: a linked session is not sent again", #requests == 0)

-- a modified client sending made-up session IDs in a loop
qbPlayers[8] = qbPlayer("Erika", "Muster", "ambulance", "42")
reset(200, "ok", { success = true })
source = 8
for i = 1, 8 do
    handlers['ignisTab:identifyCharacter']("loop-session-" .. i)
end
check("identify: 5 requests per minute and player", #requests == 5)
check("identify: numeric citizen id goes along as char_id", requests[1].body:find('"char_id":"42"', 1, true) ~= nil)
reset(200, "ok", { success = true }, 61)
source = 8
handlers['ignisTab:identifyCharacter']("loop-session-9")
check("identify: next minute goes through again", #requests == 1)
handlers['playerDropped']()

-- ESX
Config.Framework = 'esx'
esxPlayers[3] = {
    identifier = "char1:abc",
    job = { name = "fire" },
    get = function(key) return ({ firstName = "Erika", lastName = "Brand" })[key] end,
    getName = function() return "Steam Name" end,
}
dofile(root .. "server/main.lua")
reset(200, "ok", { success = true })
source = 3
handlers['ignisTab:identifyCharacter']("esx-session-0001", { firstName = "Fake" })
body = requests[1] and requests[1].body or ""
check("identify (ESX): name and job from xPlayer", body:find('"char_name":"Erika Brand"', 1, true) ~= nil
    and body:find('"char_job":"fire"', 1, true) ~= nil and not body:find("char_id"))
Config.Framework = 'auto'
dofile(root .. "server/main.lua")

-- ===== billing =====

local function requestProtocols(src, target)
    reset(200, "ok", { success = true })
    source = src
    handlers['enotf-billing:requestProtocols'](target)
    return clientEvents[1]
end

ev = requestProtocols(5)
check("billing: player without ACE gets nothing", ev == nil)
check("billing: denied request is logged", printedContains("requestProtocols denied for source 5"))
aceAllowed[6] = 'ignistab.billing'
ev = requestProtocols(6, 99)
check("billing: player with ACE gets the protocols himself", ev and ev.name == 'enotf-billing:receiveProtocols' and ev.src == 6 and #clientEvents == 1)
ev = requestProtocols('', 7)
check("billing: server trigger sends to the named player", ev and ev.src == 7)
ev = requestProtocols('')
check("billing: server trigger without player sends nothing", ev == nil)
check("billing: custom hooks are no net events", not netEvents['enotf-billing:autoSync'] and not netEvents['enotf-billing:manualSync'])
check("billing: requestProtocols stays reachable for players with ACE", netEvents['enotf-billing:requestProtocols'] == true)

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

-- both tablets share the ignis cookies; a second login would rotate the
-- session and the CSRF token under the other frame's open forms
reset(200, "ok", okBody)
OpenTablet('FireTab')
check("other tablet after a login: no new request", #serverEvents == 0)
CloseTablet()

-- lasting errors: one notice per session
loadClient()
reset(404, "unknown", { success = false, error = "unknown_user" })
OpenTablet('eNOTF')
CloseTablet()
check("lasting error: notice", #notifications == 1)
reset(200, "ok", okBody)
OpenTablet('FireTab')
CloseTablet()
check("lasting error: no new request on the next opening", #serverEvents == 0 and #notifications == 0)

-- passing errors: ask again on the next opening
loadClient()
reset(500, "<html>error</html>", nil)
OpenTablet('eNOTF')
CloseTablet()
reset(200, "ok", okBody, 5)
OpenTablet('eNOTF')
CloseTablet()
check("passing error: the next opening asks again", #serverEvents == 1)
check("within the cooldown: rate limit notice", clientEvents[1] and clientEvents[1].args[2]:find("Zu viele"))
reset(200, "ok", okBody)
OpenTablet('eNOTF')
CloseTablet()
check("after the cooldown: login link", #serverEvents == 1 and nuiMessages[2] and nuiMessages[2].type == "tabletLogin")

realPrint(failed == 0 and "all checks passed" or (failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
