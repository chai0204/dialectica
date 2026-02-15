# Human Knowledge Graph Platform (Dialectica) — Claude Code Guide

## プロジェクト概要
人類の総合知をグラフ構造で表現するプラットフォーム。
命題（proposition）を最小単位とし、それらの論理的依存関係を可視化する。

## 技術スタック
- **Backend**: Rust 1.93+ (Axum + SQLx), PostgreSQL 16 + pgvector + PGroonga
- **Frontend**: React 19 (Vite + TypeScript + CSS Modules), Cytoscape.js
- **AI Agents**: Python 3.12+ (Ollama / Gemini API)
- **Infra**: Docker Compose, Hetzner VPS

## クリティカル・ルール (Must Follow)

### 1. コード品質と設計
- **不変性 (Immutability)**: オブジェクトや配列は決して変更せず、常に新しいコピーを作成する。
- **小さなファイル**: 1ファイル 200-400行を目安とする。800行を超えたら分割を検討。
- **高凝集・低結合**: 機能・ドメインごとに整理し、層（Layer）間の依存は一方向に保つ。

### 2. Rust/Backend 規約
- **エラー処理**: ライブラリ・モジュールエラーには `thiserror` を、アプリケーショントップレベルでは `anyhow` を使用。`unwrap()` / `expect()` は禁止（テストコード除く）。
- **SQLx活用**: クエリは必ず `sqlx::query!` / `query_as!` マクロを使用し、コンパイル時に検証する。文字列連結によるSQL構築は厳禁。
- **ロギング**: `println!` は使用せず、必ず `tracing::info!` / `error!` 等を使用する。
- **レイヤー構造**:
  - `handlers/`: リクエスト/レスポンス処理（薄く保つ）
  - `services/`: ビジネスロジック
  - `repositories/`: DBアクセス（SQLx）

### 3. Frontend 規約
- **コンポーネント**: `src/components/{Domain}/{Feature}/` に配置。
- **スタイリング**: 原則 CSS Modules (`*.module.css`) を使用。グローバルスタイルは最小限に。
- **状態管理**: サーバー状態は `TanStack Query` (未導入なら検討)、クライアント状態は `Zustand`。

### 4. テスト・検証
- **TDD推奨**: 基本的にテストを先に書くか、実装とセットで書く。
- **RUSTテスト**: `cargo test` (ユニット), `#[sqlx::test]` (DB統合)。
- **カバレッジ**: 重要なロジックは80%以上のカバレッジを目指す。

## 環境構築・コマンド

### ポート設定
- **Backend**: `4000` (Localhost)
- **Frontend**: `5173`
- **Database**: `5433` (Host), `5432` (Container)

### よく使うコマンド

```bash
# バックエンド開発
cd backend
cargo run           # 起動
cargo test          # テスト
cargo check         # 構文チェック
sqlx migrate run    # マイグレーション適用（要: DB起動）

# フロントエンド開発
cd frontend
npm run dev         # 起動
npm run build       # ビルド
npm run lint        # リント

# DB操作
docker compose up -d      # DB起動
docker compose down       # DB停止
docker compose logs -f db # ログ確認
```

## ディレクトリ構造
- `backend/` — Rust API Server
  - `src/api/` — API Handlers
  - `src/models/` — Domain Models
  - `src/db/` — Repository Layer
- `frontend/` — React App
  - `src/components/` — UI Components
  - `src/hooks/` — Custom Hooks
  - `src/styles/` — CSS Modules & Global Styles
- `agents/` — Python AI Agents
- `db/` — Custom Docker build (pgvector/pgroonga)

## 認証方針
- **通常API**: オープンアクセス (`GET /api/*`)
- **バッチAPI**: APIキー必須 (`POST /api/batch/*`) — ヘッダー `Authorization: Bearer <BATCH_API_KEY>`
