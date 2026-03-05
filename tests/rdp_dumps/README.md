# RDP Dump Corpus (Local)

This directory is the default corpus location for `emu.dump.*` tests.

- Committed baseline fixture:
  - `baseline_minimal_eof.rdp` (tiny smoke fixture; header + EOF)
- Local captures:
  - place under `tests/rdp_dumps/local/` (ignored by Git)

Quick flow:

```bash
./run-dump-tests.sh --provision-validator
```

This will:

1. Build `rdp-validate-dump` if it is not already available.
2. Run `ctest -R emu.dump` through `run-tests.sh` using the committed baseline fixture.

Optional local capture flow:

```bash
./run-dump-tests.sh --provision-validator --dump-dir tests/rdp_dumps/local --capture-if-missing
```

Requirements:

- `parallel_n64_libretro.so` built with `HAVE_RDP_DUMP=1`
- RetroArch binary at `/home/auro/code/mupen/RetroArch-upstream/retroarch`
- ROM available at `/home/auro/code/n64_roms/Paper Mario (USA).zip` (default capture target)
