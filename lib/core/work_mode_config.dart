import 'build_x_config.dart';

/// Configuration and constants for Build X Work Mode.
abstract final class WorkModeConfig {
  static const apiBase = BuildXConfig.apiBase;
  static const chatCompletionsEndpoint = BuildXConfig.chatCompletionsEndpoint;

  /// The single consolidated model powering Work Mode and Chat Mode.
  static const modelNemotron = BuildXConfig.modelId;

  static const List<String> availableModels = [
    modelNemotron,
  ];

  static const defaultModel = modelNemotron;

  static String modelDisplayName(String modelId) {
    if (modelId == modelNemotron) {
      return 'Nemotron 3 Ultra 550B';
    }
    return modelId;
  }

  static String modelSubtitle(String modelId) {
    if (modelId == modelNemotron) {
      return '550B Reasoning & Code (NVIDIA NIM)';
    }
    return 'NVIDIA NIM';
  }

  /// LiteLLM provider prefix required by OpenHands SDK.
  static String liteLlmModel(String modelId) => 'openai/$modelId';
}

enum WorkReasoningEffort {
  low('low', 'Low', 'Fast reasoning'),
  medium('medium', 'Medium', 'Balanced thinking'),
  high('high', 'High', 'Deep reasoning'),
  standard('standard', 'Thinking', 'Reasoning enabled');

  const WorkReasoningEffort(this.apiValue, this.displayName, this.description);

  final String apiValue;
  final String displayName;
  final String description;

  static WorkReasoningEffort fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'low':
        return WorkReasoningEffort.low;
      case 'high':
        return WorkReasoningEffort.high;
      case 'medium':
      default:
        return WorkReasoningEffort.medium;
    }
  }
}

enum AppWorkMode {
  chat,
  work;

  bool get isChat => this == AppWorkMode.chat;
  bool get isWork => this == AppWorkMode.work;
}
