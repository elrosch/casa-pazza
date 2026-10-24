package de.eliasrosch.casa_pazza

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.CheckBox
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.components.CircleIconButton
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import org.json.JSONObject

/** Key under which the Flutter app stores the widget data (see home_widget_sync.dart). */
private const val SHOPPING_DATA_KEY = "shopping_widget"

class ShoppingWidgetReceiver : HomeWidgetGlanceWidgetReceiver<ShoppingWidget>() {
    override val glanceAppWidget = ShoppingWidget()
}

private val ItemIdKey = ActionParameters.Key<String>("itemId")

/** Checkbox tap: checks the item off in Dart (widgetBackgroundCallback) without opening the app. */
class CheckItemAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[ItemIdKey] ?: return
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("casapazza://check-item?id=$id")).send()
    }
}

private data class ShoppingItem(val id: String, val name: String, val quantity: String)

private data class ShoppingData(
    val loggedIn: Boolean,
    val listName: String,
    val items: List<ShoppingItem>,
)

private fun parseShopping(json: String?): ShoppingData {
    if (json.isNullOrEmpty()) return ShoppingData(false, "", emptyList())
    val root = JSONObject(json)
    val items = root.optJSONArray("items")
    return ShoppingData(
        loggedIn = root.optBoolean("loggedIn", false),
        listName = root.optString("list"),
        items = (0 until (items?.length() ?: 0)).map { i ->
            val item = items!!.getJSONObject(i)
            ShoppingItem(
                id = item.optString("id"),
                name = item.optString("name"),
                quantity = item.optString("quantity"),
            )
        },
    )
}

class ShoppingWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                val state = currentState<HomeWidgetGlanceState>()
                Content(context, parseShopping(state.preferences.getString(SHOPPING_DATA_KEY, null)))
            }
        }
    }

    @Composable
    private fun Content(context: Context, data: ShoppingData) {
        val openApp = actionOpenApp(context, "casapazza://shopping")
        val scan = actionOpenApp(context, "casapazza://scan")

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.widgetBackground)
                .cornerRadius(20.dp)
                .padding(horizontal = 14.dp, vertical = 10.dp)
                .clickable(openApp),
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = data.listName.ifEmpty { "Einkauf" },
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurface,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                    modifier = GlanceModifier.defaultWeight().clickable(openApp),
                )
                if (data.loggedIn) {
                    CircleIconButton(
                        imageProvider = ImageProvider(R.drawable.ic_widget_scan),
                        contentDescription = "Barcode scannen",
                        onClick = scan,
                        backgroundColor = GlanceTheme.colors.primary,
                        contentColor = GlanceTheme.colors.onPrimary,
                        modifier = GlanceModifier.size(36.dp),
                    )
                }
            }
            Spacer(GlanceModifier.height(6.dp))
            when {
                !data.loggedIn -> ShoppingHint("Zum Anmelden tippen", openApp)
                data.items.isEmpty() -> ShoppingHint("Nichts zu kaufen.", openApp)
                else -> ItemList(data.items, openApp)
            }
        }
    }

    @Composable
    private fun ShoppingHint(text: String, onClick: Action) {
        Box(
            modifier = GlanceModifier.fillMaxSize().clickable(onClick),
            contentAlignment = Alignment.Center,
        ) {
            Text(text, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant))
        }
    }

    @Composable
    private fun ItemList(items: List<ShoppingItem>, openApp: Action) {
        LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
            items(items) { item ->
                Row(
                    modifier = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CheckBox(
                        checked = false,
                        onCheckedChange = actionRunCallback<CheckItemAction>(
                            actionParametersOf(ItemIdKey to item.id)
                        ),
                    )
                    Row(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .padding(vertical = 6.dp)
                            .clickable(openApp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = item.name,
                            style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 14.sp),
                            maxLines = 1,
                            modifier = GlanceModifier.defaultWeight(),
                        )
                        if (item.quantity.isNotEmpty()) {
                            Text(
                                text = item.quantity,
                                style = TextStyle(
                                    color = GlanceTheme.colors.onSurfaceVariant,
                                    fontSize = 13.sp,
                                ),
                                maxLines = 1,
                            )
                        }
                    }
                }
            }
        }
    }
}
