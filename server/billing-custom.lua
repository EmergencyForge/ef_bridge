-- Custom billing: put your own handling (invoices, money transfers) into
-- ProcessBilling. It runs on every fetch, from the background sync
-- (ENOTFBilling.AutoSync) and from /enotf-billing-sync.
--
-- protocols = {
--     {
--         name = "Max Mustermann",
--         birthdate = "1990-05-15",         -- YYYY-MM-DD
--         transport = true,                 -- the patient was transported
--         missionNumber = "123_1",
--         protocolType = 0,                 -- 0 = Notfallprotokoll (Rettungsdienst), 1 = Notarztprotokoll
--         vehicleCallsign = "RTW 1-82-1"
--     },
--     ...
-- }
-- source: the player who ran /enotf-billing-sync, nil for the background
-- sync and for calls from other resources.
--
-- ignis hands out every protocol only once. To also skip a patient whose
-- second protocol of the same mission ("123_2") comes later, store what
-- you billed in the enotf_billing table with the base mission number
-- ("123"); ENOTFBilling.FilterProcessed then drops it.
function ProcessBilling(protocols, source)
end

-- Both events are server-only on purpose. Don't add RegisterNetEvent for
-- them, otherwise any player could trigger your billing with made-up data.
AddEventHandler('enotf-billing:autoSync', function(protocols)
    ProcessBilling(protocols, nil)
end)

AddEventHandler('enotf-billing:manualSync', function(protocols, source)
    ProcessBilling(protocols, source)
end)

-- For other resources that fetch the protocols themselves
-- (exports.ef_bridge:getReleasedENOTFProtocols())
exports('processBilling', function(protocols)
    return ProcessBilling(protocols, nil)
end)
