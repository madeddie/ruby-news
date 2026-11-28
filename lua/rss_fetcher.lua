local _M = {}

-- NPR feed IDs: https://feeds.npr.org/FEEDID/rss.xml
local NPR_FEEDS = {
    world         = "1004",
    business      = "1006",
    technology    = "1019",
    health        = "1013",
    sports        = "1055",
    science       = "1007",
    entertainment = "1008",
}

-- BBC uses full URLs because sport lives outside /news/
local BBC_SECTION_URLS = {
    world         = "https://feeds.bbci.co.uk/news/world/rss.xml",
    business      = "https://feeds.bbci.co.uk/news/business/rss.xml",
    technology    = "https://feeds.bbci.co.uk/news/technology/rss.xml",
    health        = "https://feeds.bbci.co.uk/news/health/rss.xml",
    sports        = "https://feeds.bbci.co.uk/sport/rss.xml",
    science       = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
    entertainment = "https://feeds.bbci.co.uk/news/entertainment_and_arts/rss.xml",
}

local function http_get(url)
    local http = require "resty.http"

    local opts = {
        method = "GET",
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        },
        ssl_verify = false,
    }

    for _ = 1, 5 do
        local httpc = http.new()
        httpc:set_timeout(15000)
        local res, err = httpc:request_uri(url, opts)
        if not res then
            ngx.log(ngx.ERR, "http_get failed: ", err)
            return nil, "request failed: " .. tostring(err)
        end

        if res.status == 301 or res.status == 302 or res.status == 307 or res.status == 308 then
            url = res.headers["Location"]
            if not url then
                return nil, "redirect with no Location header"
            end
        elseif res.status == 200 then
            return res.body
        else
            ngx.log(ngx.ERR, "http_get non-200: ", res.status)
            return nil, "HTTP " .. res.status
        end
    end

    return nil, "too many redirects"
end

local function parse_xml_feed(body)
    local feed = { title = "", items = {} }

    local title_match = body:match("<title>(.-)</title>")
    if title_match then
        title_match = title_match:gsub("&nbsp;", " - "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        feed.title = title_match
    end

    local items_start = 1
    while true do
        local item_start, item_end = body:find("<item>", items_start)
        if not item_start then break end

        local item_end_tag = body:find("</item>", item_end or item_start)
        if not item_end_tag then break end

        local item_html = body:sub(item_start, item_end_tag + 7)
        items_start = item_end_tag + 7

        local title, link, description, pub_date = "", "", "", ""

        local t_match = item_html:match("<title>(.-)</title>")
        if t_match then
            title = t_match:gsub("&nbsp;", " - "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        end

        local l_match = item_html:match("<link>(.-)</link>")
        if l_match then
            link = l_match:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        end

        local d_match = item_html:match("<description>(.-)</description>")
        if d_match then
            description = d_match:gsub("&nbsp;", " - "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        end

        local pd_match = item_html:match("<pubDate>(.-)</pubDate>")
        if pd_match then pub_date = pd_match end

        if title ~= "" or link ~= "" then
            table.insert(feed.items, {
                title       = title,
                link        = link,
                description = description,
                pub_date    = pub_date,
            })
        end
    end

    return feed
end

function _M.fetch_feed(news_source, section, loc, lang)
    local url

    if news_source == "npr" then
        local feed_id = section and NPR_FEEDS[section] or "1001"
        url = "https://feeds.npr.org/" .. feed_id .. "/rss.xml"
    elseif news_source == "bbc" then
        url = (section and BBC_SECTION_URLS[section])
            or "https://feeds.bbci.co.uk/news/rss.xml"
    else
        if section then
            url = string.format(
                "https://news.google.com/rss/headlines/section/topic/%s?ned=%s&hl=%s",
                section:upper(), loc, lang
            )
        else
            url = string.format(
                "https://news.google.com/rss?gl=%s&hl=%s-%s&ceid=%s:%s",
                loc, lang, loc, loc, lang
            )
        end
    end

    local body, err = http_get(url)
    if body and #body > 0 then
        return parse_xml_feed(body)
    end

    return nil, err or "empty response"
end

return _M
