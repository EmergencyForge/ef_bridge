-- Older versions kept the API key in config.lua, which every player
-- downloads. A key still sitting there is public.
if Config.APIKey then
    print("^1[ignisTab]^7 Config.APIKey in config.lua is readable by every player. Move it to ServerConfig.APIKey in config_server.lua, delete it from config.lua and create a new key in ignis.")
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
        elseif statusCode == 401 then
            print("^1[ignisTab]^7 identifyCharacter: invalid API key (401)")
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

local function TabletLoginFailed(src, tabletType, message)
    TriggerClientEvent('ignisTab:tabletLoginFailed', src, tabletType, message)
end

RegisterServerEvent('ignisTab:requestTabletLogin')
AddEventHandler('ignisTab:requestTabletLogin', function(tabletType)
    local src = source

    if not (Config.TabletLogin and Config.TabletLogin.Enabled) then
        return
    end

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
            TabletLoginFailed(src, tabletType, "Zu viele Anmeldeversuche. Warte kurz und öffne das Tablet dann erneut.")
        else
            if statusCode == 403 then
                print("^1[ignisTab]^7 tablet login: API key rejected, check ServerConfig.APIKey in config_server.lua")
            else
                print("^1[ignisTab]^7 tablet login: ignis answered " .. tostring(statusCode))
            end
            TabletLoginFailed(src, tabletType, TabletLoginUnavailable)
        end
    end, 'POST', json.encode({ discord_id = discordId }), {
        ['Content-Type'] = 'application/json',
        ['X-API-Key'] = ServerConfig.APIKey,
        ['User-Agent'] = 'FiveM-ignisTab/3.0'
    })
end)
