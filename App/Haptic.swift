//
//  Haptic.swift
//  FratRat
//
//  Created by Brady Bangasser on 6/28/26.
//

import UIKit

enum Haptic {

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(type)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Fired when a security alert arrives within 500 feet.
    /// Alternates .rigid (sharp/staccato) and .error (system urgent pattern)
    /// with .heavy impacts so it reads as "something is wrong" rather than
    /// a regular notification pulse.
    static func securityAlert() {
        let pattern: [(TimeInterval, () -> Void)] = [
            (0.00, { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }),
            (0.10, { UINotificationFeedbackGenerator().notificationOccurred(.error) }),
            (0.20, { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }),
            (0.30, { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }),
            (0.45, { UINotificationFeedbackGenerator().notificationOccurred(.error) }),
            (0.55, { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }),
            (0.65, { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }),
            (0.80, { UINotificationFeedbackGenerator().notificationOccurred(.error) }),
            (0.90, { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }),
            (1.00, { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }),
            (1.10, { UINotificationFeedbackGenerator().notificationOccurred(.error) }),
        ]
        for (delay, feedback) in pattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { feedback() }
        }
    }
}
