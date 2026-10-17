// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Observation
import SwiftUI

/// Live scores and a market watchlist: games from the leagues you follow, read from ESPN's public
/// scoreboards, and stocks, indices, and coins from Yahoo Finance, with a ticker on the closed notch.
///
/// Both are polls, since neither service pushes. While the tab is open it reads every 30 seconds.
/// Closed, it reads only for what the ticker shows: every 90 seconds while a game is live or the
/// watchlist rotates there, and every 10 minutes while it waits for a game to start. Nothing runs
/// while the ticker is off and the tab is closed, or while the notch is hidden. A "slow down" from
/// either service keeps the last numbers and waits longer before asking again.
@MainActor
@Observable
public final class LiveFeature: NotchFeature {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case scores, markets

        public var id: Self { self }
        public var title: String { self == .scores ? "Scores" : "Markets" }
    }

    /// What the closed notch rotates through beside the camera.
    public enum Ticker: String, CaseIterable, Identifiable, Sendable {
        case liveGames, watchlist, both, off

        public var id: Self { self }

        public var title: String {
            switch self {
            case .liveGames: "Live Games"
            case .watchlist: "Watchlist"
            case .both: "Live Games and Watchlist"
            case .off: "Off"
            }
        }

        var showsGames: Bool { self == .liveGames || self == .both }
        var showsWatchlist: Bool { self == .watchlist || self == .both }
    }

    public let id = FeatureID.live
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != oldValue { update() } }
    }
    public var section: Section {
        didSet { defaults.set(section.rawValue, forKey: Self.sectionKey) }
    }
    public var ticker: Ticker {
        didSet {
            defaults.set(ticker.rawValue, forKey: Self.tickerKey)
            update()
        }
    }
    /// The leagues the Scores section follows, in `League.allCases` order.
    public private(set) var leagues: [League] {
        didSet { defaults.set(leagues.map(\.rawValue), forKey: Self.leaguesKey) }
    }
    public private(set) var watchlist: [WatchItem] {
        didSet { defaults.set(try? JSONEncoder().encode(watchlist), forKey: Self.watchlistKey) }
    }
    /// The followed leagues' games, live first.
    public private(set) var games: [Game] = []
    /// The latest prices, by symbol.
    public private(set) var quotes: [String: Quote] = [:]
    public private(set) var scoresUpdated: Date?
    public private(set) var quotesUpdated: Date?
    /// Why the last reading failed, while nothing newer has worked.
    public private(set) var scoresProblem: String?
    public private(set) var quotesProblem: String?
    /// Set while a symbol typed into the watchlist is being looked up.
    public private(set) var isSearching = false
    /// Shows the ticker on the closed notch; nil once there's nothing to show.
    @ObservationIgnored public var onOngoing: ((Activity?) -> Void)?

    nonisolated static let foregroundInterval: TimeInterval = 30
    nonisolated static let tickerInterval: TimeInterval = 90
    nonisolated static let waitingInterval: TimeInterval = 600
    /// How long each item stays on the closed notch.
    nonisolated static let rotation: Duration = .seconds(5)
    /// Yahoo answers at most this many symbols at once.
    public nonisolated static let watchlistLimit = 20
    private static let sectionKey = "live.section"
    private static let tickerKey = "live.ticker"
    private static let leaguesKey = "live.leagues"
    private static let watchlistKey = "live.watchlist"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var rotate: Task<Void, Never>?
    @ObservationIgnored private var ongoing: Activity?
    @ObservationIgnored private var tickerIndex = 0
    /// After a "slow down", no reading of that kind before this.
    @ObservationIgnored private var scoresBackoff: Date?
    @ObservationIgnored private var quotesBackoff: Date?

    public convenience init() {
        self.init(defaults: .standard, fetch: LiveFeature.download)
    }

    init(defaults: UserDefaults, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.defaults = defaults
        self.fetch = fetch
        section = defaults.string(forKey: Self.sectionKey).flatMap(Section.init) ?? .scores
        ticker = defaults.string(forKey: Self.tickerKey).flatMap(Ticker.init) ?? .liveGames
        leagues =
            defaults.stringArray(forKey: Self.leaguesKey).map { $0.compactMap(League.init(rawValue:)) }
            ?? [.cricket, .premierLeague, .nba]
        watchlist =
            defaults.data(forKey: Self.watchlistKey).flatMap { try? JSONDecoder().decode([WatchItem].self, from: $0) }
            ?? WatchItem.defaults
    }

    public var view: some View { LiveView(live: self) }

    /// Live games first: what the closed notch and the tab lead with.
    public var liveGames: [Game] { games.filter { $0.state == .live } }

    // MARK: Choices

    public func follows(_ league: League) -> Bool { leagues.contains(league) }

    public func setFollows(_ league: League, _ follows: Bool) {
        var set = Set(leagues)
        if follows { set.insert(league) } else { set.remove(league) }
        leagues = League.allCases.filter(set.contains)
        games.removeAll { !set.contains($0.league) }
        if follows { refreshNow() }
    }

    public func remove(_ item: WatchItem) {
        watchlist.removeAll { $0.symbol == item.symbol }
        quotes[item.symbol] = nil
        showTicker()
    }

    public func move(_ item: WatchItem, by offset: Int) {
        guard let index = watchlist.firstIndex(of: item) else { return }
        let target = min(max(index + offset, 0), watchlist.count - 1)
        watchlist.move(fromOffsets: [index], toOffset: target > index ? target + 1 : target)
    }

    public func resetWatchlist() {
        watchlist = WatchItem.defaults
        quotes = [:]
        refreshNow()
    }

    /// Looks up what was typed, a symbol or a name, and adds the best match. Returns why it couldn't.
    @discardableResult
    public func add(_ query: String) async -> String? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        guard watchlist.count < Self.watchlistLimit else { return "The watchlist holds \(Self.watchlistLimit)." }
        isSearching = true
        defer { isSearching = false }
        do {
            let data = try await fetch(LiveData.searchURL(for: query))
            guard let item = try LiveData.match(from: data, query: query) else { return "Nothing found for “\(query)”." }
            guard !watchlist.contains(where: { $0.symbol == item.symbol }) else { return "\(item.symbol) is already here." }
            watchlist.append(item)
            await readQuotes()
            return nil
        } catch {
            return Self.describe(error)
        }
    }

    /// Reads everything now, as when the tab opens or a league is added.
    public func refreshNow() {
        guard phase != .stopped else { return }
        poll?.cancel()
        poll = Task { [weak self] in await self?.run(immediately: true) }
    }

    // MARK: Readings

    private func update() {
        guard phase != .stopped, phase == .foreground || ticker != .off else { return stop() }
        refreshNow()
        startRotation()
    }

    private func stop() {
        poll?.cancel()
        poll = nil
        rotate?.cancel()
        rotate = nil
        show(nil)
    }

    private func run(immediately: Bool) async {
        var first = immediately
        while !Task.isCancelled {
            if !first {
                let wait = nextWait
                do { try await Task.sleep(for: .seconds(wait), tolerance: .seconds(wait / 6)) } catch { return }
            }
            first = false
            let wantsScores = phase == .foreground || ticker.showsGames
            let wantsQuotes = phase == .foreground || ticker.showsWatchlist
            if wantsScores { await readScores() }
            if wantsQuotes { await readQuotes() }
            showTicker()
        }
    }

    /// Half a minute with the tab open; closed, often enough for what the ticker shows.
    private var nextWait: TimeInterval {
        Self.interval(phase: phase, ticker: ticker, anyLive: !liveGames.isEmpty)
    }

    nonisolated static func interval(phase: FeaturePhase, ticker: Ticker, anyLive: Bool) -> TimeInterval {
        if phase == .foreground { return foregroundInterval }
        if ticker.showsWatchlist || (ticker.showsGames && anyLive) { return tickerInterval }
        return waitingInterval
    }

    private func readScores() async {
        if let scoresBackoff, scoresBackoff > .now { return }
        let leagues = leagues
        let fetch = fetch
        var found: [Game] = []
        var problem: String?
        await withTaskGroup(of: Result<[Game], Error>.self) { group in
            for league in leagues {
                group.addTask {
                    do { return .success(try LiveData.games(from: try await fetch(league.url), league: league)) } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let games): found += games
                case .failure(let error): problem = Self.describe(error)
                }
            }
        }
        if problem != nil, found.isEmpty, !leagues.isEmpty {
            scoresProblem = problem
            scoresBackoff = Self.backoff(after: problem)
            return
        }
        games = LiveData.relevant(found)
        scoresProblem = nil
        scoresBackoff = nil
        scoresUpdated = .now
    }

    private func readQuotes() async {
        if let quotesBackoff, quotesBackoff > .now { return }
        let symbols = watchlist.map(\.symbol)
        guard !symbols.isEmpty else { return }
        do {
            let read = try LiveData.quotes(from: try await fetch(LiveData.sparkURL(for: symbols)))
            quotes.merge(read) { $1 }
            quotesProblem = nil
            quotesBackoff = nil
            quotesUpdated = .now
        } catch {
            quotesProblem = Self.describe(error)
            quotesBackoff = Self.backoff(after: quotesProblem)
        }
    }

    private static func backoff(after problem: String?) -> Date? {
        problem == LiveError.busy.description ? .now.addingTimeInterval(300) : nil
    }

    // MARK: Ticker

    private func startRotation() {
        rotate?.cancel()
        guard ticker != .off else { return show(nil) }
        rotate = Task { [weak self] in
            while !Task.isCancelled {
                self?.showTicker()
                do { try await Task.sleep(for: Self.rotation, tolerance: .milliseconds(500)) } catch { return }
                self?.tickerIndex += 1
            }
        }
    }

    /// What the ticker rotates through, in order.
    var tickerItems: [Activity] {
        var items: [Activity] = []
        if ticker.showsGames {
            items += liveGames.map {
                Activity(feature: .live, symbol: $0.league.symbol, title: $0.tickerTitle, duration: .zero)
            }
        }
        if ticker.showsWatchlist {
            items += watchlist.compactMap { item in
                quotes[item.symbol].map {
                    Activity(
                        feature: .live, symbol: $0.tickerSymbol, title: "\(item.displaySymbol) \($0.percentText)",
                        duration: .zero)
                }
            }
        }
        return items
    }

    private func showTicker() {
        guard phase != .stopped, ticker != .off else { return show(nil) }
        let items = tickerItems
        show(items.isEmpty ? nil : items[tickerIndex % items.count])
    }

    private func show(_ activity: Activity?) {
        guard activity != ongoing else { return }
        ongoing = activity
        onOngoing?(activity)
    }

    // MARK: Network

    /// A browser's user agent: Yahoo turns away requests that don't send one.
    nonisolated static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
                + "Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 429 { throw LiveError.busy }
        guard (200..<300).contains(status) else { throw LiveError.status(status) }
        return data
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let error = error as? LiveError { return error.description }
        if let error = error as? URLError {
            return error.code == .notConnectedToInternet ? "You're offline." : "Couldn't connect."
        }
        return "The service sent something unexpected."
    }
}

enum LiveError: Error, CustomStringConvertible {
    case busy
    case status(Int)

    var description: String {
        switch self {
        case .busy: "The service asked to slow down. Trying again in a few minutes."
        case .status(let code): "The service didn't answer (\(code))."
        }
    }
}
