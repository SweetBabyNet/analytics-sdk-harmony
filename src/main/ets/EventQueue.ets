import { Constants } from './Constants';
import { EventRecord } from './Types';
import { FileUtil } from './util/FileUtil';
import { Logger } from './Logger';

/**
 * 事件队列（规范第 5 节）：内存数组 + JSONL 文件兜底。
 * - 路径：context.filesDir + '/analytics/events.log'
 * - 上限 5000 条，超出丢最旧
 * - 启动时读回（含上次崩溃暂存的 crash_pending.log）
 */
export class EventQueue {
  private events: EventRecord[] = [];
  private eventsFile: string = '';
  private crashFile: string = '';

  /** filesDir 传入；初始化目录并读回历史事件 */
  init(filesDir: string): void {
    const dir: string = filesDir + Constants.STORE_DIR;
    FileUtil.ensureDir(dir);
    this.eventsFile = dir + Constants.EVENTS_FILE;
    this.crashFile = dir + Constants.CRASH_FILE;

    this.loadFromFile(this.eventsFile, false);
    // 崩溃事件：读回后清空暂存文件，避免重复上报
    this.loadFromFile(this.crashFile, true);
    // 启动读回后统一落盘一次（合并崩溃事件、清理坏行、执行上限）
    this.persistAll();
    Logger.d('EventQueue loaded, size=' + this.events.length);
  }

  size(): number {
    return this.events.length;
  }

  /** 入队：内存 + 追加落盘；超过 5000 丢最旧 */
  enqueue(record: EventRecord): void {
    this.events.push(record);
    if (this.events.length > Constants.QUEUE_MAX) {
      this.events.shift();
      // 发生了丢弃，整体重写保持文件与内存一致
      this.persistAll();
      return;
    }
    FileUtil.appendLine(this.eventsFile, JSON.stringify(record));
  }

  /** 取队首至多 n 条（不移除） */
  peek(n: number): EventRecord[] {
    return this.events.slice(0, n);
  }

  /** flush 成功 / 400/401 丢弃后移除队首 n 条并重写文件 */
  removeFirst(n: number): void {
    if (n <= 0) {
      return;
    }
    this.events.splice(0, n);
    this.persistAll();
  }

  crashFilePath(): string {
    return this.crashFile;
  }

  private loadFromFile(path: string, clearAfter: boolean): void {
    const lines: string[] = FileUtil.readLines(path);
    for (const line of lines) {
      try {
        const record = JSON.parse(line) as EventRecord;
        if (record !== null && typeof record.event_name === 'string' && record.event_name.length > 0) {
          this.events.push(record);
        }
      } catch (e) {
        // 坏行丢弃
      }
    }
    if (clearAfter && lines.length > 0) {
      FileUtil.truncate(path);
    }
    // 读回期间也可能超上限（events.log + crash 合并）
    while (this.events.length > Constants.QUEUE_MAX) {
      this.events.shift();
    }
  }

  private persistAll(): void {
    const lines: string[] = [];
    for (const record of this.events) {
      try {
        lines.push(JSON.stringify(record));
      } catch (e) {
        // 序列化失败的事件丢弃
      }
    }
    FileUtil.rewriteLines(this.eventsFile, lines);
  }
}
