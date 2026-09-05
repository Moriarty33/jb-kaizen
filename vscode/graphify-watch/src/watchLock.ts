import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { log } from './log';

const LOCK_FILE = '.watch.lock';
const HEARTBEAT_MS = 5000;

interface LockData {
  pid: number;
  token: string;
  heartbeat: number;
}

export class WatchLock {
  private heartbeatTimer?: NodeJS.Timeout;
  private ownsLock = false;
  private readonly token = crypto.randomUUID();

  constructor(
    private readonly outPath: string,
    private readonly staleLockSeconds: number,
  ) {}

  get isOwner(): boolean {
    return this.ownsLock;
  }

  private get lockPath(): string {
    return path.join(this.outPath, LOCK_FILE);
  }

  read(): LockData | undefined {
    try {
      if (!fs.existsSync(this.lockPath)) {
        return undefined;
      }
      const parsed = JSON.parse(fs.readFileSync(this.lockPath, 'utf8')) as LockData;
      if (
        typeof parsed.pid === 'number' &&
        typeof parsed.heartbeat === 'number' &&
        typeof parsed.token === 'string'
      ) {
        return parsed;
      }
    } catch {
      /* ignore corrupt lock */
    }
    return undefined;
  }

  isFresh(lock: LockData): boolean {
    return Date.now() - lock.heartbeat < this.staleLockSeconds * 1000;
  }

  isForeignAndFresh(): boolean {
    const existing = this.read();
    return !!existing && this.isFresh(existing) && existing.pid !== process.pid;
  }

  isStale(): boolean {
    const lock = this.read();
    return !lock || !this.isFresh(lock);
  }

  acquire(): boolean {
    if (!this.claim()) {
      return false;
    }
    this.ownsLock = true;
    this.heartbeatTimer = setInterval(() => {
      if (this.ownsLock) {
        this.write();
      }
    }, HEARTBEAT_MS);
    return true;
  }

  private claim(): boolean {
    try {
      fs.mkdirSync(this.outPath, { recursive: true });
      fs.writeFileSync(this.lockPath, this.serialize(), { flag: 'wx' });
      return true;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'EEXIST') {
        log(`Failed to claim lock: ${String(err)}`);
        return false;
      }
    }
    const existing = this.read();
    if (existing && this.isFresh(existing) && !this.isMine(existing)) {
      return false;
    }
    return this.takeOver();
  }

  private takeOver(): boolean {
    const tmp = `${this.lockPath}.${this.token}.tmp`;
    try {
      fs.writeFileSync(tmp, this.serialize(), 'utf8');
      fs.renameSync(tmp, this.lockPath);
    } catch (err) {
      log(`Failed to take over lock: ${String(err)}`);
      try {
        fs.rmSync(tmp, { force: true });
      } catch {
        /* ignore */
      }
      return false;
    }
    const after = this.read();
    return !!after && this.isMine(after);
  }

  private isMine(lock: LockData): boolean {
    return lock.token === this.token;
  }

  release(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = undefined;
    }
    if (this.ownsLock) {
      try {
        const existing = this.read();
        if (existing && this.isMine(existing)) {
          fs.unlinkSync(this.lockPath);
        }
      } catch {
        /* ignore */
      }
      this.ownsLock = false;
    }
  }

  private serialize(): string {
    const data: LockData = { pid: process.pid, token: this.token, heartbeat: Date.now() };
    return JSON.stringify(data);
  }

  private write(): void {
    try {
      fs.mkdirSync(this.outPath, { recursive: true });
      fs.writeFileSync(this.lockPath, this.serialize(), 'utf8');
    } catch (err) {
      log(`Failed to write lock: ${String(err)}`);
    }
  }
}
