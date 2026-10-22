import 'api.dart';

class NailuPlan {
  const NailuPlan(this.data);
  final Map<String, dynamic> data;
  int get id => (data['id'] as num).toInt();
  String get name => data['name'] as String? ?? '';
  num get traffic => data['transfer_enable'] as num? ?? 0;
  num? get devices => data['device_limit'] as num?;
  num? get speed => data['speed_limit'] as num?;
  bool get soldOut =>
      data['capacity_limit'] is num && (data['capacity_limit'] as num) <= 0;
  List<String> get periods =>
      periodKeys.where((key) => data[key] is num).toList();
  bool get periodic => periods.any((key) => key != 'onetime_price');
  int price(String period) => (data[period] as num).toInt();
  String get description => (data['content'] as String? ?? '')
      .replaceAll(
        RegExp(r'<(?:br\s*/?|/p|/li|/div)>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  static const periodKeys = [
    'month_price',
    'quarter_price',
    'half_year_price',
    'year_price',
    'two_year_price',
    'three_year_price',
    'onetime_price',
  ];
}

Future<List<NailuPlan>> fetchNailuPlans(NailuApi api) async {
  final result = await api.value('user/plan/fetch', authenticated: true);
  if (result is! List) throw const NailuApiException('Invalid plan response');
  return result
      .whereType<Map>()
      .map((value) => NailuPlan(Map<String, dynamic>.from(value)))
      .where((plan) => plan.data['id'] is num && plan.periods.isNotEmpty)
      .toList();
}

String nailuBytes(num value) {
  const units = ['B', 'KB', 'GB', 'TB'];
  if (value < 1048576) {
    return '${(value / 1024).toStringAsFixed(1)} ${units[1]}';
  }
  if (value < 1099511627776) {
    return '${(value / 1073741824).toStringAsFixed(1)} ${units[2]}';
  }
  return '${(value / 1099511627776).toStringAsFixed(1)} ${units[3]}';
}
