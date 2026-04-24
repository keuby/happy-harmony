// Single source of truth for the happy-server URL. Upstream resolves
// this via MMKV override → env var → default; MVP hardcodes the default
// with a compile-time DEV_SERVER override to keep the scope tight. When
// 1a acquires a dev-settings page, swap this for preferences-backed
// runtime override.

const PROD_SERVER: string = 'https://api.cluster-fluster.com';

// Set this to e.g. 'http://192.168.x.x:3005' to point at a local
// happy-server during development. Commit this back to empty string
// before merging.
const DEV_SERVER: string = 'https://happy.cdkchen.com';

export function getServerUrl(): string {
  return DEV_SERVER !== '' ? DEV_SERVER : PROD_SERVER;
}
