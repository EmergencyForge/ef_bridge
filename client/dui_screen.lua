-- Where each tablet model has its display, and the math to place it on
-- screen in the close-up and to map the cursor onto it. No natives, so
-- tests/dui_check.lua runs it as it is.
DuiScreen = {}

-- Corners TL, TR, BR, BL of the display face in the drawable's space, read
-- from the source .blend files, plus the half millimetre the _dui variant
-- sits forward (pipeline/variant.py). The face must sit square to the model's
-- axes: a tilted face leaves its texels slanted across the screen pixels,
-- which blurs the DUI. n is the display normal, roll turns the camera so
-- the display's top is up. dist and fov frame the tablet: further back
-- with a narrower fov keeps the thumbs in front of the display from
-- looming, but the eye must stay out of the ped's head (the near clip
-- hides what lies closer than 0.9 dist). Floats only: FiveM hands Lua
-- integers to float natives as raw bits.
local SCREENS = {
    notfpad = {
        n = { 1.0, 0.0, 0.0 }, dist = 0.5, fov = 18.8, roll = 0.0,
        { 0.0148, -0.12156, 0.0625 }, { 0.0148, 0.10236, 0.0625 },
        { 0.0148, 0.10236, -0.05935 }, { 0.0148, -0.12156, -0.05935 },
    },
    firetab = {
        n = { 1.0, 0.0, 0.0 }, dist = 0.5, fov = 23.2, roll = 90.0,
        { 0.0026, 0.0769, 0.1089 }, { 0.0026, 0.0769, -0.1086 },
        { 0.0026, -0.0767, -0.1086 }, { 0.0026, -0.0767, 0.1089 },
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

-- Places the close-up so the DUI maps one texel onto one screen pixel:
-- a fraction of a pixel off and every pixel blends two texels, which is
-- what makes a 3D display soft. Picks an even DUI width near what the
-- display spans at the model's fov (even keeps the left edge on a pixel
-- boundary) whose height also lands near whole pixels, tunes the fov so
-- the display spans exactly that width, and shifts the eye by the leftover
-- fraction so the top edge sits on a pixel boundary too. Returns the fov,
-- the DUI size, the eye in the drawable's space and the display corners on
-- screen (0..1, TL, TR, BR, BL) for the cursor. Past maxWidth the texels
-- grow larger than pixels and the alignment no longer matters.
function DuiScreen.Fit(s, rw, rh, maxWidth)
    local w, h = dist(s[1], s[2]), dist(s[1], s[4])
    local span = w * rh / (2 * math.tan(math.rad(s.fov) / 2) * s.dist)
    local width, fov
    if span > maxWidth then
        width, fov = maxWidth - maxWidth % 2, s.fov
    else
        local base, bestErr = 2 * math.floor(span / 2 + 0.5), nil
        for k = -12, 12 do
            local c = base + 2 * k
            local err = math.abs(c * h / w - math.floor(c * h / w + 0.5)) + math.abs(k) * 0.001
            if not bestErr or err < bestErr then width, bestErr = c, err end
        end
        fov = math.deg(2 * math.atan(w * rh / (2 * s.dist * width)))
    end
    local px = 2 * math.tan(math.rad(fov) / 2) * s.dist / rh -- one screen pixel at the display
    local wPx, hPx = w / px, h / px
    local left, top = (rw - wPx) / 2, (rh - hPx) / 2
    local x0, y0 = math.floor(left + 0.5), math.floor(top + 0.5)
    -- moving the eye right moves the display left, moving it up moves it down
    local sx, sy = (left - x0) * px, (y0 - top) * px
    local c = DuiScreen.Center(s)
    local right, up = dir(s[1], s[2]), dir(s[4], s[1])
    local eye = {}
    for k = 1, 3 do
        eye[k] = c[k] + s.n[k] * s.dist + right[k] * sx + up[k] * sy
    end
    return {
        fov = fov, w = width, h = math.floor(width * h / w + 0.5), eye = eye,
        quad = {
            { x0 / rw, y0 / rh }, { (x0 + wPx) / rw, y0 / rh },
            { (x0 + wPx) / rw, (y0 + hPx) / rh }, { x0 / rw, (y0 + hPx) / rh },
        },
    }
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
