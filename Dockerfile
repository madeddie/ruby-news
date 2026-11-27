FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        libnginx-mod-http-lua \
        ca-certificates \
        curl \
        python3 \
        python3-pip \
    && pip3 install --no-cache-dir readability-lxml --break-system-packages \
    && rm -rf /var/lib/apt/lists/* /root/.cache/pip

# Install lua-resty-http and dkjson (as cjson drop-in; identical API, pure Lua)
RUN mkdir -p /etc/nginx/lua/resty \
    && curl -sLo /etc/nginx/lua/resty/http.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http.lua \
    && curl -sLo /etc/nginx/lua/resty/http_connect.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http_connect.lua \
    && curl -sLo /etc/nginx/lua/resty/http_headers.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http_headers.lua \
    && curl -sLo /etc/nginx/lua/cjson.lua \
        https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua

COPY lua/ /etc/nginx/lua/
# Remove any stray .so files that dependencies may have dropped here
RUN find /etc/nginx/lua -name '*.so' -delete
COPY nginx.conf.docker /etc/nginx/nginx.conf
COPY readability_service.py /app/readability_service.py

EXPOSE 80 5000

CMD ["nginx", "-g", "daemon off;"]
