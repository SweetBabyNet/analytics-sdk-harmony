import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Constants } from './Constants';
import { CommonUtil } from './util/CommonUtil';
import { Logger } from './Logger';

/**
 * 标识持久化（规范第 4 节）：device_id / user_id / is_new / device_register 已发标记 / 会话。
 * 存储介质：首选项（@kit.ArkData preferences）。
 */
export class IdentityStore {
  private static readonly KEY_DEVICE_ID: string = 'device_id';
  private static readonly KEY_USER_ID: string = 'user_id';
  private static readonly KEY_DEVICE_REGISTERED: string = 'device_registered';
  private static readonly KEY_LAST_ACTIVE_DATE: string = 'last_active_date';
  private static readonly KEY_SESSION_ID: string = 'session_id';
  private static readonly KEY_SESSION_LAST_TIME: string = 'session_last_time';

  private prefs: preferences.Preferences | null = null;

  deviceId: string = '';
  userId: number | null = null;
  deviceRegistered: boolean = false;
  /** 当日首次启动（含当次启动所在日期内的所有事件，DDL: 当日首次启动为1） */
  isNewToday: boolean = false;

  init(context: common.UIAbilityContext): void {
    try {
      this.prefs = preferences.getPreferencesSync(context, { name: Constants.PREFS_NAME });
    } catch (e) {
      Logger.e('IdentityStore init preferences fail');
      return;
    }
    // device_id：首启用 UUID 持久化
    let did: string = this.getString(IdentityStore.KEY_DEVICE_ID, '');
    if (did.length === 0) {
      did = CommonUtil.uuid();
      this.put(IdentityStore.KEY_DEVICE_ID, did);
    }
    this.deviceId = CommonUtil.trunc(did, 40) ?? did.substring(0, 40);

    // user_id：未设置为 null；-1 为本地哨兵值
    const uid: number = this.getNumber(IdentityStore.KEY_USER_ID, -1);
    this.userId = uid >= 0 ? uid : null;

    this.deviceRegistered = this.getBool(IdentityStore.KEY_DEVICE_REGISTERED, false);
    this.refreshIsNew(Date.now());
  }

  /** 当日首次启动判定：进入前台 / setup 时调用一次 */
  refreshIsNew(now: number): void {
    const today: string = CommonUtil.todayKey(now);
    const last: string = this.getString(IdentityStore.KEY_LAST_ACTIVE_DATE, '');
    this.isNewToday = last !== today;
    if (this.isNewToday) {
      this.put(IdentityStore.KEY_LAST_ACTIVE_DATE, today);
    }
  }

  setUserId(userId: number | null): void {
    this.userId = userId;
    this.put(IdentityStore.KEY_USER_ID, userId === null ? -1 : userId);
  }

  markDeviceRegistered(): void {
    this.deviceRegistered = true;
    this.put(IdentityStore.KEY_DEVICE_REGISTERED, true);
  }

  // ---- 会话持久化（供 SessionManager 使用） ----

  loadSession(): string {
    return this.getString(IdentityStore.KEY_SESSION_ID, '');
  }

  loadSessionLastTime(): number {
    return this.getNumber(IdentityStore.KEY_SESSION_LAST_TIME, 0);
  }

  saveSession(sessionId: string, lastTime: number): void {
    this.put(IdentityStore.KEY_SESSION_ID, sessionId);
    this.put(IdentityStore.KEY_SESSION_LAST_TIME, lastTime);
  }

  // ---- KV 基础操作（catch-all，持久化失败不影响采集） ----

  private getString(key: string, defValue: string): string {
    try {
      if (this.prefs !== null) {
        return this.prefs.getSync(key, defValue) as string;
      }
    } catch (e) {
      // ignore
    }
    return defValue;
  }

  private getNumber(key: string, defValue: number): number {
    try {
      if (this.prefs !== null) {
        return this.prefs.getSync(key, defValue) as number;
      }
    } catch (e) {
      // ignore
    }
    return defValue;
  }

  private getBool(key: string, defValue: boolean): boolean {
    try {
      if (this.prefs !== null) {
        return this.prefs.getSync(key, defValue) as boolean;
      }
    } catch (e) {
      // ignore
    }
    return defValue;
  }

  private put(key: string, value: string | number | boolean): void {
    try {
      if (this.prefs !== null) {
        this.prefs.putSync(key, value);
        this.prefs.flush();
      }
    } catch (e) {
      // ignore
    }
  }
}
