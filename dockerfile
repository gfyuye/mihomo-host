# 使用支持多架构的 Alpine 作为基础镜像
FROM alpine:latest

# 安装必要的工具
RUN apk add --no-cache curl tar gzip bash jq busybox-extras

# 设置构建参数
ARG TARGETPLATFORM
ARG ZASHBOARD_DOWNLOAD_URL

# 创建工作目录
WORKDIR /app

# 下载并安装 Mihomo（使用之前正确的筛选条件）
RUN --mount=type=secret,id=MIHOMO_RELEASE_DATA \
    set -e && \
    echo "=== Processing platform ${TARGETPLATFORM} ===" && \
    \
    if [ ! -f /run/secrets/MIHOMO_RELEASE_DATA ]; then \
        echo "ERROR: Secret file not found!" && exit 1; \
    fi && \
    MIHOMO_RELEASE_DATA=$(cat /run/secrets/MIHOMO_RELEASE_DATA) && \
    \
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then \
        echo "Selecting amd64 v3 binary (standard version)..." && \
        FILTER='.assets[] | select(.name | test("linux-amd64-v3-v[0-9]+\\.[0-9]+\\.[0-9]+\\.gz$")) | .browser_download_url'; \
    elif [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        echo "Selecting arm64 binary (standard version)..." && \
        FILTER='.assets[] | select(.name | test("linux-arm64-v[0-9]+\\.[0-9]+\\.[0-9]+\\.gz$")) | .browser_download_url'; \
    else \
        echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1; \
    fi && \
    \
    MIHOMO_URL=$(echo "${MIHOMO_RELEASE_DATA}" | jq -r "${FILTER}" | head -n1) && \
    \
    if [ -z "${MIHOMO_URL}" ] || [ "${MIHOMO_URL}" = "null" ]; then \
        echo "Error: Could not find appropriate Mihomo binary" && exit 1; \
    fi && \
    \
    echo "Downloading Mihomo from: ${MIHOMO_URL}" && \
    curl -L -o mihomo.gz "${MIHOMO_URL}" && \
    gzip -d mihomo.gz && \
    chmod +x mihomo && \
    mv mihomo /usr/local/bin/mihomo && \
    echo "Mihomo installed successfully"

# 下载并安装 zashboard
RUN set -e && \
    echo "=== Installing Zashboard ===" && \
    if [ -n "${ZASHBOARD_DOWNLOAD_URL}" ] && [ "${ZASHBOARD_DOWNLOAD_URL}" != "null" ]; then \
        echo "Downloading Zashboard from: ${ZASHBOARD_DOWNLOAD_URL}" && \
        mkdir -p /app/zashboard && \
        curl -L -o zashboard.zip "${ZASHBOARD_DOWNLOAD_URL}" && \
        \
        if [ ! -f zashboard.zip ] || [ ! -s zashboard.zip ]; then \
            echo "ERROR: Zashboard download failed" && exit 1; \
        fi && \
        \
        echo "Download complete, file size: $(wc -c < zashboard.zip) bytes" && \
        apk add --no-cache unzip && \
        echo "Extracting zip archive..." && \
        unzip -q zashboard.zip -d /app/zashboard/ && \
        \
        # 如果解压后有 dist 目录，将其内容移出
        if [ -d "/app/zashboard/dist" ]; then \
            echo "Moving dist contents to /app/zashboard..." && \
            mv /app/zashboard/dist/* /app/zashboard/ 2>/dev/null || true && \
            rmdir /app/zashboard/dist 2>/dev/null || true; \
        fi && \
        \
        rm zashboard.zip; \
        echo "Zashboard installed to /app/zashboard"; \
    else \
        echo "Zashboard download URL not provided, skipping..."; \
    fi

# 创建必要的目录
RUN mkdir -p /etc/mihomo /var/log

# 创建默认配置文件
RUN echo 'port: 7890' > /etc/mihomo/config.yaml && \
    echo 'socks-port: 7891' >> /etc/mihomo/config.yaml && \
    echo 'allow-lan: true' >> /etc/mihomo/config.yaml && \
    echo 'mode: rule' >> /etc/mihomo/config.yaml && \
    echo 'log-level: info' >> /etc/mihomo/config.yaml && \
    echo 'external-controller: 0.0.0.0:9090' >> /etc/mihomo/config.yaml && \
    echo '' >> /etc/mihomo/config.yaml && \
    echo 'proxies: []' >> /etc/mihomo/config.yaml && \
    echo '' >> /etc/mihomo/config.yaml && \
    echo 'proxy-groups:' >> /etc/mihomo/config.yaml && \
    echo '  - name: "PROXY"' >> /etc/mihomo/config.yaml && \
    echo '    type: select' >> /etc/mihomo/config.yaml && \
    echo '    proxies:' >> /etc/mihomo/config.yaml && \
    echo '      - DIRECT' >> /etc/mihomo/config.yaml && \
    echo '' >> /etc/mihomo/config.yaml && \
    echo 'rules:' >> /etc/mihomo/config.yaml && \
    echo '  - GEOIP,CN,DIRECT' >> /etc/mihomo/config.yaml && \
    echo '  - MATCH,PROXY' >> /etc/mihomo/config.yaml

# 创建启动脚本（同时启动 mihomo 和 zashboard web server）
RUN echo '#!/bin/sh' > /start.sh && \
    echo '# 后台启动 mihomo' >> /start.sh && \
    echo 'echo "Starting mihomo..."' >> /start.sh && \
    echo '/usr/local/bin/mihomo -d /etc/mihomo 2>&1 | tee /var/log/mihomo.log &' >> /start.sh && \
    echo 'MIHOMO_PID=$!' >> /start.sh && \
    echo 'echo "Mihomo started with PID: $MIHOMO_PID"' >> /start.sh && \
    echo '' >> /start.sh && \
    echo '# 启动静态文件服务器（zashboard）' >> /start.sh && \
    echo 'echo "Starting zashboard web server on port 8080..."' >> /start.sh && \
    echo 'cd /app/zashboard && busybox httpd -f -p 8080 -h /app/zashboard &' >> /start.sh && \
    echo 'HTTPD_PID=$!' >> /start.sh && \
    echo 'echo "Zashboard server started with PID: $HTTPD_PID"' >> /start.sh && \
    echo '' >> /start.sh && \
    echo '# 保持容器运行并监控日志' >> /start.sh && \
    echo 'tail -f /var/log/mihomo.log' >> /start.sh && \
    chmod +x /start.sh

# 暴露端口：mihomo 端口(7890,7891,9090) + zashboard web端口(8080)
EXPOSE 7890 7891 9090 8080

# 使用启动脚本
CMD ["/start.sh"]
