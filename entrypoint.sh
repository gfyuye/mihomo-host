#!/bin/sh
set -e

# 配置 Mihomo
if [ ! -f /etc/mihomo/config.yaml ]; then
    if [ -n "$SUBSCRIBE_URL" ]; then
        echo "Downloading subscribe file..."
        curl -sL -H "User-Agent: clash.meta" -o /etc/mihomo/config.yaml "$SUBSCRIBE_URL"
    else
        echo "No config file found and no SUBSCRIBE_URL provided"
        exit 1
    fi
fi

# 启动 Mihomo
echo "Starting Mihomo..."
/usr/local/bin/mihomo -d /etc/mihomo 2>&1 | tee /var/log/mihomo/mihomo.log &

# 等待 Mihomo 启动
sleep 2

# 启动 Nginx
echo "Starting Nginx..."
nginx -g 'daemon off;'
