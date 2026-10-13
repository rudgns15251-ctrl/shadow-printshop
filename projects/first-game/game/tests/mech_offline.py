"""Offline data/BFS checks; does not execute GDScript or verify UI."""
import json
from pathlib import Path
from collections import deque

ROOT = Path(__file__).resolve().parents[1]
ROWS = json.loads((ROOT / 'data/mech_puzzles.json').read_text())
MASKS = [11, 38, 416, 200, 7, 292, 448, 73]
def packed(board):
    assert len(board) == 9 and all(v in (0, 1) for v in board)
    return sum(v << i for i, v in enumerate(board))
assert json.loads((ROOT / "data/mech_data.gd").read_text().split("const PUZZLES := ", 1)[1]) == ROWS
assert len(ROWS) == 8
assert ROWS[0]['start'] == [0]*9
assert ROWS[0]['target'] == [1,0,1,1,0,1,0,0,0]
assert ROWS[1]['start'] == [0,1,0,1,0,0,0,0,1]
assert ROWS[1]['target'] == [0,1,1,1,0,0,0,1,1]
assert ROWS[6]['allowed_masks'] == [0]
assert ROWS[6]['target'] == [0]*9
assert ROWS[6]['solution'] == [0, 1, 2, 3]
assert ROWS[7]['allowed_masks'] == [0, 1]
assert ROWS[7]['minimum_prints'] == 5
assert len({(tuple(r['start']), tuple(r['target']), tuple(r['allowed_masks'])) for r in ROWS}) == 8
assert len({packed(r['start']) ^ packed(r['target']) for r in ROWS}) == 8
for row in ROWS:
    start, target = packed(row['start']), packed(row['target'])
    allowed = [s*4+r for s in row['allowed_masks'] for r in range(4)]
    distances, queue = {start: 0}, deque([start])
    while queue:
        board = queue.popleft()
        for action in allowed:
            nxt = board ^ MASKS[action]
            if nxt not in distances:
                distances[nxt] = distances[board]+1
                queue.append(nxt)
    assert distances[target] == row['minimum_prints']
    assert len(distances) == row['reachable_states']
    board = start
    for action in row['solution']:
        assert action in allowed and board != target
        board ^= MASKS[action]
    assert board == target
    seen = set()
    for case in range(1000):
        code, board, history, sequence = case, start, [], []
        for step in range(12):
            choice = code % len(allowed)
            action = allowed[choice]
            if step:
                code //= len(allowed)
            else:
                action = allowed[0]
            sequence.append(action)
            if board != target:
                history.append(board)
                board ^= MASKS[action]
        while history:
            board = history.pop()
        assert board == start
        seen.add(tuple(sequence))
    assert len(seen) == 1000
    print(row['id'], 'minimum', distances[target], 'reachable', len(distances), 'unique undo cases', len(seen))
print('PASS offline cases 8000 (Python reference only)')
