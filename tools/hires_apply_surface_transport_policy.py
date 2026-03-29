#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def main() -> int:
    parser = argparse.ArgumentParser(description='Apply tracked surface transport alias policy to a surface package.')
    parser.add_argument('--surface-package', required=True, help='Input phrs-surface-package JSON path.')
    parser.add_argument('--policy', required=True, help='Surface transport policy JSON path.')
    parser.add_argument('--output', required=True, help='Output surface package JSON path.')
    args = parser.parse_args()

    surface_path = Path(args.surface_package)
    policy_path = Path(args.policy)
    output_path = Path(args.output)

    data = load_json(surface_path)
    policy = load_json(policy_path)
    surface_aliases = policy.get('surface_aliases', {})

    for record in data.get('surfaces', []):
        surface = record.get('surface', {})
        surface_id = surface.get('surface_id')
        alias_cfg = surface_aliases.get(surface_id)
        if not alias_cfg:
            continue

        slots = surface.get('slots', [])
        replacement_ids = list(surface.get('replacement_ids', []))
        unresolved = list(surface.get('unresolved_sequences', []))
        unresolved_by_index = {item['sequence_index']: item for item in unresolved}
        applied = []

        for slot_index_str, alias in alias_cfg.get('slot_aliases', {}).items():
            slot_index = int(slot_index_str)
            if slot_index < 0 or slot_index >= len(slots):
                raise SystemExit(f'{surface_id}: slot {slot_index} out of range')
            replacement_id = alias['replacement_id']
            slots[slot_index]['replacement_id'] = replacement_id
            if replacement_id not in replacement_ids:
                replacement_ids.append(replacement_id)
            unresolved_by_index.pop(slot_index, None)
            applied.append({
                'sequence_index': slot_index,
                'replacement_id': replacement_id,
                'reason': alias.get('reason', ''),
            })

        surface['replacement_ids'] = replacement_ids
        surface['unresolved_sequences'] = [unresolved_by_index[idx] for idx in sorted(unresolved_by_index)]
        record.setdefault('provenance', {})['surface_transport_policy'] = {
            'policy_path': str(policy_path),
            'applied_aliases': applied,
        }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(data, indent=2) + '\n')
    print(output_path)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
