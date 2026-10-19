import SwiftUI

struct FairwayVectorMark: View {
    var progress = 1.0

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let rect = CGRect(
                x: (size.width - side) / 2 + side * 0.056,
                y: (size.height - side) / 2 + side * 0.056,
                width: side * 0.888,
                height: side * 0.888
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: side * 0.18),
                with: .color(FairwayVectorColors.gold),
                style: StrokeStyle(lineWidth: side * 0.029)
            )

            let start = CGPoint(x: size.width * 0.15, y: size.height * 0.72)
            let control1 = CGPoint(x: size.width * 0.30, y: size.height * 0.22)
            let control2 = CGPoint(x: size.width * 0.63, y: size.height * 0.13)
            let landing = CGPoint(x: size.width * 0.85, y: size.height * 0.58)

            var flight = Path()
            flight.move(to: start)
            flight.addCurve(to: landing, control1: control1, control2: control2)
            context.stroke(
                flight,
                with: .color(FairwayVectorColors.flightBlue.opacity(0.95)),
                style: StrokeStyle(lineWidth: side * 0.066, lineCap: .round)
            )

            var vector = Path()
            vector.move(to: start)
            vector.addLine(to: landing)
            vector.addLine(to: CGPoint(x: size.width * 0.65, y: size.height * 0.40))
            context.stroke(
                vector,
                with: .color(FairwayVectorColors.surface),
                style: StrokeStyle(lineWidth: side * 0.082, lineCap: .round, lineJoin: .round)
            )

            let ball = pointOnFlight(start: start, firstControl: control1, secondControl: control2, end: landing)
            context.fill(
                Path(ellipseIn: CGRect(x: ball.x - side * 0.082, y: ball.y - side * 0.082, width: side * 0.164, height: side * 0.164)),
                with: .color(FairwayVectorColors.orange)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: landing.x - side * 0.057, y: landing.y - side * 0.057, width: side * 0.114, height: side * 0.114)),
                with: .color(FairwayVectorColors.gold)
            )
        }
        .accessibilityHidden(true)
    }

    private func pointOnFlight(start: CGPoint, firstControl: CGPoint, secondControl: CGPoint, end: CGPoint) -> CGPoint {
        let t = min(max(progress, 0), 1)
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * inverse * start.x + 3 * inverse * inverse * t * firstControl.x + 3 * inverse * t * t * secondControl.x + t * t * t * end.x,
            y: inverse * inverse * inverse * start.y + 3 * inverse * inverse * t * firstControl.y + 3 * inverse * t * t * secondControl.y + t * t * t * end.y
        )
    }
}
