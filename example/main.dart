// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_onesignal/otel_onesignal.dart';

/// Traces Onesignal calls with OpenTelemetry.
///
/// `otel_onesignal` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Onesignal call in
/// [tracedOnesignalSend]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'onesignal-example');

  // Wraps a OneSignal server-side push send (REST notifications API) in a PRODUCER span using OTel messaging semconv.
  final onesignalSendId = await tracedOnesignalSend<String>(
    appId: 'app_8f3a2c',
    recipientCount: 3,
    templateId: 'template_8f3a2c',
    invoke: () async {
      // Make the Onesignal call here, then report what it returned.
      const id = 'onesignal_8f3a2c';
      return const OnesignalSendResult(
          value: id, notificationId: 'notification_8f3a2c');
    },
  );
  OTelLog.info('tracedOnesignalSend returned $onesignalSendId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutOnesignalInstrumentationAsync.
  await runWithoutOnesignalInstrumentationAsync(
    () => tracedOnesignalSend<String>(
      appId: 'app_8f3a2c',
      recipientCount: 3,
      templateId: 'template_8f3a2c',
      invoke: () async {
        const id = 'onesignal_8f3a2c';
        return const OnesignalSendResult(
            value: id, notificationId: 'notification_8f3a2c');
      },
    ),
  );

  await OTel.shutdown();
}
