"""Trusted campaign arithmetic; stdlib only, never human difficulty certification.

Method 1 uses the existing mech_offline.py integer masks and exhaustive BFS.
Method 2 independently rotates cell coordinates and enumerates action subsets.
XOR actions commute and pairs cancel, so a shortest solution uses each at most
once. The second method compares the entire reachable distance map, not just
the requested target. No existing game/test/answer is changed by these checks.
"""
from collections import deque
from itertools import product
import json
import re

MASKS = (11, 38, 416, 200, 7, 292, 448, 73)
IDS = [f'C01-{i:02}' for i in range(1, 9)] + [f'C{c:02}-{i:02}' for c in (2, 3) for i in range(1, 6)]

def demand(ok, message):
    if not ok: raise ValueError(message)

def packed(board):
    demand(isinstance(board, list) and len(board) == 9 and all(type(x) is int and x in (0, 1) for x in board), 'Invalid nine-bit board')
    return sum(x << i for i, x in enumerate(board))

def physical_actions():
    actions = []
    for base in ({(0, 0), (1, 0), (0, 1)}, {(0, 0), (1, 0), (2, 0)}):
        cells = set(base)
        for _ in range(4):
            actions.append(tuple(int((x, y) in cells) for y in range(3) for x in range(3)))
            cells = {(2-y, x) for x, y in cells}
    return actions

def bfs(start, allowed):
    distances = {start: 0}; queue = deque([start])
    while queue:
        board = queue.popleft()
        for action in allowed:
            following = board ^ MASKS[action]
            if following not in distances:
                distances[following] = distances[board] + 1; queue.append(following)
    return distances

def independent_distances(start_cells, allowed):
    vectors = physical_actions(); result = {}
    for subset in product((False, True), repeat=len(allowed)):
        cells = list(start_cells)
        for chosen, action in zip(subset, allowed):
            if chosen: cells = [(a+b) % 2 for a, b in zip(cells, vectors[action])]
        key = tuple(cells); distance = sum(subset)
        result[key] = min(result.get(key, 99), distance)
    return result

def calculate(rows, original):
    demand(isinstance(rows, list) and [r.get('id') for r in rows] == IDS, 'Campaign requires exact ordered 18 IDs')
    demand(len(original) == 8, 'Original eight missing')
    demand([packed(list(v)) for v in physical_actions()] == list(MASKS), 'Coordinate rotations differ from existing rules')
    signatures = set(); results = []
    for index, row in enumerate(rows):
        ident = row['id']; chapter = 1 if index < 8 else (2 if index < 13 else 3)
        demand(type(row.get('chapter')) is int and row['chapter'] == chapter, ident + ': invalid chapter')
        if index < 8:
            demand({k: v for k, v in row.items() if k != 'chapter'} == original[index], ident + ': original dictionary changed')
        start, target = packed(row['start']), packed(row['target'])
        masks = row['allowed_masks']
        demand(isinstance(masks, list) and masks and all(type(m) is int and m in (0, 1) for m in masks) and len(set(masks)) == len(masks), ident + ': invalid allowed masks')
        signature = (start, target, tuple(sorted(masks)))
        demand(signature not in signatures, ident + ': duplicate mechanical triple'); signatures.add(signature)
        allowed = [s*4+r for s in masks for r in range(4)]
        distances = bfs(start, allowed)
        independent = independent_distances(row['start'], allowed)
        demand({packed(list(k)): v for k, v in independent.items()} == distances, ident + ': independent full-map disagreement')
        demand(target in distances and start != target, ident + ': unreachable or already solved')
        witness = row['solution']; demand(isinstance(witness, list) and witness, ident + ': empty witness')
        board = start; erased = added = 0
        for action in witness:
            demand(type(action) is int and action in allowed and board != target, ident + ': forbidden/premature witness')
            erased += (board & MASKS[action]).bit_count()
            added += ((~board) & MASKS[action]).bit_count()
            board ^= MASKS[action]
        demand(board == target, ident + ': witness misses target')
        if index < 8:
            demand(row['minimum_prints'] == distances[target] and row['reachable_states'] == len(distances), ident + ': original metadata mismatch')
        results.append({'id': ident, 'minimum_prints': distances[target], 'reachable_states': len(distances),
                        'witness_length': len(witness), 'witness_valid': True, 'full_maps_equal': True,
                        'erased_ink_cells': erased, 'added_ink_cells': added})
    demand({tuple(sorted(r['allowed_masks'])) for r in rows[8:]} == {(0,), (1,), (0, 1)}, 'Missing new mask variety')
    demand(len({r['minimum_prints'] for r in results[8:]}) >= 3, 'Insufficient mathematical distance variety')
    demand(all(packed(r['start']) != 0 for r in rows[8:]), 'New nonempty starts missing')
    demand(any(r['erased_ink_cells'] for r in results[8:]) and any(r['added_ink_cells'] for r in results[8:]), 'Cancellation/synthesis missing')
    return results

def completed_text(text, results):
    """Replace only the 20 new metadata scalar tokens; keep all other bytes."""
    decoder = json.JSONDecoder(); cursor = text.index('[')+1; replacements = []
    for index, expected in enumerate(results):
        while text[cursor].isspace() or text[cursor] == ',': cursor += 1
        row, end = decoder.raw_decode(text, cursor)
        demand(row['id'] == expected['id'], 'Metadata ID mapping changed')
        if index >= 8:
            segment = text[cursor:end]
            for key in ('minimum_prints', 'reachable_states'):
                matches = list(re.finditer(r'"'+key+r'"\s*:\s*(null|-?\d+)', segment))
                demand(len(matches) == 1, row['id'] + ': invalid metadata token ' + key)
                match = matches[0]
                replacements.append((cursor+match.start(1), cursor+match.end(1), str(expected[key])))
        cursor = end
    for start, end, value in sorted(replacements, reverse=True): text = text[:start]+value+text[end:]
    return text
