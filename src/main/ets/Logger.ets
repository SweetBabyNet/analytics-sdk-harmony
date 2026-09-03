import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * SDK 内部日志。debug 模式打印事件日志（规范第 5 节 setDebug）。
 */
export class Logger {
  private static readonly DOMAIN: number = 0xA001;
  private static readonly TAG: string = 'Analytics';
  private static debug: boolean = false;

  static setDebug(debug: boolean): void {
    Logger.debug = debug;
  }

  static isDebug(): boolean {
    return Logger.debug;
  }

  static d(msg: string): void {
    if (Logger.debug) {
      hilog.info(Logger.DOMAIN, Logger.TAG, '%{public}s', msg);
    }
  }

  static e(msg: string): void {
    hilog.error(Logger.DOMAIN, Logger.TAG, '%{public}s', msg);
  }
}
