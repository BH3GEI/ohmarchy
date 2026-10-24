/*
 * STUB for runtime VM-API probe (ohmarchy Route I). Not a real Huawei SDK file.
 * Shapes reverse-engineered from com.oseasy1.ohvm modules.abc call sites.
 * @file
 * @kit VirtServiceKit
 */
export declare namespace virtualization {
  function createVm(bundleName: string, config: Record<string, Object>): Promise<string>;
  function startVm(bundleName: string, config?: Record<string, Object>): Promise<void>;
  function stopVm(bundleName: string): Promise<void>;
  function pauseVm(bundleName: string): Promise<void>;
  function resumeVm(bundleName: string): Promise<void>;
  function destroyVm(bundleName: string): Promise<void>;
  function getVmAvailableCpuNumRange(): number[];
  function getVmDiskSize(): Promise<number>;
}
export declare function createVm(config?: Record<string, Object>): Promise<string>;
