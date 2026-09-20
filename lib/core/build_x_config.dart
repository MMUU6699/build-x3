/// The only chat model and provider available in Build X.
abstract final class BuildXConfig {
  static const providerKey = 'build_x_mistral';
  static const modelId = 'mistral-medium-latest';
  static const apiBase = 'https://api.mistral.ai/v1/conversations';
  static const temperature = 0.7;
  static const maxTokens = 2048;
  static const topP = 1.0;
}
