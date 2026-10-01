// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakReminderTests {
    static func run(_ suite: TestSuite) {
        rotation(suite)
    }

    static func activity(_ text: String, _ seconds: Int = 20) -> BreakActivity {
        BreakActivity(id: UUID(), text: text, seconds: seconds)
    }

    static func rotation(_ suite: TestSuite) {
        let list = [activity("a"), activity("b"), activity("c")]
        var r = ActivityRotation()
        suite.expect(r.current(.eyes, in: list)?.text == "a", "rotation starts at the first activity")
        r.advance(.eyes, count: 3); r.advance(.eyes, count: 3)
        suite.expect(r.current(.eyes, in: list)?.text == "c", "rotation advances in order")
        r.advance(.eyes, count: 3)
        suite.expect(r.current(.eyes, in: list)?.text == "a", "rotation wraps")
        suite.expect(r.current(.movement, in: list)?.text == "a", "kinds rotate independently")

        r.indices[.eyes] = 2
        let shorter = Array(list.prefix(2))
        suite.expect(r.current(.eyes, in: shorter)?.text == "b", "deleting clamps to the last item")
        r.advance(.eyes, count: 2)
        suite.expect(r.current(.eyes, in: shorter)?.text == "a", "advance after a clamp wraps to the start")

        suite.expect(r.current(.eyes, in: []) == nil, "empty list returns nil")
        r.advance(.eyes, count: 0)
        suite.expect(r.indices[.eyes] == 0, "advancing an empty list resets the index")
    }
}
