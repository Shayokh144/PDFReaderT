package com.example.taher144.pdfreaderlite.reader

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.fragment.app.activityViewModels
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.ui.reader.PdfSearchResult
import com.example.taher144.pdfreaderlite.ui.reader.ReaderViewModel
import com.google.android.material.bottomsheet.BottomSheetDialogFragment

class PdfSearchBottomSheetFragment : BottomSheetDialogFragment() {
    private val viewModel: ReaderViewModel by activityViewModels()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return ComposeView(requireContext()).apply {
            setContent {
                MaterialTheme {
                    PdfSearchScreen(viewModel)
                }
            }
        }
    }

    override fun onDismiss(dialog: android.content.DialogInterface) {
        super.onDismiss(dialog)
        viewModel.setIsSearching(false)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PdfSearchScreen(viewModel: ReaderViewModel) {
    val searchText by viewModel.searchText.collectAsState()
    val searchResults by viewModel.searchResults.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .fillMaxHeight(0.9f)
            .background(MaterialTheme.colorScheme.surface)
    ) {
        OutlinedTextField(
            value = searchText,
            onValueChange = { viewModel.setSearchText(it) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            placeholder = { Text(stringResource(R.string.pdf_reader_search_placeholder)) },
            singleLine = true,
            trailingIcon = {
                if (searchText.isNotEmpty()) {
                    IconButton(onClick = { viewModel.setSearchText("") }) {
                        Icon(Icons.Default.Clear, contentDescription = "Clear")
                    }
                }
            }
        )

        if (searchText.isNotEmpty() && searchResults.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.pdf_reader_search_no_results), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(vertical = 8.dp)
            ) {
                items(searchResults) { result ->
                    SearchResultItem(result = result, onClick = {
                        viewModel.navigateToSearchResult(result)
                    })
                }
            }
        }
    }
}

@Composable
fun SearchResultItem(result: PdfSearchResult, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text(
            text = stringResource(R.string.pdf_reader_search_result_page, result.pageIndex + 1),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(bottom = 4.dp)
        )
        
        val annotatedString = buildAnnotatedString {
            val snippet = result.snippet
            val startIndex = result.snippetMatchStartIndex
            val endIndex = startIndex + result.matchLength

            if (startIndex >= 0 && startIndex <= snippet.length) {
                val safeEndIndex = minOf(endIndex, snippet.length)
                append(snippet.substring(0, startIndex))
                withStyle(style = SpanStyle(fontWeight = FontWeight.Bold, background = Color.Yellow.copy(alpha = 0.3f))) {
                    append(snippet.substring(startIndex, safeEndIndex))
                }
                append(snippet.substring(safeEndIndex))
            } else {
                append(snippet)
            }
        }
        
        Text(
            text = annotatedString,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}
