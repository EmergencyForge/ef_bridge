-- Checks the tablet "In der Hand": the screen math (client/dui_screen.lua),
-- the controller (client/dui.lua) and how client/main.lua drives it, with
-- stubbed FiveM natives.
--
--   lua tests/dui_check.lua    (Lua 5.4, no FiveM needed)
local root = arg[0]:gsub("[^/\\]+$", "") .. "../"

-- client/main.lua prints; parts below swap print out to catch that
local realPrint = print
local failed = 0
local function check(label, cond)
    realPrint((cond and "ok   " or "FAIL ") .. label)
    if not cond then failed = failed + 1 end
end
local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end

dofile(root .. "client/dui_screen.lua")

-- screen math
do
    local s = DuiScreen.For("notfpad")
    local q = DuiScreen.CloseUp(s, 50.0, 16 / 9)
    check("notfpad close-up width at 16:9", near(q[2][1] - q[1][1], 0.750, 0.002))
    check("notfpad close-up height", near(q[4][2] - q[1][2], 0.726, 0.002))
    local cx = (q[1][1] + q[2][1] + q[3][1] + q[4][1]) / 4
    local cy = (q[1][2] + q[2][2] + q[3][2] + q[4][2]) / 4
    check("close-up is centred", near(cx, 0.5, 1e-3) and near(cy, 0.5, 1e-3))
    check("unknown model has no screen", DuiScreen.For("prop_cs_tablet") == nil)
    check("firetab display is wider than tall", DuiScreen.Aspect(DuiScreen.For("firetab")) < 1)
    check("screen data are floats", math.type(s.roll) == 'float' and math.type(s.n[1]) == 'float' and math.type(s.dist) == 'float')
    local eye = DuiScreen.Eye(s)
    check("eye sits dist in front of the display", near(eye[1] - DuiScreen.Center(s)[1], 0.18))
end

-- cursor mapping: forward through the square-to-quad map, back through UV
do
    local q = { { 0.21, 0.14 }, { 0.83, 0.18 }, { 0.79, 0.86 }, { 0.17, 0.80 } }
    local x0, y0, x1, y1, x2, y2, x3, y3 = q[1][1], q[1][2], q[2][1], q[2][2], q[3][1], q[3][2], q[4][1], q[4][2]
    local dx1, dx2, dx3 = x1 - x2, x3 - x2, x0 - x1 + x2 - x3
    local dy1, dy2, dy3 = y1 - y2, y3 - y2, y0 - y1 + y2 - y3
    local det = dx1 * dy2 - dx2 * dy1
    local g = (dx3 * dy2 - dx2 * dy3) / det
    local h = (dx1 * dy3 - dx3 * dy1) / det
    local function forward(u, v)
        local w = g * u + h * v + 1
        return ((x1 - x0 + g * x1) * u + (x3 - x0 + h * x3) * v + x0) / w,
            ((y1 - y0 + g * y1) * u + (y3 - y0 + h * y3) * v + y0) / w
    end
    local worst = 0
    for _, p in ipairs({ { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { 0.5, 0.5 }, { 0.12, 0.93 }, { 0.71, 0.33 } }) do
        local u, v = DuiScreen.UV(q, forward(p[1], p[2]))
        worst = math.max(worst, math.abs(u - p[1]), math.abs(v - p[2]))
    end
    check("cursor maps back onto the DUI", worst < 1e-9)
    check("degenerate quad gives nil", DuiScreen.UV({ { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }, 0.5, 0.5) == nil)
end

-- natives the controller and client/main.lua use, recorded by name
local calls, timers = {}, {}
local now, duiReady, cursor = 1000, false, { 960, 540 }
local nuiCallbacks, handlers, nuiMessages = {}, {}, {}
local function record(name, ret)
    _G[name] = function(...)
        calls[#calls + 1] = { name = name, args = table.pack(...) }
        if type(ret) == 'function' then return ret(...) end
        return ret
    end
end
local function called(name)
    local out = {}
    for _, c in ipairs(calls) do if c.name == name then out[#out + 1] = c.args end end
    return out
end
local function reset() calls, timers, nuiMessages = {}, {}, {} end
local function nui(kind)
    for _, m in ipairs(nuiMessages) do if m.type == kind then return m end end
end

for _, name in ipairs({
    'RequestModel', 'Wait', 'SetModelAsNoLongerNeeded', 'AttachEntityToEntity',
    'SetCamFov', 'HardAttachCamToEntity', 'SetCamNearClip', 'RenderScriptCams',
    'DestroyCam', 'CreateRuntimeTextureFromDuiHandle', 'AddReplaceTexture',
    'RemoveReplaceTexture', 'DestroyDui', 'DeleteEntity', 'SetEntityLocallyInvisible',
    'HideHudAndRadarThisFrame', 'DrawSprite', 'SendDuiMouseMove', 'SetDuiUrl',
    'SendDuiMouseDown', 'SendDuiMouseUp', 'SendDuiMouseWheel', 'SendDuiMessage',
}) do record(name, nil) end
record('HasModelLoaded', true)
record('IsModelInCdimage', true)
record('GetHashKey', function(name) return name end)
record('PlayerPedId', 'ped')
record('GetEntityCoords', { x = 0.0, y = 0.0, z = 0.0 })
record('GetPedBoneIndex', 1)
record('CreateObject', function(model, _, _, _, net) return (net and 'net:' or 'local:') .. model end)
record('CreateCam', 'cam')
record('CreateDui', 'dui')
record('IsDuiAvailable', function() return duiReady end)
record('CreateRuntimeTxd', 'txd')
record('GetDuiHandle', 'handle')
record('DoesEntityExist', true)
record('GetActiveScreenResolution', function() return 1920, 1080 end)
record('GetNuiCursorPosition', function() return cursor[1], cursor[2] end)
function GetGameTimer() return now end
function SetTimeout(ms, fn) timers[#timers + 1] = { ms = ms, fn = fn } end
function SendNUIMessage(msg) nuiMessages[#nuiMessages + 1] = msg end
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
json = { encode = function(t) return string.format('{"type":"%s","key":"%s"}', t.type, tostring(t.key)) end }

dofile(root .. "shared/defaults.lua")
dofile(root .. "client/dui.lua")

-- controller on its own
do
    reset()
    local failedWith = nil
    DuiTablet.Begin('eNOTF', 'https://ignis.test/enotf/', false, 'net:notfpad', function() failedWith = true end)
    local created = called('CreateObject')
    check("local _dui prop, not networked", #created == 1 and created[1][1] == 'notfpad_dui' and created[1][5] == false)
    local cam = called('HardAttachCamToEntity')[1]
    check("camera hard attached with yaw 90", cam and cam[2] == 'local:notfpad_dui' and cam[5] == 90.0)
    check("camera rotation and offsets are floats", cam and math.type(cam[3]) == 'float' and math.type(cam[4]) == 'float'
        and math.type(cam[6]) == 'float' and math.type(cam[7]) == 'float' and math.type(cam[8]) == 'float')
    check("near clip at 0.9 of the distance", math.abs(called('SetCamNearClip')[1][2] - 0.162) < 1e-9)
    check("input layer switched on", nui('duiInput') and nui('duiInput').active == true)
    check("two timers: session wait and frame blank", #timers == 2 and timers[1].ms == 4000 and timers[2].ms == 10000)
    check("no DUI before the session", #called('CreateDui') == 0)

    DuiTablet.OnSession()
    local dui = called('CreateDui')[1]
    check("DUI 1440 wide at the display's aspect", dui and dui[1] == 'https://ignis.test/enotf/' and dui[2] == 1440 and dui[3] == 783)
    check("frame blanked after the session (no login pending)", nui('blankTabletFrame') ~= nil)

    DuiTablet.Frame()
    check("networked prop hidden locally", called('SetEntityLocallyInvisible')[1][1] == 'net:notfpad')
    check("no texture while the DUI loads", #called('AddReplaceTexture') == 0)
    duiReady = true
    DuiTablet.Frame()
    local rep = called('AddReplaceTexture')[1]
    check("texture replaced on the _dui model", rep and rep[1] == 'notfpad_dui' and rep[2] == 'notfpad_screen' and rep[3] == 'ef_bridge_dui')
    check("no sprite during the camera ease", #called('DrawSprite') == 0)
    now = now + 700
    DuiTablet.Frame()
    local sprite = called('DrawSprite')[1]
    check("sprite centred over the display", sprite and math.abs(sprite[3] - 0.5) < 1e-3 and math.abs(sprite[4] - 0.5) < 1e-3)
    check("sprite size from the camera", sprite and math.abs(sprite[5] - 0.750) < 0.002 and math.abs(sprite[6] - 0.726) < 0.002)
    local move = called('SendDuiMouseMove')[1]
    -- the painted display is not quite a rectangle, so the middle may sit a pixel off
    check("cursor in the middle hits the DUI middle", move and math.abs(move[2] - 720) <= 1 and math.abs(move[3] - 391) <= 1)

    nuiCallbacks['duiInput']({ kind = 'down', button = 'left' }, function() end)
    nuiCallbacks['duiInput']({ kind = 'key', key = 'a', ctrl = false, shift = false }, function() end)
    check("click goes to the DUI", called('SendDuiMouseDown')[1][2] == 'left')
    check("key goes to the DUI as efKey", called('SendDuiMessage')[1][2]:find('"type":"efKey"', 1, true) ~= nil)

    reset()
    DuiTablet.Close()
    check("close removes the replacement", #called('RemoveReplaceTexture') == 1)
    check("close destroys DUI, camera and local prop", #called('DestroyDui') == 1 and #called('DestroyCam') == 1
        and called('DeleteEntity')[1][1] == 'local:notfpad_dui')
    check("close switches the input layer off", nui('duiInput') and nui('duiInput').active == false)
    check("frame not blanked twice", nui('blankTabletFrame') == nil)
    check("closed", not DuiTablet.IsOpen() and failedWith == nil)
end

-- closed before the session: late timers do nothing
do
    reset()
    duiReady = false
    DuiTablet.Begin('eNOTF', 'https://ignis.test/enotf/', false, nil, function() end)
    local pending = timers
    DuiTablet.Close()
    reset()
    for _, t in ipairs(pending) do t.fn() end
    check("late timers start no DUI", #called('CreateDui') == 0)
    check("late timers blank nothing", nui('blankTabletFrame') == nil)
end

-- tablet closed while its model loads: the late prop is dropped, nothing else starts
do
    reset()
    local recordedWait = Wait
    local loads = 0
    record('HasModelLoaded', function()
        loads = loads + 1
        return loads > 1
    end)
    Wait = function()
        Wait = recordedWait
        DuiTablet.Close()
    end
    local ok = pcall(DuiTablet.Begin, 'eNOTF', 'https://ignis.test/enotf/', false, nil, function() end)
    check("closing while the model loads does not error", ok)
    local deleted = called('DeleteEntity')[1]
    check("late prop is deleted", deleted and deleted[1] == 'local:notfpad_dui')
    check("no camera started", #called('CreateCam') == 0)
    check("no timers set", #timers == 0)
    check("closed after the late load", not DuiTablet.IsOpen())
    record('HasModelLoaded', true)
    record('Wait', nil)
end

-- the hidden frame reports while the model loads: Frame waits for the camera
do
    reset()
    local recordedWait = Wait
    local loads = 0
    local frameOk = false
    record('HasModelLoaded', function()
        loads = loads + 1
        return loads > 1
    end)
    Wait = function()
        Wait = recordedWait
        DuiTablet.OnSession()
        duiReady = true
        frameOk = pcall(DuiTablet.Frame)
    end
    local began = pcall(DuiTablet.Begin, 'eNOTF', 'https://ignis.test/enotf/', false, nil, function() end)
    check("frame during the model load does not error", frameOk)
    check("begin finishes after that frame", began and DuiTablet.IsOpen())
    DuiTablet.Close()
    record('HasModelLoaded', true)
    record('Wait', nil)
    duiReady = false
end

-- the input layer is on while the model loads, so ESC reaches the tablet
do
    reset()
    local recordedWait = Wait
    local loads = 0
    local layerOn, objectsThen
    record('HasModelLoaded', function()
        loads = loads + 1
        return loads > 1
    end)
    Wait = function()
        Wait = recordedWait
        layerOn = nui('duiInput') and nui('duiInput').active == true
        objectsThen = #called('CreateObject')
    end
    DuiTablet.Begin('eNOTF', 'https://ignis.test/enotf/', false, nil, function() end)
    check("input layer on while the model loads", layerOn == true and objectsThen == 0)
    DuiTablet.Close()
    record('HasModelLoaded', true)
    record('Wait', nil)
end

-- a _dui model the game doesn't know: no waiting, straight to the fallback
do
    reset()
    record('IsModelInCdimage', false)
    local failedWith = false
    DuiTablet.Begin('eNOTF', 'https://ignis.test/enotf/', false, nil, function() failedWith = true end)
    check("missing _dui model: fallback called", failedWith)
    check("missing _dui model: no prop, no camera", #called('CreateObject') == 0 and #called('CreateCam') == 0)
    check("missing _dui model: input layer stays off", nui('duiInput') == nil)
    check("missing _dui model: not open", not DuiTablet.IsOpen())
    record('IsModelInCdimage', true)
end

-- clicks and wheel off the display are dropped, a release still ends a press
do
    reset()
    duiReady = true
    DuiTablet.Begin('eNOTF', 'https://ignis.test/enotf/', false, nil, function() end)
    DuiTablet.OnSession()
    DuiTablet.Frame()
    now = now + 700
    cursor[1], cursor[2] = 10, 10
    DuiTablet.Frame()
    nuiCallbacks['duiInput']({ kind = 'down', button = 'left' }, function() end)
    nuiCallbacks['duiInput']({ kind = 'wheel', dy = 120 }, function() end)
    nuiCallbacks['duiInput']({ kind = 'up', button = 'left' }, function() end)
    check("click off the display is dropped", #called('SendDuiMouseDown') == 0)
    check("wheel off the display is dropped", #called('SendDuiMouseWheel') == 0)
    check("release off the display still goes through", #called('SendDuiMouseUp') == 1)
    cursor[1], cursor[2] = 960, 540
    DuiTablet.Frame()
    nuiCallbacks['duiInput']({ kind = 'down', button = 'left' }, function() end)
    check("click back on the display goes through", #called('SendDuiMouseDown') == 1)
    DuiTablet.Close()
    duiReady = false
end

-- DUI never ready: falls back, keeps the frame
do
    reset()
    duiReady = false
    local fellBack = false
    DuiTablet.Begin('FireTab', 'https://ignis.test/einsatz/', true, nil, function() fellBack = true end)
    DuiTablet.OnSession()
    check("login pending: frame kept after the first session", nui('blankTabletFrame') == nil)
    now = now + 6000
    DuiTablet.Frame()
    check("fallback after 5 s", fellBack and not DuiTablet.IsOpen())
    check("fallback keeps the frame for the window", nui('blankTabletFrame') == nil)
end

-- client/main.lua drives the controller
local printed, notified = {}, {}
for _, name in ipairs({ 'RegisterCommand', 'RegisterKeyMapping', 'CreateThread', 'SetNuiFocus', 'SetNuiFocusKeepInput',
    'RequestAnimDict', 'StopAnimTask', 'ClearPedSecondaryTask', 'ClearPedTasks', 'SetNotificationTextEntry',
    'DrawNotification', 'RegisterNetEvent', 'TaskPlayAnim', 'TriggerServerEvent' }) do record(name, nil) end
record('HasAnimDictLoaded', true)
record('IsEntityPlayingAnim', false)
function GetResourceState() return 'missing' end
function AddTextComponentString(text) notified[#notified + 1] = text end
function AddEventHandler(name, fn) handlers[name] = fn end
dofile(root .. "shared/url.lua")
dofile(root .. "shared/settings.lua")
-- a fresh client with both tablets on; FrameworkName stays nil, so the
-- default jobs list applies and "admin" is on it
local function loadClient(display, useProp, model, tabletLogin)
    dofile(root .. "shared/defaults.lua")
    Config.Ignis.BaseURL = "https://ignis.test/"
    Config.Ignis.TabletLogin = tabletLogin == true
    for _, t in pairs(Config.Tablets) do
        t.Enabled, t.Display, t.UseProp = true, display, useProp
    end
    Config.Tablets.eNOTF.Prop.model = model or 'notfpad'
    dofile(root .. "client/main.lua")
    handlers['ef_bridge:settings']({})
    GetPlayerCharacterData = function() return { firstName = "Max", lastName = "Muster", cid = "C1", job = "admin" } end
end
local function opened()
    for _, m in ipairs(nuiMessages) do if m.type == 'openTablet' then return m end end
end
local function session() nuiCallbacks['sessionIdentify']({ session_id = 'abc' }, function() end) end

print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

loadClient('hand', true)
reset()
duiReady = true
OpenTablet('eNOTF')
check("hand: window stays hidden", opened() and opened().hidden == true)
local objects = called('CreateObject')
check("hand: networked and local prop", #objects == 2 and objects[1][5] == true and objects[2][1] == 'notfpad_dui')
session()
check("hand: session starts the DUI", #called('CreateDui') == 1)
check("hand: frame blanked without a login", nui('blankTabletFrame') ~= nil)
reset()
CloseTablet()
check("hand: close cleans up the DUI", #called('DestroyDui') == 1 and not DuiTablet.IsOpen())
check("hand: close still tells the NUI", nui('closeTablet') ~= nil)

loadClient('hand', true, nil, true)
reset()
OpenTablet('eNOTF')
check("hand + login: login requested", called('TriggerServerEvent')[1][1] == 'ef_bridge:requestTabletLogin')
session()
check("hand + login: frame kept for the login", nui('blankTabletFrame') == nil)
session() -- back from the login link
check("hand + login: DUI reloads signed in", #called('SetDuiUrl') == 1 and called('SetDuiUrl')[1][2] == 'https://ignis.test/enotf/overview.php')
check("hand + login: frame blanked after the login", nui('blankTabletFrame') ~= nil)
CloseTablet()

loadClient('hand', true, nil, true)
reset()
OpenTablet('eNOTF')
session()
handlers['ef_bridge:tabletLoginFailed']('eNOTF', 'kein Konto', false)
check("hand + login failed: frame blanked", nui('blankTabletFrame') ~= nil)
CloseTablet()

-- an immediate failure arrives before the page in the frame reports in
loadClient('hand', true, nil, true)
reset()
OpenTablet('eNOTF')
handlers['ef_bridge:tabletLoginFailed']('eNOTF', 'kein Konto', false)
check("hand + early login failure: frame stays for the first report", nui('blankTabletFrame') == nil)
session()
local identified = false
for _, args in ipairs(called('TriggerServerEvent')) do
    if args[1] == 'ef_bridge:identifyCharacter' then identified = true end
end
check("hand + early login failure: character still identified", identified)
check("hand + early login failure: frame blanked at the first report", nui('blankTabletFrame') ~= nil)
CloseTablet()

-- the login request doesn't wait for the _dui model
loadClient('hand', true, nil, true)
reset()
local duiLoads, askedWhileLoading = 0, nil
record('HasModelLoaded', function(model)
    if model ~= 'notfpad_dui' then return true end
    duiLoads = duiLoads + 1
    return duiLoads > 1
end)
record('Wait', function()
    if askedWhileLoading ~= nil then return end
    askedWhileLoading = false
    for _, args in ipairs(called('TriggerServerEvent')) do
        if args[1] == 'ef_bridge:requestTabletLogin' then askedWhileLoading = true end
    end
end)
OpenTablet('eNOTF')
record('HasModelLoaded', true)
record('Wait', nil)
check("hand + login: request sent while the model loads", askedWhileLoading == true)
CloseTablet()

loadClient('hand', false)
reset()
OpenTablet('eNOTF')
local objects2 = called('CreateObject')
check("hand without UseProp: only the local prop", #objects2 == 1 and objects2[1][1] == 'notfpad_dui')
check("hand without UseProp: anim plays", #called('TaskPlayAnim') == 1)
CloseTablet()

loadClient('hand', true, 'prop_cs_tablet')
reset()
printed = {}
OpenTablet('eNOTF')
check("custom model: opens as a window", opened() and opened().hidden ~= true and not DuiTablet.IsOpen())
local warned = false
for _, line in ipairs(printed) do if line:find('prop_cs_tablet', 1, true) then warned = true end end
check("custom model: warning in the console", warned)
CloseTablet()

loadClient('hand', false)
reset()
notified = {}
duiReady = false
OpenTablet('eNOTF')
session()
now = now + 6000
DuiTablet.Frame()
-- no login: the frame was blanked at the first report, the window needs the page back
check("DUI fails: window revealed with the page", nui('revealTablet') and nui('revealTablet').url == 'https://ignis.test/enotf/overview.php')
check("DUI fails: player told", #notified > 0)
check("DUI fails without UseProp: no empty-handed anim", #called('StopAnimTask') == 1)
CloseTablet()

loadClient('window', true)
reset()
OpenTablet('eNOTF')
check("window: unchanged", opened() and opened().hidden ~= true and #called('CreateDui') == 0)
CloseTablet()

-- closed while the prop model loads
loadClient('hand', true)
reset()
local modelChecks, closedInWait = 0, false
record('HasModelLoaded', function()
    modelChecks = modelChecks + 1
    return modelChecks > 1
end)
record('Wait', function()
    if not closedInWait then
        closedInWait = true
        CloseTablet()
    end
end)
OpenTablet('eNOTF')
record('HasModelLoaded', true)
record('Wait', nil)
check("closed while loading: tablet never opens", opened() == nil and not DuiTablet.IsOpen())
check("closed while loading: no camera or DUI", #called('CreateCam') == 0 and #called('CreateDui') == 0)
local deleted = false
for _, args in ipairs(called('DeleteEntity')) do
    if args[1] == 'net:notfpad' then deleted = true end
end
check("closed while loading: late prop deleted", deleted)
local focused = false
for _, args in ipairs(called('SetNuiFocus')) do
    if args[1] == true then focused = true end
end
check("closed while loading: no NUI focus taken", not focused)

print = realPrint

realPrint(failed == 0 and "all checks passed" or (failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
