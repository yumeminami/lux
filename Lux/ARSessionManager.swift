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
    
    // 性能优化：延迟初始化 CIContext（懒加载）
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // 频率控制：记录上一次录制和 UI 更新的时间戳
    private var lastRecordTimestamp: TimeInterval = 0
    private var lastUIUpdateTimestamp: TimeInterval = 0
    private let recordInterval: TimeInterval = 1.0 / 60.0 // 录制 60Hz
    private let uiUpdateInterval: TimeInterval = 1.0 / 30.0 // UI 更新 30Hz

    override init() {
        super.init()
        session.delegate = self
        // 延迟启动，避免阻塞主线程
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startSession()
        }
    }

    func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.isAutoFocusEnabled = true

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
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
            // 注意：确保您的 MCAPWriter 实现支持该初始化方法
            let writer = try MCAPWriter(fileURL: mcapFile)
            mcapWriter = writer

            // 定义Schema (JSON格式) - 不包含图片数据
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
                    }
                }
            }
            """

            // 异步初始化 MCAP writer - 完成后才开始录制
            Task {
                await writer.start(library: "Lux", profile: "")
                let schemaId = await writer.addSchema(
                    name: "ARPose",
                    encoding: "jsonschema",
                    data: schemaJSON.data(using: .utf8)!
                )
                await writer.addChannel(
                    topic: "/ar/pose",
                    schemaId: schemaId,
                    messageEncoding: "json"
                )

                // 初始化完成后才开始录制
                DispatchQueue.main.async {
                    self.recordingStartTime = Date()
                    self.frameCount = 0
                    self.lastRecordTimestamp = 0 // 重置时间戳
                    self.isRecording = true
                    print("开始录制MCAP: \(mcapFile.path)")
                }
            }
        } catch {
            print("创建MCAP录制失败: \(error)")
        }
    }
    
    private func stopRecording() {
        isRecording = false
        recordDuration = 0

        fileQueue.async { [weak self] in
            guard let self = self else { return }
            Task {
                await self.mcapWriter?.close()
                self.mcapWriter = nil
                print("MCAP录制完成")
            }
        }
    }
    
    // MARK: - 内部辅助函数：计算欧拉角
    private func extractEulerAngles(from matrix: simd_float3x3) -> SIMD3<Float> {
        // matrix[col][row]
        let pitch = atan2(-matrix[2][1], sqrt(matrix[2][0] * matrix[2][0] + matrix[2][2] * matrix[2][2]))
        let yaw = atan2(matrix[2][0], matrix[2][2])
        let roll = atan2(matrix[0][1], matrix[1][1])
        return SIMD3<Float>(pitch, yaw, roll)
    }

    // MARK: - 内部辅助函数：缩放并转Base64
    private func pixelBufferToBase64(_ pixelBuffer: CVPixelBuffer) -> String {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 1. 图像缩放逻辑 (目标 640x480)
        let targetWidth: CGFloat = 640.0
        let targetHeight: CGFloat = 480.0
        
        // 计算缩放比例
        let scaleX = targetWidth / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY = targetHeight / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        // 使用 transform 进行缩放
        // 注意：这里假设源图像比例与4:3接近，直接缩放可能导致拉伸。
        // 如需保持比例裁剪，逻辑会更复杂，这里按您的需求直接 Resize。
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        ciImage = ciImage.transformed(by: transform)

        // 2. 转换 JPEG
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            let options: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.5
            ]
            
            // 使用复用的 ciContext 提高性能
            if let jpegData = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options) {
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

        // 1. 提取位置 (保持 UI 60Hz 更新，不进行降频)
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
        
        let arkitEuler = extractEulerAngles(from: rotationMatrix)
        absoluteRotation = SIMD3<Float>(-arkitEuler.z, -arkitEuler.x, arkitEuler.y)
        
        let relPos = absolutePosition - referencePosition
        let relRot = absoluteRotation - referenceRotation

        // 更新 UI (限制为 30Hz，减少主线程负载)
        let currentTime = frame.timestamp
        if currentTime - lastUIUpdateTimestamp >= uiUpdateInterval {
            lastUIUpdateTimestamp = currentTime
            DispatchQueue.main.async {
                self.position = relPos
                self.rotation = relRot
                if self.isRecording, let start = self.recordingStartTime {
                    self.recordDuration = Date().timeIntervalSince(start)
                }
            }
        }
        
        // 3. 录制数据到 MCAP (降频处理 60 Hz)
        if isRecording {
            let arFrameTimestamp = frame.timestamp

            // 降频逻辑：如果距离上次录制时间不足 1/60 秒，则跳过
            if arFrameTimestamp - lastRecordTimestamp < recordInterval {
                return
            }
            lastRecordTimestamp = arFrameTimestamp

            // 使用 Unix 时间戳 (秒)
            let unixTimestamp = Date().timeIntervalSince1970

            let currentFrameIndex = frameCount
            frameCount += 1

            fileQueue.async { [weak self] in
                guard let self = self else { return }

                // 构建JSON消息 (不包含图片)
                let message: [String: Any] = [
                    "timestamp": unixTimestamp,
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
                    ]
                ]

                if let jsonData = try? JSONSerialization.data(withJSONObject: message) {
                    // Unix 时间戳转换为纳秒
                    let timestampNanos = UInt64(unixTimestamp * 1_000_000_000)
                    Task {
                        await self.mcapWriter?.writeMessage(
                            topic: "/ar/pose",
                            data: jsonData,
                            logTime: timestampNanos,
                            publishTime: timestampNanos
                        )
                    }
                }
            }
        }
    }
}
