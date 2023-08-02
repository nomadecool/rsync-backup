FROM alpine:3

RUN apk -U update
RUN apk add --no-cache dumb-init openssh-client openssh-server rsync inotify-tools bind-tools bash

ADD entryPoint.sh /entryPoint.sh
ADD sshd_config /

ENTRYPOINT ["dumb-init", "/entryPoint.sh"]

