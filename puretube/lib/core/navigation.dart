import 'package:flutter/material.dart';

/// Root navigator key for widgets mounted ABOVE the Navigator
/// (MaterialApp.builder — e.g. the floating popup player). Their own
/// contexts have no Navigator ancestor, so `Navigator.of(context)`
/// crashes from there; they push through this key instead.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();
