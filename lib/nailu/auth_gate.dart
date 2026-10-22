import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

import 'login_view.dart';
import 'session.dart';

class NailuAuthGate extends StatelessWidget {
  const NailuAuthGate({
    super.key,
    required this.session,
    required this.child,
    this.login,
  });

  final NailuSession session;
  final Widget child;
  final Widget? login;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final signedIn = session.phase == NailuPhase.signedIn;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: !signedIn, child: child),
          if (!signedIn)
            session.phase == NailuPhase.restoring
                ? const Scaffold(body: Center(child: CommonCircleLoading()))
                : login ?? NailuLoginView(session: session),
        ],
      );
    },
  );
}
