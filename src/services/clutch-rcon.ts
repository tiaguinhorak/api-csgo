import { rconService } from './rcon';

export async function reloadClutchSkinsInGame(): Promise<boolean> {
  const host = process.env.CSGO_SERVER_HOST?.trim() || '127.0.0.1';
  const rconPort = parseInt(
    process.env.CSGO_RCON_PORT || process.env.CSGO_SERVER_PORT || '27015',
    10,
  );
  const rconPassword = process.env.CSGO_RCON_PASSWORD?.trim() || '';

  if (!rconPassword || !Number.isFinite(rconPort)) {
    return false;
  }

  try {
    await rconService.sendCommand(host, rconPort, rconPassword, 'sm_reloadclutchskins');
    await rconService.sendCommand(host, rconPort, rconPassword, 'sm_clutch_applyskins');
    return true;
  } catch (err) {
    console.warn('[clutch-rcon] reload failed:', err);
    return false;
  }
}
