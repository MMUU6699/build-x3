/// Consolidated models and provider configuration powering Build X (Chat & Work).
abstract final class BuildXConfig {
  static const providerKey = 'build_x_nvidia';
  static const legacyProviderKey = 'build_x_mistral';
  static const providerName = 'NVIDIA NIM';
  static const apiBase = 'https://integrate.api.nvidia.com/v1';
  static const chatCompletionsEndpoint = '$apiBase/chat/completions';

  // Chat Mode: z-ai/glm-5.3 (Conversational AI & Deep Reasoning)
  static const chatModelId = 'z-ai/glm-5.3';
  // Vision / Multimodal Mode: meta/llama-3.2-11b-vision-instruct
  static const visionModelId = 'meta/llama-3.2-11b-vision-instruct';
  static const chatTemperature = 0.5;
  static const chatTopP = 1.0;
  static const chatMaxTokens = 4096;
  static const chatStream = true;
  static const chatEnableThinking = false;
  static const chatSystemPrompt =
      'You are Build X, an advanced AI assistant. You converse naturally, fluently, and directly with the user.\n'
      '- When addressed in Arabic, respond in clear, natural, grammatically correct Arabic with proper RTL sentence structure. Keep technical terms clear and bilingual if needed.\n'
      '- When addressed in English, respond in natural English.\n'
      '- Always provide direct, helpful, and non-empty responses.\n'
      '- When asked about recent events or real-time data, utilize the web search tool if available.';

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
