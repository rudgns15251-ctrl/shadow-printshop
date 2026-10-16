"""End-to-end simulation of the real coordinator protocol, without Godot/WSL network.

Mocks reproduce the exact troublesome '144 checks pass + leaked audio ERROR' flow:
Codex modifies one allowlisted test file, Godot QA then passes, EXE/PCK exported.
"""
import json, os, pathlib, shutil, subprocess, sys, tempfile, textwrap, unittest

PACKAGE = pathlib.Path(__file__).resolve().parents[2]
AUTO = pathlib.Path(__file__).resolve().parents[1]

class Pipeline(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=pathlib.Path(self.tmp.name)
        shutil.copytree(AUTO,self.root/'.autodev',ignore=shutil.ignore_patterns('runs','__pycache__','doctor_godot.log'))
        self.game=self.root/'game';(self.game/'tests').mkdir(parents=True)
        (self.game/'project.godot').write_text('[application]\nconfig/name="Fake C01"\n',encoding='utf8')
        for name in ['smoke_test.gd','regression_test.gd']:
            (self.game/'tests'/name).write_text('pass\n')
        (self.game/'tests'/'slice_acceptance.gd').write_text('_check(1)\nSLICE_ACCEPTANCE_PASS\n')
        (self.root/'.autodev'/'config.json').write_text(json.dumps({'game_dir':'game',
            'godot':'fakegodot', 'codex_mode':'native', 'exe_name':'test.exe',
            'tests': [{'name':'SMOKE','script':'tests/smoke_test.gd','marker':'HARNESS_SMOKE_PASS'},
                      {'name':'REGRESSION','script':'tests/regression_test.gd','marker':'HARNESS_REGRESSION_PASS'},
                      {'name':'SLICE','script':'tests/slice_acceptance.gd','marker':'SLICE_ACCEPTANCE_PASS'}]}))
        self.bin=self.root/'bin';self.bin.mkdir()
        (self.bin/'fakegodot').write_text(textwrap.dedent('''#!/usr/bin/env python3
import pathlib, sys
args=sys.argv
if '--version' in args: print('4.7.1.stable.official.testing');sys.exit(0)
game=pathlib.Path(args[args.index('--path')+1])
if '--import' in args:
 (game/'.godot'/'imported').mkdir(parents=True,exist_ok=True); print('import completed'); sys.exit(0)
if '--export-release' in args:
 out=pathlib.Path(args[-1]);out.parent.mkdir(parents=True,exist_ok=True)
 out.write_bytes(b'EXE'+b'0'*150000);out.with_suffix('.pck').write_bytes(b'PCK data')
 print('Export succeeded');sys.exit(0)
if '--script' in args:
 script=args[args.index('--script')+1]
 if script.endswith('smoke_test.gd'):print('HARNESS_SMOKE_PASS');sys.exit(0)
 if script.endswith('regression_test.gd'):print('HARNESS_REGRESSION_PASS');sys.exit(0)
 if script.endswith('slice_acceptance.gd'):
  print('SLICE_ACCEPTANCE_PASS checks=144')
  if '#LEAKFIX' not in (game/'tests'/'slice_acceptance.gd').read_text():
   print('ERROR: 2 resources still in use at exit');sys.exit(0)
  sys.exit(0)
print('ERROR: unknown invocation');sys.exit(1)
'''))
        (self.bin/'codex').write_text(textwrap.dedent('''#!/usr/bin/env python3
import sys,pathlib
_ = sys.stdin.read()
stage=pathlib.Path(sys.argv[sys.argv.index('-C')+1])
f=stage/'tests'/'slice_acceptance.gd'
f.write_text(f.read_text()+'#LEAKFIX\\n')
print('Mock Codex modified allowlisted test teardown')
'''))
        for s in self.bin.iterdir():s.chmod(0o755)
        self.env=os.environ.copy();self.env['PATH']=str(self.bin)+os.pathsep+self.env.get('PATH','')
        self.env['APPDATA']=str(self.root/'appdata')
        template=pathlib.Path(self.env['APPDATA'])/'Godot/export_templates/4.7.1.stable/windows_release_x86_64.exe'
        template.parent.mkdir(parents=True);template.write_bytes(b'template')
        subprocess.run(['git','init','-q'],cwd=self.root,check=True)
        subprocess.run(['git','config','user.email','fixture@invalid'],cwd=self.root,check=True)
        subprocess.run(['git','config','user.name','Fixture'],cwd=self.root,check=True)
        (self.root/'.gitignore').write_text('appdata/\nbin/\n')
        subprocess.run(['git','add','game','.gitignore'],cwd=self.root,check=True)
        subprocess.run(['git','commit','-qm','Source baseline'],cwd=self.root,check=True)

    def cmd(self,*args):
        return subprocess.run([sys.executable,str(self.root/'.autodev'/'auto.py'),*args],
                              cwd=self.root,env=self.env,capture_output=True,text=True)

    def test_repair_export_accept_rebuild(self):
        result=self.cmd('doctor')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        # The original game FAILS QA. No auto-fix should be invoked without a task.
        first=self.cmd('run')
        self.assertEqual(first.returncode,2, first.stdout+first.stderr)
        self.assertIn('FAIL SLICE',first.stdout, first.stderr)
        self.assertNotIn('#LEAKFIX',(self.game/'tests'/'slice_acceptance.gd').read_text())
        fixed=self.cmd('run','--task','fix_audio_teardown')
        self.assertEqual(fixed.returncode,0,fixed.stdout+fixed.stderr)
        self.assertIn('AUTODEV_PASS',fixed.stdout)
        self.assertIn('BUILD PASS',fixed.stdout)
        reports=list((self.root/'.autodev'/'runs').glob('*/result.json'))
        completed=[r for r in reports if json.loads(r.read_text())['status']=='review']
        self.assertEqual(len(completed),1)
        run_id=completed[0].parent.name
        manifest=json.loads(completed[0].read_text())
        self.assertEqual(manifest['changes'],['tests/slice_acceptance.gd'])
        self.assertTrue((completed[0].parent/'Windows_Test_Build.zip').exists())
        self.assertNotIn('#LEAKFIX',(self.game/'tests'/'slice_acceptance.gd').read_text())
        accepted=self.cmd('accept','--run-id',run_id)
        self.assertEqual(accepted.returncode,0,accepted.stdout+accepted.stderr)
        self.assertIn('#LEAKFIX',(self.game/'tests'/'slice_acceptance.gd').read_text())
        self.assertIn('AutoDev: fix_audio_teardown',subprocess.run(['git','log','-1','--format=%s'],cwd=self.root,capture_output=True,text=True).stdout)
        rebuild=self.cmd('run')
        self.assertEqual(rebuild.returncode,0,rebuild.stdout+rebuild.stderr)
        self.assertIn('BUILD PASS',rebuild.stdout)

    def test_refuse_out_of_scope(self):
        # Actively reject a task that would alter a file outside its allowlist.
        # Policy is independent of the model's claimed success status.
        sys.path.insert(0,str(self.root/'.autodev'))
        try:
            import auto
            with self.assertRaises(auto.StopRun):
                auto.check_changes({'project.godot':'a'},{'project.godot':'b'},['scripts/*.gd'])
        finally:sys.path.remove(str(self.root/'.autodev'))

if __name__=='__main__':unittest.main(verbosity=2)
