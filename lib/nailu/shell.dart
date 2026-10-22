import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fl_clash/views/tools.dart';
import 'account_view.dart';
import 'config.dart';
import 'home_view.dart';
import 'plans_view.dart';

class NailuShell extends StatefulWidget {
  const NailuShell({super.key});
  @override
  State<NailuShell> createState() => _NailuShellState();
}

class _NailuShellState extends State<NailuShell> {
  int _index = 0;
  final _visited = <int>{0};
  void _select(int index) => setState(() {
    _index = index;
    _visited.add(index);
  });
  @override
  Widget build(BuildContext context) {
    final s = context.appLocalizations;
    final titles = [s.nailuHome, s.nailuPlans, s.nailuAccount];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          NailuConfig.name,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: context.colorScheme.primary),
                        ),
                        Text(
                          titles[_index],
                          style: AppTextStyle.title1.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.nailuTools,
                    onPressed: () => showExtend<void>(
                      context,
                      builder: (_) => const ToolsView(),
                    ),
                    icon: const GlyphIcon(AppGlyphs.tools),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: IndexedStack(
                    index: _index,
                    children: [
                      NailuHomeView(onPlans: () => _select(1)),
                      if (_visited.contains(1))
                        const NailuPlansView()
                      else
                        const SizedBox.shrink(),
                      if (_visited.contains(2))
                        const NailuAccountView(embedded: true)
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: NavigationDock(
                    destinations: [
                      NavigationDockDestination(
                        glyph: AppGlyphs.dashboard,
                        label: titles[0],
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.profiles,
                        label: s.nailuPlansTab,
                      ),
                      NavigationDockDestination(
                        glyph: AppGlyphs.account,
                        label: titles[2],
                      ),
                    ],
                    selectedIndex: _index,
                    onSelected: _select,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
