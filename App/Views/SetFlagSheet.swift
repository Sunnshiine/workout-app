import SwiftUI

/// The flag waits in the queue as a Set Log does, so the sheet closes before it lands and the card
/// says where it stands from there.
struct SetFlagSheet: View {
    let presentation: SetFlagSheetPresentation
    let onRaise: (SetFlag) -> Void
    @Environment(\.themePalette) private var palette
    @State private var draft: SetFlagDraft
    @State private var typedWords: String
    @FocusState private var isWordsFocused: Bool
    @AccessibilityFocusState private var isTitleFocused: Bool

    private static let chipHeight: CGFloat = 56
    private static let chipSpacing: CGFloat = 10
    private static let footFade: CGFloat = 40
    private static let raiseButtonID = "set-flag-raise-button"

    init(presentation: SetFlagSheetPresentation, draft: SetFlagDraft, onRaise: @escaping (SetFlag) -> Void) {
        self.presentation = presentation
        self.onRaise = onRaise
        _draft = State(initialValue: draft)
        _typedWords = State(initialValue: draft.words)
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    kinds
                    wordsField
                    raiseButton
                        .id(Self.raiseButtonID)
                    if !presentation.raisedFlags.isEmpty {
                        raisedFlags
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.bottom, Self.footFade, for: .scrollContent)
            .mask { footFadeMask }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(.rect)
            .onTapGesture { isWordsFocused = false }
            // A long name at the largest text can put the capsule in the foot's fade as the sheet opens or
            // the keyboard closes, or behind the keyboard as the words grow.
            .onAppear { scroll.scrollTo(Self.raiseButtonID, anchor: .bottom) }
            .onChange(of: draft.words) { scroll.scrollTo(Self.raiseButtonID, anchor: .bottom) }
            .onChange(of: isWordsFocused) { scroll.scrollTo(Self.raiseButtonID, anchor: .bottom) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { palette.paperBackground }
        .dynamicTypeSize(...Theme.TypeScale.largestSize)
        .task { isTitleFocused = true }
    }

    /// The raised list runs off the sheet's first height, so it fades there as the Lens wheel does
    /// instead of slicing a line. The content margin lets the last row and the capsule rest clear of it.
    private var footFadeMask: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.footFade)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.exerciseName)
                .themeFont(.sheetTitle)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($isTitleFocused)
            Text(presentation.setLine)
                .themeFont(.queuePill)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("set-flag-set-line")
        }
    }

    private var kinds: some View {
        Grid(horizontalSpacing: Self.chipSpacing, verticalSpacing: Self.chipSpacing) {
            GridRow {
                chip(.pain)
                chip(.technique)
            }
            GridRow {
                chip(.swapped)
                chip(.other)
            }
        }
    }

    private func chip(_ kind: SetFlagKind) -> some View {
        let isSelected = draft.kind == kind
        return Button {
            draft.kind = kind
        } label: {
            Text(kind.label)
                .themeFont(.railChipValue)
                .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Self.chipHeight)
                .background(isSelected ? palette.railSelectedFill : palette.railFill, in: .capsule)
                .overlay {
                    if isSelected {
                        Capsule().strokeBorder(palette.action, lineWidth: 2)
                    }
                }
                .contentShape(.capsule)
                .animation(Theme.pressAnimation, value: isSelected)
        }
        .buttonStyle(.pressScale)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("set-flag-kind-\(kind.rawValue)")
    }

    private var wordsField: some View {
        TextField(
            "Words for your coach",
            text: $typedWords,
            prompt: Text(draft.placeholder).foregroundStyle(palette.textSecondary),
            axis: .vertical
        )
        .themeFont(.coachNote)
        .foregroundStyle(palette.textPrimary)
        .tint(palette.action)
        .lineLimit(1...4)
        .focused($isWordsFocused)
        .submitLabel(.done)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: Self.chipHeight)
        .background(palette.railFill, in: .rect(cornerRadius: Theme.Radius.rail))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.rail)
                .strokeBorder(isWordsFocused ? palette.action : palette.pillStroke, lineWidth: 1)
        }
        .accessibilityIdentifier("set-flag-words")
        .onChange(of: typedWords, takeDraftsWords)
    }

    /// A vertical field takes Return as a new line, and a flag's words stay on one, so Return closes the
    /// keyboard instead. The draft's words go back into the field so it never shows what the flag dropped
    /// past its length.
    private func takeDraftsWords() {
        if typedWords.contains(where: \.isNewline) { isWordsFocused = false }
        draft.words = typedWords
        typedWords = draft.words
    }

    private var raisedFlags: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(presentation.raisedFlags) { flag in
                VStack(alignment: .leading, spacing: 2) {
                    Text(flag.sentence)
                        .themeFont(.coachNote)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    SetFlagStatus(standing: flag.standing, showsWord: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("set-flag-raised")
            }
        }
    }

    private var raiseButton: some View {
        Button {
            if let flag = draft.flag { onRaise(flag) }
        } label: {
            Text(presentation.raiseTitle)
                .logCapsuleMetrics()
                .foregroundStyle(palette.actionText)
                .background(palette.actionFill, in: .capsule)
        }
        .buttonStyle(.pressScale)
        .disabled(draft.flag == nil)
        .opacity(draft.flag == nil ? Theme.sheetHiddenRowOpacity : 1)
        .animation(Theme.pressAnimation, value: draft.flag == nil)
        .accessibilityIdentifier("set-flag-raise-button")
    }
}

/// Where a Set Flag stands: a status glyph beside its word (DESIGN.md §1), in Saved's type and, once
/// the Sheet holds the flag, Saved's ink. The fill says a flag is raised, because the outline is the
/// control that offers one, and the ink says how far it has gone. A refusal takes the danger mark.
/// Without its word the glyph is the mark on the branch, or what fits a crowded card head.
struct SetFlagStatus: View {
    let standing: SetFlagStanding
    let showsWord: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            switch standing {
            case .refused:
                if showsWord {
                    DangerMarkedText(message: standing.word, role: .setOf)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(palette.danger)
                }
            case .unsynced:
                raised(color: palette.textSecondary)
            case .landed:
                raised(color: showsWord ? palette.actionInk : palette.action)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func raised(color: Color) -> some View {
        if showsWord {
            Label(standing.word, systemImage: "flag.fill")
                .themeFont(.setOf)
                .foregroundStyle(color)
        } else {
            Image(systemName: "flag.fill")
                .foregroundStyle(color)
        }
    }
}
