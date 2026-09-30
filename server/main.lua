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

-- Character identify: reports which ingame character sits behind a PHP
-- session so ignis can tie the web session to the character.

local IdentifyEndpoint = BuildURL("api/character/identify.php")

RegisterServerEvent('ignisTab:identifyCharacter')
AddEventHandler('ignisTab:identifyCharacter', function(sessionId, charData)
    local src = source

    if not sessionId or sessionId == "" then
        if Config.Debug then
            print("^1[ignisTab]^7 identifyCharacter: no session_id received")
        end
        return
    end

    if not charData or not charData.firstName then
        if Config.Debug then
            print("^1[ignisTab]^7 identifyCharacter: no character data for source " .. src)
        end
        return
    end

    local charName = charData.firstName .. " " .. charData.lastName
    local charJob = charData.job or ""

    -- intraRP_API_Key is part of the ignis API contract, don't rename it
    local payload = {
        intraRP_API_Key = ServerConfig.APIKey,
        session_id = sessionId,
        char_name = charName,
        char_job = charJob
    }

    if Config.Debug then
        print("^2[ignisTab]^7 identifyCharacter: sending to " .. IdentifyEndpoint)
        print("^2[ignisTab]^7 Payload: session_id=" .. sessionId .. ", char_name=" .. charName .. ", char_job=" .. charJob)
    end

    PerformHttpRequest(IdentifyEndpoint, function(statusCode, response, headers)
        if statusCode == 200 then
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
        ['User-Agent'] = 'FiveM-ignisTab/3.0'
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
        ['User-Agent'] = 'FiveM-ignisTab/3.0'
    })
end)
