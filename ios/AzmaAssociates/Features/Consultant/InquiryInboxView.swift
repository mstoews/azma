import SwiftUI

/// Consultation requests, newest first with the unanswered ones on top.
struct InquiryInboxView: View {
    @Environment(AppSession.self) private var session
    @State private var inquiries: [Inquiry] = []
    @State private var counts: [String: Int] = [:]
    @State private var filter = "new"
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterRow
                if let errorMessage {
                    Notice(kind: .error, message: errorMessage)
                        .padding(.horizontal, Theme.gutter)
                }
                if isLoading && inquiries.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if inquiries.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "Nothing waiting",
                        message: "New consultation requests arrive here."
                    )
                } else {
                    ForEach(inquiries) { inquiry in
                        InquiryCard(inquiry: inquiry) { status in
                            await setStatus(inquiry, status)
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(InquiryStatus.allCases, id: \.self) { status in
                let count = counts[status.rawValue] ?? 0
                Button {
                    filter = status.rawValue
                    Task { await load() }
                } label: {
                    Text(count > 0 ? "\(status.label) (\(count))" : status.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(filter == status.rawValue ? Theme.navy : Theme.card, in: Capsule())
                        .foregroundStyle(filter == status.rawValue ? Color.white : Theme.ink)
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: filter == status.rawValue ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.api.fetchInquiries(status: filter)
            inquiries = page.inquiries
            counts = page.countsByStatus
            errorMessage = nil
        } catch {
            errorMessage = await session.message(for: error)
        }
    }

    private func setStatus(_ inquiry: Inquiry, _ status: InquiryStatus) async {
        do {
            _ = try await session.api.setInquiryStatus(id: inquiry.id, status: status.rawValue)
            await load()
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}

private struct InquiryCard: View {
    let inquiry: Inquiry
    let onStatus: (InquiryStatus) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(inquiry.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                    if !inquiry.company.isEmpty {
                        Text(inquiry.company)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                Chip(text: inquiry.kindKind.label, tint: inquiry.kindKind == .hiring ? Theme.navy : Theme.gold)
            }

            Text(inquiry.message)
                .font(.footnote)
                .foregroundStyle(Theme.ink.opacity(0.9))

            FlowLayout(spacing: 6) {
                Chip(text: inquiry.email, systemImage: "envelope")
                if !inquiry.phone.isEmpty { Chip(text: inquiry.phone, systemImage: "phone") }
                if !inquiry.office.isEmpty { Chip(text: Format.office(inquiry.office), systemImage: "building.2") }
                if inquiry.accountEmail?.isEmpty == false {
                    Chip("Has an account", systemImage: "person.crop.circle", tint: Theme.successTint)
                }
            }

            HStack(spacing: 14) {
                if let url = URL(string: "mailto:\(inquiry.email)") {
                    Link(destination: url) {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Menu {
                    ForEach(InquiryStatus.allCases, id: \.self) { status in
                        Button(status.label) { Task { await onStatus(status) } }
                    }
                } label: {
                    Label(InquiryStatus(rawValue: inquiry.status)?.label ?? inquiry.status,
                          systemImage: "flag")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(Format.relative(inquiry.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .brandCard()
    }
}
