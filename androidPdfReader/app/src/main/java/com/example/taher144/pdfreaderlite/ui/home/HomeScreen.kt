package com.example.taher144.pdfreaderlite.ui.home

import android.text.format.DateUtils
import android.text.format.Formatter
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.taher144.pdfreaderlite.R
import com.example.taher144.pdfreaderlite.data.model.RecentPdfRecord

private val EmptyStateBackground = Color(0xFF000000)
private val EmptyStateIconTint = Color(0xFF8E8E93)
private val SelectButtonColor = Color(0xFF32D74B)
private val RecentCardColor = Color(0xFF1C1C1E)

@Composable
fun HomeScreen(
    uiState: HomeUiState,
    onSelectPdf: () -> Unit,
    onRecentFileSelected: (RecentPdfRecord) -> Unit,
    onRecentFileDeleted: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(EmptyStateBackground)
            .padding(horizontal = 16.dp, vertical = 20.dp)
    ) {
        if (maxWidth < 600.dp) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                EmptyStateContent()
                Spacer(modifier = Modifier.height(32.dp))
                if (uiState.recentFiles.isNotEmpty()) {
                    RecentFilesSection(
                        records = uiState.recentFiles,
                        onRecentFileSelected = onRecentFileSelected,
                        onRecentFileDeleted = onRecentFileDeleted,
                        modifier = Modifier.weight(1f, fill = true)
                    )
                } else {
                    Spacer(modifier = Modifier.weight(1f, fill = true))
                }
                Spacer(modifier = Modifier.height(16.dp))
                SelectPdfButton(
                    isOpeningDocument = uiState.isOpeningDocument,
                    onSelectPdf = onSelectPdf
                )
            }
        } else {
            Row(
                modifier = Modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    EmptyStateContent()
                }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                ) {
                    if (uiState.recentFiles.isNotEmpty()) {
                        RecentFilesSection(
                            records = uiState.recentFiles,
                            onRecentFileSelected = onRecentFileSelected,
                            onRecentFileDeleted = onRecentFileDeleted,
                            modifier = Modifier.weight(1f, fill = true)
                        )
                    } else {
                        Spacer(modifier = Modifier.weight(1f, fill = true))
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    SelectPdfButton(
                        isOpeningDocument = uiState.isOpeningDocument,
                        onSelectPdf = onSelectPdf
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyStateContent(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(32.dp))
        DocumentPlaceholderIcon()
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = stringResource(R.string.pdf_reader_empty_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = stringResource(R.string.pdf_reader_empty_description),
            style = MaterialTheme.typography.bodyLarge,
            color = EmptyStateIconTint,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun SelectPdfButton(
    isOpeningDocument: Boolean,
    onSelectPdf: () -> Unit
) {
    Button(
        onClick = onSelectPdf,
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp),
        shape = RoundedCornerShape(10.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = SelectButtonColor,
            contentColor = Color.Black
        )
    ) {
        if (isOpeningDocument) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = Color.Black,
                strokeWidth = 2.dp
            )
        } else {
            Text(
                text = stringResource(R.string.pdf_reader_select_pdf),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
private fun RecentFilesSection(
    records: List<RecentPdfRecord>,
    onRecentFileSelected: (RecentPdfRecord) -> Unit,
    onRecentFileDeleted: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth()
    ) {
        Text(
            text = stringResource(R.string.pdf_reader_recent_files),
            color = Color.White,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(12.dp))
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(records, key = { it.id }) { record ->
                RecentFileCard(
                    record = record,
                    onOpen = { onRecentFileSelected(record) },
                    onDelete = { onRecentFileDeleted(record.id) }
                )
            }
        }
    }
}

@Composable
private fun RecentFileCard(
    record: RecentPdfRecord,
    onOpen: () -> Unit,
    onDelete: () -> Unit
) {
    val context = LocalContext.current
    val fileSize = record.fileSizeBytes?.let { Formatter.formatShortFileSize(context, it) }
        ?: stringResource(R.string.pdf_reader_file_size_unknown)
    val relativeTime = DateUtils.getRelativeTimeSpanString(
        record.lastOpenedAt,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
        DateUtils.FORMAT_ABBREV_RELATIVE
    ).toString()
    val pageSummary = stringResource(
        R.string.pdf_reader_recent_file_page_format,
        record.lastPage + 1,
        record.totalPages.coerceAtLeast(1)
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(RecentCardColor, RoundedCornerShape(14.dp))
            .clickable(onClick = onOpen)
            .padding(16.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = record.displayName,
                modifier = Modifier.weight(1f),
                color = Color.White,
                fontWeight = FontWeight.SemiBold
            )
            IconButton(onClick = onDelete) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = stringResource(R.string.pdf_reader_remove),
                    tint = EmptyStateIconTint
                )
            }
        }
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "$fileSize ${stringResource(R.string.pdf_reader_list_separator)} $pageSummary",
            color = EmptyStateIconTint,
            style = MaterialTheme.typography.bodyMedium
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = relativeTime,
            color = EmptyStateIconTint,
            style = MaterialTheme.typography.bodySmall
        )
    }
}

@Composable
private fun DocumentPlaceholderIcon(modifier: Modifier = Modifier) {
    Canvas(
        modifier = modifier.size(88.dp)
    ) {
        val strokeWidth = size.minDimension * 0.06f
        val foldSize = size.width * 0.28f
        val inset = strokeWidth
        val path = Path().apply {
            moveTo(inset, inset)
            lineTo(size.width - foldSize - inset, inset)
            lineTo(size.width - inset, foldSize + inset)
            lineTo(size.width - inset, size.height - inset)
            lineTo(inset, size.height - inset)
            close()
        }

        drawPath(
            path = path,
            color = EmptyStateIconTint,
            style = Stroke(width = strokeWidth)
        )

        drawLine(
            color = EmptyStateIconTint,
            start = Offset(size.width - foldSize - inset, inset),
            end = Offset(size.width - foldSize - inset, foldSize + inset),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
        drawLine(
            color = EmptyStateIconTint,
            start = Offset(size.width - foldSize - inset, foldSize + inset),
            end = Offset(size.width - inset, foldSize + inset),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )

        val lineStartX = size.width * 0.28f
        val lineEndX = size.width * 0.72f
        val firstLineY = size.height * 0.56f
        val secondLineY = size.height * 0.70f

        drawLine(
            color = EmptyStateIconTint,
            start = Offset(lineStartX, firstLineY),
            end = Offset(lineEndX, firstLineY),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
        drawLine(
            color = EmptyStateIconTint,
            start = Offset(lineStartX, secondLineY),
            end = Offset(size.width * 0.62f, secondLineY),
            strokeWidth = strokeWidth,
            cap = StrokeCap.Round
        )
    }
}
