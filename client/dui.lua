-- Tablet "In der Hand": the page runs in a DUI. Its texture replaces the
-- screen of a local <model>_dui prop (a replacement hits every prop of a
-- model on this client, so the own tablet gets its own model name), and a
-- hard attached camera looks straight at the display. The DUI is as wide
-- as the display shows on screen, so each DUI pixel lands on one screen
-- pixel and the page stays sharp on the 3D surface.
-- The NUI keeps doing the session work in its hidden frame (tablet login,
-- character identification). NUI and DUI share the cookie store, so the
-- DUI sees the same ignis session.
DuiTablet = {}

local TXD_NAME = 'ef_bridge_dui'
-- 4K would ask for about 2900 px, past what is worth a browser texture
local MAX_WIDTH = 2560
local EASE_MS = 500
local SESSION_WAIT_MS = 4000
local READY_WAIT_MS = 5000
local BLANK_WAIT_MS = 10000

local txd = nil
local textureCount = 0
local state = nil

function DuiTablet.Supports(model)
    return DuiScreen.For(model) ~= nil
end

function DuiTablet.IsOpen()
    return state ~= nil
end

local function blankFrame()
    if state.blanked then return end
    state.blanked = true
    SendNUIMessage({ type = 'blankTabletFrame', tabletType = state.tabletType })
end

local function spawnProp(prop, model)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(50)
    end
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    -- local only: the other players see the networked prop with its lock screen
    local entity = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
    local o = prop.offset
    AttachEntityToEntity(entity, ped, GetPedBoneIndex(ped, prop.bone), o.x, o.y, o.z, o.xRot, o.yRot, o.zRot,
        true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return entity
end

-- Hard attached, the camera moves with the prop in the same frame and keeps
-- its rotation to it; AttachCamToEntity only follows the heading. At zero
-- rotation it looks along the prop's +y, yaw 90 turns that onto the
-- display (-x). The near clip cuts away the ped's head, which sits between
-- eye and display in the tablet anim.
local function startCamera()
    local s = state.screen
    local eye = DuiScreen.Eye(s)
    state.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(state.cam, s.fov)
    HardAttachCamToEntity(state.cam, state.prop, 0.0, s.roll, 90.0, eye[1], eye[2], eye[3], true)
    SetCamNearClip(state.cam, s.dist * 0.9)
    RenderScriptCams(true, true, EASE_MS, true, true)
    -- while the camera eases in, the display still moves on screen
    state.settledAt = GetGameTimer() + EASE_MS + 100
end

local function startDui()
    if state.dui then return end
    local rw, rh = GetActiveScreenResolution()
    local q = DuiScreen.CloseUp(state.screen, rw / rh)
    state.w = math.min(math.floor((q[2][1] - q[1][1]) * rw + 0.5), MAX_WIDTH)
    state.h = math.floor(state.w * DuiScreen.Aspect(state.screen) + 0.5)
    state.dui = CreateDui(state.url, state.w, state.h)
    state.createdAt = GetGameTimer()
end

function DuiTablet.Begin(tabletType, url, loginPending, netProp, onFail)
    local prop = Config.Tablets[tabletType].Prop
    local model = GetHashKey(prop.model .. '_dui')
    -- a missing _dui model (partial update) falls back to the window
    if not IsModelInCdimage(model) then
        if onFail then onFail() end
        return
    end
    state = {
        tabletType = tabletType, url = url, model = prop.model, screen = DuiScreen.For(prop.model),
        netProp = netProp, loginPending = loginPending, onFail = onFail, sessions = 0,
    }
    local mine = state
    -- on before the model loads, so ESC still closes the tablet meanwhile
    SendNUIMessage({ type = 'duiInput', active = true })
    -- the tablet can close while the model loads
    local entity = spawnProp(prop, model)
    if state ~= mine then
        DeleteEntity(entity)
        return
    end
    state.prop = entity
    startCamera()
    -- no session report (ignis slow or unreachable): show the page anyway
    SetTimeout(SESSION_WAIT_MS, function()
        if state == mine then startDui() end
    end)
    SetTimeout(BLANK_WAIT_MS, function()
        if state == mine then blankFrame() end
    end)
end

function DuiTablet.OnSession()
    if not state then return end
    state.sessions = state.sessions + 1
    if state.dui then
        -- reported again after the tablet login: load the page signed in
        SetDuiUrl(state.dui, state.url)
    else
        startDui()
    end
    if not state.loginPending or state.sessions >= 2 then
        blankFrame()
    end
end

function DuiTablet.OnLoginFailed()
    if not state then return end
    -- an immediate failure comes before the frame's first report; blanking
    -- now would drop the report that ties the character to the session
    state.loginPending = false
    if state.sessions >= 1 then blankFrame() end
end

function DuiTablet.Close(keepFrame)
    if not state then return end
    local s = state
    state = nil
    SendNUIMessage({ type = 'duiInput', active = false })
    if s.cam then
        RenderScriptCams(false, true, EASE_MS, true, true)
        DestroyCam(s.cam, false)
    end
    if s.txn then RemoveReplaceTexture(s.model .. '_dui', s.model .. '_screen') end
    if s.dui then DestroyDui(s.dui) end
    if s.prop and DoesEntityExist(s.prop) then DeleteEntity(s.prop) end
    if not keepFrame and not s.blanked then
        SendNUIMessage({ type = 'blankTabletFrame', tabletType = s.tabletType })
    end
end

local function moveMouse(q, rw, rh)
    local mx, my = GetNuiCursorPosition()
    local u, v = DuiScreen.UV(q, mx / rw, my / rh)
    if not u or u < 0 or u > 1 or v < 0 or v > 1 then
        state.inside = false
        return
    end
    state.inside = true
    local px, py = math.floor(u * state.w), math.floor(v * state.h)
    if px == state.lastX and py == state.lastY then return end
    state.lastX, state.lastY = px, py
    SendDuiMouseMove(state.dui, px, py)
end

function DuiTablet.Frame()
    if not state then return end
    -- the DUI can be ready while the model still loads, nothing to draw yet
    if not state.cam then return end
    if state.netProp and DoesEntityExist(state.netProp) then
        SetEntityLocallyInvisible(state.netProp)
    end
    HideHudAndRadarThisFrame()
    if not state.dui then return end

    local now = GetGameTimer()
    if not state.txn then
        if not IsDuiAvailable(state.dui) then
            if now - state.createdAt > READY_WAIT_MS then
                local onFail = state.onFail
                DuiTablet.Close(true)
                if onFail then onFail() end
            end
            return
        end
        txd = txd or CreateRuntimeTxd(TXD_NAME)
        -- a texture name can't be reused within a runtime txd
        textureCount = textureCount + 1
        state.txn = 'screen' .. textureCount
        CreateRuntimeTextureFromDuiHandle(txd, state.txn, GetDuiHandle(state.dui))
        AddReplaceTexture(state.model .. '_dui', state.model .. '_screen', TXD_NAME, state.txn)
    end

    if now < state.settledAt then return end
    local rw, rh = GetActiveScreenResolution()
    moveMouse(DuiScreen.CloseUp(state.screen, rw / rh), rw, rh)
end

-- A DUI only gets mouse input from the game; keys go to the page as a
-- message, ignis 2026.1.2 and newer types them (assets/js/dui-keys.js).
RegisterNUICallback('duiInput', function(data, cb)
    cb('ok')
    if not state or not state.dui or type(data) ~= 'table' then return end
    local button = (data.button == 'right' or data.button == 'middle') and data.button or 'left'
    -- presses and wheel only count on the display, a release always ends a press
    if data.kind == 'down' then
        if state.inside then SendDuiMouseDown(state.dui, button) end
    elseif data.kind == 'up' then
        SendDuiMouseUp(state.dui, button)
    elseif data.kind == 'wheel' then
        if state.inside then SendDuiMouseWheel(state.dui, math.floor(-(tonumber(data.dy) or 0)), 0) end
    elseif data.kind == 'key' and type(data.key) == 'string' then
        SendDuiMessage(state.dui, json.encode({ type = 'efKey', key = data.key, ctrl = data.ctrl == true, shift = data.shift == true }))
    end
end)
