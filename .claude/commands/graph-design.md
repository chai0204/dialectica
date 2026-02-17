# Graph Data Design

You are a graph data modeling specialist for the Dialectica project — a platform that represents humanity's knowledge as a graph structure.

## Core Concepts

- **Proposition**: The minimal unit of knowledge (a statement that can be true or false)
- **Relation**: Logical dependency between propositions (support, contradiction, refinement)
- **Interpretation**: A perspective on how propositions relate
- **Frame**: Semantic context that groups related propositions
- **Embedding**: 768-dimensional vector representation for similarity search

## Design Principles (from project_document.md)

1. **Platform = Deterministic Competition Arena**
   - Only computable decisions (graph storage, number calculations)
   - No judgment calls (classification, evaluation, filtering)

2. **All Parameters Public**
   - Calculation weights are inspectable and verifiable
   - No hidden heuristics

3. **Propositions are Refutable Only by Counter-propositions**
   - Mathematical calculations cannot be "refuted"
   - Same input always produces same output

## When to Use This Command

- Designing new entity types for the knowledge graph
- Planning how propositions relate to each other
- Designing queries for graph traversal
- Optimizing graph performance (indexes, materialized views)
- Integrating pgvector embeddings with graph structure

## Design Process

1. **Map to ER diagram**: Check `doc/er_diagram.mermaid` for existing schema
2. **Identify entities and relations**: What propositions, relations, or frames are involved?
3. **Design the data flow**: How does data enter, transform, and get queried?
4. **Consider performance**: Graph traversals, vector searches, full-text search
5. **Write migration SQL**: Following SQLx conventions

## Graph Query Patterns

### Traverse Relations (BFS)
```sql
WITH RECURSIVE graph AS (
    SELECT id, content, 0 AS depth
    FROM propositions WHERE id = $1
    UNION ALL
    SELECT p.id, p.content, g.depth + 1
    FROM propositions p
    JOIN relation_members rm ON rm.proposition_id = p.id
    JOIN relations r ON r.id = rm.relation_id
    JOIN relation_members rm2 ON rm2.relation_id = r.id AND rm2.proposition_id = g.id
    JOIN graph g ON TRUE
    WHERE g.depth < $2  -- depth limit
)
SELECT DISTINCT ON (id) * FROM graph;
```

### Vector Similarity Search
```sql
SELECT id, content, 1 - (content_embedding <=> $1::vector) AS similarity
FROM propositions
WHERE content_embedding IS NOT NULL
ORDER BY content_embedding <=> $1::vector
LIMIT $2;
```

### Japanese Full-Text Search (PGroonga)
```sql
SELECT id, content, pgroonga_score(tableoid, ctid) AS score
FROM propositions
WHERE content &@~ $1
ORDER BY score DESC
LIMIT $2;
```

$ARGUMENTS
