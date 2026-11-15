import SwiftUI

/// Pick several values from a fixed list — sectors, mostly.
struct MultiSelectField: View {
    let title: String
    let options: [String]
    @Binding var selection: [String]
    var limit: Int = 12

    var body: some View {
        NavigationLink {
            List {
                Section {
                    ForEach(options, id: \.self) { option in
                        Button {
                            toggle(option)
                        } label: {
                            HStack {
                                Text(option).foregroundStyle(Theme.ink)
                                Spacer()
                                if selection.contains(option) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.navy)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Choose up to \(limit).")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(selection.isEmpty ? "None" : selection.joined(separator: ", "))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func toggle(_ option: String) {
        if let index = selection.firstIndex(of: option) {
            selection.remove(at: index)
        } else if selection.count < limit {
            selection.append(option)
        }
    }
}

/// A short list of free text the person types — the roles they want, the
/// languages they work in.
struct TokenListField: View {
    let title: String
    var placeholder: String = "Add"
    @Binding var items: [String]
    var limit: Int = 12

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !items.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            items.removeAll { $0 == item }
                        } label: {
                            HStack(spacing: 4) {
                                Text(item)
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.navy)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.navy.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(item)")
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.brand)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button("Add", action: add)
                    .font(.subheadline.weight(.semibold))
                    .disabled(draft.trimmed.isEmpty || items.count >= limit)
            }
        }
    }

    private func add() {
        let value = draft.trimmed
        guard !value.isEmpty, items.count < limit, !items.contains(value) else {
            draft = ""
            return
        }
        items.append(value)
        draft = ""
    }
}

/// A multi-line field with the app's look, for the long-form answers.
struct LongTextField: View {
    @Binding var text: String
    var minHeight: CGFloat = 130

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}
