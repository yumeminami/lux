//
//  ARSessionManager.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import ARKit
import Combine

class ARSessionManager: NSObject, ObservableObject {
    @Published var position: SIMD3<Float> = .zero
    @Published var rotation: SIMD3<Float> = .zero

    private let session = ARSession()
    private var absolutePosition: SIMD3<Float> = .zero
    private var absoluteRotation: SIMD3<Float> = .zero
    private var referencePosition: SIMD3<Float> = .zero
    private var referenceRotation: SIMD3<Float> = .zero

    override init() {
        super.init()
        session.delegate = self
        startSession()
    }

    func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        session.run(configuration)
    }

    func stopSession() {
        session.pause()
    }

    func reset() {
        referencePosition = absolutePosition
        referenceRotation = absoluteRotation
    }
}

extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform

        // 提取ARKit位置
        let arkitX = transform.columns.3.x
        let arkitY = transform.columns.3.y
        let arkitZ = transform.columns.3.z

        // 转换到机器人坐标系: x=-z, y=-x, z=y
        absolutePosition = SIMD3<Float>(-arkitZ, -arkitX, arkitY)

        // 提取ARKit旋转矩阵
        let rotationMatrix = simd_float3x3(
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )

        // 提取ARKit欧拉角
        let arkitEuler = rotationMatrix.eulerAngles

        // 转换到机器人坐标系: pitch=-yaw, yaw=-pitch, roll=roll
        absoluteRotation = SIMD3<Float>(-arkitEuler.z, -arkitEuler.x, arkitEuler.y)

        // 计算相对于参考pose的pose
        position = absolutePosition - referencePosition
        rotation = absoluteRotation - referenceRotation
    }
}

extension simd_float3x3 {
    var eulerAngles: SIMD3<Float> {
        let pitch = atan2(-self[2][1], sqrt(self[2][0] * self[2][0] + self[2][2] * self[2][2]))
        let yaw = atan2(self[2][0], self[2][2])
        let roll = atan2(self[0][1], self[1][1])
        return SIMD3<Float>(pitch, yaw, roll)
    }
}
