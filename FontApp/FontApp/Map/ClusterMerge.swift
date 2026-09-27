import CoreGraphics
import Foundation

/// Joins server clusters that would overlap on screen.
///
/// The server grids the view in ~70 px cells, but a circle is 44–52 pt and its centre is
/// the mean of its fountains, so neighbours often overlap at country zoom and cover each
/// other's numbers. Joining them keeps every fountain counted, which hiding the ones
/// underneath would not.
nonisolated enum ClusterMerge {
    /// Centres closer than this (in points) become one circle: two of the largest (52 pt)
    /// plus a small gap.
    static let minDistance: CGFloat = 56

    static func merge(_ clusters: [MapCluster], minDistance: CGFloat = minDistance,
                      project: (MapCluster) -> CGPoint) -> [MapCluster] {
        struct Group {
            var point: CGPoint
            var latitude: Double
            var longitude: Double
            var count: Int
        }
        var groups: [Group] = []
        // Biggest first, so the small ones join the big ones and not the other way round.
        for cluster in clusters.sorted(by: { $0.count > $1.count }) {
            let point = project(cluster)
            if let i = groups.firstIndex(where: { hypot($0.point.x - point.x, $0.point.y - point.y) < minDistance }) {
                var g = groups[i]
                let total = Double(g.count + cluster.count)
                g.latitude = (g.latitude * Double(g.count) + cluster.latitude * Double(cluster.count)) / total
                g.longitude = (g.longitude * Double(g.count) + cluster.longitude * Double(cluster.count)) / total
                g.count += cluster.count
                groups[i] = g
            } else {
                groups.append(Group(point: point, latitude: cluster.latitude, longitude: cluster.longitude,
                                    count: cluster.count))
            }
        }
        return groups.map { MapCluster(latitude: $0.latitude, longitude: $0.longitude, count: $0.count) }
    }
}
