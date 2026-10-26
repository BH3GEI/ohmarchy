// Route J (J+D): run the signed-into-HAP Hyprland userspace inside the display app via the
// native spawner (fork+dlopen libhyprland.so, no root/execve/JIT). Enabled by the 'jl' switch.
import bbload from 'libbbload.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0D0D;

export function startJl(): void {
  hilog.info(DOMAIN, 'JLAPP', 'jl switch on -> spawner + in-app GPU + Hyprland');
  // start() sets OHMARCHY_LOCAL_GPU=1 (app becomes the vtest broker) and forks the
  // single-threaded spawner, before the window/XComponent is created.
  const rc: number = bbload.start();
  hilog.info(DOMAIN, 'JLAPP', 'spawner start rc=%{public}d', rc);
  // Launch Hyprland (dlopen'd .so, main() in a detached spawner grandchild). Empty config
  // = Hyprland's defaults; D's ohdisplay.lua path is passed once it's bundled into the HAP.
  const hrc: number = bbload.startHyprland('');
  hilog.info(DOMAIN, 'JLAPP', 'startHyprland rc=%{public}d', hrc);
}
