# ビルドステージ
FROM rust:1-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY src/ src/
COPY migrations/ migrations/
ENV SQLX_OFFLINE=true
RUN cargo build --release

# 実行ステージ
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/kg-backend /usr/local/bin/
EXPOSE 8080
CMD ["kg-backend"]
