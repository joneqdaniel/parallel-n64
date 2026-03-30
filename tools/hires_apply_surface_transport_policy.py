#!/usr/bin/env python3
import argparse
import copy
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text())


def annotate_provenance(record: dict, key: str, payload):
    record.setdefault('provenance', {}).setdefault('surface_transport_policy', {})[key] = payload


def apply_slot_aliases(record: dict, policy_path: Path, alias_cfg: dict):
    surface = record.get('surface', {})
    surface_id = surface.get('surface_id')
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
    annotate_provenance(record, 'slot_aliases', {
        'policy_path': str(policy_path),
        'surface_id': surface_id,
        'applied_aliases': applied,
    })


def apply_selector_mode(record: dict, policy_path: Path, selector_cfg: dict):
    selector_mode = selector_cfg.get('selector_mode')
    if not selector_mode:
        raise SystemExit('surface_selector_modes entries require selector_mode')
    record['selector_mode'] = selector_mode
    annotate_provenance(record, 'selector_mode', {
        'policy_path': str(policy_path),
        'surface_id': record.get('surface', {}).get('surface_id'),
        'selector_mode': selector_mode,
        'reason': selector_cfg.get('reason', ''),
    })


def build_surface_clone(source_record: dict, clone_id: str, clone_cfg: dict, policy_path: Path):
    record = copy.deepcopy(source_record)
    surface = record.setdefault('surface', {})
    surface['surface_id'] = clone_id
    if clone_cfg.get('sampled_low32'):
        surface['sampled_low32'] = clone_cfg['sampled_low32']
    if clone_cfg.get('canonical_identity_override'):
        record['canonical_identity'] = clone_cfg['canonical_identity_override']
    if clone_cfg.get('selector_mode'):
        record['selector_mode'] = clone_cfg['selector_mode']
    annotate_provenance(record, 'clone', {
        'policy_path': str(policy_path),
        'source_surface_id': clone_cfg.get('source_surface_id'),
        'clone_surface_id': clone_id,
        'reason': clone_cfg.get('reason', ''),
    })
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description='Apply tracked surface transport policy to a surface package.')
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
    surface_selector_modes = policy.get('surface_selector_modes', {})
    surface_clones = policy.get('surface_clones', {})

    records = list(data.get('surfaces', []))
    record_index = {record.get('surface', {}).get('surface_id'): record for record in records}

    for clone_id, clone_cfg in surface_clones.items():
        source_id = clone_cfg.get('source_surface_id')
        if not source_id:
            raise SystemExit(f'{clone_id}: source_surface_id is required')
        if clone_id in record_index:
            raise SystemExit(f'{clone_id}: clone surface_id already exists in input package')
        source_record = record_index.get(source_id)
        if source_record is None:
            raise SystemExit(f'{clone_id}: source surface {source_id} not found')
        clone_record = build_surface_clone(source_record, clone_id, clone_cfg, policy_path)
        records.append(clone_record)
        record_index[clone_id] = clone_record

    for record in records:
        surface = record.get('surface', {})
        surface_id = surface.get('surface_id')
        alias_cfg = surface_aliases.get(surface_id)
        if alias_cfg:
            apply_slot_aliases(record, policy_path, alias_cfg)
        selector_cfg = surface_selector_modes.get(surface_id)
        if selector_cfg:
            apply_selector_mode(record, policy_path, selector_cfg)

    data['surfaces'] = records
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(data, indent=2) + '\n')
    print(output_path)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
