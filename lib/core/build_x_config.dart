/// Consolidated models and provider configuration powering Build X (Chat & Work).
abstract final class BuildXConfig {
  static const providerKey = 'build_x_nvidia';
  static const legacyProviderKey = 'build_x_mistral';
  static const providerName = 'NVIDIA NIM';
  static const apiBase = 'https://integrate.api.nvidia.com/v1';
  static const chatCompletionsEndpoint = '$apiBase/chat/completions';

  // Chat Mode: Nemotron 3 Ultra 550B (Instant Conversational Sub-Second Latency)
  static const chatModelId = 'nvidia/nemotron-3-ultra-550b-a55b';
  static const chatTemperature = 0.6;
  static const chatTopP = 0.95;
  static const chatMaxTokens = 16384;
  static const chatStream = true;
  static const chatEnableThinking = false;
  static const chatSystemPrompt = 'You are a helpful assistant.';

  // Work Mode: Nemotron 3 Ultra 550B
  static const workModelId = 'nvidia/nemotron-3-ultra-550b-a55b';
  static const workTemperature = 1.0;
  static const workTopP = 0.95;
  static const workMaxTokens = 16384;
  static const workStream = true;
  static const workEnableThinking = true;

  // Defaults and backwards compatibility
  static const modelId = workModelId;
  static const temperature = 1.0;
  static const maxTokens = 16384;
  static const topP = 0.95;
  static const stream = true;
  static const thinking = true;
  static const bool enableTempChat = false;
}
