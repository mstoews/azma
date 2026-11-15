import SwiftUI

/// A heading with the gold rule the web site uses under its section titles.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var action: (title: LocalizedStringKey, handler: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.sectionTitle)
                    .foregroundStyle(Theme.ink)
                Rectangle()
                    .fill(Theme.gold)
                    .frame(width: 44, height: 2)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            if let action {
                Button(action.title, action: action.handler)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.navy)
            }
        }
    }
}

/// A small rounded label: sector, location, status.
struct Chip: View {
    let text: Text
    var systemImage: String?
    var tint: Color = Theme.navy

    /// Fixed wording from the app, looked up in the string catalog.
    init(_ key: LocalizedStringKey, systemImage: String? = nil, tint: Color = Theme.navy) {
        self.text = Text(key)
        self.systemImage = systemImage
        self.tint = tint
    }

    /// Data (a location, a sector) or text that is already localized.
    init(text: String, systemImage: String? = nil, tint: Color = Theme.navy) {
        self.text = Text(verbatim: text)
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            text
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.1), in: Capsule())
        .lineLimit(1)
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A CMS image, with the navy as its placeholder so a slow photo never flashes
/// white on the paper ground.
struct RemoteImage: View {
    let path: String
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: AppConfig.assetURL(path), transaction: .init(animation: .easeIn(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Theme.navyDeep.overlay(
                    Image(systemName: "building.columns")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.35))
                )
            default:
                Theme.navyDeep.overlay(ProgressView().tint(.white.opacity(0.6)))
            }
        }
    }
}

/// The page header the web site uses: a photograph, darkened, with the title
/// set over it.
struct HeroHeader: View {
    let imagePath: String
    let title: String
    var subtitle: String?
    var height: CGFloat = 220

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(path: imagePath)
                .frame(height: height)
                .clipped()
            LinearGradient(
                colors: [.black.opacity(0.1), .black.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: height)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.display(28))
                    .foregroundStyle(.white)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(Theme.gutter)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// CMS HTML, laid out with the app's typography.
struct RichText: View {
    let html: String
    var spacing: CGFloat = 14

    var body: some View {
        let blocks = HTMLContent.parse(html)
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Text(text)
                        .font(Theme.display(level <= 2 ? 21 : 18, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 4)
                case let .paragraph(text):
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Theme.ink.opacity(0.9))
                        .lineSpacing(4)
                case let .bullets(items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle()
                                    .fill(Theme.gold)
                                    .frame(width: 5, height: 5)
                                    .offset(y: -3)
                                Text(item)
                                    .font(.body)
                                    .foregroundStyle(Theme.ink.opacity(0.9))
                            }
                        }
                    }
                }
            }
        }
        .tint(Theme.navy)
    }
}

/// What a list shows when it has nothing in it yet.
struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    let message: Text
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    init(icon: String, title: LocalizedStringKey, message: LocalizedStringKey,
         actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.init(icon: icon, title: title, message: Text(message), actionTitle: actionTitle, action: action)
    }

    /// `detail` is shown as given: an error from the server, or text that is
    /// already localized.
    init(icon: String, title: LocalizedStringKey, detail: String,
         actionTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.init(icon: icon, title: title, message: Text(verbatim: detail), actionTitle: actionTitle, action: action)
    }

    private init(icon: String, title: LocalizedStringKey, message: Text,
                 actionTitle: LocalizedStringKey?, action: (() -> Void)?) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(Theme.navy.opacity(0.5))
            Text(title)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.ink)
            message
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.brandQuiet)
                    .padding(.top, 4)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, Theme.gutter)
    }
}

/// An inline message above a form or list.
struct Notice: View {
    enum Kind { case info, success, warning, error }

    let kind: Kind
    let message: Text

    /// Fixed wording from the app, looked up in the string catalog.
    init(_ kind: Kind, _ key: LocalizedStringKey) {
        self.kind = kind
        self.message = Text(key)
    }

    /// An error from the server or text that is already localized.
    init(kind: Kind, message: String) {
        self.kind = kind
        self.message = Text(verbatim: message)
    }

    private var tint: Color {
        switch kind {
        case .info: return Theme.navy
        case .success: return Theme.successTint
        case .warning: return Theme.warningTint
        case .error: return Theme.dangerTint
        }
    }

    private var icon: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            message
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A button that runs an async action and shows progress in place.
struct AsyncButton<Label: View>: View {
    let action: () async -> Void
    @ViewBuilder var label: () -> Label
    var isEnabled = true

    @State private var isRunning = false

    var body: some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            ZStack {
                label().opacity(isRunning ? 0 : 1)
                if isRunning { ProgressView().tint(.white) }
            }
        }
        .disabled(isRunning || !isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A labelled row in a form, with the label above the control.
struct FieldRow<Content: View>: View {
    let title: LocalizedStringKey
    var hint: Text?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryInk)
            content()
            if let hint {
                hint
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
    }
}

/// The app's text field look, used by every form.
struct BrandTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension TextFieldStyle where Self == BrandTextFieldStyle {
    static var brand: BrandTextFieldStyle { BrandTextFieldStyle() }
}
