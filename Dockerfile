FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble

RUN apt update && apt install -y --no-install-recommends \
    curl \
    aria2 \
    ca-certificates \
    unzip \
    p7zip-full \
    vim \
    cron \
    exiftool \
    jq \
    dos2unix

ARG SPT_VERSION=4.1.3-40743-ddce41c
ARG FIKA_VERSION=2.4.0
ENV SPT_VERSION=$SPT_VERSION
ENV FIKA_VERSION=$FIKA_VERSION

WORKDIR /opt/build
RUN curl -sL "https://mirror.sp-tushonka.com/releases/SPT-${SPT_VERSION}.7z" -o spt.7z
RUN 7z x spt.7z

COPY entrypoint.sh /usr/bin/entrypoint
COPY scripts/backup.sh /usr/bin/backup
COPY scripts/install_mods.sh /usr/bin/install_mods
COPY data/cron/cron_backup_spt /etc/cron.d/cron_backup_spt
RUN dos2unix /usr/bin/entrypoint /usr/bin/backup /usr/bin/install_mods /etc/cron.d/cron_backup_spt && \
    chmod +x /usr/bin/entrypoint /usr/bin/backup /usr/bin/install_mods /etc/cron.d/cron_backup_spt

# Docker desktop doesn't allow you to configure port mappings unless this is present
EXPOSE 6969
ENTRYPOINT ["/usr/bin/entrypoint"]
