//
//  ContentView.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import SwiftUI
import ARKit
import RealityKit

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("监控", systemImage: "camera.viewfinder")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
        }
        // 强制 TabBar 背景半透明，防止遮挡相机太生硬
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

// MARK: - 主页面 (HomeView)
struct HomeView: View {
    @StateObject private var arSessionManager = ARSessionManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. 相机背景层
            ARCameraView(session: arSessionManager.session)
                .edgesIgnoringSafeArea(.top) // 让相机铺满顶部，但留出底部 TabBar 空间

            // 2. 数据悬浮面板
            VStack(spacing: 16) {
                // 顶部标题栏 + Reset 按钮
                HStack {
                    Label("Robot 6DOF", systemImage: "cube.transparent")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        arSessionManager.reset()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue))
                    }
                }
                
                Divider()

                // 数据显示区
                HStack(alignment: .top, spacing: 20) {
                    // Position 列
                    DataColumnView(
                        title: "Position (m)",
                        icon: "move.3d",
                        color: .blue,
                        x: arSessionManager.position.x,
                        y: arSessionManager.position.y,
                        z: arSessionManager.position.z
                    )
                    
                    // Rotation 列
                    DataColumnView(
                        title: "Rotation (rad)",
                        icon: "rotate.3d",
                        color: .green,
                        x: arSessionManager.rotation.x, // Pitch
                        y: arSessionManager.rotation.y, // Yaw
                        z: arSessionManager.rotation.z, // Roll
                        labels: ["P", "Y", "R"] // 自定义标签 Pitch/Yaw/Roll
                    )
                }
            }
            .padding(20)
            .background(.ultraThinMaterial) // iOS 风格毛玻璃背景
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 16)
            .padding(.bottom, 10) // 留出一点底部间距
        }
    }
}

// MARK: - 组件：数据列视图
struct DataColumnView: View {
    let title: String
    let icon: String
    let color: Color
    let x: Float
    let y: Float
    let z: Float
    var labels: [String] = ["X", "Y", "Z"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                DataRow(label: labels[0], value: x)
                DataRow(label: labels[1], value: y)
                DataRow(label: labels[2], value: z)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 组件：单行数据
struct DataRow: View {
    let label: String
    let value: Float
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .frame(width: 12, alignment: .leading)
            
            Text(String(format: "%.3f", value))
                .font(.system(.callout, design: .monospaced)) // 等宽字体防止跳动
                .fontWeight(.medium)
        }
    }
}

// MARK: - AR 相机视图桥接
struct ARCameraView: UIViewRepresentable {
    var session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session // 绑定 SessionManager 中的 session
        view.autoenablesDefaultLighting = true
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// 占位视图
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("通用") {
                    Text("版本 1.0.0")
                }
            }
            .navigationTitle("设置")
        }
    }
}

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.gray)
                Text("开发者")
                    .font(.title2)
            }
            .navigationTitle("我的")
        }
    }
}

#Preview {
    ContentView()
}