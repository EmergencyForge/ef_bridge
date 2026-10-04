-- Custom billing logic: wire up your own handling here.
--
-- Both events are server-only on purpose. Don't add RegisterNetEvent for
-- them, otherwise any player could trigger your billing with made-up data.

-- Fired when the background sync fetched new protocols
AddEventHandler('enotf-billing:autoSync', function(protocols)
    -- protocols = {
    --     {name = "Max Mustermann", birthdate = "1990-05-15", transport = true, missionNumber = "ENR_001", protocolType = 1, vehicleCallsign = "RTW 1-82-1"},
    --     ...
    -- }
end)

-- Fired by the manual /enotf-billing-sync command
AddEventHandler('enotf-billing:manualSync', function(protocols, source)
end)

exports('processBilling', function(protocols)
    return true
end)
