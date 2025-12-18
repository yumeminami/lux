//
//  RecordingsListView.swift
//  Lux
//
//  Created by WingMun Fung on 2025/12/18.
//

import SwiftUI
import Combine

struct Recording: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let date: Date
    let size: Int64
}

class RecordingsViewModel: ObservableObject {
    @Published var recordings: [Recording] = []

    init() {
        loadRecordings()
    }

    func loadRecordings() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        do {
            let folders = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )

            recordings = folders.compactMap { folder in
                guard folder.hasDirectoryPath else { return nil }
                let mcapFile = folder.appendingPathComponent("recording.mcap")
                guard FileManager.default.fileExists(atPath: mcapFile.path) else { return nil }

                let attributes = try? FileManager.default.attributesOfItem(atPath: mcapFile.path)
                let size = attributes?[.size] as? Int64 ?? 0
                let date = attributes?[.creationDate] as? Date ?? Date()

                return Recording(name: folder.lastPathComponent, url: folder, date: date, size: size)
            }.sorted { $0.date > $1.date }
        } catch {
            print("加载录制列表失败: \(error)")
        }
    }

    func deleteRecording(_ recording: Recording) {
        do {
            try FileManager.default.removeItem(at: recording.url)
            recordings.removeAll { $0.id == recording.id }
        } catch {
            print("删除录制失败: \(error)")
        }
    }

    func shareRecording(_ recording: Recording) -> URL {
        return recording.url.appendingPathComponent("recording.mcap")
    }
}

struct RecordingsListView: View {
    @StateObject private var viewModel = RecordingsViewModel()
    @State private var sharingItem: URL?

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.recordings) { recording in
                    RecordingRow(recording: recording, onShare: {
                        sharingItem = viewModel.shareRecording(recording)
                    })
                }
                .onDelete { indexSet in
                    indexSet.forEach { index in
                        viewModel.deleteRecording(viewModel.recordings[index])
                    }
                }
            }
            .navigationTitle("数据包")
            .toolbar {
                EditButton()
            }
            .refreshable {
                viewModel.loadRecordings()
            }
            .sheet(item: Binding(
                get: { sharingItem.map { ShareItem(url: $0) } },
                set: { sharingItem = $0?.url }
            )) { item in
                ShareSheet(items: [item.url])
            }
        }
    }
}

struct RecordingRow: View {
    let recording: Recording
    let onShare: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.name)
                    .font(.headline)

                Text(formatDate(recording.date))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(formatSize(recording.size))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    RecordingsListView()
}
