import 'package:flutter/material.dart';

import '../../../../../core/design/design.dart';
import '../../../../../core/widgets/widgets.dart';
import 'vendor_profile_copy.dart';
import 'vendor_profile_initials.dart';

/// The Vendor organization the caller administers.
///
/// ## One field, from one trusted source
///
/// The only company value this product stores and displays is
/// `organizations.name`, and it reaches this widget from the **Session /
/// PortalContext** the application already resolved — never from a direct read of
/// `organizations`, and never from the administrator profile RPC, which
/// deliberately does not return it. That is why this widget takes a plain
/// `String` rather than a model: there is no company model, because there is no
/// second company field to put in one.
///
/// ## What is deliberately absent
///
/// No legal name, trading name, registration identifier, tax identifier, website,
/// business email, business phone, postal address, country, currency, logo,
/// status, created date or updated date — **no such column exists anywhere in the
/// schema**, so there is nothing to withhold and nothing to load. There is no
/// disabled text field, no placeholder dash and no "coming soon" row standing in
/// for one: a greyed-out field implies a value exists and is merely not editable
/// here, which would be untrue.
///
/// [VendorProfileCopy.companyLimitationNote] says so once, neutrally, and does
/// not read as a failure — because nothing failed, and no retry could add a
/// column the database does not have.
///
/// ## Read-only, with no affordance that suggests otherwise
///
/// No Edit button, not even a disabled one. This product has no company write
/// path at all — web or mobile — so an affordance here would advertise a
/// capability that does not exist anywhere.
class VendorProfileCompanyCard extends StatelessWidget {
  const VendorProfileCompanyCard({super.key, required this.organizationName});

  /// The trusted name, from `session.portalContext.vendor.organizationName`.
  final String organizationName;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return SrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: VendorProfileCopy.companySemantics(organizationName),
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Initials rather than a logo: there is no logo column and no
                // identity bucket in this project.
                VendorProfileAvatar(name: organizationName, tone: SrTone.slate),
                const SizedBox(width: SrSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        VendorProfileCopy.companyScopeLabel,
                        style: SrTypography.caption.copyWith(
                          color: sr.textMuted,
                        ),
                      ),
                      const SizedBox(height: SrSpacing.xxs),
                      Text(
                        organizationName,
                        style: SrTypography.sectionTitle.copyWith(
                          color: sr.foreground,
                        ),
                      ),
                      const SizedBox(height: SrSpacing.xs),
                      Text(
                        VendorProfileCopy.companySourceNote,
                        style: SrTypography.caption.copyWith(
                          color: sr.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SrSpacing.xl),
          const VendorProfileNote(
            text: VendorProfileCopy.companyLimitationNote,
          ),
        ],
      ),
    );
  }
}

/// A one-line qualifier inside a card.
///
/// An icon plus muted text, announced as a single sentence — the same treatment
/// the Dashboard uses for the one thing about its figures a reader could
/// otherwise get wrong on sight.
class VendorProfileNote extends StatelessWidget {
  const VendorProfileNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final SrColorScheme sr = context.sr;

    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: SrSpacing.xxs),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: sr.textMuted,
            ),
          ),
          const SizedBox(width: SrSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: SrTypography.caption.copyWith(color: sr.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
