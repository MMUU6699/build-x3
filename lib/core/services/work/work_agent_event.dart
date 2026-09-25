import 'dart:convert';

/// Status of an individual step in the agent's execution plan.
enum WorkPlanStepStatus {
  pending,
  inProgress,
  completed,
  failed;

  static WorkPlanStepStatus fromString(String? status) {
    switch (status?.toLowerCase()) {
      case 'in_progress':
      case 'inprogress':
        return WorkPlanStepStatus.inProgress;
      case 'completed':
      case 'done':
        return WorkPlanStepStatus.completed;
      case 'failed':
        return WorkPlanStepStatus.failed;
      case 'pending':
      default:
        return WorkPlanStepStatus.pending;
    }
  }
}

/// A discrete step inside the agent's plan.
class WorkPlanStep {
  const WorkPlanStep({
    required this.id,
    required this.title,
    this.status = WorkPlanStepStatus.pending,
  });

  final int id;
  final String title;
  final WorkPlanStepStatus status;

  factory WorkPlanStep.fromJson(Map<String, dynamic> json) {
    return WorkPlanStep(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      title: json['title'] as String? ?? '',
      status: WorkPlanStepStatus.fromString(json['status'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.name,
  };

  WorkPlanStep copyWith({int? id, String? title, WorkPlanStepStatus? status}) {
    return WorkPlanStep(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
    );
  }
}

/// Base sealed class for all Work Mode Agent events.
sealed class WorkAgentEvent {
  const WorkAgentEvent();
}

/// 1. Planning Event: current step list / plan.
class WorkPlanningEvent extends WorkAgentEvent {
  const WorkPlanningEvent({required this.steps});
  final List<WorkPlanStep> steps;
}

/// 2. Thinking Event: reasoning tokens & trace from model/SDK.
class WorkThinkingEvent extends WorkAgentEvent {
  const WorkThinkingEvent({
    required this.content,
    this.elapsedSeconds = 0,
    this.effort = 'medium',
  });
  final String content;
  final int elapsedSeconds;
  final String effort;
}

/// 3. Browsing Event: live browser view / snapshot.
class WorkBrowsingEvent extends WorkAgentEvent {
  const WorkBrowsingEvent({
    required this.url,
    required this.title,
    this.snapshot = '',
    this.status = 'browsing',
  });
  final String url;
  final String title;
  final String snapshot;
  final String status;
}

/// 4. Coding Event: code panel / file modification / diff.
class WorkCodingEvent extends WorkAgentEvent {
  const WorkCodingEvent({
    required this.filePath,
    required this.newContent,
    this.oldContent = '',
    this.isNew = true,
    this.diff = '',
  });
  final String filePath;
  final String newContent;
  final String oldContent;
  final bool isNew;
  final String diff;
}

/// Terminal Tool Event: command execution output.
class WorkTerminalEvent extends WorkAgentEvent {
  const WorkTerminalEvent({required this.command, required this.output});
  final String command;
  final String output;
}

/// 5. Finished Deliverable Event: resulting app, site, or document.
class WorkDeliverableEvent extends WorkAgentEvent {
  const WorkDeliverableEvent({
    required this.title,
    required this.type,
    required this.entrypoint,
    required this.files,
    required this.previewHtml,
    this.summary = '',
  });
  final String title;
  final String type; // e.g. 'web_app', 'html', 'document'
  final String entrypoint;
  final List<String> files;
  final String previewHtml;
  final String summary;
}

/// 6. Message Event: direct conversational or explanatory message from the agent.
class WorkMessageEvent extends WorkAgentEvent {
  const WorkMessageEvent({required this.content});
  final String content;
}

/// Completion Event.
class WorkDoneEvent extends WorkAgentEvent {
  const WorkDoneEvent({this.error});
  final String? error;
}

/// Parser for SSE frames from the Work agent stream.
abstract final class WorkAgentEventParser {
  static WorkAgentEvent? parseEvent(String eventType, String data) {
    if (data.trim().isEmpty) return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      switch (eventType) {
        case 'planning':
          final rawSteps = json['steps'] as List<dynamic>? ?? [];
          final steps = rawSteps
              .map((s) => WorkPlanStep.fromJson(s as Map<String, dynamic>))
              .toList();
          return WorkPlanningEvent(steps: steps);

        case 'thinking':
          return WorkThinkingEvent(
            content: json['content'] as String? ?? '',
            elapsedSeconds: json['elapsed_seconds'] as int? ?? 0,
            effort: json['effort'] as String? ?? 'medium',
          );

        case 'browsing':
          return WorkBrowsingEvent(
            url: json['url'] as String? ?? '',
            title: json['title'] as String? ?? '',
            snapshot: json['snapshot'] as String? ?? '',
            status: json['status'] as String? ?? 'browsing',
          );

        case 'coding':
          return WorkCodingEvent(
            filePath: json['filePath'] as String? ?? 'file',
            isNew: json['isNew'] as bool? ?? true,
            oldContent: json['oldContent'] as String? ?? '',
            newContent: json['newContent'] as String? ?? '',
            diff: json['diff'] as String? ?? '',
          );

        case 'terminal':
          return WorkTerminalEvent(
            command: json['command'] as String? ?? '',
            output: json['output'] as String? ?? '',
          );

        case 'deliverable':
          return WorkDeliverableEvent(
            title: json['title'] as String? ?? 'Deliverable Artifact',
            type: json['type'] as String? ?? 'web_app',
            entrypoint: json['entrypoint'] as String? ?? 'index.html',
            files:
                (json['files'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                ['index.html'],
            previewHtml: json['previewHtml'] as String? ?? '',
            summary: json['summary'] as String? ?? '',
          );

        case 'message':
          return WorkMessageEvent(
            content:
                json['content'] as String? ?? json['text'] as String? ?? '',
          );

        case 'done':
          return WorkDoneEvent(error: json['error'] as String?);

        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}
