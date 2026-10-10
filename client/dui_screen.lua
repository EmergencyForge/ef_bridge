-- Where each tablet model has its display, and the math to place it on
-- screen in the close-up and to map the cursor onto it. No natives, so
-- tests/dui_check.lua runs it as it is.
DuiScreen = {}

-- Corners TL, TR, BR, BL of the painted display in the drawable's space,
-- read from the source .blend files through the screen plane's UVs. n is
-- the display normal, dist the camera distance that just fits the tablet
-- (further back the eye sits inside the ped's head), roll turns the camera
-- so the display's top is up. Floats only: FiveM hands Lua integers to
-- float natives as raw bits.
local SCREENS = {
    notfpad = {
        n = { 1.0, 0.0, 0.0 }, dist = 0.18, roll = 0.0,
        { 0.0143, -0.1209, 0.0637 }, { 0.0143, 0.1030, 0.0613 },
        { 0.0143, 0.1017, -0.0606 }, { 0.0143, -0.1222, -0.0581 },
    },
    firetab = {
        n = { 1.0, 0.0, 0.0 }, dist = 0.22, roll = 90.0,
        { 0.0021, 0.0769, 0.1089 }, { 0.0021, 0.0769, -0.1086 },
        { 0.0021, -0.0767, -0.1086 }, { 0.0021, -0.0767, 0.1089 },
    },
}

function DuiScreen.For(model)
    return SCREENS[model]
end

local function dist(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local function dir(from, to)
    local l = dist(from, to)
    return { (to[1] - from[1]) / l, (to[2] - from[2]) / l, (to[3] - from[3]) / l }
end

local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function DuiScreen.Center(s)
    local c = { 0.0, 0.0, 0.0 }
    for i = 1, 4 do
        for k = 1, 3 do c[k] = c[k] + s[i][k] / 4 end
    end
    return c
end

-- height / width of the display, for the DUI's pixel size
function DuiScreen.Aspect(s)
    return dist(s[1], s[4]) / dist(s[1], s[2])
end

function DuiScreen.Eye(s)
    local c = DuiScreen.Center(s)
    return { c[1] + s.n[1] * s.dist, c[2] + s.n[2] * s.dist, c[3] + s.n[3] * s.dist }
end

-- The display corners on screen (0..1) in the close-up. The camera is hard
-- attached and looks straight at the display centre, so this follows from
-- the vertical fov, dist, the display size and the screen aspect.
-- Projecting the corners from the prop instead uses its position from the
-- frame before and wobbles while walking.
function DuiScreen.CloseUp(s, fov, aspect)
    local half = math.tan(math.rad(fov) / 2) * s.dist
    local center = DuiScreen.Center(s)
    local right, up = dir(s[1], s[2]), dir(s[4], s[1])
    local quad = {}
    for i = 1, 4 do
        local rel = { s[i][1] - center[1], s[i][2] - center[2], s[i][3] - center[3] }
        quad[i] = { 0.5 + dot(rel, right) / (2 * half * aspect), 0.5 - dot(rel, up) / (2 * half) }
    end
    return quad
end

-- Inverts the perspective map from the unit square onto quad (TL, TR, BR,
-- BL), so a cursor position becomes u/v on the DUI. Heckbert's
-- square-to-quad, then the adjugate of that matrix.
function DuiScreen.UV(q, x, y)
    local x0, y0, x1, y1 = q[1][1], q[1][2], q[2][1], q[2][2]
    local x2, y2, x3, y3 = q[3][1], q[3][2], q[4][1], q[4][2]
    local dx1, dx2, dx3 = x1 - x2, x3 - x2, x0 - x1 + x2 - x3
    local dy1, dy2, dy3 = y1 - y2, y3 - y2, y0 - y1 + y2 - y3
    local det = dx1 * dy2 - dx2 * dy1
    if det == 0 then return nil end
    local g = (dx3 * dy2 - dx2 * dy3) / det
    local h = (dx1 * dy3 - dx3 * dy1) / det
    local a, b, c = x1 - x0 + g * x1, x3 - x0 + h * x3, x0
    local d, e, f = y1 - y0 + g * y1, y3 - y0 + h * y3, y0
    local A, B, C = e - f * h, c * h - b, b * f - c * e
    local D, E, F = f * g - d, a - c * g, c * d - a * f
    local G, H, I = d * h - e * g, b * g - a * h, a * e - b * d
    local w = G * x + H * y + I
    if w == 0 then return nil end
    return (A * x + B * y + C) / w, (D * x + E * y + F) / w
end
