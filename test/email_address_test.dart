import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/email_address.dart';

void main() {
  test('accepts common mailboxes and aliases', () {
    for (final email in [
      '1365511383@qq.com',
      ' First.Last+bus@Example.COM ',
      "o'connor@example.co.uk",
      'user@sub-domain.example.com',
      '${'a' * 64}@example.com',
    ]) {
      expect(isValidEmailAddress(email), isTrue, reason: email);
    }
  });
  test('rejects malformed mailbox and domain syntax and excessive lengths', () {
    for (final email in [
      '',
      'abc',
      'a@@qq.com',
      'a@qq',
      'a b@qq.com',
      '.a@qq.com',
      'a.@qq.com',
      'a..b@qq.com',
      'a@qq..com',
      'a@-qq.com',
      'a@qq-.com',
      'a@q_q.com',
      'a@qq.com.',
      'a@qq,com',
      'a@127.0.0.1',
      '名字@qq.com',
      'Name <a@qq.com>',
      'a,b@qq.com',
      'a;reply@qq.com',
      'a\r\nb@qq.com',
      '${'a' * 65}@example.com',
      'a@${'b' * 64}.com',
      '${'a' * 64}@${'b' * 63}.${'c' * 63}.${'d' * 63}.com',
    ]) {
      expect(isValidEmailAddress(email), isFalse, reason: email);
    }
  });
}
