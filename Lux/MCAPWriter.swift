//
//  MCAPWriter.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import Foundation
import MCAP
import Compression

/// File writer that conforms to MCAP's IWritable protocol
private class FileWriter: IWritable {
    private var fileHandle: FileHandle?
    private var bytesWritten: UInt64 = 0
    private let queue = DispatchQueue(label: "com.lux.mcap.filewriter")

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func position() -> UInt64 {
        bytesWritten
    }

    func write(_ data: Data) async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let handle = self.fileHandle else {
                    continuation.resume()
                    return
                }

                do {
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                    self.bytesWritten += UInt64(data.count)
                    continuation.resume()
                } catch {
                    print("Failed to write to file: \(error)")
                    continuation.resume()
                }
            }
        }
    }

    func close() {
        queue.sync {
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
            fileHandle = nil
        }
    }
}

/// Wrapper around MCAP Swift library for easy file writing
class MCAPWriter {
    private let writer: MCAP.MCAPWriter
    private let fileWriter: FileWriter
    private let fileURL: URL

    private var channelIdMap: [String: ChannelID] = [:]
    private var schemaIdMap: [String: SchemaID] = [:]
    private var messageSequence: UInt32 = 0
    private var isInitialized = false

    init(fileURL: URL, useCompression: Bool = true) throws {
        self.fileURL = fileURL

        // Create file
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileURL)

        self.fileWriter = FileWriter(fileHandle: fileHandle)

        // Configure options with compression
        var options = MCAP.MCAPWriter.Options()
        if useCompression {
            options = MCAP.MCAPWriter.Options(
                useStatistics: true,
                useSummaryOffsets: true,
                useChunks: true,
                repeatSchemas: true,
                repeatChannels: true,
                useAttachmentIndex: true,
                useMetadataIndex: true,
                useMessageIndex: true,
                useChunkIndex: true,
                startChannelID: 0,
                chunkSize: 1024 * 1024, // 1MB chunks
                compressChunk: Self.compressWithLZ4
            )
        }

        self.writer = MCAP.MCAPWriter(fileWriter, options)
    }

    // MARK: - Compression

    nonisolated private static func compressWithLZ4(data: Data) -> (compression: String, compressedData: Data) {
        let sourceBuffer = [UInt8](data)
        let destinationBufferSize = sourceBuffer.count
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let compressedSize = compression_encode_buffer(
            &destinationBuffer,
            destinationBufferSize,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            COMPRESSION_LZ4
        )

        if compressedSize > 0 && compressedSize < sourceBuffer.count {
            // Compression successful and reduced size
            return ("lz4", Data(destinationBuffer.prefix(compressedSize)))
        } else {
            // Compression failed or didn't reduce size, return original
            return ("", data)
        }
    }

    nonisolated private static func compressWithLZFSE(data: Data) -> (compression: String, compressedData: Data) {
        let sourceBuffer = [UInt8](data)
        let destinationBufferSize = compression_encode_scratch_buffer_size(COMPRESSION_LZFSE)
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let compressedSize = compression_encode_buffer(
            &destinationBuffer,
            destinationBufferSize,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            COMPRESSION_LZFSE
        )

        if compressedSize > 0 && compressedSize < sourceBuffer.count {
            // Compression successful and reduced size
            return ("lz4", Data(destinationBuffer.prefix(compressedSize)))
        } else {
            // Compression failed or didn't reduce size, return original
            return ("", data)
        }
    }

    deinit {
        fileWriter.close()
    }

    /// Start writing the MCAP file - MUST be called before adding schemas/channels
    func start(library: String = "Lux", profile: String = "") async {
        await writer.start(library: library, profile: profile)
        isInitialized = true
    }

    /// Add a schema and return its ID
    @discardableResult
    func addSchema(name: String, encoding: String, data: Data) async -> SchemaID {
        if let existingId = schemaIdMap[name] {
            return existingId
        }

        let schemaId = await writer.addSchema(name: name, encoding: encoding, data: data)
        schemaIdMap[name] = schemaId
        return schemaId
    }

    /// Add a channel and return its ID
    @discardableResult
    func addChannel(
        topic: String,
        schemaId: SchemaID,
        messageEncoding: String,
        metadata: [String: String] = [:]
    ) async -> ChannelID {
        if let existingId = channelIdMap[topic] {
            return existingId
        }

        let channelId = await writer.addChannel(
            schemaID: schemaId,
            topic: topic,
            messageEncoding: messageEncoding,
            metadata: metadata
        )
        channelIdMap[topic] = channelId
        return channelId
    }

    /// Write a message to a channel
    func writeMessage(
        channelId: ChannelID,
        data: Data,
        logTime: UInt64? = nil,
        publishTime: UInt64? = nil
    ) async {
        guard isInitialized else {
            print("Warning: Writer not initialized, call start() first")
            return
        }

        let timestamp = logTime ?? UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        let message = Message(
            channelID: channelId,
            sequence: messageSequence,
            logTime: timestamp,
            publishTime: publishTime ?? timestamp,
            data: data
        )

        await writer.addMessage(message)
        messageSequence += 1
    }

    /// Convenience method: write message using topic name
    func writeMessage(
        topic: String,
        data: Data,
        logTime: UInt64? = nil,
        publishTime: UInt64? = nil
    ) async {
        guard isInitialized else {
            print("Warning: Writer not initialized, call start() first")
            return
        }

        guard let channelId = channelIdMap[topic] else {
            print("Warning: Channel not found for topic '\(topic)'")
            return
        }

        await writeMessage(
            channelId: channelId,
            data: data,
            logTime: logTime,
            publishTime: publishTime
        )
    }

    /// Finalize and close the MCAP file
    func close() async {
        await writer.end()
        fileWriter.close()
    }
}
