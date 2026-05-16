// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_onesignal/otel_onesignal.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;
  late InMemoryLogExporter logs;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_onesignal-test',
    );
    spans = harness.spans;
    logs = harness.logs;
  });

  setUp(() => harness.clear());

  Map<String, Object> spanAttrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};
  Map<String, Object> logAttrsOf(LogRecord r) {
    final list = r.attributes?.toList() ?? <Attribute<Object>>[];
    return {for (final a in list) a.key: a.value};
  }

  test('send emits PRODUCER span with messaging.* attrs', () async {
    await tracedOnesignalSend<String>(
      appId: 'app-1',
      recipientCount: 1000,
      templateId: 'tpl-1',
      invoke: () async => const OnesignalSendResult(
        value: 'ok',
        notificationId: 'noti-9',
      ),
    );
    final span = spans.findSpanByName('onesignal send');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.producer);
    final a = spanAttrsOf(span);
    expect(a['messaging.system'], 'onesignal');
    expect(a['messaging.operation'], 'publish');
    expect(a['onesignal.app.id'], 'app-1');
    expect(a['onesignal.recipient.count'], 1000);
    expect(a['onesignal.template.id'], 'tpl-1');
    expect(a['messaging.message.id'], 'noti-9');
    expect(a['onesignal.notification.id'], 'noti-9');
  });

  test('click emits log record', () async {
    OTelOnesignal().notificationClicked(
      notificationId: 'n-1',
      title: 'hello',
      body: 'world',
      additionalData: {'screen': 'orders', 'count': 2},
    );
    await harness.flushLogs();
    final r = logs.records.firstWhere(
      (r) => r.body == 'onesignal.click n-1',
    );
    final a = logAttrsOf(r);
    expect(a['onesignal.event.type'], 'click');
    expect(a['onesignal.notification.id'], 'n-1');
    expect(a['onesignal.notification.title'], 'hello');
    expect(a['onesignal.notification.body'], 'world');
    expect(a['onesignal.data.screen'], 'orders');
    expect(a['onesignal.data.count'], 2);
  });

  test('login records user.id and forwards', () async {
    String? fwd;
    OTelOnesignal(forwardLogin: (id) => fwd = id).login('user-5');
    await harness.flushLogs();
    expect(fwd, 'user-5');
    final r =
        logs.records.firstWhere((r) => r.body == 'onesignal.login user-5');
    final a = logAttrsOf(r);
    expect(a['onesignal.user.external_id'], 'user-5');
    expect(a['user.id'], 'user-5');
  });

  test('send records exception', () async {
    await expectLater(
      tracedOnesignalSend<String>(
        appId: 'a',
        invoke: () async => throw StateError('boom'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
        spans.findSpanByName('onesignal send')!.status, SpanStatusCode.Error);
  });

  test('suppression skips both spans and logs', () async {
    await runWithoutOnesignalInstrumentationAsync(() async {
      await tracedOnesignalSend<String>(
        appId: 'a',
        invoke: () async => const OnesignalSendResult(value: 'v'),
      );
      OTelOnesignal().notificationClicked(notificationId: 'n');
    });
    await harness.flushLogs();
    expect(spans.findSpansStartingWith('onesignal '), isEmpty);
    expect(
      logs.records.where((r) {
        final b = r.body;
        return b is String && b.startsWith('onesignal.');
      }),
      isEmpty,
    );
  });
}
