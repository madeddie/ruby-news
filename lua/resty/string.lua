-- Pure-Lua drop-in for the resty.string subset used by lua-resty-http
-- (the OpenResty version uses ffi/ngx_hex_dump which is not available
-- in plain nginx builds)
local _M = {}

function _M.to_hex(s)
    return (s:gsub('.', function(c)
        return string.format('%02x', string.byte(c))
    end))
end

return _M
