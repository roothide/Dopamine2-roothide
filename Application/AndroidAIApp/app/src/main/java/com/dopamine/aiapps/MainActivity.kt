package com.dopamine.aiapps

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.dopamine.aiapps.ui.theme.AiApplicationsTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AiApplicationsTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AiToolLauncherScreen()
                }
            }
        }
    }
}

private data class AiTool(
    val name: String,
    val description: String,
    val url: String
)

private data class AiToolCategory(
    val title: String,
    val tools: List<AiTool>
)

@Composable
private fun AiToolLauncherScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val categories = remember { AiToolCatalog.categories }

    val gradientColors = listOf(
        Color(0xFF0F172A),
        Color(0xFF1E1B4B),
        Color(0xFF0F172A)
    )

    Scaffold(
        modifier = modifier,
        containerColor = Color.Transparent
    ) { padding ->
        Box(
            modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(gradientColors))
        ) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp),
                contentPadding = PaddingValues(top = padding.calculateTopPadding() + 36.dp, bottom = 36.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            text = "AI Tool Launcher",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        Text(
                            text = "?????? ???? ????? ????? ?????? ????????? ???????? ?? ??? ??????? ?????????.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                    }
                }

                categories.forEach { category ->
                    item(key = category.title) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(
                                text = category.title,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White.copy(alpha = 0.75f)
                            )

                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                category.tools.forEach { tool ->
                                    AiToolCard(tool) { openUrl(context, tool.url) }
                                }
                            }
                        }
                    }
                }

                item { Spacer(modifier = Modifier.height(12.dp)) }
            }
        }
    }
}

@Composable
private fun AiToolCard(tool: AiTool, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable { onOpen() },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(
            containerColor = Color.White.copy(alpha = 0.08f),
            contentColor = Color.White
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = tool.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White
            )
            Text(
                text = tool.description,
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.8f),
                maxLines = 4,
                overflow = TextOverflow.Ellipsis
            )
            Icon(
                imageVector = Icons.Default.OpenInNew,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.8f)
            )
        }
    }
}

private fun openUrl(context: Context, url: String) {
    val uri = Uri.parse(url)
    val customTabsIntent = CustomTabsIntent.Builder()
        .setShowTitle(true)
        .build()

    try {
        customTabsIntent.launchUrl(context, uri)
    } catch (unsupported: ActivityNotFoundException) {
        val viewIntent = Intent(Intent.ACTION_VIEW, uri)
        context.startActivity(viewIntent)
    }
}

private object AiToolCatalog {
    val categories = listOf(
        AiToolCategory(
            title = "?????? ?????",
            tools = listOf(
                AiTool(
                    name = "DeepSeek Chat",
                    description = "????? ?????? ????? ???? ?????? ?????? ???????? ?? ??? ??? ?????.",
                    url = "https://chat.deepseek.com/"
                ),
                AiTool(
                    name = "ChatGPT (??? ??????)",
                    description = "????? ChatGPT ????????? ??????????? ??????? ?????? ??????.",
                    url = "https://chat.openai.com/"
                ),
                AiTool(
                    name = "Gemini",
                    description = "????? ???? ???????? ?? ??? ????? ??????? ??????? ???.",
                    url = "https://gemini.google.com/"
                ),
                AiTool(
                    name = "Perplexity",
                    description = "???? ??? ????? ???? ?????? ?????? ?? ????? ??????.",
                    url = "https://www.perplexity.ai/"
                )
            )
        ),
        AiToolCategory(
            title = "??? ??????",
            tools = listOf(
                AiTool(
                    name = "Stable Diffusion (ClipDrop)",
                    description = "????? ??? ????? ?? Stability.ai ?? ??????? ????? ????????.",
                    url = "https://clipdrop.co/stable-diffusion"
                ),
                AiTool(
                    name = "Ideogram",
                    description = "???? ????? ??? ????? ?????? ????? ??????? ?????????.",
                    url = "https://ideogram.ai/"
                ),
                AiTool(
                    name = "Runway",
                    description = "????? ????? ????? ???? ?????? ????? ???? ?????? ?????.",
                    url = "https://runwayml.com/"
                ),
                AiTool(
                    name = "Leonardo AI",
                    description = "???? ??? ????? ?? ????? ?????? ?????? ?????? ????? ??????.",
                    url = "https://app.leonardo.ai/"
                )
            )
        ),
        AiToolCategory(
            title = "????? ????????",
            tools = listOf(
                AiTool(
                    name = "GitHub Copilot Chat",
                    description = "????? ????? ???? ??????? ????????? ????? ???? ???????.",
                    url = "https://github.com/copilot"
                ),
                AiTool(
                    name = "Cody by Sourcegraph",
                    description = "????? ????? ????? ???? ????? ?????? ????? ??? ??????????.",
                    url = "https://sourcegraph.com/cody"
                ),
                AiTool(
                    name = "Notion AI",
                    description = "????? ?????? ???? ?????? Notion ?? ??? ?????? ??????.",
                    url = "https://www.notion.so/product/ai"
                ),
                AiTool(
                    name = "HuggingFace Spaces",
                    description = "????? ???? ?????? ????? ?????? ?????? ??? ?????? ??? ?????.",
                    url = "https://huggingface.co/spaces"
                )
            )
        )
    )
}

@Preview(showBackground = true)
@Composable
private fun AiToolLauncherPreview() {
    AiApplicationsTheme {
        AiToolLauncherScreen()
    }
}
