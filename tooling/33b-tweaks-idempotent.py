#!/usr/bin/env python3
"""Run refs/ios-sweet/sweet-root-tweaks.py so that a re-run over an already
tweaked volume succeeds. refs/ is a read-only clone, so the upstream script is
executed unmodified; only its one non-idempotent step is handled here.

  tooling/33b-tweaks-idempotent.py TWEAKS_SCRIPT MOUNTED_ROOT

The non-idempotent step is audio(): if Library/Audio/Plug-Ins/HAL/
VirtualAudio.plugin exists it shutil.move()s it into HAL.disabled/, and
shutil.move raises "Destination path ... already exists" when an earlier run
already put a copy there (an rsync re-run of the OS DMG brings the source
back). Every other step (launchd.plist rename, containers, data ark, pref
merges) is already safe to repeat.

Handling, in order:
  1. Before running: if both the source and HAL.disabled/VirtualAudio.plugin
     exist, the disabled copy is a stale result of an earlier run; remove it so
     the upstream move goes through with the fresh source.
  2. If the upstream run still fails with exactly that collision (shutil.Error
     naming HAL.disabled/VirtualAudio.plugin), remove the collision and retry
     once.
Any other failure, or a second failure, exits non-zero with the upstream
traceback: a real failure stays fatal.
"""
import os, runpy, shutil, sys, traceback

REL_SRC = 'Library/Audio/Plug-Ins/HAL/VirtualAudio.plugin'
REL_DST = 'Library/Audio/Plug-Ins/HAL.disabled/VirtualAudio.plugin'


def rm(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def clear_collision(root, why):
    src = os.path.join(root, REL_SRC)
    dst = os.path.join(root, REL_DST)
    if os.path.lexists(src) and os.path.lexists(dst):
        rm(dst)
        print('33b: removed stale /%s (%s)' % (REL_DST, why))
        return True
    return False


def run(script, root):
    saved = sys.argv
    sys.argv = [script, root]
    try:
        runpy.run_path(script, run_name='__main__')
    except SystemExit as e:
        if e.code not in (None, 0):
            raise
    finally:
        sys.argv = saved


def is_move_collision(exc, root):
    if not isinstance(exc, shutil.Error):
        return False
    msg = str(exc)
    return 'already exists' in msg and os.path.join(root, REL_DST) in msg


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    script, root = sys.argv[1], os.path.abspath(sys.argv[2])
    if not os.path.isfile(script):
        sys.exit('33b: no tweaks script %s' % script)
    clear_collision(root, 'already applied by an earlier run')
    try:
        run(script, root)
    except Exception as e:
        if not is_move_collision(e, root):
            raise
        print('33b: upstream move collided: %s' % e)
        if not clear_collision(root, 'collision on retry'):
            raise
        run(script, root)
        print('33b: retry succeeded')
    print('33b: tweaks applied')


if __name__ == '__main__':
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        traceback.print_exc()
        sys.exit(1)
