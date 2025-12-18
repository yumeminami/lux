//
//  MCAPWriter.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import Foundation
import MCAP
import Compression

/// 文件写入器，遵循 MCAP 的 IWritable 协议
/// 标记为 @unchecked Sendable 以允许在 Actor 内部传递
private final class FileWriter: @unchecked Sendable, IWritable {
    private var fileHandle: FileHandle?
    
    // 🔥 核心修复：仅使用内部计数器作为事实来源，不再询问操作系统 offsetInFile
    private var _logicalPosition: UInt64 = 0

    nonisolated init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    // IWritable 协议方法
    nonisolated func position() -> UInt64 {
        return _logicalPosition
    }

    nonisolated func write(_ data: Data) {
        guard let handle = fileHandle else {
            print("❌ MCAP Error: Attempted to write to closed file handle.")
            return
        }
        
        do {
            if #available(iOS 13.4, *) {
                try handle.write(contentsOf: data)
            } else {
                handle.write(data)
            }
            // 严格累加写入的字节数
            _logicalPosition += UInt64(data.count)
        } catch {
            // 遇到写入错误直接崩溃，防止生成损坏的“僵尸”文件
            fatalError("❌ MCAP Critical Error: Failed to write data. Disk full? Error: \(error)")
        }
    }

    nonisolated func close() {
        do {
            try fileHandle?.synchronize()
            try fileHandle?.close()
            fileHandle = nil
        } catch {
            print("⚠️ MCAP Warning: Failed to close file handle: \(error)")
        }
    }
}

/// MCAPWriter 封装 Actor
actor MCAPWriter {
    private let writer: MCAP.MCAPWriter
    private let fileWriter: FileWriter
    
    private var channelIdMap: [String: ChannelID] = [:]
    private var schemaIdMap: [String: SchemaID] = [:]
    private var messageSequence: UInt32 = 0
    private var isInitialized = false

    /// 初始化
    init(fileURL: URL) throws {
        // 1. 确保目录存在
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // 2. 创建空文件（如果存在则覆盖）
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        
        // 3. 打开文件句柄
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        self.fileWriter = FileWriter(fileHandle: fileHandle)

        // 4. 配置选项
        var options = MCAP.MCAPWriter.Options()
        options = MCAP.MCAPWriter.Options(
            useStatistics: true,
            useSummaryOffsets: true,
            useChunks: true, // 启用 Chunk
            repeatSchemas: true,
            repeatChannels: true,
            useAttachmentIndex: true,
            useMetadataIndex: true,
            useMessageIndex: true,
            useChunkIndex: true,
            startChannelID: 0,
            chunkSize: 4 * 1024 * 1024, // 4MB
            compressChunk: nil          // 🔥 禁用压缩，防止 LZ4 兼容性问题
        )

        self.writer = MCAP.MCAPWriter(fileWriter, options)
    }

    // MARK: - Async Wrapper Methods

    func start(library: String = "Lux", profile: String = "") async {
        await writer.start(library: library, profile: profile)
        isInitialized = true
    }

    @discardableResult
    func addSchema(name: String, encoding: String, data: Data) async -> SchemaID {
        if let existingId = schemaIdMap[name] { return existingId }
        let schemaId = await writer.addSchema(name: name, encoding: encoding, data: data)
        schemaIdMap[name] = schemaId
        return schemaId
    }

    @discardableResult
    func addChannel(topic: String, schemaId: SchemaID, messageEncoding: String, metadata: [String: String] = [:]) async -> ChannelID {
        if let existingId = channelIdMap[topic] { return existingId }
        let channelId = await writer.addChannel(schemaID: schemaId, topic: topic, messageEncoding: messageEncoding, metadata: metadata)
        channelIdMap[topic] = channelId
        return channelId
    }

    func writeMessage(channelId: ChannelID, data: Data, logTime: UInt64, publishTime: UInt64) async {
        guard isInitialized else { return }
        
        let message = Message(
            channelID: channelId,
            sequence: messageSequence,
            logTime: logTime,
            publishTime: publishTime,
            data: data
        )

        await writer.addMessage(message)
        messageSequence += 1
    }

    func writeMessage(topic: String, data: Data, logTime: UInt64, publishTime: UInt64) async {
        guard let channelId = channelIdMap[topic] else { return }
        await writeMessage(channelId: channelId, data: data, logTime: logTime, publishTime: publishTime)
    }

    func close() async {
        await writer.end()
        fileWriter.close()
    }
}
