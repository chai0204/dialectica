# 人類の総合知グラフプラットフォーム — 開発環境整備ガイド

> **対象読者**: プログラミングの理論はわかるが、環境構築の具体的な手順に不慣れな開発者
> **前提OS**: Windows（WSL2経由）、macOS、または Linux
> **最終更新**: 2026-02-16

---

## 目次

1. [全体像と着手順序](#1-全体像と着手順序)
2. [前提ツールのインストール](#2-前提ツールのインストール)
3. [Git・GitHubの設定](#3-gitgithubの設定)
4. [リポジトリの初期構築](#4-リポジトリの初期構築)
5. [Docker Compose環境の構築](#5-docker-compose環境の構築)
6. [PostgreSQL + pgvectorの初期化](#6-postgresql--pgvectorの初期化)
7. [Rustバックエンドの構築](#7-rustバックエンドの構築)
8. [フロントエンドの構築](#8-フロントエンドの構築)
9. [AIエージェント環境の構築](#9-aiエージェント環境の構築)
10. [Claude Code（AI駆動開発）の設定](#10-claude-codeai駆動開発の設定)
11. [開発ワークフロー](#11-開発ワークフロー)
12. [GitHub Actionsの設定](#12-github-actionsの設定)
13. [トラブルシューティング](#13-トラブルシューティング)

---

## 1. 全体像と着手順序

### 構成要素の依存関係

```
CLAUDE.md の作成（最初にやる）
    ↓
Git / GitHub リポジトリの初期化
    ↓
Docker Compose で PostgreSQL + pgvector を起動
    ↓
マイグレーション（core_schema.sql の適用）
    ↓
Rust バックエンド（Axum + SQLx）の雛形作成
    ↓
フロントエンド（Vite + React + TS）の雛形作成
    ↓
AIエージェント（Python）の雛形作成
    ↓
GitHub Actions の設定
```

### 推奨着手順序

| ステップ | 内容 | 所要時間目安 |
|---------|------|-------------|
| Step 1 | 前提ツールのインストール | 30分-1時間 |
| Step 2 | Git/GitHub設定 + リポジトリ作成 | 15分 |
| Step 3 | Docker ComposeでDB起動 + マイグレーション | 30分 |
| Step 4 | Rustバックエンドの雛形 | 1-2時間 |
| Step 5 | フロントエンドの雛形 | 30分 |
| Step 6 | AIエージェント環境 | 30分 |
| Step 7 | Claude Code設定 + CLAUDE.md | 30分 |
| Step 8 | GitHub Actions | 30分 |

Step 4以降はClaude Codeに大部分を委任可能。

---

## 2. 前提ツールのインストール

### 2.0 Windows の場合: WSL2 のセットアップ

Windows環境では、全ての開発作業をWSL2（Windows Subsystem for Linux 2）上で行う。

```powershell
# PowerShell（管理者として実行）で以下を実行
wsl --install
# 再起動後、Ubuntu が自動的にインストールされる

# インストール確認
wsl --version
# WSL バージョン: 2.x.x 以上
```

以降のコマンドは全て **WSL2のUbuntuターミナル内** で実行する。
Windows TerminalからWSLタブを開くか、スタートメニューから「Ubuntu」を起動する。

> **重要**: プロジェクトのファイルはWSL2のファイルシステム内（`~/` 以下）に配置すること。
> Windows側のパス（`/mnt/c/...`）に配置するとファイルI/Oが著しく遅くなる。

Docker Desktop for Windowsをインストールし、Settings → Resources → WSL Integration で使用するWSLディストリビューションを有効にする。

### 2.1 Docker Desktop

Docker Composeを使ってPostgreSQLとバックエンドをコンテナで動かす。

```bash
# macOS（Homebrew経由）
brew install --cask docker

# Linux / WSL2（Ubuntu/Debian）
# 公式手順: https://docs.docker.com/engine/install/ubuntu/
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Windowsの場合はDocker Desktop for Windowsをインストール済みなら
# WSL2内で自動的にdockerコマンドが使える

# インストール確認
docker --version          # Docker version 27.x.x 以上
docker compose version    # Docker Compose version v2.x.x 以上
```

Docker Desktopを起動しておくこと（macOS / Windowsの場合）。
Linuxの場合は `sudo systemctl start docker` でデーモンを起動。

### 2.2 Rust

```bash
# rustup（Rust公式のバージョン管理ツール）をインストール
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# シェルの再読み込み（または新しいターミナルを開く）
source $HOME/.cargo/env

# インストール確認
rustc --version     # rustc 1.8x.x 以上
cargo --version     # cargo 1.8x.x 以上

# 開発に便利なコンポーネントを追加
rustup component add clippy      # リンター
rustup component add rustfmt     # フォーマッター
```

### 2.3 Node.js

```bash
# fnm（高速なNode.jsバージョン管理）を推奨
# macOS
brew install fnm

# Linux
curl -fsSL https://fnm.vercel.app/install | bash

# Node.js LTS版をインストール
fnm install --lts
fnm use lts-latest

# インストール確認
node --version    # v22.x.x 以上
npm --version     # 10.x.x 以上
```

### 2.4 Python

```bash
# macOS（Homebrew経由）
brew install python@3.12

# Linux（Ubuntu/Debian）
sudo apt-get install python3.12 python3.12-venv python3-pip

# インストール確認
python3 --version    # Python 3.12.x 以上
```

### 2.5 Git

```bash
# macOS（通常プリインストール済み。なければ:）
brew install git

# Linux（Ubuntu/Debian）
sudo apt-get install git

# インストール確認
git --version    # git version 2.x.x
```

### 2.6 Claude Code

```bash
# Node.js がインストール済みであること
npm install -g @anthropic-ai/claude-code

# インストール確認
claude --version

# 初回起動時にAnthropicアカウントでの認証が必要
claude
```

### 2.7 SQLx CLI（Rustマイグレーション用）

```bash
# SQLx CLIをインストール（PostgreSQL機能のみ）
cargo install sqlx-cli --no-default-features --features rustls,postgres

# インストール確認
sqlx --version
```

### 2.8 cargo-watch（ホットリロード用）

```bash
# ファイル変更時に自動でコンパイル・再起動するツール
cargo install cargo-watch

# インストール確認
cargo watch --version
```

Rust開発ではコードを変更するたびに再コンパイルが必要。
`cargo watch -x run` でファイル保存時に自動再起動できるため、開発効率が大幅に向上する。

---

## 3. Git・GitHubの設定

### 3.1 Gitの初期設定

```bash
# ユーザー情報の設定（コミットに記録される）
git config --global user.name "あなたの名前"
git config --global user.email "your-email@example.com"

# デフォルトブランチ名をmainに
git config --global init.defaultBranch main

# 改行コードの自動変換（macOS/Linux）
git config --global core.autocrlf input

# 日本語ファイル名の文字化け防止
git config --global core.quotepath false
```

### 3.2 SSH鍵の設定（GitHub認証用）

```bash
# SSH鍵の生成（既に持っていればスキップ）
ssh-keygen -t ed25519 -C "your-email@example.com"
# Enterを3回押す（デフォルトパスでパスフレーズなし、またはパスフレーズを設定）

# 公開鍵の内容をクリップボードにコピー
# macOS:
cat ~/.ssh/id_ed25519.pub | pbcopy
# Linux:
cat ~/.ssh/id_ed25519.pub
# （表示された内容を手動でコピー）
```

GitHubの設定画面（https://github.com/settings/keys）で「New SSH key」をクリックし、コピーした公開鍵を貼り付けて保存。

```bash
# 接続テスト
ssh -T git@github.com
# "Hi username! You've successfully authenticated" と表示されればOK
```

### 3.3 GitHubリポジトリの作成

1. https://github.com/new にアクセス
2. Repository name: `knowledge-graph-platform`（任意）
3. Description: 人類の総合知グラフプラットフォーム
4. **Public** を選択（オープンソース）
5. Add .gitignore: **None**（後で自作する）
6. Add a license: **GNU Affero General Public License v3.0**
7. 「Create repository」をクリック

---

## 4. リポジトリの初期構築

### 4.1 ローカルにクローン＆ディレクトリ構造の作成

```bash
# リポジトリをクローン
git clone git@github.com:YOUR_USERNAME/knowledge-graph-platform.git
cd knowledge-graph-platform

# ディレクトリ構造を作成
mkdir -p backend/src/{api,db,models,computation}
mkdir -p backend/migrations
mkdir -p backend/tests
mkdir -p frontend/src/{components/{graph,proposition,interpretation,fragility},api,stores,types,styles,hooks}
mkdir -p db
mkdir -p agents/prompts
mkdir -p docs/diagrams
mkdir -p scripts/seed_data
```

### 4.2 .gitignore の作成

```bash
cat > .gitignore << 'EOF'
# ===== Rust =====
backend/target/
**/*.rs.bk

# ===== Node.js =====
frontend/node_modules/
frontend/dist/

# ===== Python =====
agents/__pycache__/
agents/.venv/
agents/*.pyc

# ===== Docker =====
pgdata/

# ===== Environment =====
.env
.env.local
.env.production

# ===== IDE =====
.vscode/
.idea/
*.swp
*.swo
*~

# ===== OS =====
.DS_Store
Thumbs.db

# ===== Logs =====
*.log

# ===== Seed data output =====
agents/output/
scripts/seed_data/*.json
EOF
```

### 4.3 .env ファイルの作成（gitignore対象）

```bash
cat > .env << 'EOF'
# Database
DB_PASSWORD=dev_password_change_in_production
DATABASE_URL=postgres://app:dev_password_change_in_production@localhost:5432/knowledge_graph

# Backend
BACKEND_PORT=8080
RUST_LOG=info

# Batch API
BATCH_API_KEY=dev_batch_key_change_in_production

# AI Agents (必要に応じて設定)
GEMINI_API_KEY=your_gemini_api_key_here
EOF
```

### 4.4 .env.example の作成（gitに含める。他の開発者向け）

```bash
cat > .env.example << 'EOF'
# Database
DB_PASSWORD=dev_password_change_in_production
DATABASE_URL=postgres://app:dev_password_change_in_production@localhost:5432/knowledge_graph

# Backend
BACKEND_PORT=8080
RUST_LOG=info

# Batch API
BATCH_API_KEY=

# AI Agents
GEMINI_API_KEY=
EOF
```

### 4.5 初回コミット

```bash
git add .
git commit -m "初期ディレクトリ構造と設定ファイルの作成"
git push origin main
```

---

## 5. Docker Compose環境の構築

### 5.1 DBコンテナ用Dockerfileの作成

pgvectorとPGroonga（日本語全文検索）の両方が必要なため、自前のDockerfileを用意する。

```bash
mkdir -p db
cat > db/Dockerfile << 'EOF'
FROM pgvector/pgvector:pg16

# PGroonga（日本語全文検索）のインストール
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      software-properties-common \
      gnupg \
      wget && \
    # Groonga公式APTリポジトリの追加
    wget -q -O /tmp/groonga.deb https://packages.groonga.org/debian/groonga-apt-source-latest-bookworm.deb && \
    dpkg -i /tmp/groonga.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-16-pgdg-pgroonga && \
    rm -rf /var/lib/apt/lists/* /tmp/*
EOF
```

> **注意**: Groonga公式リポジトリの構成は変更される可能性がある。
> インストールに失敗した場合は https://pgroonga.github.io/install/ を参照。

### 5.2 docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
services:
  db:
    build: ./db
    container_name: kg-db
    restart: unless-stopped
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: knowledge_graph
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d knowledge_graph"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
EOF
```

### 5.3 開発用オーバーライド

```bash
cat > docker-compose.dev.yml << 'EOF'
# 開発時のみの追加設定
# 使用: docker compose -f docker-compose.yml -f docker-compose.dev.yml up
services:
  db:
    ports:
      - "5432:5432"
    # ログレベルを上げる（開発時のみ）
    command: postgres -c log_statement=all -c log_min_duration_statement=100
EOF
```

### 5.4 DBの起動と確認

```bash
# .envファイルを読み込んでDBをビルド＆起動
docker compose up -d --build db

# 起動確認（healthyになるまで待つ）
docker compose ps
# kg-db が "healthy" と表示されればOK

# DBに接続テスト
docker compose exec db psql -U app -d knowledge_graph -c "SELECT version();"
# PostgreSQL 16.x が表示されればOK

# pgvectorの確認
docker compose exec db psql -U app -d knowledge_graph -c "CREATE EXTENSION IF NOT EXISTS vector; SELECT extversion FROM pg_extension WHERE extname = 'vector';"
# 0.7.x 以上が表示されればOK

# PGroongaの確認
docker compose exec db psql -U app -d knowledge_graph -c "CREATE EXTENSION IF NOT EXISTS pgroonga; SELECT extversion FROM pg_extension WHERE extname = 'pgroonga';"
# バージョンが表示されればOK
```

---

## 6. PostgreSQL + pgvectorの初期化

### 6.1 マイグレーションファイルの配置

プロジェクトの `core_schema.sql` をSQLxのマイグレーション形式で配置する。

```bash
# マイグレーションディレクトリにコピー（ファイル名の形式が重要）
cp docs/core_schema.sql backend/migrations/001_initial_schema.sql
```

SQLxのマイグレーションファイル名は `{番号}_{説明}.sql` の形式。
番号は実行順序を決める（辞書順）。

### 6.2 マイグレーションの実行

```bash
# backend ディレクトリに移動
cd backend

# SQLx CLIでマイグレーションを実行
# DATABASE_URLは.envから読み込まれる（または直接指定）
sqlx migrate run --database-url "postgres://app:dev_password_change_in_production@localhost:5432/knowledge_graph"

# 実行確認: テーブル一覧を表示
docker compose exec db psql -U app -d knowledge_graph -c "\dt"
```

以下のテーブルが表示されれば成功:

```
propositions, relations, relation_members,
interpretations, interpretation_premises, interpretation_rebuttals,
frames, frame_roles, frame_bindings,
contexts, proposition_contexts,
equivalence_groups, equivalence_members,
interpretation_embeddings, proposition_embeddings,
interpretation_clusters, interpretation_cluster_members,
perspectives, interpretation_perspectives, interpretation_blind_spots,
interpretation_tags,
plausibility_cache, relation_confidence_cache, system_parameters,
ai_suggestions, ai_generation_metadata,
revision_history, cascade_events, cascade_impacts, proposition_closure,
users
```

### 6.3 計算関数の確認

```bash
# 計算関数が正しく作成されたか確認
docker compose exec db psql -U app -d knowledge_graph -c "\df compute_*"
# compute_structural_soundness_v2, compute_refutation_resilience,
# compute_interpretation_reliability, compute_plausibility_final,
# compute_fragility が表示されればOK
```

---

## 7. Rustバックエンドの構築

### 7.1 Cargoプロジェクトの初期化

```bash
cd backend

# Cargo.tomlを作成（既存ディレクトリ内で初期化）
cargo init --name kg-backend .
```

### 7.2 Cargo.toml の設定

`backend/Cargo.toml` を以下の内容に編集する。
（ここからはClaude Codeに依頼してもよい）

```toml
[package]
name = "kg-backend"
version = "0.1.0"
edition = "2024"

[dependencies]
# Web framework
axum = { version = "0.8", features = ["macros"] }
tokio = { version = "1", features = ["full"] }
tower = "0.5"
tower-http = { version = "0.6", features = ["cors", "trace"] }

# Database
sqlx = { version = "0.8", features = [
    "runtime-tokio-rustls",
    "postgres",
    "uuid",
    "chrono",
    "json",
    "migrate"
] }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Types
uuid = { version = "1", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }

# Error handling
anyhow = "1"
thiserror = "2"

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Config
dotenvy = "0.15"

# Validation
validator = { version = "0.19", features = ["derive"] }

[dev-dependencies]
tokio = { version = "1", features = ["test-util"] }
```

### 7.3 最小限のmain.rsを作成

`backend/src/main.rs`:

```rust
use axum::{routing::get, Json, Router};
use serde_json::{json, Value};
use sqlx::postgres::PgPoolOptions;
use std::net::SocketAddr;
use tower_http::cors::CorsLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // .envファイルの読み込み
    dotenvy::dotenv().ok();

    // ログの初期化
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| "kg_backend=debug,tower_http=debug".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // DB接続プールの作成
    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set");
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;

    tracing::info!("Connected to database");

    // ルーターの構築
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/api/stats", get(get_stats))
        .layer(CorsLayer::permissive())
        .with_state(pool);

    // サーバー起動
    let port: u16 = std::env::var("BACKEND_PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse()?;
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("Backend listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

async fn get_stats(
    axum::extract::State(pool): axum::extract::State<sqlx::PgPool>,
) -> Result<Json<Value>, (axum::http::StatusCode, String)> {
    let row = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM propositions"
    )
    .fetch_one(&pool)
    .await
    .map_err(|e| {
        (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
    })?;

    Ok(Json(json!({
        "proposition_count": row
    })))
}
```

### 7.4 ビルドと起動テスト

```bash
cd backend

# コンパイルチェック（ビルドはせず型チェックのみ。高速）
cargo check

# ビルド（初回は依存クレートのダウンロード+コンパイルで数分かかる）
cargo build

# 起動（DBが起動済みであること）
cargo run

# 別のターミナルで動作確認
curl http://localhost:8080/health
# {"status":"ok"}

curl http://localhost:8080/api/stats
# {"proposition_count":0}
```

### 7.5 バックエンドのDockerfile

`backend/Dockerfile`:

```dockerfile
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
```

---

## 8. フロントエンドの構築

### 8.1 Vite + React + TypeScriptプロジェクトの初期化

```bash
cd frontend

# Viteでプロジェクトを初期化
npm create vite@latest . -- --template react-ts

# 依存パッケージをインストール
npm install

# グラフ可視化・リアルタイム通信
npm install cytoscape react-cytoscapejs
npm install -D @types/cytoscape

# 状態管理
npm install zustand

# UIコンポーネント（ヘッドレスUI、スタイルはCSS Modulesで適用）
npm install @radix-ui/react-dialog @radix-ui/react-tabs

# ルーティング
npm install react-router-dom
```

> **スタイリング方針**: CSS Modulesを採用。Viteが標準でサポートしており追加設定不要。
> コンポーネントのスタイルは `*.module.css` ファイルに記述し、
> Cytoscape.jsのグラフスタイルは `cy.style()` APIでJS内に定義する。

### 8.2 起動テスト

```bash
cd frontend

# 開発サーバー起動
npm run dev
# ブラウザで http://localhost:5173 を開く
# Viteのデフォルト画面が表示されればOK
```

### 8.3 API接続の設定

`frontend/src/api/client.ts` を作成:

```typescript
const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:8080';

export async function fetchStats() {
  const res = await fetch(`${API_BASE}/api/stats`);
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}
```

`frontend/.env.development`:

```
VITE_API_BASE=http://localhost:8080
```

---

## 9. AIエージェント環境の構築

### 9.1 Python仮想環境の設定

```bash
cd agents

# 仮想環境を作成
python3 -m venv .venv

# 仮想環境を有効化
# macOS / Linux:
source .venv/bin/activate
# (プロンプトの先頭に (.venv) が表示される)
```

### 9.2 依存パッケージのインストール

```bash
cat > requirements.txt << 'EOF'
# LLM APIs
google-generativeai>=0.8.0    # Gemini API
ollama>=0.4.0                 # ローカルLLM (Ollama)

# HTTP client
httpx>=0.27.0                 # バッチAPI呼び出し用

# Data processing
pydantic>=2.10.0              # データバリデーション

# Utilities
python-dotenv>=1.0.0          # .env読み込み
tenacity>=9.0.0               # リトライ処理
EOF

pip install -r requirements.txt
```

### 9.3 バッチクライアントの雛形

`agents/batch_client.py`:

```python
"""バッチAPI経由でデータを本番DBに投入するクライアント

バッチAPIはAPIキー認証が必須。
通常の投稿API（1件ずつ）はオープンアクセス。
"""
import httpx
import json
from pathlib import Path


class BatchClient:
    def __init__(self, base_url: str, api_key: str):
        """
        Args:
            base_url: バックエンドのURL
            api_key: バッチAPI認証用のAPIキー（必須）
        """
        self.base_url = base_url.rstrip("/")
        self.headers = {"Authorization": f"Bearer {api_key}"}

    def submit_propositions(self, propositions: list[dict]) -> dict:
        """命題をバッチで投入"""
        res = httpx.post(
            f"{self.base_url}/api/batch/propositions",
            json=propositions,
            headers=self.headers,
            timeout=60.0,
        )
        res.raise_for_status()
        return res.json()

    def save_to_file(self, data: list[dict], path: str):
        """投入データをJSONファイルとして保存（再現性のため）"""
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
```

### 9.4 Ollama のインストール（ローカルLLM用、任意）

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh

# モデルのダウンロード（数GB。必要なときに実行）
ollama pull llama3.1:8b
ollama pull mistral:7b

# 起動確認
ollama list
```

---

## 10. Claude Code（AI駆動開発）の設定

### 10.1 CLAUDE.md の作成

プロジェクトルートに `CLAUDE.md` を作成する。
これはClaude Codeが参照するプロジェクトガイドで、開発効率を大きく左右する重要なファイル。

```bash
cat > CLAUDE.md << 'HEREDOC'
# Knowledge Graph Platform — Claude Code Guide

## プロジェクト概要
人類の総合知をグラフ構造で表現するプラットフォーム。
命題（proposition）を最小単位とし、それらの論理的依存関係を可視化する。

## 最重要設計原則
1. **プラットフォームは判定を行わない** — 分類・評価・フィルタリングは参加者の役割
2. **推定無罪** — 全投稿は反駁されるまで信頼される
3. **全パラメータ公開** — 同じ入力 → 同じ出力（決定論的）
4. **不完全な参加の前提** — 偏りの集積が多面性を形成

## 技術スタック
- Backend: Rust (Axum + SQLx), PostgreSQL 16 + pgvector + PGroonga
- Frontend: Vite + React + TypeScript + Cytoscape.js + CSS Modules
- リアルタイム通信: WebSocket (tokio-tungstenite)
- AI Agents: Python + Ollama / Gemini API
- Infra: Hetzner VPS + Docker Compose, Cloudflare Pages

## 認証方針
- 通常API（GET/POST /api/*）: 認証なし（オープンアクセス）
- バッチAPI（/api/batch/*）: APIキー認証必須

## ディレクトリ構造
- `backend/` — Rustバックエンド（Axum + SQLx）
- `backend/src/api/ws.rs` — WebSocketハンドラ
- `backend/migrations/` — SQLxマイグレーションファイル
- `frontend/` — React + TypeScript + Vite
- `frontend/src/styles/` — グローバルCSS + CSS変数
- `frontend/src/hooks/` — WebSocket等のカスタムフック
- `agents/` — Python AIエージェント
- `db/` — DBコンテナ用Dockerfile（pgvector + PGroonga）
- `docs/` — 設計書・スキーマ・図

## スタイリング方針
- Reactコンポーネント: CSS Modules（*.module.css）
- Cytoscape.jsグラフ: cy.style() API（JS内でスタイル定義）
- グローバルスタイル: src/styles/global.css（リセット、変数、フォント）

## 命名規則
- Rust: snake_case（関数・変数）、PascalCase（型・構造体）
- TypeScript: camelCase（関数・変数）、PascalCase（型・コンポーネント）
- CSS Modules: camelCase（クラス名）
- DB: snake_case（テーブル・カラム）
- API: /api/{resource} のREST形式、JSONレスポンス

## DB設計の要点
- 全テーブルのPKはUUID
- 命題(propositions)、関係(relations)、解釈(interpretations)が中心
- もっともらしさの計算はDB内のPL/pgSQL関数で実行
  - compute_plausibility_final, compute_structural_soundness_v2 等
- PGroongaで日本語全文検索をサポート
- 詳細は docs/core_schema.sql を参照

## テスト方針
- `cargo test` でバックエンドテスト
- `sqlx::test` でDB統合テスト（テスト用DBを自動作成）
- `npm test` でフロントエンドテスト

## よくある作業
- 新しいAPIエンドポイント追加: backend/src/api/ にハンドラ追加 → main.rs のRouterに登録
- WebSocketイベント追加: backend/src/api/ws.rs にハンドラ追加
- 新しいテーブル追加: backend/migrations/ に新しいSQLファイル → `sqlx migrate run`
- フロントコンポーネント追加: frontend/src/components/ に配置、スタイルは*.module.cssで作成
HEREDOC
```

### 10.2 Claude Codeの基本的な使い方

```bash
# プロジェクトルートで起動
cd knowledge-graph-platform
claude

# Claude Codeに作業を依頼する例:

# 命題のCRUD APIを作ってください。
# backend/src/api/propositions.rs にハンドラを、
# backend/src/models/proposition.rs に型定義を作成してください。
# GET /api/propositions, GET /api/propositions/:id,
# POST /api/propositions を実装してください。

# Claude Codeは CLAUDE.md を参照して、
# プロジェクトの設計原則と命名規則に沿ったコードを生成する。
```

### 10.3 Claude Codeでの効率的な開発パターン

```
1. 指示は具体的に:
   ✗ 「APIを作って」
   ✓ 「GET /api/propositions/:id を作って。
      propositionsテーブルからUUIDで検索し、
      関連するrelation_membersも含めて返す。」

2. エラーが出たらそのまま貼る:
   Claude Codeはエラーメッセージから修正を推論できる。
   「cargo checkで以下のエラーが出ました」→ コピペ

3. テストも一緒に頼む:
   「上記のAPIに対するテストも
    backend/tests/test_propositions.rs に作成してください」

4. 段階的に進める:
   一度に大量のコードを生成させるより、
   小さな機能単位で生成→確認→次へ、が確実。
```

---

## 11. 開発ワークフロー

### 11.1 日常の開発サイクル

```bash
# 1. DBを起動（初回 or 停止後）
docker compose up -d db

# 2. バックエンドを起動（開発モード、ファイル変更時に自動再起動）
cd backend
cargo watch -x run

# 3. フロントエンドを起動（別ターミナル）
cd frontend
npm run dev

# 4. 開発作業
#    - Claude Codeでコード生成
#    - cargo check で型チェック
#    - ブラウザで動作確認

# 5. テスト
cd backend && cargo test
cd frontend && npm test

# 6. コミット
git add .
git commit -m "feat: 命題のCRUD APIを追加"
git push origin main
```

### 11.2 ブランチ戦略（シンプル）

```bash
# 機能開発時
git checkout -b feature/proposition-api
# ... 開発 ...
git add .
git commit -m "feat: 命題のCRUD APIを追加"
git push origin feature/proposition-api
# GitHubでPull Requestを作成 → レビュー → マージ

# mainに戻る
git checkout main
git pull origin main
```

コミットメッセージの規約（推奨）:

```
feat: 新機能の追加
fix: バグ修正
docs: ドキュメントのみの変更
refactor: リファクタリング（機能変更なし）
test: テストの追加・修正
chore: ビルド・設定等の変更
```

### 11.3 マイグレーションの追加

スキーマを変更する際の手順:

```bash
cd backend

# 新しいマイグレーションファイルを作成
sqlx migrate add add_some_feature
# migrations/ に新しいSQLファイルが作成される

# SQLを記述した後、マイグレーション実行
sqlx migrate run --database-url "$DATABASE_URL"

# SQLxのオフラインクエリデータを更新
# （CI/CDやDockerビルドでDBなしでもコンパイルするために必要）
cargo sqlx prepare --database-url "$DATABASE_URL"
git add sqlx-data.json  # または .sqlx/ ディレクトリ
```

---

## 12. GitHub Actionsの設定

### 12.1 CI設定ファイルの作成

```bash
mkdir -p .github/workflows
```

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  CARGO_TERM_COLOR: always
  DATABASE_URL: postgres://app:test_password@localhost:5432/knowledge_graph_test

jobs:
  backend:
    name: Backend (Rust)
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Build and start DB (pgvector + PGroonga)
        run: |
          docker build -t kg-db-test ./db
          docker run -d --name kg-db-test \
            -e POSTGRES_DB=knowledge_graph_test \
            -e POSTGRES_USER=app \
            -e POSTGRES_PASSWORD=test_password \
            -p 5432:5432 \
            kg-db-test
          # ヘルスチェック待機
          for i in $(seq 1 30); do
            docker exec kg-db-test pg_isready -U app -d knowledge_graph_test && break
            sleep 2
          done

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable

      - name: Cache cargo dependencies
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            backend/target
          key: ${{ runner.os }}-cargo-${{ hashFiles('backend/Cargo.lock') }}

      - name: Run migrations
        run: |
          cargo install sqlx-cli --no-default-features --features rustls,postgres
          cd backend && sqlx migrate run

      - name: Check
        run: cd backend && cargo check

      - name: Test
        run: cd backend && cargo test

      - name: Clippy
        run: cd backend && cargo clippy -- -D warnings

      - name: Format check
        run: cd backend && cargo fmt -- --check

  frontend:
    name: Frontend (React)
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: frontend/package-lock.json

      - name: Install dependencies
        run: cd frontend && npm ci

      - name: Build
        run: cd frontend && npm run build

      - name: Lint
        run: cd frontend && npm run lint
```

### 12.2 コミットしてCIを確認

```bash
git add .github/
git commit -m "chore: GitHub Actions CIを設定"
git push origin main
# GitHubのActionsタブでCIの実行結果を確認
```

---

## 13. トラブルシューティング

### Docker関連

| 問題 | 原因 | 解決策 |
|------|------|--------|
| `docker compose up` でエラー | Docker Desktopが起動していない | Docker Desktopを起動する |
| ポート5432が既に使用中 | ローカルのPostgreSQLが動作中 | `sudo lsof -i :5432` で確認し、停止するか docker-compose.yml のポートを変更 |
| DBデータをリセットしたい | — | `docker compose down -v`（ボリュームも削除） |

### Rust関連

| 問題 | 原因 | 解決策 |
|------|------|--------|
| `cargo build` が遅い | 初回は依存クレート全てをコンパイル | 初回は5-10分かかるのが正常。2回目以降はキャッシュが効く |
| SQLxのコンパイル時チェックでエラー | DBに接続できない | DBが起動しているか確認。`DATABASE_URL` が正しいか確認 |
| `cargo check` と `cargo build` の違い | — | `check` は型チェックのみ（高速）、`build` はバイナリ生成まで行う。開発中は `check` を多用 |

### フロントエンド関連

| 問題 | 原因 | 解決策 |
|------|------|--------|
| `npm run dev` でAPIに接続できない | CORSエラー | バックエンドの `CorsLayer::permissive()` が有効か確認 |
| `npm ci` と `npm install` の違い | — | `ci` は `package-lock.json` から厳密にインストール（CI向け）。`install` は `package.json` から解決（開発向け） |

### Claude Code関連

| 問題 | 原因 | 解決策 |
|------|------|--------|
| 生成コードがプロジェクトの設計と合わない | コンテクスト不足 | `CLAUDE.md` を充実させる。具体的な設計原則やコード例を追記 |
| 大きな機能を一度に頼むと品質が下がる | コンテクスト長の限界 | 小さな単位に分割して依頼する |

---

## 付録: 全体の起動確認チェックリスト

すべての設定が完了した後、以下の手順で全体が動作するか確認する。

```bash
# 1. プロジェクトルートに移動
cd knowledge-graph-platform

# 2. DBを起動
docker compose up -d db
docker compose ps  # healthy を確認

# 3. マイグレーション実行（初回のみ）
cd backend
sqlx migrate run --database-url "$DATABASE_URL"

# 4. バックエンドを起動
cargo run &

# 5. ヘルスチェック
curl http://localhost:8080/health
# → {"status":"ok"}

# 6. DB接続確認
curl http://localhost:8080/api/stats
# → {"proposition_count":0}

# 7. フロントエンドを起動（別ターミナル）
cd frontend
npm run dev
# → ブラウザで http://localhost:5173 を確認

# 8. 全テスト実行
cd backend && cargo test
cd frontend && npm test

# すべてパスすれば開発環境の整備は完了 ✓
```
