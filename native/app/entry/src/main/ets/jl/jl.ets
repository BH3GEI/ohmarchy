// Route J (J+D): run a signed-into-HAP busybox userspace inside the display app, via the
// native spawner (fork+dlopen, no root/execve/JIT). Enabled by the 'jl' switch (off by default).
import bbload from 'libbbload.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0D0D;

export function startJl(): void {
  hilog.info(DOMAIN, 'JLAPP', 'jl switch on -> start spawner + demo');
  const rc: number = bbload.start();
  hilog.info(DOMAIN, 'JLAPP', 'spawner start rc=%{public}d', rc);
  const demo: string =
    'echo ===JL-IN-APP===; echo pid=$$; ' +
    'echo sysbin=$(ls /system/bin | wc -l); ' +
    '{ sleep 1 & echo bg=$!; wait; }; ' +
    'for i in 1 2 3; do echo loop$i; done; echo ===END===';
  const out: string = bbload.runSh(demo);
  const lines: string[] = out.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].length > 0) hilog.info(DOMAIN, 'JLAPP', 'OUT| %{public}s', lines[i]);
  }
}
