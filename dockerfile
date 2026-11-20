# ScopeSentry-Scan: multi-stage build that compiles the binary from source, so
# it works from a plain checkout or a git-URL build context (no dist/ needed).
# linux/amd64 only, because tools/linux/* are amd64 binaries:
#   docker build --platform linux/amd64 -f dockerfile -t scopesentry-scan .

ARG GO_VERSION=1.24

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS builder
ARG TARGETOS
ARG TARGETARCH
RUN if [ "${TARGETOS}/${TARGETARCH}" != "linux/amd64" ]; then \
      echo "ScopeSentry-Scan must be built for linux/amd64 (tools/linux/* are amd64 binaries): use --platform linux/amd64" >&2; \
      exit 1; \
    fi
WORKDIR /src
# Whole repo: go.mod has replace directives pointing at ./libs/*.
COPY . .
# CGO is not needed: with CGO_ENABLED=0, pebble and go-rpmutils use their pure-Go
# code paths instead of DataDog/zstd, so this cross-compiles without emulation.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags "-s -w" -o /out/ScopeSentry-Scan ./cmd/ScopeSentry/main.go

FROM python:3.7-slim

WORKDIR /apps
COPY msyh.ttc /usr/share/fonts/

# 更新软件包列表并安装必要的软件包
RUN apt-get update && apt-get install -y \
    libexif-dev \
    udev \
    chromium \
    vim \
    tzdata \
    libpcap-dev \
    default-jdk \
    && rm -rf /var/lib/apt/lists/*

#    tini \
# 设置 tini 作为 init 进程（PID 1）
# ENTRYPOINT ["/usr/bin/tini", "--"]


RUN pip install uro
# 拷贝构建阶段编译好的可执行文件到容器中
COPY --from=builder /out/ScopeSentry-Scan /apps/ScopeSentry-Scan
RUN chmod +x /apps/ScopeSentry-Scan
RUN mkdir /apps/ext
RUN mkdir /apps/ext/rad
RUN mkdir /apps/ext/ksubdomain
RUN mkdir /apps/ext/rustscan
RUN mkdir /apps/ext/katana

COPY tools/linux/ksubdomain /apps/ext/ksubdomain/ksubdomain
RUN chmod +x /apps/ext/ksubdomain/ksubdomain
COPY tools/linux/rad /apps/ext/rad/rad
RUN chmod +x /apps/ext/rad/rad
COPY tools/linux/rustscan /apps/ext/rustscan/rustscan
RUN chmod +x /apps/ext/rustscan/rustscan

COPY tools/linux/katana /apps/ext/katana/katana
RUN chmod +x /apps/ext/katana/katana
# 设置时区为上海
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
RUN echo 'Asia/Shanghai' >/etc/timezone

# 设置编码
ENV LANG=C.UTF-8

# 运行golang程序的命令
ENTRYPOINT ["/apps/ScopeSentry-Scan"]
