import { Constants } from './Constants';
import { EventRecord } from './Types';
import { EventQueue } from './EventQueue';
import { Uploader, UploadResult } from './Uploader';
import { Logger } from './Logger';

/**
 * flush 调度（规范第 5 节，先到先触发）：
 * ① 队列满 50 条；② 距上次 flush 30 秒（前台定时器）；③ 退到后台（app_end）。
 * 每批 <=100 条，压缩前 body <=1MB；失败退避 5s->15s->60s->5min；400/401 丢弃。
 * debug 模式阈值降为 5 条 / 5 秒。
 */
export class FlushScheduler {
  private queue: EventQueue;
  private uploader: Uploader;
  private appKey: string;

  private timerId: number = -1;
  private retryTimerId: number = -1;
  private running: boolean = false;
  private flushing: boolean = false;
  private backoffIdx: number = 0;
  private debug: boolean = false;

  constructor(queue: EventQueue, uploader: Uploader, appKey: string) {
    this.queue = queue;
    this.uploader = uploader;
    this.appKey = appKey;
  }

  setDebug(debug: boolean): void {
    this.debug = debug;
    if (this.running) {
      this.stopTimer();
      this.startTimer();
    }
  }

  /** 前台：启动 30 秒（debug 5 秒）定时器 */
  start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.startTimer();
  }

  /** 后台 / disable：停定时器并立即 flush 一次 */
  stopAndFlush(): void {
    this.running = false;
    this.stopTimer();
    this.flush();
  }

  /** 入队后检查条数阈值 */
  onEventEnqueued(): void {
    const threshold: number = this.debug ? Constants.DEBUG_FLUSH_COUNT : Constants.FLUSH_COUNT;
    if (this.queue.size() >= threshold) {
      this.flush();
    }
  }

  /** 立即上报：循环发送直到队列清空或失败 */
  flush(): void {
    if (this.flushing) {
      return;
    }
    if (this.queue.size() === 0) {
      return;
    }
    this.flushing = true;
    const batch: EventRecord[] = this.fitBatch(this.queue.peek(Constants.BATCH_MAX));
    this.uploader.upload(batch)
      .then((result: UploadResult) => {
        if (result === UploadResult.RETRY) {
          Logger.e('flush retryable fail, batch kept, count=' + batch.length);
          this.flushing = false;
          this.scheduleRetry();
          return;
        }
        if (result === UploadResult.DISCARD) {
          Logger.e('flush discarded by server (400/401), count=' + batch.length);
        } else {
          Logger.d('flush success, count=' + batch.length);
        }
        this.queue.removeFirst(batch.length);
        this.backoffIdx = 0;
        this.flushing = false;
        // 还有剩余则继续发下一批
        if (this.queue.size() > 0) {
          this.flush();
        }
      })
      .catch(() => {
        this.flushing = false;
        this.scheduleRetry();
      });
  }

  /** 压缩前 body <=1MB：超限则对半缩减批次 */
  private fitBatch(batch: EventRecord[]): EventRecord[] {
    let fitted: EventRecord[] = batch;
    while (fitted.length > 1 && Uploader.bodyBytes(this.appKey, fitted) > Constants.BODY_MAX_BYTES) {
      fitted = fitted.slice(0, Math.floor(fitted.length / 2));
    }
    return fitted;
  }

  /** 指数退避重试：5s -> 15s -> 60s -> 5min 封顶 */
  private scheduleRetry(): void {
    if (this.retryTimerId >= 0) {
      return;
    }
    const idx: number = Math.min(this.backoffIdx, Constants.BACKOFF_MS.length - 1);
    const delay: number = Constants.BACKOFF_MS[idx];
    this.backoffIdx++;
    Logger.d('retry in ' + delay + 'ms');
    this.retryTimerId = setTimeout(() => {
      this.retryTimerId = -1;
      this.flush();
    }, delay);
  }

  private startTimer(): void {
    const interval: number = this.debug ? Constants.DEBUG_FLUSH_INTERVAL_MS : Constants.FLUSH_INTERVAL_MS;
    this.timerId = setInterval(() => {
      this.flush();
    }, interval);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}
