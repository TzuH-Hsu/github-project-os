# ADR-0004: The adopter's licence is an explicit bootstrap decision

- **Status**: Accepted
- **Date**: 2026-09-02

## Context

A repository created from this template starts out carrying the template's own `LICENSE`: MIT, copyright the template author. De-templating rewrote `README.md`, `CHANGELOG.md` and the release-please manifest, and removed `docs/template/` — but never touched `LICENSE`. Nothing in the script mentioned licensing at all.

For an open-source adopter that is a wrong copyright line. For an adopter doing client or commissioned work it is considerably worse: MIT is an irrevocable, written grant of the right to use, modify, publish, distribute, sublicense and sell, made to the whole world. A commission agreement typically transfers copyright on final payment; an MIT file in the delivered repository grants far more than that, to more people, before payment, and cannot be withdrawn. It removes the leverage the payment clause was built on. The field report that prompted this ADR came from an adopter who shipped four private client repositories that way.

The obvious fix — rewrite the copyright line to the adopter — is itself a defect. Substantial portions of the template ship verbatim in every adopted repository, and MIT requires its copyright and permission notice to be included with them. Rewriting that line deletes the only copy of the notice from the repository, trading a licensing mistake for a licence violation.

## Decision

Bootstrap gains **phase 9 — Licence**, before de-template, forcing an explicit choice: MIT under the adopter's name, a proprietary all-rights-reserved notice, or an explicit defer.

1. **The phase runs before de-template and is not gated by `--keep-template-docs`.** De-template returns early for three unrelated reasons; folding the licence step into it would let any of them silently swallow the decision. Running first also means an aborted run fails into the safe state.
2. **There is no default, and a closed stdin defers.** `confirm()` treats a closed stdin as "take the default", which here would mean silently shipping the template author's MIT — the original bug with extra steps.
3. **`--yes` never writes a licence.** It defers and files the decision as the first remaining manual step, visually marked. This is the one place where the script declines to act on `--yes`.
4. **Attribution is unconditional.** Every answer that writes `LICENSE` also writes `NOTICE`, carrying the template's MIT notice. The MIT-keep path needs it exactly as much as the proprietary path.
5. **Attribution goes in `NOTICE`, never inside `LICENSE`.** A `LICENSE` containing both an all-rights-reserved notice and a verbatim MIT grant is ambiguous about what a client is receiving, and a client's counsel reads `LICENSE` and nothing else.
6. **The script ships exactly two licence bodies.** Anything else is the defer answer with a pointer to SPDX.
7. **`LICENSE` is regenerated from a seed, not patched with `sed`.** Holder names legitimately contain `&` and `/`, both `sed` replacement metacharacters.

## Consequences

- One more interactive prompt in an already long run, and it is the one prompt that cannot be safely skimmed.
- Adopters carry a `NOTICE` file. Licence scanners find it, which is useful when a client runs an open-source audit on delivery.
- The template must keep `TEMPLATE_COPYRIGHT_HOLDER` and `TEMPLATE_COPYRIGHT_YEAR` in sync with its own `LICENSE`. If they drift, the phase stops recognising its own licence and silently does nothing — the original defect, with no symptom. `scripts/check-license-marker.sh` turns that into a red build.
- The proprietary body is an example and says so on its face, with a self-removing trailer the adopter deletes after counsel review.
- The template now takes a position on adopters' licensing. It is a prompt, not a policy: every answer including "leave it alone" is available.

## Alternatives considered

- **Rewrite only the copyright line.** Manufactures an MIT violation by deleting the notice. Rejected outright.
- **Delete `LICENSE` during de-templating.** An unlicensed repository is "all rights reserved" by default in most jurisdictions, which is arguably the safest state — but it reads as an oversight rather than a decision, and breaks GitHub's licence detection. Rejected.
- **Ship more licence bodies (Apache-2.0, GPL, MPL).** Kilobytes of legal text the maintainer cannot meaningfully maintain, and any set of three is arbitrary. Rejected in favour of pointing at SPDX.
- **Attribution as a comment block inside the new `LICENSE`.** Creates grant ambiguity in the one file people actually read. Rejected.
- **Attribution in the README.** Does not survive editorial churn, and phase 10 replaces the file wholesale. Rejected.
- **A `docs/template/LICENSE.proprietary.example` file.** Under `--yes` the phase writes nothing and files a manual step, and phase 10 then removes `docs/template/` — deleting the example in the very run that told the adopter to read it. The text lives as a script constant and in `docs/setup/licensing.md` instead. Rejected.
- **Do nothing; document it in the README.** The failure mode is silent and the cost is legal. A paragraph nobody reads is not a mitigation. Rejected.
