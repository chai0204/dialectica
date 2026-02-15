-- ============================================================
-- 人類の総合知グラフプラットフォーム — 統合スキーマ（最終版）
-- ============================================================
-- 設計原則:
--   ・プラットフォーム = 決定論的な競技場（判定を行わない）
--   ・推定無罪（反駁されない限り信頼される）
--   ・不完全な参加の前提（偏りの集積が多面性を形成）
--   ・全パラメータ公開（同じ入力→同じ出力）
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS vector;  -- pgvector

-- ============================================================
-- 0. ENUM 型定義
-- ============================================================

CREATE TYPE proposition_type AS ENUM (
    'fact_claim', 'value_judgment', 'definition',
    'hypothesis', 'question', 'meta'
);

CREATE TYPE relation_type AS ENUM (
    'support', 'refutation', 'equivalence', 'context_restriction',
    'analogy', 'causation', 'correlation', 'composition',
    'specialization', 'contradiction'
);

CREATE TYPE member_role AS ENUM (
    'premise', 'conclusion', 'subject', 'object', 'context', 'qualifier'
);

CREATE TYPE interpretation_target AS ENUM ('proposition', 'relation');

CREATE TYPE interpretation_stance AS ENUM (
    'agree', 'disagree', 'uncertain', 'conditional', 'reinterpret'
);

CREATE TYPE inference_pattern AS ENUM (
    'deductive', 'inductive', 'abductive', 'analogical',
    'statistical', 'causal', 'normative', 'definitional'
);

CREATE TYPE equivalence_status AS ENUM ('proposed', 'approved', 'rejected');


-- ============================================================
-- 1. USERS（参加者: 人間もAIも同一テーブル・同一ルール）
-- ============================================================

CREATE TABLE users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username     VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(200),
    user_type    VARCHAR(20) NOT NULL DEFAULT 'human'
                 CHECK (user_type IN ('human','ai_seed','ai_dialectic','ai_bridge','ai_perspective')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 2. CORE LAYER（命題・関係・ハイパーエッジ）
-- ============================================================

CREATE TABLE propositions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content    TEXT NOT NULL,
    type       proposition_type NOT NULL,
    parent_id  UUID REFERENCES propositions(id) ON DELETE SET NULL,
    frame_id   UUID,  -- FK → frames (後述)
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_prop_parent ON propositions(parent_id);
CREATE INDEX idx_prop_type ON propositions(type);

CREATE TABLE relations (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type       relation_type NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE relation_members (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    relation_id    UUID NOT NULL REFERENCES relations(id) ON DELETE CASCADE,
    proposition_id UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    role           member_role NOT NULL,
    position       INT NOT NULL DEFAULT 0,
    UNIQUE(relation_id, proposition_id, role)
);
CREATE INDEX idx_rm_relation ON relation_members(relation_id);
CREATE INDEX idx_rm_proposition ON relation_members(proposition_id);


-- ============================================================
-- 3. INTERPRETATION & REBUTTAL LAYER（解釈・反駁）
-- ============================================================

CREATE TABLE interpretations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type   interpretation_target NOT NULL,
    target_id     UUID NOT NULL,
    author_id     UUID NOT NULL REFERENCES users(id),
    stance        interpretation_stance NOT NULL,
    confidence    DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    reasoning     TEXT,
    conditions    JSONB,
    inference_type inference_pattern,       -- 参加者の自己申告
    structured_reasoning JSONB,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(target_type, target_id, author_id, stance)
);
CREATE INDEX idx_interp_target ON interpretations(target_type, target_id);
CREATE INDEX idx_interp_author ON interpretations(author_id);

CREATE TABLE interpretation_premises (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interpretation_id UUID NOT NULL REFERENCES interpretations(id) ON DELETE CASCADE,
    proposition_id    UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    role              VARCHAR(50) NOT NULL CHECK (role IN (
        'supporting_evidence','necessary_assumption',
        'contextual_condition','counter_to_alternative'
    )),
    weight            DECIMAL(3,2) NOT NULL DEFAULT 1.0 CHECK (weight > 0 AND weight <= 1),
    UNIQUE(interpretation_id, proposition_id, role)
);
CREATE INDEX idx_ip_interp ON interpretation_premises(interpretation_id);
CREATE INDEX idx_ip_prop ON interpretation_premises(proposition_id);

CREATE TABLE interpretation_rebuttals (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_interpretation_id   UUID NOT NULL REFERENCES interpretations(id) ON DELETE CASCADE,
    rebuttal_interpretation_id UUID NOT NULL REFERENCES interpretations(id) ON DELETE CASCADE,
    rebuttal_type              VARCHAR(50) NOT NULL CHECK (rebuttal_type IN (
        'premise_attack','inference_attack','undercutting',
        'counter_example','alternative_explanation'
    )),
    attacked_premise_id        UUID REFERENCES interpretation_premises(id),
    status                     VARCHAR(20) NOT NULL DEFAULT 'active'
                               CHECK (status IN ('active','addressed','withdrawn','superseded')),
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(target_interpretation_id, rebuttal_interpretation_id)
);
CREATE INDEX idx_reb_target ON interpretation_rebuttals(target_interpretation_id);


-- ============================================================
-- 4. SEMANTIC FRAME LAYER（フレーム意味論）
-- ============================================================

CREATE TABLE frames (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(200) NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE propositions
    ADD CONSTRAINT fk_prop_frame FOREIGN KEY (frame_id) REFERENCES frames(id) ON DELETE SET NULL;

CREATE TABLE frame_roles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    frame_id    UUID NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
    role_name   VARCHAR(100) NOT NULL,
    description TEXT,
    is_required BOOLEAN NOT NULL DEFAULT false,
    UNIQUE(frame_id, role_name)
);

CREATE TABLE frame_bindings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proposition_id UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    frame_role_id  UUID NOT NULL REFERENCES frame_roles(id) ON DELETE CASCADE,
    bound_value    TEXT NOT NULL,
    UNIQUE(proposition_id, frame_role_id)
);


-- ============================================================
-- 5. CONTEXT LAYER（文脈・スコープ）
-- ============================================================

CREATE TABLE contexts (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(200) NOT NULL,
    description TEXT,
    parent_id  UUID REFERENCES contexts(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE proposition_contexts (
    proposition_id UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    context_id     UUID NOT NULL REFERENCES contexts(id) ON DELETE CASCADE,
    PRIMARY KEY(proposition_id, context_id)
);


-- ============================================================
-- 6. EQUIVALENCE LAYER（等価管理: Frege Sinn/Bedeutung）
-- ============================================================

CREATE TABLE equivalence_groups (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    canonical_id UUID NOT NULL REFERENCES propositions(id),
    rationale    TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE equivalence_members (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id       UUID NOT NULL REFERENCES equivalence_groups(id) ON DELETE CASCADE,
    proposition_id UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    similarity     DECIMAL(3,2) CHECK (similarity >= 0 AND similarity <= 1),
    proposed_by    UUID NOT NULL REFERENCES users(id),
    status         equivalence_status NOT NULL DEFAULT 'proposed',
    reviewed_at    TIMESTAMPTZ,
    UNIQUE(group_id, proposition_id)
);


-- ============================================================
-- 7. EMBEDDING & CLUSTERING LAYER
-- ============================================================

CREATE TABLE interpretation_embeddings (
    interpretation_id UUID PRIMARY KEY REFERENCES interpretations(id) ON DELETE CASCADE,
    embedding         vector(768),
    model_name        VARCHAR(100) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ie_hnsw ON interpretation_embeddings USING hnsw (embedding vector_cosine_ops);

CREATE TABLE proposition_embeddings (
    proposition_id UUID PRIMARY KEY REFERENCES propositions(id) ON DELETE CASCADE,
    embedding      vector(768),
    model_name     VARCHAR(100) NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pe_hnsw ON proposition_embeddings USING hnsw (embedding vector_cosine_ops);

CREATE TABLE interpretation_clusters (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proposition_id     UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    centroid_interp_id UUID REFERENCES interpretations(id),
    summary            TEXT,
    dominant_stance    VARCHAR(20),
    stance_agreement   DECIMAL(3,2),
    member_count       INT NOT NULL DEFAULT 0,
    cohesion           DECIMAL(5,4),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE interpretation_cluster_members (
    cluster_id           UUID NOT NULL REFERENCES interpretation_clusters(id) ON DELETE CASCADE,
    interpretation_id    UUID NOT NULL REFERENCES interpretations(id) ON DELETE CASCADE,
    distance_to_centroid DECIMAL(5,4),
    PRIMARY KEY(cluster_id, interpretation_id)
);


-- ============================================================
-- 8. PERSPECTIVE & TAG LAYER
-- ============================================================

CREATE TABLE perspectives (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(200) NOT NULL,
    description TEXT,
    parent_id  UUID REFERENCES perspectives(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE interpretation_perspectives (
    interpretation_id UUID NOT NULL REFERENCES interpretations(id) ON DELETE CASCADE,
    perspective_id    UUID NOT NULL REFERENCES perspectives(id) ON DELETE CASCADE,
    depth             VARCHAR(20) NOT NULL DEFAULT 'primary'
                      CHECK (depth IN ('primary','considered','acknowledged')),
    PRIMARY KEY(interpretation_id, perspective_id)
);

CREATE TABLE interpretation_blind_spots (
    interpretation_id UUID NOT NULL REFERENCES interpretations(id) ON DELETE CASCADE,
    perspective_id    UUID NOT NULL REFERENCES perspectives(id) ON DELETE CASCADE,
    reason            TEXT,
    PRIMARY KEY(interpretation_id, perspective_id)
);

CREATE TABLE interpretation_tags (
    interpretation_id UUID NOT NULL REFERENCES interpretations(id) ON DELETE CASCADE,
    tag_name          VARCHAR(100) NOT NULL,
    tag_value         TEXT,
    tagged_by         UUID NOT NULL REFERENCES users(id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(interpretation_id, tag_name, tagged_by)
);
-- ★ タグはもっともらしさ計算に一切影響しない


-- ============================================================
-- 9. CACHE & PARAMETERS（計算キャッシュ・公開パラメータ）
-- ============================================================

CREATE TABLE plausibility_cache (
    proposition_id     UUID PRIMARY KEY REFERENCES propositions(id) ON DELETE CASCADE,
    local_score        DECIMAL(5,4) NOT NULL DEFAULT 0,
    propagated_score   DECIMAL(5,4) NOT NULL DEFAULT 0,
    fragility_score    DECIMAL(5,4) NOT NULL DEFAULT 1.0,
    interpretation_count INT NOT NULL DEFAULT 0,
    last_computed      TIMESTAMPTZ NOT NULL DEFAULT now(),
    previous_propagated DECIMAL(5,4) DEFAULT 0,
    delta              DECIMAL(5,4) GENERATED ALWAYS AS (ABS(propagated_score - previous_propagated)) STORED
);

CREATE TABLE relation_confidence_cache (
    relation_id   UUID PRIMARY KEY REFERENCES relations(id) ON DELETE CASCADE,
    confidence    DECIMAL(5,4) NOT NULL DEFAULT 0,
    last_computed TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE system_parameters (
    key         VARCHAR(100) PRIMARY KEY,
    value       DECIMAL NOT NULL,
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO system_parameters (key, value, description) VALUES
    ('cluster_similarity_threshold',    0.85,   'クラスタリングのコサイン類似度閾値'),
    ('cluster_plausibility_log_base',   2.7183, 'クラスタ支持数の対数底'),
    ('structural_no_premise_base',      0.3,    '前提なし解釈の基礎スコア'),
    ('structural_premise_log_coeff',    0.3,    '前提数の対数補正係数'),
    ('cascade_damping_factor',          0.85,   '波及伝播の減衰係数'),
    ('cascade_threshold',               0.05,   '波及伝播の打ち切り閾値'),
    ('propagation_local_weight',        0.40,   '局所もっともらしさの重み'),
    ('propagation_cascade_weight',      0.60,   '伝播もっともらしさの重み'),
    ('reliability_structural_weight',   0.60,   '構造的健全性の重み'),
    ('reliability_resilience_weight',   0.40,   '反駁耐性の重み');


-- ============================================================
-- 10. AI SUGGESTION LAYER（グラフに影響しない隔離層）
-- ============================================================

CREATE TABLE ai_suggestions (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type        VARCHAR(30) NOT NULL
                       CHECK (target_type IN ('raw_input','interpretation','proposition','rebuttal_opportunity')),
    target_id          UUID,
    suggestion_content JSONB NOT NULL,
    model_name         VARCHAR(100) NOT NULL,
    response_status    VARCHAR(20) NOT NULL DEFAULT 'pending'
                       CHECK (response_status IN ('pending','adopted','modified','dismissed','expired')),
    adopted_entity_ids UUID[],
    user_id            UUID NOT NULL REFERENCES users(id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 days')
);
-- ★ グラフ本体との外部キー結合なし → テーブルごと削除してもグラフ不変

CREATE TABLE ai_generation_metadata (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type   VARCHAR(50) NOT NULL,
    target_id     UUID NOT NULL,
    model_name    VARCHAR(100) NOT NULL,
    workflow_name VARCHAR(100) NOT NULL,
    input_context JSONB,
    review_status VARCHAR(20) NOT NULL DEFAULT 'pending'
                  CHECK (review_status IN ('pending','approved','modified','rejected')),
    reviewed_by   UUID REFERENCES users(id),
    reviewed_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 11. AUDIT LAYER（変更履歴・波及記録）
-- ============================================================

CREATE TABLE revision_history (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type    VARCHAR(50) NOT NULL,
    target_id      UUID NOT NULL,
    previous_state JSONB,
    new_state      JSONB,
    changed_by     UUID NOT NULL REFERENCES users(id),
    change_reason  TEXT,
    changed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_rev_target ON revision_history(target_type, target_id);

CREATE TABLE cascade_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trigger_proposition UUID NOT NULL REFERENCES propositions(id),
    trigger_delta       DECIMAL(5,4) NOT NULL,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,
    total_affected      INT DEFAULT 0
);

CREATE TABLE cascade_impacts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cascade_event_id UUID NOT NULL REFERENCES cascade_events(id) ON DELETE CASCADE,
    proposition_id   UUID NOT NULL REFERENCES propositions(id),
    old_score        DECIMAL(5,4),
    new_score        DECIMAL(5,4),
    delta            DECIMAL(5,4),
    depth            INT NOT NULL,
    path             UUID[] NOT NULL
);
CREATE INDEX idx_ci_event ON cascade_impacts(cascade_event_id);

CREATE TABLE proposition_closure (
    ancestor_id   UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    descendant_id UUID NOT NULL REFERENCES propositions(id) ON DELETE CASCADE,
    depth         INT NOT NULL,
    PRIMARY KEY(ancestor_id, descendant_id)
);


-- ============================================================
-- 12. COMPUTATION FUNCTIONS（決定論的計算）
-- ============================================================

-- 構造的健全性 v2（プラットフォームの価値判断を含まない）
CREATE OR REPLACE FUNCTION compute_structural_soundness_v2(interp_id UUID)
RETURNS DECIMAL(5,4) AS $$
DECLARE
    weighted_score DECIMAL;
    premise_count  INT;
    base_val       DECIMAL;
    log_coeff      DECIMAL;
    result         DECIMAL;
BEGIN
    SELECT value INTO base_val FROM system_parameters WHERE key = 'structural_no_premise_base';
    SELECT value INTO log_coeff FROM system_parameters WHERE key = 'structural_premise_log_coeff';

    SELECT
        COALESCE(SUM(ip.weight * GREATEST(0, COALESCE(pc.propagated_score, pc.local_score, 0)))
                 / NULLIF(SUM(ip.weight), 0), 0),
        COUNT(*)
    INTO weighted_score, premise_count
    FROM interpretation_premises ip
    LEFT JOIN plausibility_cache pc ON pc.proposition_id = ip.proposition_id
    WHERE ip.interpretation_id = interp_id;

    IF premise_count = 0 THEN
        result := base_val;
    ELSE
        result := weighted_score * (1.0 + log_coeff * ln(premise_count::DECIMAL));
    END IF;

    RETURN GREATEST(0.0, LEAST(1.0, result));
END;
$$ LANGUAGE plpgsql STABLE;

-- 反駁耐性
CREATE OR REPLACE FUNCTION compute_refutation_resilience(interp_id UUID)
RETURNS DECIMAL(5,4) AS $$
DECLARE
    total_reb   INT;
    active_reb  INT;
    addr_reb    INT;
    attack_sum  DECIMAL;
    survival    DECIMAL;
    bonus       DECIMAL;
    result      DECIMAL;
BEGIN
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE status = 'active'),
           COUNT(*) FILTER (WHERE status = 'addressed')
    INTO total_reb, active_reb, addr_reb
    FROM interpretation_rebuttals WHERE target_interpretation_id = interp_id;

    IF total_reb = 0 THEN RETURN 0.5; END IF;

    SELECT COALESCE(SUM(compute_structural_soundness_v2(rebuttal_interpretation_id)), 0)
    INTO attack_sum
    FROM interpretation_rebuttals
    WHERE target_interpretation_id = interp_id AND status = 'active';

    survival := GREATEST(0.0,
        1.0 - (attack_sum / GREATEST(active_reb, 1)::DECIMAL)
              * (active_reb::DECIMAL / GREATEST(total_reb, 1)::DECIMAL));
    bonus := 1.0 + LEAST(0.3, addr_reb::DECIMAL * 0.05);
    result := survival * bonus;

    RETURN GREATEST(0.0, LEAST(1.0, result));
END;
$$ LANGUAGE plpgsql STABLE;

-- 解釈の信頼度（2層統合）
CREATE OR REPLACE FUNCTION compute_interpretation_reliability(interp_id UUID)
RETURNS DECIMAL(5,4) AS $$
DECLARE
    w1 DECIMAL; w2 DECIMAL;
BEGIN
    SELECT value INTO w1 FROM system_parameters WHERE key = 'reliability_structural_weight';
    SELECT value INTO w2 FROM system_parameters WHERE key = 'reliability_resilience_weight';
    RETURN GREATEST(0.0, LEAST(1.0,
        compute_structural_soundness_v2(interp_id) * w1
        + compute_refutation_resilience(interp_id) * w2
    ));
END;
$$ LANGUAGE plpgsql STABLE;

-- 命題のもっともらしさ（クラスタベース・最終版）
CREATE OR REPLACE FUNCTION compute_plausibility_final(p_id UUID)
RETURNS DECIMAL(5,4) AS $$
DECLARE
    log_base DECIMAL;
    result   DECIMAL;
BEGIN
    SELECT value INTO log_base FROM system_parameters WHERE key = 'cluster_plausibility_log_base';

    SELECT COALESCE(
        SUM(
            compute_interpretation_reliability(ic.centroid_interp_id)
            * ln(1.0 + ic.member_count) / ln(log_base)
            * CASE ic.dominant_stance
                WHEN 'agree' THEN 1.0 WHEN 'disagree' THEN -1.0
                WHEN 'uncertain' THEN 0.0 WHEN 'conditional' THEN 0.5
                WHEN 'reinterpret' THEN 0.0 END
        ) / NULLIF(SUM(ln(1.0 + ic.member_count) / ln(log_base)), 0),
        0
    ) INTO result
    FROM interpretation_clusters ic
    WHERE ic.proposition_id = p_id AND ic.member_count > 0;

    RETURN GREATEST(-1.0, LEAST(1.0, result));
END;
$$ LANGUAGE plpgsql STABLE;

-- 前提脆弱性スコア
CREATE OR REPLACE FUNCTION compute_fragility(p_id UUID)
RETURNS DECIMAL(5,4) AS $$
DECLARE
    agree_r DECIMAL; disagree_r DECIMAL; cond_r DECIMAL;
    total   INT; variance_s DECIMAL; result DECIMAL;
BEGIN
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE stance='agree')::DECIMAL / NULLIF(COUNT(*),0),
           COUNT(*) FILTER (WHERE stance='disagree')::DECIMAL / NULLIF(COUNT(*),0),
           COUNT(*) FILTER (WHERE stance='conditional')::DECIMAL / NULLIF(COUNT(*),0)
    INTO total, agree_r, disagree_r, cond_r
    FROM interpretations WHERE target_type='proposition' AND target_id=p_id;

    IF total = 0 THEN RETURN 1.0; END IF;

    variance_s := 4.0 * agree_r * disagree_r;
    result := variance_s * (1.0 + cond_r) * (1.0 / ln(total + 2.0));
    RETURN GREATEST(0.0, LEAST(1.0, result));
END;
$$ LANGUAGE plpgsql STABLE;

-- 下流命題の取得
CREATE OR REPLACE FUNCTION get_downstream_propositions(p_id UUID)
RETURNS TABLE(proposition_id UUID, relation_id UUID, rel_type relation_type) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT rm_c.proposition_id, r.id, r.type
    FROM relation_members rm_p
    JOIN relations r ON r.id = rm_p.relation_id
    JOIN relation_members rm_c ON rm_c.relation_id = r.id AND rm_c.role = 'conclusion'
    WHERE rm_p.proposition_id = p_id AND rm_p.role = 'premise';
END;
$$ LANGUAGE plpgsql STABLE;

-- 前提脆弱性マップ
CREATE OR REPLACE FUNCTION get_premise_fragility_map(target_id UUID, max_depth INT DEFAULT 5)
RETURNS TABLE(
    prop_id UUID, content TEXT, prop_type proposition_type,
    depth INT, frag_score DECIMAL, local_p DECIMAL, propagated_p DECIMAL,
    interp_count INT, path UUID[]
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE tree AS (
        SELECT rm_p.proposition_id AS pid, 1 AS d,
               ARRAY[target_id, rm_p.proposition_id] AS p
        FROM relation_members rm_c
        JOIN relations r ON r.id = rm_c.relation_id
        JOIN relation_members rm_p ON rm_p.relation_id = r.id AND rm_p.role = 'premise'
        WHERE rm_c.proposition_id = target_id AND rm_c.role = 'conclusion'
          AND r.type IN ('support','causation','specialization','composition')
        UNION
        SELECT rm_p.proposition_id, t.d + 1, t.p || rm_p.proposition_id
        FROM tree t
        JOIN relation_members rm_c ON rm_c.proposition_id = t.pid AND rm_c.role = 'conclusion'
        JOIN relations r ON r.id = rm_c.relation_id
        JOIN relation_members rm_p ON rm_p.relation_id = r.id AND rm_p.role = 'premise'
        WHERE t.d < max_depth
          AND r.type IN ('support','causation','specialization','composition')
          AND NOT rm_p.proposition_id = ANY(t.p)
    )
    SELECT DISTINCT ON (t.pid)
        t.pid, pr.content, pr.type, t.d,
        COALESCE(pc.fragility_score, compute_fragility(t.pid)),
        COALESCE(pc.local_score, 0::DECIMAL),
        COALESCE(pc.propagated_score, 0::DECIMAL),
        COALESCE(pc.interpretation_count, 0),
        t.p
    FROM tree t
    JOIN propositions pr ON pr.id = t.pid
    LEFT JOIN plausibility_cache pc ON pc.proposition_id = t.pid
    ORDER BY t.pid, t.d ASC;
END;
$$ LANGUAGE plpgsql STABLE;
