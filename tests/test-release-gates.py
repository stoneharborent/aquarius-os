#!/usr/bin/python3
"""Offline workflow dependency and fetch-failure regression checks."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
import yaml
ROOT=Path(__file__).resolve().parents[1]

class Gates(unittest.TestCase):
    def test_publication_depends_on_shell_checks_and_exact_image_load(self):
        workflow=yaml.safe_load((ROOT/'.github/workflows/build.yml').read_text())
        job=workflow['jobs']['build_push']
        self.assertIn('shell_tests',job['needs'])
        steps=job['steps'];gate=next(i for i,s in enumerate(steps) if s['name']=='Load the exact desktop and greeter before publishing')
        publish=next(i for i,s in enumerate(steps) if s['name']=='Publish')
        self.assertLess(gate,publish)
        self.assertNotIn('if',steps[gate])
        for text in ('--pull=never','${IMAGE_NAME}:${DEFAULT_TAG}','EXPECT_SHELL_REF','check-built-shell.sh'):
            self.assertIn(text,steps[gate]['run'])
        self.assertEqual(len(job['strategy']['matrix']['include']),2)
    def test_failed_clone_stops_source_stage(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)
            (p/'stage.sh').write_text((ROOT/'build_files/stage-aquarius-shell.sh').read_text())
            (p/'aq-lib.sh').write_text('set -euo pipefail\nsay() { :; }\naq_dnf() { :; }\n')
            (p/'git').write_text('#!/bin/sh\nexit 43\n');(p/'git').chmod(0o755)
            env=dict(os.environ,PATH=temp+':'+os.environ['PATH'],AQUARIUS_SHELL_REPO='unreachable',AQUARIUS_SHELL_REF='0'*40)
            result=subprocess.run(['bash',str(p/'stage.sh')],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,43,result.stdout+result.stderr)
    def test_workflow_fetch_failure_is_failure(self):
        w=yaml.safe_load((ROOT/'.github/workflows/build.yml').read_text())
        fetch=next(s for s in w['jobs']['shell_tests']['steps'] if s['name']=='Fetch the shell at that exact commit')
        self.assertIn('set -euo pipefail',fetch['run'])
        self.assertNotIn('exit 0',fetch['run'])

if __name__=='__main__':unittest.main()
