//
//  IntentSheet.swift — daily "today's focus" prompt
//
//  Pops on first launch each calendar day (unless the user already wrote
//  today's intent, or already dismissed today's prompt). The text lands at
//  data/intentions/{YYYY-MM-DD}.md which tell-rich's `load_intent` reads as
//  the INTENT line in its prompt — so once the user writes "ship the Tell
//  MVP", every hero narrative for today is grounded against that focus.
//

import SwiftUI
import AppKit

struct IntentSheet: View {
    @EnvironmentObject var store: ActivityStore
    @Binding var isPresented: Bool

    /// Pre-populated with whatever's already on disk (manual-edit path) so
    /// users updating mid-day don't have to retype.
    @State private var text: String = ""
    @State private var showSaved: Bool = false

    /// True when re-opening to EDIT an existing focus rather than the
    /// first-launch prompt. Drives copy + the "Skip" button label.
    let editing: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool { !trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(T.borderSoft)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    leadingCopy
                    editor
                    examples
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            Divider().background(T.borderSoft)
            footer
        }
        .frame(width: 560, height: 480)
        .background(T.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            // Pre-populate with the current intent so editing doesn't wipe.
            text = store.intent
        }
    }

    // MARK: - sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(T.accent).frame(width: 7, height: 7)
                .shadow(color: T.accent.opacity(0.55), radius: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(editing ? "Update today's focus" : "Set today's focus")
                    .font(T.serif(18))
                    .fontWeight(.semibold)
                    .foregroundColor(T.fgPri)
                Text(dateHeading)
                    .font(T.mono(11))
                    .foregroundColor(T.fgTer)
            }
            Spacer()
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(T.fgTer)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var leadingCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(editing
                 ? "Re-anchor what you're trying to land today."
                 : "What are you actually trying to land today?")
                .font(T.serif(15))
                .foregroundColor(T.fgPri)
                .lineSpacing(2)
            Text("Tell will hold you to it — every hero observation gets grounded against this focus, so drift shows up loud.")
                .font(T.ui(11.5))
                .foregroundColor(T.fgTer)
                .lineSpacing(2)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOCUS")
                .font(T.ui(10, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(T.fgTer)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(T.bgDeep)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.borderSoft, lineWidth: 0.5))
                if text.isEmpty {
                    Text("Ship Tell MVP — capture + OCR + distill + daily summary. No Twitter, no HN, no new side projects.")
                        .font(T.serif(13))
                        .italic()
                        .foregroundColor(T.fgQuat)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(T.serif(13))
                    .foregroundColor(T.fgPri)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
            }
            .frame(height: 120)
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT MAKES A GOOD ONE")
                .font(T.ui(9.5, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(T.fgTer)
            VStack(alignment: .leading, spacing: 4) {
                bullet("✓ Specific: 'finish OAuth callback fix + write tests'")
                bullet("✓ Names the traps: 'no Twitter, no new side projects'")
                bullet("✗ Vague: 'be productive'")
            }
        }
    }

    private func bullet(_ s: String) -> some View {
        Text(s)
            .font(T.mono(10.5))
            .foregroundColor(T.fgSec)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if showSaved {
                Text("Saved. Next refresh will use it.")
                    .font(T.mono(10.5))
                    .foregroundColor(T.accent)
                    .transition(.opacity)
            }
            Spacer()
            Button(action: dismissWithoutSaving) {
                Text(editing ? "Cancel" : "Skip for today")
                    .font(T.ui(12))
                    .foregroundColor(T.fgSec)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.bgElev))
            }
            .buttonStyle(.plain)
            Button(action: saveAndDismiss) {
                Text(editing ? "Update focus" : "Set focus")
                    .font(T.ui(12, weight: .semibold))
                    .foregroundColor(canSave ? T.fgPri : T.fgQuat)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(canSave ? T.accent.opacity(0.18) : T.bgElev)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(canSave ? T.accent.opacity(0.6) : T.borderSoft,
                                            lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    // MARK: - actions

    private func saveAndDismiss() {
        guard canSave else { return }
        if store.saveIntent(trimmed) {
            withAnimation { showSaved = true }
            // Mark "prompted today" so the first-launch trigger doesn't
            // re-pop if the user closes + reopens later in the day.
            store.markIntentPromptShownToday()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isPresented = false
            }
        }
    }

    private func dismissWithoutSaving() {
        // Either way the user explicitly closed the prompt today — don't
        // re-show it for the rest of the calendar day.
        store.markIntentPromptShownToday()
        isPresented = false
    }

    private var dateHeading: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"  // "Friday, May 16"
        return df.string(from: Date())
    }
}
