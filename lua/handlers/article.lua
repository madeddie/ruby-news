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

local css = [[<style type="text/css"><!--
body { font-size: 1.1em; line-height: 1.7; overflow-wrap: break-word; margin: 0; padding: 0.75em; }
@media only screen and (min-width: 50em) {
body { max-width: 40em; margin: 0 auto; padding: 0 2em; }
}
@media (prefers-color-scheme: dark) {
body { background-color: #111; color: #ddd; }
a { color: #6af; }
a:visited { color: #a8c; }
}
--></style>]]

local function page_head(title)
    return '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">\n' ..
        '<html><head>\n' ..
        '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">\n' ..
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n' ..
        '<title>' .. title .. '</title>\n' ..
        css .. '\n</head><body>\n'
end

local function send_error(status, loc, headline, detail, links)
    local out = page_head("flatland.nyc/news: Error")
    out = out .. '<small><a href="/news?loc=' .. loc .. '">&lt; Back to flatland.nyc/news ' .. loc .. '</a></small>\n'
    out = out .. '<h2>' .. headline .. '</h2>\n'
    if detail then
        out = out .. '<p><small>' .. detail .. '</small></p>\n'
    end
    if links then
        for _, link in ipairs(links) do
            out = out .. '<p><a href="' .. link.url .. '">' .. link.label .. '</a></p>\n'
        end
    end
    out = out .. '</body></html>'
    send_response(status, out)
end

local function handle()
    ngx.header["X-Robots-Tag"] = "noindex, nofollow"

    local loc = get_param("loc") or "US"
    loc = loc:upper()
    local article_url = get_param("a") or ""

    if article_url == "" then
        send_error(400, loc, "No article URL provided.", nil, nil)
    end

    local article_source = get_param("source") or ""
    local allowed = false
    if article_source == "hn" then
        allowed = article_url:sub(1, 8) == "https://"
    else
        for _, prefix in ipairs({
            "https://news.google.com/",
            "https://www.npr.org/",
            "https://www.bbc.com/",
            "https://www.bbc.co.uk/",
        }) do
            if article_url:sub(1, #prefix) == prefix then
                allowed = true
                break
            end
        end
    end
    if not allowed then
        send_error(400, loc, "Invalid article URL.", "Unsupported source domain.", nil)
    end

    local actual_article_url
    if article_url:sub(1, 23) == "https://news.google.com" then
        local decoder = require "google_news_decoder"
        local decode_result = decoder.decode_google_news_url(article_url)
        if not decode_result.status then
            send_error(502, loc,
                "Could not resolve article link.",
                "Google News URL decoding failed: " .. (decode_result.message or "unknown error"),
                { { url = article_url, label = "Open on Google News instead" } }
            )
        end
        actual_article_url = decode_result.decoded_url
    else
        actual_article_url = article_url
    end

    local extract = require "article_extract"
    local allowed_tags = "<ol><ul><li><br><p><small><font><b><strong><i><em><blockquote><h1><h2><h3><h4><h5><h6>"

    local readable_article, title, extract_err = extract.fetch_and_extract(actual_article_url)

    if not readable_article or readable_article == "" then
        send_error(502, loc,
            "Could not extract article content.",
            extract_err or "The readability service returned no content.",
            {
                { url = actual_article_url, label = "Open original article directly" },
                { url = article_url,        label = "Open on Google News" },
            }
        )
    end

    readable_article = string_utils.clean_str(readable_article)
    local html_utils = require "html"
    readable_article = html_utils.strip_tags(readable_article, allowed_tags)
    readable_article = readable_article:gsub("strong>", "b>"):gsub("em>", "i>")

    local page_title = string_utils.clean_str(title or "flatland.nyc/news")

    local out = {}
    out[#out + 1] = page_head(page_title)
    out[#out + 1] = '<small><a href="/news?loc=' .. loc .. '">&lt; Back to flatland.nyc/news ' .. loc .. '</a></small>'
    out[#out + 1] = '<h1>' .. page_title .. '</h1>'
    out[#out + 1] = '<p><small><a href="' .. actual_article_url .. '" target="_blank">Original source</a></small></p>'
    out[#out + 1] = '<hr>'
    out[#out + 1] = readable_article
    out[#out + 1] = '<hr>'
    out[#out + 1] = '<small><a href="/news?loc=' .. loc .. '">&lt; Back to flatland.nyc/news ' .. loc .. '</a></small>'
    out[#out + 1] = '</body></html>'

    send_response(200, table.concat(out))
end

handle()
