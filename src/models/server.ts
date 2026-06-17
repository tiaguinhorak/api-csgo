export interface GameServer {
  id: string;
  name: string;
  host: string;
  sshPort: number;
  sshUser: string;
  sshKey?: string;
  sshPassword?: string;
  rconPort: number;
  rconPassword: string;
  csgoDir: string;
  screenSession: string;
  status: 'online' | 'offline' | 'busy';
  currentMatchId?: string;
  port: number;
  tickrate: number;
}

export interface CreateServerDTO {
  name: string;
  host: string;
  sshPort?: number;
  sshUser: string;
  sshKey?: string;
  sshPassword?: string;
  rconPort?: number;
  rconPassword: string;
  csgoDir: string;
  port?: number;
  tickrate?: number;
}
