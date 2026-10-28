import Foundation

public struct BuildStage: Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var finished: Bool?
}

public struct BuildProgress: Sendable {
    public private(set) var stages: [BuildStage] = []
    public private(set) var step = ""
    public private(set) var fraction: Double?
    public private(set) var elapsed: Double?
    public private(set) var eta: Double?
    public private(set) var done: Double?
    public private(set) var total: Double?
    public private(set) var unit = ""
    public private(set) var estimated = false
    public private(set) var stageIndex = 0
    public private(set) var stageTotal = 0
    public init() {}
    public mutating func receive(_ event: ProgressEvent) {
        if event.ev == "stage" {
            let index = event.k ?? stageIndex + 1
            // The pipeline replans after decompression or a provisional survey.
            // Its counter restarts; show the new plan without duplicate row IDs.
            if index <= stageIndex { stages.removeAll(keepingCapacity: true) }
            stageIndex = index
            stages.append(BuildStage(id: index, name: event.name ?? "Preparing", finished: nil))
            stageTotal = event.n ?? stageTotal
            step = event.step ?? ""; fraction = nil; elapsed = nil; eta = nil; done = nil; total = nil
            unit = ""; estimated = false
        } else if event.ev == "progress" {
            // A null ETA or fraction clears the previous estimate instead of freezing it.
            fraction = event.fraction; elapsed = event.elapsed; eta = event.eta
            done = event.done; total = event.total; unit = event.unit ?? ""; estimated = event.est ?? false
        } else if event.ev == "stage_end", !stages.isEmpty {
            stages[stages.count - 1].finished = event.ok ?? true
            fraction = event.ok == false ? fraction : 1
            elapsed = event.elapsed; eta = nil
        }
        if let step = event.step { self.step = step }
    }
}
