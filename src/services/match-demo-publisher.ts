import fs from 'fs';
import path from 'path';
import {
  siteBaseUrlFromEnv,
  siteRequestBaseUrl,
  siteRequestHeaders,
  siteSyncKeyFromEnv,
} from './site-http';

const DEFAULT_SERVER_DIR = '/home/csgo/server';

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resolveDemoSourcePath(matchId: string, demoFile?: string): string | null {
  const fileName = demoFile?.trim() || `clutch_${matchId}.dem`;
  const safeName = path.basename(fileName);
  const serverDir = process.env.CSGO_SERVER_DIR?.trim() || DEFAULT_SERVER_DIR;
  const candidate = path.join(serverDir, 'csgo', safeName);
  if (!fs.existsSync(candidate)) return null;
  return candidate;
}

/** Wait until GOTV finishes flushing the `.dem` file after tv_stoprecord. */
async function waitForStableDemoFile(
  filePath: string,
  maxWaitMs = 45_000,
): Promise<boolean> {
  const start = Date.now();
  let lastSize = -1;
  let stableChecks = 0;

  while (Date.now() - start < maxWaitMs) {
    if (!fs.existsSync(filePath)) {
      await sleep(1500);
      continue;
    }

    const stat = fs.statSync(filePath);
    if (stat.size > 0 && stat.size === lastSize) {
      stableChecks += 1;
      if (stableChecks >= 2) return true;
    } else {
      stableChecks = 0;
    }
    lastSize = stat.size;
    await sleep(2000);
  }

  return fs.existsSync(filePath) && fs.statSync(filePath).size > 0;
}

function publicDemoUrl(matchId: string): string | null {
  const base = siteBaseUrlFromEnv();
  if (!base) return null;
  return `${base}/uploads/demos/${matchId}.dem`;
}

async function copyDemoToUploadDir(matchId: string, src: string): Promise<string | null> {
  const uploadDir = process.env.CLUTCH_DEMO_UPLOAD_DIR?.trim();
  if (!uploadDir) return null;

  fs.mkdirSync(uploadDir, { recursive: true });
  const dest = path.join(uploadDir, `${matchId}.dem`);
  await fs.promises.copyFile(src, dest);
  return publicDemoUrl(matchId);
}

async function uploadDemoViaSiteApi(matchId: string, src: string): Promise<string | null> {
  const base = siteRequestBaseUrl();
  const key = siteSyncKeyFromEnv();
  if (!base || !key) return null;

  const url = `${base}/api/csgo/match-demo?matchId=${encodeURIComponent(matchId)}`;
  const buffer = await fs.promises.readFile(src);

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: siteRequestHeaders({
        'content-type': 'application/octet-stream',
      }),
      body: buffer,
      signal: AbortSignal.timeout(300_000),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      console.warn(
        `[match-demo] upload POST ${url} → ${res.status}: ${text.slice(0, 200)}`,
      );
      return null;
    }

    const body = (await res.json().catch(() => null)) as { demoUrl?: string } | null;
    if (body?.demoUrl) return body.demoUrl;
    return publicDemoUrl(matchId);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn(`[match-demo] upload failed for ${matchId}: ${message}`);
    return null;
  }
}

/**
 * Publishes clutch_<matchId>.dem to the site and returns the public demo URL.
 * Prefers CLUTCH_DEMO_UPLOAD_DIR (same-VPS copy); falls back to HTTP upload API.
 */
export async function publishMatchDemo(
  matchId: string,
  demoFile?: string,
): Promise<string | null> {
  const src = resolveDemoSourcePath(matchId, demoFile);
  if (!src) {
    console.warn(`[match-demo] no demo file on disk for match ${matchId}`);
    return null;
  }

  const ready = await waitForStableDemoFile(src);
  if (!ready) {
    console.warn(`[match-demo] demo file not stable yet for match ${matchId}: ${src}`);
    return null;
  }

  const copied = await copyDemoToUploadDir(matchId, src);
  if (copied) {
    console.log(`[match-demo] copied ${src} → site (${matchId})`);
    return copied;
  }

  const uploaded = await uploadDemoViaSiteApi(matchId, src);
  if (uploaded) {
    console.log(`[match-demo] uploaded ${src} for match ${matchId}`);
  }
  return uploaded;
}
