FROM debian:stable-slim
RUN apt-get update && apt-get install -y \
    inotify-tools \
    openssh-server \
    rsync \
    && rm -rf /var/lib/apt/lists/* # bajamos el peso de la imagen de nuevo

COPY entryPoint.sh /entryPoint.sh
RUN chmod +x /entryPoint.sh

ENTRYPOINT ["/entryPoint.sh"]
