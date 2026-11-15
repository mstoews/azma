import SwiftUI

/// "If you would like to discuss a position, career change or market
/// information, please feel free to contact below." — the web site's Contact
/// page, as a form that reaches a consultant's desk.
struct ContactView: View {
    @Environment(AppSession.self) private var session
    @Environment(SiteStore.self) private var site

    @State private var draft: InquiryInput
    @State private var errorMessage: String?
    @State private var sent = false

    init(prefill: InquiryInput? = nil) {
        _draft = State(initialValue: prefill ?? InquiryInput())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if sent {
                        sentCard
                    } else {
                        form
                    }
                    offices
                }
                .padding(.bottom, 36)
            }
            .brandBackground()
            .scrollIndicators(.hidden)
            .navigationTitle("Contact")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: prefillFromAccount)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let page = site.contactPage, !page.hero.isEmpty {
                HeroHeader(
                    imagePath: page.hero,
                    title: String(localized: "Talk to a consultant"),
                    subtitle: String(localized: "Tokyo · Singapore"),
                    height: 190
                )
            }
            Text("Whether you are hiring or thinking about your next move, tell us what you need and the right consultant will come back to you.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
        }
    }

    private var sentCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.successTint)
            Text("Thank you — your message is with us")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Group {
                if draft.office.isEmpty {
                    Text("A consultant from the nearest office will be in touch.")
                } else {
                    Text("A consultant from the \(Format.office(draft.office)) office will be in touch.")
                }
            }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Send another") {
                draft = InquiryInput()
                prefillFromAccount()
                sent = false
            }
            .buttonStyle(.brandQuiet)
        }
        .brandCard(padding: 22)
        .padding(.horizontal, Theme.gutter)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage {
                Notice(kind: .error, message: errorMessage)
            }

            FieldRow(title: "What is this about") {
                Picker("Subject", selection: $draft.kind) {
                    ForEach(InquiryKind.allCases, id: \.rawValue) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            FieldRow(title: "Your name") {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.brand)
                    .textContentType(.name)
            }

            FieldRow(title: "Email") {
                TextField("you@example.com", text: $draft.email)
                    .textFieldStyle(.brand)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            HStack(alignment: .top, spacing: 12) {
                FieldRow(title: "Phone (optional)") {
                    TextField("Phone", text: $draft.phone)
                        .textFieldStyle(.brand)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                FieldRow(title: "Company (optional)") {
                    TextField("Company", text: $draft.company)
                        .textFieldStyle(.brand)
                }
            }

            FieldRow(title: "Office") {
                Picker("Office", selection: $draft.office) {
                    Text("Either").tag("")
                    ForEach(session.options.offices, id: \.self) { office in
                        Text(Format.office(office)).tag(office)
                    }
                }
                .pickerStyle(.segmented)
            }

            FieldRow(title: "Message", hint: InquiryKind(rawValue: draft.kind).map { Text(verbatim: $0.prompt) }) {
                LongTextField(text: $draft.message, minHeight: 150)
            }

            AsyncButton {
                await send()
            } label: {
                Text("Send to AZMA")
            }
            .buttonStyle(.brand)

            Text("Or email us directly at \(AppConfig.contactEmail).")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var offices: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Our offices")
            HStack(alignment: .top, spacing: 12) {
                officeCard(
                    city: "Tokyo",
                    lines: ["AZMA & Associates (Japan) Limited", "Morita Building 2F", "3-37-3 Honmachi, Shibuya", "Tokyo 151-0071"]
                )
                officeCard(
                    city: "Singapore",
                    lines: ["AZMA & Associates Pte. Ltd.", "18 Robinson Road, #20-02", "Singapore 048547"]
                )
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func officeCard(city: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(city)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.ink)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .brandCard(padding: 14)
    }

    private func prefillFromAccount() {
        guard let account = session.account else { return }
        if draft.name.isEmpty { draft.name = account.name }
        if draft.email.isEmpty { draft.email = account.email }
        if draft.kind == InquiryKind.hiring.rawValue, account.role == .candidate {
            draft.kind = InquiryKind.career.rawValue
        }
    }

    private func send() async {
        if let problem = draft.problem {
            errorMessage = problem
            return
        }
        do {
            _ = try await session.api.sendInquiry(draft)
            errorMessage = nil
            sent = true
        } catch {
            errorMessage = await session.message(for: error)
        }
    }
}
