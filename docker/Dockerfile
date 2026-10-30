FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG SDK_COMMIT=824b817f889c2cbff1d48fcdb18ab494a68f69d1

ENV TZ=Etc/UTC
ENV A_EYE_SDK_DIR=/opt/luckfox-pico

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf \
        bc \
        bison \
        build-essential \
        cpio \
        device-tree-compiler \
        expect \
        fakeroot \
        file \
        flex \
        gawk \
        gcc-multilib \
        g++-multilib \
        git \
        gperf \
        lib32ncurses-dev \
        lib32z1-dev \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        lzop \
        make \
        openssh-client \
        pkg-config \
        python-is-python3 \
        rsync \
        texinfo \
        unzip \
        wget \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pin the vendor SDK to the same source revision used by this project. The
# SDK lives in the image as a clean seed; Compose mounts a writable named
# volume over it when building firmware.
RUN git init /opt/luckfox-pico \
    && git -C /opt/luckfox-pico remote add origin https://github.com/LuckfoxTECH/luckfox-pico.git \
    && git -C /opt/luckfox-pico fetch --depth=1 origin "${SDK_COMMIT}" \
    && git -C /opt/luckfox-pico checkout --detach FETCH_HEAD \
    && rm -rf /opt/luckfox-pico/.git \
    && ln -s project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk \
        /opt/luckfox-pico/.BoardConfig.mk

COPY entrypoint.sh /usr/local/bin/a-eye-build
RUN chmod 0755 /usr/local/bin/a-eye-build

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/a-eye-build"]
