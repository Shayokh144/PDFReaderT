package com.example.taher144.pdfreaderlite

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.example.taher144.pdfreaderlite.ui.PDFReaderApp
import com.example.taher144.pdfreaderlite.ui.theme.PDFReaderLiteTheme

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            PDFReaderLiteTheme(dynamicColor = false) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    PDFReaderApp()
                }
            }
        }
    }
}