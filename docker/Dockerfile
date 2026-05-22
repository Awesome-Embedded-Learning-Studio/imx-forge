#
# IMX-Forge Docker 构建环境
# 
# 多阶段构建，优化镜像大小
# 阶段1: builder - 下载和解压工具链
# 阶段2: runtime - 最终运行环境
#

# ============================================
# 阶段1: Builder - 下载和解压工具链
# ============================================
FROM ubuntu:24.04 AS builder

ARG TOOLCHAIN_VERSION=15.2.rel1
ARG TOOLCHAIN_URL=https://developer.arm.com/-/media/Files/downloads/gnu/${TOOLCHAIN_VERSION}/binrel/arm-gnu-toolchain-${TOOLCHAIN_VERSION}-x86_64-arm-none-linux-gnueabihf.tar.xz
ARG VERBOSE=0

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    xz-utils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN if [ "$VERBOSE" = "1" ]; then \
        wget -v ${TOOLCHAIN_URL} -O toolchain.tar.xz; \
    else \
        wget --progress=bar:force:noscroll ${TOOLCHAIN_URL} -O toolchain.tar.xz; \
    fi \
    && tar -xf toolchain.tar.xz \
    && mv arm-gnu-toolchain-${TOOLCHAIN_VERSION}-x86_64-arm-none-linux-gnueabihf /opt/arm-gnu-toolchain \
    && rm toolchain.tar.xz \
    && rm -rf /opt/arm-gnu-toolchain/share/doc

# ============================================
# 阶段2: Runtime - 最终运行环境
# ============================================
FROM ubuntu:24.04

LABEL maintainer="IMX-Forge Team"
LABEL description="i.MX6ULL 嵌入式 Linux 开发环境"
LABEL version="1.0"

ARG USER_NAME=ubuntu
ARG USER_ID=1000
ARG GROUP_ID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    bc \
    bison \
    flex \
    device-tree-compiler \
    python3 \
    python3-pyelftools \
    swig \
    libssl-dev \
    libgnutls28-dev \
    libncurses-dev \
    git \
    make \
    cmake \
    ninja-build \
    meson \
    cpio \
    rsync \
    file \
    u-boot-tools \
    picocom \
    imagemagick \
    libts-dev \
    libpulse-dev \
    libasound2-dev \
    wget \
    curl \
    ca-certificates \
    ccache \
    unzip \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

COPY --from=builder /opt/arm-gnu-toolchain /opt/arm-gnu-toolchain

ENV PATH="/opt/arm-gnu-toolchain/bin:${PATH}"
ENV CROSS_COMPILE=arm-none-linux-gnueabihf-
ENV ARCH=arm

# 使用 ubuntu 用户（基础镜像已存在），无需创建
RUN chown -R ${USER_NAME}:${USER_NAME} /workspace

RUN echo '#!/bin/bash\n\
set -e\n\
echo "========================================"\n\
echo "  IMX-Forge 开发环境"\n\
echo "========================================"\n\
echo ""\n\
echo "工具链版本: $(arm-none-linux-gnueabihf-gcc --version | head -1)"\n\
echo "工作目录: $(pwd)"\n\
echo ""\n\
echo "快速开始:"\n\
echo "  ./scripts/build_helper/build-uboot.sh      # 编译 U-Boot"\n\
echo "  ./scripts/build_helper/build-linux.sh      # 编译 Linux 内核"\n\
echo "  ./scripts/build_helper/build-busybox.sh    # 编译 BusyBox"\n\
echo "  ./scripts/release-all.sh                   # 一键构建所有组件"\n\
echo ""\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

USER ${USER_NAME}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
