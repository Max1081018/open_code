package com.example.camera.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.IosShare
import androidx.compose.material.icons.rounded.SelectAll
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.camera.data.PhotoStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun GalleryScreen(vm: CameraViewModel) {
    val files = vm.gallery
    var selection by remember { mutableStateOf<Set<File>>(emptySet()) }
    var selectMode by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Ink)
            .statusBarsPadding()
    ) {
        // ---------------------------------------------------------- header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HaloIconButton(
                icon = Icons.Rounded.ArrowBack,
                contentDescription = "Back to camera",
                onClick = { vm.openCamera() }
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (selectMode) "${selection.size} selected" else "Library",
                    color = Mist,
                    fontFamily = DisplayFont,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "${files.size} items · kept on this phone",
                    color = Muted,
                    fontSize = 11.sp
                )
            }
            HaloIconButton(
                icon = Icons.Rounded.SelectAll,
                contentDescription = "Select all",
                active = selectMode,
                onClick = {
                    if (!selectMode) {
                        selectMode = true
                        selection = files.toSet()
                    } else if (selection.size == files.size) {
                        selection = emptySet()
                    } else {
                        selection = files.toSet()
                    }
                }
            )
        }

        // ------------------------------------------------------------ grid
        if (files.isEmpty()) {
            EmptyLibrary(modifier = Modifier.weight(1f))
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    horizontal = 8.dp, vertical = 4.dp
                ),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                items(files, key = { it.absolutePath }) { file ->
                    val isVideo = remember(file) { PhotoStore.isVideo(file) }
                    val thumb = rememberThumbnail(vm.store, file, 200)
                    val selected = file in selection
                    // Duration is probed off the main thread; badge appears when ready.
                    val durationMs by produceState(0L, file) {
                        value = withContext(Dispatchers.IO) { vm.store.durationMs(file) }
                    }
                    Box(
                        modifier = Modifier
                            .aspectRatio(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(PanelHigh)
                            .combinedClickable(
                                onClick = {
                                    if (selectMode) {
                                        selection = if (selected) selection - file else selection + file
                                    } else {
                                        vm.openEditor(file, from = Screen.Gallery)
                                    }
                                },
                                onLongClick = {
                                    if (!selectMode) selectMode = true
                                    selection = selection + file
                                }
                            )
                    ) {
                        if (thumb != null) {
                            Image(
                                bitmap = thumb,
                                contentDescription = "Library item",
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                        if (isVideo && durationMs > 0) {
                            Box(
                                modifier = Modifier
                                    .padding(6.dp)
                                    .align(Alignment.BottomStart)
                                    .clip(RoundedCornerShape(50))
                                    .background(Color.Black.copy(alpha = 0.55f))
                                    .padding(horizontal = 7.dp, vertical = 3.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(
                                        imageVector = Icons.Rounded.Videocam,
                                        contentDescription = null,
                                        tint = Mist,
                                        modifier = Modifier.size(11.dp)
                                    )
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text(
                                        text = formatDurationMs(durationMs),
                                        color = Mist,
                                        fontSize = 9.sp
                                    )
                                }
                            }
                        }
                        if (selectMode) {
                            Box(
                                modifier = Modifier
                                    .padding(6.dp)
                                    .align(Alignment.TopEnd)
                                    .size(20.dp)
                                    .clip(CircleShape)
                                    .background(if (selected) Amber else Color.Black.copy(alpha = 0.4f))
                                    .padding(3.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                if (selected) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .clip(CircleShape)
                                            .background(Ink.copy(alpha = 0.9f))
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------ bottom bar
        if (selectMode && selection.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                GradientButton(
                    text = "Save ${selection.size} to gallery",
                    leading = Icons.Rounded.IosShare,
                    onClick = {
                        vm.exportAll(selection.toList())
                        selectMode = false
                        selection = emptySet()
                    },
                    modifier = Modifier.weight(1f)
                )
                HaloIconButton(
                    icon = Icons.Rounded.Delete,
                    contentDescription = "Delete selected",
                    background = Danger.copy(alpha = 0.22f),
                    borderColor = Danger.copy(alpha = 0.5f),
                    size = 52.dp,
                    iconSize = 22.dp,
                    onClick = {
                        selection.forEach { vm.delete(it) }
                        selection = emptySet()
                        selectMode = false
                    }
                )
            }
        } else {
            Text(
                text = "Tap to edit · hold to select",
                color = Muted.copy(alpha = 0.7f),
                fontSize = 11.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(bottom = 10.dp)
            )
        }
    }
}

@Composable
private fun EmptyLibrary(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        HaloLogo(size = 72.dp, glow = 0.8f)
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No photos yet",
            color = Mist,
            fontFamily = DisplayFont,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "Take your first shot and Halo will\nenhance it the moment you capture.",
            color = Muted,
            fontSize = 12.sp,
            textAlign = TextAlign.Center
        )
    }
}

private fun formatDurationMs(ms: Long): String {
    val total = (ms.coerceAtLeast(0) / 1000).toInt()
    return String.format(Locale.US, "%d:%02d", total / 60, total % 60)
}
