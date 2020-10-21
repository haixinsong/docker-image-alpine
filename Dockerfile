FROM alpine as builder

ENV MIRRORS=https://mirrors.aliyun.com/alpine \
    ARCH=x86_64 \
    TZ=Asia/Shanghai

ENV MAJOR_VERSION=3.12 \
    MINOR_VERSION=1

RUN sed -i "s#http://dl-cdn.alpinelinux.org/alpine#${MIRRORS}#g" /etc/apk/repositories && \
    apk add --no-cache ca-certificates tzdata && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

RUN wget ${MIRRORS}/v${MAJOR_VERSION}/releases/${ARCH}/alpine-minirootfs-${MAJOR_VERSION}.${MINOR_VERSION}-${ARCH}.tar.gz && \
    mkdir alpine-minirootfs && \
    tar -zxf alpine-minirootfs-${MAJOR_VERSION}.${MINOR_VERSION}-${ARCH}.tar.gz -C alpine-minirootfs && \
    # copy time conf (Asia/Shanghai)
    cp /etc/localtime /alpine-minirootfs/etc/ && \
    cp /etc/timezone /alpine-minirootfs/etc/ && \
    # change repositories mirrors and add edge repositories
    sed -i "s#http://dl-cdn.alpinelinux.org/alpine#${MIRRORS}#g" /alpine-minirootfs/etc/apk/repositories

# ---------------------------------------------------------------------------------------------------------

FROM scratch

COPY --from=builder /alpine-minirootfs /

CMD ["/bin/sh"]

# docker build . --no-cache -t nediiii/alpine:3.12 -t nediiii/alpine:3.12.1
