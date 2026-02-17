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
- **Clippy**: `cargo clippy -- -D warnings` で警告ゼロを維持する。
- **レイヤー構造**:
  - `handlers/`: リクエスト/レスポンス処理（薄く保つ）
  - `services/`: ビジネスロジック
  - `repositories/`: DBアクセス（SQLx）
- **パターン**:
  ```rust
  // BAD: SQL injection risk
  let q = format!("SELECT * FROM propositions WHERE id = '{}'", id);

  // GOOD: Compile-time verified parameterized query
  let p = sqlx::query_as!(Proposition, "SELECT * FROM propositions WHERE id = $1", id)
      .fetch_optional(&pool).await?;
  ```
  ```rust
  // BAD: Error handling
  let result = something().unwrap();

  // GOOD: Error propagation
  let result = something().map_err(|e| AppError::Internal(e.into()))?;
  ```

### 3. Frontend 規約
- **コンポーネント**: `src/components/{Domain}/{Feature}/` に配置。
- **スタイリング**: 原則 CSS Modules (`*.module.css`) を使用。グローバルスタイルは最小限に。
- **状態管理**: サーバー状態は `TanStack Query` (未導入なら検討)、クライアント状態は `Zustand`。
- **不変性**: スプレッド演算子・`map`/`filter` で新しいオブジェクトを生成。直接変更禁止。
- **console.log禁止**: デバッグ後は必ず削除する。

### 4. Python/AI Agent 規約
- **APIキー**: 環境変数から読み込む（ハードコード禁止）
- **バリデーション**: Pydantic でデータ検証
- **エラーハンドリング**: 裸の `except:` 禁止。具体的な例外をキャッチする。
- **HTTP**: httpx + timeout 設定必須

### 5. テスト・検証
- **TDD推奨**: 基本的にテストを先に書くか、実装とセットで書く。
- **Rustテスト**: `cargo test` (ユニット), `#[sqlx::test]` (DB統合)。
- **カバレッジ**: 重要なロジックは80%以上のカバレッジを目指す。
- **エッジケース**: null/空文字, 日本語テキスト (Unicode), 境界値, エラーパスを必ずテスト。

### 6. セキュリティ
- **秘密情報**: ソースコードにAPIキー・パスワード・トークンを書かない。`.env` + `.gitignore` を使用。
- **SQL Injection**: `sqlx::query!` マクロのみ使用（文字列連結禁止）。
- **入力検証**: APIの境界で全てのユーザー入力を検証する。
- **エラーメッセージ**: 内部詳細をクライアントに公開しない。
- **バッチAPI**: `Authorization: Bearer <BATCH_API_KEY>` ヘッダーを必ず検証。

### 7. Git ワークフロー
- **コミットメッセージ形式**: `<type>: <description>`
  - `feat:` 新機能, `fix:` バグ修正, `refactor:` リファクタリング
  - `docs:` ドキュメント, `test:` テスト, `chore:` 雑務
- **CI**: `cargo fmt --check` → `cargo clippy` → `cargo test` → `npm run lint` → `npm run build`

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
cargo clippy -- -D warnings  # リント
cargo fmt           # フォーマット
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

# 全体検証
cd backend && cargo check && cargo clippy -- -D warnings && cargo test && cd ../frontend && npm run lint && npm run build
```

## ディレクトリ構造
```
dialectica/
├── CLAUDE.md                    # このファイル (Claude Code ガイド)
├── .claude/
│   ├── settings.json            # Hooks・自動化設定
│   └── commands/                # カスタムスラッシュコマンド
│       ├── plan.md              # /project:plan — 実装計画
│       ├── tdd.md               # /project:tdd — TDD ワークフロー
│       ├── code-review.md       # /project:code-review — コードレビュー
│       ├── verify.md            # /project:verify — 全体検証
│       ├── db-migrate.md        # /project:db-migrate — DB マイグレーション
│       └── graph-design.md      # /project:graph-design — グラフデータ設計
├── backend/                     # Rust API Server
│   ├── src/
│   │   ├── main.rs              # エントリーポイント
│   │   ├── api/                 # API Handlers (薄く保つ)
│   │   ├── services/            # ビジネスロジック
│   │   ├── db/                  # Repository Layer (SQLx)
│   │   └── models/              # Domain Models
│   └── migrations/              # SQLx マイグレーション
├── frontend/                    # React App
│   ├── src/
│   │   ├── components/          # {Domain}/{Feature}/ 配置
│   │   ├── hooks/               # Custom Hooks
│   │   ├── stores/              # Zustand ストア
│   │   └── styles/              # CSS Modules
│   └── public/
├── agents/                      # Python AI Agents
├── db/                          # Custom Docker build (pgvector/pgroonga)
└── doc/                         # 設計ドキュメント
    ├── project_document.md      # 総合設計書
    ├── er_diagram.mermaid       # ERダイアグラム
    ├── architecture_diagram.mermaid
    └── core_schema.sql          # 完全スキーマ定義
```

## 認証方針
- **通常API**: オープンアクセス (`GET /api/*`)
- **バッチAPI**: APIキー必須 (`POST /api/batch/*`) — ヘッダー `Authorization: Bearer <BATCH_API_KEY>`

## Claude Code カスタムコマンド

以下のスラッシュコマンドが使用可能:

| コマンド | 用途 |
|----------|------|
| `/project:plan` | 新機能の実装計画を立てる（コード前に承認を待つ） |
| `/project:tdd` | TDD ワークフロー (RED → GREEN → REFACTOR) |
| `/project:code-review` | コードレビュー (セキュリティ → 品質 → パフォーマンス) |
| `/project:verify` | 全体検証 (cargo check/clippy/test + npm lint/build) |
| `/project:db-migrate` | DB マイグレーション作成・適用 |
| `/project:graph-design` | グラフデータモデリング支援 |

## 推奨開発ワークフロー

```
1. /project:plan "機能の説明"     → 計画立案（承認まで待機）
2. ユーザー承認
3. /project:tdd                    → テスト先行で実装
4. /project:code-review            → コードレビュー
5. /project:verify                 → 全体検証
6. git commit -m "feat: ..."       → コミット
```

## Hooks (自動チェック)

`.claude/settings.json` に以下のフックが設定済み:

| タイミング | チェック内容 |
|------------|-------------|
| **Edit後** (Rust) | `println!` の使用を警告 |
| **Edit後** (Rust) | `format!` によるSQL構築をブロック |
| **Edit後** (TS) | `console.log` の使用を警告 |
| **Push前** | テスト・リント実行のリマインド |
| **応答完了時** | 変更ファイルの `println!`, `unwrap()`, `console.log` を監査 |
| **Write時** | `doc/` 外への不要な .md ファイル作成をブロック |
