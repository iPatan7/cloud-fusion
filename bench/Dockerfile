# Container baseline for the benchmarks: the same Debian 13 user space and OpenSSL
# build as the VMs, but running directly on the host kernel (OS-level virtualisation).
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*
COPY cpu-disk.sh /cpu-disk.sh
ENTRYPOINT ["sh", "/cpu-disk.sh"]
