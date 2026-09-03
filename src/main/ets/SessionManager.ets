import { Constants } from './Constants';
import { CommonUtil } from './util/CommonUtil';
import { IdentityStore } from './IdentityStore';
import { Logger } from './Logger';

/**
 * 会话管理（规范第 4 节）：
 * 进入前台时若无活跃会话或距上一事件 >30 分钟，生成新会话。
 * 格式：s-yyyyMMdd-HHmmss-xxxx。
 * 实现说明：每条事件构造时调用 current()，内部按 30 分钟规则惰性滚动，并持久化到首选项。
 */
export class SessionManager {
  private store: IdentityStore;
  private sessionId: string = '';
  private lastEventTime: number = 0;

  constructor(store: IdentityStore) {
    this.store = store;
    this.sessionId = store.loadSession();
    this.lastEventTime = store.loadSessionLastTime();
  }

  /** 取当前会话 ID（每条事件调用一次；超过 30 分钟无事件则开新会话） */
  current(): string {
    const now: number = Date.now();
    if (this.sessionId.length === 0 || now - this.lastEventTime > Constants.SESSION_TIMEOUT_MS) {
      this.sessionId = SessionManager.generate(now);
      Logger.d('new session: ' + this.sessionId);
    }
    this.lastEventTime = now;
    this.store.saveSession(this.sessionId, this.lastEventTime);
    return this.sessionId;
  }

  private static generate(now: number): string {
    const parts: string[] = CommonUtil.dateParts(now);
    const rand: string = Math.floor(Math.random() * 0x10000).toString(16).padStart(4, '0');
    return 's-' + parts[0] + '-' + parts[1] + '-' + rand;
  }
}
