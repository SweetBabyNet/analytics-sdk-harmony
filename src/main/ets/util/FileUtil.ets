import { fileIo as fs } from '@kit.CoreFileKit';
import { Logger } from '../Logger';

/**
 * 文件操作工具（同步 API，内部 catch-all）。
 * 用于 JSONL 队列兜底、崩溃暂存、gzip 临时文件。
 */
export class FileUtil {
  /** 确保目录存在 */
  static ensureDir(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      try {
        fs.mkdirSync(dir, true);
      } catch (e2) {
        Logger.e('FileUtil.ensureDir fail: ' + dir);
      }
    }
  }

  /** 追加一行文本（JSONL） */
  static appendLine(path: string, line: string): void {
    let fd: number = -1;
    try {
      const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fd = f.fd;
      const size: number = fs.statSync(path).size;
      fs.writeSync(fd, line + '\n', { offset: size });
    } catch (e) {
      Logger.e('FileUtil.appendLine fail: ' + path);
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /** 读取全部非空行；文件不存在或读取失败返回空数组 */
  static readLines(path: string): string[] {
    const out: string[] = [];
    try {
      const content: string = fs.readTextSync(path);
      const lines: string[] = content.split('\n');
      for (const line of lines) {
        const trimmed: string = line.trim();
        if (trimmed.length > 0) {
          out.push(trimmed);
        }
      }
    } catch (e) {
      // 文件不存在等场景，静默
    }
    return out;
  }

  /** 用内存中的剩余事件重写文件（flush 成功后的压缩 / 丢弃最旧后的整理） */
  static rewriteLines(path: string, lines: string[]): void {
    let fd: number = -1;
    try {
      const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fd = f.fd;
      if (lines.length > 0) {
        fs.writeSync(fd, lines.join('\n') + '\n');
      }
    } catch (e) {
      Logger.e('FileUtil.rewriteLines fail: ' + path);
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /** 清空文件内容（保留文件） */
  static truncate(path: string): void {
    let fd: number = -1;
    try {
      const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fd = f.fd;
    } catch (e) {
      // ignore
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /** 覆盖写文本（gzip 临时输入文件用） */
  static writeText(path: string, content: string): void {
    let fd: number = -1;
    try {
      const f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fd = f.fd;
      fs.writeSync(fd, content);
    } catch (e) {
      Logger.e('FileUtil.writeText fail: ' + path);
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          // ignore
        }
      }
    }
  }

  /** 读取文件字节（gzip 输出 / 上传用）；失败返回 null */
  static readBytes(path: string): Uint8Array | null {
    let fd: number = -1;
    try {
      const f = fs.openSync(path, fs.OpenMode.READ_ONLY);
      fd = f.fd;
      const size: number = fs.statSync(path).size;
      const buf: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(fd, buf);
      return new Uint8Array(buf);
    } catch (e) {
      Logger.e('FileUtil.readBytes fail: ' + path);
      return null;
    } finally {
      if (fd >= 0) {
        try {
          fs.closeSync(fd);
        } catch (e) {
          // ignore
        }
      }
    }
  }
}
