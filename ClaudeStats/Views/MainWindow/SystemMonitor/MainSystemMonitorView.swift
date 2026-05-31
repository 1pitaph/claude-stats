import SwiftUI

struct MainSystemMonitorView: View {
    @Environment(AppEnvironment.self) private var env

    private var vm: SystemMonitorViewModel { env.systemMonitor }
    private var visibleModules: [SystemMonitorModule] {
        SystemMonitorModule.allCases.filter(env.preferences.systemMonitorVisibleModules.contains)
    }

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls
                cards
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            vm.start(refreshRate: env.preferences.systemMonitorRefreshRate)
        }
        .onDisappear {
            vm.stop()
        }
        .onChange(of: env.preferences.systemMonitorRefreshRate) { _, rate in
            vm.start(refreshRate: rate)
        }
    }

    private var snapshot: SystemMonitorSnapshot {
        vm.snapshot ?? .placeholder
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SYSTEM")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("System monitor")
                .font(.sora(24, weight: .semibold))
            Text("CPU, memory, disk, network, power, and thermal signals.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Task { await vm.refreshNow() }
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
                    .font(.sora(11, weight: .medium))
            }
            .buttonStyle(.bordered)

            Text(env.preferences.systemMonitorRefreshRate == .off ? "Manual refresh" : "Every \(env.preferences.systemMonitorRefreshRate.displayName)")
                .font(.sora(11))
                .foregroundStyle(Color.stxMuted)

            Spacer()

            if let timestamp = vm.snapshot?.timestamp {
                Text("Updated \(timestamp.formatted(date: .omitted, time: .standard))")
                    .font(.sora(11).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            } else {
                Text("No sample yet")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
            }
        }
    }

    private var cards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], spacing: 12) {
            ForEach(visibleModules) { module in
                card(for: module)
            }
        }
    }

    @ViewBuilder
    private func card(for module: SystemMonitorModule) -> some View {
        switch module {
        case .cpu: cpuCard
        case .memory: memoryCard
        case .disk: diskCard
        case .network: networkCard
        case .battery: batteryCard
        case .gpu: gpuCard
        case .thermal: thermalCard
        }
    }

    private var cpuCard: some View {
        let cpu = snapshot.cpu
        return SystemMetricCard(
            title: "Processor Load",
            symbol: SystemMonitorModule.cpu.symbol,
            value: Format.percent(cpu.totalUsage),
            caption: "\(cpu.perCoreUsage.count) logical cores",
            legends: [
                SystemMetricLegend("User", value: Format.percent(cpu.userUsage), color: Color.stxRamp[1]),
                SystemMetricLegend("System", value: Format.percent(cpu.systemUsage), color: Color.stxRamp[0]),
            ]
        ) {
            VStack(spacing: 10) {
                if !cpu.perCoreUsage.isEmpty {
                    SystemCoreLoadStrip(values: cpu.perCoreUsage)
                }
                SystemTimelineChart(bars: historyBars { sample in
                    [
                        SystemTimelineSegment(value: sample.cpu.userUsage, color: Color.stxRamp[1]),
                        SystemTimelineSegment(value: sample.cpu.systemUsage, color: Color.stxRamp[0]),
                    ]
                })
            }
        }
    }

    private var memoryCard: some View {
        let memory = snapshot.memory
        return SystemMetricCard(
            title: "Memory",
            symbol: SystemMonitorModule.memory.symbol,
            value: Format.percent(memory.usedRatio),
            caption: "\(bytes(memory.usedBytes)) of \(bytes(memory.totalBytes)) · \(memory.pressure.displayName)",
            legends: [
                SystemMetricLegend("Active", value: bytes(memory.activeBytes), color: Color.stxRamp[0]),
                SystemMetricLegend("Wired", value: bytes(memory.wiredBytes), color: Color.stxRamp[1]),
                SystemMetricLegend("Compressed", value: bytes(memory.compressedBytes), color: Color.stxRamp[3]),
            ]
        ) {
            SystemTimelineChart(bars: historyBars { sample in
                [
                    SystemTimelineSegment(value: sample.memory.activeRatio, color: Color.stxRamp[0]),
                    SystemTimelineSegment(value: sample.memory.wiredRatio, color: Color.stxRamp[1]),
                    SystemTimelineSegment(value: sample.memory.compressedRatio, color: Color.stxRamp[3]),
                ]
            })
        }
    }

    private var diskCard: some View {
        let disk = snapshot.disk
        return SystemMetricCard(
            title: "Disk",
            symbol: SystemMonitorModule.disk.symbol,
            value: Format.percent(disk.usedRatio),
            caption: "\(disk.volumeName) · \(bytes(disk.freeBytes)) free",
            legends: [
                SystemMetricLegend("Read", value: bytesPerSecond(disk.readBytesPerSecond), color: Color.stxRamp[3]),
                SystemMetricLegend("Write", value: bytesPerSecond(disk.writeBytesPerSecond), color: Color.stxRamp[0]),
            ]
        ) {
            SystemTimelineChart(bars: throughputBars(colors: [Color.stxRamp[3], Color.stxRamp[0]]) { sample in
                [sample.disk.readBytesPerSecond, sample.disk.writeBytesPerSecond]
            })
        }
    }

    private var networkCard: some View {
        let network = snapshot.network
        return SystemMetricCard(
            title: "Network",
            symbol: SystemMonitorModule.network.symbol,
            value: network.isUp ? bytesPerSecond(network.downloadBytesPerSecond) : "Offline",
            caption: "\(network.displayName) \(network.localIPv4.map { "· \($0)" } ?? "")",
            legends: [
                SystemMetricLegend("Down", value: bytesPerSecond(network.downloadBytesPerSecond), color: Color.stxRamp[3]),
                SystemMetricLegend("Up", value: bytesPerSecond(network.uploadBytesPerSecond), color: Color.stxRamp[0]),
            ]
        ) {
            SystemTimelineChart(bars: throughputBars(colors: [Color.stxRamp[3], Color.stxRamp[0]]) { sample in
                [sample.network.downloadBytesPerSecond, sample.network.uploadBytesPerSecond]
            })
        }
    }

    private var batteryCard: some View {
        let battery = snapshot.battery
        return SystemMetricCard(
            title: "Power",
            symbol: SystemMonitorModule.battery.symbol,
            value: battery.level.map(Format.percent) ?? "AC",
            caption: batteryCaption(battery),
            legends: [
                SystemMetricLegend("Health", value: battery.healthPercent.map { "\($0)%" } ?? "--", color: Color.stxRamp[3]),
                SystemMetricLegend("Cycles", value: battery.cycleCount.map(String.init) ?? "--", color: Color.stxRamp[1]),
                SystemMetricLegend("Adapter", value: battery.adapterWatts.map { "\($0)W" } ?? "--", color: Color.stxRamp[0]),
            ]
        ) {
            SystemTimelineChart(bars: historyBars { sample in
                [SystemTimelineSegment(value: sample.battery.level ?? 0, color: Color.stxRamp[3])]
            })
        }
    }

    private var gpuCard: some View {
        let gpu = snapshot.gpu
        return SystemMetricCard(
            title: "GPU",
            symbol: SystemMonitorModule.gpu.symbol,
            value: gpu.utilization.map(Format.percent) ?? "--",
            caption: gpu.isAvailable ? gpu.model : "GPU counters unavailable",
            legends: [
                SystemMetricLegend("Temp", value: gpu.temperatureCelsius.map { "\(Int($0.rounded()))C" } ?? "--", color: Color.stxRamp[0]),
                SystemMetricLegend("FPS", value: gpu.fps.map { String(format: "%.0f", $0) } ?? "--", color: Color.stxRamp[3]),
            ]
        ) {
            SystemTimelineChart(bars: historyBars { sample in
                [SystemTimelineSegment(value: sample.gpu.utilization ?? 0, color: Color.stxRamp[0])]
            })
        }
    }

    private var thermalCard: some View {
        let thermal = snapshot.thermal
        return SystemMetricCard(
            title: "Thermal",
            symbol: SystemMonitorModule.thermal.symbol,
            value: thermal.state.displayName,
            valueAnimatesNumeric: false,
            caption: "macOS thermal pressure",
            legends: [
                SystemMetricLegend("State", value: thermal.state.displayName, color: thermalColor(thermal.state), animatesValue: false),
            ]
        ) {
            SystemTimelineChart(bars: historyBars { sample in
                [SystemTimelineSegment(value: thermalSeverity(sample.thermal.state), color: thermalColor(sample.thermal.state))]
            })
        }
    }

    private func historyBars(_ makeSegments: (SystemMonitorSnapshot) -> [SystemTimelineSegment]) -> [[SystemTimelineSegment]] {
        vm.history.map(makeSegments)
    }

    private func throughputBars(
        colors: [Color],
        _ values: (SystemMonitorSnapshot) -> [Double]
    ) -> [[SystemTimelineSegment]] {
        let raw = vm.history.map(values)
        let maxValue = max(1, raw.flatMap { $0 }.max() ?? 1)
        return raw.map { row in
            row.enumerated().map { index, value in
                SystemTimelineSegment(
                    value: value / maxValue,
                    color: colors.indices.contains(index) ? colors[index] : Color.stxRamp[0]
                )
            }
        }
    }

    private func batteryCaption(_ battery: SystemBatterySnapshot) -> String {
        if !battery.isPresent {
            return battery.adapterWatts.map { "AC Power · \($0)W adapter" } ?? "AC Power"
        }
        if battery.isCharging {
            return battery.timeToFullMinutes.map { "Charging · \($0)m to full" } ?? "Charging"
        }
        if battery.isBatteryPowered {
            return battery.timeToEmptyMinutes.map { "Battery Power · \($0)m remaining" } ?? "Battery Power"
        }
        return battery.isCharged ? "Charged" : battery.powerSource
    }

    private func thermalSeverity(_ state: SystemThermalState) -> Double {
        switch state {
        case .nominal: 0.20
        case .fair: 0.42
        case .serious: 0.72
        case .critical: 1.0
        }
    }

    private func thermalColor(_ state: SystemThermalState) -> Color {
        switch state {
        case .nominal: Color.stxRamp[3]
        case .fair: Color.stxRamp[2]
        case .serious: Color.stxRamp[1]
        case .critical: Color.stxRamp[0]
        }
    }

    private func bytes(_ value: UInt64) -> String {
        Format.bytes(Int(clamping: value))
    }

    private func bytesPerSecond(_ value: Double) -> String {
        "\(Format.bytes(Int(clamping: UInt64(max(0, value.rounded())))))/s"
    }
}

#if DEBUG
#Preview("System Monitor") {
    MainSystemMonitorView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
