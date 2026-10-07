local Framework = nil
local FrameworkName = nil

for _, note in ipairs(Settings.MigrateLegacy(false)) do
    print("^1[ef_bridge]^7 old config layout: " .. note)
end

-- The server sends the shared settings, its ingame changes included. Until
-- they arrive, config.lua applies.
RegisterNetEvent('ef_bridge:settings')
AddEventHandler('ef_bridge:settings', function(values)
    if type(values) ~= 'table' then return end
    for key, value in pairs(values) do
        local entry = Settings.ByKey[key]
        if entry and entry.scope == 'shared' then
            Settings.Write(entry, value)
        end
    end
end)
TriggerServerEvent('ef_bridge:settings:request')

-- Framework detection
CreateThread(function()
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
        print("^2[ef_bridge]^7 Client framework detected: " .. (FrameworkName or "None"))
        print("^2[ef_bridge]^7 ignis BaseURL: ^3" .. (Config.Ignis.BaseURL or "EMPTY") .. "^7")
        print("^2[ef_bridge]^7 eNOTF Command: ^3/" .. Config.Tablets.eNOTF.Command .. "^7")
        print("^2[ef_bridge]^7 FireTab Command: ^3/" .. Config.Tablets.FireTab.Command .. "^7")
    end
end)

local isTabletOpen = false
local currentTabletType = nil -- 'eNOTF' or 'FireTab'
local tabletProp = nil
-- Asked for a login link this session. The NUI keeps the pages loaded
-- between openings and both tablets share the ignis cookies, so one login
-- covers both. A second one would rotate the session and its CSRF token
-- under forms the other tablet still shows.
local tabletLoginRequested = false
local tabletDict = Config.Animation.dict
local tabletAnim = Config.Animation.anim

-- Exposed for client/admin.lua, the panel uses the same notifications

function ShowNotification(message, type)
    if FrameworkName == 'qbcore' then
        Framework.Functions.Notify(message, type or "primary")
    elseif FrameworkName == 'esx' then
        Framework.ShowNotification(message)
    else
        SetNotificationTextEntry("STRING")
        AddTextComponentString(message)
        DrawNotification(false, false)
    end
end

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

function CreateTabletProp(tabletType)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local tabletConfig = Config.Tablets[tabletType]
    if not tabletConfig or not tabletConfig.Prop then
        if Config.Debug then
            print("No prop config found for " .. tabletType)
        end
        return
    end

    local propConfig = tabletConfig.Prop
    local model = GetHashKey(propConfig.model)

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(100)
    end

    tabletProp = CreateObject(model, coords.x, coords.y, coords.z, true, true, true)

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

    SetModelAsNoLongerNeeded(model)

    if Config.Debug then
        print("Tablet prop created and attached for " .. tabletType)
    end
end

function DeleteTabletProp()
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteEntity(tabletProp)
        tabletProp = nil
        if Config.Debug then
            print("Tablet prop deleted")
        end
    end
end

function PlayTabletAnimation()
    local ped = PlayerPedId()

    RequestAnimDict(tabletDict)
    while not HasAnimDictLoaded(tabletDict) do
        Wait(100)
    end

    TaskPlayAnim(ped, tabletDict, tabletAnim, 3.0, 3.0, -1, Config.Animation.flag, 0, false, false, false)
end

function StopTabletAnimation()
    local ped = PlayerPedId()

    StopAnimTask(ped, tabletDict, tabletAnim, 1.0)

    -- StopAnimTask alone doesn't always cut it, so escalate gently
    if IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
        ClearPedSecondaryTask(ped)
    end

    if IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
        ClearPedTasks(ped)
    end
end

function PlayerHasItem(itemName)
    -- ox_inventory works with both QBCore and ESX
    if GetResourceState('ox_inventory') == 'started' then
        local count = exports.ox_inventory:Search('count', itemName)
        if Config.Debug then
            print("^2[ef_bridge]^7 ox_inventory item check: " .. itemName .. " = " .. tostring(count))
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

function OpenTablet(tabletType)
    -- the admin panel holds the NUI focus
    if AdminPanelOpen and AdminPanelOpen() then
        return
    end

    if isTabletOpen then
        if Config.Debug then
            print("Tablet already open")
        end
        return
    end

    local config = Config.Tablets[tabletType]
    if not config or not config.Enabled then
        ShowNotification("Dieses Tablet ist nicht aktiviert!", "error")
        return
    end

    local charData = GetPlayerCharacterData()

    if not charData then
        ShowNotification("Fehler beim Abrufen deiner Daten!", "error")
        return
    end

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
                print("^1[ef_bridge]^7 Player job '" .. tostring(charData.job) .. "' not in AllowedJobs for " .. tabletType .. ": " .. json.encode(config.AllowedJobs))
            end
            ShowNotification("Du darfst dieses Tablet nicht nutzen!", "error")
            return
        end
    end

    if config.RequireItem then
        if not PlayerHasItem(config.RequiredItem) then
            ShowNotification("Du besitzt kein " .. config.RequiredItem .. "!", "error")
            return
        end
    end

    isTabletOpen = true
    currentTabletType = tabletType

    if config.UseProp then
        CreateTabletProp(tabletType)
        PlayTabletAnimation()
    end

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    local url = BuildURL(config.Path or '')

    SendNUIMessage({
        type = "openTablet",
        tabletType = tabletType,
        characterData = charData,
        url = url
    })

    if Config.Debug then
        print("Tablet opened with URL:", url)
    end

    if Config.Ignis.TabletLogin and not tabletLoginRequested then
        tabletLoginRequested = true
        TriggerServerEvent('ef_bridge:requestTabletLogin', tabletType)
    end
end

function CloseTablet()
    if not isTabletOpen then return end

    local closingType = currentTabletType

    -- Flag closed before UI updates
    isTabletOpen = false

    StopTabletAnimation()
    DeleteTabletProp()

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({
        type = "closeTablet",
        tabletType = closingType
    })

    currentTabletType = nil

    if Config.Debug then
        print("Tablet closed (" .. tostring(closingType) .. ")")
    end
end

-- NUI callbacks
RegisterNUICallback('getCharacterData', function(data, cb)
    local charData = GetPlayerCharacterData()
    if charData then
        cb(charData)
    else
        cb({error = "Unable to get character data"})
    end
end)

-- The PHP iframe sends its session_id via postMessage -> master.js -> here,
-- so the web session can be tied to the ingame character.
RegisterNUICallback('sessionIdentify', function(data, cb)
    if data and data.session_id then
        if Config.Debug then
            -- shortened: the full ID would let anyone reading the log take over the session
            print("^2[ef_bridge]^7 Received PHP session_id: " .. tostring(data.session_id):sub(1, 8) .. "...")
        end

        local charData = GetPlayerCharacterData()
        if charData then
            -- the server reads name and job from the framework itself
            TriggerServerEvent('ef_bridge:identifyCharacter', data.session_id)
            cb({ success = true })
        else
            cb({ success = false, error = "No character data" })
        end
    else
        cb({ success = false, error = "No session_id" })
    end
end)

RegisterNUICallback('closeTablet', function(data, cb)
    CloseTablet()
    cb('ok')
end)

-- Tablet login: the server fetched a one-time login link for this player,
-- the NUI opens it in the tablet frame. Don't print it, its token signs
-- the player in.
RegisterNetEvent('ef_bridge:tabletLogin')
AddEventHandler('ef_bridge:tabletLogin', function(tabletType, url)
    SendNUIMessage({
        type = "tabletLogin",
        tabletType = tabletType,
        url = url
    })
end)

-- The frame keeps what it loaded (the normal login page without a
-- session). Passing errors (rate limit, ignis unreachable) ask again on the
-- next opening; lasting ones (no Discord ID, no account, login off in
-- ignis) come up once per session.
RegisterNetEvent('ef_bridge:tabletLoginFailed')
AddEventHandler('ef_bridge:tabletLoginFailed', function(tabletType, message, retry)
    if retry then
        tabletLoginRequested = false
    end
    ShowNotification(message, "error")
end)

-- ESC handling and animation upkeep. Runs every frame only while the
-- tablet is open; otherwise it just checks now and then whether a stray
-- animation needs cleanup.
CreateThread(function()
    while true do
        local ped = PlayerPedId()

        if isTabletOpen then
            local config = currentTabletType and Config.Tablets[currentTabletType]
            local usesProp = config and config.UseProp

            DisableControlAction(0, 322, true) -- ESC
            if IsDisabledControlJustPressed(0, 322) then
                CloseTablet()
            end

            if usesProp and not IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
                PlayTabletAnimation()
            end

            Wait(0)
        else
            if IsEntityPlayingAnim(ped, tabletDict, tabletAnim, 3) then
                StopAnimTask(ped, tabletDict, tabletAnim, 1.0)
            end

            Wait(500)
        end
    end
end)

-- Commands. Names and default keys come from config.lua: a key mapping
-- can't be taken back at runtime, so a new command or key from the admin
-- panel applies after a restart.
RegisterCommand(Config.Tablets.eNOTF.Command, function()
    OpenTablet('eNOTF')
end, false)

RegisterCommand(Config.Tablets.FireTab.Command, function()
    OpenTablet('FireTab')
end, false)

RegisterCommand('efbridgetest', function()
    local charData = GetPlayerCharacterData()
    if charData then
        ShowNotification("Character: " .. charData.firstName .. " " .. charData.lastName .. " (" .. charData.job .. ")", "success")
    else
        ShowNotification("No character data found", "error")
    end
end, false)

-- Key mappings - players can rebind these under
-- FiveM settings > key bindings > FiveM.
-- OpenKey = nil still lists the binding, just without a default key.
-- Registered even while a tablet is switched off, so switching it on in
-- the admin panel brings the binding along.
RegisterKeyMapping(Config.Tablets.eNOTF.Command, 'eNOTF Tablet öffnen/schließen', 'keyboard', Config.Tablets.eNOTF.OpenKey or '')
RegisterKeyMapping(Config.Tablets.FireTab.Command, 'FireTab Tablet öffnen/schließen', 'keyboard', Config.Tablets.FireTab.OpenKey or '')

-- Status changes coming from the web side (FireTab) get pushed into
-- emergencydispatch here.
RegisterNetEvent('ef_bridge:applyStatus')
AddEventHandler('ef_bridge:applyStatus', function(status)
    if not status or status == "" then
        return
    end

    local success, result = pcall(function()
        return exports['emergencydispatch']:emf_status(status)
    end)

    if Config.Debug then
        if success and result then
            print("^2[Status-Poll]^7 Status '" .. status .. "' applied")
        else
            print("^1[Status-Poll]^7 Failed to apply status '" .. status .. "'")
        end
    end
end)

-- Cleanup when the resource stops while a tablet is open
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
