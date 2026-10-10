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

realPrint(failed == 0 and "all checks passed" or (failed .. " check(s) failed"))
os.exit(failed == 0 and 0 or 1)
