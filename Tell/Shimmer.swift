//
//  Shimmer.swift — animated loading shimmer
//  Ported from PickTrip/View/Shimmer.swift
//

import SwiftUI

public struct Shimmer: ViewModifier {
    public enum Mode {
        case mask
        case overlay(blendMode: BlendMode = .sourceAtop)
        case background
    }

    private let animation: Animation
    private let gradient: Gradient
    private let min, max: CGFloat
    private let mode: Mode
    @State private var isInitialState = true
    @Environment(\.layoutDirection) private var layoutDirection

    public init(
        animation: Animation = Self.defaultAnimation,
        gradient: Gradient = Self.defaultGradient,
        bandSize: CGFloat = 0.3,
        mode: Mode = .mask
    ) {
        self.animation = animation
        self.gradient = gradient
        self.min = 0 - bandSize
        self.max = 1 + bandSize
        self.mode = mode
    }

    public static let defaultAnimation = Animation
        .linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false)

    public static let defaultGradient = Gradient(colors: [
        .black.opacity(0.3), .black, .black.opacity(0.3)
    ])

    var startPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            isInitialState ? UnitPoint(x: max, y: min) : UnitPoint(x: 0, y: 1)
        } else {
            isInitialState ? UnitPoint(x: min, y: min) : UnitPoint(x: 1, y: 1)
        }
    }

    var endPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            isInitialState ? UnitPoint(x: 1, y: 0) : UnitPoint(x: min, y: max)
        } else {
            isInitialState ? UnitPoint(x: 0, y: 0) : UnitPoint(x: max, y: max)
        }
    }

    public func body(content: Content) -> some View {
        applyingGradient(to: content)
            .animation(animation, value: isInitialState)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    isInitialState = false
                }
            }
    }

    @ViewBuilder
    public func applyingGradient(to content: Content) -> some View {
        let g = LinearGradient(gradient: gradient, startPoint: startPoint, endPoint: endPoint)
        switch mode {
        case .mask:
            content.mask(g)
        case let .overlay(blendMode: blendMode):
            content.overlay(g.blendMode(blendMode))
        case .background:
            content.background(g)
        }
    }
}

public extension View {
    @ViewBuilder
    func shimmering(
        active: Bool = true,
        animation: Animation = Shimmer.defaultAnimation,
        gradient: Gradient = Shimmer.defaultGradient,
        bandSize: CGFloat = 0.3,
        mode: Shimmer.Mode = .mask
    ) -> some View {
        if active {
            modifier(Shimmer(animation: animation, gradient: gradient, bandSize: bandSize, mode: mode))
        } else {
            self
        }
    }
}

// MARK: - Tell-specific mock placeholder text

/// A 3-line placeholder that mimics a typical Tell hero observation,
/// rendered dim so .shimmering() reads as "AI is thinking".
struct TellHeroPlaceholder: View {
    let lines: [String]

    init(_ lines: [String] = [
        "You spent the last stretch jumping between three projects without",
        "finishing any of them. The OAuth callback fix is still untouched",
        "even though you opened the file twice — want to talk about it?"
    ]) {
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(T.serif(14.5))
                    .foregroundColor(T.fgQuat)  // dim — will be masked by shimmer
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
