FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS ffmpeg-build

ARG fdk_aac_version=v2.0.3

ENV DEBIAN_FRONTEND=noninteractive

ENV DEV="make gcc git g++ automake curl wget autoconf build-essential libass-dev libfreetype6-dev libsdl1.2-dev libtheora-dev libtool libva-dev libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev pkg-config texinfo zlib1g-dev"
ENV FFMPEG_VERSION=7.0.2

RUN apt-get update && \
    apt-get -y install $DEV && \
    apt-get -y install yasm libx264-dev libmp3lame-dev libopus-dev libvpx-dev libfdk-aac-dev && \
    apt-get -y install libx265-dev libnuma-dev && \
    apt-get -y install libasound2 libass9 libvdpau1 libva-x11-2 libva-drm2 libxcb-shm0 libxcb-xfixes0 libxcb-shape0 libvorbisenc2 libtheora0 libaribb24-dev

#nvenc build
RUN GIT_SSL_NO_VERIFY=1 \
    git clone --branch master --depth 1 https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && make install && cd .. && \
    rm -rf nv-codec-headers

#ffmpeg build
WORKDIR /tmp/ffmpeg_sources
RUN curl -fsSL http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz | tar -xJ --strip-components=1
    # sed -i -e 's/$nvccflags -ptx/$nvccflags/g' ./configure && \
RUN ./configure \
    --prefix=/ffmpeg \
    --disable-shared \
    --pkg-config-flags=--static \
    --enable-gpl \
    --enable-libass \
    --enable-libfdk-aac \
    --enable-libfreetype \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libx265 \
    --enable-version3 \
    --enable-libaribb24 \
    --enable-nonfree \
    --disable-debug \
    --disable-doc \
    # CUDA Toolkit
    --enable-cuda-nvcc \
    --extra-cflags="-I/usr/local/cuda/include" \
    --extra-ldflags="-L/usr/local/cuda/lib64" \
    --enable-nvenc \
    # CC指定フラグ追加 (https://github.com/NVIDIA/cuda-samples/issues/46#issuecomment-863835984 より)
    #   --nvccflags="${CUDA_OPTION}" \
    && \
    make -j$(nproc) && \
    make install

# 不要なパッケージを削除
RUN apt-get -y remove $DEV && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV NODE_VERSION=20
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNTIME="libasound2 libass9 libvdpau1 libva-x11-2 libva-drm2 libxcb-shm0 libxcb-xfixes0 libxcb-shape0 libvorbisenc2 libtheora0 libx264-dev libx265-dev libmp3lame0 libopus0 libvpx-dev libfdk-aac-dev libaribb24-0"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y wget gcc g++ make && \
    wget https://deb.nodesource.com/setup_${NODE_VERSION}.x -O - | bash - && \
    apt-get -y install nodejs && \
    apt-get install -y $RUNTIME && \
    apt-get purge -y wget gcc g++ make

COPY --from=l3tnun/epgstation:master-debian /app /app/
COPY --from=l3tnun/epgstation:master-debian /app/client /app/client/
COPY --from=ffmpeg-build /ffmpeg /usr/local/
COPY config/ /app/config
RUN chmod 444 /app/src -R

# dry run
RUN ffmpeg -codecs

EXPOSE 8888
WORKDIR /app
ENTRYPOINT ["npm"]
CMD ["start"]
