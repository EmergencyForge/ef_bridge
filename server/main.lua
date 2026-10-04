-- Older versions kept the API key in config.lua, which every player
-- downloads. A key still sitting there is public.
if Config.APIKey then
    print("^1[ignisTab]^7 Config.APIKey in config.lua is readable by every player. Move it to ServerConfig.APIKey in config_server.lua, delete it from config.lua and create a new key in ignis.")
end

-- An update brings a fresh config_server.lua; without the key ignis
-- rejects every request
if ServerConfig.APIKey == 'CHANGE_ME' then
    print("^1[ignisTab]^7 ServerConfig.APIKey in config_server.lua is not set, ignis will reject every request.")
end

-- Release builds get the version from the tag (build-release.yml)
local UserAgent = 'FiveM-ignisTab/' .. (GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'dev')

-- Framework detection like client/main.lua. Done on first use, because
-- ignisTab may start before qb-core or es_extended.
local Framework, FrameworkName

local function DetectFramework()
    if FrameworkName then return end

    local wanted = Config.Framework
    if wanted == 'qbcore' or (wanted == 'auto' and GetResourceState('qb-core') == 'started') then
        Framework, FrameworkName = exports['qb-core']:GetCoreObject(), 'qbcore'
    elseif wanted == 'esx' or (wanted == 'auto' and GetResourceState('es_extended') == 'started') then
        Framework, FrameworkName = exports['es_extended']:getSharedObject(), 'esx'
    end
end

-- Name, job and character id from the framework on the server, never
-- from the client
local function GetServerCharacter(src)
    DetectFramework()

    if FrameworkName == 'qbcore' then
        local player = Framework.Functions.GetPlayer(src)
        local data = player and player.PlayerData
        if data and data.charinfo then
            return {
                name = (data.charinfo.firstname or '') .. ' ' .. (data.charinfo.lastname or ''),
                job = data.job and data.job.name or '',
                cid = data.citizenid
            }
        end
    elseif FrameworkName == 'esx' then
        local xPlayer = Framework.GetPlayerFromId(src)
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

-- Character identify: reports which ingame character sits behind a PHP
-- session so ignis can tie the web session to the character.

local IdentifyEndpoint = BuildURL("api/character/identify.php")

-- Every ignis page in the tablet reports its session ID, so repeats of an
-- already linked session are skipped. A new ID also comes right after the
-- tablet login, seconds after the first one, so instead of one cooldown
-- each player gets a few requests per minute.
local IdentifyLimit = 5
local IdentifyWindow = 60
local identifyState = {}

RegisterServerEvent('ignisTab:identifyCharacter')
AddEventHandler('ignisTab:identifyCharacter', function(sessionId)
    local src = source

    if type(sessionId) ~= 'string' or sessionId == "" then
        if Config.Debug then
            print("^1[ignisTab]^7 identifyCharacter: no session_id received")
        end
        return
    end

    local state = identifyState[src]
    if not state then
        state = { since = os.time(), count = 0 }
        identifyState[src] = state
    end
    if state.linked == sessionId then
        return
    end
    if os.time() - state.since >= IdentifyWindow then
        state.since, state.count = os.time(), 0
    end
    if state.count >= IdentifyLimit then
        if Config.Debug then
            print("^3[ignisTab]^7 identifyCharacter: too many requests from source " .. src .. ", skipped")
        end
        return
    end
    state.count = state.count + 1

    local char = GetServerCharacter(src)
    if not char then
        if Config.Debug then
            print("^1[ignisTab]^7 identifyCharacter: no character data for source " .. src .. " (framework: " .. tostring(FrameworkName) .. ")")
        end
        return
    end

    local charName = char.name
    local charJob = char.job

    -- intraRP_API_Key is part of the ignis API contract, don't rename it
    local payload = {
        intraRP_API_Key = ServerConfig.APIKey,
        session_id = sessionId,
        char_name = charName,
        char_job = charJob
    }
    -- ignis only takes a positive whole number here, QBCore citizen IDs
    -- and ESX identifiers are neither
    local cid = tonumber(char.cid)
    if math.type(cid) == 'integer' and cid > 0 then
        payload.char_id = cid
    end

    if Config.Debug then
        print("^2[ignisTab]^7 identifyCharacter: sending to " .. IdentifyEndpoint)
        -- the full session ID would let anyone reading the log take over the session
        print("^2[ignisTab]^7 Payload: session_id=" .. tostring(sessionId):sub(1, 8) .. "..., char_name=" .. charName .. ", char_job=" .. charJob)
    end

    PerformHttpRequest(IdentifyEndpoint, function(statusCode, response, headers)
        if statusCode == 200 then
            state.linked = sessionId
            if Config.Debug then
                print("^2[ignisTab]^7 identifyCharacter: OK (200)")
            end
        elseif statusCode == 401 or statusCode == 403 then
            print("^1[ignisTab]^7 identifyCharacter: API key rejected (" .. statusCode .. "), check ServerConfig.APIKey in config_server.lua")
        else
            print("^1[ignisTab]^7 identifyCharacter: error " .. tostring(statusCode) .. " - " .. tostring(response))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = UserAgent
    })
end)

-- Tablet login: the Discord login of ignis doesn't work in the game
-- browser. Instead the server asks ignis for a one-time login link for
-- the player's Discord ID and hands it to that player only. The API key
-- stays on the server, and the link is never printed: its token signs
-- the player in.

local TabletLoginEndpoint = BuildURL("api/tablet/login-token")
local TabletLoginUnavailable = "Tablet-Login ist gerade nicht verfügbar. Bitte melde dich normal an."
local TabletLoginTooMany = "Zu viele Anmeldeversuche. Warte kurz und öffne das Tablet dann erneut."

-- The client asks once per session, but a modified client can fire the
-- event in a loop and every request costs ignis a few queries. One
-- request per player every 15 seconds.
local TabletLoginCooldown = 15
local lastTabletLogin = {}

AddEventHandler('playerDropped', function()
    lastTabletLogin[source] = nil
    identifyState[source] = nil
end)

-- retry: a passing error (rate limit, ignis unreachable), the client asks
-- again on the next opening. Otherwise it doesn't ask again this session.
local function TabletLoginFailed(src, tabletType, message, retry)
    TriggerClientEvent('ignisTab:tabletLoginFailed', src, tabletType, message, retry == true)
end

RegisterServerEvent('ignisTab:requestTabletLogin')
AddEventHandler('ignisTab:requestTabletLogin', function(tabletType)
    local src = source

    if not (Config.TabletLogin and Config.TabletLogin.Enabled) then
        return
    end

    local now = os.time()
    if now - (lastTabletLogin[src] or 0) < TabletLoginCooldown then
        TabletLoginFailed(src, tabletType, TabletLoginTooMany, true)
        return
    end
    lastTabletLogin[src] = now

    -- With a public key anyone could fetch login links for any Discord ID
    if Config.APIKey then
        print("^1[ignisTab]^7 tablet login: disabled while Config.APIKey is still in config.lua")
        TabletLoginFailed(src, tabletType, TabletLoginUnavailable)
        return
    end

    -- "discord:<id>", verified by FiveM when Discord is a required identifier
    local discordId = (GetPlayerIdentifierByType(src, 'discord') or ''):match('^discord:(%d+)$')
    if not discordId then
        TabletLoginFailed(src, tabletType, "Tablet-Login nicht möglich: Dein FiveM ist nicht mit Discord verbunden. Bitte melde dich normal an.")
        return
    end

    PerformHttpRequest(TabletLoginEndpoint, function(statusCode, response)
        local ok, data = pcall(json.decode, response or '')
        if not ok or type(data) ~= 'table' then
            data = {}
        end

        if statusCode == 200 and data.success and type(data.token) == 'string' then
            local loginUrl = EnsureHttps(data.login_url or BuildURL('auth/tablet'))
            TriggerClientEvent('ignisTab:tabletLogin', src, tabletType, loginUrl .. '?token=' .. data.token)
            if Config.Debug then
                print("^2[ignisTab]^7 tablet login: link sent to source " .. src)
            end
        elseif statusCode == 404 and data.error == 'unknown_user' then
            TabletLoginFailed(src, tabletType, "Tablet-Login nicht möglich: Zu deiner Discord-ID gibt es kein aktives ignis-Konto.")
        elseif statusCode == 404 then
            TabletLoginFailed(src, tabletType, "Tablet-Login ist in ignis nicht aktiviert. Bitte melde dich normal an.")
        elseif statusCode == 409 and data.error == 'ambiguous_user' then
            TabletLoginFailed(src, tabletType, "Tablet-Login nicht möglich: Deine Discord-ID gehört zu mehreren ignis-Konten. Bitte melde dich normal an und wende dich an die Verwaltung.")
        elseif statusCode == 422 then
            TabletLoginFailed(src, tabletType, "Tablet-Login nicht möglich: ignis hat deine Discord-ID nicht angenommen. Bitte melde dich normal an.")
        elseif statusCode == 429 then
            TabletLoginFailed(src, tabletType, TabletLoginTooMany, true)
        else
            if statusCode == 403 then
                print("^1[ignisTab]^7 tablet login: API key rejected, check ServerConfig.APIKey in config_server.lua")
            else
                print("^1[ignisTab]^7 tablet login: ignis answered " .. tostring(statusCode))
            end
            -- 0: ignis not reachable
            local code = tonumber(statusCode) or 0
            TabletLoginFailed(src, tabletType, TabletLoginUnavailable, code == 0 or code >= 500)
        end
    end, 'POST', json.encode({ discord_id = discordId }), {
        ['Content-Type'] = 'application/json',
        ['X-API-Key'] = ServerConfig.APIKey,
        ['User-Agent'] = UserAgent
    })
end)
