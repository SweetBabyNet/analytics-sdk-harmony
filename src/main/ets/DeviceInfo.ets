import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { display } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { FieldLen } from './Constants';
import { CommonUtil } from './util/CommonUtil';
import { Logger } from './Logger';

/**
 * 设备信息快照（规范第 2 节公共字段）。
 * app_version/build_number 取 bundleManager；os/brand/model 取 deviceInfo；
 * lang 取系统 Locale；屏幕宽高取 display（仅 device_register 事件带值）。
 * network 按事件实时查询。
 */
export class DeviceInfoProvider {
  appVersion: string = '';
  buildNumber: string | null = null;
  osVersion: string | null = null;
  deviceBrand: string | null = null;
  deviceModel: string | null = null;
  lang: string | null = null;
  screenWidth: number | null = null;
  screenHeight: number | null = null;

  /** setup 时调用一次，采集静态信息；任何子项失败不影响其他项 */
  load(): void {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.appVersion = CommonUtil.trunc(info.versionName, FieldLen.APP_VERSION) ?? '';
      this.buildNumber = CommonUtil.trunc(info.versionCode.toString(), FieldLen.BUILD_NUMBER);
    } catch (e) {
      Logger.e('DeviceInfo load bundleInfo fail');
    }
    try {
      this.osVersion = CommonUtil.trunc(deviceInfo.displayVersion, FieldLen.OS_VERSION);
      this.deviceBrand = CommonUtil.trunc(deviceInfo.brand, FieldLen.DEVICE_BRAND);
      this.deviceModel = CommonUtil.trunc(deviceInfo.productModel, FieldLen.DEVICE_MODEL);
    } catch (e) {
      Logger.e('DeviceInfo load deviceInfo fail');
    }
    try {
      this.lang = CommonUtil.trunc(i18n.System.getSystemLocale(), FieldLen.LANG);
    } catch (e) {
      Logger.e('DeviceInfo load locale fail');
    }
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      this.screenWidth = d.width;
      this.screenHeight = d.height;
    } catch (e) {
      Logger.e('DeviceInfo load display fail');
    }
  }

  /**
   * 当前网络类型（协议枚举：wifi/5g/4g/3g/2g/none/unknown）。
   * Harmony 不暴露细分代际，cellular 统一报 "4g"（任务约定）；无网报 "none"。
   * 需要宿主声明 ohos.permission.GET_NETWORK_INFO，否则降级 "unknown"。
   */
  static currentNetwork(): string {
    try {
      const handle: connection.NetHandle = connection.getDefaultNetSync();
      if (handle === null || handle.netId === 0) {
        return 'none';
      }
      const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
      if (caps === null || caps.bearerTypes === null) {
        return 'unknown';
      }
      if (caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
        return 'wifi';
      }
      if (caps.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
        return '4g';
      }
      return 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }
}
