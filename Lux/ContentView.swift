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
    @State private var isFullScreen = false

    var body: some View {
        TabView {
            HomeView(isFullScreen: $isFullScreen)
                .tabItem {
                    Label("监控", systemImage: "camera.viewfinder")
                }
                .toolbar(isFullScreen ? .hidden : .visible, for: .tabBar)

            RecordingsListView()
                .tabItem {
                    Label("数据", systemImage: "folder.fill")
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
    }
}

// MARK: - HomeView
struct HomeView: View {
    @Binding var isFullScreen: Bool
    @StateObject private var arSessionManager = ARSessionManager()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 全局背景 (非全屏时显示灰色背景)
                if !isFullScreen {
                    Color(UIColor.systemGroupedBackground)
                        .edgesIgnoringSafeArea(.all)
                }

                VStack(spacing: 0) {
                    // 1. 顶部标题栏 (非全屏)
                    if !isFullScreen {
                        HStack {
                            Label("Robot 6DOF", systemImage: "cube.transparent")
                                .font(.headline)
                            Spacer()
                            ResetButton(action: arSessionManager.reset)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                    }

                    // 2. 相机区域
                    ZStack(alignment: .bottomTrailing) {
                        ARCameraView(session: arSessionManager.session)
                            .frame(
                                width: isFullScreen ? geometry.size.width : nil,
                                height: isFullScreen ? geometry.size.height : 320
                            )
                            .cornerRadius(isFullScreen ? 0 : 24)
                            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                            .edgesIgnoringSafeArea(isFullScreen ? .all : [])

                        // 全屏切换按钮
                        FullScreenToggleButton(isFullScreen: $isFullScreen)
                            .padding(16)
                            .padding(.bottom, isFullScreen ? geometry.safeAreaInsets.bottom + 40 : 0)
                    }
                    .padding(.horizontal, isFullScreen ? 0 : 16)
                    .padding(.top, isFullScreen ? 0 : 10)

                    // 3. 底部数据面板 (灰色画布区域)
                    if !isFullScreen {
                        ScrollView {
                            VStack(spacing: 24) {
                                // 数据卡片
                                HStack(spacing: 12) {
                                    DataCard(
                                        title: "Position (m)",
                                        icon: "move.3d",
                                        iconColor: .blue,
                                        data: [
                                            ("X", arSessionManager.position.x),
                                            ("Y", arSessionManager.position.y),
                                            ("Z", arSessionManager.position.z)
                                        ]
                                    )
                                    
                                    DataCard(
                                        title: "Rotation (rad)",
                                        icon: "rotate.3d",
                                        iconColor: .green,
                                        data: [
                                            ("Roll", arSessionManager.rotation.x),
                                            ("Pitch", arSessionManager.rotation.y),
                                            ("Yaw", arSessionManager.rotation.z)
                                        ]
                                    )
                                }
                                
                                // 录制按钮
                                RecordControlView(
                                    isRecording: arSessionManager.isRecording,
                                    duration: arSessionManager.recordDuration,
                                    action: arSessionManager.toggleRecording
                                )
                            }
                            .padding(16)
                        }
                    }
                }
                
                // 全屏模式下的悬浮录制按钮
                if isFullScreen {
                    VStack {
                        Spacer()
                        RecordControlView(
                            isRecording: arSessionManager.isRecording,
                            duration: arSessionManager.recordDuration,
                            action: arSessionManager.toggleRecording,
                            isFloating: true
                        )
                        .padding(.bottom, 50)
                    }
                }
            }
        }
    }
}

// MARK: - 组件：数据卡片 (灰色背景上的白色卡片)
struct DataCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let data: [(label: String, value: Float)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(data, id: \.label) { item in
                    HStack {
                        Text(item.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 30, alignment: .leading)
                        
                        Text(String(format: "% .3f", item.value))
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 这里的背景色实现了 "卡片" 效果
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(16)
        // 轻微阴影增加层次感
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - 组件：录制按钮
struct RecordControlView: View {
    var isRecording: Bool
    var duration: TimeInterval
    var action: () -> Void
    var isFloating: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            // 计时器 (录制时显示)
            if isRecording {
                Text(timeString(from: duration))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(isFloating ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(isFloating ? .black.opacity(0.5) : .clear)
                    .cornerRadius(8)
            }
            
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                withAnimation { action() }
            }) {
                ZStack {
                    // 外圈
                    Circle()
                        .strokeBorder(isFloating ? .white : Color.gray.opacity(0.3), lineWidth: 4)
                        .frame(width: 72, height: 72)
                    
                    // 内圈 (方形或圆形)
                    RoundedRectangle(cornerRadius: isRecording ? 8 : 30)
                        .fill(Color.red)
                        .frame(width: isRecording ? 32 : 56, height: isRecording ? 32 : 56)
                        .animation(.spring(response: 0.3), value: isRecording)
                }
            }
        }
    }
    
    func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// 辅助组件：Reset 按钮
struct ResetButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            Text("Reset")
                .font(.caption.bold())
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
        }
    }
}

// 辅助组件：全屏切换
struct FullScreenToggleButton: View {
    @Binding var isFullScreen: Bool
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isFullScreen.toggle()
            }
        }) {
            Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
    }
}

// 辅助组件：相机视图
struct ARCameraView: UIViewRepresentable {
    var session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.autoenablesDefaultLighting = true
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// 占位 View
struct SettingsView: View { var body: some View { Text("设置") } }
struct ProfileView: View { var body: some View { Text("我的") } }

#Preview {
    ContentView()
}