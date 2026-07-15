-- ========================================
-- eNOTF ABRECHNUNGSSYSTEM
-- ========================================
-- Diese Datei stellt eine Schnittstelle zur Verfügung, um freigegebene eNOTF-Protokolle
-- für Abrechnungszwecke abzurufen. Die Daten werden dedupliziert nach Name + Einsatznummer.
--
-- RÜCKGABEFORMAT:
-- {
--   {
--     name = "Max Mustermann",
--     birthdate = "1990-01-15",  -- Format: YYYY-MM-DD
--     transport = true,           -- Boolean: true wenn Transport durchgeführt wurde
--     missionNumber = "ENR_123",  -- Einsatznummer (kann auch ENR_X Format sein)
--     protocolType = 1,           -- Numerisch: Art des Protokolls (0 = Notarzt, 1 = Rettungsdienst, etc.)
--     vehicleCallsign = "RTW 1-82-1" -- String: Rufname des Fahrzeugs
--   },
--   ...
-- }
-- ========================================

-- Funktion zum Ausführen von MySQL-Queries (nutzt vorhandene Framework-DB-Connection)
local function ExecuteQuery(query, parameters)
    local promise = promise.new()
    
    -- Versuche oxmysql (QBCore/ESX modern)
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute(query, parameters, function(result)
            promise:resolve(result)
        end)
    -- Fallback auf mysql-async (ESX legacy)
    elseif MySQL and MySQL.Async then
        MySQL.Async.fetchAll(query, parameters, function(result)
            promise:resolve(result)
        end)
    else
        if Config.Debug then
            print("^1[eNOTF-Billing]^7 Keine MySQL-Resource gefunden! Bitte oxmysql oder mysql-async installieren.")
        end
        promise:resolve(nil)
    end
    
    return Citizen.Await(promise)
end

-- Stelle sicher, dass URLs HTTPS verwenden (FiveM-Anforderung)
local function EnsureHttps(url)
    if not url or url == "" then
        return url
    end
    
    url = url:match("^%s*(.-)%s*$")
    
    if url:lower():sub(1, 7) == "http://" then
        url = "https://" .. url:sub(8)
    elseif url:lower():sub(1, 8) ~= "https://" and url:sub(1, 2) ~= "//" then
        url = "https://" .. url
    end
    
    return url
end

-- Füge trailing slash hinzu
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
    
    if basePath and basePath:sub(1, 1) == "/" then
        basePath = basePath:sub(2)
    end
    
    return baseURL .. (basePath or "")
end

-- Generiere API-Endpunkt für eNOTF-Abrechnung
local BillingEndpoint = BuildURL("api/enotf/billing.php")

if Config.Debug then
    print("^2[eNOTF-Billing]^7 BillingEndpoint generiert: " .. (BillingEndpoint or "FEHLER"))
end

-- ========================================
-- HAUPTFUNKTION: Abrufen der freigegebenen eNOTF-Protokolle
-- ========================================
function GetReleasedENOTFProtocols()
    if not Config.ENOTFBilling or not Config.ENOTFBilling.Enabled then
        if Config.Debug then
            print("^3[eNOTF-Billing]^7 Abrechnungssystem ist deaktiviert")
        end
        return {}
    end
    
    if not BillingEndpoint then
        if Config.Debug then
            print("^1[eNOTF-Billing]^7 Fehler: BillingEndpoint konnte nicht generiert werden!")
        end
        return {}
    end
    
    -- Prüfe API-Key
    if not Config.APIKey or Config.APIKey == "" or Config.APIKey == "CHANGE_ME" then
        print("^1[eNOTF-Billing]^7 ❌ FEHLER: API-Key ist nicht gesetzt!")
        print("^3[eNOTF-Billing]^7 Bitte setze 'Config.APIKey' in der config.lua")
        return {}
    end
    
    if Config.Debug then
        print("^2[eNOTF-Billing]^7 Abfrage der freigegebenen eNOTF-Protokolle...")
        print("^2[eNOTF-Billing]^7 API-Endpunkt: " .. BillingEndpoint)
        print("^2[eNOTF-Billing]^7 API-Key (erste 8 Zeichen): " .. string.sub(Config.APIKey, 1, 8) .. "...")
    end
    
    local promise = promise.new()
    
    PerformHttpRequest(BillingEndpoint, function(statusCode, response, headers)
        if statusCode == 200 then
            local success, data = pcall(json.decode, response)
            
            if success and data then
                if Config.Debug then
                    print("^2[eNOTF-Billing]^7 " .. (data.count or 0) .. " Protokolle erfolgreich abgerufen")
                end
                
                -- Deduplizierung: Name + Einsatznummer (innerhalb der aktuellen Anfrage)
                local deduplicatedData = DeduplicateProtocols(data.protocols or {})
                
                -- Filter: Bereits verarbeitete Protokolle ausschließen (über mehrere Anfragen)
                if Config.ENOTFBilling.FilterProcessed then
                    deduplicatedData = FilterAlreadyProcessed(deduplicatedData)
                end
                
                promise:resolve(deduplicatedData)
            else
                if Config.Debug then
                    print("^1[eNOTF-Billing]^7 Fehler beim Parsen der JSON-Antwort")
                end
                promise:resolve({})
            end
        else
            if Config.Debug then
                print("^1[eNOTF-Billing]^7 Fehler beim Abrufen der Daten. Statuscode: " .. statusCode)
                if response then
                    print("^1[eNOTF-Billing]^7 Antwort: " .. response)
                end
            end
            promise:resolve({})
        end
    end, 'POST', json.encode({
        intraRP_API_Key = Config.APIKey,
        timestamp = os.time()
    }), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'FiveM-eNOTF-Billing/1.0'
    })
    
    return Citizen.Await(promise)
end

-- ========================================
-- HILFSFUNKTION: Basis-Einsatznummer extrahieren
-- ========================================
local function GetBaseMissionNumber(missionNumber)
    if not missionNumber then return "" end
    -- Extrahiere die Basis-Nummer vor dem "_" (z.B. "123" aus "123_1")
    local baseNumber = missionNumber:match("^(%d+)")
    return baseNumber or missionNumber
end

-- ========================================
-- DEDUPLIZIERUNG: Name + Basis-Einsatznummer
-- ========================================
-- Verhindert mehrfache Abrechnung: Name + 123, Name + 123_1, Name + 123_2 = nur 1x
function DeduplicateProtocols(protocols)
    if not protocols or #protocols == 0 then
        return {}
    end
    
    local uniqueMap = {}
    local deduplicated = {}
    
    for _, protocol in ipairs(protocols) do
        -- Extrahiere Basis-Einsatznummer (vor dem "_")
        local baseNumber = GetBaseMissionNumber(protocol.missionNumber)
        
        -- Erstelle eindeutigen Schlüssel: Name + Basis-Einsatznummer
        local key = (protocol.name or "") .. "|" .. baseNumber
        
        if not uniqueMap[key] then
            uniqueMap[key] = true
            table.insert(deduplicated, protocol)
        else
            if Config.Debug then
                print("^3[eNOTF-Billing]^7 Duplikat ignoriert: " .. protocol.name .. " + " .. protocol.missionNumber .. " (Basis: " .. baseNumber .. ")")
            end
        end
    end
    
    if Config.Debug then
        print("^2[eNOTF-Billing]^7 Deduplizierung: " .. #protocols .. " -> " .. #deduplicated .. " Protokolle")
    end
    
    return deduplicated
end

-- ========================================
-- FILTER: Bereits verarbeitete Protokolle ausschließen
-- ========================================
-- Prüft gegen die lokale FiveM-Datenbank, welche Protokolle bereits verarbeitet wurden
function FilterAlreadyProcessed(protocols)
    if not protocols or #protocols == 0 then
        return {}
    end
    
    -- Erstelle Liste aller Kombinationen aus Name + Basis-Einsatznummer
    local keys = {}
    for _, protocol in ipairs(protocols) do
        local baseNumber = GetBaseMissionNumber(protocol.missionNumber)
        local key = (protocol.name or "") .. "|" .. baseNumber
        table.insert(keys, key)
    end
    
    -- Erstelle Platzhalter für SQL IN-Klausel
    local placeholders = {}
    for i = 1, #keys do
        table.insert(placeholders, '?')
    end
    
    -- Hinweis: mission_number in DB sollte bereits die Basis-Nummer sein (ohne _X Suffix)
    local query = string.format([[
        SELECT CONCAT(name, '|', mission_number) as combination_key
        FROM enotf_billing
        WHERE CONCAT(name, '|', mission_number) IN (%s)
    ]], table.concat(placeholders, ','))
    
    local result = ExecuteQuery(query, keys)
    
    -- Erstelle Set der bereits verarbeiteten Kombinationen
    local processedSet = {}
    if result then
        for _, row in ipairs(result) do
            processedSet[row.combination_key] = true
        end
    end
    
    -- Filtere bereits verarbeitete Protokolle heraus
    local filtered = {}
    for _, protocol in ipairs(protocols) do
        local baseNumber = GetBaseMissionNumber(protocol.missionNumber)
        local key = (protocol.name or "") .. "|" .. baseNumber
        
        if not processedSet[key] then
            table.insert(filtered, protocol)
        else
            if Config.Debug then
                print("^3[eNOTF-Billing]^7 Bereits verarbeitet, übersprungen: " .. protocol.name .. " + " .. protocol.missionNumber .. " (Basis: " .. baseNumber .. ")")
            end
        end
    end
    
    if Config.Debug and #protocols > #filtered then
        print("^2[eNOTF-Billing]^7 Filter: " .. #protocols .. " -> " .. #filtered .. " Protokolle (bereits verarbeitet ausgeschlossen)")
    end
    
    return filtered
end

-- ========================================
-- EXPORT: Für externe Verwendung
-- ========================================
exports('getReleasedENOTFProtocols', GetReleasedENOTFProtocols)

-- ========================================
-- SERVER CALLBACK: Für Clientseitige Abfrage
-- ========================================
RegisterServerEvent('enotf-billing:requestProtocols')
AddEventHandler('enotf-billing:requestProtocols', function()
    local src = source
    local protocols = GetReleasedENOTFProtocols()
    
    TriggerClientEvent('enotf-billing:receiveProtocols', src, protocols)
end)

-- ========================================
-- AUTOMATISCHE SYNC-FUNKTION (optional)
-- ========================================
if Config.ENOTFBilling and Config.ENOTFBilling.Enabled and Config.ENOTFBilling.AutoSync then
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Config.ENOTFBilling.SyncInterval or 300000) -- Standard: 5 Minuten
            
            local protocols = GetReleasedENOTFProtocols()
            
            if protocols and #protocols > 0 then
                -- Trigger Custom-Handler in billing-custom.lua
                TriggerEvent('enotf-billing:autoSync', protocols)
            end
        end
    end)
end

-- ========================================
-- MANUELLER COMMAND FÜR ADMINISTRATOREN
-- ========================================
RegisterCommand('enotf-billing-sync', function(source, args, rawCommand)
    local src = source
    
    -- Überprüfe Admin-Rechte (passe dies an dein Framework an)
    if src > 0 then
        -- Hier kannst du Admin-Checks hinzufügen
    end
    
    print("^2[eNOTF-Billing]^7 Manueller Sync gestartet von Source: " .. src)
    
    local protocols = GetReleasedENOTFProtocols()
    
    if protocols and #protocols > 0 then
        print("^2[eNOTF-Billing]^7 " .. #protocols .. " Protokolle abgerufen:")
        
        for i, protocol in ipairs(protocols) do
            print(string.format("  [%d] %s | Geburtsdatum: %s | Transport: %s | Einsatz: %s | Protokollart: %s | Fahrzeug: %s",
                i,
                protocol.name,
                protocol.birthdate,
                protocol.transport and "Ja" or "Nein",
                protocol.missionNumber,
                protocol.protocolType or "N/A",
                protocol.vehicleCallsign or "N/A"
            ))
        end
        
        -- Trigger Custom-Handler in billing-custom.lua
        TriggerEvent('enotf-billing:manualSync', protocols, src)
        
        if src > 0 then
            TriggerClientEvent('chat:addMessage', src, {
                args = {"^2[eNOTF-Billing]", "Sync erfolgreich: " .. #protocols .. " Protokolle abgerufen"}
            })
        end
    else
        print("^3[eNOTF-Billing]^7 Keine Protokolle gefunden oder Fehler beim Abrufen")
        
        if src > 0 then
            TriggerClientEvent('chat:addMessage', src, {
                args = {"^1[eNOTF-Billing]", "Keine Protokolle gefunden"}
            })
        end
    end
end, false)

-- ========================================
-- AUTOMATISCHE DATENBANK-TABELLEN-PRÜFUNG
-- ========================================
if Config.ENOTFBilling and Config.ENOTFBilling.Enabled and Config.ENOTFBilling.FilterProcessed then
    Citizen.CreateThread(function()
        Citizen.Wait(2000) -- Warte 2 Sekunden für Datenbankverbindung
        
        if Config.Debug then
            print("^2[eNOTF-Billing]^7 Prüfe Datenbank-Tabelle 'enotf_billing'...")
        end
        
        -- Prüfe, ob Tabelle existiert
        local checkQuery = [[
            SELECT COUNT(*) as count 
            FROM information_schema.TABLES 
            WHERE TABLE_NAME = 'enotf_billing' 
            AND TABLE_SCHEMA = DATABASE()
        ]]
        
        local result = ExecuteQuery(checkQuery, {})
        
        if result and result[1] and result[1].count == 0 then
            print("^3[eNOTF-Billing]^7 Tabelle 'enotf_billing' nicht gefunden, erstelle automatisch...")
            
            -- Erstelle Tabelle
            local createQuery = [[
                CREATE TABLE IF NOT EXISTS enotf_billing (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    birthdate DATE NOT NULL,
                    transport BOOLEAN NOT NULL DEFAULT 0,
                    mission_number VARCHAR(50) NOT NULL,
                    amount DECIMAL(10,2) DEFAULT 0.00,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    processed BOOLEAN DEFAULT 0,
                    processed_at TIMESTAMP NULL,
                    invoice_number VARCHAR(50) NULL,
                    notes TEXT NULL,
                    UNIQUE KEY unique_billing (name, mission_number),
                    INDEX idx_mission (mission_number),
                    INDEX idx_name (name),
                    INDEX idx_processed (processed)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ]]
            
            local createResult = ExecuteQuery(createQuery, {})
            
            if createResult ~= nil then
                print("^2[eNOTF-Billing]^7 ✅ Tabelle 'enotf_billing' erfolgreich erstellt!")
            else
                print("^1[eNOTF-Billing]^7 ❌ Fehler beim Erstellen der Tabelle 'enotf_billing'!")
                print("^1[eNOTF-Billing]^7 Bitte erstelle die Tabelle manuell (siehe sql_examples.sql)")
            end
        elseif result and result[1] and result[1].count > 0 then
            if Config.Debug then
                print("^2[eNOTF-Billing]^7 ✅ Tabelle 'enotf_billing' existiert bereits")
            end
        else
            print("^1[eNOTF-Billing]^7 ⚠️ Konnte Tabelle nicht prüfen. Stelle sicher, dass eine MySQL-Datenbank verbunden ist.")
        end
    end)
end

print("^2[eNOTF-Billing]^7 Abrechnungssystem geladen")
