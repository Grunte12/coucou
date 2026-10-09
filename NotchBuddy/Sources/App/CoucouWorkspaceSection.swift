#if COUCOU_HUB
import SwiftUI

extension Notification.Name {
    /// object: `CoucouWorkspaceSection`. Posted by the host, e.g. on file drag-enter.
    static let coucouWorkspaceShowSection = Notification.Name("coucouWorkspaceShowSection")
}

enum CoucouWorkspaceSection: String, CaseIterable {
    case agents, shelf, clipboard, usage, folders

    var title: String {
        switch self {
        case .agents:    return "Agents"
        case .shelf:     return "Shelf"
        case .clipboard: return "Clipboard"
        case .usage:     return "Usage"
        case .folders:   return "Folders"
        }
    }
    var icon: String {
        switch self {
        case .agents:    return "person.2.fill"
        case .shelf:     return "tray.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .usage:     return "chart.bar.fill"
        case .folders:   return "folder.fill"
        }
    }
}

/// Vertical icon rail in the left gutter, under the companion. Icons only:
/// the dense Agents header never gains labels.
struct CoucouWorkspaceRail: View {
    let selection: CoucouWorkspaceSection
    let shelfCount: Int
    let onSelect: (CoucouWorkspaceSection) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(CoucouWorkspaceSection.allCases, id: \.self) { section in
                button(section)
            }
        }
    }

    private func button(_ section: CoucouWorkspaceSection) -> some View {
        let on = selection == section
        let count = section == .shelf ? shelfCount : 0
        return Button { onSelect(section) } label: {
            Image(systemName: section.icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(on ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                .frame(width: 30, height: 24)
                .background(on ? Color(hex: "#1D1F23") : Color.clear)
                .clipShape(Capsule())
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : String(count))
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 3.5)
                            .background(Color(hex: "#F5F6F8"), in: Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(section.title)
        .accessibilityLabel(count > 0 ? "\(section.title), \(count) files" : section.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Header for the non-Agents sections. Same 24pt height and close position as
/// the Agents header, so the frame anchors do not move between sections.
struct CoucouSectionHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            actions()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
        }
        .frame(height: 24)
    }
}

/// Round ⓘ toggle that reveals a section's fine print in place.
struct CoucouInfoToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOn.toggle() } } label: {
            Image(systemName: isOn ? "info.circle.fill" : "info.circle")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color(hex: isOn ? "#C5C8CD" : "#8E939C"))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Hide details" : "About this section")
    }
}

/// Small text action used in section headers.
struct CoucouHeaderAction: View {
    let title: String
    var disabled = false
    let action: () -> Void

    init(_ title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.disabled = disabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .padding(.horizontal, 8).frame(height: 20)
                .background(Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

/// Shared look for the Shelf, Clipboard and Usage bodies.
enum CoucouWorkspaceStyle {
    /// Spacing scale for the workspace: everything sits on 4 / 8 / 12 / 16.
    static let gap: CGFloat = 8
    static let sectionGap: CGFloat = 12

    /// Muted fine print shown under an ⓘ toggle.
    static func finePrint(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.system(size: 10.5)).foregroundColor(Color(hex: "#8E939C"))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        .transition(.opacity)
    }

    static func label(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#6B7079"))
    }

    /// Soft edge at the bottom of a vertical scroll body, so rows that run
    /// under the footer read as "more below" instead of being cut.
    static let scrollFade = LinearGradient(stops: [.init(color: .black, location: 0),
                                                   .init(color: .black, location: 0.88),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)

    static func rowBackground(_ shape: some Shape = Capsule()) -> some View {
        shape.fill(Color(hex: "#0E0F11")).overlay(shape.stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    @ViewBuilder static func banner(_ text: String, symbol: String = "exclamationmark.triangle.fill",
                                    hex: String = "#F5A524") -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 10.5)).foregroundColor(Color(hex: hex))
            Text(text).font(.system(size: 10.5)).foregroundColor(Color(hex: "#C5C8CD"))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: hex).opacity(0.1)))
    }

    static func emptyNotice(_ title: String, _ message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundColor(Color(hex: "#6B7079"))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text(message).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }
}
#endif
