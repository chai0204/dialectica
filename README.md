# Human Knowledge Graph Platform (Dialectica)

人類の総合知をグラフ構造で表現するプラットフォーム。

## プロジェクト構成

- **Backend**: Rust (Axum + SQLx)
- **Frontend**: React (Vite + TypeScript)
- **Database**: PostgreSQL 16 + pgvector + PGroonga
- **AI Agents**: Python
- **Infrastructure**: Docker Compose

## クイックスタート

### 1. 開発環境の起動

```bash
# DBコンテナの起動（初回はビルドが走ります）
docker compose up -d

# バックエンドの起動（ポート 4000）
cd backend
cargo run

# フロントエンドの起動（ポート 5173）
cd frontend
npm run dev
```

### 2. 環境変数

`.env.example` をコピーして `.env` を作成してください。
デフォルトでは以下のポートを使用します：

- Backend: 4000
- Database: 5433 (ホスト側), 5432 (コンテナ内)
- Frontend: 5173

### 3. API ドキュメント

- ヘルスチェック: `GET http://localhost:4000/health`
- 統計情報: `GET http://localhost:4000/api/stats`

## 開発ガイド

詳細は `doc/dev_setup_guide.md` および `CLAUDE.md` を参照してください。
