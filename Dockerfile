FROM alpine

RUN apk add --no-cache inotify-tools openssh rsync

COPY entryPoint.sh /entryPoint.sh
RUN chmod +x /entryPoint.sh

ENTRYPOINT ["/entryPoint.sh"]
