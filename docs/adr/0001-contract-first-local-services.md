# ADR 0001: Contract-first local services

- Status: Accepted
- Date: 2026-07-29

## Context

Aurisia needs replaceable perception modules and local crash isolation without
requiring cloud infrastructure. Desktop and mobile impose different process
constraints.

## Decision

Services exchange versioned `aurisia.v1` Protobuf messages. Domain code uses
immutable equivalents with no model SDK types. Desktop services will run as
supervised local processes; deterministic tests and mobile hosts may compose
the same services in-process.

No service may import another service implementation.

## Consequences

Model and transport replacements do not affect consumers. We accept explicit
mapping at transport boundaries and maintain compatibility tests for schemas.
