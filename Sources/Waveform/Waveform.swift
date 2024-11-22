// Waveform.swift
// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/Waveform/

import AVFoundation
import MetalKit
import SwiftUI

#if os(macOS)
/// Waveform SwiftUI View
public struct Waveform: NSViewRepresentable {
    var samples: SampleBuffer
    var start: Int
    var length: Int
    var constants: Constants = Constants()
    var currentTime: TimeInterval? = nil // Optional: Defaults to nil, no red indicator
    var onSeek: ((TimeInterval) -> Void)? = nil // Optional: Defaults to nil, no interaction
    var audioDuration: TimeInterval // Duration of the audio in seconds

    public init(samples: SampleBuffer, start: Int = 0, length: Int = 0, currentTime: TimeInterval? = nil, audioDuration: TimeInterval, onSeek: ((TimeInterval) -> Void)? = nil) {
        self.samples = samples
        self.start = start
        self.currentTime = currentTime
        self.audioDuration = audioDuration
        self.onSeek = onSeek
        if length > 0 {
            self.length = min(length, samples.samples.count - start)
        } else {
            self.length = samples.samples.count - start
        }
    }

    public class Coordinator {
        var renderer: Renderer
        var onSeek: ((TimeInterval) -> Void)?
        var audioDuration: TimeInterval

        init(constants: Constants, onSeek: ((TimeInterval) -> Void)?, audioDuration: TimeInterval) {
            renderer = Renderer(device: MTLCreateSystemDefaultDevice()!)
            renderer.constants = constants
            self.onSeek = onSeek
            self.audioDuration = audioDuration
        }

        @objc func handleWaveformClick(_ gesture: NSClickGestureRecognizer) {
            guard let onSeek = onSeek, let gestureView = gesture.view else { return }
            let location = gesture.location(in: gestureView)
            let percent = location.x / gestureView.bounds.width
            let newTime = percent * audioDuration
            onSeek(newTime)
        }
    }

    public func makeCoordinator() -> Coordinator {
        return Coordinator(constants: constants, onSeek: onSeek, audioDuration: audioDuration)
    }

    public func makeNSView(context: Context) -> some NSView {
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), device: MTLCreateSystemDefaultDevice()!)
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.delegate = context.coordinator.renderer
        metalView.layer?.isOpaque = false

        if onSeek != nil {
            let clickRecognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleWaveformClick(_:)))
            metalView.addGestureRecognizer(clickRecognizer)
        }
        return metalView
    }

    public func updateNSView(_ nsView: NSViewType, context: Context) {
        let renderer = context.coordinator.renderer
        renderer.constants = constants
        if let currentTime = currentTime {
            renderer.set(samples: samples, start: start, length: length, currentTime: currentTime)
        } else {
            renderer.set(samples: samples, start: start, length: length)
        }
        nsView.setNeedsDisplay(nsView.bounds)
    }
}
#else
public struct Waveform: UIViewRepresentable {
    var samples: SampleBuffer
    var start: Int
    var length: Int
    var constants: Constants = Constants()
    var currentTime: TimeInterval? = nil
    var onSeek: ((TimeInterval) -> Void)? = nil
    var audioDuration: TimeInterval

    public init(samples: SampleBuffer, start: Int = 0, length: Int = 0, currentTime: TimeInterval? = nil, audioDuration: TimeInterval, onSeek: ((TimeInterval) -> Void)? = nil) {
        self.samples = samples
        self.start = start
        self.currentTime = currentTime
        self.audioDuration = audioDuration
        self.onSeek = onSeek
        if length > 0 {
            self.length = min(length, samples.samples.count - start)
        } else {
            self.length = samples.samples.count - start
        }
    }

    public class Coordinator {
        var renderer: Renderer
        var onSeek: ((TimeInterval) -> Void)?
        var audioDuration: TimeInterval

        init(constants: Constants, onSeek: ((TimeInterval) -> Void)?, audioDuration: TimeInterval) {
            renderer = Renderer(device: MTLCreateSystemDefaultDevice()!)
            renderer.constants = constants
            self.onSeek = onSeek
            self.audioDuration = audioDuration
        }

        @objc func handleWaveformTap(_ gesture: UITapGestureRecognizer) {
            guard let onSeek = onSeek, let gestureView = gesture.view else { return }
            let location = gesture.location(in: gestureView)
            let percent = location.x / gestureView.bounds.width
            let newTime = percent * audioDuration
            onSeek(newTime)
        }
    }

    public func makeCoordinator() -> Coordinator {
        return Coordinator(constants: constants, onSeek: onSeek, audioDuration: audioDuration)
    }

    public func makeUIView(context: Context) -> some UIView {
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), device: MTLCreateSystemDefaultDevice()!)
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.delegate = context.coordinator.renderer
        metalView.layer.isOpaque = false

        if onSeek != nil {
            let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleWaveformTap(_:)))
            metalView.addGestureRecognizer(tapRecognizer)
        }
        return metalView
    }

    public func updateUIView(_ uiView: UIViewType, context: Context) {
        let renderer = context.coordinator.renderer
        renderer.constants = constants
        if let currentTime = currentTime {
            renderer.set(samples: samples, start: start, length: length, currentTime: currentTime)
        } else {
            renderer.set(samples: samples, start: start, length: length)
        }
        uiView.setNeedsDisplay()
    }
}
#endif

extension Waveform {
    /// Modifier to change the foreground color of the waveform
    /// - Parameter foregroundColor: foreground color
    public func foregroundColor(_ foregroundColor: Color) -> Waveform {
        var copy = self
        copy.constants = Constants(color: foregroundColor)
        return copy
    }
}
