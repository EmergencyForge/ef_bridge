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

realPrint(failed == 0 and "all checks passed" or (failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
