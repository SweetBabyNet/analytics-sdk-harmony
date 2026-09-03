import { Constants } from './Constants';
import { Props } from './Types';

/** 页面事件发出回调（由 Analytics 门面注入，避免模块循环依赖） */
export type PageEventSink = (page: string, referPage: string | null, durationMs: number, props: Props | null) => void;

/**
 * 页面跟踪（规范第 3 节 page_view）：
 * trackPage() 记录进入；离开该页时补发 page_view，duration_ms 为停留时长，
 * refer_page 为上一页面；停留 <100ms 不上报。
 */
export class PageTracker {
  private sink: PageEventSink;
  private currentPage: string | null = null;
  private currentRefer: string | null = null;
  private enterTime: number = 0;
  private currentProps: Props | null = null;

  constructor(sink: PageEventSink) {
    this.sink = sink;
  }

  trackPage(pageName: string, props: Props | null): void {
    const prevPage: string | null = this.currentPage;
    // 先补发上一页的离开事件
    this.leaveCurrent();
    this.currentPage = pageName;
    this.currentRefer = prevPage;
    this.enterTime = Date.now();
    this.currentProps = props;
  }

  /** 退到后台视为离开当前页 */
  onBackground(): void {
    this.leaveCurrent();
    this.currentPage = null;
    this.currentRefer = null;
    this.currentProps = null;
  }

  private leaveCurrent(): void {
    if (this.currentPage === null) {
      return;
    }
    const duration: number = Date.now() - this.enterTime;
    if (duration >= Constants.PAGE_MIN_STAY_MS) {
      this.sink(this.currentPage, this.currentRefer, duration, this.currentProps);
    }
  }
}
