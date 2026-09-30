-- eNOTF billing: fetches released eNOTF protocols from ignis so servers
-- can bill patients. Results are deduplicated by name + mission number.
--
-- Returned protocol format:
-- {
--   {
--     name = "Max Mustermann",
--     birthdate = "1990-01-15",      -- YYYY-MM-DD
--     transport = true,              -- whether the patient was transported
--     missionNumber = "ENR_123",
--     protocolType = 1,              -- 0 = Notarzt, 1 = Rettungsdienst, ...
--     vehicleCallsign = "RTW 1-82-1"
--   },
--   ...
-- }

local function ExecuteQuery(query, parameters)
    local p = promise.new()

    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute(query, parameters, function(result)
            p:resolve(result)
        end)
    elseif MySQL and MySQL.Async then
        -- mysql-async fallback for older ESX setups
        MySQL.Async.fetchAll(query, parameters, function(result)
            p:resolve(result)
        end)
    else
        if Config.Debug then
            print("^1[eNOTF-Billing]^7 No MySQL resource found. Install oxmysql or mysql-async.")
        end
        p:resolve(nil)
    end

    return Citizen.Await(p)
end

local BillingEndpoint = BuildURL("api/enotf/billing.php")

if Config.Debug then
    print("^2[eNOTF-Billing]^7 endpoint: " .. (BillingEndpoint or "MISSING"))
end

-- Pulls the base number out of mission numbers like "123_1" -> "123"
local function GetBaseMissionNumber(missionNumber)
    if not missionNumber then return "" end
    local baseNumber = missionNumber:match("^(%d+)")
    return baseNumber or missionNumber
end

-- Dedup within one response: name + 123, name + 123_1, name + 123_2
-- must only be billed once.
local function DeduplicateProtocols(protocols)
    if not protocols or #protocols == 0 then
        return {}
    end

    local seen = {}
    local deduplicated = {}

    for _, protocol in ipairs(protocols) do
        local baseNumber = GetBaseMissionNumber(protocol.missionNumber)
        local key = (protocol.name or "") .. "|" .. baseNumber

        if not seen[key] then
            seen[key] = true
            table.insert(deduplicated, protocol)
        elseif Config.Debug then
            print("^3[eNOTF-Billing]^7 duplicate skipped: " .. protocol.name .. " + " .. protocol.missionNumber)
        end
    end

    if Config.Debug then
        print("^2[eNOTF-Billing]^7 dedup: " .. #protocols .. " -> " .. #deduplicated .. " protocols")
    end

    return deduplicated
end

-- Dedup across requests: drop protocols that are already stored in the
-- local enotf_billing table.
local function FilterAlreadyProcessed(protocols)
    if not protocols or #protocols == 0 then
        return {}
    end

    local keys = {}
    for _, protocol in ipairs(protocols) do
        local baseNumber = GetBaseMissionNumber(protocol.missionNumber)
        table.insert(keys, (protocol.name or "") .. "|" .. baseNumber)
    end

    local placeholders = {}
    for i = 1, #keys do
        placeholders[i] = '?'
    end

    -- mission_number in the DB is expected to be the base number already
    local query = string.format([[
        SELECT CONCAT(name, '|', mission_number) as combination_key
        FROM enotf_billing
        WHERE CONCAT(name, '|', mission_number) IN (%s)
    ]], table.concat(placeholders, ','))

    local result = ExecuteQuery(query, keys)

    local processedSet = {}
    if result then
        for _, row in ipairs(result) do
            processedSet[row.combination_key] = true
        end
    end

    local filtered = {}
    for _, protocol in ipairs(protocols) do
        local baseNumber = GetBaseMissionNumber(protocol.missionNumber)
        local key = (protocol.name or "") .. "|" .. baseNumber

        if not processedSet[key] then
            table.insert(filtered, protocol)
        elseif Config.Debug then
            print("^3[eNOTF-Billing]^7 already processed, skipped: " .. protocol.name .. " + " .. protocol.missionNumber)
        end
    end

    if Config.Debug and #protocols > #filtered then
        print("^2[eNOTF-Billing]^7 filter: " .. #protocols .. " -> " .. #filtered .. " protocols")
    end

    return filtered
end

function GetReleasedENOTFProtocols()
    if not Config.ENOTFBilling or not Config.ENOTFBilling.Enabled then
        return {}
    end

    if not ServerConfig.APIKey or ServerConfig.APIKey == "" or ServerConfig.APIKey == "CHANGE_ME" then
        print("^1[eNOTF-Billing]^7 API key is not set, check ServerConfig.APIKey in config_server.lua")
        return {}
    end

    if Config.Debug then
        print("^2[eNOTF-Billing]^7 fetching released protocols from " .. BillingEndpoint)
    end

    local p = promise.new()

    PerformHttpRequest(BillingEndpoint, function(statusCode, response, headers)
        if statusCode == 200 then
            local success, data = pcall(json.decode, response)

            if success and data then
                local deduplicatedData = DeduplicateProtocols(data.protocols or {})

                if Config.ENOTFBilling.FilterProcessed then
                    deduplicatedData = FilterAlreadyProcessed(deduplicatedData)
                end

                p:resolve(deduplicatedData)
            else
                if Config.Debug then
                    print("^1[eNOTF-Billing]^7 failed to parse JSON response")
                end
                p:resolve({})
            end
        else
            if Config.Debug then
                print("^1[eNOTF-Billing]^7 request failed, status code: " .. statusCode)
                if response then
                    print("^1[eNOTF-Billing]^7 response: " .. response)
                end
            end
            p:resolve({})
        end
    end, 'POST', json.encode({
        intraRP_API_Key = ServerConfig.APIKey,
        timestamp = os.time()
    }), {
        ['Content-Type'] = 'application/json',
        ['User-Agent'] = 'FiveM-eNOTF-Billing/1.0'
    })

    return Citizen.Await(p)
end

exports('getReleasedENOTFProtocols', GetReleasedENOTFProtocols)

RegisterServerEvent('enotf-billing:requestProtocols')
AddEventHandler('enotf-billing:requestProtocols', function()
    local src = source
    local protocols = GetReleasedENOTFProtocols()

    TriggerClientEvent('enotf-billing:receiveProtocols', src, protocols)
end)

-- Optional background sync
if Config.ENOTFBilling and Config.ENOTFBilling.Enabled and Config.ENOTFBilling.AutoSync then
    CreateThread(function()
        while true do
            Wait(Config.ENOTFBilling.SyncInterval or 900000)

            local protocols = GetReleasedENOTFProtocols()

            if protocols and #protocols > 0 then
                -- handled by whatever listens in billing-custom.lua
                TriggerEvent('enotf-billing:autoSync', protocols)
            end
        end
    end)
end

-- Manual sync command for admins
RegisterCommand('enotf-billing-sync', function(source, args, rawCommand)
    local src = source

    print("^2[eNOTF-Billing]^7 manual sync started by source " .. src)

    local protocols = GetReleasedENOTFProtocols()

    if protocols and #protocols > 0 then
        print("^2[eNOTF-Billing]^7 " .. #protocols .. " protocols fetched:")

        for i, protocol in ipairs(protocols) do
            print(string.format("  [%d] %s | birthdate: %s | transport: %s | mission: %s | type: %s | vehicle: %s",
                i,
                protocol.name,
                protocol.birthdate,
                protocol.transport and "yes" or "no",
                protocol.missionNumber,
                protocol.protocolType or "N/A",
                protocol.vehicleCallsign or "N/A"
            ))
        end

        TriggerEvent('enotf-billing:manualSync', protocols, src)

        if src > 0 then
            TriggerClientEvent('chat:addMessage', src, {
                args = {"^2[eNOTF-Billing]", "Sync erfolgreich: " .. #protocols .. " Protokolle abgerufen"}
            })
        end
    else
        print("^3[eNOTF-Billing]^7 no protocols found or request failed")

        if src > 0 then
            TriggerClientEvent('chat:addMessage', src, {
                args = {"^1[eNOTF-Billing]", "Keine Protokolle gefunden"}
            })
        end
    end
end, true)

-- Creates the enotf_billing table on first start if FilterProcessed is on
if Config.ENOTFBilling and Config.ENOTFBilling.Enabled and Config.ENOTFBilling.FilterProcessed then
    CreateThread(function()
        Wait(2000) -- let the DB connection come up

        local checkQuery = [[
            SELECT COUNT(*) as count
            FROM information_schema.TABLES
            WHERE TABLE_NAME = 'enotf_billing'
            AND TABLE_SCHEMA = DATABASE()
        ]]

        local result = ExecuteQuery(checkQuery, {})

        if result and result[1] and result[1].count == 0 then
            print("^3[eNOTF-Billing]^7 table 'enotf_billing' not found, creating it...")

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
                print("^2[eNOTF-Billing]^7 table 'enotf_billing' created")
            else
                print("^1[eNOTF-Billing]^7 failed to create table 'enotf_billing', please create it manually")
            end
        elseif result and result[1] and result[1].count > 0 then
            if Config.Debug then
                print("^2[eNOTF-Billing]^7 table 'enotf_billing' exists")
            end
        else
            print("^1[eNOTF-Billing]^7 could not check for the billing table, is a MySQL database connected?")
        end
    end)
end

print("^2[eNOTF-Billing]^7 billing module loaded")
