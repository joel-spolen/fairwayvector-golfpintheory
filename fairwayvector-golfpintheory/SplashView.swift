import SwiftUI

struct SplashView: View {
    let isReturningUser: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var didScheduleDismissal = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("splashscreen")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(1.06)
                    .clipped()
                    .opacity(isVisible ? 1 : 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Golf PinTheory")
            .accessibilityAddTraits(.isHeader)
        }
        .ignoresSafeArea()
        .background(Color(red: 0.012, green: 0.043, blue: 0.034).ignoresSafeArea())
        .onAppear(perform: startAnimation)
    }

    private func startAnimation() {
        guard !didScheduleDismissal else { return }
        didScheduleDismissal = true

        if reduceMotion {
            isVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (isReturningUser ? 0.3 : 0.75), execute: onDismiss)
            return
        }

        withAnimation(.easeOut(duration: isReturningUser ? 0.2 : 0.45)) {
            isVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (isReturningUser ? 0.65 : 1.8)) {
            withAnimation(.easeInOut(duration: isReturningUser ? 0.15 : 0.3)) {
                isVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (isReturningUser ? 0.15 : 0.3), execute: onDismiss)
        }
    }
}
