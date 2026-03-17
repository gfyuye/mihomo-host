# 使用支持多架构的 Alpine 作为基础镜像
FROM alpine:latest

# 安装必要的工具
RUN apk add --no-cache curl tar gzip bash

# 设置构建参数
ARG TARGETPLATFORM
ARG MIHOMO_RELEASE_DATA
ARG ZASHBOARD_DOWNLOAD_URL

# 创建工作目录
WORKDIR /app

# 根据架构选择正确的 Mihomo 下载 URL
RUN echo "Target platform: ${TARGETPLATFORM}" && \
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then \
        MIHOMO_URL=$(echo "${MIHOMO_RELEASE_DATA}" | grep -o '"browser_download_url": *"[^"]*linux-amd64-v3[^"]*"' | sed 's/"browser_download_url": "//;s/"//g' | head -n1); \
    elif [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        MIHOMO_URL=$(echo "${MIHOMO_RELEASE_DATA}" | grep -o '"browser_download_url": *"[^"]*linux-arm64[^"]*"' | sed 's/"browser_download_url": "//;s/"//g' | head -n1); \
    else \
        echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1; \
    fi && \
    if [ -z "${MIHOMO_URL}" ] || [ "${MIHOMO_URL}" = "null" ]; then \
        echo "Error: Could not find appropriate Mihomo binary for ${TARGETPLATFORM}" && exit 1; \
    fi && \
    echo "Downloading Mihomo from: ${MIHOMO_URL}" && \
    curl -L -o mihomo.gz "${MIHOMO_URL}" && \
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
        # 检查文件类型并解压
        if file zashboard.archive | grep -q "gzip compressed"; then \
            tar -xzf zashboard.archive -C /app/zashboard/; \
        elif file zashboard.archive | grep -q "Zip archive"; then \
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

# 复制配置文件（假设在仓库中有 config.yaml）
# 如果配置文件不在仓库中，可以通过卷挂载的方式提供
COPY config.yaml /etc/mihomo/config.yaml

# 创建启动脚本
RUN echo '#!/bin/sh' > /start.sh && \
    echo '# 后台启动 mihomo' >> /start.sh && \
    echo '/usr/local/bin/mihomo -d /etc/mihomo 2>&1 | tee /var/log/mihomo.log &' >> /start.sh && \
    echo '# 保持容器运行' >> /start.sh && \
    echo 'tail -f /dev/null' >> /start.sh && \
    chmod +x /start.sh

# 暴露端口
EXPOSE 7890 7891 9090

# 使用启动脚本
CMD ["/start.sh"]
