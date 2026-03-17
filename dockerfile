# 使用支持多架构的 Alpine 作为基础镜像
FROM alpine:latest

# 安装必要的工具
RUN apk add --no-cache curl tar gzip bash jq

# 设置构建参数
ARG TARGETPLATFORM
ARG ZASHBOARD_DOWNLOAD_URL

# 创建工作目录
WORKDIR /app

# 挂载 secret 文件（在构建时通过 --secret 注入）
RUN --mount=type=secret,id=MIHOMO_RELEASE_DATA \
    echo "Target platform: ${TARGETPLATFORM}" && \
    echo "Processing Mihomo release data..." && \
    \
    # 从 secret 文件读取数据
    MIHOMO_RELEASE_DATA=$(cat /run/secrets/MIHOMO_RELEASE_DATA) && \
    \
    # 根据架构选择正确的二进制文件
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then \
        # 查找 amd64 v3 版本
        FILTER='.assets[] | select(.name | contains("linux-amd64-v3") and endswith(".gz")) | .browser_download_url'; \
    elif [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        # 查找 arm64 版本
        FILTER='.assets[] | select(.name | contains("linux-arm64") and endswith(".gz")) | .browser_download_url'; \
    else \
        echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1; \
    fi && \
    \
    # 使用 jq 从 JSON 中提取 URL
    MIHOMO_URL=$(echo "${MIHOMO_RELEASE_DATA}" | jq -r "${FILTER}" | head -n1) && \
    \
    if [ -z "${MIHOMO_URL}" ] || [ "${MIHOMO_URL}" = "null" ]; then \
        echo "Error: Could not find appropriate Mihomo binary for ${TARGETPLATFORM}" && \
        echo "Available assets:" && \
        echo "${MIHOMO_RELEASE_DATA}" | jq '.assets[].name' && \
        exit 1; \
    fi && \
    \
    echo "Downloading Mihomo from: ${MIHOMO_URL}" && \
    curl -L -o mihomo.gz "${MIHOMO_URL}" && \
    \
    # 解压 gz 文件并重命名为 mihomo
    gzip -d mihomo.gz && \
    chmod +x mihomo && \
    mv mihomo /usr/local/bin/mihomo && \
    echo "Mihomo installed successfully"

# 下载并安装 zashboard
RUN if [ -n "${ZASHBOARD_DOWNLOAD_URL}" ] && [ "${ZASHBOARD_DOWNLOAD_URL}" != "null" ]; then \
        echo "Downloading Zashboard from: ${ZASHBOARD_DOWNLOAD_URL}" && \
        mkdir -p /app/zashboard && \
        curl -L -o zashboard.archive "${ZASHBOARD_DOWNLOAD_URL}" && \
        \
        # 检查文件类型并解压
        if file zashboard.archive | grep -q "gzip compressed"; then \
            tar -xzf zashboard.archive -C /app/zashboard/; \
        elif file zashboard.archive | grep -q "Zip archive"; then \
            apk add --no-cache unzip && \
            unzip zashboard.archive -d /app/zashboard/; \
        else \
            echo "Unknown archive format, copying as is" && \
            cp zashboard.archive /app/zashboard/; \
        fi && \
        rm zashboard.archive; \
    else \
        echo "Zashboard download URL not provided, skipping..."; \
    fi

# 创建必要的目录
RUN mkdir -p /etc/mihomo /var/log

# 创建默认配置文件
RUN if [ ! -f /etc/mihomo/config.yaml ]; then \
        cat > /etc/mihomo/config.yaml << 'EOF' && \
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
external-controller: 0.0.0.0:9090

proxies: []

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - DIRECT

rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
        echo "Created default config.yaml"; \
    fi

# 创建启动脚本
RUN echo '#!/bin/sh' > /start.sh && \
    echo '# 后台启动 mihomo' >> /start.sh && \
    echo 'echo "Starting mihomo..."' >> /start.sh && \
    echo '/usr/local/bin/mihomo -d /etc/mihomo 2>&1 | tee /var/log/mihomo.log &' >> /start.sh && \
    echo 'MIHOMO_PID=$!' >> /start.sh && \
    echo 'echo "Mihomo started with PID: $MIHOMO_PID"' >> /start.sh && \
    echo '# 保持容器运行并监控日志' >> /start.sh && \
    echo 'tail -f /var/log/mihomo.log' >> /start.sh && \
    chmod +x /start.sh

# 暴露端口
EXPOSE 7890 7891 9090

CMD ["/start.sh"]
