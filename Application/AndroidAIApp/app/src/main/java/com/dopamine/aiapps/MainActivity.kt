package com.dopamine.aiapps

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import androidx.compose.foundation.layout.Row
import com.dopamine.aiapps.ui.theme.AiApplicationsTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AiApplicationsTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AiApplicationsScreen()
                }
            }
        }
    }
}

data class AiApplication(
    val name: String,
    val description: String,
    val url: String
)

data class AiCategory(
    val title: String,
    val applications: List<AiApplication>
)

@Composable
fun AiApplicationsScreen(
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val categories = remember { AiContent.categories }

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
                    Column(
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = context.getString(R.string.ai_catalog_title),
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        Text(
                            text = "Curated AI assistants, creative studios, and productivity copilots.",
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
                                category.applications.forEach { app ->
                                    AiApplicationCard(app) { target ->
                                        val uri = Uri.parse(target)
                                        val intent = Intent(Intent.ACTION_VIEW, uri)
                                        try {
                                            context.startActivity(intent)
                                        } catch (exception: ActivityNotFoundException) {
                                            Toast.makeText(context, "No browser found to open link", Toast.LENGTH_SHORT).show()
                                        }
                                    }
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
fun AiApplicationCard(
    application: AiApplication,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxWidth()
            .clickable { onOpen(application.url) },
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
                text = application.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = Color.White
            )
            Text(
                text = application.description,
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.8f),
                maxLines = 4,
                overflow = TextOverflow.Ellipsis
            )
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.CenterStart
            ) {
                RowWithIcon()
            }
        }
    }
}

@Composable
private fun RowWithIcon() {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(
            imageVector = Icons.Default.OpenInNew,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.8f)
        )
        Text(
            text = "Open",
            style = MaterialTheme.typography.labelLarge,
            color = Color.White.copy(alpha = 0.8f)
        )
    }
}

private object AiContent {
    val categories = listOf(
        AiCategory(
            title = "Chat Assistants",
            applications = listOf(
                AiApplication(
                    name = "ChatGPT",
                    description = "General-purpose assistant for ideation, explanations, and coding support.",
                    url = "https://chat.openai.com"
                ),
                AiApplication(
                    name = "Claude",
                    description = "Anthropic's assistant focused on reasoning-heavy writing and analysis.",
                    url = "https://claude.ai"
                ),
                AiApplication(
                    name = "Gemini",
                    description = "Google's multimodal AI with deep search and collaboration features.",
                    url = "https://gemini.google.com"
                ),
                AiApplication(
                    name = "Perplexity",
                    description = "Conversational research engine with citation-backed answers.",
                    url = "https://www.perplexity.ai"
                )
            )
        ),
        AiCategory(
            title = "Creative & Media",
            applications = listOf(
                AiApplication(
                    name = "Midjourney",
                    description = "Community-driven image generation for concept art and branding.",
                    url = "https://www.midjourney.com"
                ),
                AiApplication(
                    name = "Runway",
                    description = "Video editing and generative video tools for storytellers.",
                    url = "https://runwayml.com"
                ),
                AiApplication(
                    name = "Ideogram",
                    description = "Text-accurate image generation for marketing and typography designs.",
                    url = "https://ideogram.ai"
                ),
                AiApplication(
                    name = "ElevenLabs",
                    description = "High-quality synthetic voices for narration and localization.",
                    url = "https://elevenlabs.io"
                )
            )
        ),
        AiCategory(
            title = "Productivity & Automation",
            applications = listOf(
                AiApplication(
                    name = "GitHub Copilot",
                    description = "AI pair-programmer that suggests code in real time inside editors.",
                    url = "https://github.com/features/copilot"
                ),
                AiApplication(
                    name = "Notion AI",
                    description = "Embedded writing and research assistant within workspace documents.",
                    url = "https://www.notion.so/product/ai"
                ),
                AiApplication(
                    name = "Zapier Central",
                    description = "AI-assisted workflow builder that joins apps and automations.",
                    url = "https://zapier.com/ai"
                ),
                AiApplication(
                    name = "Cody",
                    description = "Sourcegraph's contextual enterprise AI assistant for codebases.",
                    url = "https://about.sourcegraph.com/cody"
                )
            )
        )
    )
}

@Preview(showBackground = true)
@Composable
private fun AiApplicationsPreview() {
    AiApplicationsTheme {
        AiApplicationsScreen()
    }
}
