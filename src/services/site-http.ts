/**
 * HTTP helpers for api-csgo → site (CLUTCH_SITE_URL).
 */

export function siteBaseUrlFromEnv(): string | null {
  const raw =
    process.env.CLUTCH_SITE_URL?.trim() ||
    process.env.SITE_ORIGIN?.trim() ||
    '';
  if (!raw) return null;
  return raw.replace(/\/+$/, '');
}

export function siteSyncKeyFromEnv(): string | null {
  return process.env.CSGO_SKINS_SYNC_KEY?.trim() || null;
}

/** ngrok free returns HTML interstitial unless this header is set. */
export function siteRequestHeaders(extra: Record<string, string> = {}): Record<string, string> {
  const headers: Record<string, string> = { ...extra };
  const key = siteSyncKeyFromEnv();
  if (key) {
    headers['x-skins-sync-key'] = key;
  }
  const base = siteBaseUrlFromEnv() ?? '';
  if (base.includes('ngrok')) {
    headers['ngrok-skip-browser-warning'] = 'true';
  }
  return headers;
}
