// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_onesignal_suppression.dart';

const _loggerName = 'package.onesignal';
const _tracerName = 'dartastic_otel_libs_onesignal';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedOnesignalSend` callback.
class OnesignalSendResult<T> {
  const OnesignalSendResult({required this.value, this.notificationId});
  final T value;
  final String? notificationId;
}

/// Wraps a OneSignal server-side push send (REST notifications API)
/// in a PRODUCER span using OTel messaging semconv.
Future<T> tracedOnesignalSend<T>({
  required String appId,
  required Future<OnesignalSendResult<T>> Function() invoke,
  int? recipientCount,
  String? templateId,
}) async {
  if (onesignalInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'messaging.system': 'onesignal',
    'messaging.operation': 'publish',
    'onesignal.app.id': appId,
  };
  if (recipientCount != null) m['onesignal.recipient.count'] = recipientCount;
  if (templateId != null) m['onesignal.template.id'] = templateId;
  final span = _tracer().startSpan(
    'onesignal send',
    kind: SpanKind.producer,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.notificationId != null) {
      span.addAttributes(OTel.attributes([
        OTel.attributeString('messaging.message.id', r.notificationId!),
        OTel.attributeString('onesignal.notification.id', r.notificationId!),
      ]));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Bridges OneSignal client-side lifecycle events (click, foreground
/// will-display, dismissed, permission change, tag updates) into
/// OpenTelemetry log records.
class OTelOnesignal {
  OTelOnesignal({
    LoggerProvider? loggerProvider,
    this.forwardLogin,
    this.forwardLogout,
    this.forwardSendTag,
  }) : _loggerProvider = loggerProvider;

  final LoggerProvider? _loggerProvider;

  final void Function(String externalId)? forwardLogin;
  final void Function()? forwardLogout;
  final void Function(String key, String value)? forwardSendTag;

  OTelLogger _logger() =>
      (_loggerProvider ?? OTel.loggerProvider()).getLogger(_loggerName);

  /// Records a OneSignal notification click on-device.
  void notificationClicked({
    required String notificationId,
    String? title,
    String? body,
    Map<String, Object?>? additionalData,
  }) {
    if (onesignalInstrumentationSuppressed()) return;
    final attrs = <Attribute<Object>>[
      OTel.attributeString('onesignal.event.type', 'click'),
      OTel.attributeString('onesignal.notification.id', notificationId),
      if (title != null)
        OTel.attributeString('onesignal.notification.title', title),
      if (body != null)
        OTel.attributeString('onesignal.notification.body', body),
    ];
    if (additionalData != null) {
      additionalData.forEach((k, v) {
        if (v == null) return;
        final key = 'onesignal.data.$k';
        if (v is String) {
          attrs.add(OTel.attributeString(key, v));
        } else if (v is int) {
          attrs.add(OTel.attributeInt(key, v));
        } else if (v is double) {
          attrs.add(OTel.attributeDouble(key, v));
        } else if (v is bool) {
          attrs.add(OTel.attributeBool(key, v));
        } else {
          attrs.add(OTel.attributeString(key, v.toString()));
        }
      });
    }
    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: 'onesignal.click $notificationId',
      attributes: OTel.attributes(attrs),
    );
  }

  /// Records a OneSignal foreground will-display event.
  void willDisplay(String notificationId) {
    if (onesignalInstrumentationSuppressed()) return;
    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: 'onesignal.will_display $notificationId',
      attributes: OTel.attributes([
        OTel.attributeString('onesignal.event.type', 'will_display'),
        OTel.attributeString('onesignal.notification.id', notificationId),
      ]),
    );
  }

  /// Logs a OneSignal user login (external id).
  void login(String externalId) {
    forwardLogin?.call(externalId);
    if (onesignalInstrumentationSuppressed()) return;
    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: 'onesignal.login $externalId',
      attributes: OTel.attributes([
        OTel.attributeString('onesignal.event.type', 'login'),
        OTel.attributeString('onesignal.user.external_id', externalId),
        OTel.attributeString(User.userId.key, externalId),
      ]),
    );
  }

  /// Logs a OneSignal logout.
  void logout() {
    forwardLogout?.call();
    if (onesignalInstrumentationSuppressed()) return;
    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: 'onesignal.logout',
      attributes: OTel.attributes([
        OTel.attributeString('onesignal.event.type', 'logout'),
      ]),
    );
  }

  /// Logs a OneSignal tag set.
  void sendTag(String key, String value) {
    forwardSendTag?.call(key, value);
    if (onesignalInstrumentationSuppressed()) return;
    _logger().emit(
      severityNumber: Severity.INFO,
      severityText: 'info',
      body: 'onesignal.send_tag $key',
      attributes: OTel.attributes([
        OTel.attributeString('onesignal.event.type', 'send_tag'),
        OTel.attributeString('onesignal.tag.key', key),
        OTel.attributeString('onesignal.tag.value', value),
      ]),
    );
  }
}
