local RuntimeManifest = {}

function RuntimeManifest.Load(resourcePath)
    resourcePath = resourcePath or "image/green_assistant/runtime/manifest.json"
    if not cache or not cache.Exists or not cache:Exists(resourcePath) then
        return nil, "runtime animation manifest not found: " .. tostring(resourcePath)
    end
    local file = cache:GetFile(resourcePath)
    if not file or not file:IsOpen() then
        return nil, "runtime animation manifest could not be opened: " .. tostring(resourcePath)
    end
    local content = file:ReadString()
    file:Dispose()
    if not cjson or not cjson.decode then return nil, "cjson decoder is unavailable" end
    local ok, manifest = pcall(cjson.decode, content)
    if not ok then return nil, "runtime animation manifest decode failed: " .. tostring(manifest) end
    return manifest
end

return RuntimeManifest
