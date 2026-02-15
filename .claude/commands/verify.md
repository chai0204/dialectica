# Full Project Verification

Run the complete verification suite for the Dialectica project. This checks all layers: backend, frontend, and code quality.

## Verification Steps

Execute the following checks in order. Stop and report on the first failure.

### 1. Backend Checks
```bash
# Compile check
cd backend && cargo check 2>&1

# Linting (deny all warnings)
cd backend && cargo clippy -- -D warnings 2>&1

# Format check
cd backend && cargo fmt -- --check 2>&1

# Run tests
cd backend && cargo test 2>&1
```

### 2. Frontend Checks
```bash
# TypeScript compilation
cd frontend && npx tsc --noEmit 2>&1

# Linting
cd frontend && npm run lint 2>&1

# Build
cd frontend && npm run build 2>&1
```

### 3. Code Quality Audit
After running the above, also check:

- Search for `unwrap()` or `expect()` in `backend/src/` (excluding test files)
- Search for `println!` in `backend/src/`
- Search for `console.log` in `frontend/src/`
- Search for `format!("SELECT` or `format!("INSERT` in `backend/src/` (SQL injection risk)
- Check all `.rs` files are under 800 lines
- Check all `.ts`/`.tsx` files are under 800 lines

### 4. Report Results

```
## Verification Report

| Check            | Result |
|------------------|--------|
| cargo check      | PASS/FAIL |
| cargo clippy     | PASS/FAIL |
| cargo fmt        | PASS/FAIL |
| cargo test       | PASS/FAIL |
| tsc --noEmit     | PASS/FAIL |
| npm run lint     | PASS/FAIL |
| npm run build    | PASS/FAIL |
| Code quality     | PASS/FAIL |

Overall: [PASS / FAIL]
```

If any check fails, list the specific errors and suggest fixes.
