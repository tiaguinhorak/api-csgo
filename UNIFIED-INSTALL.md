# Instalação unificada Clutch (VPS CS:GO)

Um **único stack** para ranked, warmup, deathmatch, surf, retake, KZ, etc. O que muda entre servidores é só o `.env` (perfil da sala + IP/porta/screen).

## Quick start (nova VPS)

```bash
sudo adduser csgo   # se ainda não existe
sudo usermod -aG sudo csgo
# instalar CS:GO via SteamCMD em /home/csgo/server (manual ou script existente)

su - csgo
cd ~
git clone https://github.com/tiaguinhorak/api-csgo.git
cd api-csgo
cp .env.example .env
nano .env   # SERVER_PROFILE, keys, RCON, GSLT, screen name
./install.sh
```

Atualizar depois:

```bash
cd ~/api-csgo && ./deploy.sh
```

## O que é igual em TODOS os servidores

| Componente | Descrição |
|------------|-----------|
| api-csgo (pm2) | player-sync, SQLite skins/gloves, RCON |
| `z_clutch_gloves` + `z_clutch_skins_bridge` | skins do site, 1x por partida |
| `clutch_platform_gate` | Steam allowlist |
| Stickers (opcional) | weaponstickers |
| Sync site → SQLite | loadouts + weapons_english.cfg |
| `CSGO_SKINS_SYNC_KEY` | **mesmo valor** no site e em cada VPS |

## O que muda por servidor (.env)

| Variável | Exemplo ranked | Exemplo deathmatch |
|----------|----------------|-------------------|
| `SERVER_PROFILE` | `ranked` | `deathmatch` |
| `SERVER_NAME` | `Clutch #1` | `DM SP #1` |
| `SERVER_MODE_LABEL` | `Competitivo` | `Deathmatch` |
| `CSGO_SERVER_POOL` | `ranked` | `warmup` |
| `CLUTCH_CS_SCREEN` | `csgo-clutch-#1` | `csgo-dm-#1` |
| `CSGO_GSLT_TOKEN` | token Steam | outro token |
| `CSGO_GAME_TYPE/MODE` | 0/1 | conforme modo |
| `CSGO_PUBLIC_HOST` | IP público | IP público |

Perfis `warmup`, `deathmatch`, `surf`, `retake`, `kz`, `casual`, etc. usam o **mesmo pipeline público**:

- skins instantâneas (`defer_live=0`)
- sem match tracker
- extras: nolobby, steamfix, ptah
- `BIND_HOST=0.0.0.0` (site push via LAN)

Perfil `ranked`:

- match tracker
- skins staged durante partida (defer default)
- pool `ranked` na API (fila 5v5)

## Site (Hostinger)

Cada nova VPS precisa aparecer no push de equip:

```env
CSGO_API_URL=http://188.220.168.233:3001
CSGO_WARMUP_API_URL=http://192.168.100.5:3001
CSGO_API_URLS=http://dm-vps:3001,http://surf-vps:3001
```

`CSGO_SKINS_SYNC_KEY` e `API_KEY` iguais em site e todas as VPS.

## Docker?

| Parte | Docker hoje? | Recomendação |
|-------|----------------|--------------|
| **api-csgo** | Fácil | Opcional futuro — hoje **pm2 + bash** funciona bem |
| **CS:GO srcds** | Pesado | SteamCMD + GSLT + screen; container exige imagem custom e mais RAM |
| **Site Next.js** | Sim (Hostinger/Vercel) | Já separado |

**Conclusão:** para CS:GO Legacy, o caminho mais estável é **bare metal + `./install.sh`**. Docker faz sentido depois para orquestrar **só a API** ou quando migrar a CS2 com imagem oficial.

Stack Docker futuro (referência):

```yaml
# docker-compose.yml (futuro — não implementado)
services:
  api-csgo:
    build: .
    env_file: .env
    ports: ["3001:3001"]
  # csgo-srcds: imagem custom + GSLT — não trivial no Legacy
```

## Scripts

| Script | Uso |
|--------|-----|
| `./install.sh` | Primeira instalação + deploy |
| `./deploy.sh` | Git pull + build + plugins + sync |
| `scripts/deploy-unified.sh` | Mesmo que deploy.sh |
| `scripts/deploy-unified.sh --profile=surf` | Override perfil |
| `scripts/start-csgo-screen.sh` | Subir srcds no screen |

## Checklist novo servidor

1. Copiar `.env.example` → `.env`
2. `SERVER_PROFILE` + `SERVER_MODE_LABEL` + `CLUTCH_CS_SCREEN`
3. `CSGO_SKINS_SYNC_KEY` = site
4. `./install.sh`
5. Subir CS:GO: `bash scripts/start-csgo-screen.sh`
6. No **site** `.env`: adicionar URL em `CSGO_API_URLS`
7. No admin site: editar servidor → modo (Deathmatch, etc.) se necessário

## Troubleshooting skins

Igual em qualquer VPS — um deploy resolve:

```bash
cd ~/api-csgo && ./deploy.sh
bash scripts/reload-clutch-skins-ingame.sh
```

Verificar bridge ≥ 3.8.7, gloves 1.4.3, sem `gloves.smx` kgns ativo.
