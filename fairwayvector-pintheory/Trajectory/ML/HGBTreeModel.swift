import Foundation

/// One decision-tree node from an exported `HistGradientBoostingRegressor` tree.
nonisolated struct HGBNode: Decodable, Sendable {
    let isLeaf: Bool
    let value: Double
    let featureIdx: Int
    let threshold: Double
    let missingGoToLeft: Bool
    let left: Int
    let right: Int
}

/// One target's exported HGB model: baseline prediction plus an additive tree ensemble.
nonisolated struct HGBModel: Decodable, Sendable {
    let target: String
    let exportName: String
    let featureList: [String]
    let baselinePrediction: Double
    let treeCount: Int
    let trees: [[HGBNode]]

    /// Reproduces `HistGradientBoostingRegressor.predict()` exactly: baseline + sum of tree leaves.
    func predict(features: [Double]) -> Double {
        var total = baselinePrediction
        for tree in trees {
            guard !tree.isEmpty else { continue }
            var index = 0
            while tree.indices.contains(index) {
                let node = tree[index]
                if node.isLeaf {
                    total += node.value
                    break
                }
                guard features.indices.contains(node.featureIdx) else { break }
                let value = features[node.featureIdx]
                let goLeft = value.isNaN ? node.missingGoToLeft : (value <= node.threshold)
                let nextIndex = goLeft ? node.left : node.right
                guard tree.indices.contains(nextIndex) else { break }
                index = nextIndex
            }
        }
        return total
    }
}

nonisolated enum HGBModelLoader {
    /// Loads a single exported model JSON (e.g. "carry") from the app bundle.
    static func load(exportName: String, bundle: Bundle = .main) throws -> HGBModel {
        guard let url = bundle.url(forResource: exportName, withExtension: "json", subdirectory: "MLModels")
            ?? bundle.url(forResource: exportName, withExtension: "json") else {
            throw HybridPredictorError.missingResource("\(exportName).json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HGBModel.self, from: data)
    }
}
