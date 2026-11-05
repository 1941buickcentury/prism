import UIKit

/// Keyboard haptics. These only fire when the keyboard has Full Access granted, so the
/// controller passes that in; without it the generators do nothing.
final class Haptics {
    private let enabled: Bool
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()

    init(enabled: Bool) {
        self.enabled = enabled
        if enabled { prepare() }
    }

    func prepare() {
        guard enabled else { return }
        light.prepare(); soft.prepare(); rigid.prepare(); selection.prepare()
    }

    /// A crisp tick for a normal key.
    func key() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.7)
        light.prepare()
    }

    /// A softer tick for space / return.
    func wide() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.9)
        soft.prepare()
    }

    /// A firm tap for backspace / shift.
    func control() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.8)
        rigid.prepare()
    }

    /// A light step as a glide crosses into a new key.
    func glideStep() {
        guard enabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    /// A satisfying double-tap when a glided word commits.
    func glideCommit() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.light.impactOccurred(intensity: 0.6)
            self?.light.prepare()
        }
    }
}
