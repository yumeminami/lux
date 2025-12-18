//
//  ContentView.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("主页", systemImage: "house.fill")
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

struct HomeView: View {
    @StateObject private var arSession = ARSessionManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Robot 6DOF Tracking")
                .font(.title)
                .bold()

            Button(action: {
                arSession.reset()
            }) {
                Text("Reset")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red)
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Position (米) - 机器人坐标系")
                    .font(.headline)
                Text("X: \(String(format: "%.3f", arSession.position.x))")
                Text("Y: \(String(format: "%.3f", arSession.position.y))")
                Text("Z: \(String(format: "%.3f", arSession.position.z))")
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 10) {
                Text("Rotation (弧度) - 机器人坐标系")
                    .font(.headline)
                Text("Pitch: \(String(format: "%.3f", arSession.rotation.x))")
                Text("Yaw: \(String(format: "%.3f", arSession.rotation.y))")
                Text("Roll: \(String(format: "%.3f", arSession.rotation.z))")
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(10)
        }
        .padding()
    }
}

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("设置")
                .font(.largeTitle)
        }
    }
}

struct ProfileView: View {
    var body: some View {
        VStack {
            Text("我的")
                .font(.largeTitle)
        }
    }
}

#Preview {
    ContentView()
}
