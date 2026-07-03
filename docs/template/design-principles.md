# Design principles

> Template-product documentation — removed from your copy by the bootstrap de-template step.

These principles decided every file in this repository. When proposing a change to the template, argue from them.

1. **Convention over configuration.** One good default beats three options. Alternatives are documented (see ADR "Alternatives considered" sections), not shipped.
2. **GitHub-native before third-party.** Native issue types, native sub-issues, native rulesets, Projects v2. A third-party tool must clear a high bar: solve something GitHub genuinely cannot.
3. **Every file justifies its maintenance cost.** If a file stops earning its keep, it gets deleted. The [architecture ledger](architecture.md) records what each piece is for.
4. **One home per fact.** Metadata (ADR-0003), documentation (`skills/docs-hygiene/`), configuration — duplicate homes always drift.
5. **Logic in the Makefile, not workflows.** Adopters customize `make` targets; workflow YAML stays untouched and upgradable.
6. **The template obeys its own rules.** Its CI is the CI it ships; its issues use its own forms; its releases use its own flow. Dogfooding is the drift detector.
7. **AI agents are first-class, humans stay in control.** Agents get a self-service queue (`agent-ok`), clear capability boundaries, and an audit trail (`by-agent`); humans gate merges, releases, and destructive operations.
8. **Ratchets over cleanup.** Label budgets, workflow-count budgets, handoff caps — prevention mechanisms, because every failure mode this template guards against is cheap to prevent and expensive to undo (see `skills/anti-patterns/`).
