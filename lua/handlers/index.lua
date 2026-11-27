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

-- Split "Title - Source" into title and source
local function split_title_source(title)
    local source = title:match(" %- ([^%-]+)$")
    if source then
        return title:sub(1, #title - #source - 3), source
    end
    return title, ""
end

-- Strip CDATA wrapper if present
local function strip_cdata(s)
    return (s:gsub("^%s*<%!%[CDATA%[(.-)%]%]>%s*$", "%1"))
end

-- Parse description HTML into sub-article list
local function parse_sub_articles(desc, loc)
    desc = strip_cdata(desc)
    local items = {}
    for li in desc:gmatch("<li>(.-)</li>") do
        local url   = li:match('<a href="([^"]+)"')
        local title = li:match('<a[^>]*>(.-)</a>')
        local src   = li:match('<font[^>]*>(.-)</font>')
        if not src then
            src = li:match("&nbsp;&nbsp;([^<&]+)")
        end
        if url and title and title ~= "" then
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
--></style>]]

local function handle()
    local section = get_param("section")
    local loc  = get_param("loc") or "US"
    local lang = get_param("lang") or "en"

    loc = loc:upper()

    local uri = ngx.var.request_uri or ""
    if uri:find("?") then
        ngx.header["X-Robots-Tag"] = "noindex, nofollow"
    end

    local cache     = ngx.shared.news_cache
    local feed
    local fetch_err
    local cache_key = "feed:" .. loc .. ":" .. lang .. ":" .. (section or "all")
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
        feed, fetch_err = fetcher.fetch_feed(section, loc, lang)
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
            '<title>ruby.news: Error</title>' .. css .. '</head><body class="column">' ..
            '<center><h1><b>ruby.news:</b> <font color="#9400d3"><i>Headlines from the Future</i></font></h1></center>' ..
            '<hr><small>Unable to load news feed. Please try again later.' ..
            (fetch_err and (" (" .. tostring(fetch_err) .. ")") or "") ..
            '</small></body></html>'
        send_response(502, error_body)
    end

    if not feed.items or #feed.items == 0 then
        local msg = section
            and ('No articles available for the <b>' .. section:upper() .. '</b> section in this location. <a href="/news?loc=' .. loc .. '">View top news instead.</a>')
            or 'No articles available for this location. <a href="/news">View US top news.</a>'
        local error_body =
            '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">' ..
            '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">' ..
            '<title>ruby.news: No Articles</title>' .. css .. '</head><body class="column">' ..
            '<center><h1><b>ruby.news:</b> <font color="#9400d3"><i>Headlines from the Future</i></font></h1></center>' ..
            '<hr><small>' .. msg .. '</small></body></html>'
        send_response(404, error_body)
    end

    local nav_links = {
        { label = "TOP",           params = "loc=" .. loc },
        { label = "WORLD",         params = "section=world&loc=" .. loc },
        { label = "NATION",        params = "section=nation&loc=" .. loc },
        { label = "BUSINESS",      params = "section=business&loc=" .. loc },
        { label = "TECHNOLOGY",    params = "section=technology&loc=" .. loc },
        { label = "ENTERTAINMENT", params = "section=entertainment&loc=" .. loc },
        { label = "SPORTS",        params = "section=sports&loc=" .. loc },
        { label = "SCIENCE",       params = "section=science&loc=" .. loc },
        { label = "HEALTH",        params = "section=health&loc=" .. loc },
    }

    local out = {}

    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<html><head>'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<meta name="viewport" content="width=device-width, initial-scale=1">'
    out[#out + 1] = '<title>ruby.news: Headlines From the Future</title>'
    out[#out + 1] = css
    out[#out + 1] = '</head><body class="column">'

    out[#out + 1] = '<center><h1><b>ruby.news:</b> <font color="#9400d3"><i>Headlines from the Future</i></font></h1></center>'
    out[#out + 1] = '<hr>'
    out[#out + 1] = '<center><small>Basic HTML Google News for vintage computers. Built by <a href="https://youtube.com/ActionRetro" target="_blank"><b>Action Retro</b></a> on YouTube. Updated to Lua/nginx by <a href="https://rubymaelstrom.com">Ruby</a>.</small></center>'

    -- Nav
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
    out[#out + 1] = '<center><small>' .. loc:upper() .. ' Edition <a href="/news/choose_edition">(Change)</a></small></center>'
    out[#out + 1] = '<hr>'

    if section then
        out[#out + 1] = '<center><h2>' .. section:upper() .. ' NEWS</h2></center>'
    end

    -- Articles
    for _, item in ipairs(feed.items) do
        local raw_title  = string_utils.clean_str(item.title or "")
        local title, source = split_title_source(raw_title)
        local link       = item.link or ""
        local article_url = "/news/article?loc=" .. loc .. "&a=" .. link
        local date_str   = format_date(item.pub_date)

        out[#out + 1] = '<h3><a href="' .. article_url .. '">' .. title .. '</a></h3>'

        local meta = source
        if date_str ~= "" then
            meta = meta .. (meta ~= "" and " - " or "") .. date_str
        end
        if meta ~= "" then
            out[#out + 1] = '<small>' .. meta .. '</small>'
        end

        local sub_articles = parse_sub_articles(item.description or "", loc)
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
    out[#out + 1] = '<center><small>Powered by Lua on nginx | Headlines from <a href="https://news.google.com/">Google News</a></small></center>'
    out[#out + 1] = '</body></html>'

    send_response(200, table.concat(out))
end

local ok, err = pcall(handle)
if not ok then
    ngx.header["Content-Type"] = "text/html; charset=utf-8"
    ngx.status = 502
    ngx.say('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN"><html><head>' ..
        '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">' ..
        '<title>ruby.news: Error</title></head><body>' ..
        '<center><h1><b>ruby.news:</b> <font color="#9400d3"><i>Headlines from the Future</i></font></h1></center>' ..
        '<hr><small>Error: ' .. tostring(err) .. '</small></body></html>')
    ngx.exit(ngx.OK)
end
