FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV ANALYST_USER=analyst
ENV ANALYST_PASSWORD=analyst123
ENV GROUP_NAME="Workshop Group"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        curl \
        grep \
        iproute2 \
        less \
        nano \
        net-tools \
        openssh-server \
        procps \
        socat \
        sudo \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd /logs /opt/workshop /etc/ssh/sshd_config.d \
    && chmod 755 /logs \
    && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?UsePAM .*/UsePAM no/' /etc/ssh/sshd_config \
    && printf '%s\n' \
        'PrintMotd yes' \
        'Banner /etc/workshop-banner' \
        'X11Forwarding no' \
        'AllowTcpForwarding no' \
        > /etc/ssh/sshd_config.d/workshop.conf

COPY entrypoint.sh /usr/local/bin/analyst-entrypoint.sh
COPY workshop-mitigation-client.sh /usr/local/bin/workshop-block-ip
COPY workshop-mitigation-client.sh /usr/local/bin/workshop-unblock-ip
COPY workshop-mitigation-client.sh /usr/local/bin/workshop-list-blocked
COPY README-WORKSHOP.md /opt/workshop/README-WORKSHOP.md
COPY banner.txt /etc/workshop-banner

RUN chmod 0755 \
        /usr/local/bin/analyst-entrypoint.sh \
        /usr/local/bin/workshop-block-ip \
        /usr/local/bin/workshop-unblock-ip \
        /usr/local/bin/workshop-list-blocked

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/analyst-entrypoint.sh"]
