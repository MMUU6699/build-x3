/// The single consolidated model and provider powering Build X (both Chat & Work).
abstract final class BuildXConfig {
  static const providerKey = 'build_x_nvidia';
  static const legacyProviderKey = 'build_x_mistral';
  static const modelId = 'nvidia/nemotron-3-ultra-550b-a55b';
  static const apiBase = 'https://integrate.api.nvidia.com/v1';
  static const chatCompletionsEndpoint = '$apiBase/chat/completions';
  static const temperature = 0.7;
  static const maxTokens = 4096;
  static const topP = 1.0;
}
