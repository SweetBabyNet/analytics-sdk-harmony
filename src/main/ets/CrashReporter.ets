import { errorManager } from '@kit.AbilityKit';
import { EventRecord } from './Types';
import { FileUtil } from './util/FileUtil';
import { Logger } from './Logger';

/** 崩溃事件构造回调（由 Analytics 门面注入；未 setup / 未 enable 时返回 null） */
export type CrashRecordSupplier = (errMsg: string) => EventRecord | null;

/**
 * 崩溃捕获（规范第 3 节 app_crash）：
 * 用 errorManager 注册全局未处理异常观察者；异常发生时同步写入
 * crash_pending.log，下次启动由 EventQueue 读回上报。
 * 注意：errorManager 需在 UIAbility 所在进程主线程注册（setup 时调用），
 * 子进程 / 非 Ability 场景可能收不到回调，详见 README 限制说明。
 */
export class CrashReporter {
  private static registered: boolean = false;

  static register(crashFile: string, supplier: CrashRecordSupplier): void {
    if (CrashReporter.registered) {
      return;
    }
    try {
      const observer: errorManager.ErrorObserver = {
        onUnhandledException: (errMsg: string): void => {
          CrashReporter.onCrash(crashFile, supplier, errMsg);
        }
      };
      errorManager.on('error', observer);
      CrashReporter.registered = true;
      Logger.d('CrashReporter registered');
    } catch (e) {
      Logger.e('CrashReporter register fail');
    }
  }

  private static onCrash(crashFile: string, supplier: CrashRecordSupplier, errMsg: string): void {
    try {
      const record: EventRecord | null = supplier(errMsg);
      if (record !== null) {
        // 同步落盘，下次启动上报
        FileUtil.appendLine(crashFile, JSON.stringify(record));
      }
    } catch (e) {
      // 崩溃回调内不允许再抛异常
    }
  }
}
