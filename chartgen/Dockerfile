FROM alpine:3.19

# Install all required build + Postgres client libraries
RUN apk update && apk add --no-cache \
    gcc \
    g++ \
    make \
    musl-dev \
    postgresql-dev \
    openssl-dev \
    zlib-dev \
    libxml2-dev \
    lz4-dev \
    zstd-dev

WORKDIR /app

COPY main.c .

# Add both include and lib paths explicitly (important on Alpine ARM)
RUN gcc main.c \
    -I/usr/include/postgresql \
    -L/usr/lib \
    -lpq \
    -o chartgen \
    -v

CMD ["./chartgen"]