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
