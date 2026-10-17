// SPDX-License-Identifier: MIT
import Foundation

/// A league the Scores section can follow, read from ESPN's public scoreboards.
public enum League: String, CaseIterable, Identifiable, Codable, Sendable {
    case cricket, premierLeague, laLiga, championsLeague, mls, nba, nfl, mlb, nhl

    public var id: Self { self }

    public var title: String {
        switch self {
        case .cricket: "Cricket"
        case .premierLeague: "Premier League"
        case .laLiga: "LaLiga"
        case .championsLeague: "Champions League"
        case .mls: "MLS"
        case .nba: "NBA"
        case .nfl: "NFL"
        case .mlb: "MLB"
        case .nhl: "NHL"
        }
    }

    /// A few letters, for a game card's corner.
    public var short: String {
        switch self {
        case .cricket: "CRICKET"
        case .premierLeague: "EPL"
        case .laLiga: "LALIGA"
        case .championsLeague: "UCL"
        case .mls: "MLS"
        case .nba: "NBA"
        case .nfl: "NFL"
        case .mlb: "MLB"
        case .nhl: "NHL"
        }
    }

    /// SF Symbol for the sport. Every name exists on macOS 14.6, the oldest supported.
    public var symbol: String {
        switch self {
        case .cricket: "figure.cricket"
        case .premierLeague, .laLiga, .championsLeague, .mls: "soccerball"
        case .nba: "basketball.fill"
        case .nfl: "football.fill"
        case .mlb: "baseball.fill"
        case .nhl: "hockey.puck.fill"
        }
    }

    /// Cricket has no single league: its score panel lists every match ESPN covers today.
    public var url: URL {
        let base = "https://site.api.espn.com/apis/site/v2/sports/"
        let path =
            switch self {
            case .cricket: "cricket/scorepanel"
            case .premierLeague: "soccer/eng.1/scoreboard"
            case .laLiga: "soccer/esp.1/scoreboard"
            case .championsLeague: "soccer/uefa.champions/scoreboard"
            case .mls: "soccer/usa.1/scoreboard"
            case .nba: "basketball/nba/scoreboard"
            case .nfl: "football/nfl/scoreboard"
            case .mlb: "baseball/mlb/scoreboard"
            case .nhl: "hockey/nhl/scoreboard"
            }
        return URL(string: base + path)!
    }
}

/// One match or game, live, coming up, or just finished.
public struct Game: Identifiable, Hashable, Sendable {
    public enum State: Int, Comparable, Sendable {
        // Ordered as the Scores section lists them: live first.
        case live, upcoming, final

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Side: Hashable, Sendable {
        public var abbreviation: String
        public var name: String
        /// Nil before the game starts.
        public var score: String?
        public var logo: URL?
        public var isWinner: Bool
    }

    public var id: String
    public var league: League
    public var start: Date
    public var state: State
    /// ESPN's word on where it stands: "Q3 5:12", "45'", "FT", "Stumps".
    public var detail: String
    /// Listed first: the away side, or the first side named when there's no home and away.
    public var first: Side
    public var second: Side

    /// The closed notch's line: "CHE 2–0 EVE" for most sports; cricket's scores are too long for
    /// both, so it shows the side batting now, "NEP 232/7".
    public var tickerTitle: String {
        if league == .cricket {
            let batting = [second, first].first { $0.score?.contains("ov") == true } ?? second
            return "\(batting.abbreviation) \(Self.cricketRuns(batting.score ?? "–"))"
        }
        return "\(first.abbreviation) \(first.score ?? "0")\u{2013}\(second.score ?? "0") \(second.abbreviation)"
    }

    /// "232 (46/50 ov, target 257)" → "232", and "417/8d & 8/1 (3 ov)" → "8/1": the innings in progress.
    static func cricketRuns(_ score: String) -> String {
        let innings = score.components(separatedBy: "&").last ?? score
        let runs = innings.split(separator: "(").first.map(String.init) ?? innings
        return runs.trimmingCharacters(in: .whitespaces)
    }
}

/// A stock, index, fund, or coin on the watchlist.
public struct WatchItem: Identifiable, Hashable, Codable, Sendable {
    /// Yahoo Finance's symbol: "AAPL", "RELIANCE.NS", "^NSEI", "BTC-USD".
    public var symbol: String
    public var name: String
    /// ISO code, such as "USD" or "INR", when known.
    public var currency: String?

    public var id: String { symbol }

    public init(symbol: String, name: String, currency: String? = nil) {
        self.symbol = symbol
        self.name = name
        self.currency = currency
    }

    /// Indices by the names people use, and other symbols without their exchange or currency suffix.
    public var displaySymbol: String {
        let known = [
            "^NSEI": "NIFTY", "^BSESN": "SENSEX", "^NSEBANK": "BANKNIFTY", "^GSPC": "S&P 500", "^IXIC": "NASDAQ",
            "^DJI": "DOW", "^FTSE": "FTSE", "^N225": "NIKKEI",
        ]
        if let name = known[symbol] { return name }
        var text = symbol.hasPrefix("^") ? String(symbol.dropFirst()) : symbol
        for suffix in ["-USD", ".NS", ".BO"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        return text
    }

    public static let defaults: [WatchItem] = [
        WatchItem(symbol: "^NSEI", name: "Nifty 50", currency: "INR"),
        WatchItem(symbol: "^GSPC", name: "S&P 500", currency: "USD"),
        WatchItem(symbol: "AAPL", name: "Apple", currency: "USD"),
        WatchItem(symbol: "NVDA", name: "NVIDIA", currency: "USD"),
        WatchItem(symbol: "BTC-USD", name: "Bitcoin", currency: "USD"),
        WatchItem(symbol: "ETH-USD", name: "Ethereum", currency: "USD"),
    ]
}

/// A watchlist item's price now, and the day so far.
public struct Quote: Hashable, Sendable {
    public var symbol: String
    public var price: Double
    public var previousClose: Double
    /// Today's prices, oldest first, for the sparkline.
    public var closes: [Double]

    public var change: Double { price - previousClose }
    public var changePercent: Double { previousClose == 0 ? 0 : change / previousClose * 100 }

    /// "+0.42%", "−1.30%".
    public var percentText: String {
        let sign = change >= 0 ? "+" : "\u{2212}"
        return sign + String(format: "%.2f%%", abs(changePercent))
    }

    public var tickerSymbol: String {
        change > 0 ? "arrowtriangle.up.fill" : change < 0 ? "arrowtriangle.down.fill" : "minus"
    }
}

/// Parsing and formatting, apart from the feature so tests can feed it saved responses.
public enum LiveData {
    // MARK: ESPN

    /// The games in a league's scoreboard, or in cricket's score panel.
    public static func games(from data: Data, league: League) throws -> [Game] {
        let decoder = JSONDecoder()
        let events: [ESPN.Event] =
            if league == .cricket {
                try decoder.decode(ESPN.ScorePanel.self, from: data).scores?.flatMap { $0.events ?? [] } ?? []
            } else {
                try decoder.decode(ESPN.Scoreboard.self, from: data).events ?? []
            }
        return events.compactMap { game(from: $0, league: league) }
    }

    static func game(from event: ESPN.Event, league: League) -> Game? {
        guard let competition = event.competitions?.first, let competitors = competition.competitors,
            competitors.count == 2, let start = date(event.date)
        else { return nil }
        let status = (competition.status ?? event.status)?.type
        let state: Game.State =
            switch status?.state {
            case "in": .live
            case "post": .final
            default: .upcoming
            }
        // Away first, the way scores are read out in the US; otherwise the order ESPN gives.
        let ordered =
            competitors.contains { $0.homeAway == "away" }
            ? competitors.sorted { ($0.homeAway == "away" ? 0 : 1) < ($1.homeAway == "away" ? 0 : 1) } : competitors
        let sides = ordered.map { competitor in
            Game.Side(
                abbreviation: competitor.team?.abbreviation ?? String((competitor.team?.displayName ?? "?").prefix(3)),
                name: competitor.team?.shortDisplayName ?? competitor.team?.displayName ?? "",
                score: state == .upcoming ? nil : competitor.score?.text.nilIfEmpty,
                logo: (competitor.team?.logo).flatMap(URL.init(string:)),
                isWinner: competitor.winner ?? false)
        }
        return Game(
            id: "\(league.rawValue)-\(event.id)", league: league, start: start, state: state,
            detail: status?.shortDetail ?? status?.detail ?? "", first: sides[0], second: sides[1])
    }

    /// ESPN leaves the seconds out: "2026-10-17T11:30Z".
    static func date(_ text: String?) -> Date? {
        guard var text else { return nil }
        if text.count == 17, text.hasSuffix("Z") { text.insert(contentsOf: ":00", at: text.index(before: text.endIndex)) }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    /// What the Scores section lists: live games, then today's and tomorrow's, then what finished
    /// in the last day and a half, newest first.
    public static func relevant(_ games: [Game], now: Date = .now) -> [Game] {
        games
            .filter { game in
                switch game.state {
                case .live: true
                case .upcoming: game.start < now.addingTimeInterval(48 * 3600)
                case .final: game.start > now.addingTimeInterval(-36 * 3600)
                }
            }
            .sorted { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state < rhs.state }
                return lhs.state == .final ? lhs.start > rhs.start : lhs.start < rhs.start
            }
    }

    // MARK: Yahoo Finance

    /// One request for the whole watchlist's prices and today's chart.
    public static func sparkURL(for symbols: [String]) -> URL {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/spark")!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
            URLQueryItem(name: "range", value: "1d"), URLQueryItem(name: "interval", value: "15m"),
        ]
        return components.url!
    }

    public static func quotes(from data: Data) throws -> [String: Quote] {
        let entries = try JSONDecoder().decode([String: Yahoo.Spark].self, from: data)
        var quotes: [String: Quote] = [:]
        for (symbol, entry) in entries {
            let closes = (entry.close ?? []).compactMap { $0 }
            guard let price = entry.fulldayPrice ?? closes.last,
                let previous = entry.chartPreviousClose ?? entry.previousClose
            else { continue }
            quotes[symbol] = Quote(symbol: symbol, price: price, previousClose: previous, closes: closes)
        }
        return quotes
    }

    public static func searchURL(for query: String) -> URL {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "quotesCount", value: "6"),
            URLQueryItem(name: "newsCount", value: "0"),
        ]
        return components.url!
    }

    /// The best match for what was typed: the symbol itself when it's listed, otherwise the first result.
    public static func match(from data: Data, query: String) throws -> WatchItem? {
        let results = try JSONDecoder().decode(Yahoo.Search.self, from: data).quotes ?? []
        let wanted = query.trimmingCharacters(in: .whitespaces).uppercased()
        let listed = results.filter { $0.symbol != nil }
        guard let best = listed.first(where: { $0.symbol?.uppercased() == wanted }) ?? listed.first,
            let symbol = best.symbol
        else { return nil }
        return WatchItem(symbol: symbol, name: best.shortname ?? best.longname ?? symbol, currency: currency(for: symbol))
    }

    /// The currency a symbol trades in, from its exchange suffix; a plain symbol is a US listing.
    static func currency(for symbol: String) -> String? {
        let suffixes: [(String, String)] = [
            (".NS", "INR"), (".BO", "INR"), ("-USD", "USD"), ("-INR", "INR"), ("-EUR", "EUR"), (".L", "GBP"),
            (".T", "JPY"), (".DE", "EUR"), (".PA", "EUR"), (".AS", "EUR"),
        ]
        if let match = suffixes.first(where: { symbol.hasSuffix($0.0) }) { return match.1 }
        if ["^NSEI", "^BSESN", "^NSEBANK"].contains(symbol) { return "INR" }
        return symbol.contains(".") || symbol.hasPrefix("^") ? nil : "USD"
    }

    // MARK: Formatting

    /// Two decimals, grouped, with fewer for big numbers and more for tiny ones: "81,182", "343.46", "0.1834".
    public static func price(_ value: Double, currency: String? = nil, locale: Locale = .current) -> String {
        let digits = abs(value) >= 100_000 ? 0 : abs(value) < 1 ? 4 : 2
        let number = value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        let symbols = ["USD": "$", "INR": "₹", "EUR": "€", "GBP": "£", "JPY": "¥"]
        return (currency.flatMap { symbols[$0] } ?? "") + number
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: Wire formats

/// The parts of ESPN's scoreboard JSON the Scores section reads.
enum ESPN {
    struct Scoreboard: Decodable { var events: [Event]? }
    struct ScorePanel: Decodable { var scores: [Scoreboard]? }

    struct Event: Decodable {
        var id: String
        var date: String?
        var status: Status?
        var competitions: [Competition]?
    }

    struct Competition: Decodable {
        var competitors: [Competitor]?
        var status: Status?
    }

    struct Competitor: Decodable {
        var homeAway: String?
        var score: Score?
        var winner: Bool?
        var team: Team?
    }

    struct Team: Decodable {
        var abbreviation: String?
        var displayName: String?
        var shortDisplayName: String?
        var logo: String?
    }

    struct Status: Decodable { var type: StatusType? }

    struct StatusType: Decodable {
        var state: String?
        var detail: String?
        var shortDetail: String?
    }

    /// A score is usually a string, but some feeds send a number or an object with a display value.
    struct Score: Decodable {
        var text: String

        private struct Object: Decodable { var displayValue: String? }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                text = string
            } else if let number = try? container.decode(Double.self) {
                text = number.formatted(.number.precision(.fractionLength(0...1)))
            } else {
                text = (try? container.decode(Object.self))?.displayValue ?? ""
            }
        }
    }
}

/// The parts of Yahoo Finance's JSON the Markets section reads.
enum Yahoo {
    struct Spark: Decodable {
        var close: [Double?]?
        var previousClose: Double?
        var chartPreviousClose: Double?
        var fulldayPrice: Double?
    }

    struct Search: Decodable { var quotes: [Result]? }

    struct Result: Decodable {
        var symbol: String?
        var shortname: String?
        var longname: String?
    }
}
