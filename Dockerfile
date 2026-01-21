# OpenSSL zlib DSO init bug PoC
# This demonstrates the bug where COMP_zlib_oneshot() returns a method
# even when zlib DSO fails to load, causing NULL pointer dereference.

FROM ubuntu:24.04 AS builder

# Install build dependencies including zlib headers
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    ca-certificates \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and apply the fix if FIX=1 (passed as build arg)
ARG FIX=0
ARG OPENSSL_VERSION=openssl-3.6.0

WORKDIR /tmp

# Download and extract OpenSSL
RUN wget -q https://github.com/openssl/openssl/releases/download/${OPENSSL_VERSION}/${OPENSSL_VERSION}.tar.gz && \
    tar xzf ${OPENSSL_VERSION}.tar.gz && \
    mv ${OPENSSL_VERSION} openssl

# Apply the fix if requested
COPY fix.patch /tmp/
RUN if [ "$FIX" = "1" ]; then \
      cd /tmp/openssl && patch -p1 < /tmp/fix.patch; \
    fi

# Configure with zlib-dynamic - this sets ZLIB_SHARED
# which means zlib is loaded via DSO at runtime
RUN cd /tmp/openssl && \
    ./Configure --prefix=/usr/local/openssl \
        enable-zlib zlib-dynamic \
        shared -g -O2 && \
    make -j$(nproc) && \
    make install

# Copy test program
COPY test_zlib_init.c /tmp/

# Compile test program
RUN gcc -g -O0 -o /tmp/test_zlib_init /tmp/test_zlib_init.c \
    -I/usr/local/openssl/include \
    -L/usr/local/openssl/lib64 \
    -Wl,-rpath,/usr/local/openssl/lib64 \
    -lssl -lcrypto

# Runtime image - deliberately WITHOUT zlib installed
# This causes DSO_load() to fail when OpenSSL tries to load libz.so
FROM ubuntu:24.04

# Copy OpenSSL - but NOT zlib library!
COPY --from=builder /usr/local/openssl /usr/local/openssl
COPY --from=builder /tmp/test_zlib_init /test_zlib_init

# Configure library path
RUN echo "/usr/local/openssl/lib64" > /etc/ld.so.conf.d/openssl.conf && ldconfig

# Copy run script
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
