abstract final class NailuConfig {
  static const name = '奈鹿 NaiLu';
  static const origin = 'https://nailu.pro';
  static const api = '$origin/api/v1/';
  static const plans = '$origin/#/plans';
  static const support = '$origin/#/tickets';
  static const register = '$origin/#/register';
  static const forgot = '$origin/#/forget';
  static const challenge = '$origin/nailu-client-challenge.html';
  static const releaseRepository = String.fromEnvironment(
    'NAILU_RELEASE_REPOSITORY',
  );

  static Uri subscriptionUri(String source) {
    final uri = Uri.parse(source);
    const hosts = {
      'nailu.pro',
      'cn1.nailu.club',
      'cn2.nailu.club',
      'cn3.nailu.club',
      'cn4.nailu.pro',
      'cn5.nailu.pro',
      'cn6.nailu.pro',
    };
    if (uri.scheme != 'https' ||
        !hosts.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const FormatException('Invalid NaiLu subscription origin');
    }
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'flag': 'meta'},
    );
  }
}
