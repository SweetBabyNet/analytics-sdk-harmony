# @analytics/sdk — HarmonyOS 埋点 SDK

ArkTS 实现的 HAR 静态共享包，零三方依赖。行为契约见 `analytics/docs/埋点协议与SDK规范.md`，
字段长度以 `analytics/sql/analytics.sql` 的 DDL 为准（SDK 侧超长截断后上报）。

- platform 固定为 `harmony`，SDK 版本 `1.0.0`
- 宿主应用要求：`compatibleSdkVersion >= 5.0.0(12)`（API 12）
- 宿主应用 `module.json5` 需声明权限：
  - `ohos.permission.INTERNET`（事件上报）
  - `ohos.permission.GET_NETWORK_INFO`（network 字段；未声明时降级报 `unknown`）

## 集成步骤

### 方式一：ohpm 从 GitHub 拉取（推荐）

本 SDK 托管在 GitHub，ohpm 支持以 git 地址作为依赖源。在宿主模块（entry）目录执行：

```bash
ohpm install https://github.com/SweetBabyNet/analytics-sdk-harmony.git
```

或在宿主模块的 `oh-package.json5` 中声明（`#v1.0.1` 固定到 tag，推荐显式指定版本）：

```json5
"dependencies": {
  "@analytics/sdk": "https://github.com/SweetBabyNet/analytics-sdk-harmony.git#v1.0.1"
}
```

> SDK 版本号即 git tag（如 `v1.0.1`），发版 = 打 tag 并推送。
> 如需私有仓库，改用 ssh 形式 `git@github.com:<用户名>/analytics-sdk-harmony.git#v1.0.1`。

### 方式二：本地目录

1. 将本目录拷贝到宿主工程（如 `<project>/libs/sdk-harmony`），在宿主模块的
   `oh-package.json5` 中加本地依赖：

   ```json5
   "dependencies": {
     "@analytics/sdk": "file:../../libs/sdk-harmony"
   }
   ```

2. `EntryAbility.ets` 中初始化并接生命周期（共三行调用）：

   ```ts
   import { Analytics } from '@analytics/sdk';

   export default class EntryAbility extends UIAbility {
     onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
       Analytics.setup(this.context, 'cfood-help', 'YOUR_APP_SECRET',
         'https://your-server', true, 'huawei');
     }

     onForeground(): void {
       Analytics.onForeground();
     }

     onBackground(): void {
       Analytics.onBackground();
     }
   }
   ```

   > HAR 无法自动 hook UIAbility 生命周期，`onForeground` / `onBackground` 两行必须手动调用，
   > 否则冷/热启动 app_start、app_end、30 秒定时 flush 都不会触发。

3. 页面埋点：在每个页面的 `aboutToAppear`（或路由进入处）调一行：

   ```ts
   Analytics.trackPage('HomePage');
   ```

   离开时 SDK 自动补发 `page_view`（含停留时长 `duration_ms` 与 `refer_page`），
   停留 <100ms 不上报。

## API 列表

```ts
Analytics.setup(context, appKey, appSecret, endpoint, enable = true, channel = '')
Analytics.enable() / Analytics.disable()
Analytics.track(eventName: string, props: Props = {},
                eventType: string = 'biz', durationMs: number | null = null)
Analytics.trackPage(pageName: string, props: Props = {})
Analytics.trackApiError(apiPath: string, httpCode: number, bizCode: number | null = null)
Analytics.setUserId(userId: number | null)
Analytics.flush()            // 手动立即上报（业务大动作后可选）
Analytics.setDebug(debug: boolean)  // 打印事件日志，flush 阈值降为 5 条 / 5 秒
```

- `Props = Record<string, string | number | boolean | null>`（ArkTS 严格模式，不支持嵌套对象）。
- `track` 的 `eventType` 仅允许 `biz` / `interact` / `exposure`，非法值按 `biz` 处理并打 debug 日志；
  `durationMs` 写入事件 `duration_ms`，仅 exposure 等有时长语义的事件使用，其余传 `null`。
- 未 `setup` 或未 `enable` 时所有采集 API 静默忽略；SDK 内部全 catch-all，不向业务抛异常。

## 隐私合规（两段式）

1. 首次启动、用户**同意隐私政策前**：

   ```ts
   Analytics.setup(this.context, appKey, appSecret, endpoint, false, channel); // enable=false：仅初始化不采集
   ```

2. 用户同意后：

   ```ts
   Analytics.enable(); // 开始采集，含补发 device_register
   ```

`Analytics.disable()` 可随时停止采集（已缓冲的事件会继续上报完，后续事件丢弃）。

## 内置自动事件

`device_register`（每台设备仅一次，带屏幕宽高）、`app_start`（冷/热启动，
`props.launch_type=cold|hot`，冷启动 `duration_ms` 为 setup 到首次 onForeground 耗时）、
`app_end`（退后台，触发立即 flush）、`page_view`、`api_error`（业务网络层调
`trackApiError`）、`app_crash`（见下方限制）。

## 缓冲与上报

内存队列 + JSONL 文件兜底（`context.filesDir/analytics/events.log`，上限 5000 条丢最旧，
启动读回）。flush 触发：队列满 50 条 / 30 秒定时（前台）/ 退后台；每批 ≤100 条、
压缩前 ≤1MB；失败退避 5s→15s→60s→5min；400/401 直接丢弃。请求体 gzip 压缩
（zlib 经临时文件实现，压缩失败自动降级为不压缩、不带 `Content-Encoding` 头，
服务端兼容两种），`X-Sign` 为对最终传输字节的 HMAC-SHA256(appSecret) hex。

## 已知限制

- **崩溃捕获**：`app_crash` 通过 `errorManager.on('error')` 全局观察者捕获未处理异常，
  同步写入 `crash_pending.log`，下次启动时上报（`props.message` 为异常信息前 200 字符，
  不含完整堆栈）。限制：errorManager 只在 UIAbility 所在进程的主线程生效，子进程、
  Native 层崩溃无法捕获；观察者收到回调后系统可能继续运行而非立即终止，此时该事件
  仍会等下次启动才上报。
- **network 细分**：HarmonyOS 不暴露蜂窝网络代际，`cellular` 统一报 `4g`（任务约定）。
- **生命周期**：必须按上文手动接 `onForeground` / `onBackground`。
- **session**：格式 `s-yyyyMMdd-HHmmss-xxxx`，距上一事件 >30 分钟自动开新会话。
- **is_new**：按 DDL 注释"当日首次启动为1"实现——每次 `setup`/`onForeground` 时判定
  当日是否首次活跃，当日首个活跃周期内的事件 `is_new=1`；`device_register` 恒为 1。

## 目录结构

```
sdk-harmony/
├── oh-package.json5          # @analytics/sdk 1.0.0
├── build-profile.json5       # HAR 模块构建配置（SDK 版本随宿主工程）
├── hvigorfile.ts             # harTasks
├── Index.ets                 # export { Analytics }
└── src/main/
    ├── module.json5          # type: har
    └── ets/
        ├── Analytics.ets     # 对外门面（静态类）
        ├── EventQueue.ets    # 内存队列 + JSONL 文件兜底（5000 上限丢最旧）
        ├── FlushScheduler.ets# 50条/30s/后台触发，退避重试，400/401 丢弃
        ├── Uploader.ets      # http + gzip(zlib) + HMAC-SHA256 签名
        ├── DeviceInfo.ets    # 设备/应用/网络/Locale/屏幕信息
        ├── IdentityStore.ets # 首选项持久化 device_id/user_id/is_new/会话
        ├── SessionManager.ets# 30 分钟会话规则
        ├── PageTracker.ets   # page_view 进入/离开补发
        ├── CrashReporter.ets # errorManager 崩溃暂存
        ├── Constants.ets     # 阈值与 DDL 字段长度
        ├── Types.ets         # EventRecord / Props / BatchBody
        ├── Logger.ets        # hilog 封装
        └── util/             # CommonUtil / FileUtil
```
