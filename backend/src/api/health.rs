use axum::{Json, extract::State};
use sqlx::PgPool;
use serde::Serialize;

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
}

#[derive(Serialize)]
pub struct StatsResponse {
    pub proposition_count: i64,
}

/// GET /health — ヘルスチェック
pub async fn health_check() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
    })
}

/// GET /api/stats — 基本統計情報
pub async fn stats(State(pool): State<PgPool>) -> Json<StatsResponse> {
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM propositions")
        .fetch_one(&pool)
        .await
        .unwrap_or((0,));

    Json(StatsResponse {
        proposition_count: count.0,
    })
}
