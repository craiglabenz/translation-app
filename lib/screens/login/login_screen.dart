import 'package:material_ui/material_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        // child: SignInWidget(
        //   client: snapshot.data!,
        //   onAuthenticated: () {
        //     context.showSnackBar(
        //       message: 'User authenticated.',
        //       backgroundColor: colors.primaryContainer,
        //       foregroundColor: colors.onPrimaryContainer,
        //     );
        //   },
        //   onError: (error) {
        //     context.showSnackBar(
        //       message: 'Authentication failed: $error',
        //       backgroundColor: colors.errorContainer,
        //       foregroundColor: colors.onErrorContainer,
        //     );
        //   },
        // ),
      ),
    );
  }
}

extension on BuildContext {
  // ignore: unused_element
  void showSnackBar({
    required String message,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: foregroundColor)),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
