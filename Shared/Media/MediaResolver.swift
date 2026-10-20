import Foundation
import os

/// Находит изображения и фрагменты для рекомендаций без ключей API:
/// • картины и статьи — свободные изображения Википедии (prop=pageimages отдаёт только свободные файлы);
/// • альбомы и фильмы — обложки, 30-секундные фрагменты и трейлеры из iTunes Search API,
///   а если там не нашлось — обложка или постер из статьи Википедии.
/// Найденные ссылки кэшируются в общем контейнере, чтобы виджет не искал их заново.
actor MediaResolver {
    static let shared = MediaResolver()

    private enum Lookup: Sendable {
        case found(String)
        /// Не нашли; искать снова не раньше чем через `retryAfter` секунд.
        case notFound(retryAfter: TimeInterval)
        case failed
    }

    private struct Entry: Codable {
        var value: String?
        var date: Date
        /// Для «не нашли»: когда можно искать снова.
        var retryAt: Date?
    }

    private var cache: [String: Entry] = [:]
    private var loaded = false
    private var inFlight: [String: Task<Lookup, Never>] = [:]
    private let fileURL = AppGroup.containerURL.appendingPathComponent("media-cache.json")
    /// Через сколько повторять поиск, если подходящего результата не нашлось.
    private static let retryNotFound: TimeInterval = 3 * 24 * 3600
    /// …и если iTunes вернул пустой список: так он отвечает и под нагрузкой, поэтому ждём недолго.
    private static let retryEmpty: TimeInterval = 20 * 60

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = ["User-Agent": AppConfig.userAgent]
        return URLSession(configuration: configuration)
    }()

    /// iTunes Search API пускает примерно 20 запросов в минуту с одного адреса.
    private static let iTunesGate = RequestGate(spacing: 1, pauseAfterRefusal: 90)
    private static let log = Logger(subsystem: "Kvartet", category: "media")

    // MARK: - Публичный интерфейс

    /// Обложка, постер или изображение картины.
    func artworkURL(for item: Item) async -> URL? {
        if let direct = item.image.flatMap(URL.init(string:)) { return direct }
        let value = await resolve(key: item.id + "|art") { await Self.findArtwork(for: item) }
        return value.flatMap(URL.init(string:))
    }

    /// Только из кэша, без сети.
    func cachedArtworkURL(for item: Item) -> URL? {
        if let direct = item.image.flatMap(URL.init(string:)) { return direct }
        loadIfNeeded()
        return cache[item.id + "|art"]?.value.flatMap(URL.init(string:))
    }

    /// Для альбома — 30-секундный фрагмент ключевого трека, для фильма — трейлер.
    func previewURL(for item: Item) async -> URL? {
        guard item.kind == .album || item.kind == .film else { return nil }
        let value = await resolve(key: item.id + "|preview") { await Self.findPreview(for: item) }
        return value.flatMap(URL.init(string:))
    }

    /// Страница «Подробнее»: русская статья Википедии, если есть, иначе исходная.
    func readMoreURL(for item: Item) async -> URL? {
        guard let wiki = item.wiki else { return nil }
        let fallback = item.wikipediaURL
        if wiki.hasPrefix("ru:") { return fallback }
        let value = await resolve(key: item.id + "|wiki") {
            switch await Self.wikipediaInfo(wiki) {
            case .some(let info): return info.ruURL.map(Lookup.found) ?? .notFound(retryAfter: Self.retryNotFound)
            case .none: return .failed
            }
        }
        return value.flatMap(URL.init(string:)) ?? fallback
    }

    // MARK: - Кэш

    private func resolve(key: String, _ work: @escaping @Sendable () async -> Lookup) async -> String? {
        loadIfNeeded()
        if let cached = usable(cache[key]) { return cached.value }
        // Возможно, виджет или приложение уже нашли ссылку — перечитываем файл.
        reloadFromDisk()
        if let cached = usable(cache[key]) { return cached.value }

        let task: Task<Lookup, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            task = Task { await work() }
            inFlight[key] = task
        }
        let result = await task.value
        inFlight[key] = nil

        switch result {
        case .found(let value):
            cache[key] = Entry(value: value, date: Date())
            save()
            return value
        case .notFound(let retryAfter):
            cache[key] = Entry(value: nil, date: Date(), retryAt: Date().addingTimeInterval(retryAfter))
            save()
            return nil
        case .failed:
            return nil
        }
    }

    /// Запись из кэша, если она ещё актуальна. Двойной Optional: .some(nil) — «точно не нашли».
    private func usable(_ entry: Entry?) -> Entry? {
        guard let entry else { return nil }
        if entry.value != nil { return entry }
        let retryAt = entry.retryAt ?? entry.date.addingTimeInterval(Self.retryNotFound)
        return Date() < retryAt ? entry : nil
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        reloadFromDisk()
    }

    private func reloadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }
        cache.merge(stored) { current, disk in disk.date > current.date ? disk : current }
    }

    private func save() {
        reloadFromDisk()
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Поиск

    private static func findArtwork(for item: Item) async -> Lookup {
        var failed = false
        var retryAfter = retryNotFound
        let iTunes: Match?
        switch item.kind {
        case .album: iTunes = await iTunesAlbum(item)
        case .film: iTunes = await iTunesMovie(item)
        case .painting, .article: iTunes = nil
        }
        switch iTunes {
        case .found(let match):
            if let art = match.artworkUrl100 { return .found(upscaledArtwork(art)) }
        case .empty: retryAfter = retryEmpty
        case .failed: failed = true
        case .notFound, nil: break
        }
        if let wiki = item.wiki {
            // Обложки и постеры в Википедии — несвободные файлы, их просим отдельно.
            let anyLicense = item.kind == .album || item.kind == .film
            guard let info = await wikipediaInfo(wiki, anyLicense: anyLicense) else { return .failed }
            if let image = info.image { return .found(image) }
        }
        return failed ? .failed : .notFound(retryAfter: retryAfter)
    }

    private static func findPreview(for item: Item) async -> Lookup {
        switch item.kind {
        case .film:
            switch await iTunesMovie(item) {
            case .found(let match): return match.previewUrl.map(Lookup.found) ?? .notFound(retryAfter: retryNotFound)
            case .notFound: return .notFound(retryAfter: retryNotFound)
            case .empty: return .notFound(retryAfter: retryEmpty)
            case .failed: return .failed
            }
        case .album:
            return await iTunesSongPreview(item)
        case .painting, .article:
            return .notFound(retryAfter: retryNotFound)
        }
    }

    // MARK: - Википедия

    struct WikiInfo: Sendable {
        var image: String?
        var pageURL: String?
        var ruURL: String?
    }

    private struct WikiResponse: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Page: Decodable {
            let title: String?
            let missing: Bool?
            let fullurl: String?
            let thumbnail: Thumbnail?
            let langlinks: [LangLink]?
        }
        struct Thumbnail: Decodable { let source: String }
        struct LangLink: Decodable {
            let lang: String
            let url: String?
        }
        let query: Query?
    }

    /// `wiki` в формате "en:The_Hunters_in_the_Snow". nil — ошибка сети.
    /// `anyLicense` — брать и несвободное изображение статьи (обложку альбома, постер фильма).
    static func wikipediaInfo(_ wiki: String, anyLicense: Bool = false) async -> WikiInfo? {
        let parts = wiki.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return WikiInfo() }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(parts[0]).wikipedia.org"
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "prop", value: "pageimages|langlinks|info"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: String(AppConfig.wikipediaImageWidth)),
            URLQueryItem(name: "lllang", value: "ru"),
            URLQueryItem(name: "llprop", value: "url"),
            URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "titles", value: parts[1].replacingOccurrences(of: "_", with: " "))
        ]
        if anyLicense {
            components.queryItems?.append(URLQueryItem(name: "pilicense", value: "any"))
        }
        guard let url = components.url, let data = await get(url) else { return nil }
        guard let response = try? JSONDecoder().decode(WikiResponse.self, from: data),
              let page = response.query?.pages?.first,
              page.missing != true
        else { return WikiInfo() }
        let ruURL = parts[0] == "ru" ? page.fullurl : page.langlinks?.first(where: { $0.lang == "ru" })?.url
        return WikiInfo(image: page.thumbnail?.source, pageURL: page.fullurl, ruURL: ruURL)
    }

    // MARK: - iTunes

    struct ITunesItem: Decodable, Sendable {
        /// «feature-movie», «song»… (у альбомов нет).
        let kind: String?
        let artistName: String?
        let collectionName: String?
        let trackName: String?
        let artworkUrl100: String?
        let previewUrl: String?
        let releaseDate: String?
    }

    private struct ITunesResponse: Decodable {
        let results: [ITunesItem]
    }

    private enum Match: Sendable {
        case found(ITunesItem)
        /// Результаты были, но ни один не подошёл.
        case notFound
        /// Все поиски вернули пустой список.
        case empty
        case failed
    }

    /// nil — ошибка сети.
    /// Без `media` и `entity` ищет по всему магазину.
    private static func iTunesSearch(term: String, media: String?, entity: String?, country: String, limit: Int = 25) async -> [ITunesItem]? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let media { components?.queryItems?.append(URLQueryItem(name: "media", value: media)) }
        if let entity { components?.queryItems?.append(URLQueryItem(name: "entity", value: entity)) }
        guard let url = components?.url, let data = await get(url, gate: iTunesGate) else { return nil }
        let results = (try? JSONDecoder().decode(ITunesResponse.self, from: data))?.results ?? []
        if results.isEmpty {
            log.notice("iTunes: nothing for «\(term, privacy: .public)» (\(entity ?? "all", privacy: .public), \(country, privacy: .public))")
        }
        return results
    }

    private static func countries(for item: Item) -> [String] {
        item.isRussianWork ? ["ru", "us"] : ["us"]
    }

    private static func artists(of item: Item) -> [String] {
        [item.originalCreator, item.creator].compactMap { $0 }
    }

    private static func titles(of item: Item) -> [String] {
        var titles = [item.originalTitle, item.title].compactMap { $0 }
        // У фильмов в поле search — международное название для iTunes («Babette's Feast»).
        if item.kind == .film, let search = item.search {
            titles.insert(search, at: 0)
        }
        return titles
    }

    private static func iTunesAlbum(_ item: Item) async -> Match {
        let artists = artists(of: item)
        let titles = titles(of: item)
        var outcome = SearchOutcome()
        for country in countries(for: item) {
            let results = await iTunesSearch(term: "\(artists[0]) \(titles[0])", media: "music", entity: "album", country: country)
            let match = outcome.record(results)?.first { result in
                artists.contains { Matching.sameArtist($0, result.artistName) }
                    && titles.contains { Matching.sameTitle($0, result.collectionName) }
            }
            if let match { return .found(match) }
            // Поиск альбомов находит не всё (например, «For Emma, Forever Ago»), а песня с него
            // находится — и у неё та же обложка.
            if let track = item.keyTrack {
                let songs = await iTunesSearch(term: "\(artists[0]) \(track)", media: "music", entity: "song", country: country)
                let song = outcome.record(songs)?.first { result in
                    artists.contains { Matching.sameArtist($0, result.artistName) }
                        && titles.contains { Matching.sameTitle($0, result.collectionName) }
                }
                if let song { return .found(song) }
            }
        }
        return outcome.miss
    }

    private static func iTunesMovie(_ item: Item) async -> Match {
        let titles = titles(of: item)
        var outcome = SearchOutcome()
        for country in countries(for: item) {
            // В американском iTunes нет смысла искать по-русски или по-японски.
            for title in titles where country != "us" || Matching.isLatin(title) {
                // Поиск с media=movie сейчас ничего не находит, поэтому ищем по всему магазину
                // и берём только полнометражные фильмы.
                let results = await iTunesSearch(term: title, media: nil, entity: nil, country: country, limit: 50)
                let match = outcome.record(results)?.first { result in
                    result.kind == "feature-movie"
                        && titles.contains { Matching.sameTitle($0, result.trackName) }
                        && Matching.isYear(item.yearValue, closeTo: result.releaseDate)
                }
                if let match { return .found(match) }
            }
        }
        return outcome.miss
    }

    private static func iTunesSongPreview(_ item: Item) async -> Lookup {
        guard let track = item.keyTrack else { return .notFound(retryAfter: retryNotFound) }
        let artists = artists(of: item)
        var outcome = SearchOutcome()
        for country in countries(for: item) {
            let results = await iTunesSearch(term: "\(artists[0]) \(track)", media: "music", entity: "song", country: country)
            let match = outcome.record(results)?.first { result in
                result.previewUrl != nil
                    && artists.contains { Matching.sameArtist($0, result.artistName) }
                    && Matching.sameTitle(track, result.trackName)
            }
            if let preview = match?.previewUrl { return .found(preview) }
        }
        switch outcome.miss {
        case .failed: return .failed
        case .empty: return .notFound(retryAfter: retryEmpty)
        default: return .notFound(retryAfter: retryNotFound)
        }
    }

    /// Итог нескольких поисков без совпадения: сбой сети, пустые ответы или просто не нашли.
    private struct SearchOutcome {
        private var failed = false
        private var sawResults = false

        /// Запоминает ответ и возвращает его (nil — сбой).
        mutating func record(_ results: [ITunesItem]?) -> [ITunesItem]? {
            if let results {
                sawResults = sawResults || !results.isEmpty
            } else {
                failed = true
            }
            return results
        }

        var miss: Match {
            if failed { return .failed }
            return sawResults ? .notFound : .empty
        }
    }

    /// iTunes отдаёт картинку 100×100; меняем размер в адресе на 1200×1200 (с сохранением пропорций).
    private static func upscaledArtwork(_ url: String) -> String {
        url.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
    }

    // MARK: - Сеть

    /// nil — ошибка сети или сервер отказал (тогда поиск повторится в следующий раз).
    private static func get(_ url: URL, gate: RequestGate? = nil) async -> Data? {
        if let gate, await !gate.enter() {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                log.error("HTTP \(status) for \(url.absoluteString, privacy: .public)")
                if status == 403 || status == 429 {
                    await gate?.pause()
                }
                return nil
            }
            return data
        } catch {
            log.error("\(error.localizedDescription, privacy: .public) for \(url.absoluteString, privacy: .public)")
            return nil
        }
    }
}

/// Очередь запросов к сервису с ограничением частоты: запросы идут не чаще
/// одного в `spacing` секунд, а после отказа (403/429) сервис какое-то время не беспокоим.
actor RequestGate {
    private let spacing: TimeInterval
    private let pauseAfterRefusal: TimeInterval
    private var nextSlot = Date.distantPast
    private var pausedUntil = Date.distantPast

    init(spacing: TimeInterval, pauseAfterRefusal: TimeInterval) {
        self.spacing = spacing
        self.pauseAfterRefusal = pauseAfterRefusal
    }

    /// Дожидается своей очереди. false — сервис просил подождать, запрос лучше не отправлять.
    func enter() async -> Bool {
        let now = Date()
        guard now >= pausedUntil else { return false }
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(spacing)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        return Date() >= pausedUntil
    }

    func pause() {
        pausedUntil = Date().addingTimeInterval(pauseAfterRefusal)
    }
}

/// Нестрогое сравнение названий и имён из разных источников.
enum Matching {
    static func normalize(_ text: String) -> String {
        var value = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "&", with: " and ")
        // «(Remastered)», «[Deluxe Edition]» и т. п.
        value = value.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: " ", options: .regularExpression)
        let scalars = value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    static func sameTitle(_ expected: String, _ candidate: String?) -> Bool {
        guard let candidate else { return false }
        let a = normalize(expected)
        let b = normalize(candidate)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || b.hasPrefix(a + " ") || a.hasPrefix(b + " ")
    }

    static func sameArtist(_ expected: String, _ candidate: String?) -> Bool {
        guard let candidate else { return false }
        let a = normalize(expected)
        let b = normalize(candidate)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || b.contains(a) || a.contains(b)
    }

    /// Название латиницей (в том числе с диакритикой: «Die große Stille», «Höstsonaten»).
    static func isLatin(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { !CharacterSet.letters.contains($0) || $0.value < 0x0250 }
    }

    static func isYear(_ year: Int?, closeTo releaseDate: String?, tolerance: Int = 2) -> Bool {
        guard let year, let releaseDate, let released = Int(releaseDate.prefix(4)) else { return false }
        return abs(released - year) <= tolerance
    }
}
