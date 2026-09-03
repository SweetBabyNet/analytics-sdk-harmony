/**
 * 常量定义。字段长度以 sql/analytics.sql 的 DDL 为唯一准绳（规范第 8 节）。
 */
export class Constants {
  static readonly SDK_VERSION: string = '1.0.0';
  static readonly PLATFORM: string = 'harmony';

  /** 本地存储目录（filesDir 下）与文件名 */
  static readonly STORE_DIR: string = '/analytics';
  static readonly EVENTS_FILE: string = '/events.log';
  static readonly CRASH_FILE: string = '/crash_pending.log';
  static readonly PREFS_NAME: string = 'analytics_identity';

  /** 缓冲与上报策略（规范第 5 节） */
  static readonly QUEUE_MAX: number = 5000;          // 本地文件上限，超出丢最旧
  static readonly FLUSH_COUNT: number = 50;          // 队列满 50 条触发 flush
  static readonly FLUSH_INTERVAL_MS: number = 30000; // 30 秒定时 flush
  static readonly BATCH_MAX: number = 100;           // 每批 <=100 条
  static readonly BODY_MAX_BYTES: number = 1024 * 1024; // 压缩前 body <= 1MB
  static readonly DEBUG_FLUSH_COUNT: number = 5;     // debug 模式 5 条
  static readonly DEBUG_FLUSH_INTERVAL_MS: number = 5000; // debug 模式 5 秒

  /** 失败退避：5s -> 15s -> 60s -> 5min 封顶 */
  static readonly BACKOFF_MS: number[] = [5000, 15000, 60000, 300000];

  /** 会话 30 分钟规则（规范第 4 节） */
  static readonly SESSION_TIMEOUT_MS: number = 30 * 60 * 1000;

  /** 热启动判定：回前台且距上次退出 >30s 算新启动（规范第 3 节） */
  static readonly HOT_START_GAP_MS: number = 30000;

  /** 页面停留 <100ms 不上报 */
  static readonly PAGE_MIN_STAY_MS: number = 100;

  /** 网络超时 */
  static readonly HTTP_TIMEOUT_MS: number = 15000;

  /** duration_ms 为 INT，上限 2^31-1 */
  static readonly INT_MAX: number = 2147483647;
}

/** 字段长度（DDL 为准），SDK 侧超长截断后再上报 */
export class FieldLen {
  static readonly EVENT_ID: number = 40;
  static readonly EVENT_NAME: number = 64;
  static readonly EVENT_TYPE: number = 16;
  static readonly DEVICE_ID: number = 40;
  static readonly SESSION_ID: number = 40;
  static readonly PLATFORM: number = 16;
  static readonly APP_VERSION: number = 16;
  static readonly BUILD_NUMBER: number = 16;
  static readonly CHANNEL: number = 32;
  static readonly LANG: number = 16;
  static readonly OS_VERSION: number = 32;
  static readonly DEVICE_BRAND: number = 32;
  static readonly DEVICE_MODEL: number = 64;
  static readonly NETWORK: number = 8;
  static readonly PAGE: number = 64;
  static readonly REFER_PAGE: number = 64;
}

/** 内置事件名（规范第 3 节） */
export class EventNames {
  static readonly DEVICE_REGISTER: string = 'device_register';
  static readonly APP_START: string = 'app_start';
  static readonly APP_END: string = 'app_end';
  static readonly PAGE_VIEW: string = 'page_view';
  static readonly API_ERROR: string = 'api_error';
  static readonly APP_CRASH: string = 'app_crash';
}

/** 事件类型枚举值（协议第 2 节） */
export class EventTypes {
  static readonly LIFECYCLE: string = 'lifecycle';
  static readonly PAGE: string = 'page';
  static readonly INTERACT: string = 'interact';
  static readonly EXPOSURE: string = 'exposure';
  static readonly BIZ: string = 'biz';
  static readonly ERROR: string = 'error';
}
