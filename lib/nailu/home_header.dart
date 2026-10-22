import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'account_view.dart';
import 'services_view.dart';

class NailuHomeHeader extends StatelessWidget {
  const NailuHomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: context.colorScheme.secondaryContainer,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.nailuHeroTitle,
                          style: AppTextStyle.title2.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.nailuHeroHint,
                          style: AppTextStyle.footnote.of(context),
                        ),
                      ],
                    ),
                  ),
                  ExcludeSemantics(
                    child: SvgPicture.asset(
                      'assets/images/nailu-giraffe.svg',
                      width: 110,
                      height: 110,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: ListItem.open(
                    leading: const GlyphIcon(AppGlyphs.account),
                    title: Text(s.nailuAccount),
                    widget: const NailuAccountView(),
                  ),
                ),
                Expanded(
                  child: ListItem.open(
                    leading: const GlyphIcon(AppGlyphs.profiles),
                    title: Text(s.nailuServices),
                    widget: const NailuServicesView(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
