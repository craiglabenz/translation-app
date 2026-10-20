import 'package:material_ui/material_ui.dart';
import 'package:get_it/get_it.dart';

import '../../core/core.dart' show AuthCubit;

/// Things logged-in people see.
class HomeScreen extends StatefulWidget {
  /// Constructor.
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AuthCubit cubit;

  @override
  void initState() {
    super.initState();
    cubit = GetIt.I<AuthCubit>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('You\'re logged in!'),
      ),
    );
  }
}
