#!/usr/bin/python3
"""Offline tests: fixed commands, digests, failure precedence and GUI lifecycle."""
import ast
import copy
import json
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
helper = runpy.run_path(str(ROOT/'system_files/usr/libexec/aquarius-update-system'))
ui = runpy.run_path(str(ROOT/'system_files/usr/libexec/aquarius-updater'))
REF = dict(image='ghcr.io/example/os:latest', transport='registry')

def image(letter, version='same-display-version'):
    return dict(image=REF, imageDigest='sha256:'+letter*64, version=version)

def status(cached=None, staged=None):
    return dict(apiVersion='org.containers.bootc/v1', spec=dict(image=REF, bootOrder='default'),
                status=dict(booted=dict(image=image('a'), cachedUpdate=cached), staged=staged))

class Updates(unittest.TestCase):
    def test_digest_not_display_version(self):
        self.assertEqual(helper['checked_state'](status(image('b')), 'Update available for: source\n  Digest: sha256:'+ 'b'*64, 'check')['state'], 'available')
        self.assertEqual(helper['checked_state'](status(image('a')), 'No changes in: source', 'check')['state'], 'up-to-date')
    def test_stale_cache_after_tag_rollback(self):
        self.assertEqual(helper['checked_state'](status(image('b')), 'No changes in: source', 'check')['state'], 'up-to-date')
    def test_unknown_output_not_current(self):
        self.assertEqual(helper['checked_state'](status(image('a')), 'Already latest', 'check')['state'], 'unknown')
    def test_invalid_schema_never_current(self):
        s=status();s['apiVersion']='org.containers.bootc/v2'
        self.assertEqual(helper['checked_state'](s, 'No changes in: source', 'check')['state'], 'unknown')
    def test_booted_only_unknown(self):
        self.assertEqual(helper['status_state'](status(), True)['state'], 'unknown')
        self.assertEqual(helper['status_state'](status(image('b')))['state'], 'unknown')
    def test_staged_is_restart_not_apply(self):
        calls=[]
        def run(cmd):
            calls.append(cmd)
            return 0,json.dumps(status(staged=dict(image=image('b')))),''
        self.assertEqual(helper['operate']('apply',run)['state'],'restart-required')
        self.assertEqual(len(calls),1)
    def test_download_only_or_rollback_not_restart(self):
        s=status(staged=dict(image=image('b'),downloadOnly=True))
        self.assertEqual(helper['status_state'](s)['state'],'unknown')
        s=status(staged=dict(image=image('b')));s['spec']['bootOrder']='rollback'
        self.assertEqual(helper['status_state'](s)['state'],'unknown')
    def test_failed_check_never_uses_stale_cache(self):
        calls=[]
        def run(cmd):
            calls.append(cmd)
            return (0,json.dumps(status(image('a'))),'') if cmd[0]=='status' else (1,'No changes in cached metadata','Permission denied')
        self.assertEqual(helper['operate']('check',run)['state'],'unknown')
        self.assertEqual(len(calls),2)
    def test_network_failure(self):
        def run(cmd):
            return (0,json.dumps(status()),'') if cmd[0]=='status' else (1,'','Network is unreachable')
        self.assertEqual(helper['operate']('check',run)['state'],'offline')
    def test_success_requires_structured_postcheck(self):
        responses=iter([(0,json.dumps(status()),''),(0,'No changes',''),(0,'not json','')])
        self.assertEqual(helper['operate']('check',lambda _:next(responses))['state'],'unknown')
    def test_other_source_and_malformed_digest(self):
        s=status(image('b'));s['status']['booted']['cachedUpdate']['image']={'image':'other'}
        self.assertEqual(helper['status_state'](s,True)['state'],'unknown')
        s=status(image('z'));self.assertEqual(helper['status_state'](s,True)['state'],'unknown')
    def test_operation_reserved_before_worker(self):
        state=ui['OperationState']()
        self.assertTrue(state.begin());self.assertTrue(state.busy)
        self.assertFalse(state.begin());state.finish();self.assertTrue(state.begin())
    def test_gui_callbacks_enforce_lifecycle(self):
        # Exercise real callback bodies without GTK or a display.
        tree=ast.parse((ROOT/'system_files/usr/libexec/aquarius-updater').read_text())
        methods={n.name:n for n in ast.walk(tree) if isinstance(n,ast.FunctionDef)}
        close=copy.deepcopy(methods['_on_close_request'])
        module=ast.Module(body=[close],type_ignores=[]);ast.fix_missing_locations(module)
        ns={};exec(compile(module,'callback','exec'),ns)
        class Title:
            def set_subtitle(self,text): self.text=text
        class Window: pass
        w=Window();w.operation=ui['OperationState']();w.header_title=Title()
        self.assertFalse(ns['_on_close_request'](w,None))
        w.operation.begin()  # before any subprocess exists, including auth prompt
        self.assertTrue(ns['_on_close_request'](w,None))
        w.operation.finish();self.assertFalse(ns['_on_close_request'](w,None))
    def test_authorization_dismissal(self):
        class P: returncode=126;stdout='';stderr='dismissed'
        with patch('subprocess.run',return_value=P()),patch('os.geteuid',return_value=1000):
            self.assertEqual(ui['system_operation']('check')['state'],'declined')
    def test_helper_failure_cannot_be_success(self):
        class P: returncode=1;stdout='{"state":"up-to-date"}';stderr='error'
        with patch('subprocess.run',return_value=P()):
            self.assertEqual(ui['system_operation']('check')['state'],'unknown')

if __name__=='__main__': unittest.main()
