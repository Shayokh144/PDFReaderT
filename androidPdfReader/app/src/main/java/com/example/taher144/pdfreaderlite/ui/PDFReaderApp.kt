package com.example.taher144.pdfreaderlite.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.app.appContainer
import com.example.taher144.pdfreaderlite.ui.home.HomeEvent
import com.example.taher144.pdfreaderlite.ui.home.HomeScreen
import com.example.taher144.pdfreaderlite.ui.home.HomeViewModel

private const val PdfMimeType = "application/pdf"
private val EmptyStateBackground = Color(0xFF000000)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PDFReaderApp(
    viewModel: HomeViewModel = viewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val pdfEngine = remember { context.appContainer.pdfEngine }

    val pickerLauncher = rememberLauncherForActivityResult(
        contract = OpenPdfDocumentContract()
    ) { uri ->
        if (uri != null) {
            viewModel.onPdfPicked(uri)
        }
    }

    LaunchedEffect(viewModel) {
        viewModel.events.collect { event ->
            when (event) {
                is HomeEvent.OpenReader -> {
                    if (!pdfEngine.isReaderSupportedOnDevice()) {
                        snackbarHostState.showSnackbar(
                            context.getString(R.string.pdf_reader_unsupported_device)
                        )
                        return@collect
                    }
                    context.startActivity(
                        pdfEngine.createReaderIntent(context, event.request)
                    )
                }

                is HomeEvent.ShowMessage -> {
                    snackbarHostState.showSnackbar(context.getString(event.messageResId))
                }
            }
        }
    }

    Scaffold(
        containerColor = EmptyStateBackground,
        contentColor = Color.White,
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Text(text = stringResource(R.string.pdf_reader_navigation_title))
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = EmptyStateBackground,
                    titleContentColor = Color.White
                )
            )
        },
        snackbarHost = {
            SnackbarHost(hostState = snackbarHostState)
        }
    ) { innerPadding ->
        HomeScreen(
            uiState = uiState,
            onSelectPdf = { pickerLauncher.launch(arrayOf(PdfMimeType)) },
            onRecentFileSelected = viewModel::onRecentFileSelected,
            onRecentFileDeleted = viewModel::onRecentFileDeleted,
            modifier = androidx.compose.ui.Modifier.padding(innerPadding)
        )
    }
}
