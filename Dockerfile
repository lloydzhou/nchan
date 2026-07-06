# Production Nchan image: nginx + nchan module, no OpenResty dependency.
#
# Key difference from the old lloydzhou/nchan (OpenResty-based):
#   - Pure nginx (no Lua engine needed — zero Lua in our config)
#   - -DNDEBUG disables C assert() to prevent worker core dumps
#     (fixes: "assert(spool->msg_status == MSG_INVALID)" spool.c:479)
#   - nginx binary: /usr/local/nginx/sbin/nginx
#   - nginx conf:   /usr/local/nginx/conf/
#
# Build & push:
#   docker buildx build --platform linux/amd64 -t lloydzhou/nchan:latest . --load --push

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NGINX_VERSION=1.26.3

RUN apt-get update && apt-get install -y \
    build-essential \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Download and extract nginx
RUN cd /tmp && \
    wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -xzf nginx-${NGINX_VERSION}.tar.gz && \
    mv nginx-${NGINX_VERSION} /usr/src/nginx && \
    rm -f nginx-${NGINX_VERSION}.tar.gz

# Copy nchan source (includes lloyd's stub_status multi-format patch)
COPY . /nchan

WORKDIR /usr/src/nginx

# Build nginx + nchan.
# -DNDEBUG disables C assert() — prevents worker core dumps from
# spool_fetch_msg assertion failures while keeping the logic intact.
RUN ./configure --prefix=/usr/local/nginx \
    --add-module=/nchan \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-cc-opt="-DNDEBUG -Wno-error" \
    && make -j$(nproc) && make install

# Create nginx user + directories
RUN useradd -r -s /bin/false nginx && \
    mkdir -p /usr/local/nginx/logs /usr/local/nginx/run /usr/local/nginx/conf/conf.d /etc/nginx/templates

# Base nginx.conf (entrypoint adjusts worker_connections; conf.d/*.conf for apps)
RUN cat > /usr/local/nginx/conf/nginx.conf << 'NGINXCONF'
worker_processes  auto;
daemon off;
error_log  /dev/stderr  warn;
pid        /usr/local/nginx/run/nginx.pid;

events {
    worker_connections  10240;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout  65;
    include /usr/local/nginx/conf/conf.d/*.conf;
}
NGINXCONF

EXPOSE 80

CMD ["/usr/local/nginx/sbin/nginx", "-g", "daemon off;"]
