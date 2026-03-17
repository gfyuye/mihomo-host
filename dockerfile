# 使用 archlinux 作为基础镜像
FROM archlinux:latest

# 设置构建参数，用于接收从 Actions 传入的下载链接
ARG MIHOMO_DOWNLOAD_URL
ARG ZASHBOARD_DOWNLOAD_URL

# 安装必要的工具：curl, jq, zstd (用于解压 .zst 文件)，以及 unzip 或 tar (根据zashboard的包格式)
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm curl jq zstd unzip tar && \
    pacman -Scc --noconfirm

# 创建工作目录
WORKDIR /app

# 下载并安装 mihomo (使用构建时传入的URL)
RUN echo "Downloading Mihomo from: ${MIHOMO_DOWNLOAD_URL}" && \
    curl -L -o mihomo.pkg.tar.zst "${MIHOMO_DOWNLOAD_URL}" && \
    # 使用 pacman 的 -U 选项直接从本地包文件安装
    # --noconfirm 跳过确认，--root 可以指定安装路径，但为了简单起见，我们直接安装到系统
    pacman -U --noconfirm mihomo.pkg.tar.zst && \
    rm mihomo.pkg.tar.zst

# 下载并安装 zashboard
# 注意：这里需要根据实际下载的包类型（如 .zip 或 .tar.gz）来处理
RUN echo "Downloading Zashboard from: ${ZASHBOARD_DOWNLOAD_URL}" && \
    # 创建一个目录存放zashboard文件
    mkdir -p /app/zashboard && \
    # 下载文件
    curl -L -o zashboard.archive "${ZASHBOARD_DOWNLOAD_URL}" && \
    # 根据文件类型解压 (这里假设是 .zip 文件，如果是 .tar.gz 或 .tar.xz 需要调整)
    # 可以使用 file 命令检测，但为了简化，我们尝试使用 unzip
    unzip zashboard.archive -d /app/zashboard/ || \
    # 如果 unzip 失败，尝试使用 tar
    tar -xf zashboard.archive -C /app/zashboard/ || \
    (echo "Failed to extract Zashboard archive" && exit 1) && \
    rm zashboard.archive

# 暴露 mihomo 的常用端口 (根据实际需要调整)
EXPOSE 7890 7891 9090

# 可以设置默认命令，例如启动 mihomo
# 注意：你可能需要根据实际情况修改配置文件路径
CMD ["/usr/bin/mihomo", "-d", "/etc/mihomo"]
