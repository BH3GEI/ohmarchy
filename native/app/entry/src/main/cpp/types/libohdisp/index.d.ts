// libohdisp.so imported directly (the settings page; no XComponent there): only the
// calls that need no display.
export const sandboxCtl: (cmd: string, body?: string) => Promise<string>;
