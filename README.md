# API CS:GO

API para gerenciamento de servidores CS:GO, partidas e skins.

## Rotas

- `GET /health` - Health check
- `/api/matches` - Gerenciamento de partidas e veto
- `/api/servers` - Gerenciamento de servidores via SSH/RCON
- `/api/skins` - Sistema de skins

## Deploy

```bash
npm install
npm run build
pm2 start ecosystem.config.js
```
