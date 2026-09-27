import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/work/work_agent_event.dart';
import '../services/work/work_agent_service.dart';
import '../work_mode_config.dart';

/// Manages state for Build X Work Mode vs Chat Mode.
class WorkModeProvider extends ChangeNotifier {
  WorkModeProvider({WorkAgentService? service})
    : _service = service ?? WorkAgentService();

  final WorkAgentService _service;

  AppWorkMode _currentMode = AppWorkMode.chat;
  String _selectedModel = WorkModeConfig.defaultModel;
  WorkReasoningEffort _reasoningEffort = WorkReasoningEffort.medium;

  bool _isExecuting = false;
  String _currentTask = '';
  String _responseText = '';
  String? _error;

  WorkPlanningEvent? _planningEvent;
  WorkThinkingEvent? _thinkingEvent;
  WorkBrowsingEvent? _browsingEvent;
  WorkComputerEvent? _computerEvent;
  final List<WorkToolEvent> _toolEvents = [];
  final List<WorkCodingEvent> _codingEvents = [];
  final List<WorkTerminalEvent> _terminalEvents = [];
  WorkDeliverableEvent? _deliverableEvent;

  // Getters
  AppWorkMode get currentMode => _currentMode;
  bool get isWorkMode => _currentMode.isWork;
  bool get isChatMode => _currentMode.isChat;

  String get selectedModel => _selectedModel;
  WorkReasoningEffort get reasoningEffort => _reasoningEffort;

  bool get isExecuting => _isExecuting;
  String get currentTask => _currentTask;
  String get responseText => _responseText;
  String? get error => _error;

  WorkPlanningEvent? get planningEvent => _planningEvent;
  WorkThinkingEvent? get thinkingEvent => _thinkingEvent;
  WorkBrowsingEvent? get browsingEvent => _browsingEvent;
  WorkComputerEvent? get computerEvent => _computerEvent;
  List<WorkToolEvent> get toolEvents => List.unmodifiable(_toolEvents);
  WorkToolEvent? get currentToolEvent =>
      _toolEvents.isEmpty ? null : _toolEvents.last;
  List<WorkCodingEvent> get codingEvents => List.unmodifiable(_codingEvents);
  List<WorkTerminalEvent> get terminalEvents =>
      List.unmodifiable(_terminalEvents);
  WorkDeliverableEvent? get deliverableEvent => _deliverableEvent;

  bool get hasActiveArtifact => _deliverableEvent != null;

  int get totalSteps => _planningEvent?.steps.length ?? 0;
  int get completedSteps =>
      _planningEvent?.steps
          .where((s) => s.status == WorkPlanStepStatus.completed)
          .length ??
      0;
  WorkPlanStep? get activeStep {
    if (_planningEvent == null || _planningEvent!.steps.isEmpty) return null;
    try {
      return _planningEvent!.steps.firstWhere(
        (s) => s.status == WorkPlanStepStatus.inProgress,
      );
    } catch (_) {
      return _planningEvent!.steps.last;
    }
  }

  void setMode(AppWorkMode mode) {
    if (_currentMode == mode) return;
    _currentMode = mode;
    notifyListeners();
  }

  void setSelectedModel(String model) {
    if (_selectedModel == model) return;
    _selectedModel = model;
    notifyListeners();
  }

  void setReasoningEffort(WorkReasoningEffort effort) {
    if (_reasoningEffort == effort) return;
    _reasoningEffort = effort;
    notifyListeners();
  }

  void clearSession() {
    _currentTask = '';
    _responseText = '';
    _error = null;
    _planningEvent = null;
    _thinkingEvent = null;
    _browsingEvent = null;
    _computerEvent = null;
    _toolEvents.clear();
    _codingEvents.clear();
    _terminalEvents.clear();
    _deliverableEvent = null;
    notifyListeners();
  }

  void cancelTask() {
    _service.cancel();
    _isExecuting = false;
    notifyListeners();
  }

  void startTask(String prompt) {
    clearSession();
    _isExecuting = true;
    _currentTask = prompt.trim();
    final taskTitle = prompt.trim().length > 30
        ? '${prompt.trim().substring(0, 30)}…'
        : prompt.trim();
    final plan = [
      WorkPlanStep(
        id: 1,
        title: 'Analyze requirements: $taskTitle',
        status: WorkPlanStepStatus.inProgress,
      ),
      const WorkPlanStep(
        id: 2,
        title: 'Research & architectural design',
        status: WorkPlanStepStatus.pending,
      ),
      const WorkPlanStep(
        id: 3,
        title: 'Generate solution & code',
        status: WorkPlanStepStatus.pending,
      ),
      const WorkPlanStep(
        id: 4,
        title: 'Finalize & verify deliverable',
        status: WorkPlanStepStatus.pending,
      ),
    ];
    _planningEvent = WorkPlanningEvent(steps: List.unmodifiable(plan));
    notifyListeners();
  }

  void updateTaskProgress({
    int? currentStepId,
    String? statusSummary,
    String? streamingContent,
  }) {
    if (_planningEvent != null && currentStepId != null) {
      final updatedSteps = <WorkPlanStep>[];
      for (final s in _planningEvent!.steps) {
        if (s.id < currentStepId) {
          updatedSteps.add(s.copyWith(status: WorkPlanStepStatus.completed));
        } else if (s.id == currentStepId) {
          updatedSteps.add(s.copyWith(status: WorkPlanStepStatus.inProgress));
        } else {
          updatedSteps.add(s.copyWith(status: WorkPlanStepStatus.pending));
        }
      }
      _planningEvent = WorkPlanningEvent(
        steps: List.unmodifiable(updatedSteps),
      );
    }
    if (streamingContent != null) {
      _responseText = streamingContent;
    }
    notifyListeners();
  }

  void completeTask({String? finalContent, WorkDeliverableEvent? deliverable}) {
    _isExecuting = false;
    if (_planningEvent != null) {
      final completedSteps = [
        for (final s in _planningEvent!.steps)
          s.copyWith(status: WorkPlanStepStatus.completed),
      ];
      _planningEvent = WorkPlanningEvent(
        steps: List.unmodifiable(completedSteps),
      );
    }
    if (finalContent != null && finalContent.isNotEmpty) {
      _responseText = finalContent;
    }
    if (deliverable != null) {
      _deliverableEvent = deliverable;
    }
    notifyListeners();
  }

  Future<void> runTask(String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty || _isExecuting) return;

    clearSession();
    _isExecuting = true;
    _currentTask = cleanPrompt;
    notifyListeners();

    try {
      final stream = _service.runTask(
        prompt: cleanPrompt,
        modelId: _selectedModel,
        reasoningEffort: _reasoningEffort,
      );

      await for (final event in stream) {
        if (!_isExecuting) break;

        if (event is WorkPlanningEvent) {
          _planningEvent = event;
        } else if (event is WorkThinkingEvent) {
          _thinkingEvent = event;
        } else if (event is WorkMessageEvent) {
          _responseText = event.content;
        } else if (event is WorkBrowsingEvent) {
          _browsingEvent = event;
        } else if (event is WorkComputerEvent) {
          _computerEvent = event;
        } else if (event is WorkToolEvent) {
          final existingIndex = _toolEvents.indexWhere(
            (item) => item.callId == event.callId,
          );
          if (existingIndex < 0) {
            _toolEvents.add(event);
          } else {
            _toolEvents[existingIndex] = event;
          }
        } else if (event is WorkCodingEvent) {
          _codingEvents.add(event);
        } else if (event is WorkTerminalEvent) {
          _terminalEvents.add(event);
        } else if (event is WorkDeliverableEvent) {
          _deliverableEvent = event;
        } else if (event is WorkDoneEvent) {
          if (event.error != null) {
            _error = event.error;
          }
        }
        notifyListeners();
      }
    } catch (e) {
      _error = 'Error running work agent: $e';
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }
}
