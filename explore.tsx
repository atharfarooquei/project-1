/**
 * NABD :: Home / Explore
 *
 * One surface for everything a member can do today: venues covered by their
 * pass, the club meets happening this week, and open matches that still need
 * a player. Deliberately not a gym directory with community bolted on: the
 * community rail sits above the venue list because it is the reason the app
 * gets opened on a day when nobody intends to visit a gym.
 *
 * UAE-specific behaviour in this screen:
 *  - Gender policy is a first-class filter, surfaced without being buried in
 *    a sheet, because for a significant share of members it is the only
 *    filter that matters.
 *  - Between May and September the heat banner appears above the fold and the
 *    "indoor or shaded" filter defaults on.
 *  - Distances come from PostGIS in kilometres; nothing is computed here.
 *  - Layout direction follows the locale rather than being hard-coded LTR.
 */

import React, { useCallback, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import MapView, { Marker, PROVIDER_DEFAULT } from 'react-native-maps';

import type { Discipline, GenderPolicy, VenueSummary, VenueType } from '@nabd/shared/types';
import { isHeatSeason } from '@nabd/shared';
import { isRTL } from '@nabd/shared/i18n';

import { VenueCard } from '../../src/components/VenueCard';
import { FilterSheet } from '../../src/components/FilterSheet';
import { CommunityRail } from '../../src/components/CommunityRail';
import { HeatBanner } from '../../src/components/HeatBanner';
import {
  DEFAULT_FILTERS,
  useMemberLocation,
  useVenueDiscovery,
  type DiscoveryFilters,
} from '../../src/hooks/useVenueDiscovery';
import { useMember } from '../../src/hooks/useMember';
import { palette, radius, spacing, typography } from '../../src/theme/tokens';

type ViewMode = 'list' | 'map';

interface Category {
  key: string;
  labelKey: string;
  venueTypes?: VenueType[];
  disciplines?: Discipline[];
  /** Community categories navigate away rather than filtering the venue list. */
  route?: string;
}

const CATEGORIES: Category[] = [
  { key: 'all', labelKey: 'categories.all' },
  {
    key: 'gym',
    labelKey: 'categories.gym',
    venueTypes: ['commercial_gym', 'hotel_gym', 'multi_sport'],
  },
  { key: 'padel', labelKey: 'categories.padel', venueTypes: ['padel_club'], disciplines: ['padel'] },
  { key: 'running', labelKey: 'categories.running', route: '/community/clubs?discipline=running' },
  { key: 'cycling', labelKey: 'categories.cycling', route: '/community/clubs?discipline=cycling' },
  { key: 'events', labelKey: 'categories.events', route: '/community/events' },
  { key: 'classes', labelKey: 'categories.classes', route: '/classes' },
  {
    key: 'crossfit',
    labelKey: 'categories.crossfit',
    venueTypes: ['crossfit_box'],
    disciplines: ['crossfit', 'hyrox'],
  },
  { key: 'yoga', labelKey: 'categories.yoga', venueTypes: ['yoga_studio'], disciplines: ['yoga', 'pilates'] },
  { key: 'swimming', labelKey: 'categories.swimming', venueTypes: ['swimming_pool'], disciplines: ['swimming'] },
];

const GENDER_QUICK_FILTERS: GenderPolicy[] = ['ladies_only', 'mixed', 'men_only'];

export default function ExploreScreen() {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const rtl = isRTL(i18n.language);

  const { member } = useMember();
  const { state: locationState, coords, request: requestLocation, isPrecise } = useMemberLocation();

  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [activeCategory, setActiveCategory] = useState('all');
  const [searchTerm, setSearchTerm] = useState('');
  const [filterSheetOpen, setFilterSheetOpen] = useState(false);

  // In heat season the safe default is the one the member gets without
  // having to think about it.
  const [filters, setFilters] = useState<DiscoveryFilters>(() => ({
    ...DEFAULT_FILTERS,
    heatSafeOnly: isHeatSeason(new Date()),
  }));

  const effectiveFilters = useMemo<DiscoveryFilters>(() => {
    const category = CATEGORIES.find((c) => c.key === activeCategory);
    if (!category || category.key === 'all') return filters;
    return {
      ...filters,
      venueTypes: category.venueTypes ?? filters.venueTypes,
      disciplines: category.disciplines ?? filters.disciplines,
    };
  }, [activeCategory, filters]);

  const { venues, isLoading, error, refresh, loadMore, hasMore } = useVenueDiscovery(
    coords,
    effectiveFilters,
    searchTerm,
  );

  const onCategoryPress = useCallback(
    (category: Category) => {
      if (category.route) {
        router.push(category.route as never);
        return;
      }
      setActiveCategory(category.key);
    },
    [router],
  );

  const openVenue = useCallback(
    (venue: VenueSummary) => router.push(`/venue/${venue.slug}` as never),
    [router],
  );

  const activeFilterCount = useMemo(() => {
    let n = 0;
    if (filters.genderPolicies.length) n += 1;
    if (filters.emirate) n += 1;
    if (filters.amenities.length) n += 1;
    if (filters.openNow) n += 1;
    if (filters.heatSafeOnly) n += 1;
    if (filters.maxTier !== 'elite') n += 1;
    if (filters.radiusKm !== DEFAULT_FILTERS.radiusKm) n += 1;
    return n;
  }, [filters]);

  const toggleGenderQuickFilter = useCallback((policy: GenderPolicy) => {
    setFilters((prev) => ({
      ...prev,
      genderPolicies: prev.genderPolicies.includes(policy)
        ? prev.genderPolicies.filter((p) => p !== policy)
        : [...prev.genderPolicies, policy],
    }));
  }, []);

  const header = (
    <View>
      <View style={styles.headerBlock}>
        <Text style={[styles.greeting, rtl && styles.textRTL]}>
          {member ? t('explore.greeting') : t('explore.title')}
        </Text>
      </View>

      {/* Heat advisory sits above the fold in summer. It is the single most
          useful thing the app can tell a UAE member in August. */}
      <HeatBanner coords={coords} />

      <View style={[styles.searchRow, rtl && styles.rowRTL]}>
        <View style={[styles.searchField, rtl && styles.rowRTL]}>
          <Text style={styles.searchIcon}>{'⌕'}</Text>
          <TextInput
            value={searchTerm}
            onChangeText={setSearchTerm}
            placeholder={t('common.search')}
            placeholderTextColor={palette.textFaint}
            style={[styles.searchInput, rtl && styles.textRTL]}
            returnKeyType="search"
            accessibilityLabel={t('common.search')}
          />
        </View>

        <Pressable
          onPress={() => setFilterSheetOpen(true)}
          accessibilityRole="button"
          accessibilityLabel={t('filters.title')}
          style={[styles.filterButton, activeFilterCount > 0 && styles.filterButtonActive]}
        >
          <Text style={styles.filterButtonText}>{t('common.filters')}</Text>
          {activeFilterCount > 0 ? (
            <View style={styles.filterCount}>
              <Text style={styles.filterCountText}>{activeFilterCount}</Text>
            </View>
          ) : null}
        </Pressable>
      </View>

      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.chipRow}
        style={styles.chipScroll}
      >
        {CATEGORIES.map((category) => {
          const active = category.key === activeCategory && !category.route;
          return (
            <Pressable
              key={category.key}
              onPress={() => onCategoryPress(category)}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
              style={[styles.chip, active && styles.chipActive]}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>
                {t(category.labelKey)}
              </Text>
            </Pressable>
          );
        })}
      </ScrollView>

      {/* Community rail. Above the venue list on purpose: this is the wedge,
          and a member with no pass still has a reason to be here. */}
      <CommunityRail coords={coords} />

      {/* Gender policy is surfaced directly rather than buried in the sheet.
          For a meaningful share of members it is the only filter that
          decides whether a venue is usable at all. */}
      <View style={[styles.quickFilterRow, rtl && styles.rowRTL]}>
        {GENDER_QUICK_FILTERS.map((policy) => {
          const active = filters.genderPolicies.includes(policy);
          return (
            <Pressable
              key={policy}
              onPress={() => toggleGenderQuickFilter(policy)}
              accessibilityRole="switch"
              accessibilityState={{ checked: active }}
              style={[styles.quickFilter, active && styles.quickFilterActive]}
            >
              <Text style={[styles.quickFilterText, active && styles.quickFilterTextActive]}>
                {t(`filters.${policy}`)}
              </Text>
            </Pressable>
          );
        })}
      </View>

      <View style={[styles.listHeaderRow, rtl && styles.rowRTL]}>
        <Text style={styles.sectionTitle}>{t('explore.nearYou')}</Text>
        <View style={styles.viewToggle}>
          {(['list', 'map'] as ViewMode[]).map((mode) => (
            <Pressable
              key={mode}
              onPress={() => setViewMode(mode)}
              accessibilityRole="button"
              accessibilityState={{ selected: viewMode === mode }}
              style={[styles.viewToggleItem, viewMode === mode && styles.viewToggleItemActive]}
            >
              <Text
                style={[
                  styles.viewToggleText,
                  viewMode === mode && styles.viewToggleTextActive,
                ]}
              >
                {t(`explore.${mode}`)}
              </Text>
            </Pressable>
          ))}
        </View>
      </View>

      {!isPrecise && locationState.status !== 'requesting' ? (
        <Pressable onPress={requestLocation} style={styles.locationPrompt}>
          <Text style={styles.locationPromptText}>{t('explore.locationNeeded')}</Text>
          <Text style={styles.locationPromptAction}>{t('explore.enableLocation')}</Text>
        </Pressable>
      ) : null}
    </View>
  );

  if (viewMode === 'map') {
    return (
      <SafeAreaView style={styles.screen} edges={['top']}>
        <ScrollView stickyHeaderIndices={[]}>{header}</ScrollView>
        <MapView
          provider={PROVIDER_DEFAULT}
          style={styles.map}
          initialRegion={{
            latitude: coords.lat,
            longitude: coords.lng,
            latitudeDelta: 0.22,
            longitudeDelta: 0.22,
          }}
          showsUserLocation={isPrecise}
        >
          {venues.map((venue) => (
            <Marker
              key={venue.id}
              coordinate={{ latitude: venue.lat, longitude: venue.lng }}
              title={i18n.language === 'ar' && venue.nameAr ? venue.nameAr : venue.nameEn}
              description={`${venue.distanceKm} ${t('common.km')}`}
              // Elite supply is pinned in a cooler colour so the tier
              // difference is legible without opening anything.
              pinColor={venue.tierRequired === 'elite' ? palette.elite : palette.accent}
              onCalloutPress={() => openVenue(venue)}
            />
          ))}
        </MapView>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.screen} edges={['top']}>
      <FlatList
        data={venues}
        keyExtractor={(item) => item.id}
        ListHeaderComponent={header}
        renderItem={({ item }) => (
          <VenueCard
            venue={item}
            memberTier={member?.tier ?? 'community'}
            onPress={openVenue}
          />
        )}
        contentContainerStyle={styles.listContent}
        onEndReached={loadMore}
        onEndReachedThreshold={0.6}
        refreshControl={
          <RefreshControl
            refreshing={isLoading && venues.length > 0}
            onRefresh={refresh}
            tintColor={palette.accent}
          />
        }
        ListEmptyComponent={
          isLoading ? (
            <ActivityIndicator color={palette.accent} style={styles.spinner} />
          ) : (
            <View style={styles.empty}>
              <Text style={styles.emptyTitle}>{error ?? t('explore.noResults')}</Text>
              <Text style={styles.emptyHint}>{t('explore.noResultsHint')}</Text>
              <Pressable onPress={refresh} style={styles.emptyAction}>
                <Text style={styles.emptyActionText}>{t('common.retry')}</Text>
              </Pressable>
            </View>
          )
        }
        ListFooterComponent={
          isLoading && venues.length > 0 ? (
            <ActivityIndicator color={palette.accent} style={styles.spinner} />
          ) : !hasMore && venues.length > 0 ? (
            <Text style={styles.listEnd}>{t('explore.resultCount', { count: venues.length })}</Text>
          ) : null
        }
      />

      <FilterSheet
        visible={filterSheetOpen}
        filters={filters}
        onApply={(next) => {
          setFilters(next);
          setFilterSheetOpen(false);
        }}
        onClose={() => setFilterSheetOpen(false)}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: palette.ink900 },
  headerBlock: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
  greeting: { ...typography.title, color: palette.text },
  textRTL: { textAlign: 'right', writingDirection: 'rtl' },
  rowRTL: { flexDirection: 'row-reverse' },

  searchRow: {
    flexDirection: 'row',
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    marginTop: spacing.md,
  },
  searchField: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: palette.ink700,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: palette.border,
    paddingHorizontal: spacing.md,
    height: 44,
  },
  searchIcon: { color: palette.textFaint, fontSize: 16 },
  searchInput: { flex: 1, color: palette.text, ...typography.body },
  filterButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingHorizontal: spacing.lg,
    height: 44,
    borderRadius: radius.md,
    backgroundColor: palette.ink700,
    borderWidth: 1,
    borderColor: palette.border,
  },
  filterButtonActive: { borderColor: palette.accent },
  filterButtonText: { ...typography.bodyStrong, color: palette.text },
  filterCount: {
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: palette.accent,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  filterCountText: { ...typography.label, color: palette.ink900 },

  chipScroll: { marginTop: spacing.lg },
  chipRow: { paddingHorizontal: spacing.lg, gap: spacing.sm },
  chip: {
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    borderRadius: radius.pill,
    backgroundColor: palette.ink700,
    borderWidth: 1,
    borderColor: palette.border,
  },
  chipActive: { backgroundColor: palette.accent, borderColor: palette.accent },
  chipText: { ...typography.caption, color: palette.textMuted, fontWeight: '600' },
  chipTextActive: { color: palette.ink900 },

  quickFilterRow: {
    flexDirection: 'row',
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    marginTop: spacing.lg,
  },
  quickFilter: {
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: palette.borderStrong,
  },
  quickFilterActive: { backgroundColor: palette.accentSoft, borderColor: palette.accent },
  quickFilterText: { ...typography.caption, color: palette.textMuted },
  quickFilterTextActive: { color: palette.accent, fontWeight: '600' },

  listHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.lg,
    marginTop: spacing.xl,
    marginBottom: spacing.md,
  },
  sectionTitle: { ...typography.heading, color: palette.text },
  viewToggle: {
    flexDirection: 'row',
    backgroundColor: palette.ink700,
    borderRadius: radius.sm,
    padding: 2,
  },
  viewToggleItem: {
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
    borderRadius: radius.sm - 2,
  },
  viewToggleItemActive: { backgroundColor: palette.ink500 },
  viewToggleText: { ...typography.caption, color: palette.textFaint },
  viewToggleTextActive: { color: palette.text, fontWeight: '600' },

  locationPrompt: {
    marginHorizontal: spacing.lg,
    marginBottom: spacing.md,
    padding: spacing.md,
    borderRadius: radius.md,
    backgroundColor: palette.accentSoft,
    borderWidth: 1,
    borderColor: palette.accent,
  },
  locationPromptText: { ...typography.caption, color: palette.text },
  locationPromptAction: {
    ...typography.caption,
    color: palette.accent,
    fontWeight: '700',
    marginTop: 4,
  },

  listContent: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xxxl },
  map: { flex: 1 },
  spinner: { marginVertical: spacing.xl },
  listEnd: {
    ...typography.caption,
    color: palette.textFaint,
    textAlign: 'center',
    marginVertical: spacing.xl,
  },
  empty: { alignItems: 'center', paddingVertical: spacing.xxxl, gap: spacing.sm },
  emptyTitle: { ...typography.bodyStrong, color: palette.text },
  emptyHint: { ...typography.caption, color: palette.textFaint, textAlign: 'center' },
  emptyAction: {
    marginTop: spacing.md,
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.sm,
    borderRadius: radius.pill,
    backgroundColor: palette.ink600,
  },
  emptyActionText: { ...typography.caption, color: palette.text, fontWeight: '600' },
});
