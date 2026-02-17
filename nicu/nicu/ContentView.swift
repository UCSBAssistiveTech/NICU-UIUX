import SwiftUI
import Charts

// MARK: - Data Model for Graphing
// A simple identifiable structure to hold data points for the charts.
struct VitalDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - Text Outline Modifier
// This view modifier adds a black outline to any view, making text more readable.
struct TextOutlineModifier: ViewModifier {
    let color: Color
    let width: CGFloat

    func body(content: Content) -> some View {
        ZStack {
            // Creates the outline by layering shadows in four directions.
            content.shadow(color: color, radius: 0, x: width, y: 0)
            content.shadow(color: color, radius: 0, x: -width, y: 0)
            content.shadow(color: color, radius: 0, x: 0, y: width)
            content.shadow(color: color, radius: 0, x: 0, y: -width)
            content
        }
    }
}

// Extension to make applying the text outline modifier easier.
extension View {
    func textOutline(color: Color, width: CGFloat) -> some View {
        self.modifier(TextOutlineModifier(color: color, width: width))
    }
}

// MARK: - Content View
// This view automatically opens the immersive space when it appears.
struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @State private var hasOpenedSpace = false

    var body: some View {
        VStack {
            Text("Loading Vitals...")
                .font(.title)
        }
        .onAppear {
            if !hasOpenedSpace {
                Task {
                    await openImmersiveSpace(id: "HealthMetrics")
                    hasOpenedSpace = true
                }
            }
        }
    }
}

// MARK: - Health Metrics View (TOP charts + BOTTOM vitals)
struct HealthMetricsView: View {
    // Live vital state (simulated for now, will be replaced by real data)
    @State private var heartRate: Double = 75
    @State private var spo2: Double = 98
    @State private var bloodPressureSystolic: Double = 120
    @State private var bloodPressureDiastolic: Double = 80
    @State private var temperature: Double = 98.6

    // Time-series data used by graphs
    @State private var heartRateHistory: [VitalDataPoint] = []
    @State private var spo2History: [VitalDataPoint] = []
    @State private var mapHistory: [VitalDataPoint] = []

    // Periodically refresh simulated vitals
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            
            // Global layout scaling and padding
            let outerPad: CGFloat = 16

            // Top chart row spacing
            let topBarPad: CGFloat = 14
            let topSpacing: CGFloat = 14
            
            // Bottom metric row
            let bottomBarPad: CGFloat = 8
            let bottomSpacing: CGFloat = 12

            // Dynamic row width based on screen size
            let barW = geo.size.width - outerPad * 2

            // Responsive tile widths
            let topTileW = (barW - topBarPad * 2 - topSpacing * 2) / 3
            let bottomTileW = (barW - bottomBarPad * 2 - bottomSpacing * 3) / 4

            VStack(spacing: 0) {

                // MARK: - Top Row: Charts
                HStack(spacing: topSpacing) {
                    SPO2HistogramView(title: "SpO2 (%)", data: spo2History, color: .blue)
                        .frame(width: topTileW)

                    VitalGraphView(title: "Heart Rate (BPM)", data: heartRateHistory, color: .red)
                        .frame(width: topTileW)

                    VitalGraphView(title: "Mean Arterial Pressure (mmHg)", data: mapHistory, color: .purple)
                        .frame(width: topTileW)
                }
                .padding(topBarPad)
                .background(.thinMaterial)
                .cornerRadius(20)
                .frame(width: barW)
                .clipped()

                Spacer()

                // MARK: - Bottom Row: Live Metrics
                HStack(spacing: bottomSpacing) {
                    HealthMetricView(
                        name: "SpO2",
                        value: "\(Int(spo2))",
                        unit: "%",
                        icon: "lungs.fill",
                        color: colorForSpO2(),
                        cardWidth: bottomTileW
                    )

                    HealthMetricView(
                        name: "Heart Rate",
                        value: "\(Int(heartRate))",
                        unit: "BPM",
                        icon: "heart.fill",
                        color: colorForHeartRate(),
                        cardWidth: bottomTileW
                    )

                    HealthMetricView(
                        name: "Blood Pressure",
                        value: "\(Int(bloodPressureSystolic))/\(Int(bloodPressureDiastolic))",
                        unit: "mmHg",
                        icon: "waveform.path.ecg",
                        color: colorForBloodPressure(),
                        cardWidth: bottomTileW
                    )

                    HealthMetricView(
                        name: "Temperature",
                        value: String(format: "%.1f", temperature),
                        unit: "°F",
                        icon: "thermometer",
                        color: colorForTemperature(),
                        cardWidth: bottomTileW
                    )
                }
                .frame(width: barW, alignment: .leading)
                .padding(bottomBarPad)
                .background(.thinMaterial)
                .cornerRadius(20)
                .clipped()
            }
            .padding(.horizontal, outerPad)
            .padding(.vertical, 2)
            .scaleEffect(0.75)
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear(perform: setupInitialData)
            .onReceive(timer) { _ in updateVitals() }
        }
        
    }

    // MARK: - Data and Color Logic
    
    func setupInitialData() {
        for _ in 0..<20 {
            updateVitals(isInitialSetup: true)
        }
    }

    func colorForHeartRate() -> Color { (60...100).contains(heartRate) ? .green : .red }
    func colorForSpO2() -> Color { (95...100).contains(spo2) ? .green : .red }
    func colorForBloodPressure() -> Color {
        let isSystolicNormal = (90...120).contains(bloodPressureSystolic)
        let isDiastolicNormal = (60...80).contains(bloodPressureDiastolic)
        return isSystolicNormal && isDiastolicNormal ? .green : .red
    }
    func colorForTemperature() -> Color { (97.8...99.1).contains(temperature) ? .green : .red }

    func updateVitals(isInitialSetup: Bool = false) {
        let updateAnimation: Animation? = isInitialSetup ? nil : .easeInOut

        withAnimation(updateAnimation) {
            // Generate new values
            if Int.random(in: 1...5) == 1 {
                heartRate = Bool.random() ? Double.random(in: 40...59) : Double.random(in: 101...140)
            } else {
                heartRate = Double.random(in: 60...100)
            }

            if Int.random(in: 1...5) == 1 {
                spo2 = Double.random(in: 90...94)
            } else {
                spo2 = Double.random(in: 95...100)
            }

            if Int.random(in: 1...5) == 1 {
                bloodPressureSystolic = Bool.random() ? Double.random(in: 80...89) : Double.random(in: 121...140)
                bloodPressureDiastolic = Bool.random() ? Double.random(in: 50...59) : Double.random(in: 81...90)
            } else {
                bloodPressureSystolic = Double.random(in: 90...120)
                bloodPressureDiastolic = Double.random(in: 60...80)
            }

            if Int.random(in: 1...5) == 1 {
                temperature = Bool.random() ? Double.random(in: 96.0...97.7) : Double.random(in: 99.2...100.4)
            } else {
                temperature = Double.random(in: 97.8...99.1)
            }
            // Calculate Mean Arterial Pressure (MAP)
            let map = bloodPressureDiastolic + (bloodPressureSystolic - bloodPressureDiastolic) / 3.0

            // Update history arrays
            let now = Date()
            heartRateHistory.append(VitalDataPoint(date: now, value: heartRate))
            spo2History.append(VitalDataPoint(date: now, value: spo2))
            mapHistory.append(VitalDataPoint(date: now, value: map))

            // Keep history to a fixed size
            if heartRateHistory.count > 20 { heartRateHistory.removeFirst() }
            if spo2History.count > 20 { spo2History.removeFirst() }
            if mapHistory.count > 20 { mapHistory.removeFirst() }
        }
    }
}

// MARK: - Metric Card 
struct HealthMetricView: View {
    let name: String, value: String, unit: String, icon: String, color: Color
    var cardWidth: CGFloat = 260
    var cardHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.headline)
                .foregroundColor(.white)
                .textOutline(color: .gray, width: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Fixed width keeps icons aligned across all cards
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 26)

                // Monospaced digits prevent jitter when values update
                Text(value)
                    .font(.system(size: 48, weight: .bold)) // middle
                    .foregroundColor(color)
                    .monospacedDigit()
                    .textOutline(color: .gray, width: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .layoutPriority(1)

                // Fixed size ensures units like "mmHg" never truncate
                Text(unit)
                    .font(.callout)
                    .foregroundColor(.white)
                    .textOutline(color: .gray, width: 1)
                    .fixedSize()
                    .layoutPriority(2)
            }
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .center)
    }
}


// MARK: - Graph Views
// A reusable view for displaying a single-line vital graph.
struct VitalGraphView: View {
    let title: String
    let data: [VitalDataPoint]
    let color: Color

    var body: some View {
        VStack(alignment: .trailing) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .textOutline(color: .gray, width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Chart(Array(data.enumerated()), id: \.element.id) { index, point in
                LineMark(
                    x: .value("Index", index),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: 0...19)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 90)
        }
        .frame(maxWidth: .infinity)
    }
}

// A new view for the SpO2 histogram.
struct SPO2HistogramView: View {
    let title: String
    let data: [VitalDataPoint]
    let color: Color

    var body: some View {
        VStack(alignment: .trailing) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .textOutline(color: .gray, width: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Chart(Array(data.enumerated()), id: \.element.id) { index, point in
                BarMark(
                    x: .value("Index", index),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(color)
            }
            .chartXScale(domain: 0...19)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 90)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
#Preview {
    HealthMetricsView()
}
