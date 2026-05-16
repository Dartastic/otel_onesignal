// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

const Symbol _suppressKey = #dartastic_otel_libs_onesignal_suppress;

bool onesignalInstrumentationSuppressed() {
  return Zone.current[_suppressKey] == true;
}

T runWithoutOnesignalInstrumentation<T>(T Function() body) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}

Future<T> runWithoutOnesignalInstrumentationAsync<T>(
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}
