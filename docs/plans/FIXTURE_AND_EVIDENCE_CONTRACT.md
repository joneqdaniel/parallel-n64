# Fixture And Evidence Contract

## Fixture Identity

Each fixture is defined by:

- fixture manifest
- ROM identity
- savestate identity when available
- config snapshot
- expected capture points

## Fixture Authority

- early ladder work may use debug warps or scripted entry
- authoritative fixtures should become savestate-backed as soon as possible
- the steady-state fixture path is authoritative savestate -> settle 3 frames -> capture
- controller input is the bootstrap path for minting or replacing authoritative savestates

## Required Evidence Bundle Contents

- final frame capture or screenshot
- fixture identity
- feature/config snapshot
- ROM hash
- savestate hash when present
- hi-res pack hash when present
- log output relevant to the run
- replacement hit/miss or fallback reporting when present

## Primary Pass/Fail Signals

- corruption is always fail
- expected explicit fallback is acceptable when the phase claims it
- visual output is the primary signal
- traces, logs, and telemetry explain why the output happened

## Evidence Rules

- every bundle should be comparable over long periods of time
- evidence should be lightweight enough to collect on every important run
- evidence should combine final output with a small amount of intermediate state, not one or the other alone
