import SwiftUI

/// Usage so far and the four plans: pick one to see it, then switch to it.
struct PlanSection: View {
    @Environment(AppModel.self) private var model
    @State private var yearly = false
    @State private var selected: String?

    private var current: String { model.billing?.plan ?? "free" }
    private var chosen: PlanCard { PlanCard.all.first { $0.id == (selected ?? current) } ?? PlanCard.all[0] }

    var body: some View {
        Card(title: "Plan & usage", icon: "plan") {
            if let usage = model.billing?.usage {
                HStack(spacing: 18) {
                    meter("AI answers", used: usage.answersUsed, limit: usage.answersLimit)
                    meter("Emailed notes", used: usage.notesUsed, limit: usage.notesLimit)
                }
            } else {
                Text("Plan details are unavailable right now.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 10) {
                Picker("Billing", selection: $yearly) { Text("Monthly").tag(false); Text("Yearly").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                if yearly { Tag(text: "2 months free", tone: .success).transition(.scale.combined(with: .opacity)) }
                Spacer()
                if model.plansAreTestOnly { Tag(text: "Test mode · no charge", tone: .warning) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(PlanCard.all) { card($0) }
            }
            footer
        }
        .animation(.snappy(duration: 0.25), value: yearly)
        .animation(.snappy(duration: 0.25), value: selected)
        .task { await model.refreshBilling() }
    }

    private func price(_ plan: PlanCard) -> String {
        plan.monthly == 0 ? "Free" : "₦\((yearly ? plan.yearly : plan.monthly).formatted())"
    }

    private func card(_ plan: PlanCard) -> some View {
        let isChosen = chosen.id == plan.id
        let isCurrent = current == plan.id
        return Button { selected = plan.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Icon8(["free": "chat", "starter": "mic", "pro": "star", "max": "bot"][plan.id] ?? "plan", size: 28)
                    Spacer()
                    Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isChosen ? Theme.accent : Theme.border)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(plan.name).font(.system(size: 13.5, weight: .bold))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(price(plan)).font(.system(size: 17, weight: .bold)).contentTransition(.numericText())
                    if plan.monthly > 0 { Text(yearly ? "/ year" : "/ month").font(.system(size: 10.5)).foregroundStyle(Theme.secondary) }
                }
                ForEach(plan.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.success)
                        Text(point).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if isCurrent { StatusPill(label: "Current plan", color: Theme.success) }
            }
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 216, alignment: .topLeading)
            .background(isChosen ? Theme.surface : Theme.subtle, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(isChosen ? Theme.accent : Theme.border, lineWidth: isChosen ? 2 : 1) }
            .shadow(color: .black.opacity(isChosen ? 0.1 : 0), radius: 8, y: 4)
            .offset(y: isChosen ? -2 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plan.name), \(price(plan))\(isCurrent ? ", current plan" : "")")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var footer: some View {
        let isCurrent = chosen.id == current
        // Real checkout cannot sell the free plan.
        let canSwitch = !isCurrent && (model.plansAreTestOnly || chosen.id != "free")
        return HStack {
            Text(isCurrent ? "You’re on \(chosen.name). Select another plan to compare or switch."
                 : model.plansAreTestOnly ? "Switching here is free and only affects this Mac’s server." : "Checkout opens in your browser.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            Spacer()
            if canSwitch {
                AsyncButton(title: "Switch to \(chosen.name)", busyTitle: "Switching…") {
                    await model.choosePlan(chosen.id, interval: yearly ? "yearly" : "monthly")
                }
                .id(chosen.id)
            }
        }
    }

    private func meter(_ title: String, used: Int, limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(limit.map { "\(used) of \($0)" } ?? "\(used) · unlimited").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            ProgressView(value: limit.map { $0 > 0 ? min(1, Double(used) / Double($0)) : 0 } ?? 0)
        }
    }
}
