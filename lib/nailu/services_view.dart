import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'portal_view.dart';
import 'plans_view.dart';

class NailuServicesView extends StatelessWidget {
  const NailuServicesView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.appLocalizations;
    final services = [
      ('plans', s.nailuPlans, AppGlyphs.profiles),
      ('orders', s.nailuOrders, AppGlyphs.requests),
      ('notices', s.nailuNotices, AppGlyphs.send),
      ('profile', s.nailuAccount, AppGlyphs.account),
      ('tickets', s.nailuSupport, AppGlyphs.tools),
      ('invite', s.nailuInvite, AppGlyphs.link),
      ('gift', s.nailuGift, AppGlyphs.resources),
      ('help', s.nailuGuide, AppGlyphs.profiles),
      ('devices', s.nailuDevices, AppGlyphs.devices),
      ('traffic', s.nailuTraffic, AppGlyphs.speed),
      ('nodes', s.nailuNodes, AppGlyphs.proxies),
      ('diagnostics', s.nailuDiagnostics, AppGlyphs.verified),
    ];
    return CommonScaffold(
      title: s.nailuServices,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, context.appBarInset + 16, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(s.nailuServicesHint),
          ),
          for (final (route, title, glyph) in services)
            Card(
              child: ListItem.open(
                leading: GlyphIcon(glyph),
                title: Text(title),
                forceFull: true,
                widget: route == 'plans'
                    ? CommonScaffold(
                        title: title,
                        body: Padding(
                          padding: EdgeInsets.only(top: context.appBarInset),
                          child: const NailuPlansView(),
                        ),
                      )
                    : NailuPortalView(route: route, title: title),
              ),
            ),
          Card(
            child: ListItem(
              leading: const GlyphIcon(AppGlyphs.send),
              title: Text(s.nailuTelegram),
              subtitle: Text(
                NailuConfig.telegram.isEmpty
                    ? s.nailuChannelPending
                    : NailuConfig.telegram,
              ),
              onTap: () async {
                if (NailuConfig.telegram.isEmpty) {
                  await dialogs.showMessage(
                    title: s.nailuTelegram,
                    message: TextSpan(text: s.nailuChannelPending),
                  );
                  return;
                }
                final uri = Uri.parse(NailuConfig.telegram);
                if (uri.scheme == 'https' &&
                    uri.host == 't.me' &&
                    uri.userInfo.isEmpty) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
