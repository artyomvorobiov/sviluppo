import Foundation

/// Выпуск дня: тема и четыре связанные с ней рекомендации.
struct Issue: Codable, Identifiable, Hashable {
    var id: String
    var theme: String
    var intro: String
    var items: [Item]

    func item(_ kind: ItemKind) -> Item? {
        items.first { $0.kind == kind }
    }

    /// Рекомендации выбранных типов в порядке «от быстрого к долгому».
    func items(for kinds: Set<ItemKind>) -> [Item] {
        ItemKind.displayOrder.compactMap { kinds.contains($0) ? item($0) : nil }
    }

    static let placeholder = Issue(
        id: "empty",
        theme: "Скоро здесь будет тема",
        intro: "Каталог пуст или повреждён. Проверьте файл catalog.json.",
        items: []
    )
}

/// Весь каталог (файл Shared/Resources/catalog.json).
struct Catalog: Codable {
    var schemaVersion: Int
    /// Дата обновления в формате "2026-10-20": из двух каталогов берётся более свежий.
    var updated: String?
    var issues: [Issue]

    static let supportedSchemaVersion = 1
}
