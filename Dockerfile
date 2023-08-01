FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    git \
    gcc \
    make \
    openssh-client \
    openssh-server \
    rsync \
    inotify-tools \
    dnsutils \
    bash \
    && git clone https://github.com/Yelp/dumb-init.git \
    && cd dumb-init \
    && make \
    && cp dumb-init /usr/bin/ \
    && cd .. \
    && rm -rf dumb-init \
    && rm -rf /var/lib/apt/lists/* # Clean up to reduce the size of the image

COPY entryPoint.sh /entryPoint.sh
COPY sshd_config /sshd_config
RUN chmod +x /entryPoint.sh

ENTRYPOINT ["/usr/bin/dumb-it","/entryPoint.sh"]
