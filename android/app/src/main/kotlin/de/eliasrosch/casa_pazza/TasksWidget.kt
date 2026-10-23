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
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.actionStartActivity
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import org.json.JSONObject

/** Key under which the Flutter app stores the widget data (see home_widget_sync.dart). */
private const val DATA_KEY = "tasks_widget"

class TasksWidgetReceiver : HomeWidgetGlanceWidgetReceiver<TasksWidget>() {
    override val glanceAppWidget = TasksWidget()
}

private val TaskIdKey = ActionParameters.Key<String>("taskId")

/** Checkbox tap: completes the task in Dart (widgetBackgroundCallback) without opening the app. */
class CompleteTaskAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[TaskIdKey] ?: return
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("casapazza://complete?id=$id")).send()
    }
}

private data class WidgetTask(
    val id: String,
    val title: String,
    val due: LocalDate?,
    val assignee: String,
    val repeats: Boolean,
)

private data class WidgetData(
    val loggedIn: Boolean,
    val listName: String,
    /** "Heute" view: only tasks due today, overdue or without a date. */
    val todayOnly: Boolean,
    val tasks: List<WidgetTask>,
) {
    fun visibleTasks(today: LocalDate): List<WidgetTask> =
        if (!todayOnly) tasks else tasks.filter { it.due == null || !it.due.isAfter(today) }
}

private fun parse(json: String?): WidgetData {
    if (json.isNullOrEmpty()) return WidgetData(false, "", false, emptyList())
    val root = JSONObject(json)
    val tasks = root.optJSONArray("tasks")
    return WidgetData(
        loggedIn = root.optBoolean("loggedIn", false),
        listName = root.optString("list"),
        todayOnly = root.optBoolean("todayOnly", false),
        tasks = (0 until (tasks?.length() ?: 0)).map { i ->
            val t = tasks!!.getJSONObject(i)
            WidgetTask(
                id = t.optString("id"),
                title = t.optString("title"),
                due = t.optString("due").takeIf { it.isNotEmpty() }?.let(LocalDate::parse),
                assignee = t.optString("assignee"),
                repeats = t.optBoolean("repeats"),
            )
        },
    )
}

/** Same wording as the app: Heute, Morgen, Gestern or e.g. "Fr., 24.10.". */
private fun dueLabel(due: LocalDate, today: LocalDate): String =
    when (ChronoUnit.DAYS.between(today, due)) {
        0L -> "Heute"
        1L -> "Morgen"
        -1L -> "Gestern"
        else -> due.format(DateTimeFormatter.ofPattern("EE, d.M.", Locale.GERMAN))
    }

class TasksWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                val state = currentState<HomeWidgetGlanceState>()
                Content(context, parse(state.preferences.getString(DATA_KEY, null)))
            }
        }
    }

    @Composable
    private fun Content(context: Context, data: WidgetData) {
        val openApp = actionStartActivity<MainActivity>(context, Uri.parse("casapazza://tasks"))
        val addTask = actionStartActivity<MainActivity>(context, Uri.parse("casapazza://add-task"))

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
                    text = data.listName.ifEmpty { "Casa Pazza" },
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
                        imageProvider = ImageProvider(R.drawable.ic_widget_add),
                        contentDescription = "Aufgabe hinzufügen",
                        onClick = addTask,
                        backgroundColor = GlanceTheme.colors.primary,
                        contentColor = GlanceTheme.colors.onPrimary,
                        modifier = GlanceModifier.size(36.dp),
                    )
                }
            }
            Spacer(GlanceModifier.height(6.dp))
            val tasks = data.visibleTasks(LocalDate.now())
            when {
                !data.loggedIn -> Hint("Zum Anmelden tippen", openApp)
                tasks.isEmpty() -> Hint(if (data.todayOnly) "Heute nichts zu tun." else "Nichts zu tun.", openApp)
                else -> TaskList(context, tasks)
            }
        }
    }

    @Composable
    private fun Hint(text: String, onClick: Action) {
        Box(
            modifier = GlanceModifier.fillMaxSize().clickable(onClick),
            contentAlignment = Alignment.Center,
        ) {
            Text(text, style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant))
        }
    }

    @Composable
    private fun TaskList(context: Context, tasks: List<WidgetTask>) {
        val today = LocalDate.now()
        LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
            items(tasks) { task ->
                val overdue = task.due != null && task.due.isBefore(today)
                val details = listOfNotNull(
                    task.due?.let { dueLabel(it, today) },
                    task.assignee.takeIf { it.isNotEmpty() },
                    if (task.repeats) "↻" else null,
                ).joinToString(" · ")

                val editTask = actionStartActivity<MainActivity>(
                    context,
                    Uri.parse("casapazza://edit-task?id=${task.id}"),
                )

                Row(
                    modifier = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CheckBox(
                        checked = false,
                        onCheckedChange = actionRunCallback<CompleteTaskAction>(
                            actionParametersOf(TaskIdKey to task.id)
                        ),
                    )
                    Column(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .padding(vertical = 3.dp)
                            .clickable(editTask),
                    ) {
                        Text(
                            text = task.title,
                            style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 14.sp),
                            maxLines = 1,
                        )
                        if (details.isNotEmpty()) {
                            Text(
                                text = details,
                                style = TextStyle(
                                    color = if (overdue) GlanceTheme.colors.error
                                    else GlanceTheme.colors.onSurfaceVariant,
                                    fontSize = 12.sp,
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
