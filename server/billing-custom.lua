-- Custom billing logic — wire up your own handling here.

-- Fired when the background sync fetched new protocols
RegisterNetEvent('enotf-billing:autoSync')
AddEventHandler('enotf-billing:autoSync', function(protocols)
    -- protocols = {
    --     {name = "Max Mustermann", birthdate = "1990-05-15", transport = true, missionNumber = "ENR_001", protocolType = 1, vehicleCallsign = "RTW 1-82-1"},
    --     ...
    -- }
end)

-- Fired by the manual /enotf-billing-sync command
RegisterNetEvent('enotf-billing:manualSync')
AddEventHandler('enotf-billing:manualSync', function(protocols, source)
end)

exports('processBilling', function(protocols)
    return true
end)
