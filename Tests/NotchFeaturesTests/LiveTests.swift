// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Testing

@testable import NotchFeatures

@MainActor
struct LiveTests {
    private let defaults = UserDefaults(suiteName: "Live.\(UUID().uuidString)")!

    /// Trimmed from ESPN's Premier League scoreboard: one game on, one finished, one tomorrow.
    nonisolated static let soccer = Data(
        """
        {"events":[
          {"id":"1","date":"2026-10-17T14:00Z","competitions":[{"status":{"type":{"state":"in","shortDetail":"67'"}},
            "competitors":[
              {"homeAway":"home","score":"1","team":{"abbreviation":"BRE","shortDisplayName":"Brentford"}},
              {"homeAway":"away","score":"2","team":{"abbreviation":"LIV","shortDisplayName":"Liverpool",
                "logo":"https://a.espncdn.com/liv.png"}}]}]},
          {"id":"2","date":"2026-10-17T11:30Z","competitions":[{"status":{"type":{"state":"post","shortDetail":"FT"}},
            "competitors":[
              {"homeAway":"home","score":"0","team":{"abbreviation":"EVE"}},
              {"homeAway":"away","score":"2","winner":true,"team":{"abbreviation":"CHE"}}]}]},
          {"id":"3","date":"2026-10-18T15:30Z","competitions":[{"status":{"type":{"state":"pre","shortDetail":"Sun"}},
            "competitors":[
              {"homeAway":"home","score":"0","team":{"abbreviation":"ARS"}},
              {"homeAway":"away","score":"0","team":{"abbreviation":"MCI"}}]}]}
        ]}
        """.utf8)

    /// Trimmed from ESPN's cricket score panel, whose competitors have no home or away.
    nonisolated static let cricket = Data(
        """
        {"scores":[{"events":[
          {"id":"9","date":"2026-10-17T05:30Z","competitions":[{"status":{"type":{"state":"in","shortDetail":"Live"}},
            "competitors":[
              {"score":"256","team":{"abbreviation":"CAN","displayName":"Canada"}},
              {"score":"232/7 (46/50 ov, target 257)","team":{"abbreviation":"NEP","displayName":"Nepal"}}]}]}
        ]}]}
        """.utf8)

    nonisolated static let spark = Data(
        """
        {"AAPL":{"symbol":"AAPL","previousClose":342.0,"chartPreviousClose":342.0,"fulldayPrice":343.46,
                 "close":[343.6,null,344.8,343.46]},
         "BTC-USD":{"symbol":"BTC-USD","chartPreviousClose":81501.61,"close":[81518.3,81457.08,81182.12]},
         "GONE":{"symbol":"GONE","close":[]}}
        """.utf8)

    @Test func scoresReadAwayFirstWithoutScoresBeforeKickoff() throws {
        let games = try LiveData.games(from: Self.soccer, league: .premierLeague)
        #expect(games.count == 3)
        let live = try #require(games.first { $0.state == .live })
        #expect(live.first.abbreviation == "LIV" && live.second.abbreviation == "BRE", "away first")
        #expect(live.tickerTitle == "LIV 2\u{2013}1 BRE")
        #expect(live.first.logo == URL(string: "https://a.espncdn.com/liv.png"))
        #expect(live.detail == "67'")
        let upcoming = try #require(games.first { $0.state == .upcoming })
        #expect(upcoming.first.score == nil && upcoming.second.score == nil)
        #expect(games.first { $0.state == .final }?.first.isWinner == true)
    }

    @Test func cricketShowsTheSideBattingNow() throws {
        let game = try #require(try LiveData.games(from: Self.cricket, league: .cricket).first)
        #expect(game.first.abbreviation == "CAN", "the order ESPN gives")
        #expect(game.tickerTitle == "NEP 232/7")
        #expect(Game.cricketRuns("417/8d & 8/1 (3 ov)") == "8/1")
        #expect(Game.cricketRuns("256") == "256")
    }

    @Test func liveGamesComeFirstThenUpcomingThenRecentResults() throws {
        let now = try #require(LiveData.date("2026-10-17T15:00Z"))
        var games = try LiveData.games(from: Self.soccer, league: .premierLeague)
        var old = games[1]
        old.id = "old"
        old.start = now.addingTimeInterval(-3 * 24 * 3600)
        games.append(old)
        let listed = LiveData.relevant(games, now: now)
        #expect(listed.map(\.state) == [.live, .upcoming, .final])
        #expect(!listed.contains { $0.id == "old" }, "results older than a day and a half drop off")
    }

    @Test func espnDatesWithoutSeconds() {
        #expect(LiveData.date("2026-10-17T11:30Z") != nil)
        #expect(LiveData.date("2026-10-17T11:30:00Z") != nil)
        #expect(LiveData.date("tomorrow") == nil)
    }

    @Test func quotesTakeTheDaysPriceAndSkipGaps() throws {
        let quotes = try LiveData.quotes(from: Self.spark)
        #expect(quotes.count == 2, "a symbol without prices is left out")
        let apple = try #require(quotes["AAPL"])
        #expect(apple.price == 343.46 && apple.closes.count == 3)
        #expect(apple.percentText == "+0.43%")
        #expect(apple.tickerSymbol == "arrowtriangle.up.fill")
        let bitcoin = try #require(quotes["BTC-USD"])
        #expect(bitcoin.price == 81182.12, "the last close when there's no day price")
        #expect(bitcoin.percentText == "\u{2212}0.39%")
    }

    @Test func searchPrefersTheExactSymbol() throws {
        let data = Data(
            """
            {"quotes":[{"symbol":"RELIANCE.BO","shortname":"RELIANCE IND"},{"symbol":"RELIANCE.NS","shortname":"Reliance"},
                       {"shortname":"no symbol"}]}
            """.utf8)
        #expect(try LiveData.match(from: data, query: "reliance.ns")?.symbol == "RELIANCE.NS")
        let first = try LiveData.match(from: data, query: "reliance")
        #expect(first?.symbol == "RELIANCE.BO" && first?.currency == "INR")
        #expect(try LiveData.match(from: Data(#"{"quotes":[]}"#.utf8), query: "zzz") == nil)
    }

    @Test func symbolsReadTheWayPeopleSayThem() {
        #expect(WatchItem(symbol: "^NSEI", name: "").displaySymbol == "NIFTY")
        #expect(WatchItem(symbol: "BTC-USD", name: "").displaySymbol == "BTC")
        #expect(WatchItem(symbol: "RELIANCE.NS", name: "").displaySymbol == "RELIANCE")
        #expect(WatchItem(symbol: "^VIX", name: "").displaySymbol == "VIX")
        #expect(LiveData.currency(for: "TCS.NS") == "INR")
        #expect(LiveData.currency(for: "TSLA") == "USD")
        #expect(LiveData.currency(for: "^VIX") == nil)
        let us = Locale(identifier: "en_US")
        #expect(LiveData.price(343.456, currency: "USD", locale: us) == "$343.46")
        #expect(LiveData.price(0.18342, locale: us) == "0.1834")
        #expect(LiveData.price(123_456.7, currency: "INR", locale: us) == "₹123,457")
        #expect(LiveData.price(123_456.7, currency: "INR", locale: Locale(identifier: "en_IN")) == "₹1,23,457")
    }

    @Test func readsOnlyAsOftenAsWhatsShowingNeeds() {
        #expect(LiveFeature.interval(phase: .foreground, ticker: .off, anyLive: false) == 30)
        #expect(LiveFeature.interval(phase: .background, ticker: .watchlist, anyLive: false) == 90)
        #expect(LiveFeature.interval(phase: .background, ticker: .liveGames, anyLive: true) == 90)
        #expect(LiveFeature.interval(phase: .background, ticker: .liveGames, anyLive: false) == 600)
    }

    /// With the ticker on, the closed notch shows the live game and the watchlist, one at a time, and
    /// nothing once the notch stops.
    @Test func theTickerShowsLiveGamesAndTheWatchlist() async throws {
        let live = LiveFeature(defaults: defaults) { url in
            if url.host() == "query1.finance.yahoo.com" { return Self.spark }
            return url.path().contains("eng.1") ? Self.soccer : Data(#"{"events":[]}"#.utf8)
        }
        live.setFollows(.cricket, false)
        live.setFollows(.nba, false)
        live.ticker = .both
        var shown: [Activity?] = []
        live.onOngoing = { shown.append($0) }
        live.phase = .background
        try await waitUntil { live.quotesUpdated != nil && live.scoresUpdated != nil }
        #expect(live.liveGames.map(\.tickerTitle) == ["LIV 2\u{2013}1 BRE"])
        let titles = live.tickerItems.map(\.title)
        #expect(titles.first == "LIV 2\u{2013}1 BRE")
        #expect(titles.contains("AAPL +0.43%") && titles.contains("BTC \u{2212}0.39%"))
        #expect(live.tickerItems.allSatisfy { $0.feature == .live })
        #expect(shown.last??.feature == .live)
        live.phase = .stopped
        #expect(shown.last == .some(nil))
    }

    @Test func choicesAreRemembered() {
        let first = LiveFeature(defaults: defaults) { _ in Data() }
        first.ticker = .watchlist
        first.setFollows(.nfl, true)
        first.remove(WatchItem.defaults[0])
        let second = LiveFeature(defaults: defaults) { _ in Data() }
        #expect(second.ticker == .watchlist)
        #expect(second.follows(.nfl) && second.follows(.cricket))
        #expect(second.watchlist.count == WatchItem.defaults.count - 1)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}
