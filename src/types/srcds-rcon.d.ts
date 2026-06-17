declare module 'srcds-rcon' {
  export interface RCONOptions {
    host: string;
    port: number;
    password: string;
    timeout?: number;
  }

  export class RCON {
    constructor(options: RCONOptions);
    connect(): Promise<void>;
    disconnect(): Promise<void>;
    command(command: string): Promise<string>;
    authenticate(): Promise<boolean>;
  }
}
