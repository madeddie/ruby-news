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

local function handle()
    ngx.header["X-Robots-Tag"] = "noindex, nofollow"

    local loc = get_param("loc") or "US"
    loc = loc:upper()

    local article_url = get_param("a") or ""
    if not article_url or article_url == "" then
        send_response(400, 'What do you think you\'re doing... >;(')
    end

    if article_url:sub(1, 23) ~= "https://news.google.com" then
        send_response(400, "That's not news :(")
    end

    local decoder = require "google_news_decoder"
    local decode_result = decoder.decode_google_news_url(article_url)

    if not decode_result.status then
        send_response(502, "Failed to decode article URL: " .. (decode_result.message or "unknown error"))
    end

    local actual_article_url = decode_result.decoded_url

    local extract = require "article_extract"
    local allowed_tags = "<ol><ul><li><br><p><small><font><b><strong><i><em><blockquote><h1><h2><h3><h4><h5><h6>"

    local readable_article, title, extract_err = extract.fetch_and_extract(actual_article_url)

    if not readable_article or readable_article == "" then
        send_response(502, 'Failed to extract article' .. (extract_err and (': ' .. extract_err) or '') .. '<br>')
    end

    readable_article = string_utils.clean_str(readable_article)

    local html_utils = require "html"
    readable_article = html_utils.strip_tags(readable_article, allowed_tags)

    readable_article = readable_article:gsub("strong>", "b>"):gsub("em>", "i>")

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

    local out = {}
    out[#out + 1] = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 2.0//EN">'
    out[#out + 1] = '<html><head>'
    out[#out + 1] = '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
    out[#out + 1] = '<meta name="viewport" content="width=device-width, initial-scale=1">'

    local page_title = string_utils.clean_str(title or "flatland.nyc/news")
    out[#out + 1] = '<title>' .. page_title .. '</title>'
    out[#out + 1] = css
    out[#out + 1] = '</head><body>'

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
