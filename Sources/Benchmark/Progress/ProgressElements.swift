//
//  ProgressElements.swift
//  Progress.swift
//
//  Created by Justus Kandzi on 04/01/16.
//  Copyright © 2016 Justus Kandzi. All rights reserved.
//
//  The MIT License (MIT)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

@_documentation(visibility: internal)
public protocol ProgressElementType: Sendable {
    func value(_ progressBar: ProgressBar) -> String
}

/// the progress bar element e.g. "[----------------------        ]"
@_documentation(visibility: internal)
public struct ProgressBarLine: ProgressElementType {
    let barLength: Int

    public init(barLength: Int = 30) {
        self.barLength = barLength
    }

    public func value(_ progressBar: ProgressBar) -> String {
        var completedBarElements = 0
        if progressBar.count == 0 {
            completedBarElements = barLength
        } else {
            completedBarElements = Int(Double(barLength) * (Double(progressBar.index) / Double(progressBar.count)))
        }

        var barArray = [String](repeating: "-", count: completedBarElements)
        barArray += [String](repeating: " ", count: barLength - completedBarElements)
        return "[" + barArray.joined(separator: "") + "]"
    }
}

/// the index element e.g. "2 of 3"
@_documentation(visibility: internal)
public struct ProgressIndex: ProgressElementType {
    public init() {}

    public func value(_ progressBar: ProgressBar) -> String {
        return "\(progressBar.index) of \(progressBar.count)"
    }
}

/// the percentage element e.g. "90.0%"
@_documentation(visibility: internal)
public struct ProgressPercent: ProgressElementType {
    let decimalPlaces: Int

    public init(decimalPlaces: Int = 0) {
        self.decimalPlaces = decimalPlaces
    }

    public func value(_ progressBar: ProgressBar) -> String {
        var percentDone = 100.0
        if progressBar.count > 0 {
            percentDone = Double(progressBar.index) / Double(progressBar.count) * 100
        }

        var padded = "\(percentDone.format(decimalPlaces))%"
        while padded.count < 4 {
            padded = " " + padded
        }
        return padded // "\(percentDone.format(decimalPlaces))%"
    }
}

/// the time estimates e.g. "ETA: 00:00:02 (at 1.00 it/s)"
@_documentation(visibility: internal)
public struct ProgressTimeEstimates: ProgressElementType {
    public init() {}

    public func value(_ progressBar: ProgressBar) -> String {
        let totalTime = getTimeOfDay() - progressBar.startTime

        var itemsPerSecond = 0.0
        var estimatedTimeRemaining = 0.0
        if progressBar.index > 0 {
            itemsPerSecond = Double(progressBar.index) / totalTime
            estimatedTimeRemaining = (Double(progressBar.count - progressBar.index) / itemsPerSecond) + 1.0
        }

        if progressBar.index >= progressBar.count {
            estimatedTimeRemaining = 0.0
        }

        let estimatedTimeRemainingString = formatDuration(estimatedTimeRemaining)

        return "ETA: \(estimatedTimeRemainingString)"
    }

    fileprivate func formatDuration(_ duration: Double) -> String {
        let duration = Int(duration)
        let seconds = Double(duration % 60)
        let minutes = Double((duration / 60) % 60)
        let hours = Double(duration / 3600)
        return
            "\(hours.format(0, minimumIntegerPartLength: 2)):\(minutes.format(0, minimumIntegerPartLength: 2)):\(seconds.format(0, minimumIntegerPartLength: 2))"
    }
}

/// an arbitrary string that can be added to the progress bar.
@_documentation(visibility: internal)
public struct ProgressString: ProgressElementType {
    let string: String

    public init(string: String) {
        self.string = string
    }

    public func value(_: ProgressBar) -> String {
        return string
    }
}
