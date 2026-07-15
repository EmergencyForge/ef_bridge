-- ========================================
-- URL HELPER FUNKTIONEN
-- ========================================
local function EnsureHttps(url)
    if not url or url == "" then
        return url
    end
    url = url:match("^%s*(.-)%s*$")
    if url:lower():sub(1, 7) == "http://" then
        url = "https://" .. url:sub(8)
        if Config.Debug then
            print("^3[EMD-Sync]^7 URL converted to HTTPS: " .. url)
        end
    elseif url:lower():sub(1, 8) ~= "https://" and url:sub(1, 2) ~= "//" then
        url = "https://" .. url
        if Config.Debug then
            print("^3[EMD-Sync]^7 HTTPS prefix added to URL: " .. url)
        end
    end
    return url
end

local function AddTrailingSlash(url)
    if url and url:sub(-1) ~= "/" then
        return url .. "/"
    end
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

-- Generiere PHPEndpoint einmalig beim Start
local PHPEndpoint = BuildURL("api/emd/sync.php")

if Config.Debug then
    print("^2[EMD-Sync]^7 PHPEndpoint generiert: " .. (PHPEndpoint or "FEHLER"))
end

-- ========================================
-- DATENBANK HILFSFUNKTIONEN
-- ========================================
local function ExecuteQuery(query, parameters)
    local promise = promise.new()
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute(query, parameters, function(result)
            promise:resolve(result)
        end)
    elseif MySQL and MySQL.Async then
        MySQL.Async.fetchAll(query, parameters, function(result)
            promise:resolve(result)
        end)
    else
        if Config.Debug then
            print("^1[EMD-Sync]^7 Keine MySQL-Resource gefunden! Bitte oxmysql oder mysql-async installieren.")
        end
        promise:resolve(nil)
    end
    return Citizen.Await(promise)
end

-- ========================================
-- HEARTBEAT STATE
-- ========================================
local currentTick = 0
local isSyncing = false
local lastStatusId = 0

-- Fallback Status Queue
local fallbackStatusQueue = {}
local pendingFallbackStatuses = nil

-- Mannedvehicles Cache (pro Tick)
local cachedMannedVehicles = nil
local cachedMannedVehiclesTick = -1

-- ========================================
-- RESPONSE-PROZESSOREN (PHP -> FiveM)
-- ========================================

-- Lagemeldungen aus PHP-Response in emergencydispatch einpflegen
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
                        if Config.Debug then
                            print("^2[Heartbeat]^7 Lagemeldung für Einsatz #" .. einsatznummer .. " eingepflegt: " .. text)
                        end
                    else
                        totalFailed = totalFailed + 1
                        if Config.Debug then
                            print("^1[Heartbeat]^7 Fehler beim Einpflegen der Lagemeldung für Einsatz #" .. einsatznummer)
                        end
                    end
                end
            end
        end
    end

    if Config.Debug and (totalSent > 0 or totalFailed > 0) then
        print("^2[Heartbeat]^7 Lagemeldungen verarbeitet: " .. totalSent .. " erfolgreich, " .. totalFailed .. " fehlgeschlagen")
    end
end

-- Statusänderungen von PHP (FireTab) auf Clients anwenden
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
                TriggerClientEvent('intraTab:applyStatus', playerSource, tostring(status))
                applied = applied + 1
                if Config.Debug then
                    print("^2[Heartbeat]^7 Status '" .. status .. "' an Spieler " .. playerSource .. " gesendet (Fahrzeug: " .. vehicleName .. ")")
                end
            else
                notFound = notFound + 1
                if Config.Debug then
                    print("^3[Heartbeat]^7 Kein Spieler für Fahrzeug '" .. vehicleName .. "' gefunden (Status: " .. status .. ")")
                end
            end
        end
    end

    if Config.Debug and (applied > 0 or notFound > 0) then
        print("^2[Heartbeat]^7 Statusänderungen verarbeitet: " .. applied .. " angewendet, " .. notFound .. " ohne Spieler")
    end
end

-- Patientendaten aus PHP-Response in emergencydispatch einpflegen
local function ProcessPatientData(responseData)
    if not responseData or not responseData.patient_updates then
        return
    end

    local totalAdded = 0
    local totalFailed = 0

    for key, patient in pairs(responseData.patient_updates) do
        -- Key kann "12345" oder "12345_1" sein -> Basis-Einsatznummer extrahieren
        local baseNummer = tostring(key):match("^(%d+)")
        local einsatznummer = tonumber(baseNummer)
        if not einsatznummer then
            if Config.Debug then
                print("^3[Heartbeat]^7 Ungültige Einsatznummer: " .. tostring(key) .. " - übersprungen")
            end
            goto continue
        end

        local vorname = patient.vorname or ""
        local nachname = patient.nachname or ""
        local alter = tostring(patient.alter or "")
        local pzc = ""  -- PZC nicht in PHP-Response
        local funkrufname = patient.funkrufname or ""
        local transportziel = patient.transportziel or ""

        if vorname ~= "" and nachname ~= "" then
            local success, result = pcall(function()
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
                if Config.Debug then
                    print("^2[Heartbeat]^7 Patient " .. vorname .. " " .. nachname .. " für Einsatz #" .. einsatznummer .. " eingepflegt")
                end
            else
                totalFailed = totalFailed + 1
                if Config.Debug then
                    print("^1[Heartbeat]^7 Fehler beim Einpflegen des Patienten für Einsatz #" .. einsatznummer .. ": " .. tostring(result))
                end
            end
        else
            if Config.Debug then
                print("^3[Heartbeat]^7 Patient für Einsatz #" .. einsatznummer .. " übersprungen (Vor-/Nachname fehlt)")
            end
        end
        ::continue::
    end

    if Config.Debug and (totalAdded > 0 or totalFailed > 0) then
        print("^2[Heartbeat]^7 Patientendaten verarbeitet: " .. totalAdded .. " eingepflegt, " .. totalFailed .. " fehlgeschlagen")
    end
end

-- ========================================
-- DATA COLLECTOR FUNKTIONEN
-- ========================================

-- Mannedvehicles mit Cache pro Tick (vermeidet redundante Export-Calls)
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
        if Config.Debug then
            print("^2[Heartbeat]^7 " .. #result .. " besetzte Fahrzeuge abgerufen (Tick " .. tick .. ")")
        end
        return result
    end

    if Config.Debug then
        print("^1[Heartbeat]^7 Fehler beim Abrufen von mannedvehicles()")
    end
    return nil
end

-- Dispatch-Details aus emd_dispatchlist
local function GetDispatchListDetails(dispatchNumbers)
    if not dispatchNumbers or #dispatchNumbers == 0 then
        return {}
    end
    local placeholders = {}
    for i = 1, #dispatchNumbers do
        table.insert(placeholders, '?')
    end
    local query = string.format([[
        SELECT id, number, dispatch
        FROM emd_dispatchlist
        WHERE number IN (%s)
    ]], table.concat(placeholders, ','))
    local result = ExecuteQuery(query, dispatchNumbers)
    if Config.Debug and result then
        print("^2[Heartbeat]^7 " .. #result .. " Dispatch-Details aus emd_dispatchlist gefunden")
    end
    return result or {}
end

-- Lagemeldungen für eine Einsatznummer
local function GetLagemeldungen(einsatznummer)
    if not einsatznummer then
        return nil
    end
    local success, lagemeldungen = pcall(function()
        return exports['emergencydispatch']:emf_lagemeldung_get(einsatznummer)
    end)
    if not success then
        if Config.Debug then
            print("^1[Heartbeat]^7 Fehler beim Abrufen der Lagemeldungen für Einsatz " .. tostring(einsatznummer))
        end
        return nil
    end
    if Config.Debug and lagemeldungen then
        local count = 0
        if type(lagemeldungen) == 'table' then
            count = #lagemeldungen
        end
        print("^2[Heartbeat]^7 " .. count .. " Lagemeldung(en) für Einsatz " .. tostring(einsatznummer) .. " abgerufen")
    end
    return lagemeldungen
end

-- Lagemeldungen für mehrere Einsatznummern
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
    if Config.Debug then
        local count = 0
        for _ in pairs(lagemeldungMap) do count = count + 1 end
        print("^2[Heartbeat]^7 Lagemeldungen für " .. count .. " Einsätze abgerufen")
    end
    return lagemeldungMap
end

-- Letzte Status-ID laden
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
            print("^2[Heartbeat]^7 Letzte Status-ID geladen: " .. lastStatusId)
        end
    end
end

-- Neue Statusmeldungen aus DB
local function GetNewStatusMessages()
    if not Config.EMDSync or not Config.EMDSync.StatusSync or not Config.EMDSync.StatusSync.Enabled then
        return nil
    end
    local statusList = table.concat(Config.EMDSync.StatusSync.SyncStatuses, "','")
    local query = string.format([[
        SELECT id, number, date, time, sender, type, text
        FROM %s
        WHERE id > ?
        AND type = 'status'
        AND text IN ('%s')
        ORDER BY id ASC
    ]], Config.EMDSync.StatusSync.SourceTable, statusList)
    local result = ExecuteQuery(query, {lastStatusId})
    if Config.Debug and result and #result > 0 then
        print("^2[Heartbeat]^7 " .. #result .. " neue Statusmeldungen gefunden")
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
    if Config.Debug then
        print("^2[Heartbeat]^7 Fallback-Status in Queue: " .. tostring(vehicleName) .. " -> " .. tostring(status) .. " (Queue: " .. #fallbackStatusQueue .. ")")
    end
end

local function DrainFallbackStatusQueue()
    if #fallbackStatusQueue == 0 then
        return nil
    end
    pendingFallbackStatuses = fallbackStatusQueue
    fallbackStatusQueue = {}
    if Config.Debug then
        print("^2[Heartbeat]^7 " .. #pendingFallbackStatuses .. " Fallback-Status aus Queue entnommen")
    end
    return pendingFallbackStatuses
end

local function ConfirmFallbackStatuses()
    pendingFallbackStatuses = nil
end

local function RestoreFallbackStatuses()
    if pendingFallbackStatuses then
        for i = #pendingFallbackStatuses, 1, -1 do
            table.insert(fallbackStatusQueue, 1, pendingFallbackStatuses[i])
        end
        pendingFallbackStatuses = nil
        if Config.Debug then
            print("^3[Heartbeat]^7 Fallback-Status zurück in Queue (HTTP-Fehler)")
        end
    end
end

-- ========================================
-- MODUL COLLECTOR FUNKTIONEN
-- ========================================

-- Dispatch-Daten sammeln (Fahrzeuge + Einsatzdetails + Patienten + Lagemeldungen)
local function CollectDispatchData(tick)
    local mannedVehicles = GetMannedVehiclesCached(tick)
    if not mannedVehicles or #mannedVehicles == 0 then
        return nil
    end

    -- Sammle Einsatznummern
    local dispatchNumbers = {}
    local dispatchNumberSet = {}
    for _, vehicle in ipairs(mannedVehicles) do
        if vehicle.dispatch and not dispatchNumberSet[vehicle.dispatch] then
            table.insert(dispatchNumbers, vehicle.dispatch)
            dispatchNumberSet[vehicle.dispatch] = true
        end
    end

    -- Hole Dispatch-Details aus DB
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
            -- Patientendaten
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

    -- Lagemeldungen (wenn aktiviert)
    local lagemeldungMap = {}
    if Config.EMDSync.LagemeldungSync and Config.EMDSync.LagemeldungSync.Enabled then
        lagemeldungMap = GetAllLagemeldungen(dispatchNumbers)
    end

    -- Fahrzeuge mit Dispatch-Daten anreichern
    for _, vehicle in ipairs(mannedVehicles) do
        if vehicle.dispatch then
            local dispatchNumber = tostring(vehicle.dispatch)
            if dispatchMap[dispatchNumber] then
                vehicle.dispatch_data = dispatchMap[dispatchNumber]
                if lagemeldungMap[dispatchNumber] then
                    vehicle.dispatch_data.lagemeldungen = lagemeldungMap[dispatchNumber]
                end
                if Config.Debug then
                    local patientInfo = ""
                    if dispatchMap[dispatchNumber].patienten then
                        patientInfo = " (inkl. " .. #dispatchMap[dispatchNumber].patienten .. " Patient(en))"
                    end
                    local lageInfo = ""
                    if lagemeldungMap[dispatchNumber] then
                        lageInfo = " (inkl. " .. #lagemeldungMap[dispatchNumber] .. " Lagemeldung(en))"
                    end
                    print("^2[Heartbeat]^7 Dispatch-Daten für Einsatz " .. vehicle.dispatch .. " hinzugefügt" .. patientInfo .. lageInfo)
                end
            end
        end
    end

    return { vehicles = mannedVehicles }
end

-- Status-Updates sammeln (FiveM -> PHP)
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

-- Lagemeldungen sammeln (standalone)
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
-- VEHICLE REGISTRY (on-demand, triggered by PHP response)
-- ========================================

local function SendVehicleRegistry()
    local result = ExecuteQuery("SELECT id, department, value, valuelong, job, grade, image, type, locked, funkkanal FROM emd_vehicles", {})

    if not result or #result == 0 then
        if Config.Debug then
            print("^3[VehicleRegistry]^7 Keine Fahrzeuge in emd_vehicles gefunden")
        end
        return
    end

    if Config.Debug then
        print("^2[VehicleRegistry]^7 " .. #result .. " Fahrzeuge geladen, sende an PHP...")
    end

    local payload = {
        intraRP_API_Key = Config.APIKey,
        timestamp = os.time(),
        vehicle_registry = result
    }

    PerformHttpRequest(PHPEndpoint, function(statusCode, response, headers)
        if Config.Debug then
            if statusCode == 200 then
                print("^2[VehicleRegistry]^7 Fahrzeugregister erfolgreich gesendet")
            else
                print("^1[VehicleRegistry]^7 Fehler beim Senden: " .. tostring(statusCode) .. " " .. tostring(response))
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
        intraRP_API_Key = Config.APIKey,
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

    -- Dispatch-Daten (Fahrzeuge + Einsatzdetails)
    if Config.EMDSync.DispatchSync and Config.EMDSync.DispatchSync.Enabled
       and tick % (Config.EMDSync.DispatchSync.TickMultiplier or 6) == 0 then
        local dispatchData = CollectDispatchData(tick)
        if dispatchData then
            payload.dispatch_data = dispatchData
            hasData = true
        end
    end

    -- Status-Updates (FiveM -> PHP)
    if Config.EMDSync.StatusSync and Config.EMDSync.StatusSync.Enabled
       and tick % (Config.EMDSync.StatusSync.TickMultiplier or 1) == 0 then
        local statusData = CollectStatusUpdates()
        if statusData then
            payload.status_updates = statusData
            hasData = true
        end
        -- Status-Poll anfordern (PHP -> FiveM)
        table.insert(payload.request_modules, "status_poll")
        hasData = true -- Auch ohne ausgehende Daten wollen wir die Poll-Antwort
    end

    -- Lagemeldungen (standalone)
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

    -- Fallback-Status-Queue (immer prüfen)
    local fallbacks = DrainFallbackStatusQueue()
    if fallbacks and #fallbacks > 0 then
        payload.fallback_statuses = { entries = fallbacks }
        hasData = true
    end

    if not hasData then
        -- Nichts zu senden, Fallback-Queue wiederherstellen falls drained
        RestoreFallbackStatuses()
        return nil
    end

    return payload
end

local function HandleHeartbeatResponse(statusCode, response)
    if statusCode ~= 200 then
        if Config.Debug then
            print("^1[Heartbeat]^7 Fehler. Statuscode: " .. tostring(statusCode))
            if statusCode == 401 then
                print("^1[Heartbeat]^7 API-Key ungültig! Bitte Config.APIKey in config.lua korrekt setzen.")
            end
            if response then
                print("^1[Heartbeat]^7 Antwort: " .. tostring(response))
            end
        end
        -- Fallback-Queue wiederherstellen bei Fehler
        RestoreFallbackStatuses()
        isSyncing = false
        return
    end

    if Config.Debug then
        print("^2[Heartbeat]^7 Antwort empfangen: " .. tostring(response))
    end

    local responseData = json.decode(response)
    if not responseData then
        if Config.Debug then
            print("^1[Heartbeat]^7 Ungültige JSON-Antwort")
        end
        RestoreFallbackStatuses()
        isSyncing = false
        return
    end

    -- Status-Poll verarbeiten (PHP -> FiveM)
    if responseData.status_poll and responseData.status_poll.status_changes then
        ProcessStatusChanges(responseData.status_poll.status_changes)
    end

    -- Lagemeldungen aus Response verarbeiten (PHP -> emergencydispatch)
    if responseData.situation_reports then
        ProcessSituationReports(responseData)
    end

    -- Patientendaten aus Response verarbeiten (PHP -> emergencydispatch)
    if responseData.patient_updates then
        ProcessPatientData(responseData)
    end

    -- Vehicle Registry senden wenn angefordert
    if responseData.request_vehicle_registry then
        if Config.Debug then
            print("^2[Heartbeat]^7 PHP fordert Fahrzeugregister an - sende...")
        end
        SendVehicleRegistry()
    end

    -- Status-ACK verarbeiten (lastStatusId aktualisieren)
    if responseData.status_ack and responseData.status_ack.successful_ids then
        for _, id in ipairs(responseData.status_ack.successful_ids) do
            if id > lastStatusId then
                lastStatusId = id
            end
        end
        if Config.Debug then
            print("^2[Heartbeat]^7 lastStatusId aktualisiert: " .. lastStatusId)
        end
    end

    -- Fallback-Status bestätigen (erfolgreich gesendet)
    ConfirmFallbackStatuses()

    isSyncing = false
end

function PerformHeartbeat(tick)
    if not Config.EMDSync or not Config.EMDSync.Enabled then
        return
    end

    if not PHPEndpoint then
        if Config.Debug then
            print("^1[Heartbeat]^7 PHPEndpoint nicht verfügbar!")
        end
        return
    end

    local payload = BuildHeartbeatPayload(tick)
    if not payload then
        if Config.Debug then
            print("^3[Heartbeat]^7 Tick " .. tick .. ": Nichts zu senden, überspringe")
        end
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
        print("^2[Heartbeat]^7 Tick " .. tick .. " -> " .. table.concat(modules, " + "))
    end

    PerformHttpRequest(PHPEndpoint, function(statusCode, response, headers)
        HandleHeartbeatResponse(statusCode, response)
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'FiveM-Heartbeat/2.0'
    })
end

-- ========================================
-- HEARTBEAT TIMER (ersetzt alle bisherigen Timer)
-- ========================================
CreateThread(function()
    Wait(5000) -- Warte nach Server-Start

    if not Config or not Config.EMDSync or not Config.EMDSync.Enabled then
        if Config.Debug then
            print("^3[Heartbeat]^7 EMD-Sync ist in der Konfiguration deaktiviert")
        end
        return
    end

    -- Initialisierung
    if Config.EMDSync.StatusSync and Config.EMDSync.StatusSync.Enabled then
        LoadLastStatusId()
    end

    local heartbeatInterval = Config.EMDSync.HeartbeatInterval or 5000

    if Config.Debug then
        print("^2[Heartbeat]^7 ==============================")
        print("^2[Heartbeat]^7 Konsolidierter Heartbeat gestartet")
        print("^2[Heartbeat]^7 Basis-Intervall: " .. (heartbeatInterval / 1000) .. "s")
        print("^2[Heartbeat]^7 Endpunkt: " .. PHPEndpoint)
        if Config.EMDSync.DispatchSync and Config.EMDSync.DispatchSync.Enabled then
            print("^2[Heartbeat]^7   DispatchSync: aktiv (alle " .. ((Config.EMDSync.DispatchSync.TickMultiplier or 6) * heartbeatInterval / 1000) .. "s)")
        end
        if Config.EMDSync.StatusSync and Config.EMDSync.StatusSync.Enabled then
            print("^2[Heartbeat]^7   StatusSync: aktiv (alle " .. ((Config.EMDSync.StatusSync.TickMultiplier or 1) * heartbeatInterval / 1000) .. "s)")
            print("^2[Heartbeat]^7   Überwachte Status: " .. table.concat(Config.EMDSync.StatusSync.SyncStatuses, ", "))
        end
        if Config.EMDSync.LagemeldungSync and Config.EMDSync.LagemeldungSync.Enabled then
            print("^2[Heartbeat]^7   LagemeldungSync: aktiv (alle " .. ((Config.EMDSync.LagemeldungSync.TickMultiplier or 6) * heartbeatInterval / 1000) .. "s)")
        end
        print("^2[Heartbeat]^7 ==============================")
    end

    -- Erster Heartbeat sofort (tick 0 = alle Module feuern)
    currentTick = 0
    PerformHeartbeat(currentTick)

    -- Heartbeat-Loop
    while true do
        Wait(heartbeatInterval)
        currentTick = currentTick + 1

        if not isSyncing then
            PerformHeartbeat(currentTick)
        else
            if Config.Debug then
                print("^3[Heartbeat]^7 Vorheriger Heartbeat noch aktiv, überspringe Tick " .. currentTick)
            end
        end
    end
end)

-- ========================================
-- EVENT HANDLER
-- ========================================

-- Fallback: Statusmeldungen ohne Einsatzzuordnung in Queue
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
        if Config.Debug then
            print("^2[Heartbeat]^7 Fahrzeug '" .. tostring(fzg) .. "' hat keinen Einsatz - Queue Fallback-Status")
        end
        QueueFallbackStatus(fzg, status, time)
    else
        if Config.Debug then
            print("^3[Heartbeat]^7 Fahrzeug '" .. tostring(fzg) .. "' hat Einsatz - normaler StatusSync greift")
        end
    end
end)

-- Manuelle Synchronisation
RegisterServerEvent('emd:syncNow')
AddEventHandler('emd:syncNow', function()
    local source = source
    if IsPlayerAceAllowed(source, 'command.emdsync') then
        if Config.Debug then
            print("^2[Heartbeat]^7 Manuelle Synchronisierung durch Spieler " .. source)
        end
        PerformHeartbeat(0)
    end
end)

-- Fahrzeug-Alarmierung
RegisterServerEvent('emd:vehicleAlerted')
AddEventHandler('emd:vehicleAlerted', function()
    if Config.Debug then
        print("^2[Heartbeat]^7 Fahrzeugalarmierung - sofortiger Heartbeat")
    end
    PerformHeartbeat(0)
end)

-- Status-Änderung
RegisterServerEvent('emd:statusChanged')
AddEventHandler('emd:statusChanged', function(vehicleId, newStatus)
    if Config.Debug then
        print("^2[Heartbeat]^7 Status geändert: " .. tostring(vehicleId) .. " -> " .. tostring(newStatus))
    end
    PerformHeartbeat(0)
end)

-- ========================================
-- COMMANDS & EXPORTS
-- ========================================

RegisterCommand('emdsync', function(source, args)
    if source == 0 or IsPlayerAceAllowed(source, 'command.emdsync') then
        if Config.Debug then
            print("^2[Heartbeat]^7 Manueller Heartbeat ausgelöst")
        end
        PerformHeartbeat(0)
    end
end, true)

-- Neuer Haupt-Export
exports('syncHeartbeat', function()
    PerformHeartbeat(0)
end)

-- Backward-kompatible Wrapper
exports('syncDispatchData', function() PerformHeartbeat(0) end)
exports('syncStatusMessages', function() PerformHeartbeat(0) end)
exports('syncLagemeldungen', function() PerformHeartbeat(0) end)

print("^2[Heartbeat]^7 EMD-Sync Heartbeat v2 erfolgreich geladen!")
