-- URL helpers shared between client and server.
-- NUI iframes refuse plain HTTP, so every URL leaving this resource
-- gets normalized to HTTPS here.

function EnsureHttps(url)
    if not url or url == "" then
        return url
    end

    url = url:match("^%s*(.-)%s*$")

    if url:lower():sub(1, 7) == "http://" then
        url = "https://" .. url:sub(8)
    elseif url:lower():sub(1, 8) ~= "https://" and url:sub(1, 2) ~= "//" then
        url = "https://" .. url
    end

    return url
end

-- Joins a path onto a base URL, taking care of stray slashes. Without a
-- base it's the ignis address (Config.Ignis.BaseURL). Read on every call,
-- so a new address from the admin panel applies right away.
function BuildURL(basePath, base)
    local baseURL = EnsureHttps(base or (Config.Ignis and Config.Ignis.BaseURL) or "")

    if baseURL ~= "" and baseURL:sub(-1) ~= "/" then
        baseURL = baseURL .. "/"
    end

    if basePath and basePath:sub(1, 1) == "/" then
        basePath = basePath:sub(2)
    end

    return baseURL .. (basePath or "")
end
