FROM debian:13-slim AS xray
ARG XRAY_VERSION=CHANGE_ME
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip ca-certificates \
 && A=$(uname -m | sed 's/x86_64/64/;s/aarch64/arm64-v8a/') \
 && curl -fsSL -o /x.zip https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${A}.zip \
 && unzip /x.zip xray -d /out

FROM debian:13-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends openvpn iproute2 iptables \
 && rm -rf /var/lib/apt/lists/*
COPY --from=xray /out/xray /usr/local/bin/xray
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
