# Changelog

## [0.5.3](https://github.com/TzuH-Hsu/github-project-os/compare/v0.5.2...v0.5.3) (2026-09-21)


### Bug Fixes

* the PR lint can read the linked issue on a private repository ([#76](https://github.com/TzuH-Hsu/github-project-os/issues/76)) ([7eb2dc0](https://github.com/TzuH-Hsu/github-project-os/commit/7eb2dc00f92cca6e8be210e9cbdf83f7f9b1dcb4))

## [0.5.2](https://github.com/TzuH-Hsu/github-project-os/compare/v0.5.1...v0.5.2) (2026-09-16)


### Documentation

* hidden commit types ship no release; refactor is one of them ([#71](https://github.com/TzuH-Hsu/github-project-os/issues/71)) ([819ce60](https://github.com/TzuH-Hsu/github-project-os/commit/819ce6057dbd1fa459ffbfd200c2aca861e50cec))

## [0.5.1](https://github.com/TzuH-Hsu/github-project-os/compare/v0.5.0...v0.5.1) (2026-09-16)


### Bug Fixes

* the labeler test no longer assumes area:ci exists in the repository's labels.yml ([#67](https://github.com/TzuH-Hsu/github-project-os/issues/67)) ([eafbfd6](https://github.com/TzuH-Hsu/github-project-os/commit/eafbfd60a9ac3fa9b15d1ac8834d34d61f5b6608))

## [0.5.0](https://github.com/TzuH-Hsu/github-project-os/compare/v0.4.1...v0.5.0) (2026-09-16)


### Features

* issue labeler logic moves to scripts/issue-labeler.js with a durable test ([#63](https://github.com/TzuH-Hsu/github-project-os/issues/63)) ([f464cfb](https://github.com/TzuH-Hsu/github-project-os/commit/f464cfb0b3feb7e99fc33b0da742dfdf10a20691))

## [0.4.1](https://github.com/TzuH-Hsu/github-project-os/compare/v0.4.0...v0.4.1) (2026-09-16)


### Bug Fixes

* de-template empties CHANGELOG.md instead of seeding it ([#57](https://github.com/TzuH-Hsu/github-project-os/issues/57)) ([86d505f](https://github.com/TzuH-Hsu/github-project-os/commit/86d505f4c7a52aecf3ec8a5effab0e1fb5d87aac))

## [0.4.0](https://github.com/TzuH-Hsu/github-project-os/compare/v0.3.1...v0.4.0) (2026-09-15)


### Features

* make check fails when the issue forms or the labeler disagree with labels.yml ([#50](https://github.com/TzuH-Hsu/github-project-os/issues/50)) ([22cc535](https://github.com/TzuH-Hsu/github-project-os/commit/22cc53521264e5371e5e94fc4956a1196804c58e))


### Bug Fixes

* issue labeler reads the area:* allowlist from labels.yml instead of a hardcoded list ([#48](https://github.com/TzuH-Hsu/github-project-os/issues/48)) ([3371cd1](https://github.com/TzuH-Hsu/github-project-os/commit/3371cd11ac375df7992f10ed0db29126faa62ee3))

## [0.3.1](https://github.com/TzuH-Hsu/github-project-os/compare/v0.3.0...v0.3.1) (2026-09-15)


### Bug Fixes

* phase 2 probes GraphQL so personal accounts are reported as lacking native issue types ([#43](https://github.com/TzuH-Hsu/github-project-os/issues/43)) ([d16f465](https://github.com/TzuH-Hsu/github-project-os/commit/d16f4657e57a3ef894d3bfa07a162169a1ff16f8))

## [0.3.0](https://github.com/TzuH-Hsu/github-project-os/compare/v0.2.0...v0.3.0) (2026-09-15)


### Features

* bootstrap phase 6 reports and offers repository security settings ([#27](https://github.com/TzuH-Hsu/github-project-os/issues/27)) ([8a62e5c](https://github.com/TzuH-Hsu/github-project-os/commit/8a62e5c0595133ed478276b2beb35c5268aa9922))
* bootstrap phase 9 requires an explicit licence choice ([#29](https://github.com/TzuH-Hsu/github-project-os/issues/29)) ([9465360](https://github.com/TzuH-Hsu/github-project-os/commit/9465360ec5b5a9d2359f33392311750558aed7c9))
* retire the agent-ok and by-agent label mechanism ([#37](https://github.com/TzuH-Hsu/github-project-os/issues/37)) ([bd8258d](https://github.com/TzuH-Hsu/github-project-os/commit/bd8258db4eb28f04516b0fbd7fa742fdccb9fbe8)), closes [#36](https://github.com/TzuH-Hsu/github-project-os/issues/36)
* runner selection moves to the RUNNER_LABELS repository variable ([#32](https://github.com/TzuH-Hsu/github-project-os/issues/32)) ([02542da](https://github.com/TzuH-Hsu/github-project-os/commit/02542da1ee049c805e3acdc949de9887393aa7aa))
* ship the coarse-Type fallback labels as a commented-out opt-in ([#34](https://github.com/TzuH-Hsu/github-project-os/issues/34)) ([4d06dc1](https://github.com/TzuH-Hsu/github-project-os/commit/4d06dc1dbdeda07b644ed49659da6561c7cbab85))


### Bug Fixes

* bootstrap phase 5 sets four repository settings left at GitHub defaults ([#25](https://github.com/TzuH-Hsu/github-project-os/issues/25)) ([91bb54a](https://github.com/TzuH-Hsu/github-project-os/commit/91bb54a66ce86c1dd9796a899f18e0db2bca4c12)), closes [#24](https://github.com/TzuH-Hsu/github-project-os/issues/24)
* pin adopters' first release to v0.1.0 with initial-version ([#39](https://github.com/TzuH-Hsu/github-project-os/issues/39)) ([06662a5](https://github.com/TzuH-Hsu/github-project-os/commit/06662a5605ccfeee28215a5dfa1c92b20bea7dbb)), closes [#38](https://github.com/TzuH-Hsu/github-project-os/issues/38)
* stop the issue labeler stripping hand-added type:* labels ([#20](https://github.com/TzuH-Hsu/github-project-os/issues/20)) ([61b4cc3](https://github.com/TzuH-Hsu/github-project-os/commit/61b4cc3eb45c2038c275177a6ede7121389365f1))

## [0.2.0](https://github.com/TzuH-Hsu/github-project-os/compare/v0.1.0...v0.2.0) (2026-07-04)


### Features

* bootstrap sets Project Status options via GraphQL on newly created projects ([#6](https://github.com/TzuH-Hsu/github-project-os/issues/6)) ([515f78a](https://github.com/TzuH-Hsu/github-project-os/commit/515f78ab646bd2644b80c4a0b69d09fc12e9fa58))

## 0.1.0 (2026-07-03)


### Features

* idempotent bootstrap script (labels, project, settings, ruleset, de-template) ([79c71d8](https://github.com/TzuH-Hsu/github-project-os/commit/79c71d8c4a0bc25fc54de8da6855dd8622dbf6c2))
* issue forms, PR template, CODEOWNERS, dependabot, branch ruleset ([f315fe3](https://github.com/TzuH-Hsu/github-project-os/commit/f315fe301a38905effc7b587c9113428bcbd0e70))
* metadata single-home contract and declarative labels ([241d071](https://github.com/TzuH-Hsu/github-project-os/commit/241d0717c5d8495520747e6d46d40730483bd9d7))
* repo self-consistency checks (skills index, local-md hygiene) ([6457f87](https://github.com/TzuH-Hsu/github-project-os/commit/6457f8725512df0335ab601c2e28484f68dbbe1e))
* skills knowledge system (15 skills, catalog, AGENTS.md index) ([6ab52bd](https://github.com/TzuH-Hsu/github-project-os/commit/6ab52bd2224f6d46df0327688929fe2cf4624126))


### Bug Fixes

* bootstrap autorelease prune exclusion, gh api 404 detection, personal-account type docs ([0f912c0](https://github.com/TzuH-Hsu/github-project-os/commit/0f912c0c5ebb0a6bb7aa39aa6c185f4f0bc640ed))
