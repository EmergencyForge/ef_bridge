-- Framework detection
local Framework = nil
local FrameworkName = nil

-- ========================================
-- URL HELPER FUNKTIONEN
-- ========================================
-- Stelle sicher, dass URLs HTTPS verwenden (FiveM-Anforderung)
local function EnsureHttps(url)
    if not url or url == "" then
        return url
    end
    
    -- Entferne führende/trailing Leerzeichen
    url = url:match("^%s*(.-)%s*$")
    
    -- Wenn die URL mit http:// beginnt, ersetze es durch https://
    if url:lower():sub(1, 7) == "http://" then
        url = "https://" .. url:sub(8)
        if Config.Debug then
            print("^3[intraTab]^7 URL converted to HTTPS: " .. url)
        end
    -- Wenn die URL nicht mit einem Protokoll beginnt, füge https:// hinzu
    elseif url:lower():sub(1, 8) ~= "https://" and url:sub(1, 2) ~= "//" then
        url = "https://" .. url
        if Config.Debug then
            print("^3[intraTab]^7 HTTPS prefix added to URL: " .. url)
        end
    end
    
    return url
end

-- Entferne trailing slash
local function RemoveTrailingSlash(url)
    if url and url:sub(-1) == "/" then
        return url:sub(1, -2)
    end
    return url
end

-- Stelle sicher, dass trailing slash vorhanden ist
local function AddTrailingSlash(url)
    if url and url:sub(-1) ~= "/" then
        return url .. "/"
    end
    return url
end

-- Baue relative URLs basierend auf BaseURL
local function BuildURL(basePath)
    local baseURL = EnsureHttps(Config.BaseURL or "")
    baseURL = AddTrailingSlash(baseURL)
    
    -- basePath sollte ohne führenden Slash sein
    if basePath and basePath:sub(1, 1) == "/" then
        basePath = basePath:sub(2)
    end
    
    return baseURL .. (basePath or "")
end

-- Auto-detect framework
Citizen.CreateThread(function()
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
    
    if Config.Debug then
        print("^2[intraTab]^7 Client framework detected: " .. (FrameworkName or "None"))
        print("^2[intraTab]^7 Loaded BaseURL from config: ^3" .. (Config.BaseURL or "EMPTY") .. "^7")
        print("^2[intraTab]^7 eNOTF Command: ^3/" .. Config.eNOTF.Command .. "^7")
        print("^2[intraTab]^7 FireTab Command: ^3/" .. Config.FireTab.Command .. "^7")
    end
end)

local isTabletOpen = false
local currentTabletType = nil  -- 'eNOTF' oder 'FireTab'
local characterData = nil
local tabletProp = nil
local tabletDict = Config.Animation.dict
local tabletAnim = Config.Animation.anim

-- Framework-specific notification function
local function ShowNotification(message, type)
    if FrameworkName == 'qbcore' then
        Framework.Functions.Notify(message, type or "primary")
    elseif FrameworkName == 'esx' then
        Framework.ShowNotification(message)
    else
        -- Fallback notification
        SetNotificationTextEntry("STRING")
        AddTextComponentString(message)
        DrawNotification(false, false)
    end
end

-- Framework-specific player data getter
function GetPlayerCharacterData()
    if FrameworkName == 'qbcore' then
        local PlayerData = Framework.Functions.GetPlayerData()
        
        if PlayerData and PlayerData.charinfo then
            if Config.Debug then
                print("QBCore data found:", json.encode(PlayerData.charinfo))
            end
            
            return {
                firstName = PlayerData.charinfo.firstname,
                lastName = PlayerData.charinfo.lastname,
                cid = PlayerData.citizenid,
                job = PlayerData.job.name
            }
        end
    elseif FrameworkName == 'esx' then
        local PlayerData = Framework.GetPlayerData()
        
        if PlayerData then
            if Config.Debug then
                print("ESX data found:", json.encode(PlayerData))
            end
            
            return {
                firstName = PlayerData.firstName,
                lastName = PlayerData.lastName,
                cid = PlayerData.identifier,
                job = PlayerData.job.name
            }
        end
    end
    
    return nil
end

-- Function to create tablet prop based on tablet type
function CreateTabletProp(tabletType)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- Get prop config for specific tablet type
    local tabletConfig = Config[tabletType]
    if not tabletConfig or not tabletConfig.Prop then
        if Config.Debug then
            print("No prop config found for " .. tabletType)
        end
        return
    end
    
    local propConfig = tabletConfig.Prop
    
    -- Load prop model
    RequestModel(GetHashKey(propConfig.model))
    while not HasModelLoaded(GetHashKey(propConfig.model)) do
        Wait(100)
    end
    
    -- Create the prop
    tabletProp = CreateObject(GetHashKey(propConfig.model), coords.x, coords.y, coords.z, true, true, true)
    
    -- Attach to player
    AttachEntityToEntity(
        tabletProp, 
        ped, 
        GetPedBoneIndex(ped, propConfig.bone),
        propConfig.offset.x, 
        propConfig.offset.y, 
        propConfig.offset.z,
        propConfig.offset.xRot, 
        propConfig.offset.yRot, 
        propConfig.offset.zRot,
        true, true, false, true, 1, true
    )
    
    if Config.Debug then
        print("Tablet prop created and attached for " .. tabletType)
    end
end

-- Function to delete tablet prop
function DeleteTabletProp()
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteEntity(tabletProp)
        tabletProp = nil
        if Config.Debug then
            print("Tablet prop deleted")
        end
    end
end

-- Function to play tablet animation
function PlayTabletAnimation()
    local ped = PlayerPedId()
    
    -- Load animation dictionary
    RequestAnimDict(tabletDict)
    while not HasAnimDictLoaded(tabletDict) do
        Wait(100)
    end
    
    -- Play animation
    TaskPlayAnim(ped, tabletDict, tabletAnim, 3.0, 3.0, -1, Config.Animation.flag, 0, false, false, false)
    
    if Config.Debug then
        print("Playing tablet animation:", tabletDict, tabletAnim)
    end
end

-- Function to stop tablet animation
function StopTabletAnimation()
    local ped = PlayerPedId()
    
    -- Stop animation
    StopAnimTask(ped, tabletDict, tabletAnim, 1.0)

    -- If still playing, clear secondary task as a gentle fallback
    if IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
        ClearPedSecondaryTask(ped)
        if Config.Debug then
            print("Secondary task cleared as animation fallback")
        end
    end

    -- Final guard: if the same animation still persists, clear tasks once
    if IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
        ClearPedTasks(ped)
        if Config.Debug then
            print("Ped tasks cleared to ensure animation stop")
        end
    end

    if Config.Debug then
        print("Stopped tablet animation")
    end
end


function PlayerHasItem(itemName)
    -- ox_inventory Support (funktioniert mit QBCore und ESX)
    if GetResourceState('ox_inventory') == 'started' then
        local count = exports.ox_inventory:Search('count', itemName)
        if Config.Debug then
            print("^2[intraTab]^7 ox_inventory item check: " .. itemName .. " = " .. tostring(count))
        end
        return count and count > 0
    end

    if FrameworkName == 'qbcore' then
        local PlayerData = Framework.Functions.GetPlayerData()
        if not PlayerData or not PlayerData.items then return false end

        for _, item in pairs(PlayerData.items) do
            if item and item.name == itemName and (item.amount or 0) > 0 then
                return true
            end
        end
        return false

    elseif FrameworkName == 'esx' then
        local inventory = Framework.GetPlayerData().inventory
        if not inventory then return false end

        for _, item in pairs(inventory) do
            if item and item.name == itemName and (item.count or 0) > 0 then
                return true
            end
        end
        return false
    end

    return false
end

-- Generic tablet open function
function OpenTablet(tabletType)
    if isTabletOpen then 
        if Config.Debug then
            print("Tablet already open")
        end
        return 
    end
    
    -- Validiere tabletType
    local config = Config[tabletType]
    if not config or not config.Enabled then
        ShowNotification("Dieses Tablet ist nicht aktiviert!", "error")
        return
    end
    
    if Config.Debug then
        print("Opening " .. tabletType .. " Tablet...")
    end
    
    -- Get character data
    local charData = GetPlayerCharacterData()
    
    if not charData then
        ShowNotification("Fehler beim Abrufen deiner Daten!", "error")
        return
    end
    
    if Config.Debug then
        print("Got character data:", json.encode(charData))
    end

    -- Prüfe erlaubte Jobs
    if config.AllowedJobs then
        local found = false
        for _, v in ipairs(config.AllowedJobs) do            
            if v == charData.job then
                found = true
                break
            end
        end

        if not found then
            if Config.Debug then
                print("^1[intraTab]^7 Player job '" .. tostring(charData.job) .. "' not in AllowedJobs for " .. tabletType .. ": " .. json.encode(config.AllowedJobs))
            end
            ShowNotification("Du darfst dieses Tablet nicht nutzen!", "error")
            return
        end
    end

    -- Prüfe erforderliches Item
    if config.RequireItem then
        if not PlayerHasItem(config.RequiredItem) then
            ShowNotification("Du besitzt kein " .. config.RequiredItem .. "!", "error")
            return
        end
    end
    
    isTabletOpen = true
    currentTabletType = tabletType
    
    -- Check if this tablet type should use a prop
    if config.UseProp then
        CreateTabletProp(tabletType)
        PlayTabletAnimation()
    end
   
    -- Enable NUI with proper focus
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    -- Baue die URL basierend auf tabletType
    local url
    if tabletType == 'eNOTF' then
        url = BuildURL('enotf/overview.php')
    elseif tabletType == 'FireTab' then
        url = BuildURL('einsatz/list.php')
    else
        url = BuildURL('')
    end

    -- Send character data to NUI
    SendNUIMessage({
        type = "openTablet",
        tabletType = tabletType,
        characterData = charData,
        url = url
    })

    if Config.Debug then
        print("Tablet opened with URL:", url)
    end
end

-- Legacy function for backward compatibility
function OpenIntraRPTablet()
    OpenTablet('eNOTF')
end

-- Close tablet
function CloseTablet()
    if not isTabletOpen then return end
    
    local closingType = currentTabletType
    
    if Config.Debug then
        print("Closing tablet of type: " .. tostring(closingType))
    end
    
    -- Flag closed before UI updates
    isTabletOpen = false
    
    -- Stop animation and delete prop
    StopTabletAnimation()
    DeleteTabletProp()
    
    -- Properly disable NUI focus
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    
    -- Notify NUI which tablet to close
    SendNUIMessage({
        type = "closeTablet",
        tabletType = closingType
    })
    if Config.Debug then
        print("Sent NUI closeTablet for type:", tostring(closingType))
    end
    
    -- Now clear current type
    currentTabletType = nil
    
    if Config.Debug then
        print("Tablet closed")
    end
end

-- Legacy function for backward compatibility
function CloseIntraRPTablet()
    CloseTablet()
end

-- NUI Callbacks
RegisterNUICallback('getCharacterData', function(data, cb)
    if Config.Debug then
        print("NUI requested character data")
    end
    
    local charData = GetPlayerCharacterData()
    if charData then
        if Config.Debug then
            print("Sending character data to NUI:", json.encode(charData))
        end
        cb(charData)
    else
        if Config.Debug then
            print("No character data available")
        end
        cb({error = "Unable to get character data"})
    end
end)

-- Session Identify: PHP iframe sends session_id via postMessage -> master.js -> here
RegisterNUICallback('sessionIdentify', function(data, cb)
    if data and data.session_id then
        if Config.Debug then
            print("^2[intraTab]^7 Received PHP session_id: " .. data.session_id)
        end

        local charData = GetPlayerCharacterData()
        if charData then
            TriggerServerEvent('intraTab:identifyCharacter', data.session_id, charData)
            cb({ success = true })
        else
            if Config.Debug then
                print("^1[intraTab]^7 No character data available for session identify")
            end
            cb({ success = false, error = "No character data" })
        end
    else
        cb({ success = false, error = "No session_id" })
    end
end)

RegisterNUICallback('closeTablet', function(data, cb)
    if Config.Debug then
        print("NUI requested to close tablet, data:", json.encode(data or {}))
    end
    CloseIntraRPTablet()
    cb('ok')
end)

-- Key detection thread
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        
        if isTabletOpen then
            -- Check if current tablet uses prop/animation
            local config = currentTabletType and Config[currentTabletType]
            local usesProp = config and config.UseProp
            
            -- Handle ESC key
            DisableControlAction(0, 322, true) -- ESC key
            if IsDisabledControlJustPressed(0, 322) then
                if Config.Debug then
                    print("ESC pressed, closing tablet")
                end
                CloseTablet()
            end
            
            -- Keep animation playing ONLY if tablet uses prop
            if usesProp and not IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
                PlayTabletAnimation()
            end
        else
            -- When tablet is NOT open, actively stop animation if it's running
            if IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
                StopAnimTask(ped, tabletDict, tabletAnim, 1.0)
            end
        end
        
        Wait(0)
    end
end)

-- Commands
RegisterCommand(Config.eNOTF.Command, function()
    if Config.Debug then
        print(Config.eNOTF.Command .. " command executed")
    end
    OpenTablet('eNOTF')
end, false)

RegisterCommand(Config.FireTab.Command, function()
    if Config.Debug then
        print(Config.FireTab.Command .. " command executed")
    end
    OpenTablet('FireTab')
end, false)

RegisterCommand('intrarptest', function()
    local charData = GetPlayerCharacterData()
    if charData then
        ShowNotification("Character: " .. charData.firstName .. " " .. charData.lastName .. " (" .. charData.job .. ")", "success")
        if Config.Debug then
            print("Character Data:", json.encode(charData))
        end
    else
        ShowNotification("No character data found", "error")
    end
end, false)

-- Key Mappings - Benutzer können die Tasten in FiveM Einstellungen > Tastenbelegung > FiveM ändern
-- Hinweis: Diese Tasten sind nur Standardwerte und können von jedem Spieler individuell angepasst werden
-- Wenn OpenKey = nil, erscheint die Option trotzdem in den Einstellungen, aber ohne vorgegebene Taste
if Config.eNOTF.Enabled then
    local defaultKey = Config.eNOTF.OpenKey or ''  -- Leerer String = keine Vorgabe, aber User kann selbst zuweisen
    RegisterKeyMapping(Config.eNOTF.Command, 'eNOTF Tablet öffnen/schließen', 'keyboard', defaultKey)
end

if Config.FireTab.Enabled then
    local defaultKey = Config.FireTab.OpenKey or ''  -- Leerer String = keine Vorgabe, aber User kann selbst zuweisen
    RegisterKeyMapping(Config.FireTab.Command, 'FireTab Tablet öffnen/schließen', 'keyboard', defaultKey)
end

-- Framework-specific events
if FrameworkName == 'qbcore' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        characterData = nil
        if Config.Debug then
            print("QBCore player loaded, character data reset")
        end
    end)
elseif FrameworkName == 'esx' then
    RegisterNetEvent('esx:playerLoaded', function(xPlayer)
        characterData = nil
        if Config.Debug then
            print("ESX player loaded, character data reset")
        end
    end)
end

-- ========================================
-- STATUS-POLL: Statusänderungen von PHP (FireTab) -> emergencydispatch
-- ========================================
RegisterNetEvent('intraTab:applyStatus')
AddEventHandler('intraTab:applyStatus', function(status)
    if not status or status == "" then
        return
    end

    local success, result = pcall(function()
        return exports['emergencydispatch']:emf_status(status)
    end)

    if Config.Debug then
        if success and result then
            print("^2[Status-Poll]^7 Status '" .. status .. "' erfolgreich gesetzt")
        else
            print("^1[Status-Poll]^7 Fehler beim Setzen von Status '" .. status .. "'")
        end
    end
end)

-- Resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if Config.Debug then
            print("tablet resource started")
            print("Framework:", FrameworkName or "None")
            print("eNOTF OpenKey:", Config.eNOTF.OpenKey, "FireTab OpenKey:", Config.FireTab.OpenKey)
        end
    end
end)

-- Resource stop - cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if isTabletOpen then
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            StopTabletAnimation()
            DeleteTabletProp()
        end
    end
end)
