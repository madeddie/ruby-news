local string_utils = require "string_util"

local function send_response(status_code, body)
    ngx.status = status_code
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    if status_code >= 400 then
        ngx.header["X-Robots-Tag"] = "noindex, nofollow"
    end
    ngx.say(body)
    ngx.exit(ngx.OK)
end

local function get_param(name)
    local val = ngx.var["arg_" .. name]
    if val then return val end
    return nil
end

-- Split "Title - Source" into title and source label
local function split_title_source(title)
    local src = title:match(" %- ([^%-]+)$")
    if src then
        return title:sub(1, #title - #src - 3), src
    end
    return title, ""
end

-- Strip CDATA wrapper if present
local function strip_cdata(s)
    return (s:gsub("^%s*<%!%[CDATA%[(.-)%]%]>%s*$", "%1"))
end

-- Parse description HTML into sub-article list, skipping main_link if given
local function parse_sub_articles(desc, loc, main_link)
    desc = strip_cdata(desc)
    local items = {}
    for li in desc:gmatch("<li>(.-)</li>") do
        local url   = li:match('<a href="([^"]+)"')
        local title = li:match('<a[^>]*>(.-)</a>')
        local src   = li:match('<font[^>]*>(.-)</font>')
        if not src then
            src = li:match("&nbsp;&nbsp;([^<&]+)")
        end
        if url and title and title ~= "" and url ~= main_link then
            local article_url = "/news/article?loc=" .. loc .. "&a=" .. url
            table.insert(items, {
                url    = article_url,
                title  = string_utils.clean_str(title),
                source = src and src:match("^%s*(.-)%s*$") or "",
            })
        end
    end
    return items
end

local function format_date(pub_date)
    if not pub_date or pub_date == "" then return "" end
    local d, m, y = pub_date:match("(%d+) (%a+) (%d+)")
    if d then
        local t = pub_date:match("(%d+:%d+)") or ""
        if t ~= "" then
            local hour = tonumber(t:sub(1, 2))
            local ampm = hour >= 12 and "pm" or "am"
            if hour > 12 then hour = hour - 12 end
            if hour == 0 then hour = 12 end
            t = string.format("%d:%s %s", hour, t:sub(4), ampm)
        end
        return string.format("%s %s %s%s", d, m, y, t ~= "" and (" " .. t) or "")
    end
    return pub_date
end

local css = [[<style type="text/css"><!--
@media only screen {
body { line-height: 1.4; overflow-wrap: break-word; }
}
@media only screen and (min-width: 50em) {
body { padding: 0 3em; }
body.column { max-width: 46em; margin: 0 auto; }
}
@media only screen and (max-width: 36em) {
body { margin: 0; padding: 0.4em 0.75em; }
}
@media (prefers-color-scheme: dark) {
body { background-color: #111; color: #ddd; }
a { color: #6af; }
a:visited { color: #a8c; }
}
--></style>]]

local SOURCE_LABELS = {
    google = "Google News",
    npr    = "NPR",
    bbc    = "BBC News",
    hn     = "Hacker News",
}

local SOURCES = { "google", "npr", "bbc", "hn" }

local function handle()
    local section    = get_param("section")
    local loc        = get_param("loc") or "US"
    local lang       = get_param("lang") or "en"
    local news_source = get_param("source") or "google"

    if not SOURCE_LABELS[news_source] then news_source = "google" end
    -- legacy redirect: old ?source=reuters links → npr
    if news_source == "reuters" then news_source = "npr" end
    loc = loc:upper()

    local uri = ngx.var.request_uri or ""
    if uri:find("?") then
        ngx.header["X-Robots-Tag"] = "noindex, nofollow"
    end

    local cache     = ngx.shared.news_cache
    local feed
    local fetch_err
    local cache_key = "feed:" .. news_source .. ":" .. loc .. ":" .. lang .. ":" .. (section or "all")
    if cache then
        local cached = cache:get(cache_key)
        if cached then
            local cjson = require "cjson"
            local ok, decoded = pcall(cjson.decode, cached)
            if ok and decoded then feed = decoded end
        end
    end
    if not feed then
        local fetcher = require "rss_fetcher"
        feed, fetch_err = fetcher.fetch_feed(news_source, section, loc, lang)
        if not feed then
            ngx.log(ngx.ERR, "fetch_feed failed: ", tostring(fetch_err))
        else
            local cjson = require "cjson"
            cache:set(cache_key, cjson.encode(feed), 300)
        end
    end

    if not feed then
        local error_body =
            '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">' ..
            '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">' ..
            '<title>flatland.nyc/news: Error</title>' .. css .. '</head><body class="column">' ..
            '<center><h1><b>flatland.nyc/news</b></h1></center>' ..
            '<hr><small>Unable to load news feed. Please try again later.' ..
            (fetch_err and (" (" .. tostring(fetch_err) .. ")") or "") ..
            '</small></body></html>'
        send_response(502, error_body)
    end

    if not feed.items or #feed.items == 0 then
        local msg = section
            and ('No articles available for the <b>' .. section:upper() .. '</b> section. <a href="/news?source=' .. news_source .. '&loc=' .. loc .. '">View top news instead.</a>')
            or  'No articles available. <a href="/news">View US top news.</a>'
        local error_body =
            '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">' ..
            '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">' ..
            '<title>flatland.nyc/news: No Articles</title>' .. css .. '</head><body class="column">' ..
            '<center><h1><b>flatland.nyc/news</b></h1></center>' ..
            '<hr><small>' .. msg .. '</small></body></html>'
        send_response(404, error_body)
    end

    -- Build section nav
    local base = "source=" .. news_source .. "&loc=" .. loc
    local nav_links = {}
    if news_source == "hn" then
        for _, v in ipairs({ {"TOP",""}, {"ASK","ask"}, {"SHOW","show"}, {"JOBS","jobs"} }) do
            table.insert(nav_links, { label = v[1], params = base .. (v[2] ~= "" and ("&section=" .. v[2]) or "") })
        end
    else
        table.insert(nav_links, { label = "TOP",   params = base })
        table.insert(nav_links, { label = "WORLD", params = base .. "&section=world" })
        if news_source == "google" then
            table.insert(nav_links, { label = "NATION", params = base .. "&section=nation" })
        end
        for _, v in ipairs({
            { "BUSINESS",      "business" },
            { "TECHNOLOGY",    "technology" },
            { "ENTERTAINMENT", "entertainment" },
            { "SPORTS",        "sports" },
            { "SCIENCE",       "science" },
            { "HEALTH",        "health" },
        }) do
            table.insert(nav_links, { label = v[1], params = base .. "&section=" .. v[2] })
        end
    end

    local out = {}

    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<html><head>'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<meta name="viewport" content="width=device-width, initial-scale=1">'
    out[#out + 1] = '<title>flatland.nyc/news</title>'
    out[#out + 1] = css
    out[#out + 1] = '</head><body class="column">'

    out[#out + 1] = '<center><h1><b>flatland.nyc/news</b></h1></center>'

    -- Source switcher
    out[#out + 1] = '<center><small>'
    local src_parts = {}
    for _, sid in ipairs(SOURCES) do
        if sid == news_source then
            src_parts[#src_parts + 1] = '<b>' .. SOURCE_LABELS[sid] .. '</b>'
        else
            local sparams = "source=" .. sid .. "&loc=" .. loc .. (section and ("&section=" .. section) or "")
            src_parts[#src_parts + 1] = '<a href="/news?' .. sparams .. '">' .. SOURCE_LABELS[sid] .. '</a>'
        end
    end
    out[#out + 1] = table.concat(src_parts, " | ")
    out[#out + 1] = '</small></center>'

    -- Section nav
    out[#out + 1] = '<center><small>'
    local nav_parts = {}
    for _, link in ipairs(nav_links) do
        local label = link.label
        if section and section:upper() == label or (not section and label == "TOP") then
            nav_parts[#nav_parts + 1] = '<b>' .. label .. '</b>'
        else
            nav_parts[#nav_parts + 1] = '<a href="/news?' .. link.params .. '">' .. label .. '</a>'
        end
    end
    out[#out + 1] = table.concat(nav_parts, " | ")
    out[#out + 1] = '</small></center>'

    if news_source == "google" then
        out[#out + 1] = '<center><small>' .. loc:upper() .. ' Edition <a href="/news/choose_edition">(Change)</a></small></center>'
    elseif news_source ~= "hn" then
        -- no edition for hn; other sources show nothing
    end
    out[#out + 1] = '<hr>'

    if section then
        out[#out + 1] = '<center><h2>' .. section:upper() .. ' NEWS</h2></center>'
    end

    -- Articles
    for _, item in ipairs(feed.items) do
        local raw_title  = string_utils.clean_str(item.title or "")
        local title, item_source = split_title_source(raw_title)
        local link        = item.link or ""
        local source_param = news_source == "hn" and "&source=hn" or ""
        local article_url = "/news/article?loc=" .. loc .. source_param .. "&a=" .. link
        local date_str    = format_date(item.pub_date)

        out[#out + 1] = '<h3><a href="' .. article_url .. '">' .. title .. '</a></h3>'

        local meta = item_source
        if date_str ~= "" then
            meta = meta .. (meta ~= "" and " - " or "") .. date_str
        end
        if item.comments and item.comments ~= "" then
            local discuss = '<a href="' .. item.comments .. '">discuss</a>'
            meta = meta .. (meta ~= "" and " - " or "") .. discuss
        end
        if meta ~= "" then
            out[#out + 1] = '<small>' .. meta .. '</small>'
        end

        local sub_articles = parse_sub_articles(item.description or "", loc, link)
        if #sub_articles > 0 then
            out[#out + 1] = '<ul>'
            for _, sub in ipairs(sub_articles) do
                local line = '<li><a href="' .. sub.url .. '">' .. sub.title .. '</a>'
                if sub.source ~= "" then
                    line = line .. ' <small>(' .. sub.source .. ')</small>'
                end
                out[#out + 1] = line .. '</li>'
            end
            out[#out + 1] = '</ul>'
        end
    end

    out[#out + 1] = '<hr>'
    out[#out + 1] = '<center><small>Powered by Lua on nginx | ' .. SOURCE_LABELS[news_source] .. '</small></center>'
    out[#out + 1] = '</body></html>'

    send_response(200, table.concat(out))
end

local ok, err = pcall(handle)
if not ok then
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    ngx.status = 502
    ngx.say('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN"><html><head>' ..
        '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">' ..
        '<title>flatland.nyc/news: Error</title></head><body>' ..
        '<center><h1><b>flatland.nyc/news</b></h1></center>' ..
        '<hr><small>Error: ' .. tostring(err) .. '</small></body></html>')
    ngx.exit(ngx.OK)
end
