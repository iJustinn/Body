//
//  BodyPerformanceSignposts.swift
//  Body
//

import os

/// Shared signposter for the performance-critical paths tuned in 0.9.2.
/// Inspect intervals in Instruments (os_signpost) under subsystem
/// com.zihengthedeveloper.Body, category "Performance".
enum BodyPerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: "com.zihengthedeveloper.Body",
        category: "Performance"
    )
}
