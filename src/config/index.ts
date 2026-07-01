import dotenv from 'dotenv';
dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  apiKey:
    process.env.API_KEY?.trim() ||
    process.env.CSGO_API_KEY?.trim() ||
    'default-key-change-me',

  csgo: {
    defaultTickrate: 128,
    defaultGameType: 0,
    defaultGameMode: 1,
    tvDelay: 70,
    /** MR12 — 12 rounds por half. */
    maxRounds: 24,
    overtimeRounds: 6,
    knifeRound: true,
    /** 10 jogadores + 1 slot reservado para admin telespectador. */
    maxPlayers: parseInt(process.env.CSGO_MAXPLAYERS || '11', 10),
    /** Diretório do srcds na VPS quando o registro não envia csgoDir. */
    defaultServerDir: process.env.CSGO_SERVER_DIR?.trim() || '/home/csgo/server',
  },

  veto: {
    mapPool: [
      'de_mirage', 'de_inferno', 'de_dust2', 'de_nuke',
      'de_overpass', 'de_ancient', 'de_anubis', 'de_vertigo'
    ],
  },
};
