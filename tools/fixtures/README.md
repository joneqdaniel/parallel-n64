# Fixture Manifests

This directory holds versioned metadata for deterministic test fixtures.

The manifests here describe:

- which game or content is under test
- how to reach the target scene
- what external assets or states are required
- what outputs should be captured
- what checks define success or failure

Large binary assets stay outside git.
Reference them by stable local paths or environment variables instead of committing them here.

Use [`fixture-template.yaml`](/home/auro/code/parallel-n64/tools/fixtures/fixture-template.yaml) as the starting point for new fixture definitions.
Follow the shared scenario runtime model in [tools/scenarios/MODEL.md](/home/auro/code/parallel-n64/tools/scenarios/MODEL.md) when deciding whether a fixture is steady-state authoritative or bootstrap-driven.

Current tracked fixture seeds:

- [`paper-mario-title-screen.yaml`](/home/auro/code/parallel-n64/tools/fixtures/paper-mario-title-screen.yaml)
- [`paper-mario-file-select.yaml`](/home/auro/code/parallel-n64/tools/fixtures/paper-mario-file-select.yaml)
- [`paper-mario-authority-graph.yaml`](/home/auro/code/parallel-n64/tools/fixtures/paper-mario-authority-graph.yaml)
