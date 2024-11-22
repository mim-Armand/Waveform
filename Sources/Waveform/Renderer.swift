// Renderer.swift
// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/Waveform/

import Foundation
import Metal
import MetalKit
import SwiftUI

let MaxBuffers = 3

/// Parameters defining the look and feel of the waveform
struct Constants {
    var sampleRate: Double = 44100.0  // Default sample rate
    var color: Color = .blue

    init(color: Color = .blue) {
        self.color = color
    }
}

class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice!
    var queue: MTLCommandQueue!
    var pipeline: MTLRenderPipelineState!
    public var constants = Constants()
    var commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState
    var samples: SampleBuffer?
    var start: Int = 0
    var length: Int = 0
    var currentSampleIndex: Int?  // Added to handle the red indicator position

    private let inflightSemaphore = DispatchSemaphore(value: MaxBuffers)

    var minBuffers: [MTLBuffer] = []
    var maxBuffers: [MTLBuffer] = []

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        queue = device.makeCommandQueue()

        //        let library = device.makeDefaultLibrary()!
        guard let library = try? device.makeDefaultLibrary(bundle: .module)
        else {
            fatalError(
                "Failed to load Metal library from the Waveform package.")
        }
        let vertexFunction = library.makeFunction(name: "vertex_main")!
        let fragmentFunction = library.makeFunction(name: "fragment_main")!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true

        self.pipelineState = try! device.makeRenderPipelineState(
            descriptor: pipelineDescriptor)
        self.constants = Constants()  // Defaults to ensure compatibility

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = library.makeFunction(name: "waveform_vert")
        rpd.fragmentFunction = library.makeFunction(name: "waveform_frag")

        let colorAttachment = rpd.colorAttachments[0]!
        colorAttachment.pixelFormat = .bgra8Unorm
        colorAttachment.isBlendingEnabled = true
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipeline = try! device.makeRenderPipelineState(descriptor: rpd)

        minBuffers = [device.makeBuffer([0])!]
        maxBuffers = [device.makeBuffer([0])!]

        print("minBuffers count: \(minBuffers.count)")
        print("maxBuffers count: \(maxBuffers.count)")

        super.init()
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func selectBuffers(width: CGFloat) -> (MTLBuffer?, MTLBuffer?) {
        var level = 0
        for (minBuffer, maxBuffer) in zip(minBuffers, maxBuffers) {
            if CGFloat(minBuffer.length / MemoryLayout<Float>.size) < width {
                return (minBuffer, maxBuffer)
            }
            level += 1
        }

        if let minBufferLast = minBuffers.last,
            let maxBufferLast = maxBuffers.last
        {
            return (minBufferLast, maxBufferLast)
        } else {
            return (nil, nil)
        }
    }

    func encode(
        to commandBuffer: MTLCommandBuffer,
        pass: MTLRenderPassDescriptor,
        width: CGFloat
    ) {
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1.0)
        
        print("Number of samples during encoding: \(samples?.samples.count ?? 0)")

        let highestResolutionCount = Float(samples?.samples.count ?? 0)
        let startFactor = Float(start) / highestResolutionCount
        let lengthFactor = Float(length) / highestResolutionCount

        let (minBufferOpt, maxBufferOpt) = selectBuffers(
            width: width / CGFloat(lengthFactor))
        guard let minBuffer = minBufferOpt, let maxBuffer = maxBufferOpt else {
            return
        }

        let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
        enc.setRenderPipelineState(pipeline)

        let bufferLength = Float(minBuffer.length / MemoryLayout<Float>.size)
        let bufferStart = Int(bufferLength * startFactor)
        var bufferCount = Int(bufferLength * lengthFactor)

        enc.setFragmentBuffer(
            minBuffer, offset: bufferStart * MemoryLayout<Float>.size, index: 0)
        enc.setFragmentBuffer(
            maxBuffer, offset: bufferStart * MemoryLayout<Float>.size, index: 1)
        enc.setFragmentBytes(
            &bufferCount, length: MemoryLayout<Int32>.size, index: 2)
        let c = [constants]
        enc.setFragmentBytes(c, length: MemoryLayout<Constants>.size, index: 3)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let samples = samples else {
            print("Samples are nil or drawable is missing")
            return
        }
        
        print("Number of samples in draw: \(samples.samples.count)")


        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderPassDescriptor = view.currentRenderPassDescriptor!

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(pipelineState)

        let size = view.frame.size
        let w = Float(size.width)
        let h = Float(size.height)

        if w == 0 || h == 0 {
            return
        }

        _ = inflightSemaphore.wait(timeout: DispatchTime.distantFuture)

        let semaphore = inflightSemaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        if let currentSampleIndex = currentSampleIndex {
            drawRedIndicator(
                at: currentSampleIndex, in: renderEncoder, view: view)
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func drawRedIndicator(
        at sampleIndex: Int, in renderEncoder: MTLRenderCommandEncoder,
        view: MTKView
    ) {
        // Implement red line drawing at `sampleIndex`
        // This function will need logic to translate the `sampleIndex` to a screen X position
    }

    func set(
        samples: SampleBuffer, start: Int, length: Int,
        currentTime: TimeInterval? = nil
    ) {
        self.samples = samples
        self.start = start
        self.length = length
        
        print("Number of samples set: \(samples.samples.count)")
        
        if let currentTime = currentTime {
            self.currentSampleIndex = calculateSampleIndex(for: currentTime)
        } else {
            self.currentSampleIndex = nil
        }
    }

    func calculateSampleIndex(for currentTime: TimeInterval) -> Int {
        guard let samples = samples else { return 0 }
        let totalSamples = samples.samples.count
        let sampleRate = constants.sampleRate
        let totalDuration = Double(totalSamples) / sampleRate
        return Int((currentTime / totalDuration) * Double(totalSamples))
    }
}

func makeBuffers(device: MTLDevice, samples: SampleBuffer) -> (
    [MTLBuffer], [MTLBuffer]
) {
    var minSamples = samples.samples
    var maxSamples = samples.samples

    var s = samples.samples.count
    var minBuffers: [MTLBuffer] = []
    var maxBuffers: [MTLBuffer] = []
    while s > 2 {
        minBuffers.append(device.makeBuffer(minSamples)!)
        maxBuffers.append(device.makeBuffer(maxSamples)!)

        minSamples = binMin(samples: minSamples, binSize: 2)
        maxSamples = binMax(samples: maxSamples, binSize: 2)
        s /= 2
    }
    return (minBuffers, maxBuffers)
}
