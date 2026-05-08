FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV ALLOWED_GROUP_PORTS="1:5001 2:5002 3:5003 4:5004"
ENV MITIGATION_SOCKET=/run/workshop-mitigation/mitigation.sock

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        iptables \
        socat \
    && rm -rf /var/lib/apt/lists/*

COPY mitigation-helper/dispatch.sh /usr/local/bin/workshop-mitigation-dispatch
COPY mitigation-helper/entrypoint.sh /usr/local/bin/workshop-mitigation-entrypoint

RUN chmod 0755 /usr/local/bin/workshop-mitigation-dispatch /usr/local/bin/workshop-mitigation-entrypoint

ENTRYPOINT ["/usr/local/bin/workshop-mitigation-entrypoint"]
