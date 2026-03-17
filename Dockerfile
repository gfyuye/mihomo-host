# 使用 metacubex 官方镜像作为基础
FROM ghcr.io/metacubex/mihomo:latest AS builder

# 第二阶段：构建最终镜像
FROM alpine:latest

# 安装必要工具
RUN apk add --no-cache \
    nginx \
    curl \
    bash \
    supervisor \
    && rm -rf /var/cache/apk/*

# 设置工作目录
WORKDIR /app

# 复制 Mihomo 二进制文件
COPY --from=builder /mihomo /usr/local/bin/mihomo

# 下载 Zashboard
ARG ZASHBOARD_VERSION=latest
RUN if [ "$ZASHBOARD_VERSION" = "latest" ]; then \
        ZASHBOARD_URL=$(curl -s https://api.github.com/repos/zephyruso/zashboard/releases/latest | grep "browser_download_url.*dist.tar.gz" | cut -d : -f 2,3 | tr -d \"); \
    else \
        ZASHBOARD_URL="https://github.com/zephyruso/zashboard/releases/download/${ZASHBOARD_VERSION}/dist.tar.gz"; \
    fi && \
    curl -L -o /tmp/zashboard.tar.gz $ZASHBOARD_URL && \
    mkdir -p /usr/share/nginx/html/zashboard && \
    tar -xzf /tmp/zashboard.tar.gz -C /usr/share/nginx/html/zashboard --strip-components=1 && \
    rm /tmp/zashboard.tar.gz

# 创建必要目录
RUN mkdir -p /etc/mihomo /var/log/mihomo /run/nginx

# 配置 Nginx
COPY nginx.conf /etc/nginx/nginx.conf
COPY mihomo.conf /etc/nginx/conf.d/default.conf

# 配置启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 暴露端口
EXPOSE 80 7890 9090

# 设置健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
