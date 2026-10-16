"""WSL-worker mechanics on Linux (not a real WSL/Codex provider test)."""
import json,os,pathlib,subprocess,sys,tempfile,textwrap,unittest
WORKER=pathlib.Path(__file__).resolve().parents[1]/'wsl_worker.py'

class Worker(unittest.TestCase):
 def test_safe_sync_and_scope_guard(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);game=root/'game';(game/'scripts').mkdir(parents=True)
   (game/'project.godot').write_text('config_version=5\n')
   target=game/'scripts'/'main.gd';target.write_text('old\n')
   secret=game/'secrets.txt';secret.write_text('keep')
   prompt=root/'prompt.txt';prompt.write_text('edit game')
   allow=root/'allowed.json';allow.write_text(json.dumps(['scripts/main.gd']))
   fake=root/'codex';fake.write_text(textwrap.dedent('''#!/usr/bin/env python3
import pathlib,sys
_ = sys.stdin.read()
root=pathlib.Path(sys.argv[sys.argv.index('-C')+1]);(root/'scripts'/'main.gd').write_text('new\\n')
print('edited')
'''))
   fake.chmod(0o755)
   call=lambda:subprocess.run([sys.executable,str(WORKER),'--source',str(game), '--prompt',str(prompt),
                                '--allowed',str(allow),'--codex',str(fake)],capture_output=True,text=True,timeout=40)
   res=call();self.assertEqual(res.returncode,0,res.stdout+res.stderr)
   self.assertEqual(target.read_text(),'new\n');self.assertEqual(secret.read_text(),'keep')
   fake.write_text(textwrap.dedent('''#!/usr/bin/env python3
import pathlib,sys
_=sys.stdin.read()
root=pathlib.Path(sys.argv[sys.argv.index('-C')+1]);(root/'secrets.txt').write_text('tampered')
'''))
   res=call();self.assertNotEqual(res.returncode,0)
   self.assertEqual(secret.read_text(),'keep')

if __name__=='__main__':unittest.main(verbosity=2)
