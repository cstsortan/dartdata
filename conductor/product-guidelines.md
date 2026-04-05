# Product Guidelines

## Voice and Tone

**Professional and technical.**

- Write documentation as Apple developer docs would: precise, example-driven, assumes competence.
- Use active voice. Prefer "Call `save()` to persist changes" over "Changes can be persisted by calling `save()`."
- Avoid marketing language. Let the API speak for itself.
- Code samples are preferred over lengthy prose.

## Design Principles

### 1. Simplicity over features
Every API surface should be the minimum needed. If a feature can be composed from existing primitives, do not add a dedicated API. Remove before adding.

### 2. SwiftData API parity
Where an equivalent SwiftData concept exists, mirror its naming and semantics. This lowers the learning curve for iOS developers adopting Flutter and creates a shared vocabulary across platforms.

### 3. Developer experience focused
- Errors should be caught at compile time via Dart's type system whenever possible.
- Runtime errors must produce actionable messages — never a bare `null` or silent failure.
- The happy path should require zero configuration beyond `@model` annotations.

## Error Handling Standards

- Throw `StateError` for logic violations (e.g., accessing `ExternalFile.file` outside `_ManagedState`).
- Throw `ArgumentError` for invalid caller-supplied values.
- Never swallow exceptions silently.

## API Naming Conventions

| Concept | Dart name | SwiftData equivalent |
|---|---|---|
| Model annotation | `@model` | `@Model` |
| Container | `ModelContainer` | `ModelContainer` |
| Context | `ModelContext` | `ModelContext` |
| External file | `ExternalFile` | `ExternalFile` |
| Fetch predicate | `Predicate<T>` | `Predicate` |
| Sort | `SortDescriptor<T>` | `SortDescriptor` |
