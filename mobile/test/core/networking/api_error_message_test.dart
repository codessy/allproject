import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/core/networking/api_error_message.dart';

void main() {
  test('apiErrorMessageFrom reads error field from dio response map', () {
    final ro = RequestOptions(path: '/v1/x');
    final err = DioException(
      requestOptions: ro,
      response: Response<dynamic>(
        requestOptions: ro,
        statusCode: 400,
        data: <String, dynamic>{'error': 'bad request'},
      ),
    );
    expect(apiErrorMessageFrom(err), 'bad request');
  });

  test('apiErrorMessageFrom returns empty for non-dio', () {
    expect(apiErrorMessageFrom(Exception('x')), '');
  });
}
