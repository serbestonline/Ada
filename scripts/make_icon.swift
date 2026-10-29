import SwiftUI
import AppKit

// Ada'nın simgesi: açık zeminli karenin tepesinden sarkan siyah ada, içinde turuncu yıldız.
//   swift scripts/make_icon.swift build/AppIcon-1024.png

struct Icon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 185, style: .continuous)
            .fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                HStack {
                    Text("✻").font(.system(size: 118, weight: .bold)).foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
                    Spacer()
                }
                .padding(.horizontal, 72)
                .frame(width: 540, height: 190)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: 80, bottomTrailingRadius: 80).fill(.black))
            }
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .frame(width: 824, height: 824)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Icon()); r.scale = 1
    try! NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
