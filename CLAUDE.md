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
