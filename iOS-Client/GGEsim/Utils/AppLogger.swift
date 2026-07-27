//
//  AppLogger.swift
//  GGEsim
//
//  统一日志出口：双写。
//    - 终端：仅 DEBUG 构建打印（Release / Disco 分发包不在终端输出）。
//    - 沙盒文件：所有构建都追加写入 `Documents/ggesim.log`，供「关于」页导出分享。
//
//  用法：把散落各处的 `print(...)` 换成全局函数 `appLog(...)` 即可，file/line 自动带上。
//

import Foundation

final class AppLogger {
    static let shared = AppLogger()

    /// 沙盒日志文件路径：Documents/ggesim.log。
    let logFileURL: URL

    /// 串行队列：保证多线程写入不交错、不竞争文件句柄。
    private let queue = DispatchQueue(label: "com.ggesim.applogger")

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logFileURL = docs.appendingPathComponent("ggesim.log")
    }

    /// 写一行日志：`[时间] [文件:行] 内容`。终端与文件双写。
    func log(_ message: String, file: String = #fileID, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = timeFormatter.string(from: Date())
        let entry = "[\(timestamp)] [\(fileName):\(line)] \(message)"

        #if DEBUG
        // 仅 DEBUG 在终端打印；Release / Disco 分发包只写文件。
        print(entry)
        #endif

        queue.async { [weak self] in
            self?.append(entry + "\n")
        }
    }

    /// 读取完整日志内容（用于导出 / 预览）。
    func readAll() -> String {
        (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
    }

    /// 供「关于」页导出分享：确保文件存在（即便还没写过日志），返回可分享的文件 URL。
    func exportFileURL() -> URL {
        queue.sync {
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: Data(), attributes: nil)
            }
        }
        return logFileURL
    }

    /// 清空日志文件。
    func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
        }
    }

    /// 追加写入（在串行队列上执行）。文件不存在时创建。
    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
}

/// 全局日志函数：替换所有 `print(...)`。file/line 自动捕获调用位置。
func appLog(_ message: String, file: String = #fileID, line: Int = #line) {
    AppLogger.shared.log(message, file: file, line: line)
}
