import Foundation

/// Каталог выпусков с быстрым поиском рекомендаций по id.
final class ContentLibrary {
    let catalog: Catalog
    private let itemsByID: [String: Item]
    private let issuesByItemID: [String: Issue]

    var issues: [Issue] { catalog.issues }

    init(catalog: Catalog) {
        self.catalog = catalog
        var items: [String: Item] = [:]
        var issues: [String: Issue] = [:]
        for issue in catalog.issues {
            for item in issue.items {
                items[item.id] = item
                issues[item.id] = issue
            }
        }
        itemsByID = items
        issuesByItemID = issues
    }

    func item(id: String) -> Item? { itemsByID[id] }

    func issue(containing itemID: String) -> Issue? { issuesByItemID[itemID] }

    // MARK: - Загрузка

    private static var remoteFileURL: URL {
        AppGroup.containerURL.appendingPathComponent("catalog-remote.json")
    }

    /// Встроенный каталог или скачанный (если он новее).
    static func load() -> ContentLibrary {
        let bundled = loadBundled()
        if let remote = loadRemote(), (remote.updated ?? "") >= (bundled?.updated ?? "") {
            return ContentLibrary(catalog: remote)
        }
        return ContentLibrary(catalog: bundled ?? Catalog(schemaVersion: Catalog.supportedSchemaVersion, updated: nil, issues: []))
    }

    private static func loadBundled() -> Catalog? {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    private static func loadRemote() -> Catalog? {
        guard let data = try? Data(contentsOf: remoteFileURL) else { return nil }
        return decode(data)
    }

    private static func decode(_ data: Data) -> Catalog? {
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.schemaVersion <= Catalog.supportedSchemaVersion,
              !catalog.issues.isEmpty
        else { return nil }
        return catalog
    }

    /// Скачивает каталог с `AppConfig.remoteCatalogURL`. Возвращает true, если он изменился.
    static func refreshRemote() async -> Bool {
        guard let url = AppConfig.remoteCatalogURL else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              decode(data) != nil
        else { return false }
        if let existing = try? Data(contentsOf: remoteFileURL), existing == data { return false }
        do {
            try data.write(to: remoteFileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// Какой выпуск показывать в какой день: по порядку от дня первого запуска,
/// после последнего выпуска — снова с первого.
struct DayPlanner {
    let library: ContentLibrary
    let startDay: Date

    func index(for date: Date) -> Int {
        max(0, Days.between(startDay, date))
    }

    func issue(for date: Date) -> Issue {
        let issues = library.issues
        guard !issues.isEmpty else { return .placeholder }
        return issues[index(for: date) % issues.count]
    }

    static func startDay(from state: UserState) -> Date {
        state.startDay.flatMap(Days.date(fromKey:)) ?? Days.startOfDay(Date())
    }
}
