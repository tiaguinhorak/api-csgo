const STEAM_ID64_BASE = BigInt('76561197960265728');

export function isSteamId64(steamId: string): boolean {
  return /^\d{17}$/.test(steamId.trim());
}

export function steam2ToSteamId64(steam2: string): string | null {
  const match = steam2.trim().match(/^STEAM_[0-5]:([0-1]):(\d+)$/i);
  if (!match) return null;
  const y = Number(match[1]);
  const z = Number(match[2]);
  if (!Number.isFinite(y) || !Number.isFinite(z)) return null;
  const accountId = z * 2 + y;
  return String(STEAM_ID64_BASE + BigInt(accountId));
}

/** Prefer SteamID64 for site APIs; pass through if already normalized. */
export function normalizeSteamId64(steamId: string): string {
  const trimmed = steamId.trim();
  if (isSteamId64(trimmed)) return trimmed;
  return steam2ToSteamId64(trimmed) ?? trimmed;
}
