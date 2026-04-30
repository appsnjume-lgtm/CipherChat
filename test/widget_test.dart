import 'package:flutter_test/flutter_test.dart';

import 'package:cipherchat/core/constants/app_constants.dart';

void main() {
  test('message page size stays at the secure paging default', () {
    expect(AppConstants.messagePageSize, 30);
  });
}
