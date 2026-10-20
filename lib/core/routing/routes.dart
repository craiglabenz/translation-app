import 'package:kaisel/kaisel.dart';

sealed class AppRoute extends KaiselRoute {
  const AppRoute();
}

final class LoginRoute extends AppRoute {
  const LoginRoute();
}

final class HomeRoute extends AppRoute {
  const HomeRoute();
}
