# Workflow

## TDD Policy: Strict

All implementation follows the **Red → Green → Refactor** cycle:

1. **Red** — write a failing test in `dartdata/test/` that describes the desired behavior.
2. **Green** — write the minimum implementation code to make the test pass. No gold-plating.
3. **Refactor** — clean up without breaking tests.

**No implementation code may be written without a failing test that justifies it.**

Tests live in `dartdata/test/`. Run the suite from inside the package:

```bash
cd dartdata
flutter test                          # all tests
flutter test test/model_context_test.dart  # single file
flutter test --coverage               # with coverage
```

For pure Dart integration tests (no Flutter engine), use `dart test` from the `dartdata/` directory.

## Commit Strategy: Conventional Commits

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

### Types

| Type | When to use |
|---|---|
| `feat` | New feature or API addition |
| `fix` | Bug fix |
| `test` | Adding or correcting tests |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `chore` | Build, tooling, dependency updates |
| `docs` | Documentation only |
| `perf` | Performance improvement |

### Examples

```
feat(context): add fetchCount method to ModelContext
fix(external-file): throw StateError when accessing file in pending deletion state
test(container): add WAL mode verification test
chore: upgrade sqlite3 to 2.4.0
```

## Code Review Policy

**All changes require code review before merge.**

- Open a pull request for every change, including small fixes.
- Self-review of diff is the minimum; external review strongly preferred.
- PR description must reference the track/task being addressed.
- All tests must pass before review is requested.

## Verification Checkpoints

Manual verification is required **at track completion**:

1. All tests pass (`flutter test` with zero failures).
2. Coverage has not regressed.
3. Public API matches the intended design (check against `dartdata.dart` barrel export).
4. Generated code (`.g.dart`) is up to date (`dart run build_runner build`).
5. CHANGELOG updated if public API changed.

## Task Lifecycle

```
pending → in_progress → review → complete
                      ↘ blocked
```

- A task is **in_progress** when the first test for it is written (Red phase started).
- A task is **review** when implementation is complete and tests pass.
- A task is **complete** after verification checkpoint passes.

## Branch Strategy

- `main` — stable, always passing tests
- Feature branches: `feat/<track-id>-<short-description>`
- Fix branches: `fix/<issue-short-description>`
