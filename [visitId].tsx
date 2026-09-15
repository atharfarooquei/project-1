/**
 * NABD :: post-visit review composer
 *
 * The structured questions are the product. The star rating is at the
 * bottom, optional, and earns nothing, and the screen says so.
 *
 * Why it is built this way: paying for stars buys rating inflation within
 * weeks, and rating inflation destroys the discovery ranking the whole app
 * depends on. Paying for structured attributes buys something a competitor
 * cannot scrape and the next member actually needs: is it busy at 7pm, do
 * the showers work, was the ladies-hours policy honoured in practice.
 *
 * Three things on this screen are compliance features, not decoration:
 *  - the disclosure banner, which tells the member their review will be
 *    publicly labelled as incentivised
 *  - the same-coins-either-way line, which removes the incentive to be
 *    positive
 *  - the composition timer, which refuses a review tapped through in three
 *    seconds
 */

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';

import { countAnsweredAttributes, MIN_COMPOSITION_SECONDS } from '@nabd/shared';
import { isRTL } from '@nabd/shared/i18n';

import { api } from '../../src/lib/api';
import { palette, radius, spacing, typography } from '../../src/theme/tokens';

// ---------------------------------------------------------------------------
// Question set
// ---------------------------------------------------------------------------

type QuestionType = 'scale' | 'choice' | 'boolean' | 'number';

interface Question {
  key: string;
  type: QuestionType;
  labelKey: string;
  choices?: string[];
  /** Only shown for venues whose gender policy makes it meaningful. */
  showWhen?: (context: { genderPolicy: string }) => boolean;
}

const QUESTIONS: Question[] = [
  {
    key: 'busy_level',
    type: 'choice',
    labelKey: 'review.q.busy_level',
    choices: ['empty', 'quiet', 'moderate', 'busy', 'packed'],
  },
  { key: 'cleanliness', type: 'scale', labelKey: 'review.q.cleanliness' },
  { key: 'equipment_working', type: 'boolean', labelKey: 'review.q.equipment_working' },
  { key: 'wait_for_equipment_min', type: 'number', labelKey: 'review.q.wait_for_equipment' },
  { key: 'showers_clean', type: 'scale', labelKey: 'review.q.showers_clean' },
  { key: 'aircon_adequate', type: 'boolean', labelKey: 'review.q.aircon_adequate' },
  { key: 'staff_helpful', type: 'scale', labelKey: 'review.q.staff_helpful' },
  { key: 'parking_available', type: 'boolean', labelKey: 'review.q.parking_available' },
  {
    // The single most valuable question in the set. A venue that advertises
    // ladies hours and does not honour them is a serious failure, and the
    // only way to find out is to ask the people who were there.
    key: 'gender_policy_honoured',
    type: 'boolean',
    labelKey: 'review.q.gender_policy_honoured',
    showWhen: ({ genderPolicy }) => genderPolicy !== 'mixed',
  },
];

interface VisitContext {
  visitId: string;
  venueId: string;
  venueName: string;
  venueNameAr: string | null;
  genderPolicy: string;
  checkedInAt: string;
  /** Quoted by the server from the live earn rule, not hardcoded here. */
  coinsOnOffer: number;
  minAttributes: number;
  alreadyReviewed: boolean;
}

export default function ReviewComposerScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const rtl = isRTL(i18n.language);
  const { visitId } = useLocalSearchParams<{ visitId: string }>();

  const [context, setContext] = useState<VisitContext | null>(null);
  const [answers, setAnswers] = useState<Record<string, unknown>>({});
  const [body, setBody] = useState('');
  const [rating, setRating] = useState<number | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Composition timer. The server re-checks this; the client copy exists so
  // the button can explain itself rather than silently failing.
  const openedAt = useRef(Date.now());
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    const tick = setInterval(
      () => setElapsed(Math.floor((Date.now() - openedAt.current) / 1000)),
      1000,
    );
    return () => clearInterval(tick);
  }, []);

  useEffect(() => {
    void api
      .get(`/api/reviews/context?visitId=${visitId}`)
      .then(setContext)
      .catch(() => setError(t('review.loadFailed')));
  }, [visitId, t]);

  const visibleQuestions = useMemo(
    () =>
      QUESTIONS.filter(
        (q) => !q.showWhen || q.showWhen({ genderPolicy: context?.genderPolicy ?? 'mixed' }),
      ),
    [context?.genderPolicy],
  );

  const answered = countAnsweredAttributes(answers);
  const minRequired = context?.minAttributes ?? 4;
  const tooFast = elapsed < MIN_COMPOSITION_SECONDS;
  const canSubmit = answered >= minRequired && !tooFast && !submitting;

  const setAnswer = useCallback((key: string, value: unknown) => {
    setAnswers((prev) => ({ ...prev, [key]: value }));
  }, []);

  const submit = useCallback(async () => {
    if (!context || !canSubmit) return;
    setSubmitting(true);
    setError(null);

    try {
      const response = await api.post('/api/reviews', {
        visitId: context.visitId,
        subjectType: 'venue',
        subjectId: context.venueId,
        attributes: answers,
        body: body.trim() || null,
        rating,
        compositionSeconds: Math.floor((Date.now() - openedAt.current) / 1000),
        idempotencyKey: `review:${context.visitId}`,
      });

      router.replace({
        pathname: '/review/thanks',
        params: {
          coins: String(response.coinsAwarded ?? 0),
          held: response.heldForModeration ? '1' : '0',
        },
      } as never);
    } catch {
      setError(t('review.submitFailed'));
      setSubmitting(false);
    }
  }, [context, canSubmit, answers, body, rating, router, t]);

  if (!context) {
    return (
      <SafeAreaView style={[styles.screen, styles.centred]}>
        {error ? (
          <Text style={styles.error}>{error}</Text>
        ) : (
          <ActivityIndicator color={palette.accent} />
        )}
      </SafeAreaView>
    );
  }

  const venueName =
    i18n.language === 'ar' && context.venueNameAr ? context.venueNameAr : context.venueName;

  return (
    <SafeAreaView style={styles.screen}>
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Text style={[styles.title, rtl && styles.textRTL]}>
          {t('review.title', { venue: venueName })}
        </Text>
        <Text style={[styles.subtitle, rtl && styles.textRTL]}>
          {t('review.subtitle', { count: context.coinsOnOffer })}
        </Text>

        {/* Disclosure. Not optional, and not buried in a terms link: an
            undisclosed incentivised review is a consumer-protection
            exposure, and the member should know before they write. */}
        <View style={styles.disclosure}>
          <Text style={styles.disclosureText}>{t('review.disclosure')}</Text>
          <Text style={styles.disclosureEmphasis}>{t('review.sameEitherWay')}</Text>
        </View>

        <View style={styles.progressBlock}>
          <View style={styles.progressTrack}>
            <View
              style={[
                styles.progressFill,
                { width: `${Math.min(100, (answered / minRequired) * 100)}%` },
              ]}
            />
          </View>
          <Text style={styles.progressLabel}>
            {answered >= minRequired
              ? t('review.enoughAnswered', { count: context.coinsOnOffer })
              : t('review.answersNeeded', { count: minRequired - answered })}
          </Text>
        </View>

        {visibleQuestions.map((question) => (
          <View key={question.key} style={styles.question}>
            <Text style={[styles.questionLabel, rtl && styles.textRTL]}>
              {t(question.labelKey)}
            </Text>

            {question.type === 'scale' ? (
              <ScaleInput
                value={answers[question.key] as number | undefined}
                onChange={(v) => setAnswer(question.key, v)}
                rtl={rtl}
              />
            ) : null}

            {question.type === 'boolean' ? (
              <BooleanInput
                value={answers[question.key] as boolean | undefined}
                onChange={(v) => setAnswer(question.key, v)}
                yesLabel={t('common.yes')}
                noLabel={t('common.no')}
                rtl={rtl}
              />
            ) : null}

            {question.type === 'choice' ? (
              <ChoiceInput
                choices={question.choices ?? []}
                value={answers[question.key] as string | undefined}
                onChange={(v) => setAnswer(question.key, v)}
                labelFor={(c) => t(`review.choice.${c}`)}
                rtl={rtl}
              />
            ) : null}

            {question.type === 'number' ? (
              <ChoiceInput
                choices={['0', '5', '10', '15', '20']}
                value={
                  answers[question.key] !== undefined
                    ? String(answers[question.key])
                    : undefined
                }
                onChange={(v) => setAnswer(question.key, Number(v))}
                labelFor={(c) => (c === '0' ? t('review.noWait') : `${c} ${t('common.min')}`)}
                rtl={rtl}
              />
            ) : null}
          </View>
        ))}

        <View style={styles.question}>
          <Text style={[styles.questionLabel, rtl && styles.textRTL]}>
            {t('review.freeTextLabel')}
          </Text>
          <Text style={[styles.optional, rtl && styles.textRTL]}>{t('review.optional')}</Text>
          <TextInput
            value={body}
            onChangeText={setBody}
            multiline
            numberOfLines={4}
            placeholder={t('review.freeTextPlaceholder')}
            placeholderTextColor={palette.textFaint}
            style={[styles.textArea, rtl && styles.textRTL]}
          />
        </View>

        {/* Star rating last, and explicitly worth nothing. Putting it first
            would anchor the whole form on sentiment. */}
        <View style={styles.question}>
          <Text style={[styles.questionLabel, rtl && styles.textRTL]}>
            {t('review.ratingLabel')}
          </Text>
          <Text style={[styles.optional, rtl && styles.textRTL]}>
            {t('review.ratingEarnsNothing')}
          </Text>
          <View style={[styles.starRow, rtl && styles.rowRTL]}>
            {[1, 2, 3, 4, 5].map((star) => (
              <Pressable
                key={star}
                onPress={() => setRating(star === rating ? null : star)}
                accessibilityRole="radio"
                accessibilityState={{ selected: rating === star }}
                style={styles.star}
              >
                <Text
                  style={[
                    styles.starGlyph,
                    rating !== null && star <= rating && styles.starGlyphActive,
                  ]}
                >
                  {'★'}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>

        {error ? <Text style={styles.error}>{error}</Text> : null}
      </ScrollView>

      <View style={styles.footer}>
        {tooFast ? (
          <Text style={styles.footerHint}>
            {t('review.takeYourTime', { count: MIN_COMPOSITION_SECONDS - elapsed })}
          </Text>
        ) : null}
        <Pressable
          onPress={submit}
          disabled={!canSubmit}
          style={[styles.submitButton, !canSubmit && styles.submitButtonDisabled]}
        >
          {submitting ? (
            <ActivityIndicator color={palette.ink900} />
          ) : (
            <Text style={styles.submitButtonText}>
              {t('review.submit', { count: context.coinsOnOffer })}
            </Text>
          )}
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

function ScaleInput({
  value,
  onChange,
  rtl,
}: {
  value?: number;
  onChange: (v: number) => void;
  rtl: boolean;
}) {
  return (
    <View style={[styles.optionRow, rtl && styles.rowRTL]}>
      {[1, 2, 3, 4, 5].map((n) => (
        <Pressable
          key={n}
          onPress={() => onChange(n)}
          accessibilityRole="radio"
          accessibilityState={{ selected: value === n }}
          style={[styles.scaleChip, value === n && styles.optionActive]}
        >
          <Text style={[styles.optionText, value === n && styles.optionTextActive]}>{n}</Text>
        </Pressable>
      ))}
    </View>
  );
}

function BooleanInput({
  value,
  onChange,
  yesLabel,
  noLabel,
  rtl,
}: {
  value?: boolean;
  onChange: (v: boolean) => void;
  yesLabel: string;
  noLabel: string;
  rtl: boolean;
}) {
  return (
    <View style={[styles.optionRow, rtl && styles.rowRTL]}>
      {[true, false].map((option) => (
        <Pressable
          key={String(option)}
          onPress={() => onChange(option)}
          accessibilityRole="radio"
          accessibilityState={{ selected: value === option }}
          style={[styles.option, value === option && styles.optionActive]}
        >
          <Text style={[styles.optionText, value === option && styles.optionTextActive]}>
            {option ? yesLabel : noLabel}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}

function ChoiceInput({
  choices,
  value,
  onChange,
  labelFor,
  rtl,
}: {
  choices: string[];
  value?: string;
  onChange: (v: string) => void;
  labelFor: (choice: string) => string;
  rtl: boolean;
}) {
  return (
    <View style={[styles.optionRow, styles.optionWrap, rtl && styles.rowRTL]}>
      {choices.map((choice) => (
        <Pressable
          key={choice}
          onPress={() => onChange(choice)}
          accessibilityRole="radio"
          accessibilityState={{ selected: value === choice }}
          style={[styles.option, value === choice && styles.optionActive]}
        >
          <Text style={[styles.optionText, value === choice && styles.optionTextActive]}>
            {labelFor(choice)}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: palette.ink900 },
  centred: { alignItems: 'center', justifyContent: 'center' },
  content: { padding: spacing.xl, paddingBottom: spacing.xxxl, gap: spacing.lg },
  textRTL: { textAlign: 'right', writingDirection: 'rtl' },
  rowRTL: { flexDirection: 'row-reverse' },

  title: { ...typography.title, color: palette.text },
  subtitle: { ...typography.body, color: palette.textMuted },

  disclosure: {
    backgroundColor: palette.ink700,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: palette.border,
    padding: spacing.md,
    gap: spacing.xs,
  },
  disclosureText: { ...typography.caption, color: palette.textMuted },
  disclosureEmphasis: { ...typography.caption, color: palette.accent, fontWeight: '700' },

  progressBlock: { gap: spacing.sm },
  progressTrack: {
    height: 6,
    borderRadius: 3,
    backgroundColor: palette.ink600,
    overflow: 'hidden',
  },
  progressFill: { height: '100%', backgroundColor: palette.accent, borderRadius: 3 },
  progressLabel: { ...typography.caption, color: palette.textFaint },

  question: { gap: spacing.sm, marginTop: spacing.md },
  questionLabel: { ...typography.bodyStrong, color: palette.text },
  optional: { ...typography.caption, color: palette.textFaint, marginTop: -4 },

  optionRow: { flexDirection: 'row', gap: spacing.sm },
  optionWrap: { flexWrap: 'wrap' },
  option: {
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: palette.borderStrong,
  },
  scaleChip: {
    width: 48,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: palette.borderStrong,
  },
  optionActive: { backgroundColor: palette.accentSoft, borderColor: palette.accent },
  optionText: { ...typography.caption, color: palette.textMuted },
  optionTextActive: { color: palette.accent, fontWeight: '700' },

  textArea: {
    minHeight: 96,
    backgroundColor: palette.ink700,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: palette.border,
    padding: spacing.md,
    color: palette.text,
    textAlignVertical: 'top',
    ...typography.body,
  },

  starRow: { flexDirection: 'row', gap: spacing.xs },
  star: { padding: spacing.xs },
  starGlyph: { fontSize: 30, color: palette.ink500 },
  starGlyphActive: { color: palette.accent },

  error: { ...typography.caption, color: palette.danger },

  footer: {
    padding: spacing.xl,
    borderTopWidth: 1,
    borderTopColor: palette.border,
    backgroundColor: palette.ink800,
    gap: spacing.sm,
  },
  footerHint: { ...typography.caption, color: palette.textFaint, textAlign: 'center' },
  submitButton: {
    height: 50,
    borderRadius: radius.md,
    backgroundColor: palette.accent,
    alignItems: 'center',
    justifyContent: 'center',
  },
  submitButtonDisabled: { opacity: 0.35 },
  submitButtonText: { ...typography.bodyStrong, color: palette.ink900 },
});
