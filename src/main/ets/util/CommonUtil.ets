import { util } from '@kit.ArkTS';

/**
 * 通用小工具：截断、UUID、UTF-8 编解码、hex。
 */
export class CommonUtil {
  /** 超长字符串截断到 DDL 长度（规范第 8 节）；null 保持 null（禁止空字符串假数据） */
  static trunc(s: string | null, max: number): string | null {
    if (s === null) {
      return null;
    }
    return s.length > max ? s.substring(0, max) : s;
  }

  static uuid(): string {
    try {
      return util.generateRandomUUID(false);
    } catch (e) {
      // 兜底：时间戳 + 随机数拼 UUID 形态
      const rand: string = Math.floor(Math.random() * 0xFFFFFFFF).toString(16);
      return 'fallback-' + Date.now().toString(16) + '-' + rand;
    }
  }

  static utf8Encode(s: string): Uint8Array {
    // encodeIntoUint8Array 在新版 SDK 返回 EncodeIntoUint8ArrayInfo 且签名不同，统一用 encode
    return util.TextEncoder.create('utf-8').encode(s);
  }

  static utf8Length(s: string): number {
    return CommonUtil.utf8Encode(s).length;
  }

  static toHex(data: Uint8Array): string {
    const hexChars: string = '0123456789abcdef';
    let out: string = '';
    for (let i = 0; i < data.length; i++) {
      const v: number = data[i];
      out += hexChars.charAt((v >> 4) & 0xF) + hexChars.charAt(v & 0xF);
    }
    return out;
  }

  static pad2(n: number): string {
    return n < 10 ? '0' + n : n.toString();
  }

  /** 会话 ID 用日期片段：yyyyMMdd / HHmmss */
  static dateParts(now: number): string[] {
    const d: Date = new Date(now);
    const ymd: string = d.getFullYear().toString()
      + CommonUtil.pad2(d.getMonth() + 1)
      + CommonUtil.pad2(d.getDate());
    const hms: string = CommonUtil.pad2(d.getHours())
      + CommonUtil.pad2(d.getMinutes())
      + CommonUtil.pad2(d.getSeconds());
    return [ymd, hms];
  }

  /** 当日标识（is_new 当日首次启动判定用） */
  static todayKey(now: number): string {
    const d: Date = new Date(now);
    return d.getFullYear().toString() + '-' + (d.getMonth() + 1).toString() + '-' + d.getDate().toString();
  }
}
