import AVFoundation
import Foundation
import Testing
@testable import LitScenes

// MARK: Stall deadline

@Test func shortContentGetsTheFloorDeadline() {
    // Below the six-second crossover the realtime multiple is smaller than
    // the floor, and fixed setup cost is what actually needs covering.
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: 0.5) == MediaExportGuard.floorSeconds)
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: 6) == MediaExportGuard.floorSeconds)
}

@Test func tracedClipLookCaseFailsFarSoonerThanBefore() {
    // The 9.04s clip behind cliplook_1d9a1764a3418d5b96 stalled for 361
    // seconds before VideoToolbox gave up. It now gets 90.
    let deadline = MediaExportGuard.deadlineSeconds(forContentSeconds: 9.036666)
    #expect(deadline == 90.36666)
    #expect(deadline < 361)
}

@Test func unknownContentDurationFallsBackToTheFloor() {
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: 0) == MediaExportGuard.floorSeconds)
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: -12) == MediaExportGuard.floorSeconds)
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: .nan) == MediaExportGuard.floorSeconds)
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: .infinity) == MediaExportGuard.floorSeconds)
}

@Test func longerContentScalesWithRealtimeMultiple() {
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: 30) == 300)
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: 120) == 1200)
}

@Test func veryLongContentIsCappedByTheCeilingButKeepsRealMargin() {
    // A ten-minute Lucy source (the documented input cap) is the longest
    // legitimate export: the ceiling clamps it, but the clamp must still
    // leave several multiples of realtime — a clamp that starved the
    // longest real export would cut it off mid-encode, not guard it.
    let tenMinutes = MediaExportGuard.deadlineSeconds(forContentSeconds: 600)
    #expect(tenMinutes == MediaExportGuard.ceilingSeconds)
    #expect(tenMinutes >= 600 * 6)
    #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: 10_000) == MediaExportGuard.ceilingSeconds)
}

@Test func shortContentFailsFarFasterThanTheObservedStall() {
    // The traced 9.04s Clip Look sat wedged for 361 seconds before the OS
    // surfaced anything. For everyday clip lengths the guard must beat that
    // number by a wide margin, or it buys the operator nothing.
    for seconds in [0.0, 1, 9.036666, 24] {
        #expect(MediaExportGuard.deadlineSeconds(forContentSeconds: seconds) < 361)
    }
}

// MARK: Encoder contention detection

@Test func avErrorEncodeFailedIsEncoderContention() {
    let error = NSError(domain: AVFoundationErrorDomain, code: -11883)
    #expect(MediaExportGuard.isEncoderContentionFailure(error))
}

@Test func nestedVideoToolboxMalfunctionIsEncoderContention() {
    // The exact shape logged by the failed Clip Look:
    // "Cannot Encode [domain=AVFoundationErrorDomain code=-11883
    //  underlying_1=NSOSStatusErrorDomain:-12912]"
    let videoToolbox = NSError(domain: NSOSStatusErrorDomain, code: -12912)
    let encode = NSError(
        domain: AVFoundationErrorDomain,
        code: -11883,
        userInfo: [NSUnderlyingErrorKey: videoToolbox]
    )
    #expect(MediaExportGuard.isEncoderContentionFailure(encode))
}

@Test func bareVideoToolboxStatusCodesAreEncoderContention() {
    for code in [-12912, -12915, -12907] {
        #expect(MediaExportGuard.isEncoderContentionFailure(
            NSError(domain: NSOSStatusErrorDomain, code: code)
        ))
    }
}

@Test func contentionIsFoundThroughAnIntermediateWrapper() {
    let videoToolbox = NSError(domain: NSOSStatusErrorDomain, code: -12912)
    let encode = NSError(
        domain: AVFoundationErrorDomain,
        code: -11883,
        userInfo: [NSUnderlyingErrorKey: videoToolbox]
    )
    let wrapper = NSError(
        domain: "LitScenes.Test",
        code: 7,
        userInfo: [NSUnderlyingErrorKey: encode]
    )
    #expect(MediaExportGuard.isEncoderContentionFailure(wrapper))
}

@Test func unrelatedFailuresAreNotEncoderContention() {
    #expect(!MediaExportGuard.isEncoderContentionFailure(
        NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    ))
    // A different AVFoundation fault must not borrow the encoder remedy.
    #expect(!MediaExportGuard.isEncoderContentionFailure(
        NSError(domain: AVFoundationErrorDomain, code: -11800)
    ))
    // A same-numbered code in another domain is a different error entirely.
    #expect(!MediaExportGuard.isEncoderContentionFailure(
        NSError(domain: "SomeOtherDomain", code: -12912)
    ))
    #expect(!MediaExportGuard.isEncoderContentionFailure(ScreenGraphError.capture("no encoder involved")))
}

// MARK: Cancellation stays recognizable

@Test func cancellationIsNotTreatedAsFailure() {
    #expect(MediaExportGuard.isCancellation(CancellationError()))
    #expect(MediaExportGuard.isCancellation(
        NSError(domain: AVFoundationErrorDomain, code: AVError.Code.operationCancelled.rawValue)
    ))
    #expect(!MediaExportGuard.isCancellation(
        NSError(domain: AVFoundationErrorDomain, code: -11883)
    ))
}

// MARK: Operator message keeps machine provenance

@Test func failureShowsRemedyWhileKeepingUnderlyingProvenance() {
    let videoToolbox = NSError(domain: NSOSStatusErrorDomain, code: -12912)
    let encode = NSError(
        domain: AVFoundationErrorDomain,
        code: -11883,
        userInfo: [NSUnderlyingErrorKey: videoToolbox]
    )
    let failure = MediaExportFailure(
        message: MediaExportGuard.encoderContentionMessage,
        underlying: encode
    )

    // What the operator reads names the cause and the cure — including the
    // app's own recorder, which competes for the same AVE block.
    #expect(failure.localizedDescription.contains("hardware video encoder"))
    #expect(failure.localizedDescription.contains("screen recording"))
    #expect(failure.localizedDescription.contains("Record Session"))
    #expect(!failure.localizedDescription.contains("Cannot Encode"))

    // What the trace records still identifies the exact system fault, so the
    // diagnosis that produced this guard stays reproducible.
    let asNSError = failure as NSError
    let firstUnderlying = asNSError.userInfo[NSUnderlyingErrorKey] as? NSError
    #expect(firstUnderlying?.domain == AVFoundationErrorDomain)
    #expect(firstUnderlying?.code == -11883)
    let secondUnderlying = firstUnderlying?.userInfo[NSUnderlyingErrorKey] as? NSError
    #expect(secondUnderlying?.domain == NSOSStatusErrorDomain)
    #expect(secondUnderlying?.code == -12912)
}

@Test func stallMessageStatesTheDeadlineAndTheRemedy() {
    let message = MediaExportGuard.stallMessage(deadlineSeconds: 90)
    #expect(message.contains("90 seconds"))
    #expect(message.contains("screen recording"))
}

@Test func audioStallMessageNeverBlamesTheVideoEncoder() {
    // An m4a export never touches the AVE block — telling the operator to
    // stop a screen recording would be plausible-sounding false advice.
    let message = MediaExportGuard.stallMessage(deadlineSeconds: 60, fileType: .m4a)
    #expect(message.contains("60 seconds"))
    #expect(!message.contains("screen recording"))
    #expect(!message.contains("video encoder"))
}

// MARK: Pinned system constants

@Test func systemErrorConstantsMatchTheOnesTheGuardHardcodes() {
    // -11883 and -12912 are written as literals in the tests above and as
    // symbols in the guard; if the SDK ever disagrees, fail here rather than
    // silently stop recognizing a wedged encoder.
    #expect(AVError.Code.encodeFailed.rawValue == -11883)
    #expect(MediaExportGuard.encoderContentionStatusCodes.contains(-12912))
}

// MARK: THE ENCODER FALLBACK LAW (reverse bakes retry once on software)

@Test func softwareEncoderRetryLawClassifiesFailures() {
    // The watchdog's stall — with or without an underlying error — retries.
    #expect(ReverseProxyBaker.shouldRetryWithSoftwareEncoder(
        MediaExportFailure(message: "stalled", underlying: nil)
    ))
    // VideoToolbox contention (kVTVideoEncoderMalfunctionErr) retries, even
    // nested under another error.
    let contention = NSError(
        domain: AVFoundationErrorDomain,
        code: AVError.Code.encodeFailed.rawValue,
        userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -12912)]
    )
    #expect(ReverseProxyBaker.shouldRetryWithSoftwareEncoder(contention))
    // Cancellation is the operator, never the encoder — no retry, in either
    // of its shapes.
    #expect(!ReverseProxyBaker.shouldRetryWithSoftwareEncoder(CancellationError()))
    #expect(!ReverseProxyBaker.shouldRetryWithSoftwareEncoder(NSError(
        domain: AVFoundationErrorDomain,
        code: AVError.Code.operationCancelled.rawValue
    )))
    // An unrelated failure (bad source, refused track) surfaces as-is.
    #expect(!ReverseProxyBaker.shouldRetryWithSoftwareEncoder(
        ScreenGraphError.capture("no video track")
    ))
}
