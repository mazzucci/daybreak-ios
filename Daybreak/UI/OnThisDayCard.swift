import SwiftUI
import UIKit

/// One cheerful moment from today's date in history: its picture (when there's a good free one) across the top,
/// "1975 · 51 years ago", what happened, and the article's title as the link. Tapping opens the article; "Another"
/// (when the day has more than one pick) moves on to the next. The footer credits Wikipedia and, with a picture,
/// links the picture's page on Commons for its author and licence. Ported from Android's OnThisDayCard.
struct OnThisDayCard: View {
    let day: OnThisDayToday
    let pick: OnThisDayPick
    let onAnother: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if let url = URL(string: pick.url) { openURL(url) }
            } label: {
                content(pick)
                    .id(pick)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40)), removal: .opacity))
            }
            .buttonStyle(CardPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(OnThisDay.formatYear(pick.year)), \(OnThisDay.yearsAgo(pick.year, today: day.date)). \(pick.text) \(pick.title), on Wikipedia.")
            .accessibilityHint("Reads on Wikipedia")
            .accessibilityAddTraits(.isLink)
            footer
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .task(id: pick) { await prefetchNext() }
    }

    private func content(_ shown: OnThisDayPick) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let picture = shown.picture { PictureHero(picture: picture) }
            VStack(alignment: .leading, spacing: 0) {
                yearLine(shown)
                Spacer().frame(height: 6)
                Text(shown.text)
                    .font(.bodyLarge)
                    .foregroundStyle(Palette.onSurface)
                    .lineLimit(typeSize >= .xxxLarge ? 7 : 5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 10)
                HStack(spacing: 4) {
                    Text(shown.title).lineLimit(1)
                    Image(systemName: "arrow.up.forward.square").imageScale(.small)
                }
                .font(.labelLarge)
                .foregroundStyle(Palette.primary)
            }
            .padding([.horizontal, .top], 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    /// "1975 · 51 years ago": the year as the card's lead, how long ago quieter.
    private func yearLine(_ shown: OnThisDayPick) -> some View {
        (Text(OnThisDay.formatYear(shown.year)).font(.titleMedium).foregroundColor(Palette.onSurface)
            + Text("\u{00A0}· " + OnThisDay.yearsAgo(shown.year, today: day.date).replacingOccurrences(of: " ", with: "\u{00A0}"))
            .font(.bodyMedium).foregroundColor(Palette.onSurfaceVariant))
    }

    /// "From Wikipedia · CC BY-SA", "Picture" for the picture's page on Commons when there's one, and "Another" at
    /// the end of the line. At the largest text sizes the credit has a line of its own.
    private var footer: some View {
        let credit = Text("From Wikipedia · CC\u{00A0}BY-SA")
            .font(.labelMedium)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Palette.onSurfaceVariant)
            .accessibilityLabel("From Wikipedia, licensed CC BY-SA")
        let buttons = HStack(spacing: 0) {
            if let page = pick.picture?.filePage, let url = URL(string: page) {
                Button("Picture") { openURL(url) }
                    .font(.labelMedium)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Picture's source on Wikimedia Commons")
            }
            Spacer(minLength: 0)
            if let onAnother {
                Button("Another", action: onAnother)
                    .font(.labelLarge)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Another moment from this day")
            }
        }
        .tint(Palette.primary)
        return Group {
            if typeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 4) {
                    credit.padding(.horizontal, 16).padding(.top, 12)
                    buttons.padding(.leading, 8).padding(.trailing, 4)
                }
            } else {
                HStack(spacing: 0) {
                    credit.padding(.trailing, 4)
                    buttons
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 2)
    }

    /// The next pick's picture, once this one's is in, so "Another" shows it at once.
    private func prefetchNext() async {
        guard day.picks.count > 1 else { return }
        if let picture = pick.picture { _ = await ImageLoader.shared.load(picture.url, fallback: picture.fallbackUrl) }
        let next = day.picks[(day.picks.firstIndex(of: pick).map { $0 + 1 } ?? 0) % day.picks.count]
        if let picture = next.picture { _ = await ImageLoader.shared.load(picture.url, fallback: picture.fallbackUrl) }
    }
}

/// Dims the card a little while it's pressed, as a tappable card should.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The picture across the top of the card, 180 points tall at any width, so nothing moves when it lands: the slot is
/// in the skeleton tint until the picture fades in. A landscape photo fills it, top-biased so heads aren't cut off;
/// anything else is a "poster": shown whole, framed, over a blurred and dimmed copy of itself. Decorative.
private struct PictureHero: View {
    let picture: OnThisDayPicture
    @State private var image: UIImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Palette.skeleton
            if let image {
                Group {
                    if picture.fill { filled(image) } else { poster(image) }
                }
                .transition(.opacity)
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .task(id: picture.url) {
            if let cached = ImageLoader.shared.cached(picture.url) {
                image = cached
                return
            }
            image = nil
            let loaded = await ImageLoader.shared.load(picture.url, fallback: picture.fallbackUrl)
            withAnimation(.easeIn(duration: 0.3)) { image = loaded }
        }
    }

    private func filled(_ image: UIImage) -> some View {
        // Cropped to fill, a quarter of the way down rather than centred (Android's BiasAlignment(0, -0.5)).
        GeometryReader { proxy in
            let scale = max(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            Image(uiImage: image)
                .resizable()
                .frame(width: w, height: h)
                .offset(x: (proxy.size.width - w) / 2, y: (proxy.size.height - h) * 0.25)
        }
        .clipped()
    }

    private func poster(_ image: UIImage) -> some View {
        ZStack {
            Color.clear.overlay {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: 24, opaque: true)
            }
            .clipped()
            Palette.surfaceContainer.opacity(scheme == .dark ? 0.55 : 0.40)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.outlineVariant, lineWidth: 1))
                .padding(16)
        }
    }
}
