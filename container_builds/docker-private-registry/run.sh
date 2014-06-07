#!/bin/bash
ADMIN_PASSWORD=${ADMIN_PASSWORD:-docker}
REGISTRY_NAME=${REGISTRY_NAME:-Docker Registry}
SSL_CERT_PATH=${SSL_CERT_PATH:-/opt/ssl/registry.ssl}
SSL_CERT_KEY_PATH=${SSL_CERT_KEY_PATH:-/opt/ssl/registry.ssl}
CACHE_REDIS_PASSWORD=${REDIS_PASSWORD:-docker}
CACHE_LRU_REDIS_PASSWORD=${REDIS_PASSWORD:-docker}

export CACHE_REDIS_PASSWORD
export CACHE_LRU_REDIS_PASSWORD

# nginx config
cat << EOF > /usr/local/openresty/nginx/conf/registry.conf
user root;
daemon off;
worker_processes 4;
pid /run/nginx.pid;

events {
	worker_connections 2048;
}

http {
	sendfile on;
	tcp_nopush on;
	tcp_nodelay on;
	keepalive_timeout 65;
	types_hash_max_size 2048;
	# server_tokens off;

	server_names_hash_bucket_size 64;
	server_name_in_redirect on;

	include /usr/local/openresty/nginx/conf/mime.types;
	default_type application/octet-stream;

	##
	# Logging Settings
	##

	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log;

	##
	# Gzip Settings
	##

	gzip on;
	gzip_disable "msie6";

	# gzip_vary on;
	# gzip_proxied any;
	# gzip_comp_level 6;
	# gzip_buffers 16 8k;
	# gzip_http_version 1.1;
	# gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;

	##
	# Virtual Host Configs
	##
        upstream manage {
          server localhost:4000;
        }
        upstream registry {
          server localhost:5000;
        }
        server {
            listen 80;
            client_max_body_size 0;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Scheme \$scheme;
            proxy_set_header Authorization  "";
            location / {
                auth_basic "$REGISTRY_NAME";
                auth_basic_user_file /etc/registry.users;
                proxy_pass http://registry;
            }
            location /v1/_ping {
                auth_basic off;
                proxy_pass http://registry;
            }
            location /v1/users {
                auth_basic off;
                proxy_pass http://registry;
            }
            location /static {
                alias /app/static;
                expires 1d;
            }
            location = /manage { rewrite ^ /manage/; }
            location /manage/ { try_files \$uri @manage; }
            location @manage {
                auth_basic "$REGISTRY_NAME";
                auth_basic_user_file /etc/registry.users;
                proxy_redirect off;
                include uwsgi_params;
                uwsgi_param SCRIPT_NAME /manage;
                uwsgi_modifier1 30;
                uwsgi_pass unix:/tmp/uwsgi-manage.sock;
            }
        }
EOF
if [ ! -z "$SSL_CERT_PATH" ]; then
    cat << EOF >> /usr/local/openresty/nginx/conf/registry.conf
        server {
            listen 443;
            ssl on;
            ssl_certificate $SSL_CERT_PATH;
            ssl_certificate_key $SSL_CERT_KEY_PATH;
            client_max_body_size 0;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Scheme \$scheme;
            proxy_set_header Authorization  "";
            location / {
                auth_basic "$REGISTRY_NAME";
                auth_basic_user_file /etc/registry.users;
                proxy_pass http://registry;
            }
            location /v1/_ping {
                auth_basic off;
                proxy_pass http://registry;
            }
            location /v1/users {
                auth_basic off;
                proxy_pass http://registry;
            }
            location /static {
                alias /app/static;
                expires 1d;
            }
            location = /manage { rewrite ^ /manage/; }
            location /manage/ { try_files \$uri @manage; }
            location @manage {
                auth_basic "$REGISTRY_NAME";
                auth_basic_user_file /etc/registry.users;
                proxy_redirect off;
                include uwsgi_params;
                uwsgi_param SCRIPT_NAME /manage;
                uwsgi_modifier1 30;
                uwsgi_pass unix:/tmp/uwsgi-manage.sock;
            }
        }
EOF
fi
cat << EOF >> /usr/local/openresty/nginx/conf/registry.conf
}
EOF

# uwsgi config (manage)
cat << EOF > /etc/manage.ini
[uwsgi]
chdir = /app
socket = /tmp/uwsgi-manage.sock
workers = 8
buffer-size = 32768
master = true
max-requests = 5000
static-map = /static=/app/static
module = wsgi:application
EOF

# redis config
cat << EOF >> /etc/redis.conf
daemonize no
requirepass $CACHE_REDIS_PASSWORD
maxmemory 2mb
maxmemory-policy allkeys-lru
EOF

# supervisor config
cat << EOF > /etc/supervisor/supervisor.conf
[supervisord]
nodaemon=false

[unix_http_server]
file=/var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run//supervisor.sock

[program:redis]
priority=05
user=root
command=/usr/bin/redis-server /etc/redis.conf
directory=/var/lib/redis
autostart=true
autorestart=true
stopsignal=QUIT

[program:registry]
priority=10
user=root
command=gunicorn --access-logfile - --debug --max-requests 5000 --graceful-timeout 3600 -t 3600 -k gevent -b 0.0.0.0:5000 -w 4 wsgi:application
directory=/docker-registry
autostart=true
autorestart=true
stopsignal=QUIT

[program:manage]
priority=20
user=root
command=/usr/local/bin/uwsgi --ini /etc/manage.ini
directory=/app
autostart=true
autorestart=true
stopsignal=QUIT

[program:nginx]
priority=50
user=root
command=/usr/local/openresty/nginx/sbin/nginx -c /usr/local/openresty/nginx/conf/registry.conf
directory=/tmp
autostart=true
autorestart=true
EOF

# create password file if needed
if [ ! -e "/etc/registry.users" ] ; then
    htpasswd -bc /etc/registry.users admin $ADMIN_PASSWORD
fi

# configure registry
cd /docker-registry
bash setup-configs.sh
# run supervisor
supervisord -c /etc/supervisor/supervisor.conf -n
