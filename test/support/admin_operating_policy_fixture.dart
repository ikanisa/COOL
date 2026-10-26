import 'dart:convert';
import 'dart:io';

Map<String, dynamic> operatingPolicyFixture() =>
    jsonDecode(
          File(
            'test/fixtures/admin_operating_policy/current.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> policyCopy(Map<String, dynamic> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
