# Database Migration Helper

Assist with creating and managing SQLx database migrations for the Dialectica project.

## Context

- **Database**: PostgreSQL 16 + pgvector + PGroonga
- **ORM**: SQLx with compile-time verified queries
- **Extensions**: uuid-ossp, vector (pgvector), pgroonga
- **Schema**: See `doc/er_diagram.mermaid` and `doc/core_schema.sql` for full design

## Migration Rules

1. **Reversible**: Every migration should be reversible when possible
2. **Atomic**: Each migration addresses one logical change
3. **Naming**: `YYYYMMDDHHMMSS_description.sql` format
4. **No data loss**: Never drop columns/tables without a data migration plan
5. **Indexes**: Always add appropriate indexes for query patterns
6. **PGroonga**: Use PGroonga indexes for Japanese text columns

## Process

### Step 1: Understand the Change
- What entities are being added/modified?
- Check `doc/er_diagram.mermaid` for the target schema
- Identify affected queries and repositories

### Step 2: Write the Migration
```bash
# Create migration file
cd backend && sqlx migrate add <description>
```

### Step 3: Common Patterns

#### New Table with UUID Primary Key
```sql
CREATE TABLE IF NOT EXISTS entity_name (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- columns here
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update trigger
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON entity_name
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

#### Vector Embedding Column
```sql
ALTER TABLE entity_name
ADD COLUMN content_embedding vector(768);

-- Index for similarity search (IVFFlat for large datasets)
CREATE INDEX idx_entity_name_embedding
ON entity_name USING ivfflat (content_embedding vector_cosine_ops)
WITH (lists = 100);
```

#### PGroonga Full-Text Search Index
```sql
CREATE INDEX idx_entity_name_content_pgroonga
ON entity_name USING pgroonga (content)
WITH (tokenizer='TokenMecab');
```

#### Foreign Key Relationship
```sql
ALTER TABLE child_table
ADD COLUMN parent_id UUID NOT NULL REFERENCES parent_table(id) ON DELETE CASCADE;
```

### Step 4: Apply and Test
```bash
# Apply migration (requires running DB)
cd backend && sqlx migrate run

# Verify schema
docker compose exec db psql -U app -d knowledge_graph -c '\dt'

# Run tests
cd backend && cargo test
```

$ARGUMENTS
