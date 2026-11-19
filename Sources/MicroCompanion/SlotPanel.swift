import SwiftUI
import MicroCore

struct SlotPanel: View {
    @ObservedObject var model: Companion
    @State private var hoveredSlot: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DeckMark().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DeckBrand.name).font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("AI Micro × cmux").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.showMapping() } label: {
                    Label("키 매핑 편집", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("open-key-mapping")
            }.padding(.horizontal, 18).padding(.vertical, 15)

            Divider()
            HStack {
                Text("최근 세션").font(.headline)
                Spacer()
                Text("\(model.rows.compactMap { $0 }.count) / 6").monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("사용 중인 슬롯 \(model.rows.compactMap { $0 }.count)개")
            }.font(.caption).padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 7)

            VStack(spacing: 2) {
                ForEach(0..<6) { index in
                    slot(at: index)
                }
            }.padding(.horizontal, 8).padding(.bottom, 12)

            if !model.feedback.isEmpty {
                Text(model.feedback).font(.callout).lineLimit(2)
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }

            Divider()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(model.deviceStatus, systemImage: "cable.connector").lineLimit(2)
                    Label(model.cmuxStatus, systemImage: "terminal").lineLimit(2)
                }.font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Menu {
                    Button("다시 연결") { model.connect() }.disabled(model.connecting || model.selecting)
                    Divider()
                    Button("종료") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3).frame(width: 28, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("연결 및 앱 메뉴")
            }.padding(.horizontal, 18).padding(.vertical, 10)
        }.frame(width: 420).tint(DeckBrand.accent)
    }

    private func slot(at index: Int) -> some View {
        let row = model.rows[index]
        let state = model.lights[index]
        let active = row?.active == true
        return Button { model.select(index) } label: {
            HStack(spacing: 10) {
                Text("\(index + 1)").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(active ? DeckBrand.accent : .secondary)
                    .frame(width: 23, height: 23)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? DeckBrand.accent.opacity(0.55) : Color.secondary.opacity(0.25)))
                Text(row?.title ?? "빈 슬롯").font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(row == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if active { Image(systemName: "scope").font(.caption).foregroundStyle(DeckBrand.accent) }
                HStack(spacing: 4) {
                    Circle().fill(lightColor(state)).frame(width: 6, height: 6)
                    Text(state.rawValue).font(.caption2).foregroundStyle(.secondary)
                }.fixedSize()
            }.padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 6).fill(active ? DeckBrand.accent.opacity(0.12) : (hoveredSlot == index ? Color.secondary.opacity(0.09) : .clear))
                }
        }.buttonStyle(.plain).disabled(row == nil || model.selecting)
            .onHover { isOver in hoveredSlot = isOver ? index : nil }
            .help(row?.title ?? "빈 슬롯")
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
            .accessibilityLabel("슬롯 \(index + 1), \(row?.title ?? "빈 슬롯"), \(state.rawValue)")
            .accessibilityIdentifier("slot-\(index + 1)-\(row?.id.uuidString ?? "empty")")
    }

    private func lightColor(_ state: SessionLight) -> Color {
        if state == .empty { return .secondary.opacity(0.35) }
        let rgb = state.rgb
        return Color(red: Double(rgb >> 16)/255, green: Double((rgb >> 8) & 255)/255, blue: Double(rgb & 255)/255)
    }
}
