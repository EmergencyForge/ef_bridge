-- ════════════════════════════════════════════════════════════════════════════
-- CUSTOM BILLING LOGIC - Implementiere hier deine Abrechnungslogik
-- ════════════════════════════════════════════════════════════════════════════

-- Event: Wird ausgelöst wenn neue Protokolle abgerufen wurden (automatischer Sync)
RegisterNetEvent('enotf-billing:autoSync')
AddEventHandler('enotf-billing:autoSync', function(protocols)
    -- protocols = {
    --     {name = "Max Mustermann", birthdate = "1990-05-15", transport = true, missionNumber = "ENR_001", protocolType = 1, vehicleCallsign = "RTW 1-82-1"},
    --     ...
    -- }
    
    -- Deine Logik hier implementieren
end)

-- Event: Wird ausgelöst bei manuellem Command /enotf-billing-sync
RegisterNetEvent('enotf-billing:manualSync')
AddEventHandler('enotf-billing:manualSync', function(protocols, source)
    -- Deine Logik hier implementieren
end)

-- Beispiel Command
RegisterCommand('billing-example', function(source, args, rawCommand)
    -- Dein Command Code hier
end, false)

-- Beispiel Export
exports('processBilling', function(protocols)
    -- Deine Export Logik hier
    return true
end)

-- Beispiel Funktion
function ProcessCustomBilling(protocols)
    -- Deine Funktionslogik hier
end
