local _M = {}

function _M.fetch_and_extract(article_url)
    local readability_url = os.getenv("READABILITY_URL") or "http://localhost:5000"
    local http = require "resty.http"
    local httpc = http.new()
    httpc:set_timeout(20000)

    local res, err = httpc:request_uri(
        readability_url .. "/extract?url=" .. ngx.escape_uri(article_url),
        { method = "GET" }
    )

    if not res then
        return nil, nil, "readability request failed: " .. tostring(err)
    end
    if res.status ~= 200 then
        return nil, nil, "readability service HTTP " .. res.status
    end

    local cjson = require "cjson"
    local ok, data = pcall(cjson.decode, res.body)
    if not ok or not data then
        return nil, nil, "bad response from readability service"
    end

    return data.content, data.title
end

return _M
