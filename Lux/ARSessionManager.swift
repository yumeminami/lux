//
//  ARSessionManager.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import ARKit
import Combine
import VideoToolbox
import CoreImage // 必须导入，用于 CIImage 处理
import ImageIO   // 必须导入，用于 kCGImageDestinationLossyCompressionQuality

class ARSessionManager: NSObject, ObservableObject {
    // UI 数据发布
    @Published var position: SIMD3<Float> = .zero
    @Published var rotation: SIMD3<Float> = .zero
    @Published var isRecording = false
    @Published var recordDuration: TimeInterval = 0
    
    // AR Session (公开给 UI 使用)
    let session = ARSession()
    
    // 私有变量
    private var absolutePosition: SIMD3<Float> = .zero
    private var absoluteRotation: SIMD3<Float> = .zero
    private var referencePosition: SIMD3<Float> = .zero
    private var referenceRotation: SIMD3<Float> = .zero
    
    // 录制相关
    private var recordingStartTime: Date?
    private var currentSessionPath: URL?
    private var mcapWriter: MCAPWriter?
    private var frameCount = 0
    private let fileQueue = DispatchQueue(label: "com.lux.fileQueue", qos: .utility)

    override init() {
        super.init()
        session.delegate = self
        startSession()
    }

    func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.isAutoFocusEnabled = true 
        session.run(configuration)
    }
    
    func reset() {
        referencePosition = absolutePosition
        referenceRotation = absoluteRotation
    }
    
    // MARK: - 录制控制
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let sessionName = "Session_\(formatter.string(from: Date()))"

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sessionFolder = documents.appendingPathComponent(sessionName)
        let mcapFile = sessionFolder.appendingPathComponent("recording.mcap")

        do {
            try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
            currentSessionPath = sessionFolder

            // 创建MCAP writer
            mcapWriter = try MCAPWriter(fileURL: mcapFile)

            // 定义Schema (JSON格式)
            let schemaJSON = """
            {
                "type": "object",
                "properties": {
                    "timestamp": {"type": "number"},
                    "frame_index": {"type": "integer"},
                    "position": {
                        "type": "object",
                        "properties": {
                            "x": {"type": "number"},
                            "y": {"type": "number"},
                            "z": {"type": "number"}
                        }
                    },
                    "rotation": {
                        "type": "object",
                        "properties": {
                            "roll": {"type": "number"},
                            "pitch": {"type": "number"},
                            "yaw": {"type": "number"}
                        }
                    },
                    "image": {"type": "string", "description": "base64 encoded JPEG"}
                }
            }
            """
            mcapWriter?.writeSchema(name: "ARPose", encoding: "jsonschema", schemaData: schemaJSON.data(using: .utf8)!)
            mcapWriter?.writeChannel(topic: "/ar/pose", messageEncoding: "json", schemaId: 1)

            recordingStartTime = Date()
            frameCount = 0
            isRecording = true
            print("开始录制MCAP: \(mcapFile.path)")
        } catch {
            print("创建MCAP录制失败: \(error)")
        }
    }
    
    private func stopRecording() {
        isRecording = false
        recordDuration = 0

        fileQueue.async { [weak self] in
            guard let self = self else { return }
            self.mcapWriter?.close()
            self.mcapWriter = nil
            print("MCAP录制完成")
        }
    }
    
    // MARK: - 内部辅助函数：计算欧拉角
    // 直接放在类内部，避免 extension 找不到的问题
    private func extractEulerAngles(from matrix: simd_float3x3) -> SIMD3<Float> {
        // matrix[col][row]
        let pitch = atan2(-matrix[2][1], sqrt(matrix[2][0] * matrix[2][0] + matrix[2][2] * matrix[2][2]))
        let yaw = atan2(matrix[2][0], matrix[2][2])
        let roll = atan2(matrix[0][1], matrix[1][1])
        return SIMD3<Float>(pitch, yaw, roll)
    }

    // MARK: - 内部辅助函数：将图片转换为base64
    private func pixelBufferToBase64(_ pixelBuffer: CVPixelBuffer) -> String {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            let options: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5
            ]

            if let jpegData = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options) {
                return jpegData.base64EncodedString()
            }
        }
        return ""
    }
}

// MARK: - ARSessionDelegate
extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform

        // 1. 提取位置
        let arkitX = transform.columns.3.x
        let arkitY = transform.columns.3.y
        let arkitZ = transform.columns.3.z
        
        // 机器人坐标系转换: x=-z, y=-x, z=y
        absolutePosition = SIMD3<Float>(-arkitZ, -arkitX, arkitY)
        
        // 2. 提取旋转矩阵
        let rotationMatrix = simd_float3x3(
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        
        // 使用内部函数计算欧拉角 (Pitch, Yaw, Roll)
        let arkitEuler = extractEulerAngles(from: rotationMatrix)
        
        // 转换到机器人坐标系
        absoluteRotation = SIMD3<Float>(-arkitEuler.z, -arkitEuler.x, arkitEuler.y)
        
        // 计算相对 Pose
        let relPos = absolutePosition - referencePosition
        let relRot = absoluteRotation - referenceRotation
        
        // 更新 UI
        DispatchQueue.main.async {
            self.position = relPos
            self.rotation = relRot
            if self.isRecording, let start = self.recordingStartTime {
                self.recordDuration = Date().timeIntervalSince(start)
            }
        }
        
        // 3. 录制数据到MCAP
        if isRecording {
            let timestamp = frame.timestamp
            let currentFrameIndex = frameCount
            frameCount += 1
            let pixelBuffer = frame.capturedImage

            fileQueue.async { [weak self] in
                guard let self = self else { return }

                // 将图片转换为JPEG base64
                let imageBase64 = self.pixelBufferToBase64(pixelBuffer)

                // 构建JSON消息
                let message: [String: Any] = [
                    "timestamp": timestamp,
                    "frame_index": currentFrameIndex,
                    "position": [
                        "x": relPos.x,
                        "y": relPos.y,
                        "z": relPos.z
                    ],
                    "rotation": [
                        "roll": relRot.x,
                        "pitch": relRot.y,
                        "yaw": relRot.z
                    ],
                    "image": imageBase64
                ]

                if let jsonData = try? JSONSerialization.data(withJSONObject: message) {
                    // 时间戳转换为纳秒
                    let timestampNanos = UInt64(timestamp * 1_000_000_000)
                    self.mcapWriter?.writeMessage(timestamp: timestampNanos, channelId: 1, messageData: jsonData)
                }
            }
        }
    }
}