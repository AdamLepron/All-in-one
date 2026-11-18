import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import 'ads_controller.dart';

/// True when an ad may be shown here: no purchase, consent settled. Screens
/// built without an [AdsController] (tests) simply show none.
bool adsAllowed(BuildContext context) =>
    context.watch<AdsController?>()?.canShow ?? false;

/// A thin banner, adapted to the width of the screen. It leaves no gap when
/// there is nothing to show.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _asked = false;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _load() {
    _asked = true;
    // The standard thin banner (320 × 50), the least intrusive size.
    final ad = BannerAd(
      adUnitId: AdUnits.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!adsAllowed(context)) return const SizedBox.shrink();
    if (!_asked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_asked) _load();
      });
    }
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Semantics(
      label: tr('Annonce'),
      child: Padding(
        // A gap so a tap on the bar below is never taken for a tap on the ad.
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}

/// An ad that looks like a card of the list it sits in, marked "Annonce".
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _asked = false;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _load(ColorScheme scheme) {
    _asked = true;
    final ad = NativeAd(
      adUnitId: AdUnits.native,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: scheme.surfaceContainer,
        cornerRadius: 16,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: scheme.onSurface,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: scheme.onSurfaceVariant,
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!adsAllowed(context)) return const SizedBox.shrink();
    if (!_asked) {
      final scheme = Theme.of(context).colorScheme;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_asked) _load(scheme);
      });
    }
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Annonce'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 90, maxHeight: 120),
            child: AdWidget(ad: ad),
          ),
        ],
      ),
    );
  }
}

/// Settings: remove the ads for good, restore that purchase, and reopen the
/// privacy choices where the law asks for them.
class AdsSettingsSection extends StatelessWidget {
  const AdsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ads = context.watch<AdsController?>();
    if (ads == null) return const SizedBox.shrink();
    if (ads.removed) {
      return ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: Text(tr('Publicités supprimées')),
        subtitle: Text(tr('Merci pour votre soutien !')),
      );
    }
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.block_rounded),
          title: Text(tr('Supprimer les publicités')),
          subtitle: Text(
            ads.price == null
                ? tr('Achat unique · indisponible pour le moment')
                : '${tr('Achat unique')} · ${ads.price}',
          ),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final opened = await ads.buy();
            if (!opened) {
              messenger
                ..clearSnackBars()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      tr("L'achat n'est pas disponible pour le moment"),
                    ),
                  ),
                );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.restore_rounded),
          title: Text(tr('Restaurer mon achat')),
          subtitle: Text(
            tr('Après une réinstallation ou un changement de téléphone'),
          ),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await ads.restore();
            messenger
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(tr('Vérification auprès de Google Play…')),
                ),
              );
          },
        ),
        if (ads.privacyOptionsAvailable)
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('Choix de confidentialité des annonces')),
            onTap: ads.showPrivacyOptions,
          ),
      ],
    );
  }
}
