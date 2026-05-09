package com.example.resortconnectapp

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.firebase.database.FirebaseDatabase
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
import com.google.zxing.common.BitMatrix
import com.google.common.util.concurrent.ListenableFuture
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class QrScannerActivity : AppCompatActivity() {

    private lateinit var cameraExecutor: ExecutorService
    private lateinit var previewView: PreviewView
    private val database = FirebaseDatabase.getInstance().getReference("bookings")
    private var isScanning = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_qr_scanner)

        previewView = findViewById(R.id.previewView)
        cameraExecutor = Executors.newSingleThreadExecutor()

        if (allPermissionsGranted()) {
            startCamera()
        } else {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.CAMERA), REQUEST_CODE_PERMISSIONS
            )
        }
    }

    private fun startCamera() {
        val cameraProviderFuture: ListenableFuture<ProcessCameraProvider> = 
            ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener(Runnable {
            try {
                val cameraProvider: ProcessCameraProvider = cameraProviderFuture.get()

                val preview = Preview.Builder()
                    .build()
                    .also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }

                val imageAnalyzer = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also {
                        it.setAnalyzer(cameraExecutor) { imageProxy ->
                            processImageProxy(imageProxy)
                        }
                    }

                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    this, CameraSelector.DEFAULT_BACK_CAMERA, preview, imageAnalyzer
                )
            } catch (exc: Exception) {
                Log.e(TAG, "Use case binding failed", exc)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun processImageProxy(imageProxy: ImageProxy) {
        if (!isScanning) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            val scanner = BarcodeScanning.getClient()

            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    for (barcode in barcodes) {
                        barcode.rawValue?.let { rawValue ->
                            isScanning = false // Pause scanner
                            handleScanResult(rawValue)
                            return@addOnSuccessListener
                        }
                    }
                }
                .addOnFailureListener {
                    Log.e(TAG, "Barcode scanning failed", it)
                }
                .addOnCompleteListener {
                    imageProxy.close()
                }
        }
    }

    private fun handleScanResult(rawValue: String) {
        val bookingId = if (rawValue.contains("scan=")) {
            Uri.parse(rawValue).getQueryParameter("scan") ?: rawValue
        } else {
            rawValue
        }
        fetchBookingDetails(bookingId)
    }

    private fun fetchBookingDetails(bookingId: String) {
        database.child(bookingId).get().addOnSuccessListener { snapshot ->
            if (snapshot.exists()) {
                showDetailModal(bookingId, snapshot.value.toString())
            } else {
                Toast.makeText(this, "Booking not found: $bookingId", Toast.LENGTH_SHORT).show()
                isScanning = true // Resume
            }
        }.addOnFailureListener {
            Toast.makeText(this, "Error fetching data", Toast.LENGTH_SHORT).show()
            isScanning = true // Resume
        }
    }

    private fun showDetailModal(id: String, details: String) {
        runOnUiThread {
            val dialog = BottomSheetDialog(this)
            val view = layoutInflater.inflate(R.layout.dialog_booking_details, null)
            
            view.findViewById<TextView>(R.id.textBookingId).text = "Booking ID: $id"
            view.findViewById<TextView>(R.id.textDetails).text = details
            view.findViewById<Button>(R.id.btnClose).setOnClickListener {
                dialog.dismiss()
                isScanning = true // Resume scanner when modal closes
            }
            
            dialog.setContentView(view)
            dialog.show()
        }
    }

    // TASK 2: Generate QR Code
    fun generateBookingQr(bookingId: String): Bitmap? {
        val websiteUrl = "https://your-website-url.com/owner?scan=$bookingId"
        val size = 512
        return try {
            val bitMatrix: BitMatrix = MultiFormatWriter().encode(
                websiteUrl, BarcodeFormat.QR_CODE, size, size
            )
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
            for (x in 0 until size) {
                for (y in 0 until size) {
                    bitmap.setPixel(x, y, if (bitMatrix[x, y]) Color.BLACK else Color.WHITE)
                }
            }
            bitmap
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun allPermissionsGranted() = arrayOf(Manifest.permission.CAMERA).all {
        ContextCompat.checkSelfPermission(baseContext, it) == PackageManager.PERMISSION_GRANTED
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }

    companion object {
        private const val TAG = "QrScannerActivity"
        private const val REQUEST_CODE_PERMISSIONS = 10
    }
}
