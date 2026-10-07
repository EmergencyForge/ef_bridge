-- ignis: character identify and tablet login.

-- Character identify: reports which ingame character sits behind a PHP
-- session so ignis can tie the web session to the character.

-- Every ignis page in the tablet reports its session ID, so repeats of an
-- already linked session are skipped. A new ID also comes right after the
-- tablet login, seconds after the first one, so instead of one cooldown
-- each player gets a few requests per minute.
local IdentifyLimit = 5
local IdentifyWindow = 60
local identifyState = {}

RegisterServerEvent('ef_bridge:identifyCharacter')
AddEventHandler('ef_bridge:identifyCharacter', function(sessionId)
    local src = source

    if type(sessionId) ~= 'string' or sessionId == "" then
        Bridge.Debug("identifyCharacter: no session_id received")
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
        Bridge.Debug("identifyCharacter: too many requests from source " .. src .. ", skipped")
        return
    end
    state.count = state.count + 1

    local char = Bridge.GetCharacter(src)
    if not char then
        local _, frameworkName = Bridge.Framework()
        Bridge.Debug("identifyCharacter: no character data for source " .. src .. " (framework: " .. tostring(frameworkName) .. ")")
        return
    end

    local charName = char.name
    local charJob = char.job

    -- intraRP_API_Key is part of the ignis API contract, don't rename it
    local payload = {
        intraRP_API_Key = Bridge.IgnisKey(),
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

    local endpoint = BuildURL("api/character/identify.php")
    -- the full session ID would let anyone reading the log take over the session
    Bridge.Debug("identifyCharacter: sending to " .. endpoint .. ", session_id=" .. tostring(sessionId):sub(1, 8) .. "..., char_name=" .. charName .. ", char_job=" .. charJob)

    PerformHttpRequest(endpoint, function(statusCode, response, headers)
        if statusCode == 200 then
            state.linked = sessionId
            Bridge.Debug("identifyCharacter: OK (200)")
        elseif statusCode == 401 or statusCode == 403 then
            Bridge.Warn("identifyCharacter: API key rejected (" .. statusCode .. "), check ServerConfig.Ignis.APIKey in config_server.lua")
        else
            Bridge.Warn("identifyCharacter: error " .. tostring(statusCode) .. " - " .. tostring(response))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = Bridge.UserAgent
    })
end)

-- Tablet login: the Discord login of ignis doesn't work in the game
-- browser. Instead the server asks ignis for a one-time login link for
-- the player's Discord ID and hands it to that player only. The API key
-- stays on the server, and the link is never printed: its token signs
-- the player in.

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
    TriggerClientEvent('ef_bridge:tabletLoginFailed', src, tabletType, message, retry == true)
end

RegisterServerEvent('ef_bridge:requestTabletLogin')
AddEventHandler('ef_bridge:requestTabletLogin', function(tabletType)
    local src = source

    if not Config.Ignis.TabletLogin then
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
        Bridge.Warn("tablet login: disabled while Config.APIKey is still in config.lua")
        TabletLoginFailed(src, tabletType, TabletLoginUnavailable)
        return
    end

    -- "discord:<id>", verified by FiveM when Discord is a required identifier
    local discordId = (GetPlayerIdentifierByType(src, 'discord') or ''):match('^discord:(%d+)$')
    if not discordId then
        TabletLoginFailed(src, tabletType, "Tablet-Login nicht möglich: Dein FiveM ist nicht mit Discord verbunden. Bitte melde dich normal an.")
        return
    end

    PerformHttpRequest(BuildURL("api/tablet/login-token"), function(statusCode, response)
        local ok, data = pcall(json.decode, response or '')
        if not ok or type(data) ~= 'table' then
            data = {}
        end

        if statusCode == 200 and data.success and type(data.token) == 'string' then
            local loginUrl = EnsureHttps(data.login_url or BuildURL('auth/tablet'))
            TriggerClientEvent('ef_bridge:tabletLogin', src, tabletType, loginUrl .. '?token=' .. data.token)
            Bridge.Debug("tablet login: link sent to source " .. src)
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
                Bridge.Warn("tablet login: API key rejected, check ServerConfig.Ignis.APIKey in config_server.lua")
            else
                Bridge.Warn("tablet login: ignis answered " .. tostring(statusCode))
            end
            -- 0: ignis not reachable
            local code = tonumber(statusCode) or 0
            TabletLoginFailed(src, tabletType, TabletLoginUnavailable, code == 0 or code >= 500)
        end
    end, 'POST', json.encode({ discord_id = discordId }), {
        ['Content-Type'] = 'application/json',
        ['X-API-Key'] = Bridge.IgnisKey(),
        ['User-Agent'] = Bridge.UserAgent
    })
end)
