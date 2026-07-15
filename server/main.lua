-- Framework detection
local Framework = nil
local FrameworkName = nil

-- Auto-detect framework
if Config.Framework == 'auto' then
    if GetResourceState('qb-core') == 'started' then
        Framework = exports['qb-core']:GetCoreObject()
        FrameworkName = 'qbcore'
    elseif GetResourceState('es_extended') == 'started' then
        Framework = exports['es_extended']:getSharedObject()
        FrameworkName = 'esx'
    end
elseif Config.Framework == 'qbcore' then
    Framework = exports['qb-core']:GetCoreObject()
    FrameworkName = 'qbcore'
elseif Config.Framework == 'esx' then
    Framework = exports['es_extended']:getSharedObject()
    FrameworkName = 'esx'
end

-- Framework-specific player getter
local function GetPlayer(source)
    if FrameworkName == 'qbcore' then
        return Framework.Functions.GetPlayer(source)
    elseif FrameworkName == 'esx' then
        return Framework.GetPlayerFromId(source)
    end
    return nil
end

-- Framework-specific character data extraction
local function GetCharacterData(Player)
    if not Player then return nil end
    
    if FrameworkName == 'qbcore' then
        return {
            firstName = Player.PlayerData.charinfo.firstname,
            lastName = Player.PlayerData.charinfo.lastname,
            cid = Player.PlayerData.citizenid,
            job = Player.PlayerData.job.name
        }
    elseif FrameworkName == 'esx' then
        return {
            firstName = Player.variables.firstName or Player.get('firstName'),
            lastName = Player.variables.lastName or Player.get('lastName'),
            cid = Player.identifier,
            job = Player.job.name
        }
    end
    
    return nil
end

-- Get character data from framework
if FrameworkName == 'qbcore' then
    Framework.Functions.CreateCallback('intrarp-tablet:getCharacterData', function(source, cb)
        local src = source
        local Player = GetPlayer(src)
        
        if Player then
            local characterData = GetCharacterData(Player)
            
            if Config.Debug then
                print("Server sendet Charakterdaten:", json.encode(characterData))
            end
            
            cb(characterData)
        else
            if Config.Debug then
                print("Keine Spielerdaten für Quelle gefunden:", src)
            end
            cb({error = "Keine Spielerdaten gefunden"})
        end
    end)
elseif FrameworkName == 'esx' then
    Framework.RegisterServerCallback('intrarp-tablet:getCharacterData', function(source, cb)
        local src = source
        local Player = GetPlayer(src)
        
        if Player then
            local characterData = GetCharacterData(Player)
            
            if Config.Debug then
                print("Server sendet Charakterdaten:", json.encode(characterData))
            end
            
            cb(characterData)
        else
            if Config.Debug then
                print("Keine Spielerdaten für Quelle gefunden:", src)
            end
            cb({error = "Keine Spielerdaten gefunden"})
        end
    end)
end

-- Alternative method using database query
RegisterServerEvent('intrarp-tablet:getCharacterDataFromDB')
AddEventHandler('intrarp-tablet:getCharacterDataFromDB', function()
    local src = source
    local Player = GetPlayer(src)
    
    if Player then
        local identifier = nil
        local tableName = nil
        local columnName = nil
        
        if FrameworkName == 'qbcore' then
            identifier = Player.PlayerData.citizenid
            tableName = 'players'
            columnName = 'citizenid'
        elseif FrameworkName == 'esx' then
            identifier = Player.identifier
            tableName = 'users'
            columnName = 'identifier'
        end
        
        if identifier and tableName and columnName then
            local query = string.format('SELECT * FROM %s WHERE %s = @identifier', tableName, columnName)
            
            MySQL.Async.fetchAll(query, {
                ['@identifier'] = identifier
            }, function(result)
                if result[1] then
                    local characterData = nil
                    
                    if FrameworkName == 'qbcore' then
                        local charinfo = json.decode(result[1].charinfo)
                        if charinfo and charinfo.firstname and charinfo.lastname then
                            characterData = {
                                firstName = charinfo.firstname,
                                lastName = charinfo.lastname,
                                cid = identifier
                            }
                        end
                    elseif FrameworkName == 'esx' then
                        characterData = {
                            firstName = result[1].firstname,
                            lastName = result[1].lastname,
                            cid = identifier
                        }
                    end
                    
                    if characterData then
                        if Config.Debug then
                            print("Charakterdaten aus Datenbank abgerufen:", json.encode(characterData))
                        end
                        
                        TriggerClientEvent('intrarp-tablet:receiveCharacterData', src, characterData)
                    else
                        TriggerClientEvent('intrarp-tablet:receiveCharacterData', src, {error = "Ungültige Charakterdaten"})
                    end
                else
                    TriggerClientEvent('intrarp-tablet:receiveCharacterData', src, {error = "Charakter nicht in der Datenbank gefunden"})
                end
            end)
        else
            TriggerClientEvent('intrarp-tablet:receiveCharacterData', src, {error = "Framework wird nicht unterstützt"})
        end
    end
end)

-- Framework notification function
RegisterServerEvent('intrarp-tablet:notify')
AddEventHandler('intrarp-tablet:notify', function(message, type)
    local src = source
    
    if FrameworkName == 'qbcore' then
        TriggerClientEvent('QBCore:Notify', src, message, type)
    elseif FrameworkName == 'esx' then
        TriggerClientEvent('esx:showNotification', src, message)
    end
end)

-- ========================================
-- CHARACTER IDENTIFY (Session-basiert)
-- ========================================
-- URL Helper (gleiche Logik wie in emd_sync.lua)
local function EnsureHttps(url)
    if not url or url == "" then return url end
    url = url:match("^%s*(.-)%s*$")
    if url:lower():sub(1, 7) == "http://" then
        url = "https://" .. url:sub(8)
    elseif url:lower():sub(1, 8) ~= "https://" and url:sub(1, 2) ~= "//" then
        url = "https://" .. url
    end
    return url
end

local function AddTrailingSlash(url)
    if url and url:sub(-1) ~= "/" then return url .. "/" end
    return url
end

local function BuildURL(basePath)
    local baseURL = EnsureHttps(Config.BaseURL or "")
    baseURL = AddTrailingSlash(baseURL)
    if basePath and basePath:sub(1, 1) == "/" then
        basePath = basePath:sub(2)
    end
    return baseURL .. (basePath or "")
end

local IdentifyEndpoint = BuildURL("api/character/identify.php")

RegisterServerEvent('intraTab:identifyCharacter')
AddEventHandler('intraTab:identifyCharacter', function(sessionId, charData)
    local src = source

    if not sessionId or sessionId == "" then
        if Config.Debug then
            print("^1[intraTab]^7 identifyCharacter: Keine session_id erhalten")
        end
        return
    end

    if not charData or not charData.firstName then
        if Config.Debug then
            print("^1[intraTab]^7 identifyCharacter: Keine Charakterdaten für source " .. src)
        end
        return
    end

    local charName = charData.firstName .. " " .. charData.lastName
    local charJob = charData.job or ""

    local payload = {
        intraRP_API_Key = Config.APIKey,
        session_id = sessionId,
        char_name = charName,
        char_job = charJob
    }

    if Config.Debug then
        print("^2[intraTab]^7 identifyCharacter: Sende an " .. IdentifyEndpoint)
        print("^2[intraTab]^7 Payload: session_id=" .. sessionId .. ", char_name=" .. charName .. ", char_job=" .. charJob)
    end

    PerformHttpRequest(IdentifyEndpoint, function(statusCode, response, headers)
        if statusCode == 200 then
            if Config.Debug then
                print("^2[intraTab]^7 identifyCharacter: Erfolgreich (200)")
            end
        elseif statusCode == 401 then
            print("^1[intraTab]^7 identifyCharacter: Ungültiger API-Key (401)")
        else
            print("^1[intraTab]^7 identifyCharacter: Fehler " .. tostring(statusCode) .. " - " .. tostring(response))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'FiveM-intraTab/1.0'
    })
end)

-- Debug info
if Config.Debug then
    print("^2[intraTab]^7 Framework erkannt: " .. (FrameworkName or "None"))
end
if Config.Debug and not Framework then
    print("^1[intraTab]^7 FEHLER: Kein unterstütztes Framework gefunden!")
end