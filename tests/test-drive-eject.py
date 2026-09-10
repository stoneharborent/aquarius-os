#!/usr/bin/python3
"""Run the real aq function with fake tools; never mount or detach anything."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
text=(ROOT/'system_files/usr/bin/aq').read_text()
start=text.index('drive_eject() {');end=text.index('\n}\n',start)+3
FUNCTION=text[start:end]

class Eject(unittest.TestCase):
    def check_case(self,fs,code):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp);log=p/'calls'
            for name in ('fusermount3','gio'):
                f=p/name;f.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALLS"\nexit "$RESULT"\n');f.chmod(0o755)
            script='drive_root() { echo /media; }\ndrive_table() { printf "/media/Disk\\t'+fs+'\\t/dev/fake\\tuser_id=1000\\n"; }\n'+FUNCTION+'\ndrive_eject Disk\n'
            r=subprocess.run(['bash','-c',script],env=dict(os.environ,PATH=temp+':'+os.environ['PATH'],CALLS=str(log),RESULT=str(code)),capture_output=True,text=True)
            self.assertEqual(r.returncode,code)
            calls=log.read_text().splitlines();self.assertEqual(len(calls),1)
            self.assertNotIn('-z',calls[0]);self.assertNotIn('-f',calls[0])
            self.assertNotIn('safe to unplug',r.stdout)
    def test_busy_fuse_is_not_lazily_detached(self):self.check_case('fuse.apfs',1)
    def test_busy_gvfs_is_not_forced(self):self.check_case('vfat',1)
    def test_success_mentions_other_volumes(self):self.check_case('vfat',0)

if __name__=='__main__':unittest.main()
