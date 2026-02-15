use axum::{Router, routing::get};
use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use tower_http::cors::CorsLayer;
use tracing_subscriber::EnvFilter;
use std::str::FromStr;

mod api;

#[tokio::main]
async fn main() {
    // .envファイルの読み込み
    dotenvy::dotenv().ok();

    // ロギングの初期化
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    // DB接続プールの作成
    let connect_options = PgConnectOptions::new()
        .host("127.0.0.1")
        .port(5433)
        .database("knowledge_graph")
        .username("app")
        .password(&std::env::var("DB_PASSWORD").expect("DB_PASSWORD must be set"))
        .ssl_mode(PgSslMode::Disable);
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect_with(connect_options)
        .await
        .expect("Failed to connect to database");

    // マイグレーションの自動実行
    sqlx::migrate!()
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    // ルーターの構築
    let app = Router::new()
        .route("/health", get(api::health::health_check))
        .route("/api/stats", get(api::health::stats))
        .layer(CorsLayer::permissive())
        .with_state(pool);

    // サーバーの起動
    let port = std::env::var("BACKEND_PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{}", port);
    tracing::info!("Starting server on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("Failed to bind address");
    axum::serve(listener, app)
        .await
        .expect("Server error");
}
