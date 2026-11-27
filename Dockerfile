FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        libnginx-mod-http-lua \
        ca-certificates \
        curl \
    && mkdir -p /etc/nginx/lua/resty \
    && curl -sLo /etc/nginx/lua/resty/http.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http.lua \
    && curl -sLo /etc/nginx/lua/resty/http_connect.lua \
        https://raw.githubusercontent.com/ledgetech/lua-resty-http/v0.17.2/lib/resty/http_connect.lua \
    && rm -rf /var/lib/apt/lists/*

COPY lua/ /etc/nginx/lua/

RUN printf '\
load_module modules/ndk_http_module.so;\n\
load_module modules/ngx_http_lua_module.so;\n\
\n\
worker_processes auto;\n\
\n\
events {\n\
    worker_connections 1024;\n\
}\n\
\n\
http {\n\
    include       /etc/nginx/mime.types;\n\
    default_type  application/octet-stream;\n\
    sendfile      on;\n\
    keepalive_timeout 65;\n\
\n\
    lua_shared_dict news_cache 10m;\n\
    lua_shared_dict article_cache 20m;\n\
    lua_package_path "/etc/nginx/lua/?.lua;;";\n\
\n\
    server {\n\
        listen 80;\n\
        server_name _;\n\
\n\
        resolver 8.8.8.8 8.8.4.4 ipv6=off;\n\
        resolver_timeout 5s;\n\
\n\
        location = / {\n\
            return 301 /news;\n\
        }\n\
\n\
        location /news {\n\
            content_by_lua_file /etc/nginx/lua/handlers/index.lua;\n\
        }\n\
\n\
        location /news/article {\n\
            content_by_lua_file /etc/nginx/lua/handlers/article.lua;\n\
        }\n\
\n\
        location /news/choose_edition {\n\
            content_by_lua_file /etc/nginx/lua/handlers/choose_edition.lua;\n\
        }\n\
\n\
        error_page 500 502 503 504 /50x.html;\n\
        location = /50x.html {\n\
            root /usr/share/nginx/html;\n\
            internal;\n\
        }\n\
    }\n\
}\n' > /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
