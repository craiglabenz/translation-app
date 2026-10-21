import 'package:kaisel/kaisel.dart';

/// Base sealed route hierarchy for the application.
sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

/// Login screen route (used when [AuthPolicy.serverpod] is active).
final class LoginRoute extends AppRoute {
  const LoginRoute();
}

/// Home screen route with language pill, ripple CTA, and recent threads.
final class HomeRoute extends AppRoute {
  const HomeRoute();
}

/// Active or historical conversation route.
///
/// When [conversationId] is null, starts a brand-new translation thread.
/// When [autoStartListening] is false (e.g. opened from History), opens the
/// thread in read-only mode with a prominent Resume Listening button.
final class ChatRoute extends AppRoute {
  const ChatRoute({
    this.conversationId,
    this.autoStartListening = true,
  });

  final String? conversationId;
  final bool autoStartListening;

  @override
  List<Object?> get props => <Object?>[conversationId, autoStartListening];
}

/// Full conversation history list route.
final class HistoryRoute extends AppRoute {
  const HistoryRoute();
}

/// Settings route for language/currency pair, exchange rates, and AI model management.
final class SettingsRoute extends AppRoute {
  const SettingsRoute();
}
