/**
 * 公共类型定义。字段名与《埋点协议与SDK规范》第 2 节一致，禁止改动。
 */

/** 业务自定义属性值类型（ArkTS 严格模式，不用 any） */
export type PropValue = string | number | boolean | null;

/** 业务自定义属性 */
export type Props = Record<string, PropValue>;

/** 单条事件结构，与协议第 2 节一一对应 */
export interface EventRecord {
  event_id: string;
  event_name: string;
  event_type: string;
  event_time: number;
  duration_ms: number | null;
  page: string | null;
  refer_page: string | null;
  props: Props | null;

  device_id: string;
  user_id: number | null;
  session_id: string;
  is_new: number;

  platform: string;
  app_version: string;
  build_number: string | null;
  channel: string | null;
  lang: string | null;

  os_version: string | null;
  device_brand: string | null;
  device_model: string | null;
  network: string | null;
  screen_width: number | null;
  screen_height: number | null;
}

/** 批量上报请求体，与协议第 1 节一致 */
export interface BatchBody {
  app_key: string;
  sent_time: number;
  sdk_version: string;
  events: EventRecord[];
}
