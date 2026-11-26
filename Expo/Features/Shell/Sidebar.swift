import SwiftUI

/// Collapsible navigation: start a session, move between pages, reopen recent
/// work, and reach privacy and account controls.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false

    private var collapsed: Bool { model.sidebarCollapsed }

    private var recent: [ExpoSession] {
        Array(model.state.sessions.filter { $0.deletedAt == nil }.sorted { $0.startedAt > $1.startedAt }.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            SidebarRow(title: model.assist.isActive ? "Open conversation" : "New session", collapsed: collapsed, prominent: true,
                       shortcut: "⌘N", action: model.requestAssistStart) {
                Icon8("new", size: 20)
            }
            .padding(.bottom, 6)
            ForEach(Array(Route.allCases.enumerated()), id: \.element) { index, route in
                SidebarRow(title: route.title, collapsed: collapsed,
                           selected: model.route == route && model.selectedSessionID == nil,
                           shortcut: "⌘\(index + 1)", action: { model.open(route) }) {
                    Icon8(route.rawValue, size: 20)
                }
            }
            if !collapsed && !recent.isEmpty { recents } else { Spacer(minLength: 0) }
            if !collapsed { companion }
            footer
        }
        .padding(.horizontal, 10)
        .padding(.top, 38)
        .padding(.bottom, 10)
        .frame(width: collapsed ? 76 : 216)
        .background(Theme.sidebar)
        .animation(.snappy(duration: 0.22), value: collapsed)
        .confirmationDialog("Sign out of Expo?", isPresented: $confirmSignOut) {
            Button("Sign out") { Task { await model.signOut() } }
        } message: {
            Text("Expo will revoke this device session and keep your encrypted local account data ready for your next sign-in.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !collapsed {
                Logo(size: 22)
                Text("Expo").font(.system(size: 14, weight: .bold))
                Spacer()
            }
            Button { model.sidebarCollapsed.toggle() } label: {
                Image(systemName: "sidebar.left").font(.system(size: 13)).frame(width: 26, height: 24).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .help(collapsed ? "Show sidebar (⌘\\)" : "Hide sidebar (⌘\\)")
            .accessibilityLabel("Toggle sidebar")
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, collapsed ? 0 : 6)
        .padding(.bottom, 10)
    }

    /// The chosen bot, saying what Expo is doing.
    private var companion: some View {
        let active = model.assist.isActive
        return Button { active ? model.requestAssistStart() : model.open(.practice) } label: {
            HStack(spacing: 9) {
                // Moving only during Assist, to keep idle work low.
                if active { RobotMark(size: 38) } else { MarkImage(mark: model.mark, size: 38) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(active ? (model.assist.snapshot.lifecycle == .paused ? "Paused" : "Listening") : "Warm up first")
                        .font(.system(size: 12, weight: .bold))
                    Text(active ? "Open the conversation" : "Try a practice session")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background { Wash() }
            .clipShape(.rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.border) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recents").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 9).padding(.top, 14).padding(.bottom, 3)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(recent) { session in
                        let selected = model.selectedSessionID == session.id
                        Button {
                            model.route = .history
                            model.selectedSessionID = session.id
                        } label: {
                            Text(session.title)
                                .font(.system(size: 12)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 9).frame(height: 27)
                                .background(selected ? Theme.selected : .clear, in: .rect(cornerRadius: 7))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? Theme.text : Theme.secondary)
                        .help("\(session.title) · \(ISO.display(session.startedAt))")
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        VStack(alignment: collapsed ? .center : .leading, spacing: 8) {
            Rectangle().fill(Theme.border).frame(height: 1)
            if collapsed {
                Button { model.setHiddenFromCapture(!model.capturePrivacy.isHidden) } label: {
                    Image(model.capturePrivacy.isHidden ? "privacy-hidden" : "privacy-visible")
                        .resizable().scaledToFit()
                        .frame(width: 28, height: 28).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(model.capturePrivacy == .unavailable)
                .help(model.capturePrivacy.detail)
                .accessibilityLabel("Hide from screen sharing")
                .accessibilityValue(model.capturePrivacy.detail)
            } else {
                PrivacyRow(compact: true)
            }
            // A menu label renders only simple content, so the avatar is drawn behind it.
            HStack(spacing: 8) {
                Text(initials)
                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28).background(Theme.accentSoft, in: .circle)
                if !collapsed {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.state.account?.fullName ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(model.billing.map { "\($0.plan.capitalized) plan" } ?? model.state.account?.email ?? "")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 34)
            .overlay {
                Menu {
                    Button("Settings") { model.open(.settings) }
                    Divider()
                    Button("Sign out") { confirmSignOut = true }
                } label: {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .accessibilityLabel("Account menu")
            }
        }
    }

    private var initials: String {
        let account = model.state.account
        return [account?.firstName, account?.lastName].compactMap { $0?.first.map(String.init) }.joined().uppercased()
    }
}

private struct SidebarRow<Icon: View>: View {
    var title: String
    var collapsed: Bool
    var selected = false
    var prominent = false
    var shortcut: String
    var action: () -> Void
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon.frame(width: 22)
                    .scaleEffect(hovering ? 1.18 : 1)
                    .rotationEffect(.degrees(hovering ? -7 : 0))
                    .animation(.spring(duration: 0.3, bounce: 0.5), value: hovering)
                if !collapsed {
                    Text(title).font(.system(size: 12.5, weight: selected || prominent ? .semibold : .regular))
                    Spacer(minLength: 0)
                    if hovering { Text(shortcut).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary) }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: collapsed ? .center : .leading)
            .background(selected ? Theme.surface : hovering ? Theme.selected.opacity(0.6) : .clear, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.border : .clear) }
            .shadow(color: .black.opacity(selected ? 0.06 : 0), radius: 4, y: 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected || prominent ? Theme.text : Theme.secondary)
        .onHover { hovering = $0 }
        .help(collapsed ? "\(title) (\(shortcut))" : "")
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
