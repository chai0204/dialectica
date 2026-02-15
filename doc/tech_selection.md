# 人類の総合知グラフプラットフォーム — 技術選定書

> **ステータス**: 設計フェーズ
> **最終更新**: 2026-02-16
> **前提**: Hetzner採用、AI駆動開発（Claude Code）、オープンソース

---

## 1. アーキテクチャ全体像

```
┌──────────────────────────────────────────────────────────────┐
│  フロントエンド（Cloudflare Pages）                            │
│  Vite + React + TypeScript + Cytoscape.js                    │
│  ※ 静的ビルド → CDN配信                                      │
├──────────────────────────────────────────────────────────────┤
│                     HTTPS (REST API)                         │
├──────────────────────────────────────────────────────────────┤
│  Hetzner VPS (CX22: 2vCPU / 4GB RAM / 40GB SSD)             │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Docker Compose                                        │  │
│  │  ┌──────────────────┐  ┌─────────────────────────────┐│  │
│  │  │  Rust Backend     │  │  PostgreSQL 16 + pgvector   ││  │
│  │  │  (Axum + SQLx)    │←→│  データ本体 + 計算関数       ││  │
│  │  │  Port: 8080       │  │  Port: 5432                 ││  │
│  │  └──────────────────┘  └─────────────────────────────┘│  │
│  └────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────┤
│  AIエージェント（ローカル or 別環境）                           │
│  Python + Ollama / Gemini API                                │
│  → バッチAPI経由でデータ投入                                   │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. バックエンド

### 2.1 言語: Rust

**選定理由**:
- もっともらしさ伝播・覆り波及BFS等の計算負荷の高い処理がコアにある
- 型安全性がオープンソースの長期保守に寄与する
- メモリ安全性がデータ改ざん防止の文脈で有利

**Rustバージョン**: stable最新（2024 edition）

### 2.2 Webフレームワーク: Axum

**選定理由**:
- tokioチームが開発・維持しており、非同期ランタイムとの相性が最良
- towerミドルウェアエコシステムとの統合（認証、レート制限、ロギング、CORS等）
- エクストラクタパターンによる型安全なリクエスト処理
- コミュニティが最も活発（情報量が多く、Claude Codeでの開発効率が高い）

**不採用候補**:
- Actix-web: 性能は同等だが、towerとの互換性が劣る。過去のメンテナ放棄歴あり
- Poem: OpenAPI自動生成が魅力だが、コミュニティ規模が小さい
- Loco: Rails風フルスタックだが、独自スキーマ・計算ロジックには過剰な抽象化

### 2.3 DB接続: SQLx

**選定理由**:
- コンパイル時SQLの型チェック（スキーマとの不整合をビルド時に検出）
- PostgreSQL固有機能（ENUM型、GENERATED ALWAYS AS、pgvector）をそのまま利用可能
- `compute_plausibility_final` 等の複雑な関数呼び出しが自然に書ける
- マイグレーション機能内蔵

**不採用候補**:
- SeaORM: ActiveRecordパターンだが、複雑なJOINや関数呼び出しで結局生SQLに落ちる
- Diesel: 型安全性は最高だが、非同期対応が後付け。pgvectorサポートが限定的

### 2.4 主要クレート

| 用途 | クレート | 備考 |
|------|---------|------|
| 非同期ランタイム | tokio | Axumの前提 |
| シリアライズ | serde + serde_json | JSON入出力 |
| UUID | uuid | 全テーブルのPK |
| 日時 | chrono | TIMESTAMPTZ対応 |
| ログ | tracing + tracing-subscriber | 構造化ログ |
| 環境変数 | dotenvy | .env管理 |
| エラーハンドリング | anyhow + thiserror | アプリ/ライブラリ両用 |
| バリデーション | validator | リクエストのバリデーション |
| CORS | tower-http | CORSミドルウェア |
| テスト | tokio::test + sqlx::test | DB統合テスト |

---

## 3. データベース

### 3.1 PostgreSQL 16 + pgvector

**選定理由**:
- core_schema.sqlの設計がPostgreSQL固有機能に強く依存
  - ENUM型、UUID型、JSONB、GENERATED ALWAYS AS
  - PL/pgSQL関数（compute_plausibility_final等）
  - pgvectorのHNSWインデックス
- 計算ロジックをDB内関数として実装しており、アプリ層に移す必要がない

**pgvectorバージョン**: 0.7以上（HNSWインデックス対応）

### 3.2 日本語全文検索: PGroonga

**選定理由**:
- 命題の全文検索・類似命題の発見は中核機能であり、日本語対応は初期フェーズから必須
- PGroongaはPostgreSQLの拡張として動作し、日本語を含む多言語の全文検索をネイティブにサポート
- tsvectorベースのPostgreSQL標準検索では日本語のトークナイゼーションにMeCab等の外部依存が必要だが、PGroongaはGroongaの形態素解析を内蔵しており追加設定が最小限
- `LIKE`検索より桁違いに高速で、インデックスベースの効率的な検索が可能

**Dockerイメージの構成**:
pgvectorとPGroongaの両方が必要なため、DBコンテナには自前のDockerfileを用意する。
```dockerfile
# db/Dockerfile
FROM pgvector/pgvector:pg16
RUN apt-get update && \
    apt-get install -y postgresql-16-pgdg-pgroonga && \
    rm -rf /var/lib/apt/lists/*
```
※ Groonga公式APTリポジトリの追加が必要な場合は、Dockerfileに`apt-key`とリポジトリ登録を追記する。

**不採用候補**:
- tsvector + MeCab: PostgreSQL標準だがMeCab辞書の管理・Docker内での設定が煩雑
- Meilisearch: 高機能だが別サービスとしての運用コストが増える。初期フェーズには過剰

**将来的な拡張**:
- 大規模化時にMeilisearch導入を検討（ファセット検索、タイポ耐性等が必要になった場合）

### 3.3 マイグレーション

SQLxの組み込みマイグレーションを使用。

```
migrations/
  001_initial_schema.sql      ← core_schema.sql の内容
  002_add_xxx.sql              ← 以降の変更
```

### 3.4 バックアップ

- Hetzner Storage Box（100GB、€1.05/月）にpg_dumpを日次で自動バックアップ
- cronジョブで `pg_dump | gzip` → Storage Box へrsync

---

## 4. フロントエンド

### 4.1 ビルドツール + フレームワーク: Vite + React + TypeScript

**選定理由**:
- バックエンドがRustで分離されているため、SSR（Next.js）は不要
- Viteの高速HMRで開発効率が高い
- TypeScriptの型安全性がAPI連携の信頼性を確保
- Claude Codeとの相性が良い（React + TSは学習データが豊富）

**不採用候補**:
- Next.js: SSR/ISR不要。バックエンドRustとの責務重複。過剰な抽象化
- SvelteKit: エコシステムがReactより小さく、グラフ可視化ライブラリの選択肢が狭い

### 4.2 グラフ可視化: Cytoscape.js

**選定理由**:
- グラフ可視化に特化しており、APIが直感的
- 数千ノード規模まで十分なパフォーマンス
- レイアウトアルゴリズムが豊富（dagre, cose, breadthfirst等）
- React用バインディング（react-cytoscapejs）が存在

**将来的な移行候補**:
- Sigma.js: WebGL描画で数万ノード以上に対応。大規模化時に検討

### 4.3 スタイリング方針: CSS Modules

**選定理由**:
- Cytoscape.jsは独自のスタイルシステム（`cy.style()`）を持ち、CSSユーティリティクラス（Tailwind等）とは互換性がない
- CSS Modulesを統一方式とすることで、Reactコンポーネントのスタイルとグラフ可視化のスタイルが明確に分離される
- コンポーネントごとにスコープされたCSSでクラス名の衝突を回避
- Viteが標準でCSS Modulesをサポートしており追加設定不要
- ビルドサイズへの影響がなく、ランタイムコストもゼロ

```
# スタイリングの責務分離
Reactコンポーネント → CSS Modules（*.module.css）
Cytoscape.jsグラフ  → cy.style() API（JS内でスタイル定義）
グローバルスタイル   → src/styles/global.css（リセット、変数、フォント）
```

**不採用候補**:
- Tailwind CSS: ユーティリティCSSはReact部分には便利だが、Cytoscape.jsのスタイルシステムとの二重管理が発生する。2つのスタイリングパラダイムの混在を避ける
- CSS-in-JS（styled-components等）: ランタイムコストがあり、Cytoscape.jsとの統合にメリットがない

### 4.4 その他のフロントエンド要素

| 用途 | ライブラリ | 備考 |
|------|-----------|------|
| 状態管理 | Zustand or jotai | 軽量。Reduxは過剰 |
| UIコンポーネント | Radix UI | ヘッドレスUI。スタイルはCSS Modulesで適用 |
| HTTPクライアント | fetch (標準) or ky | 外部依存最小化 |
| ルーティング | React Router v7 | SPA内のページ遷移 |
| フォーム | React Hook Form | バリデーション込み |
| リアルタイム通信 | WebSocket (native) | 覆り波及の即時通知に使用 |

### 4.5 ホスティング: Cloudflare Pages

**選定理由**:
- 無料で帯域無制限、グローバルCDN配信
- GitHub連携で自動ビルド＆デプロイ
- 日本を含む世界中のエッジロケーション（レイテンシ低減）

**代替候補**: Vercel（既にアカウントあり。機能的にはどちらでも可）

---

## 5. 認証

### 5.1 初期フェーズ: 認証なし（オープンアクセス）

初期フェーズでは認証を導入しない。全てのユーザーが認証なしで以下の操作を行える：

- 命題・解釈・関係の**読み取り**
- 命題・解釈・関係の**書き込み**（投稿）
- グラフの探索・脆弱性マップの閲覧

**理由**:
- 「推定無罪」の設計原則に沿い、参加障壁を最小化する
- 悪意ある投稿は認証ではなく構造的メカニズム（structural_soundness、クラスタリング）で減衰させる
- 初期フェーズはLLMエージェントによるブートストラップが主であり、通常APIの認証の必要性が低い

**例外: バッチAPIはAPIキー認証を初期から導入**:
- バッチAPI（`/api/batch/*`）は大量データの一括投入を行うため、認証なしで公開すると悪意ある大量投入で構造的減衰メカニズムの処理能力を超えるリスクがある
- 通常の投稿API（1件ずつ）はオープン、バッチAPIはAPIキー必須という切り分けとする

**将来的な拡張**:
- ユーザー識別が必要になった段階で、軽量な認証（OAuth / メールリンク）を導入
- `users`テーブルの`user_type`でAI/人間を区別する仕組みは維持

---

## 6. AIエージェント環境

### 6.1 言語: Python

**選定理由**:
- LLMライブラリのエコシステムが圧倒的に充実
- Ollama、Gemini API、OpenAI API等のSDKが全てPython優先
- バックエンドとは分離されたバッチ処理なので、言語を合わせる必要がない

### 6.2 LLM実行環境

| モデル | 用途 | 実行方法 |
|-------|------|---------|
| Gemini 2.0 Flash | Seed/Dialectic Agent | Google API（$0.10/1M入力トークン） |
| Llama 3 8B | Perspective Agent | Ollama（ローカル、無料） |
| Mistral 7B | Perspective Agent（多様性のため） | Ollama（ローカル、無料） |

Perspective Agentに異なるモデルを割り当てることで、
モデル固有の偏りが視点の多様性に寄与する（設計上の意図的な特性）。

### 6.3 データ投入方式: バッチAPI

```
[ローカル] Python Agent
    → JSON形式でデータ生成
    → POST /api/batch/propositions
    → POST /api/batch/interpretations
    → POST /api/batch/relations
[本番] Rust Backend
    → バリデーション
    → ai_generation_metadata 記録
    → DB INSERT
```

ローカルで生成したJSONファイルを保存しておくことで、
データの再現性・追跡可能性を確保する。

---

## 7. インフラ

### 7.1 本番環境: Hetzner VPS

| フェーズ | プラン | スペック | 月額 |
|---------|--------|---------|------|
| 初期公開（~数十人） | CX22 | 2vCPU / 4GB RAM / 40GB SSD | €3.99（約¥660） |
| 成長期（~数百人） | CX32 | 4vCPU / 8GB RAM / 80GB SSD | €6.99（約¥1,160） |
| 本格運用（~数千人） | CX42 | 8vCPU / 16GB RAM / 160GB SSD | €14.49（約¥2,400） |

**リージョン**: Ashburn（米国東部）を推奨
- 日本からのレイテンシ: 約170ms（Falkensteinの約250-300msより良好）
- フロントエンド静的アセットはCloudflare CDNでキャッシュされるため影響なし
- APIコール（命題投稿、解釈取得等）のレイテンシは直接UXに影響するため、日本に近いリージョンを優先
- 将来的にユーザーが増加した場合、Vultr東京/大阪への移行も選択肢

### 7.2 コンテナ管理: Docker Compose

```yaml
# docker-compose.yml（概要）
services:
  db:
    image: pgvector/pgvector:pg16
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: knowledge_graph
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "5432:5432"

  backend:
    build: ./backend
    depends_on:
      - db
    environment:
      DATABASE_URL: postgres://app:${DB_PASSWORD}@db/knowledge_graph
    ports:
      - "8080:8080"

volumes:
  pgdata:
```

### 7.3 デプロイフロー

```
# デプロイ手順（scripts/deploy.sh）

1. GitHub Actionsでビルド・テスト通過を確認
2. SSH接続でHetzner VPSにログイン
3. 以下を実行:
   cd /opt/knowledge-graph-platform
   git pull origin main
   docker compose pull          # 最新イメージを取得
   docker compose up -d          # コンテナを再起動
   docker compose exec backend sqlx migrate run  # マイグレーション実行
```

初期フェーズではこのシンプルなフローで十分。
ゼロダウンタイムデプロイが必要になった段階でBlue-Green等を検討する。

### 7.4 ドメイン・DNS

- ドメイン: 任意の.orgまたは.dev（年間約¥1,800）
- DNS: Cloudflare（無料）
- SSL: Cloudflareが自動管理

### 7.5 バックアップ

- Hetzner Storage Box 100GB: €1.05/月
- 日次pg_dump + 週次フルバックアップ
- バックアップスクリプトはリポジトリに含める

### 7.6 監視（初期は最小限）

- uptime監視: UptimeRobot（無料、5分間隔）
- ログ: Docker標準出力 → `docker logs` で確認
- 将来的: Prometheus + Grafana（VPS内にDocker Composeで追加）

---

## 8. 開発環境・ワークフロー

### 8.1 AI駆動開発: Claude Code

**開発フローの中心にClaude Codeを据える。**

```
開発者の役割:
  - 設計判断（アーキテクチャ、データモデル、思想的決定）
  - Claude Codeへの指示と出力のレビュー
  - テストの確認と承認

Claude Codeの役割:
  - Rust/TypeScript/Python のコード生成・修正
  - テストコードの生成
  - マイグレーションSQLの生成
  - Docker設定の生成・修正
  - ドキュメントの生成・更新
```

### 8.2 Claude Code活用のポイント

**Rustとの相性**:
- Rustのコンパイラエラーが詳細なので、Claude Codeがエラーメッセージから修正を推論しやすい
- 型システムが強いため、Claude Codeの生成コードの正確性が検証しやすい
- `cargo check` で高速にフィードバックループを回せる

**プロジェクト構造のコンテクスト管理**:
- CLAUDE.md にプロジェクトの設計原則・アーキテクチャ・命名規則を記述
- Claude Codeが一貫したコードを生成するためのガイドラインとして機能

**推奨ワークフロー**:
1. 機能要件を自然言語で記述
2. Claude Codeにコード生成を依頼
3. `cargo check` / `cargo test` でコンパイル・テスト確認
4. レビュー後、必要に応じて修正を依頼
5. git commit

### 8.3 リポジトリ構成

```
knowledge-graph-platform/
├── CLAUDE.md                    # Claude Code用プロジェクトガイド
├── docker-compose.yml
├── docker-compose.dev.yml       # 開発用オーバーライド
│
├── backend/                     # Rust (Axum + SQLx)
│   ├── Cargo.toml
│   ├── Dockerfile
│   ├── migrations/              # SQLxマイグレーション
│   ├── src/
│   │   ├── main.rs
│   │   ├── config.rs            # 環境変数・設定
│   │   ├── db/                  # DB接続・クエリ
│   │   ├── api/                 # APIハンドラ
│   │   │   ├── propositions.rs
│   │   │   ├── relations.rs
│   │   │   ├── interpretations.rs
│   │   │   ├── batch.rs         # バッチインサートAPI
│   │   │   ├── computation.rs   # 計算結果取得API
│   │   │   └── ws.rs            # WebSocketハンドラ
│   │   ├── models/              # 型定義
│   │   ├── computation/         # 計算ロジック（DB関数呼び出し）
│   │   └── error.rs             # エラー型
│   └── tests/                   # 統合テスト
│
├── frontend/                    # React + TypeScript + Vite
│   ├── package.json
│   ├── vite.config.ts
│   ├── src/
│   │   ├── App.tsx
│   │   ├── styles/              # グローバルCSS + CSS変数
│   │   ├── components/
│   │   │   ├── graph/           # Cytoscape.js グラフ表示
│   │   │   ├── proposition/     # 命題の詳細表示
│   │   │   ├── interpretation/  # 解釈の投稿・表示
│   │   │   └── fragility/       # 脆弱性マップ表示
│   │   ├── api/                 # API呼び出し
│   │   ├── hooks/               # WebSocket等のカスタムフック
│   │   ├── stores/              # 状態管理
│   │   └── types/               # 型定義
│   └── Dockerfile
│
├── agents/                      # Python AIエージェント
│   ├── requirements.txt
│   ├── seed_agent.py
│   ├── dialectic_agent.py
│   ├── perspective_agent.py
│   ├── bridge_agent.py
│   ├── batch_client.py          # バッチAPI呼び出し
│   └── prompts/                 # プロンプトテンプレート
│
├── docs/                        # プロジェクトドキュメント
│   ├── project_document.md
│   ├── core_schema.sql
│   ├── agent_workflow.md
│   └── diagrams/
│
└── scripts/                     # 運用スクリプト
    ├── backup.sh
    ├── deploy.sh                # docker compose pull ベースのデプロイ
    └── seed_data/               # 初期データ
```

### 8.4 バージョン管理: GitHub（パブリック）

- ブランチ戦略: main + feature branches（シンプルに）
- CI: GitHub Actions
  - `cargo check` + `cargo test`（バックエンド）
  - `npm run build` + `npm test`（フロントエンド）
  - SQLxのマイグレーション検証
- ライセンス: AGPL-3.0（オープンソース、改変時の公開義務）

---

## 9. ランニングコスト概算

### 初期公開フェーズ（月額）

| 項目 | コスト |
|------|--------|
| Hetzner CX22 | ¥660 |
| Cloudflare Pages | ¥0 |
| ドメイン | ¥150 |
| バックアップ（Storage Box） | ¥170 |
| AIエージェント（Gemini Flash） | ¥300-750 |
| **合計** | **約¥1,300-1,700/月** |

### 成長フェーズ（月額）

| 項目 | コスト |
|------|--------|
| Hetzner CX32 | ¥1,160 |
| Cloudflare Pages | ¥0 |
| ドメイン | ¥150 |
| バックアップ | ¥330 |
| AIエージェント + 埋め込み計算 | ¥1,500-3,000 |
| **合計** | **約¥3,000-4,700/月** |

---

## 10. 将来の拡張パス

| トリガー | 対応 |
|---------|------|
| ノード10万超・レスポンス遅延 | CX32→CX42へスケールアップ |
| pgvectorのメモリ不足 | DBサーバーを別VPSに分離 |
| 日本ユーザー増加・レイテンシ問題 | Cloudflare Workersでレスポンスキャッシュ、またはVultr東京に移行 |
| ユーザー数千人超 | ロードバランサー追加、読み取りレプリカ |
| GraphQL要望 | async-graphql (Rust) を追加 |
| PGroongaの限界 | Meilisearchを別サービスとして導入 |
| モバイルアプリ | React Native（フロントのTS資産を再利用） |
| 認証が必要になった場合 | OAuth / メールリンク認証を導入 |

---

## 11. 技術選定の判断基準まとめ

| 基準 | 選定方針 |
|------|---------|
| **性能** | 計算負荷の高いコアにはRust。フロントは標準的なReact |
| **コスト** | Hetzner + Cloudflare で月¥1,300から開始可能 |
| **AI駆動開発** | Claude Codeとの相性を重視（Rust/React/TypeScriptは学習データ豊富） |
| **オープンソース** | エコシステムが活発で、コミュニティの貢献を受けやすい技術を選択 |
| **保守性** | 型安全性（Rust + TypeScript）で長期的な保守を支える |
| **段階的成長** | Docker Composeで始め、必要に応じてスケールアップ/分離 |
| **日本語対応** | PGroongaによる全文検索を初期から組み込み |
