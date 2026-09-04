import { common } from '@kit.AbilityKit';
import { Constants, EventNames, EventTypes, FieldLen } from './Constants';
import { EventRecord, Props } from './Types';
import { CommonUtil } from './util/CommonUtil';
import { Logger } from './Logger';
import { EventQueue } from './EventQueue';
import { Uploader } from './Uploader';
import { FlushScheduler } from './FlushScheduler';
import { DeviceInfoProvider } from './DeviceInfo';
import { IdentityStore } from './IdentityStore';
import { SessionManager } from './SessionManager';
import { PageTracker } from './PageTracker';
import { CrashReporter } from './CrashReporter';

/**
 * 埋点 SDK 对外门面（静态类）。API 与《埋点协议与SDK规范》第 6 节一致。
 *
 * 用法：
 *   Analytics.setup(this.context, appKey, appSecret, endpoint, true, 'appstore'); // EntryAbility.onCreate
 *   Analytics.onForeground(); // EntryAbility.onForeground
 *   Analytics.onBackground(); // EntryAbility.onBackground
 *
 * 全异步、catch-all：任何情况不向业务抛异常；未 setup / 未 enable 时静默忽略。
 */
export class Analytics {
  private static inited: boolean = false;
  private static enabled: boolean = false;
  private static debug: boolean = false;

  private static appKey: string = '';
  private static channel: string | null = null;

  private static identity: IdentityStore | null = null;
  private static session: SessionManager | null = null;
  private static device: DeviceInfoProvider | null = null;
  private static queue: EventQueue | null = null;
  private static scheduler: FlushScheduler | null = null;
  private static pageTracker: PageTracker | null = null;

  private static setupTime: number = 0;
  private static lastBackgroundTime: number = 0;
  private static firstForegroundDone: boolean = false;

  /**
   * 初始化。enable=false 时仅初始化不采集（用于"同意隐私政策后再采集"，
   * 同意后调用 Analytics.enable()，含补发 device_register）。
   */
  static setup(context: common.UIAbilityContext, appKey: string, appSecret: string, endpoint: string,
    enable: boolean = true, channel: string = ''): void {
    try {
      if (Analytics.inited) {
        Logger.e('Analytics.setup already called, ignored');
        return;
      }
      Analytics.inited = true;
      Analytics.appKey = CommonUtil.trunc(appKey, 32) ?? appKey;
      Analytics.channel = channel.length > 0 ? CommonUtil.trunc(channel, FieldLen.CHANNEL) : null;
      Analytics.setupTime = Date.now();

      const identity = new IdentityStore();
      identity.init(context);
      Analytics.identity = identity;
      Analytics.session = new SessionManager(identity);

      const device = new DeviceInfoProvider();
      device.load();
      Analytics.device = device;

      const queue = new EventQueue();
      queue.init(context.filesDir);
      Analytics.queue = queue;

      const uploader = new Uploader(endpoint, appKey, appSecret, context.filesDir);
      Analytics.scheduler = new FlushScheduler(queue, uploader, appKey);

      Analytics.pageTracker = new PageTracker(
        (page: string, referPage: string | null, durationMs: number, props: Props | null): void => {
          Analytics.emit(EventNames.PAGE_VIEW, EventTypes.PAGE, page, referPage, durationMs, props, false, -1);
        });

      CrashReporter.register(queue.crashFilePath(), (errMsg: string): EventRecord | null => {
        if (!Analytics.enabled) {
          return null;
        }
        const props: Props = {
          'message': errMsg.length > 200 ? errMsg.substring(0, 200) : errMsg
        };
        return Analytics.buildEvent(EventNames.APP_CRASH, EventTypes.ERROR, null, null, null, props, false, -1);
      });

      if (enable) {
        Analytics.enable();
      }
      Logger.d('Analytics.setup done, enable=' + enable);
    } catch (e) {
      Logger.e('Analytics.setup exception');
    }
  }

  /** 开始采集（含补发 device_register） */
  static enable(): void {
    try {
      if (!Analytics.inited || Analytics.enabled) {
        return;
      }
      Analytics.enabled = true;
      Analytics.identity?.refreshIsNew(Date.now());
      Analytics.scheduler?.start();
      // 每台设备仅首次一次 device_register（is_new=1，带屏幕宽高）
      if (Analytics.identity !== null && !Analytics.identity.deviceRegistered) {
        Analytics.emit(EventNames.DEVICE_REGISTER, EventTypes.LIFECYCLE, null, null, null, null, true, 1);
        Analytics.identity.markDeviceRegistered();
      }
    } catch (e) {
      Logger.e('Analytics.enable exception');
    }
  }

  /** 停止采集：丢弃后续事件，已缓冲事件继续上报 */
  static disable(): void {
    try {
      if (!Analytics.inited || !Analytics.enabled) {
        return;
      }
      Analytics.enabled = false;
      Analytics.scheduler?.stopAndFlush();
    } catch (e) {
      Logger.e('Analytics.disable exception');
    }
  }

  /**
   * 业务自定义事件（规范第 6 节）。
   * eventType 仅允许 biz / interact / exposure（page/lifecycle/error 由专用 API 或 SDK 内部产生）；
   * 非法值按 biz 处理并打 debug 日志。durationMs 仅 exposure 等有时长语义的事件使用，其余传 null。
   * 兼容旧调用：track(name) / track(name, props) 等价于 eventType=biz、durationMs=null。
   */
  static track(eventName: string, props: Props = {}, eventType: string = EventTypes.BIZ,
    durationMs: number | null = null): void {
    try {
      let type: string = eventType;
      if (type !== EventTypes.BIZ && type !== EventTypes.INTERACT && type !== EventTypes.EXPOSURE) {
        Logger.d('Analytics.track: invalid eventType "' + eventType + '", fallback to biz');
        type = EventTypes.BIZ;
      }
      Analytics.emit(eventName, type, Analytics.pageTracker?.getCurrentPage() ?? null, null, durationMs, props, false, -1);
    } catch (e) {
      Logger.e('Analytics.track exception');
    }
  }

  /** 页面跟踪：记录进入；离开时补发 page_view（duration_ms 停留时长，refer_page 上一页，<100ms 不上报） */
  static trackPage(pageName: string, props: Props = {}): void {
    try {
      if (!Analytics.enabled) {
        return;
      }
      Analytics.pageTracker?.trackPage(pageName, props);
    } catch (e) {
      Logger.e('Analytics.trackPage exception');
    }
  }

  /** 接口异常（业务网络层钩子调用） */
  static trackApiError(apiPath: string, httpCode: number, bizCode: number | null = null): void {
    try {
      const props: Props = {
        'api_path': apiPath,
        'http_code': httpCode,
        'biz_code': bizCode
      };
      Analytics.emit(EventNames.API_ERROR, EventTypes.ERROR, Analytics.pageTracker?.getCurrentPage() ?? null,
        null, null, props, false, -1);
    } catch (e) {
      Logger.e('Analytics.trackApiError exception');
    }
  }

  /** 设置 / 清除用户 ID（持久化，杀进程重进仍有；未设置为 null） */
  static setUserId(userId: number | null): void {
    try {
      if (!Analytics.inited) {
        return;
      }
      Analytics.identity?.setUserId(userId);
    } catch (e) {
      Logger.e('Analytics.setUserId exception');
    }
  }

  /** 手动立即上报（业务大动作后可选调用） */
  static flush(): void {
    try {
      if (!Analytics.inited) {
        return;
      }
      Analytics.scheduler?.flush();
    } catch (e) {
      Logger.e('Analytics.flush exception');
    }
  }

  /** debug：打印事件日志，flush 阈值降为 5 条 / 5 秒 */
  static setDebug(debug: boolean): void {
    try {
      Analytics.debug = debug;
      Logger.setDebug(debug);
      Analytics.scheduler?.setDebug(debug);
    } catch (e) {
      // ignore
    }
  }

  /**
   * 前台（业务在 EntryAbility.onForeground 调一行）。
   * 冷启动 app_start：duration_ms 为 setup 到首次 onForeground 耗时；
   * 热启动：回前台且距上次退出 >30s 算新启动，duration_ms 为 null。
   */
  static onForeground(): void {
    try {
      if (!Analytics.inited) {
        return;
      }
      const now: number = Date.now();
      Analytics.identity?.refreshIsNew(now);
      if (!Analytics.enabled) {
        return;
      }
      if (!Analytics.firstForegroundDone) {
        Analytics.firstForegroundDone = true;
        const props: Props = { 'launch_type': 'cold' };
        Analytics.emit(EventNames.APP_START, EventTypes.LIFECYCLE, null, null,
          Math.max(0, now - Analytics.setupTime), props, false, -1);
      } else if (Analytics.lastBackgroundTime > 0
        && now - Analytics.lastBackgroundTime > Constants.HOT_START_GAP_MS) {
        const props: Props = { 'launch_type': 'hot' };
        Analytics.emit(EventNames.APP_START, EventTypes.LIFECYCLE, null, null, null, props, false, -1);
      }
      Analytics.lastBackgroundTime = 0;
      Analytics.scheduler?.start();
    } catch (e) {
      Logger.e('Analytics.onForeground exception');
    }
  }

  /** 后台（业务在 EntryAbility.onBackground 调一行）：app_end + 立即 flush */
  static onBackground(): void {
    try {
      if (!Analytics.inited || !Analytics.enabled) {
        return;
      }
      Analytics.pageTracker?.onBackground();
      Analytics.lastBackgroundTime = Date.now();
      Analytics.emit(EventNames.APP_END, EventTypes.LIFECYCLE, null, null, null, null, false, -1);
      Analytics.scheduler?.stopAndFlush();
    } catch (e) {
      Logger.e('Analytics.onBackground exception');
    }
  }

  // ---------------- 内部 ----------------

  /**
   * 构造并入队事件。isNew 传 -1 表示取当前"当日首次启动"标记，否则强制（device_register 传 1）。
   */
  private static emit(eventName: string, eventType: string, page: string | null, referPage: string | null,
    durationMs: number | null, props: Props | null, withScreen: boolean, isNew: number): void {
    if (!Analytics.inited || !Analytics.enabled) {
      return;
    }
    const record: EventRecord | null = Analytics.buildEvent(eventName, eventType, page, referPage,
      durationMs, props, withScreen, isNew);
    if (record === null) {
      return;
    }
    Analytics.queue?.enqueue(record);
    Analytics.scheduler?.onEventEnqueued();
    Logger.d('event: ' + record.event_name + ' queue=' + (Analytics.queue?.size() ?? 0));
  }

  private static buildEvent(eventName: string, eventType: string, page: string | null, referPage: string | null,
    durationMs: number | null, props: Props | null, withScreen: boolean, isNew: number): EventRecord | null {
    const identity = Analytics.identity;
    const device = Analytics.device;
    const session = Analytics.session;
    if (identity === null || device === null || session === null) {
      return null;
    }
    let duration: number | null = durationMs;
    if (duration !== null && duration > Constants.INT_MAX) {
      duration = Constants.INT_MAX;
    }
    const record: EventRecord = {
      event_id: CommonUtil.trunc(CommonUtil.uuid(), FieldLen.EVENT_ID) ?? '',
      event_name: CommonUtil.trunc(eventName, FieldLen.EVENT_NAME) ?? '',
      event_type: CommonUtil.trunc(eventType, FieldLen.EVENT_TYPE) ?? '',
      event_time: Date.now(),
      duration_ms: duration,
      page: CommonUtil.trunc(page, FieldLen.PAGE),
      refer_page: CommonUtil.trunc(referPage, FieldLen.REFER_PAGE),
      props: props,

      device_id: CommonUtil.trunc(identity.deviceId, FieldLen.DEVICE_ID) ?? '',
      user_id: identity.userId,
      session_id: CommonUtil.trunc(session.current(), FieldLen.SESSION_ID) ?? '',
      is_new: isNew >= 0 ? isNew : (identity.isNewToday ? 1 : 0),

      platform: Constants.PLATFORM,
      app_version: CommonUtil.trunc(device.appVersion, FieldLen.APP_VERSION) ?? '',
      build_number: device.buildNumber,
      channel: Analytics.channel,
      lang: device.lang,

      os_version: device.osVersion,
      device_brand: device.deviceBrand,
      device_model: device.deviceModel,
      network: CommonUtil.trunc(DeviceInfoProvider.currentNetwork(), FieldLen.NETWORK),
      screen_width: withScreen ? device.screenWidth : null,
      screen_height: withScreen ? device.screenHeight : null
    };
    return record;
  }
}
