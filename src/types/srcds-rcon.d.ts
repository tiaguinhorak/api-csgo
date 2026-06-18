declare module 'srcds-rcon' {
  interface RconOptions {
    address: string;
    password: string;
    timeout?: number;
  }

  interface RconClient {
    connect(): Promise<void>;
    disconnect(): Promise<void>;
    command(command: string): Promise<string>;
  }

  function createRcon(options: RconOptions): RconClient;
  export = createRcon;
}
