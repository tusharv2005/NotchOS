// SPDX-License-Identifier: MIT
import SwiftUI

/// Gains in green and losses in red, bright enough to read on black.
enum LiveTint {
    static let up = Color(red: 0.2, green: 0.83, blue: 0.47)
    static let down = Color(red: 1, green: 0.36, blue: 0.36)
    static let live = Color(red: 1, green: 0.27, blue: 0.27)

    static func change(_ value: Double) -> Color { value > 0 ? up : value < 0 ? down : .white.opacity(0.6) }
}

/// The Live tab: Scores, the followed leagues' games as cards, live ones first, and Markets, the
/// watchlist as cards with today's chart. Both scroll sideways; a short notch keeps the numbers and
/// drops the extras.
struct LiveView: View {
    @Bindable var live: LiveFeature

    var body: some View {
        VStack(spacing: 8) {
            header
            GeometryReader { proxy in
                let compact = proxy.size.height < 104
                Group {
                    switch live.section {
                    case .scores: ScoresSection(live: live, compact: compact)
                    case .markets: MarketsSection(live: live, compact: compact)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 4) {
            ForEach(LiveFeature.Section.allCases) { section in
                Button {
                    live.section = section
                } label: {
                    HStack(spacing: 4) {
                        Text(section.title)
                        if section == .scores, !live.liveGames.isEmpty {
                            Circle().fill(LiveTint.live).frame(width: 5, height: 5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(live.section == section ? .white.opacity(0.16) : .clear, in: Capsule())
                .accessibilityAddTraits(live.section == section ? .isSelected : [])
            }
            Spacer(minLength: 6)
            if live.section == .scores {
                Menu {
                    ForEach(League.allCases) { league in
                        Toggle(
                            isOn: Binding(get: { live.follows(league) }, set: { live.setFollows(league, $0) })
                        ) {
                            Label(league.title, systemImage: league.symbol)
                        }
                    }
                } label: {
                    HeaderButton(symbol: "line.3.horizontal.decrease")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Leagues to follow")
                .accessibilityLabel("Leagues")
            }
            Menu {
                Picker("Show in the Closed Notch", selection: $live.ticker) {
                    ForEach(LiveFeature.Ticker.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HeaderButton(
                    symbol: live.ticker == .off ? "rectangle.slash" : "rectangle.inset.topright.filled",
                    lit: live.ticker != .off)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("What the closed notch shows")
            .accessibilityLabel("Closed notch ticker")
        }
    }
}

private struct HeaderButton: View {
    let symbol: String
    var lit = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(lit ? .white : .white.opacity(0.6))
            .frame(width: 24, height: 22)
            .background(.white.opacity(lit ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Cards like the Network and AI Usage tiles: a faint tint from the top corner and a hairline edge.
private struct Card: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(0.18), .white.opacity(0.03)], startPoint: .topLeading,
                        endPoint: .bottomTrailing))
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.08)))
    }
}

/// A row of cards that scrolls sideways, fading at its ends.
private struct CardRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, 2)
        }
        .fadingEdges(.horizontal, length: 10)
    }
}

/// Says why a section is empty, with an update time when there is one.
private struct EmptyNote: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).opacity(0.7)
            Text(title).font(.callout.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Scores

private struct ScoresSection: View {
    let live: LiveFeature
    let compact: Bool

    var body: some View {
        if live.games.isEmpty {
            if live.leagues.isEmpty {
                EmptyNote(
                    symbol: "sportscourt", title: "No leagues followed",
                    message: "Pick the leagues to follow from the filter button above.")
            } else if let problem = live.scoresProblem {
                EmptyNote(symbol: "wifi.exclamationmark", title: "Scores unavailable", message: problem)
            } else if live.scoresUpdated == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(
                    symbol: "calendar.badge.clock", title: "No games right now",
                    message: "Nothing on in \(ListFormatter.localizedString(byJoining: live.leagues.map(\.title))) "
                        + "today or tomorrow.")
            }
        } else {
            CardRow {
                ForEach(live.games) { GameCard(game: $0, compact: compact) }
            }
        }
    }
}

private struct GameCard: View {
    let game: Game
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            HStack(spacing: 4) {
                Image(systemName: game.league.symbol).font(.system(size: 8, weight: .bold))
                Text(game.league.short).tracking(0.5)
                Spacer(minLength: 4)
                status
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            side(game.first)
            side(game.second)
            if !compact, game.state != .upcoming {
                Text(game.detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(compact ? 8 : 10)
        .frame(width: game.league == .cricket ? 176 : 148, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(Card(tint: game.state == .live ? LiveTint.live : .white))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder private var status: some View {
        switch game.state {
        case .live:
            HStack(spacing: 3) {
                Circle().fill(LiveTint.live).frame(width: 5, height: 5)
                Text("LIVE").foregroundStyle(LiveTint.live)
            }
        case .final:
            Text("FINAL")
        case .upcoming:
            Text(Self.when(game.start)).textCase(.uppercase)
        }
    }

    private func side(_ side: Game.Side) -> some View {
        let dimmed = game.state == .final && !side.isWinner && (game.first.isWinner || game.second.isWinner)
        return HStack(spacing: 6) {
            TeamLogo(url: side.logo, abbreviation: side.abbreviation, size: compact ? 16 : 20)
            Text(side.abbreviation)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if let score = side.score {
                Text(game.league == .cricket ? Game.cricketRuns(score) : score)
                    .font(.system(size: compact ? 14 : 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
        }
        .opacity(dimmed ? 0.5 : 1)
    }

    /// "7:30 PM" today, "Tomorrow" or a weekday after.
    static func when(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tmrw " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var spoken: String {
        let teams = "\(game.first.name) \(game.first.score ?? "") versus \(game.second.name) \(game.second.score ?? "")"
        switch game.state {
        case .live: return "Live, \(game.league.title): \(teams), \(game.detail)"
        case .final: return "Final, \(game.league.title): \(teams)"
        case .upcoming: return "\(game.league.title): \(game.first.name) versus \(game.second.name), \(Self.when(game.start))"
        }
    }
}

/// A team's crest from ESPN, or its initials in a circle while it loads or where there's none.
private struct TeamLogo: View {
    let url: URL?
    let abbreviation: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Circle()
                    .fill(.white.opacity(0.12))
                    .overlay(
                        Text(abbreviation.prefix(1))
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Markets

private struct MarketsSection: View {
    let live: LiveFeature
    let compact: Bool

    var body: some View {
        if live.watchlist.isEmpty {
            HStack {
                EmptyNote(
                    symbol: "chart.line.uptrend.xyaxis", title: "Your watchlist is empty",
                    message: "Add a stock, index, or coin: try AAPL, RELIANCE.NS, ^NSEI, or BTC-USD.")
                AddCard(live: live, compact: compact)
            }
        } else {
            VStack(spacing: 4) {
                CardRow {
                    ForEach(live.watchlist) { item in
                        QuoteCard(item: item, quote: live.quotes[item.symbol], compact: compact)
                            .contextMenu {
                                Button("Move Left") { live.move(item, by: -1) }
                                    .disabled(live.watchlist.first == item)
                                Button("Move Right") { live.move(item, by: 1) }
                                    .disabled(live.watchlist.last == item)
                                Divider()
                                Button("Remove \(item.displaySymbol)", role: .destructive) { live.remove(item) }
                            }
                    }
                    if live.watchlist.count < LiveFeature.watchlistLimit {
                        AddCard(live: live, compact: compact)
                    }
                }
                if let problem = live.quotesProblem {
                    Text(problem)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct QuoteCard: View {
    let item: WatchItem
    let quote: Quote?
    let compact: Bool

    var body: some View {
        let change = quote?.change ?? 0
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.displaySymbol)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let quote {
                    Text(quote.percentText)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LiveTint.change(change))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(LiveTint.change(change).opacity(0.16), in: Capsule())
                }
            }
            if !compact {
                Text(item.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            if let quote {
                Text(LiveData.price(quote.price, currency: item.currency))
                    .font(.system(size: compact ? 15 : 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                QuoteSparkline(closes: quote.closes, baseline: quote.previousClose, color: LiveTint.change(change))
                    .padding(.top, compact ? 0 : 2)
            } else {
                Text("—")
                    .font(.system(size: compact ? 15 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? 8 : 10)
        .frame(width: 132, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(Card(tint: quote.map { LiveTint.change($0.change) } ?? .white))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(
            quote.map { "\(LiveData.price($0.price, currency: item.currency)), \($0.percentText) today" } ?? "Loading")
    }
}

/// Today's prices as a line over a soft fill, with the previous close dotted across for reference.
private struct QuoteSparkline: View {
    let closes: [Double]
    let baseline: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let values = closes + [baseline]
            if closes.count > 1, let low = values.min(), let high = values.max() {
                let span = max(high - low, abs(high) * 0.0001, .ulpOfOne)
                let size = proxy.size
                let point = { (index: Int, value: Double) in
                    CGPoint(
                        x: size.width * CGFloat(index) / CGFloat(closes.count - 1),
                        y: size.height * (1 - CGFloat((value - low) / span)))
                }
                let line = Path { path in
                    for (index, value) in closes.enumerated() {
                        if index == 0 { path.move(to: point(index, value)) } else { path.addLine(to: point(index, value)) }
                    }
                }
                let base = size.height * (1 - CGFloat((baseline - low) / span))
                ZStack {
                    Path { path in
                        path.addPath(line)
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.addLine(to: CGPoint(x: 0, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: base))
                        path.addLine(to: CGPoint(x: size.width, y: base))
                    }
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    line.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(minHeight: 14)
        .accessibilityHidden(true)
    }
}

/// The last card: a plus that becomes a field for a symbol or a name.
private struct AddCard: View {
    let live: LiveFeature
    let compact: Bool
    @State private var adding = false
    @State private var query = ""
    @State private var problem: String?

    var body: some View {
        Group {
            if adding {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add to watchlist")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("AAPL, Tesla, BTC-USD", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .takesKeyboard(adding)
                        .onSubmit(submit)
                        .onExitCommand { close() }
                    if live.isSearching {
                        ProgressView().controlSize(.mini)
                    } else if let problem {
                        Text(problem)
                            .font(.system(size: 9.5))
                            .foregroundStyle(LiveTint.down)
                            .lineLimit(compact ? 1 : 2)
                    } else if !compact {
                        Text("Return to add, Esc to cancel")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(compact ? 8 : 10)
            } else {
                Button {
                    adding = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                        Text("Add").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to watchlist")
            }
        }
        .frame(width: adding ? 160 : 72, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(Card(tint: .white))
    }

    private func submit() {
        let text = query
        problem = nil
        Task {
            if let failure = await live.add(text) {
                problem = failure
            } else {
                close()
            }
        }
    }

    private func close() {
        adding = false
        query = ""
        problem = nil
    }
}
