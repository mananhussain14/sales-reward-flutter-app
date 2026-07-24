import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/widgets.dart';

/// The page shown for a destination whose screen has not been built yet.
///
/// It renders the shared [SrFailureView] for a [NotImplementedFailure] rather
/// than a bespoke "coming soon" graphic, so an unbuilt screen looks exactly like
/// every other unbuilt thing in the app and cannot be mistaken for a working one
/// that happens to be empty.
///
/// [backendNote] names the backend work the screen is waiting on — an RPC or an
/// Edge Function from the feature matrix. It is developer-facing context, shown
/// so a reviewer can see *why* a destination is inert without leaving the app.
class PlaceholderDestinationPage extends StatelessWidget {
  const PlaceholderDestinationPage({
    super.key,
    required this.roleName,
    required this.title,
    required this.backendNote,
  });

  /// The owning role, rendered as the page eyebrow.
  final String roleName;

  final String title;
  final String backendNote;

  @override
  Widget build(BuildContext context) {
    return SrPageBody(
      children: <Widget>[
        SrPageHeader(eyebrow: roleName, title: title),
        const SizedBox(height: 24),
        const SrFailureView(
          failure: NotImplementedFailure(capability: 'screen'),
        ),
        const SizedBox(height: 16),
        SrSectionCard(
          title: 'Waiting on the backend',
          description: backendNote,
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
