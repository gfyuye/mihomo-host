# 使用支持多架构的 Alpine 作为基础镜像
FROM alpine:latest

# 安装必要的工具
RUN apk add --no-cache curl tar gzip bash jq

# 设置构建参数
ARG TARGETPLATFORM
ARG ZASHBOARD_DOWNLOAD_URL

# 创建工作目录
WORKDIR /app

# 单个 RUN 命令完成所有 Mihomo 相关操作
RUN --mount=type=secret,id=MIHOMO_RELEASE_DATA \
    set -e && \
    echo "=== Processing platform ${TARGETPLATFORM} ===" && \
    \
    # 检查并读取 secret
    if [ ! -f /run/secrets/MIHOMO_RELEASE_DATA ]; then \
        echo "ERROR: Secret file not found!" && exit 1; \
    fi && \
    echo "Secret file found, size: $(wc -c < /run/secrets/MIHOMO_RELEASE_DATA) bytes" && \
    MIHOMO_RELEASE_DATA=$(cat /run/secrets/MIHOMO_RELEASE_DATA) && \
    \
    # 根据架构选择正确的二进制文件
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then \
        echo "Selecting amd64 v3 binary..." && \
        FILTER='.assets[] | select(.name | contains("linux-amd64-v3") and endswith(".gz")) | .browser_download_url'; \
    elif [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        echo "Selecting arm64 binary..." && \
        FILTER='.assets[] | select(.name | contains("linux-arm64") and endswith(".gz")) | .browser_download_url'; \
    else \
        echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1; \
    fi && \
    \
    echo "Using filter: ${FILTER}" && \
    \
    # 提取下载 URL
    MIHOMO_URL=$(echo "${MIHOMO_RELEASE_DATA}" | jq -r "${FILTER}" | head -n1) && \
    echo "Found URL: ${MIHOMO_URL}" && \
    \
    if [ -z "${MIHOMO_URL}" ] || [ "${MIHOMO_URL}" = "null" ]; then \
        echo "Error: Could not find appropriate Mihomo binary for ${TARGETPLATFORM}" && \
        echo "Available assets:" && \
        echo "${MIHOMO_RELEASE_DATA}" | jq -r '.assets[].name' && \
        exit 1; \
    fi && \
    \
    # 下载文件
    echo "Downloading Mihomo from: ${MIHOMO_URL}" && \
    curl -L -o mihomo.gz "${MIHOMO_URL}" && \
    \
    # 验证下载
    if [ ! -f mihomo.gz ] || [ ! -s mihomo.gz ]; then \
        echo "ERROR: Download failed or file is empty" && exit 1; \
    fi && \
    echo "Download complete, file size: $(wc -c < mihomo.gz) bytes" && \
    \
    # 解压并安装
    gzip -d mihomo.gz && \
    if [ ! -f mihomo ]; then \
        echo "ERROR: Decompression failed" && exit 1; \
    fi && \
    chmod +x mihomo && \
    mv mihomo /usr/local/bin/mihomo && \
    echo "Mihomo installed successfully at /usr/local/bin/mihomo"

# 下载并安装 zashboard
RUN set -e && \
    echo "=== Installing Zashboard ===" && \
    if [ -n "${ZASHBOARD_DOWNLOAD_URL}" ] && [ "${ZASHBOARD_DOWNLOAD_URL}" != "null" ]; then \
        echo "Downloading Zashboard from: ${ZASHBOARD_DOWNLOAD_URL}" && \
        mkdir -p /app/zashboard && \
        curl -L -o zashboard.archive "${ZASHBOARD_DOWNLOAD_URL}" && \
        \
        if [ ! -f zashboard.archive ] || [ ! -s zashboard.archive ]; then \
            echo "ERROR: Zashboard download failed" && exit 1; \
        fi && \
        \
        echo "Download complete, file type: $(file zashboard.archive)" && \
        \
        # 检查文件类型并解压
        if file zashboard.archive | grep -q "gzip compressed"; then \
            echo "Extracting gzip archive..." && \
            tar -xzf zashboard.archive -C /app/zashboard/; \
        elif file zashboard.archive | grep -q "Zip archive"; then \
            echo "Extracting zip archive..." && \
            apk add --no-cache unzip && \
            unzip -q zashboard.archive -d /app/zashboard/; \
        else \
            echo "Unknown archive format, copying as is" && \
            cp zashboard.archive /app/zashboard/; \
        fi && \
        rm zashboard.archive; \
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

# 使用启动脚本
CMD ["/start.sh"]
