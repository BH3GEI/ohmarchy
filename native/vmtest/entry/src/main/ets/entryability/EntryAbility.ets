import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import vm from '@hms.virtService.vmManager';

const TAG: string = 'VMPROBE';
const DOM: number = 0xBEEF;
const ME: string = 'com.ohmarchy.vmtest';

export let probeResult: string = 'probe not run yet';
function M(o: Object): Record<string, Object> { return o as object as Record<string, Object>; }
function dumpErr(e: Object): string {
  const r = M(e);
  return 'code=' + String(r?.['code']) + ' name=' + String(r?.['name']) + ' msg=' + String(r?.['message']);
}
async function callA(label: string, fn: () => Promise<Object>): Promise<Object | undefined> {
  try { const v = await fn(); hilog.info(DOM, TAG, '%{public}s => %{public}s', label, JSON.stringify(v));
    probeResult += label + ' => ' + JSON.stringify(v) + '\n'; return v;
  } catch (e) { hilog.error(DOM, TAG, '%{public}s THROW %{public}s', label, dumpErr(e as Object));
    probeResult += label + ' THROW ' + dumpErr(e as Object) + '\n'; return undefined; }
}

async function probe(): Promise<void> {
  const m = M(vm as object);
  probeResult = '';
  // arity of createVm (how many args it really wants)
  const cfn = m['createVm'];
  hilog.info(DOM, TAG, 'createVm.length=%{public}s getVmStatus.length=%{public}s',
    String(M(cfn)?.['length']), String(M(m['getVmStatus'])?.['length']));

  await callA('getVmStatus(ME) pre', () => (m['getVmStatus'] as (b: string) => Promise<Object>)(ME));

  // comprehensive config using discovered field names + typed enums
  const ST = M(m['StorageType']); const NM = M(m['NetMode']); const ST2 = M(m['VmStartType']);
  const cfg: Record<string, Object> = {
    'vmName': 'probe',
    'cpuNum': 2,
    'memory': 2048,
    'diskSize': 20,
    'storageType': ST?.['TYPE_VIRTIO'] ?? 0,
    'netMode': NM?.['MODE_NAT'] ?? 1,
    'startType': ST2?.['START'] ?? 0,
    'width': 1920,
    'height': 1080,
    'autoStart': false,
  };
  const create = m['createVm'] as (b: string, c: Record<string, Object>) => Promise<Object>;
  const r1 = await callA('createVm(ME, fullCfg)', () => create(ME, cfg));

  // variant: memSize instead of memory
  const cfg2: Record<string, Object> = { 'vmName': 'probe', 'cpuNum': 2, 'memSize': 2048, 'diskSize': 20,
    'storageType': 0, 'netMode': 1, 'startType': 0, 'width': 1920, 'height': 1080 };
  const r2 = r1 === undefined ? await callA('createVm(ME, cfg-memSize)', () => create(ME, cfg2)) : r1;

  // if anything created a VM, verify it's ours then destroy it (NEVER startVm)
  const st = await callA('getVmStatus(ME) post', () => (m['getVmStatus'] as (b: string) => Promise<Object>)(ME));
  if (r1 !== undefined || r2 !== undefined) {
    await callA('destroyVm(ME) cleanup', () => (m['destroyVm'] as (b: string) => Promise<Object>)(ME));
    await callA('getVmStatus(ME) after destroy', () => (m['getVmStatus'] as (b: string) => Promise<Object>)(ME));
  }
}

export default class EntryAbility extends UIAbility {
  onCreate(): void { hilog.info(DOM, TAG, 'onCreate; createVm full-config attempt (create-only)'); probe(); }
  onWindowStageCreate(ws: window.WindowStage): void {
    ws.loadContent('pages/Index', (err) => { if (err.code) { hilog.error(DOM, TAG, 'loadContent %{public}s', JSON.stringify(err)); } });
  }
}
