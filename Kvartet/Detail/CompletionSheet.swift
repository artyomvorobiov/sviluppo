import SwiftUI

/// «Как вам?» — оценка и заметка после знакомства с рекомендацией.
struct CompletionSheet: View {
    let item: Item

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RatingPicker(rating: $rating, color: item.kind.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } header: {
                    Text("Как вам?")
                } footer: {
                    Text(RatingPicker.caption(for: rating))
                        .frame(maxWidth: .infinity)
                }

                Section("Заметка для дневника") {
                    TextField("Мысль, цитата, ассоциация…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                }

                if model.isDone(item) {
                    Section {
                        Button("Снять отметку", role: .destructive) {
                            model.unmark(item)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        model.markDone(item, rating: rating == 0 ? nil : rating, note: note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let completion = model.completion(for: item) {
                    rating = completion.rating ?? 0
                    note = completion.note ?? ""
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Пять звёзд, по нажатию.
struct RatingPicker: View {
    @Binding var rating: Int
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 14) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = (rating == value) ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.title)
                        .foregroundStyle(value <= rating ? color : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) из 5")
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }

    static func caption(for rating: Int) -> String {
        switch rating {
        case 1: "Не моё"
        case 2: "Так себе"
        case 3: "Неплохо"
        case 4: "Понравилось"
        case 5: "Восторг"
        default: "Можно без оценки"
        }
    }
}
