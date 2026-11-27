local _M = {}

local UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

local function http_get(url)
    local http = require "resty.http"
    local httpc = http.new()
    httpc:set_timeout(15000)
    local res, err = httpc:request_uri(url, {
        method = "GET",
        headers = { ["User-Agent"] = UA },
        ssl_verify = false,
    })
    if not res then return nil, err end
    if res.status ~= 200 then return nil, "HTTP " .. res.status end
    return res.body
end

local function http_post(url, body)
    local http = require "resty.http"
    local httpc = http.new()
    httpc:set_timeout(15000)
    local res, err = httpc:request_uri(url, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded;charset=UTF-8",
            ["User-Agent"] = UA,
        },
        body = body,
        ssl_verify = false,
    })
    if not res then return nil, err end
    return res.body
end

function _M.get_base64_str(source_url)
    if not source_url:find("news.google.com") then
        return { status = false, message = "Invalid Google News URL format." }
    end

    local m = source_url:match("/articles/([A-Za-z0-9_%-]+)")
    if m then
        return { status = true, base64_str = m }
    end

    return { status = false, message = "Could not extract article ID from URL." }
end

function _M.get_decoding_params(base64_str)
    local urls = {
        "https://news.google.com/articles/" .. base64_str,
        "https://news.google.com/rss/articles/" .. base64_str,
    }

    for _, url in ipairs(urls) do
        local html, err = http_get(url)
        if html then
            local sg_match = html:match('data%-n%-a%-sg="([^"]+)"')
            local ts_match = html:match('data%-n%-a%-ts="([^"]+)"')
            if sg_match and ts_match then
                return { status = true, signature = sg_match, timestamp = ts_match, base64_str = base64_str }
            end
        else
            ngx.log(ngx.WARN, "get_decoding_params fetch failed for ", url, ": ", tostring(err))
        end
    end

    return { status = false, message = "Failed to fetch decoding params from Google News." }
end

function _M.decode_url(signature, timestamp, base64_str)
    local url = "https://news.google.com/_/DotsSplashUi/data/batchexecute"

    local payload = {
        "Fbv4je",
        string.format(
            "[\"garturlreq\",[[\"X\",\"X\",[\"X\",\"X\"],null,null,1,1,\"US:en\",null,1,null,null,null,null,null,0,1],\"X\",\"X\",1,[1,1,1],1,1,null,0,0,null,0],\"%s\",%s,\"%s\"]",
            base64_str, timestamp, signature
        )
    }

    local cjson = require "cjson"
    local encoded_json = cjson.encode({{payload}})
    local post_body = "f.req=" .. encoded_json:gsub("([^A-Za-z0-9 _.%-])", function(c)
        return ("%%%02X"):format(c:byte())
    end):gsub(" ", "+")

    local response, err = http_post(url, post_body)
    if not response then
        return { status = false, message = "Failed to connect to Google News: " .. tostring(err) }
    end

    local json_start = response:find("\n\n", 1, true) or response:find("\r\r", 1, true)
    local json_str = json_start and response:sub(json_start + 2) or response

    local ok, json_data = pcall(cjson.decode, json_str)
    if not ok or not json_data or not json_data[1] then
        return { status = false, message = "Failed to parse decode response." }
    end

    local parsed_data = json_data[1][3]
    if not parsed_data then
        return { status = false, message = "No decoded data in response." }
    end

    local ok2, decoded = pcall(cjson.decode, parsed_data)
    if not ok2 or not decoded then
        return { status = false, message = "Failed to parse inner JSON." }
    end

    if decoded[2] then
        return { status = true, decoded_url = decoded[2] }
    end

    return { status = false, message = "Failed to extract decoded URL." }
end

function _M.decode_google_news_url(source_url)
    local base64_result = _M.get_base64_str(source_url)
    if not base64_result.status then return base64_result end

    local params_result = _M.get_decoding_params(base64_result.base64_str)
    if not params_result.status then return params_result end

    return _M.decode_url(params_result.signature, params_result.timestamp, params_result.base64_str)
end

return _M
