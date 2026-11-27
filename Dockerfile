FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        libnginx-mod-http-lua \
        lua-cjson \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Install lua-resty-http and its dependencies; symlink cjson.so for lua_package_cpath
RUN mkdir -p /etc/nginx/lua/resty \
    && ln -s "$(find /usr/lib -name 'cjson.so' | head -1)" /etc/nginx/lua/cjson.so \
    && curl -sLo /etc/nginx/lua/resty/http.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http.lua \
    && curl -sLo /etc/nginx/lua/resty/http_connect.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http_connect.lua \
    && curl -sLo /etc/nginx/lua/resty/http_headers.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http_headers.lua

COPY lua/ /etc/nginx/lua/
COPY nginx.conf.docker /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
