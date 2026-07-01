import type { WsSkinAllowEntry } from './ws-weapons-config';
import { siteRequestBaseUrl, siteSyncKeyFromEnv } from './site-http';

function syncKey(): string {
  const key = siteSyncKeyFromEnv();
  if (!key) {
    throw new Error('CSGO_SKINS_SYNC_KEY is required for WS_ALLOWLIST_SOURCE=site-db');
  }
  return key;
}

export async function fetchWsAllowlistFromSite(): Promise<WsSkinAllowEntry[]> {
  const base = siteRequestBaseUrl();
  if (!base) {
    throw new Error('CLUTCH_SITE_URL is required for WS_ALLOWLIST_SOURCE=site-db');
  }
  const url = `${base}/api/csgo/catalog/allowlist`;
  const res = await fetch(url, {
    headers: { "x-skins-sync-key": syncKey() },
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`Site allowlist HTTP ${res.status}: ${text.slice(0, 200)}`);
  }

  const data = (await res.json()) as {
    entries?: Array<{ weaponId: string; paintkit: number; name?: string }>;
  };

  if (!Array.isArray(data.entries)) {
    throw new Error('Site allowlist response missing entries[]');
  }

  return data.entries.map((e) => ({
    weaponId: e.weaponId,
    paintkit: e.paintkit,
    name: e.name ?? `${e.weaponId}:${e.paintkit}`,
  }));
}
