package dev.steenbakker.mobile_scanner

import dev.steenbakker.mobile_scanner.objects.MobileScannerStartParameters
import java.lang.Error

typealias MobileScannerCallback = (barcodes: List<Map<String, Any?>>, image: ByteArray?, width: Int?, height: Int?) -> Unit
typealias AnalyzerErrorCallback = (message: String) -> Unit
typealias AnalyzerSuccessCallback = (barcodes: List<Map<String, Any?>>?) -> Unit
typealias MobileScannerErrorCallback = (error: String) -> Unit
typealias TorchStateCallback = (state: Int) -> Unit
typealias RecordStateCallback = (state: Int) -> Unit
typealias VideoRecordCompletionCallback = (String?, String?, Int?) -> Unit
typealias ZoomScaleStateCallback = (zoomScale: Double) -> Unit
typealias MobileScannerStartedCallback = (parameters: MobileScannerStartParameters) -> Unit