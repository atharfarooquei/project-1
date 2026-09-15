/**
 * NABD :: Dynamic QR check-in
 *
 * Direction of scan matters, and the common design gets it backwards.
 *
 * Rejected: the member's phone displays a QR and the venue scans it. A
 * screenshot of that code is transferable, which makes account sharing
 * trivial, and it obliges every partner to buy scanning hardware.
 *
 * Adopted: the venue tablet displays a code that rotates every 30 seconds and
 * the member scans it. A photograph of the screen is worthless 30 seconds
 * later, and the only hardware a partner needs is something with a browser.
 *
 * The client deliberately decides nothing. It captures the payload and the
 * member's coordinates and posts both. Every entitlement rule runs on the
 * server, because a client that can decide it is entitled will eventually be
 * persuaded to.
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  Vibration,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Location from 'expo-location';
import * as Haptics from 'expo-haptics';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { isRTL } from '@nabd/shared/i18n';

import { api } from '../src/lib/api';
import { palette, radius, spacing, typography } from '../src/theme/tokens';

// ---------------------------------------------------------------------------
// Screen state
// ---------------------------------------------------------------------------

type ScreenState =
  | { kind: 'needs_camera' }
  | { kind: 'needs_location' }
  | { kind: 'scanning' }
  | { kind: 'verifying' }
  | { kind: 'granted'; result: CheckinSuccess }
  | { kind: 'denied'; result: CheckinFailure };

interface CheckinSuccess {
  visitId: string;
  venueName: string;
  creditsCharged: number;
  creditsRemaining: number;
  visitsUsedHere: number;
  visitsAllowedHere: number | null;
}

interface CheckinFailure {
  reason: string;
  messageKey: string;
  remedy?: 'upgrade_tier' | 'resume_subscription' | 'buy_credits' | 'try_later' | 'move_closer' | 'contact_support';
  /** Values the localised message interpolates, supplied by the server so the
   *  client never has to reconstruct them. */
  params?: Record<string, string | number>;
}

/** Payload format written by the venue tablet: v1.<venueId>.<window>.<hmac> */
const PAYLOAD_PATTERN = /^v1\.([0-9a-f-]{36})\.(\d+)\.([0-9a-f]{64})$/i;

export default function CheckinScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const rtl = isRTL(i18n.language);

  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const [state, setState] = useState<ScreenState>({ kind: 'scanning' });
  const [manualEntry, setManualEntry] = useState(false);
  const [manualCode, setManualCode] = useState('');

  // The camera fires continuously while a code is in frame. Without this the
  // same scan posts a dozen times and the idempotency key on the server ends
  // up doing work the client should never have created.
  const inFlight = useRef(false);

  useEffect(() => {
    if (cameraPermission && !cameraPermission.granted) {
      setState({ kind: 'needs_camera' });
    }
  }, [cameraPermission]);

  const submit = useCallback(
    async (payload: string) => {
      if (inFlight.current) return;
      inFlight.current = true;
      setState({ kind: 'verifying' });

      try {
        // Location is mandatory. A scan with no position is exactly the
        // remote-scan case this design exists to prevent, so we ask here
        // rather than silently submitting without it.
        const permission = await Location.getForegroundPermissionsAsync();
        if (!permission.granted) {
          const requested = await Location.requestForegroundPermissionsAsync();
          if (!requested.granted) {
            setState({ kind: 'needs_location' });
            return;
          }
        }

        const position = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.High,
        });

        const response = await api.post('/api/checkin', {
          payload,
          lat: position.coords.latitude,
          lng: position.coords.longitude,
          accuracyM: position.coords.accuracy,
          // Idempotency: a retried submission of the same scan must not
          // produce a second visit or a second credit charge.
          idempotencyKey: `${payload}:${Math.floor(Date.now() / 30_000)}`,
        });

        if (response.granted) {
          void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          setState({ kind: 'granted', result: response as CheckinSuccess });
        } else {
          void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
          Vibration.vibrate(120);
          setState({ kind: 'denied', result: response as CheckinFailure });
        }
      } catch {
        setState({
          kind: 'denied',
          result: {
            reason: 'network',
            messageKey: 'common.retry',
            remedy: 'contact_support',
          },
        });
      } finally {
        inFlight.current = false;
      }
    },
    [],
  );

  const onBarcodeScanned = useCallback(
    ({ data }: { data: string }) => {
      if (inFlight.current) return;
      if (!PAYLOAD_PATTERN.test(data)) return; // ignore unrelated QR codes silently
      void submit(data);
    },
    [submit],
  );

  const reset = useCallback(() => {
    setManualCode('');
    setManualEntry(false);
    setState({ kind: 'scanning' });
  }, []);

  // -------------------------------------------------------------------------
  // Permission gates
  // -------------------------------------------------------------------------

  if (state.kind === 'needs_camera') {
    return (
      <Gate
        title={t('checkin.cameraPermission')}
        actionLabel={t('checkin.grantCamera')}
        onPress={() => {
          void requestCameraPermission().then((r) => {
            if (r.granted) setState({ kind: 'scanning' });
          });
        }}
        onDismiss={() => router.back()}
      />
    );
  }

  if (state.kind === 'needs_location') {
    return (
      <Gate
        title={t('checkin.locationPermission')}
        actionLabel={t('checkin.grantLocation')}
        onPress={() => {
          void Location.requestForegroundPermissionsAsync().then((r) => {
            if (r.granted) setState({ kind: 'scanning' });
          });
        }}
        onDismiss={() => router.back()}
      />
    );
  }

  // -------------------------------------------------------------------------
  // Result states
  // -------------------------------------------------------------------------

  if (state.kind === 'granted') {
    const { result } = state;
    return (
      <SafeAreaView style={[styles.screen, styles.resultScreen]}>
        <View style={[styles.resultMark, styles.resultMarkSuccess]}>
          <Text style={styles.resultGlyph}>{'✓'}</Text>
        </View>

        <Text style={styles.resultTitle}>{t('checkin.success')}</Text>
        <Text style={styles.resultSubtitle}>
          {t('checkin.successAt', { venue: result.venueName })}
        </Text>

        <View style={styles.receipt}>
          {result.creditsCharged > 0 ? (
            <ReceiptRow
              label={t('checkin.creditsCharged', { count: result.creditsCharged })}
              value={t('checkin.creditsRemaining', { count: result.creditsRemaining })}
            />
          ) : null}

          {/* Showing the remaining allowance here is deliberate. A member who
              discovers their cap at the door on visit five is a complaint;
              a member who has watched it count down is not. */}
          {result.visitsAllowedHere !== null ? (
            <ReceiptRow
              label={t('checkin.visitsRemaining', {
                count: result.visitsAllowedHere - result.visitsUsedHere,
                total: result.visitsAllowedHere,
              })}
            />
          ) : null}
        </View>

        <Pressable style={styles.primaryButton} onPress={() => router.back()}>
          <Text style={styles.primaryButtonText}>{t('checkin.done')}</Text>
        </Pressable>
      </SafeAreaView>
    );
  }

  if (state.kind === 'denied') {
    const { result } = state;
    return (
      <SafeAreaView style={[styles.screen, styles.resultScreen]}>
        <View style={[styles.resultMark, styles.resultMarkDenied]}>
          <Text style={styles.resultGlyph}>{'×'}</Text>
        </View>

        {/* Never a generic "access denied". The member needs to know whether
            this is their pass, their allowance or the venue, because each one
            leads somewhere different. */}
        <Text style={styles.resultTitle}>{t(result.messageKey, result.params ?? {})}</Text>

        <View style={styles.resultActions}>
          {result.remedy ? (
            <Pressable
              style={styles.primaryButton}
              onPress={() => router.push(remedyRoute(result.remedy) as never)}
            >
              <Text style={styles.primaryButtonText}>
                {t(`checkin.remedy.${result.remedy}`)}
              </Text>
            </Pressable>
          ) : null}

          <Pressable style={styles.secondaryButton} onPress={reset}>
            <Text style={styles.secondaryButtonText}>{t('checkin.scanAgain')}</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    );
  }

  // -------------------------------------------------------------------------
  // Scanner
  // -------------------------------------------------------------------------

  return (
    <SafeAreaView style={styles.screen}>
      <View style={styles.cameraWrap}>
        {cameraPermission?.granted ? (
          <CameraView
            style={StyleSheet.absoluteFill}
            facing="back"
            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
            onBarcodeScanned={state.kind === 'scanning' ? onBarcodeScanned : undefined}
          />
        ) : (
          <View style={[StyleSheet.absoluteFill, styles.cameraPlaceholder]} />
        )}

        <View style={styles.reticleWrap} pointerEvents="none">
          <View style={styles.reticle} />
        </View>

        {state.kind === 'verifying' ? (
          <View style={styles.verifyingOverlay}>
            <ActivityIndicator color={palette.accent} size="large" />
            <Text style={styles.verifyingText}>{t('checkin.verifying')}</Text>
          </View>
        ) : null}
      </View>

      <View style={styles.instructions}>
        <Text style={[styles.instructionTitle, rtl && styles.textRTL]}>
          {t('checkin.instruction')}
        </Text>
        <Text style={[styles.instructionDetail, rtl && styles.textRTL]}>
          {t('checkin.instructionDetail')}
        </Text>

        {manualEntry ? (
          <View style={styles.manualBlock}>
            <TextInput
              value={manualCode}
              onChangeText={setManualCode}
              placeholder="v1.xxxxxxxx..."
              placeholderTextColor={palette.textFaint}
              autoCapitalize="none"
              autoCorrect={false}
              style={styles.manualInput}
            />
            <Pressable
              style={[styles.primaryButton, !PAYLOAD_PATTERN.test(manualCode) && styles.buttonDisabled]}
              disabled={!PAYLOAD_PATTERN.test(manualCode)}
              onPress={() => void submit(manualCode)}
            >
              <Text style={styles.primaryButtonText}>{t('common.apply')}</Text>
            </Pressable>
          </View>
        ) : (
          <Pressable onPress={() => setManualEntry(true)} style={styles.linkButton}>
            <Text style={styles.linkButtonText}>{t('checkin.manualEntry')}</Text>
          </Pressable>
        )}
      </View>
    </SafeAreaView>
  );
}

function remedyRoute(remedy: NonNullable<CheckinFailure['remedy']>): string {
  switch (remedy) {
    case 'upgrade_tier':
      return '/membership/plans';
    case 'resume_subscription':
      return '/membership/pause';
    case 'buy_credits':
      return '/membership/credits';
    case 'try_later':
      return '/(tabs)/explore';
    case 'move_closer':
      return '/checkin';
    case 'contact_support':
    default:
      return '/support';
  }
}

function ReceiptRow({ label, value }: { label: string; value?: string }) {
  return (
    <View style={styles.receiptRow}>
      <Text style={styles.receiptLabel}>{label}</Text>
      {value ? <Text style={styles.receiptValue}>{value}</Text> : null}
    </View>
  );
}

function Gate({
  title,
  actionLabel,
  onPress,
  onDismiss,
}: {
  title: string;
  actionLabel: string;
  onPress: () => void;
  onDismiss: () => void;
}) {
  const { t } = useTranslation();
  return (
    <SafeAreaView style={[styles.screen, styles.resultScreen]}>
      <Text style={styles.resultTitle}>{title}</Text>
      <Pressable style={styles.primaryButton} onPress={onPress}>
        <Text style={styles.primaryButtonText}>{actionLabel}</Text>
      </Pressable>
      <Pressable style={styles.linkButton} onPress={onDismiss}>
        <Text style={styles.linkButtonText}>{t('common.close')}</Text>
      </Pressable>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: palette.ink900 },
  resultScreen: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.xl,
    gap: spacing.md,
  },
  textRTL: { textAlign: 'right', writingDirection: 'rtl' },

  cameraWrap: { flex: 1, backgroundColor: '#000', overflow: 'hidden' },
  cameraPlaceholder: { backgroundColor: palette.ink800 },
  reticleWrap: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center' },
  reticle: {
    width: 240,
    height: 240,
    borderRadius: radius.xl,
    borderWidth: 3,
    borderColor: palette.accent,
    backgroundColor: 'transparent',
  },
  verifyingOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: palette.overlay,
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.md,
  },
  verifyingText: { ...typography.bodyStrong, color: palette.text },

  instructions: {
    padding: spacing.xl,
    gap: spacing.sm,
    backgroundColor: palette.ink800,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    marginTop: -radius.xl,
  },
  instructionTitle: { ...typography.heading, color: palette.text },
  instructionDetail: { ...typography.caption, color: palette.textMuted },

  manualBlock: { gap: spacing.sm, marginTop: spacing.md },
  manualInput: {
    backgroundColor: palette.ink700,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: palette.border,
    paddingHorizontal: spacing.md,
    height: 44,
    color: palette.text,
    ...typography.mono,
  },

  resultMark: {
    width: 88,
    height: 88,
    borderRadius: 44,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.sm,
  },
  resultMarkSuccess: { backgroundColor: palette.successSoft },
  resultMarkDenied: { backgroundColor: palette.dangerSoft },
  resultGlyph: { fontSize: 44, color: palette.text, fontWeight: '700' },
  resultTitle: { ...typography.title, color: palette.text, textAlign: 'center' },
  resultSubtitle: { ...typography.body, color: palette.textMuted, textAlign: 'center' },
  resultActions: { width: '100%', gap: spacing.sm, marginTop: spacing.lg },

  receipt: {
    width: '100%',
    backgroundColor: palette.ink700,
    borderRadius: radius.lg,
    padding: spacing.lg,
    gap: spacing.sm,
    marginTop: spacing.lg,
  },
  receiptRow: { flexDirection: 'row', justifyContent: 'space-between', gap: spacing.md },
  receiptLabel: { ...typography.caption, color: palette.textMuted, flex: 1 },
  receiptValue: { ...typography.caption, color: palette.text, fontWeight: '600' },

  primaryButton: {
    backgroundColor: palette.accent,
    borderRadius: radius.md,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
    width: '100%',
    marginTop: spacing.lg,
  },
  primaryButtonText: { ...typography.bodyStrong, color: palette.ink900 },
  buttonDisabled: { opacity: 0.4 },
  secondaryButton: {
    borderRadius: radius.md,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
    width: '100%',
    borderWidth: 1,
    borderColor: palette.borderStrong,
  },
  secondaryButtonText: { ...typography.bodyStrong, color: palette.text },
  linkButton: { paddingVertical: spacing.md, alignItems: 'center' },
  linkButtonText: { ...typography.caption, color: palette.accent, fontWeight: '600' },
});
