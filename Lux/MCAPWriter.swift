//
//  MCAPWriter.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import Foundation

class MCAPWriter {
    private var fileHandle: FileHandle?
    private let fileURL: URL
    private var channelId: UInt16 = 1
    private var messageCount: UInt64 = 0

    init(fileURL: URL) throws {
        self.fileURL = fileURL

        // 创建文件
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: fileURL)

        // 写入MCAP Header
        writeHeader()
    }

    deinit {
        close()
    }

    func writeHeader() {
        guard let handle = fileHandle else { return }

        // MCAP magic bytes
        let magic = Data([0x89, 0x4D, 0x43, 0x41, 0x50, 0x30, 0x0D, 0x0A])
        handle.write(magic)

        // Header record
        writeRecord(opcode: 0x01, data: Data())
    }

    func writeSchema(name: String, encoding: String, schemaData: Data) {
        var data = Data()

        // Schema ID (2 bytes)
        data.append(UInt16(1).littleEndianData)

        // Name length + name
        data.append(UInt32(name.utf8.count).littleEndianData)
        data.append(name.data(using: .utf8)!)

        // Encoding length + encoding
        data.append(UInt32(encoding.utf8.count).littleEndianData)
        data.append(encoding.data(using: .utf8)!)

        // Schema data length + data
        data.append(UInt32(schemaData.count).littleEndianData)
        data.append(schemaData)

        writeRecord(opcode: 0x03, data: data)
    }

    func writeChannel(topic: String, messageEncoding: String, schemaId: UInt16) {
        var data = Data()

        // Channel ID (2 bytes)
        data.append(channelId.littleEndianData)

        // Schema ID (2 bytes)
        data.append(schemaId.littleEndianData)

        // Topic length + topic
        data.append(UInt32(topic.utf8.count).littleEndianData)
        data.append(topic.data(using: .utf8)!)

        // Message encoding length + encoding
        data.append(UInt32(messageEncoding.utf8.count).littleEndianData)
        data.append(messageEncoding.data(using: .utf8)!)

        // Metadata (empty map)
        data.append(UInt32(0).littleEndianData)

        writeRecord(opcode: 0x04, data: data)
    }

    func writeMessage(timestamp: UInt64, channelId: UInt16, messageData: Data) {
        var data = Data()

        // Channel ID
        data.append(channelId.littleEndianData)

        // Sequence (4 bytes)
        data.append(UInt32(messageCount).littleEndianData)

        // Log time (8 bytes, nanoseconds)
        data.append(timestamp.littleEndianData)

        // Publish time (same as log time)
        data.append(timestamp.littleEndianData)

        writeRecord(opcode: 0x05, data: data + messageData)
        messageCount += 1
    }

    func close() {
        guard let handle = fileHandle else { return }

        // Write footer
        writeRecord(opcode: 0x02, data: Data())

        // Write magic bytes again
        let magic = Data([0x89, 0x4D, 0x43, 0x41, 0x50, 0x30, 0x0D, 0x0A])
        handle.write(magic)

        try? handle.close()
        fileHandle = nil
    }

    private func writeRecord(opcode: UInt8, data: Data) {
        guard let handle = fileHandle else { return }

        var record = Data()
        record.append(opcode)
        record.append(UInt64(data.count).littleEndianData)
        record.append(data)

        handle.write(record)
    }
}

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt64 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
    }
}
