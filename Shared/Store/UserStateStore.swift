import Foundation

/// Чтение и запись состояния пользователя (файл user-state.json в общем контейнере).
/// Каждый `update` перечитывает файл с диска, поэтому изменения из виджета не теряются.
final class UserStateStore {
    static let shared = UserStateStore()

    private let fileURL = AppGroup.containerURL.appendingPathComponent("user-state.json")
    private let lock = NSLock()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load() -> UserState {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    /// Атомарно меняет состояние и возвращает новое.
    @discardableResult
    func update(_ change: (inout UserState) -> Void) -> UserState {
        lock.lock()
        defer { lock.unlock() }
        var state = read()
        change(&state)
        write(state)
        return state
    }

    /// День начала; если его ещё нет — сегодня (и сразу сохраняем).
    func ensureStartDay(now: Date = Date()) -> UserState {
        let state = load()
        if state.startDay != nil { return state }
        return update { state in
            if state.startDay == nil { state.startDay = Days.key(for: now) }
        }
    }

    private func read() -> UserState {
        guard let data = try? Data(contentsOf: fileURL) else { return UserState() }
        return (try? Self.decoder.decode(UserState.self, from: data)) ?? UserState()
    }

    private func write(_ state: UserState) {
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
