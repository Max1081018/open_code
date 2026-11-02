package com.example.camera.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.io.File

@Composable
fun GalleryScreen(vm: CameraViewModel) {
    val store = vm.store

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Ink)
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .clickable { vm.openCamera() },
                contentAlignment = Alignment.Center
            ) {
                GlyphIcon(Glyph.Close, Mist, Modifier.size(18.dp))
            }
            Spacer(modifier = Modifier.width(6.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Library",
                    color = Mist,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = countLabel(vm.gallery.size),
                    color = Muted,
                    fontSize = 11.sp
                )
            }
        }

        if (vm.gallery.isEmpty()) {
            EmptyLibrary(onCapture = { vm.openCamera() })
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(2.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                items(vm.gallery, key = { it.absolutePath }) { file ->
                    GalleryTile(store, file) { vm.openEditor(file, Screen.Gallery) }
                }
            }
        }
    }
}

@Composable
private fun GalleryTile(
    store: com.example.camera.data.PhotoStore,
    file: File,
    onClick: () -> Unit
) {
    val thumb = rememberThumbnail(store, file, 320)
    val edited = file.name.contains("_edit")

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .background(Panel)
            .clickable(onClick = onClick)
    ) {
        if (thumb != null) {
            Image(
                bitmap = thumb,
                contentDescription = "Photo",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
        if (edited) {
            Text(
                text = "AI",
                color = Ink,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(Amber)
                    .padding(horizontal = 5.dp, vertical = 2.dp)
            )
        }
    }
}

@Composable
private fun EmptyLibrary(onCapture: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        GlyphIcon(Glyph.Gallery, Muted.copy(alpha = 0.7f), Modifier.size(46.dp))
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Nothing here yet",
            color = Mist,
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "Photos you take show up here, on this phone only.",
            color = Muted,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 40.dp)
        )
        Spacer(modifier = Modifier.height(18.dp))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(30.dp))
                .background(Amber)
                .clickable(onClick = onCapture)
                .padding(horizontal = 24.dp, vertical = 12.dp)
        ) {
            Text("Take a photo", color = Ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun countLabel(count: Int): String {
    val photos = if (count == 1) "1 photo" else "$count photos"
    return "$photos · on this device"
}
