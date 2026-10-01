// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BreakOverlayView: View {
    let title: String
    let seconds: Int
    let shownAt: Date
    let text: BreakReminderStrings
    let respond: (BreakAction) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(title).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                TimelineView(.periodic(from: shownAt, by: 1)) { context in
                    let left = max(0, seconds - Int(context.date.timeIntervalSince(shownAt)))
                    Text(left > 0 ? "\(left)" : text.done)
                        .font(.system(size: 64, weight: .light).monospacedDigit()).foregroundStyle(.white)
                }
                HStack(spacing: 12) {
                    Button(text.done) { respond(.done) }
                    Button(text.snooze) { respond(.snooze) }
                    Button(text.skip) { respond(.skip) }
                }
                .controlSize(.large)
            }
            .padding(40)
        }
    }
}
