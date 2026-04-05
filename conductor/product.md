# Product Definition

## Project Name

dartdata

## Description

A Flutter persistence library inspired by Apple's SwiftData that lets you annotate models and query with type safety — no SQL required.

## Problem Statement

Flutter developers have no SwiftData-equivalent — they're forced to write raw SQL or use heavy ORMs with poor type safety.

## Target Users

Flutter/Dart developers building mobile or desktop apps who want SwiftData-style persistence.

## Key Goals

1. **Type-safe queries** — predicates and sort descriptors expressed in Dart with full type checking; no raw SQL strings.
2. **Zero SQL boilerplate** — `@model` annotation + code generation handles all DDL and CRUD mapping.
3. **SwiftData-compatible mental model** — `ModelContainer`, `ModelContext`, `@model`, `@attribute`, `@relationship` mirror Apple's SwiftData API so iOS developers feel at home.

## Out of Scope

- Flutter Web (no `dart:io`, no file-based SQLite).
- Cloud sync or remote backends.
- Dart macros (build_runner + source_gen only).
