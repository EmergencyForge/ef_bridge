-- EMD sync heartbeat: bundles dispatch data, status updates and situation
-- reports into a single periodic request against the ignis backend and
-- applies whatever the backend sends back.

local PHPEndpoint = BuildURL("api/emd/sync.php")

if Config.Debug then
    print("^2[EMD-Sync]^7 endpoint: " .. (PHPEndpoint or "MISSING"))
end

-- ========================================
-- DATABASE HELPER
-- ========================================
local function ExecuteQuery(query, parameters)
    local p = promise.new()
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute(query, parameters, function(result)
            p:resolve(result)
        end)
    elseif MySQL and MySQL.Async then
        MySQL.Async.fetchAll(query, parameters, function(result)
            p:resolve(result)
        end)
    else
        if Config.Debug then
            print("^1[EMD-Sync]^7 No MySQL resource found. Install oxmysql or mysql-async.")
        end
        p:resolve(nil)
    end
    return Citizen.Await(p)
end

-- ========================================
-- HEARTBEAT STATE
-- ========================================
local currentTick = 0
local isSyncing = false
local lastStatusId = 0

-- Statuses without a dispatch get queued here and ride along with the
-- next heartbeat.
local fallbackStatusQueue = {}
local pendingFallbackStatuses = nil

-- mannedvehicles() result cached per tick to avoid duplicate export calls
local cachedMannedVehicles = nil
local cachedMannedVehiclesTick = -1

-- ========================================
-- RESPONSE PROCESSORS (PHP -> FiveM)
-- ========================================

local function ProcessSituationReports(responseData)
    if not responseData or not responseData.situation_reports then
        return
    end

    local totalSent = 0
    local totalFailed = 0

    for einsatznummer, reports in pairs(responseData.situation_reports) do
        if type(reports) == 'table' then
            for _, report in ipairs(reports) do
                local text = report.text or ""
                local sender = report.sender or "intraRP"

                if text ~= "" then
                    local success, result = pcall(function()
                        return exports['emergencydispatch']:emf_lagemeldung_send(tonumber(einsatznummer) or einsatznummer, text, sender)
                    end)

                    if success and result then
                        totalSent = totalSent + 1
                    else
                        totalFailed = totalFailed + 1
                    end
                end
            end
        end
    end

    if Config.Debug and (totalSent > 0 or totalFailed > 0) then
        print("^2[Heartbeat]^7 situation reports processed: " .. totalSent .. " ok, " .. totalFailed .. " failed")
    end
end

local function FindPlayerSourceByVehicleName(vehicleName)
    local success, mannedVehicles = pcall(function()
        return exports['emergencydispatch']:mannedvehicles()
    end)

    if not success or not mannedVehicles then
        return nil
    end

    for _, vehicle in ipairs(mannedVehicles) do
        if vehicle.value == vehicleName then
            return vehicle.source
        end
    end

    return nil
end

local function ProcessStatusChanges(statusChanges)
    if not statusChanges or #statusChanges == 0 then
        return
    end

    local applied = 0
    local notFound = 0

    for _, change in ipairs(statusChanges) do
        local vehicleName = change.vehicle_name
        local status = change.status

        if vehicleName and status then
            local playerSource = FindPlayerSourceByVehicleName(vehicleName)

            if playerSource then
                TriggerClientEvent('ignisTab:applyStatus', playerSource, tostring(status))
                applied = applied + 1
            else
                notFound = notFound + 1
                if Config.Debug then
                    print("^3[Heartbeat]^7 no player found for vehicle '" .. vehicleName .. "' (status: " .. status .. ")")
                end
            end
        end
    end

    if Config.Debug and (applied > 0 or notFound > 0) then
        print("^2[Heartbeat]^7 status changes processed: " .. applied .. " applied, " .. notFound .. " without player")
    end
end

local function ProcessPatientData(responseData)
    if not responseData or not responseData.patient_updates then
        return
    end

    local totalAdded = 0
    local totalFailed = 0

    for key, patient in pairs(responseData.patient_updates) do
        -- keys look like "12345" or "12345_1", we only want the base number
        local baseNummer = tostring(key):match("^(%d+)")
        local einsatznummer = tonumber(baseNummer)
        if not einsatznummer then
            if Config.Debug then
                print("^3[Heartbeat]^7 invalid mission number: " .. tostring(key) .. " - skipped")
            end
            goto continue
        end

        local vorname = patient.vorname or ""
        local nachname = patient.nachname or ""
        local alter = tostring(patient.alter or "")
        local pzc = "" -- not part of the PHP response
        local funkrufname = patient.funkrufname or ""
        local transportziel = patient.transportziel or ""

        if vorname ~= "" and nachname ~= "" then
            local success = pcall(function()
                return exports['emergencydispatch']:emf_patient_add(
                    einsatznummer,
                    vorname,
                    nachname,
                    alter,
                    pzc,
                    funkrufname,
                    transportziel
                )
            end)

            if success then
                totalAdded = totalAdded + 1
            else
                totalFailed = totalFailed + 1
            end
        end
        ::continue::
    end

    if Config.Debug and (totalAdded > 0 or totalFailed > 0) then
        print("^2[Heartbeat]^7 patient data processed: " .. totalAdded .. " added, " .. totalFailed .. " failed")
    end
end

-- ========================================
-- DATA COLLECTORS
-- ========================================

local function GetMannedVehiclesCached(tick)
    if tick == cachedMannedVehiclesTick and cachedMannedVehicles then
        return cachedMannedVehicles
    end

    local success, result = pcall(function()
        return exports['emergencydispatch']:mannedvehicles()
    end)

    if success and result then
        cachedMannedVehicles = result
        cachedMannedVehiclesTick = tick
        return result
    end

    if Config.Debug then
        print("^1[Heartbeat]^7 mannedvehicles() call failed")
    end
    return nil
end

local function GetDispatchListDetails(dispatchNumbers)
    if not dispatchNumbers or #dispatchNumbers == 0 then
        return {}
    end
    local placeholders = {}
    for i = 1, #dispatchNumbers do
        placeholders[i] = '?'
    end
    local query = string.format([[
        SELECT id, number, dispatch
        FROM emd_dispatchlist
        WHERE number IN (%s)
    ]], table.concat(placeholders, ','))
    local result = ExecuteQuery(query, dispatchNumbers)
    return result or {}
end

local function GetLagemeldungen(einsatznummer)
    if not einsatznummer then
        return nil
    end
    local success, lagemeldungen = pcall(function()
        return exports['emergencydispatch']:emf_lagemeldung_get(einsatznummer)
    end)
    if not success then
        if Config.Debug then
            print("^1[Heartbeat]^7 failed to fetch situation reports for mission " .. tostring(einsatznummer))
        end
        return nil
    end
    return lagemeldungen
end

local function GetAllLagemeldungen(dispatchNumbers)
    if not dispatchNumbers or #dispatchNumbers == 0 then
        return {}
    end
    local lagemeldungMap = {}
    for _, einsatznummer in ipairs(dispatchNumbers) do
        local lagemeldungen = GetLagemeldungen(einsatznummer)
        if lagemeldungen and type(lagemeldungen) == 'table' then
            lagemeldungMap[tostring(einsatznummer)] = lagemeldungen
        end
    end
    return lagemeldungMap
end

local function LoadLastStatusId()
    if not Config.EMDSync or not Config.EMDSync.StatusSync or not Config.EMDSync.StatusSync.Enabled then
        return
    end
    local query = string.format([[
        SELECT MAX(id) as max_id
        FROM %s
        WHERE type = 'status'
    ]], Config.EMDSync.StatusSync.SourceTable)
    local result = ExecuteQuery(query, {})
    if result and result[1] and result[1].max_id then
        lastStatusId = result[1].max_id
        if Config.Debug then
            print("^2[Heartbeat]^7 last status id loaded: " .. lastStatusId)
        end
    end
end

local function GetNewStatusMessages()
    if not Config.EMDSync or not Config.EMDSync.StatusSync or not Config.EMDSync.StatusSync.Enabled then
        return nil
    end

    local syncStatuses = Config.EMDSync.StatusSync.SyncStatuses
    local placeholders = {}
    local params = { lastStatusId }
    for i, status in ipairs(syncStatuses) do
        placeholders[i] = '?'
        params[i + 1] = status
    end

    local query = string.format([[
        SELECT id, number, date, time, sender, type, text
        FROM %s
        WHERE id > ?
        AND type = 'status'
        AND text IN (%s)
        ORDER BY id ASC
    ]], Config.EMDSync.StatusSync.SourceTable, table.concat(placeholders, ','))

    local result = ExecuteQuery(query, params)
    if Config.Debug and result and #result > 0 then
        print("^2[Heartbeat]^7 " .. #result .. " new status messages found")
    end
    return result
end

-- ========================================
-- FALLBACK STATUS QUEUE
-- ========================================

local function QueueFallbackStatus(vehicleName, status, time)
    table.insert(fallbackStatusQueue, {
        vehicle_name = vehicleName,
        status = tostring(status),
        time = time,
        date = os.date('%d.%m.%Y'),
        queued_at = os.time()
    })
end

local function DrainFallbackStatusQueue()
    if #fallbackStatusQueue == 0 then
        return nil
    end
    pendingFallbackStatuses = fallbackStatusQueue
    fallbackStatusQueue = {}
    return pendingFallbackStatuses
end

local function ConfirmFallbackStatuses()
    pendingFallbackStatuses = nil
end

-- Puts drained statuses back at the front of the queue after a failed
-- request so they aren't lost.
local function RestoreFallbackStatuses()
    if pendingFallbackStatuses then
        for i = #pendingFallbackStatuses, 1, -1 do
            table.insert(fallbackStatusQueue, 1, pendingFallbackStatuses[i])
        end
        pendingFallbackStatuses = nil
        if Config.Debug then
            print("^3[Heartbeat]^7 fallback statuses restored to queue (HTTP error)")
        end
    end
end

-- ========================================
-- MODULE COLLECTORS
-- ========================================

local function CollectDispatchData(tick)
    local mannedVehicles = GetMannedVehiclesCached(tick)
    if not mannedVehicles or #mannedVehicles == 0 then
        return nil
    end

    local dispatchNumbers = {}
    local dispatchNumberSet = {}
    for _, vehicle in ipairs(mannedVehicles) do
        if vehicle.dispatch and not dispatchNumberSet[vehicle.dispatch] then
            table.insert(dispatchNumbers, vehicle.dispatch)
            dispatchNumberSet[vehicle.dispatch] = true
        end
    end

    local dispatchDetails = GetDispatchListDetails(dispatchNumbers)
    local dispatchMap = {}
    for _, detail in ipairs(dispatchDetails) do
        local dispatchJson = json.decode(detail.dispatch)
        if dispatchJson then
            local dData = {
                postal = dispatchJson.postal or "",
                dispatch_code = dispatchJson.dispatch_code or "",
                dispatch_issue = dispatchJson.dispatch_issue or "",
                issue = dispatchJson.issue or "",
                caller_phonenumber = dispatchJson.caller_phonenumber or "",
                caller_name = dispatchJson.caller_name or "",
                location_x = dispatchJson.location_x or 0,
                location_y = dispatchJson.location_y or 0,
                bluelight = dispatchJson.bluelight or "no"
            }
            if dispatchJson.patienten and dispatchJson.patienten ~= "" then
                local patientenDecoded = json.decode(dispatchJson.patienten)
                if patientenDecoded then
                    local filteredPatienten = {}
                    for _, patient in ipairs(patientenDecoded) do
                        table.insert(filteredPatienten, {
                            alter = patient.alter or "",
                            vorname = patient.vorname or "",
                            nachname = patient.nachname or ""
                        })
                    end
                    dData.patienten = filteredPatienten
                end
            end
            dispatchMap[tostring(detail.number)] = dData
        end
    end

    local lagemeldungMap = {}
    if Config.EMDSync.LagemeldungSync and Config.EMDSync.LagemeldungSync.Enabled then
        lagemeldungMap = GetAllLagemeldungen(dispatchNumbers)
    end

    for _, vehicle in ipairs(mannedVehicles) do
        if vehicle.dispatch then
            local dispatchNumber = tostring(vehicle.dispatch)
            if dispatchMap[dispatchNumber] then
                vehicle.dispatch_data = dispatchMap[dispatchNumber]
                if lagemeldungMap[dispatchNumber] then
                    vehicle.dispatch_data.lagemeldungen = lagemeldungMap[dispatchNumber]
                end
            end
        end
    end

    return { vehicles = mannedVehicles }
end

local function CollectStatusUpdates()
    local statuses = GetNewStatusMessages()
    if not statuses or #statuses == 0 then
        return nil
    end

    local formatted = {}
    for _, status in ipairs(statuses) do
        table.insert(formatted, {
            id = status.id,
            mission_number = status.number,
            date = status.date,
            time = status.time,
            sender = status.sender,
            status = status.text,
            timestamp = status.date .. ' ' .. status.time
        })
    end

    return {
        last_id = lastStatusId,
        statuses = formatted
    }
end

local function CollectLagemeldungen(tick)
    local mannedVehicles = GetMannedVehiclesCached(tick)
    if not mannedVehicles or #mannedVehicles == 0 then
        return nil
    end

    local dispatchNumbers = {}
    local dispatchNumberSet = {}
    for _, vehicle in ipairs(mannedVehicles) do
        if vehicle.dispatch and not dispatchNumberSet[vehicle.dispatch] then
            table.insert(dispatchNumbers, vehicle.dispatch)
            dispatchNumberSet[vehicle.dispatch] = true
        end
    end

    if #dispatchNumbers == 0 then
        return nil
    end

    local lagemeldungMap = GetAllLagemeldungen(dispatchNumbers)
    if not next(lagemeldungMap) then
        return nil
    end

    local einsaetze = {}
    for einsatznummer, lagemeldungen in pairs(lagemeldungMap) do
        table.insert(einsaetze, {
            einsatznummer = einsatznummer,
            lagemeldungen = lagemeldungen
        })
    end

    return { einsaetze = einsaetze }
end

-- ========================================
-- VEHICLE REGISTRY (sent on request by the PHP side)
-- ========================================

local function SendVehicleRegistry()
    local result = ExecuteQuery("SELECT id, department, value, valuelong, job, grade, image, type, locked, funkkanal FROM emd_vehicles", {})

    if not result or #result == 0 then
        if Config.Debug then
            print("^3[VehicleRegistry]^7 no vehicles in emd_vehicles")
        end
        return
    end

    if Config.Debug then
        print("^2[VehicleRegistry]^7 sending " .. #result .. " vehicles")
    end

    local payload = {
        intraRP_API_Key = ServerConfig.APIKey,
        timestamp = os.time(),
        vehicle_registry = result
    }

    PerformHttpRequest(PHPEndpoint, function(statusCode, response, headers)
        if Config.Debug then
            if statusCode == 200 then
                print("^2[VehicleRegistry]^7 registry sent")
            else
                print("^1[VehicleRegistry]^7 send failed: " .. tostring(statusCode) .. " " .. tostring(response))
            end
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'FiveM-Heartbeat/2.0'
    })
end

-- ========================================
-- HEARTBEAT CORE
-- ========================================

local function BuildHeartbeatPayload(tick)
    local payload = {
        intraRP_API_Key = ServerConfig.APIKey,
        timestamp = os.time(),
        protocol_version = 2,
        serverName = GetConvar('sv_projectName', 'Unknown Server'),
        serverTime = os.date('%Y-%m-%d %H:%M:%S'),
        heartbeat = {
            tick = tick,
            interval = Config.EMDSync.HeartbeatInterval
        },
        request_modules = {}
    }

    local hasData = false

    if Config.EMDSync.DispatchSync and Config.EMDSync.DispatchSync.Enabled
       and tick % (Config.EMDSync.DispatchSync.TickMultiplier or 6) == 0 then
        local dispatchData = CollectDispatchData(tick)
        if dispatchData then
            payload.dispatch_data = dispatchData
            hasData = true
        end
    end

    if Config.EMDSync.StatusSync and Config.EMDSync.StatusSync.Enabled
       and tick % (Config.EMDSync.StatusSync.TickMultiplier or 1) == 0 then
        local statusData = CollectStatusUpdates()
        if statusData then
            payload.status_updates = statusData
            hasData = true
        end
        -- Even with nothing to send we want the poll response back
        table.insert(payload.request_modules, "status_poll")
        hasData = true
    end

    if Config.EMDSync.LagemeldungSync and Config.EMDSync.LagemeldungSync.Enabled
       and tick % (Config.EMDSync.LagemeldungSync.TickMultiplier or 6) == 0 then
        local lageData = CollectLagemeldungen(tick)
        if lageData then
            payload.lagemeldungen = lageData
            hasData = true
        end
        table.insert(payload.request_modules, "situation_reports")
        hasData = true
    end

    local fallbacks = DrainFallbackStatusQueue()
    if fallbacks and #fallbacks > 0 then
        payload.fallback_statuses = { entries = fallbacks }
        hasData = true
    end

    if not hasData then
        -- nothing to send, put drained fallbacks back
        RestoreFallbackStatuses()
        return nil
    end

    return payload
end

local apiKeyHintShown = false

local function HandleHeartbeatResponse(statusCode, response)
    if statusCode ~= 200 then
        -- a rejected key stops the whole sync, so say it without Debug too,
        -- once instead of on every heartbeat
        if (statusCode == 401 or statusCode == 403) and not apiKeyHintShown then
            apiKeyHintShown = true
            print("^1[Heartbeat]^7 API key rejected (" .. statusCode .. "), check ServerConfig.APIKey in config_server.lua")
        end
        if Config.Debug then
            print("^1[Heartbeat]^7 request failed, status code: " .. tostring(statusCode))
            if response then
                print("^1[Heartbeat]^7 response: " .. tostring(response))
            end
        end
        RestoreFallbackStatuses()
        isSyncing = false
        return
    end

    local responseData = json.decode(response)
    if not responseData then
        if Config.Debug then
            print("^1[Heartbeat]^7 invalid JSON response")
        end
        RestoreFallbackStatuses()
        isSyncing = false
        return
    end

    if responseData.status_poll and responseData.status_poll.status_changes then
        ProcessStatusChanges(responseData.status_poll.status_changes)
    end

    if responseData.situation_reports then
        ProcessSituationReports(responseData)
    end

    if responseData.patient_updates then
        ProcessPatientData(responseData)
    end

    if responseData.request_vehicle_registry then
        SendVehicleRegistry()
    end

    -- ack: move lastStatusId past everything the backend confirmed
    if responseData.status_ack and responseData.status_ack.successful_ids then
        for _, id in ipairs(responseData.status_ack.successful_ids) do
            if id > lastStatusId then
                lastStatusId = id
            end
        end
    end

    ConfirmFallbackStatuses()

    isSyncing = false
end

function PerformHeartbeat(tick)
    if not Config.EMDSync or not Config.EMDSync.Enabled then
        return
    end

    local payload = BuildHeartbeatPayload(tick)
    if not payload then
        return
    end

    isSyncing = true

    if Config.Debug then
        local modules = {}
        if payload.dispatch_data then table.insert(modules, "Dispatch") end
        if payload.status_updates then table.insert(modules, "Status(" .. #payload.status_updates.statuses .. ")") end
        if payload.lagemeldungen then table.insert(modules, "Lagemeldungen") end
        if payload.fallback_statuses then table.insert(modules, "Fallback(" .. #payload.fallback_statuses.entries .. ")") end
        if #payload.request_modules > 0 then table.insert(modules, "Poll:" .. table.concat(payload.request_modules, ",")) end
        print("^2[Heartbeat]^7 tick " .. tick .. " -> " .. table.concat(modules, " + "))
    end

    PerformHttpRequest(PHPEndpoint, function(statusCode, response, headers)
        HandleHeartbeatResponse(statusCode, response)
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'FiveM-Heartbeat/2.0'
    })
end

-- ========================================
-- HEARTBEAT TIMER
-- ========================================
CreateThread(function()
    Wait(5000) -- give the server a moment after startup

    if not Config or not Config.EMDSync or not Config.EMDSync.Enabled then
        if Config.Debug then
            print("^3[Heartbeat]^7 EMD sync disabled in config")
        end
        return
    end

    if Config.EMDSync.StatusSync and Config.EMDSync.StatusSync.Enabled then
        LoadLastStatusId()
    end

    local heartbeatInterval = Config.EMDSync.HeartbeatInterval or 5000

    if Config.Debug then
        print("^2[Heartbeat]^7 heartbeat started, base interval " .. (heartbeatInterval / 1000) .. "s, endpoint " .. PHPEndpoint)
    end

    -- first heartbeat right away (tick 0 fires every module)
    currentTick = 0
    PerformHeartbeat(currentTick)

    while true do
        Wait(heartbeatInterval)
        currentTick = currentTick + 1

        if not isSyncing then
            PerformHeartbeat(currentTick)
        elseif Config.Debug then
            print("^3[Heartbeat]^7 previous heartbeat still running, skipping tick " .. currentTick)
        end
    end
end)

-- ========================================
-- EVENT HANDLERS
-- ========================================

-- Statuses for vehicles without a dispatch go into the fallback queue
AddEventHandler('emergencydispatch:status:emf', function(fzg, status, time)
    if not Config.EMDSync or not Config.EMDSync.StatusSync or not Config.EMDSync.StatusSync.Enabled then
        return
    end

    local hasDispatch = false
    local success, mannedVehicles = pcall(function()
        return exports['emergencydispatch']:mannedvehicles()
    end)

    if success and mannedVehicles then
        for _, vehicle in ipairs(mannedVehicles) do
            if vehicle.value == fzg and vehicle.dispatch and vehicle.dispatch ~= 0 then
                hasDispatch = true
                break
            end
        end
    end

    if not hasDispatch then
        QueueFallbackStatus(fzg, status, time)
    end
end)

-- Manual sync triggered from the client, gated behind an ACE permission
RegisterServerEvent('emd:syncNow')
AddEventHandler('emd:syncNow', function()
    local source = source
    if IsPlayerAceAllowed(source, 'command.emdsync') then
        PerformHeartbeat(0)
    end
end)

-- Server-internal triggers for an immediate heartbeat (other resources
-- fire these via TriggerEvent, so no RegisterServerEvent here on purpose)
AddEventHandler('emd:vehicleAlerted', function()
    PerformHeartbeat(0)
end)

AddEventHandler('emd:statusChanged', function(vehicleId, newStatus)
    PerformHeartbeat(0)
end)

-- ========================================
-- COMMANDS & EXPORTS
-- ========================================

RegisterCommand('emdsync', function(source, args)
    if source == 0 or IsPlayerAceAllowed(source, 'command.emdsync') then
        PerformHeartbeat(0)
    end
end, true)

exports('syncHeartbeat', function()
    PerformHeartbeat(0)
end)

-- kept for scripts that still call the old per-module exports
exports('syncDispatchData', function() PerformHeartbeat(0) end)
exports('syncStatusMessages', function() PerformHeartbeat(0) end)
exports('syncLagemeldungen', function() PerformHeartbeat(0) end)

print("^2[Heartbeat]^7 EMD sync heartbeat loaded")
