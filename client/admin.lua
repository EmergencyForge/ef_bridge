-- Admin panel: /efbridge asks the server, the server checks the ACE and
-- sends schema, values and status. Saving and the buttons go back to the
-- server, which checks the ACE again; nothing here decides anything.

local panelOpen = false

function AdminPanelOpen()
    return panelOpen
end

local function Close()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'adminClose' })
end

RegisterCommand(Config.Admin.Command, function()
    TriggerServerEvent('ef_bridge:admin:open')
end, false)

RegisterNetEvent('ef_bridge:admin:denied')
AddEventHandler('ef_bridge:admin:denied', function()
    Close()
    ShowNotification('Für das ef_bridge-Panel fehlt dir das Recht.', 'error')
end)

RegisterNetEvent('ef_bridge:admin:data')
AddEventHandler('ef_bridge:admin:data', function(data)
    if CloseTablet then
        CloseTablet()
    end
    panelOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'adminOpen', data = data })
end)

RegisterNetEvent('ef_bridge:admin:saved')
AddEventHandler('ef_bridge:admin:saved', function(data)
    SendNUIMessage({ type = 'adminSaved', data = data })
end)

RegisterNetEvent('ef_bridge:admin:result')
AddEventHandler('ef_bridge:admin:result', function(data)
    SendNUIMessage({ type = 'adminResult', data = data })
end)

RegisterNetEvent('ef_bridge:admin:imported')
AddEventHandler('ef_bridge:admin:imported', function(data)
    SendNUIMessage({ type = 'adminImported', data = data })
end)

-- latent: a pasted config file can be bigger than a normal event allows
RegisterNUICallback('adminImport', function(data, cb)
    if panelOpen and type(data) == 'table' then
        local text = type(data.text) == 'string' and data.text:sub(1, 64 * 1024) or ''
        TriggerLatentServerEvent('ef_bridge:admin:import', 50000, text, data.apply == true)
    end
    cb('ok')
end)

RegisterNUICallback('adminSave', function(data, cb)
    if panelOpen and type(data) == 'table' then
        TriggerServerEvent('ef_bridge:admin:save', data.changes or {}, data.resets or {})
    end
    cb('ok')
end)

RegisterNUICallback('adminAction', function(data, cb)
    if panelOpen and type(data) == 'table' and type(data.action) == 'string' then
        TriggerServerEvent('ef_bridge:admin:action', data.action)
    end
    cb('ok')
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    if panelOpen then
        TriggerServerEvent('ef_bridge:admin:open')
    end
    cb('ok')
end)

RegisterNUICallback('adminClose', function(_, cb)
    Close()
    cb('ok')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName and panelOpen then
        SetNuiFocus(false, false)
    end
end)
