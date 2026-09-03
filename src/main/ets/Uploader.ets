import { http } from '@kit.NetworkKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Constants } from './Constants';
import { BatchBody, EventRecord } from './Types';
import { CommonUtil } from './util/CommonUtil';
import { FileUtil } from './util/FileUtil';
import { Logger } from './Logger';

/** 上报结果：成功 / 丢弃（400/401，重试无意义）/ 可重试（429/5xx/网络异常） */
export enum UploadResult {
  SUCCESS,
  DISCARD,
  RETRY
}

/**
 * 上报器（规范第 1 节）：
 * POST {endpoint}/v1/track/batch，body gzip，X-Sign = HMAC-SHA256(传输字节, appSecret) hex。
 * gzip 用 @kit.BasicServicesKit 的 zlib（经临时文件 compressFile）；
 * 压缩失败降级为不压缩且不发送 Content-Encoding 头（服务端兼容两种）。
 */
export class Uploader {
  private endpoint: string;
  private appKey: string;
  private appSecret: string;
  private tmpDir: string;

  constructor(endpoint: string, appKey: string, appSecret: string, filesDir: string) {
    this.endpoint = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    this.appKey = appKey;
    this.appSecret = appSecret;
    this.tmpDir = filesDir + Constants.STORE_DIR + '/tmp';
    FileUtil.ensureDir(this.tmpDir);
  }

  /** 序列化批量请求体（供调度器测量压缩前大小） */
  static serialize(appKey: string, events: EventRecord[]): string {
    const body: BatchBody = {
      app_key: appKey,
      sent_time: Date.now(),
      sdk_version: Constants.SDK_VERSION,
      events: events
    };
    return JSON.stringify(body);
  }

  /** 压缩前 body 字节数 */
  static bodyBytes(appKey: string, events: EventRecord[]): number {
    try {
      return CommonUtil.utf8Length(Uploader.serialize(appKey, events));
    } catch (e) {
      return 0;
    }
  }

  async upload(events: EventRecord[]): Promise<UploadResult> {
    try {
      const body: string = Uploader.serialize(this.appKey, events);
      const plain: Uint8Array = CommonUtil.utf8Encode(body);

      // 优先 gzip，失败降级不压缩
      let payload: Uint8Array = plain;
      let gzipped: boolean = false;
      const gz: Uint8Array | null = await this.tryGzip(body);
      if (gz !== null && gz.length > 0) {
        payload = gz;
        gzipped = true;
      }

      // X-Sign 对最终传输字节计算
      const sign: string = await Uploader.hmacSha256Hex(payload, this.appSecret);

      const header: Record<string, string> = {
        'Content-Type': 'application/json',
        'X-App-Key': this.appKey,
        'X-Timestamp': Date.now().toString(),
        'X-Sign': sign
      };
      if (gzipped) {
        header['Content-Encoding'] = 'gzip';
      }

      const code: number = await this.doPost(this.endpoint + '/v1/track/batch', header, payload);
      Logger.d('upload batch count=' + events.length + ' http=' + code + ' gzip=' + gzipped);
      if (code === 200) {
        return UploadResult.SUCCESS;
      }
      if (code === 400 || code === 401) {
        return UploadResult.DISCARD;
      }
      return UploadResult.RETRY;
    } catch (e) {
      Logger.e('upload exception');
      return UploadResult.RETRY;
    }
  }

  /** zlib 经临时文件压缩为 gzip 格式；任何失败返回 null 走降级 */
  private async tryGzip(plain: string): Promise<Uint8Array | null> {
    try {
      const inPath: string = this.tmpDir + '/upload_in.json';
      const outPath: string = this.tmpDir + '/upload_out.gz';
      FileUtil.writeText(inPath, plain);
      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      };
      await zlib.compressFile(inPath, outPath, options);
      return FileUtil.readBytes(outPath);
    } catch (e) {
      Logger.e('gzip fail, fallback plain');
      return null;
    }
  }

  /** HMAC-SHA256(appSecret, data) -> hex（@kit.CryptoArchitectureKit） */
  private static async hmacSha256Hex(data: Uint8Array, secret: string): Promise<string> {
    const keyGen = cryptoFramework.createSymKeyGenerator('HMAC');
    const keyBlob: cryptoFramework.DataBlob = { data: CommonUtil.utf8Encode(secret) };
    const symKey = await keyGen.convertKey(keyBlob);
    const mac = cryptoFramework.createMac('SHA256');
    await mac.init(symKey);
    const input: cryptoFramework.DataBlob = { data: data };
    await mac.update(input);
    const out: cryptoFramework.DataBlob = await mac.doFinal();
    return CommonUtil.toHex(out.data);
  }

  private doPost(url: string, header: Record<string, string>, payload: Uint8Array): Promise<number> {
    return new Promise<number>((resolve) => {
      let req: http.HttpRequest | null = null;
      try {
        req = http.createHttp();
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: header,
          extraData: payload.buffer as ArrayBuffer,
          connectTimeout: Constants.HTTP_TIMEOUT_MS,
          readTimeout: Constants.HTTP_TIMEOUT_MS,
          expectDataType: http.HttpDataType.STRING
        };
        req.request(url, options, (err: BusinessError, resp: http.HttpResponse) => {
          try {
            req?.destroy();
          } catch (e) {
            // ignore
          }
          if (err) {
            Logger.e('http error code=' + err.code);
            resolve(-1);
            return;
          }
          resolve(resp.responseCode);
        });
      } catch (e) {
        try {
          req?.destroy();
        } catch (e2) {
          // ignore
        }
        resolve(-1);
      }
    });
  }
}
