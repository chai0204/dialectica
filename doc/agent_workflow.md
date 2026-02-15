## LLM エージェント ブートストラップ設計

### 基本方針

- 小さいモデル（Gemini 2.0 Flash / ローカルLLM）で十分な粒度に留める
- エージェントも「偏った視野からの不完全な解釈者」として参加する
- AI生成は全て明示し、人間が承認・修正・反駁できる
- コンテクスト肥大化を前提とし、局所的な判断で投稿する

---

### Agent 1: Seed Agent（種まき）

**目的**: 既存の構造化知識をグラフの初期データとして投入

**入力ソース**:
- Wikipedia 記事（出典付きの主張を抽出）
- Wikidata の構造化トリプル
- 学術論文アブストラクト（Semantic Scholar API 等）
- 教科書の定義・定理

**ワークフロー**:

```
入力: Wikipedia記事の1セクション（2000トークン程度）

ステップ1: 命題の抽出
  プロンプト: 「以下のテキストから、独立した主張を命題として抽出してください。
  各命題について以下を判定してください:
  - content: 命題の自然言語表現
  - type: fact_claim / value_judgment / definition / hypothesis
  - 前提として必要な他の命題（あれば）」

ステップ2: 関係の抽出
  プロンプト: 「抽出した命題間の関係を特定してください。
  - type: support / refutation / causation / specialization / etc.
  - 各関係の参加命題とその役割(premise/conclusion)」

ステップ3: フレームの特定
  プロンプト: 「各命題が暗黙に前提とする概念フレームを特定してください。
  例: 経済の議論なら 'Market_transaction' フレーム」

ステップ4: DBへの登録
  - propositions, relations, relation_members, frames を INSERT
  - ai_generation_metadata に記録（review_status: 'pending'）
```

**モデル要件**: Flash級で十分。構造化出力（JSON mode）推奨。

**実行頻度**: 初期に大量実行 → 徐々にペースを落とす

---

### Agent 2: Dialectic Agent（弁証法）

**目的**: 既存の命題に対して構造化された反駁を生成し、Layer 2 のデータを蓄積

**ワークフロー**:

```
入力: plausibility_cache から「反駁が少ない命題」を選択
      （refutation_count が少なく、かつ downstream_count が多いものを優先）

ステップ1: 反駁の生成
  プロンプト: 「以下の命題に対して、最も強力な反論を生成してください。
  命題: {content}
  この命題の前提: {premises}

  反論には以下を含めてください:
  - 反論の種類: premise_attack / inference_attack / counter_example / alternative_explanation
  - 反論を支持する前提命題
  - 反論の推論パターン: deductive / inductive / abductive / etc.」

ステップ2: 反駁の前提を既存グラフから検索
  - 生成された反論の根拠が既存の命題にあるか検索
  - あればリンク、なければ新規命題として追加

ステップ3: DBへの登録
  - interpretations（stance: disagree）を INSERT
  - interpretation_premises で根拠をリンク
  - interpretation_rebuttals で反駁関係を記録
```

**モデル要件**: Flash級で十分だが、反論の質が重要なので
より大きいモデルを使うと質が上がる。
ただし「偏った反論でよい」ので小さいモデルでも価値がある。

**重要**: 反駁エージェントが生成する反論が全て正しい必要はない。
弱い反論は、元の命題の反駁耐性を上げる（battle_tested_bonus）ので、
むしろ有益。

---

### Agent 3: Perspective Agent（視点拡張）

**目的**: 既存の命題に対して、異なる視野からの解釈を生成

**ワークフロー**:

```
入力: 命題P + その命題に対する既存の解釈の視野リスト
      → まだカバーされていない視野を特定

ステップ1: 不足視野の特定
  既存の interpretation_perspectives から、
  この命題にまだ適用されていない perspectives を取得

ステップ2: 指定視野からの解釈生成
  プロンプト: 「以下の命題を{perspective_name}の観点から解釈してください。
  命題: {content}

  この観点から見たとき:
  - この命題に賛成/反対/条件付き賛成のいずれか
  - その根拠（この観点特有の前提を明示）
  - この観点から見て見落とされている論点」

ステップ3: 明示的なblind spotの宣言
  プロンプト: 「あなたは{perspective_name}の観点のみから分析しました。
  考慮できていない視点を列挙してください。」
  → interpretation_blind_spots に記録
```

**モデル要件**: ローカルLLMでも可能。
むしろモデルの「偏り」が異なる視点の多様性に寄与する。
異なるモデル（Gemini, Llama, Mistral）を異なる視点に割り当てると
自然な多様性が生まれる。

---

### Agent 4: Bridge Agent（架橋）

**目的**: 異なるドメインの命題間に関係を発見

**ワークフロー**:

```
入力: 2つの異なるドメインの命題群
      （例: 経済学クラスタと環境学クラスタ）

ステップ1: 共通構造の発見
  プロンプト: 「以下の2つのドメインの命題群を比較し、
  構造的に類似した論証パターン、共通する前提、
  または矛盾する主張を特定してください。」

ステップ2: 関係の提案
  - analogy: 構造的に類似
  - contradiction: ドメイン間で矛盾
  - composition: 片方が他方の一部

ステップ3: DBへの登録
  - relations, relation_members として登録
```

**モデル要件**: これは比較的高い推論能力が必要。
Flash級でも可能だが、精度を上げるなら大きめのモデル推奨。
ただし頻度が低いので（初期は週1回程度）コストは小さい。

---

### エージェント協調のオーケストレーション

```
Phase 1 (Week 1-4): Seed Agent を集中投入
  - Wikipedia主要記事 1000件 → 命題 ~10,000件
  - 各命題に type, frame を付与
  - 目標: グラフの骨格を構築

Phase 2 (Week 2-8): Dialectic Agent を投入
  - Phase 1 で生成された命題に反駁を生成
  - downstream_count の多い命題を優先
  - 目標: Layer 2 のデータ蓄積

Phase 3 (Week 3-12): Perspective Agent を投入
  - 解釈の視野多様性が低い命題を優先
  - 目標: 量子状態の充実

Phase 4 (Week 6-): Bridge Agent を投入
  - 十分なクラスタが形成されてから
  - 目標: ドメイン間接続

Phase 5 (継続): 全エージェントが低頻度で継続稼働
  - 新規命題 → Seed が関連命題を追加
  - 反駁不足 → Dialectic が生成
  - 視野不足 → Perspective が補完
  - 孤立クラスタ → Bridge が接続
```

---

### コンテクスト肥大化への対処

**エージェントのコンテクストウィンドウ設計**:

```
各エージェントの入力は意図的に制限する:

Seed Agent:     ~2000 tokens（記事の1セクション）
Dialectic Agent: ~1500 tokens（命題 + 直接の前提2-3個）
Perspective Agent: ~1000 tokens（命題 + 視野の説明）
Bridge Agent:    ~3000 tokens（2ドメインから各5命題程度）

→ どのエージェントも「全体を把握していない」
→ これは設計上の制約ではなく、意図的な特性
→ 各エージェントの「偏った」出力が集積して多面性を形成
```

**これが人間の参加者と同じ構造になる**:
- 人間も全ての前提を把握して意見を言うわけではない
- 自分の専門・関心・経験から偏った解釈を投稿する
- その集積が集合知になる
- LLMエージェントも同じ原理で参加する

---

### コスト見積もり（ブートストラップ Phase 1-3）

```
Gemini 2.0 Flash の場合:
  入力: ~$0.10 / 1M tokens
  出力: ~$0.40 / 1M tokens

Phase 1 (Seed, 10,000命題):
  推定トークン: 入力 20M + 出力 10M = ~$6
  
Phase 2 (Dialectic, 命題あたり2反駁):
  推定トークン: 入力 30M + 出力 15M = ~$9

Phase 3 (Perspective, 命題あたり3視点):
  推定トークン: 入力 30M + 出力 15M = ~$9

合計: ~$24 で 10,000命題 + 20,000反駁 + 30,000視点解釈
→ グラフノード ~60,000 エッジ ~100,000 規模の初期データ

ローカルLLM (Llama 3 8B等) なら電気代のみ。
```
