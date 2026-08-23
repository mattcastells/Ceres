/**
 * Ceres — types & interfaces (contrato de referencia).
 *
 * Aunque la app final se desarrolle en Flutter, estos tipos son el contrato canónico:
 * los modelos Dart deben mapear 1:1 (mismos nombres de campo en camelCase, mismos
 * enums, mismas nulabilidades). Ver 07-data-model.md para el mapeo a columnas.
 *
 * Convenciones:
 *  - kcal: entero. weightKg / heightCm: number con 1-2 decimales. distanceMeters: entero.
 *  - Todos los timestamps son ISO 8601 en UTC (`IsoDateTime`).
 *  - `localDate` es la fecha del usuario (`YYYY-MM-DD`), calculada con `profile.timezone`.
 */

export type Uuid = string;
export type IsoDateTime = string; // "2026-07-27T15:10:00Z"
export type IsoDate = string;     // "2026-07-27"

/* ────────────────────────────── Enums ────────────────────────────── */

export type BiologicalSex = 'male' | 'female' | 'unspecified';
export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'high' | 'very_high';
export type UnitSystem = 'metric' | 'imperial';
export type ThemeMode = 'light' | 'dark' | 'system';

export type GoalType = 'lose' | 'maintain' | 'gain';
export type TargetMethod = 'calculated' | 'manual';

export type MealSlot = 'breakfast' | 'lunch' | 'dinner' | 'snack';
export type MealSource = 'manual' | 'ai_photo' | 'barcode' | 'duplicate';
export type FoodSource = 'user' | 'usda' | 'off' | 'ai';

export type ActivityCategory = 'cardio' | 'strength' | 'mobility' | 'sports' | 'other';
export type Intensity = 'light' | 'moderate' | 'vigorous';
export type EstimationMethod = 'met' | 'provider' | 'user_override' | 'met_recalculated' | 'pace';
export type ActivitySourceType = 'manual' | 'imported' | 'template' | 'duplicated';

export type HealthProvider = 'health_connect';
export type IntegrationStatus =
  | 'not_connected' | 'connected' | 'permission_denied' | 'provider_unavailable' | 'error';

export type SyncStatus = 'synced' | 'pending' | 'syncing' | 'error' | 'needs_review';

export type ActivityGoalType =
  | 'active_minutes' | 'sessions' | 'steps' | 'distance' | 'strength_sessions' | 'active_days';

export type MeasurementMetric =
  | 'waist' | 'hip' | 'chest' | 'arm' | 'thigh' | 'neck' | 'body_fat_pct';

export type AiAnalysisStatus = 'pending' | 'completed' | 'failed' | 'accepted' | 'discarded';

/* ─────────────────────────── Core entities ─────────────────────────── */

export interface UserProfile {
  id: Uuid;
  displayName: string | null;
  avatarPath: string | null;
  biologicalSex: BiologicalSex;
  birthDate: IsoDate | null;
  heightCm: number | null;
  activityLevel: ActivityLevel;
  timezone: string;              // IANA
  unitSystem: UnitSystem;
  themeMode: ThemeMode;
  locale: string;
  /** 0–100. Cuánto del gasto estimado se suma al presupuesto diario (RN-02). Default 0. */
  exerciseCreditPercentage: number;
  exerciseCreditEnabled: boolean;
  showNetCalories: boolean;
  profileCompleted: boolean;
  deletionRequestedAt: IsoDateTime | null;
  createdAt: IsoDateTime;
  updatedAt: IsoDateTime;
}

export interface Goal {
  id: Uuid;
  userId: Uuid;
  goalType: GoalType;
  rateKgPerWeek: number;         // 0–1 (RN-13)
  targetWeightKg: number | null;
  baseCalorieTarget: number;     // 800–6000
  targetMethod: TargetMethod;
  bmrKcal: number | null;
  tdeeKcal: number | null;
  proteinG: number;
  carbsG: number;
  fatG: number;
  macroMethod: 'default' | 'custom';
  startsOn: IsoDate;
  endsOn: IsoDate | null;        // null = vigente
  createdAt: IsoDateTime;
  updatedAt: IsoDateTime;
}

export interface FoodPortion {
  label: string;                 // "1 taza", "1 rebanada"
  grams: number;
}

export interface Food {
  id: string;                    // uuid propio, o "usda:1750340" / "off:7622210449283"
  userId: Uuid | null;           // null para catálogos externos
  name: string;
  brand: string | null;
  barcode: string | null;
  source: FoodSource;
  externalId: string | null;
  servingSize: number;
  servingUnit: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  fiberG: number | null;
  sugarG: number | null;
  sodiumMg: number | null;
  portions: FoodPortion[];
  nutrients: Record<string, number> | null;
  isFavorite: boolean;
  createdAt: IsoDateTime;
  updatedAt: IsoDateTime;
  deletedAt: IsoDateTime | null;
}

export interface MealItem {
  id: Uuid;
  mealId: Uuid;
  foodId: string | null;
  /** Snapshot: el nombre no cambia si el alimento de origen se edita después. */
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  aiConfidence: number | null;   // 0–1
  wasAiCorrected: boolean;
  position: number;
}

export interface Meal {
  id: Uuid;
  userId: Uuid;
  slot: MealSlot;
  loggedAt: IsoDateTime;
  localDate: IsoDate;
  name: string | null;
  items: MealItem[];
  totalKcal: number;
  totalProteinG: number;
  totalCarbsG: number;
  totalFatG: number;
  source: MealSource;
  aiAnalysisId: Uuid | null;
  photoPath: string | null;
  notes: string | null;
  isFavorite: boolean;
  syncStatus: SyncStatus;
  createdAt: IsoDateTime;
  updatedAt: IsoDateTime;
  deletedAt: IsoDateTime | null;
}

export interface ActivityType {
  id: Uuid;
  slug: string;
  displayName: string;
  category: ActivityCategory;
  defaultMet: number;
  lightMet: number | null;
  moderateMet: number | null;
  vigorousMet: number | null;
  supportsDistance: boolean;
  supportsSteps: boolean;
  supportsHeartRate: boolean;
  iconName: string;              // Phosphor
  isSystem: boolean;
  userId: Uuid | null;
}

export interface Activity {
  id: Uuid;
  userId: Uuid;
  activityTypeId: Uuid;
  activityType?: ActivityType;   // hidratado en lectura
  customName: string | null;
  startedAt: IsoDateTime;
  endedAt: IsoDateTime | null;
  localDate: IsoDate;
  durationMinutes: number;       // 1–1440
  intensity: Intensity;
  distanceMeters: number | null;
  steps: number | null;
  averageHeartRate: number | null;
  maximumHeartRate: number | null;
  /** Valor vigente; puede ser el corregido por el usuario. Siempre se muestra con "≈". */
  estimatedCalories: number;
  /** Valor calculado antes de un override. Nunca se pierde (RN-04). */
  originalCalories: number | null;
  /** Lo que efectivamente suma al objetivo del día (RN-02). */
  appliedCalories: number;
  /** Porcentaje congelado al momento de guardar. */
  exerciseCreditPercentage: number;
  estimationMethod: EstimationMethod;
  metValue: number | null;
  weightKgUsed: number | null;
  overrideReason: string | null;
  sourceType: ActivitySourceType;
  externalSource: string | null;
  externalId: string | null;
  sourceUpdatedAt: IsoDateTime | null;
  userEdited: boolean;
  notes: string | null;
  photoPath: string | null;
  deviceName: string | null;
  isFavorite: boolean;
  syncStatus: SyncStatus;
  createdAt: IsoDateTime;
  updatedAt: IsoDateTime;
  deletedAt: IsoDateTime | null;
}

export interface ExerciseTemplate {
  id: Uuid;
  userId: Uuid;
  name: string;
  activityTypeId: Uuid;
  defaultDurationMinutes: number;
  defaultIntensity: Intensity;
  defaultDistanceMeters: number | null;
  defaultNotes: string | null;
  useCount: number;
}

export interface ActivityGoal {
  id: Uuid;
  userId: Uuid;
  goalType: ActivityGoalType;
  targetValue: number;
  unit: 'minutes' | 'count' | 'steps' | 'meters' | 'days';
  period: 'day' | 'week';
  startDate: IsoDate;
  endDate: IsoDate | null;
  enabled: boolean;
}

export interface WeightLog {
  id: Uuid;
  userId: Uuid;
  weightKg: number;              // 25–400
  localDate: IsoDate;
  loggedAt: IsoDateTime;
  source: 'manual' | 'imported';
  externalSource: string | null;
  externalId: string | null;
  notes: string | null;
  photoPath: string | null;
  syncStatus: SyncStatus;
}

export interface BodyMeasurement {
  id: Uuid;
  userId: Uuid;
  metric: MeasurementMetric;
  value: number;
  unit: 'cm' | 'pct';
  localDate: IsoDate;
  notes: string | null;
}

export interface AiAnalysisItem {
  name: string;
  quantity: number;
  unit: string;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  confidence: number;            // 0–1
  matchedFood: { source: FoodSource; externalId: string } | null;
}

export interface AiAnalysis {
  id: Uuid;
  userId: Uuid;
  photoPath: string;
  status: AiAnalysisStatus;
  model: string;
  promptVersion: string;
  items: AiAnalysisItem[];
  confidenceAvg: number;
  latencyMs: number;
  errorCode: string | null;
  /** Diff entre lo propuesto y lo guardado; insumo para mejorar el prompt. */
  corrections: {
    itemsEdited: number; itemsRemoved: number; itemsAdded: number; kcalDelta: number;
  } | null;
  createdAt: IsoDateTime;
}

export interface HealthIntegration {
  id: Uuid;
  userId: Uuid;
  provider: HealthProvider;
  status: IntegrationStatus;
  permissions: string[];
  lastSyncAt: IsoDateTime | null;
  syncCursor: string | null;
  lastError: string | null;
  connectedAt: IsoDateTime | null;
  disconnectedAt: IsoDateTime | null;
  importedCount: number;
}

export interface SyncRecord {
  id: Uuid;
  userId: Uuid;
  provider: HealthProvider;
  entityType: 'activity' | 'weight' | 'steps' | 'heart_rate';
  externalId: string;
  localEntityId: Uuid | null;
  sourceUpdatedAt: IsoDateTime;
  syncedAt: IsoDateTime;
  syncHash: string;
  skippedReason: string | null;
}

/* ───────────────────────── Aggregates / views ───────────────────────── */

export interface MacroProgress { current: number; target: number }

export interface DailySummary {
  date: IsoDate;
  baseTarget: number;
  consumedKcal: number;
  exerciseEstimatedKcal: number;
  exerciseAppliedKcal: number;
  creditPercentage: number;
  creditEnabled: boolean;
  adjustedTarget: number;        // baseTarget + exerciseAppliedKcal
  remainingKcal: number;         // adjustedTarget - consumedKcal
  netKcal: number;               // consumedKcal - exerciseAppliedKcal (RN-11)
  macros: { protein: MacroProgress; carbs: MacroProgress; fat: MacroProgress };
  meals: Meal[];
  activities: Activity[];
  activityTotals: { minutes: number; sessions: number; steps: number | null };
  weight: { weightKg: number; deltaKg: number } | null;
  isRestDay: boolean;
}

export interface ProgressSummary {
  range: { from: IsoDate; to: IsoDate; days: number };
  weight: {
    points: { date: IsoDate; kg: number }[];
    movingAverage7: { date: IsoDate; kg: number }[];
    deltaKg: number;
    trendKgPerWeek: number;
  };
  calories: {
    days: { date: IsoDate; consumed: number; target: number; exerciseApplied: number }[];
    averageConsumed: number;
    adherencePct: number;
  };
  activity: {
    byDay: { date: IsoDate; minutes: number; calories: number; sessions: number }[];
    byCategory: { category: ActivityCategory; minutes: number }[];
    totals: {
      minutes: number; sessions: number; avgDurationMinutes: number;
      estimatedCalories: number; activeDays: number;
      mostFrequentTypeSlug: string | null; longestSessionMinutes: number;
    };
    weeklyAverageMinutes: number;
    previousWeekDeltaMinutes: number;
    stepsAverage: number | null;
  };
  goals: (ActivityGoal & { currentValue: number })[];
}

export interface HistoryDay {
  date: IsoDate;
  consumedKcal: number;
  activityKcal: number;
  appliedKcal: number;
  baseTarget: number;
  balanceKcal: number;
  exerciseMinutes: number;
  activityCount: number;
  steps: number | null;
  isRestDay: boolean;
  hasRecords: boolean;
}

/* ─────────────────────────── API envelope ─────────────────────────── */

export type ApiErrorCode =
  | 'ERR_UNAUTHENTICATED' | 'ERR_FORBIDDEN' | 'ERR_NOT_FOUND' | 'ERR_VALIDATION'
  | 'ERR_CONFLICT' | 'ERR_RATE_LIMITED' | 'ERR_QUOTA_EXCEEDED' | 'ERR_UPSTREAM_TIMEOUT'
  | 'ERR_UPSTREAM_FAILED' | 'ERR_AI_INVALID_RESPONSE' | 'ERR_AI_NO_FOOD'
  | 'ERR_PERMISSION_DENIED' | 'ERR_PROVIDER_UNAVAILABLE' | 'ERR_SYNC_FAILED'
  | 'ERR_OFFLINE' | 'ERR_SERVER';

export interface ApiError {
  code: ApiErrorCode;
  message: string;
  details?: { fields?: Record<string, string>; [k: string]: unknown };
  requestId: string;
}

export interface ApiResponse<T> {
  data: T;
  meta?: { requestId: string; durationMs?: number; degraded?: boolean; idempotentHit?: boolean };
}

export type Result<T> = { ok: true; value: T } | { ok: false; error: ApiError };

export interface Page<T> { items: T[]; nextCursor: string | null }

/* ─────────────────────────── Form inputs ─────────────────────────── */

export interface SignUpInput { email: string; password: string; acceptedTerms: boolean }
export interface SignInInput { email: string; password: string }

export interface OnboardingInput {
  goalType: GoalType;
  biologicalSex: BiologicalSex;
  birthDate: IsoDate;
  heightCm: number;
  weightKg: number;
  activityLevel: ActivityLevel;
  rateKgPerWeek: number;
  targetMethod: TargetMethod;
  manualTarget?: number;
  exerciseCreditPercentage: number;
}

export interface CreateMealInput {
  id: Uuid; slot: MealSlot; loggedAt: IsoDateTime; localDate: IsoDate;
  source: MealSource; aiAnalysisId?: Uuid | null; photoPath?: string | null;
  items: Omit<MealItem, 'mealId'>[];
}
export interface UpdateMealInput extends Partial<Omit<CreateMealInput, 'id'>> { id: Uuid }

export interface CreateActivityInput {
  id: Uuid;
  activityTypeId: Uuid;
  customName?: string | null;
  startedAt: IsoDateTime;
  endedAt?: IsoDateTime | null;
  localDate: IsoDate;
  durationMinutes: number;
  intensity: Intensity;
  distanceMeters?: number | null;
  steps?: number | null;
  averageHeartRate?: number | null;
  maximumHeartRate?: number | null;
  estimatedCalories: number;
  originalCalories?: number | null;
  estimationMethod: EstimationMethod;
  metValue?: number | null;
  weightKgUsed?: number | null;
  overrideReason?: string | null;
  sourceType: ActivitySourceType;
  notes?: string | null;
  photoPath?: string | null;
}
export interface UpdateActivityInput extends Partial<Omit<CreateActivityInput, 'id'>> {}

export interface LogWeightInput {
  id: Uuid; weightKg: number; localDate: IsoDate; notes?: string | null; photoPath?: string | null;
}

export interface DuplicateResolutionInput {
  incomingExternalId: string;
  existingActivityId: Uuid;
  resolution: 'keep_incoming' | 'keep_existing' | 'keep_both' | 'defer';
}

export interface HistoryFilters {
  from: IsoDate; to: IsoDate;
  include?: ('meals' | 'activities')[];
  activitySource?: ('manual' | 'imported')[];
  activityTypeIds?: Uuid[];
}

/* ───────────────────────── Service interfaces ───────────────────────── */

export interface AuthService {
  signUp(input: SignUpInput): Promise<Result<{ userId: Uuid; needsEmailConfirmation: boolean }>>;
  signIn(input: SignInInput): Promise<Result<{ userId: Uuid }>>;
  signOut(): Promise<void>;
  requestPasswordReset(email: string): Promise<Result<void>>;
  reauthenticate(password: string): Promise<Result<void>>;
  currentUserId(): Uuid | null;
}

export interface ProfileService {
  getProfile(): Promise<Result<UserProfile>>;
  updateProfile(patch: Partial<UserProfile>): Promise<Result<UserProfile>>;
  completeOnboarding(input: OnboardingInput): Promise<Result<{ profile: UserProfile; goal: Goal }>>;
  setExerciseCredit(percentage: number, enabled: boolean): Promise<Result<UserProfile>>;
  deleteAccount(): Promise<Result<{ scheduledFor: IsoDateTime }>>;
  exportData(): Promise<Result<{ requested: true }>>;
}

export interface GoalService {
  getCurrentGoal(): Promise<Result<Goal>>;
  setGoal(input: Omit<Goal, 'id' | 'userId' | 'createdAt' | 'updatedAt' | 'endsOn'>): Promise<Result<Goal>>;
  getGoalForDate(date: IsoDate): Promise<Result<Goal>>;
}

export interface FoodSearchService {
  search(query: string, opts?: { limit?: number; cursor?: string }): Promise<Result<Page<Food>>>;
  getDetail(source: FoodSource, externalId: string): Promise<Result<Food>>;
  lookupBarcode(ean: string): Promise<Result<Food>>;
  recent(): Promise<Result<Food[]>>;
  favorites(): Promise<Result<Food[]>>;
  createOwnFood(input: Omit<Food, 'id' | 'createdAt' | 'updatedAt' | 'deletedAt'>): Promise<Result<Food>>;
}

export interface MealService {
  createMeal(input: CreateMealInput): Promise<Result<Meal>>;
  updateMeal(input: UpdateMealInput): Promise<Result<Meal>>;
  deleteMeal(id: Uuid): Promise<Result<void>>;
  restoreMeal(id: Uuid): Promise<Result<Meal>>;
  getMeal(id: Uuid): Promise<Result<Meal>>;
  getMealsByDate(date: IsoDate): Promise<Result<Meal[]>>;
  duplicateMeal(id: Uuid, date: IsoDate, slot: MealSlot): Promise<Result<Meal>>;
}

export interface AiAnalysisService {
  analyzePhoto(input: { analysisId: Uuid; photoPath: string; localDate: IsoDate; hintSlot?: MealSlot }):
    Promise<Result<AiAnalysis>>;
  acceptAnalysis(analysisId: Uuid, corrections: AiAnalysis['corrections']): Promise<Result<void>>;
  discardAnalysis(analysisId: Uuid): Promise<Result<void>>;
  remainingQuota(): Promise<Result<{ used: number; limit: number; resetAt: IsoDateTime }>>;
}

export interface ActivityService {
  createActivity(input: CreateActivityInput): Promise<Result<Activity>>;
  updateActivity(id: Uuid, input: UpdateActivityInput): Promise<Result<Activity>>;
  deleteActivity(id: Uuid): Promise<Result<void>>;
  restoreActivity(id: Uuid): Promise<Result<Activity>>;
  getActivity(id: Uuid): Promise<Result<Activity>>;
  getActivitiesByDate(date: IsoDate): Promise<Result<Activity[]>>;
  duplicateActivity(id: Uuid, date: IsoDate): Promise<Result<Activity>>;
  toggleFavorite(id: Uuid, isFavorite: boolean): Promise<Result<Activity>>;
  overrideCalories(id: Uuid, calories: number, reason?: string): Promise<Result<Activity>>;
  restoreCalculatedCalories(id: Uuid): Promise<Result<Activity>>;
  recent(limit?: number): Promise<Result<Activity[]>>;
  favorites(): Promise<Result<Activity[]>>;
}

export interface ActivityCatalogService {
  getTypes(): Promise<Result<ActivityType[]>>;
  searchTypes(query: string): Promise<Result<ActivityType[]>>;
  createCustomType(input: Omit<ActivityType, 'id' | 'isSystem' | 'userId'>): Promise<Result<ActivityType>>;
  metFor(typeId: Uuid, intensity: Intensity): Promise<Result<number>>;
}

export interface ExerciseCalculationService {
  /** caloriasPorMinuto = MET × 3,5 × pesoKg ÷ 200 ; × duración. Redondeo half-up al entero. */
  calculateCaloriesFromMet(input: { met: number; weightKg: number; durationMinutes: number }): number;
  /** applied = round(estimated × credit/100). Devuelve 0 si el crédito está desactivado. */
  calculateAppliedExerciseCalories(input: { estimatedCalories: number; creditPercentage: number }): number;
  /** adjusted = base + applied */
  calculateAdjustedCalorieTarget(input: { baseTarget: number; appliedExerciseCalories: number }): number;
  /** remaining = adjustedTarget − consumed */
  calculateRemainingCalories(input: { adjustedTarget: number; consumedKcal: number }): number;
  /** net = consumed − applied (RN-11) */
  calculateNetCalories(input: { consumedKcal: number; appliedExerciseCalories: number }): number;
  /** Estimación por ritmo para caminata/carrera cuando hay distancia y duración. */
  estimateMetFromPace(input: { distanceMeters: number; durationMinutes: number; typeSlug: string }): number;
}

export interface BodyCalculationService {
  bmrMifflinStJeor(input: { weightKg: number; heightCm: number; ageYears: number; sex: BiologicalSex }): number;
  tdee(input: { bmr: number; activityLevel: ActivityLevel }): number;
  calorieTarget(input: { tdee: number; goalType: GoalType; rateKgPerWeek: number; sex: BiologicalSex }): number;
  macroTargets(input: { targetKcal: number; weightKg: number; goalType: GoalType }):
    { proteinG: number; carbsG: number; fatG: number };
  bmi(input: { weightKg: number; heightCm: number }): number;
  movingAverage(points: { date: IsoDate; value: number }[], window: number): { date: IsoDate; value: number }[];
  weightTrendKgPerWeek(points: { date: IsoDate; kg: number }[]): number;
  adherencePct(days: { consumed: number; target: number }[], tolerancePct?: number): number;
}

export interface ExerciseTemplateService {
  list(): Promise<Result<ExerciseTemplate[]>>;
  create(input: Omit<ExerciseTemplate, 'id' | 'userId' | 'useCount'>): Promise<Result<ExerciseTemplate>>;
  update(id: Uuid, patch: Partial<ExerciseTemplate>): Promise<Result<ExerciseTemplate>>;
  delete(id: Uuid): Promise<Result<void>>;
  instantiate(id: Uuid, date: IsoDate): Promise<Result<CreateActivityInput>>;
}

export interface ActivityGoalService {
  list(): Promise<Result<(ActivityGoal & { currentValue: number })[]>>;
  upsert(goal: Omit<ActivityGoal, 'id' | 'userId'> & { id?: Uuid }): Promise<Result<ActivityGoal>>;
  setEnabled(id: Uuid, enabled: boolean): Promise<Result<ActivityGoal>>;
  delete(id: Uuid): Promise<Result<void>>;
}

export interface HealthIntegrationService {
  list(): Promise<Result<HealthIntegration[]>>;
  isAvailable(provider: HealthProvider): Promise<boolean>;
  requiredPermissions(provider: HealthProvider): string[];
  requestPermissions(provider: HealthProvider): Promise<Result<{ granted: string[]; denied: string[] }>>;
  disconnect(provider: HealthProvider): Promise<Result<void>>;
  deleteImportedData(provider: HealthProvider): Promise<Result<{ deleted: number }>>;
}

export interface SyncResult {
  imported: number;
  updated: number;
  skipped: number;
  skippedReasons: Record<string, number>;
  duplicateCandidates: DuplicateCandidate[];
  lastSyncAt: IsoDateTime;
}

export interface HealthSyncService {
  connect(provider: HealthProvider): Promise<Result<void>>;
  disconnect(provider: HealthProvider): Promise<Result<void>>;
  sync(provider: HealthProvider): Promise<Result<SyncResult>>;
  resolveDuplicate(input: DuplicateResolutionInput): Promise<Result<void>>;
  pendingReviews(): Promise<Result<DuplicateCandidate[]>>;
}

export interface DuplicateCandidate {
  incoming: Partial<Activity> & { externalId: string };
  existing: Activity;
  matchScore: number;            // 0–1, ver 11-calculation-rules.md §12
  reasons: ('external_id' | 'time_overlap' | 'same_type' | 'similar_duration' | 'similar_calories')[];
}

export interface DuplicateDetectionService {
  check(candidate: CreateActivityInput & { externalSource?: string; externalId?: string }):
    Promise<Result<DuplicateCandidate[]>>;
  score(a: Activity, b: Activity): number;
}

export interface PermissionService {
  status(permission: 'camera' | 'photos' | 'notifications' | 'health'): Promise<'granted' | 'denied' | 'undetermined'>;
  request(permission: 'camera' | 'photos' | 'notifications' | 'health'): Promise<'granted' | 'denied'>;
  openSettings(): Promise<void>;
}

export interface SummaryService {
  getDailySummary(date: IsoDate): Promise<Result<DailySummary>>;
  getProgress(from: IsoDate, to: IsoDate): Promise<Result<ProgressSummary>>;
  getHistory(filters: HistoryFilters, cursor?: string): Promise<Result<Page<HistoryDay>>>;
  setRestDay(date: IsoDate, isRest: boolean): Promise<Result<void>>;
}

export interface AnalyticsService {
  track(event: string, properties?: Record<string, string | number | boolean | null>): void;
  identify(userId: Uuid, traits?: Record<string, unknown>): void;
  reset(): void;
}

export interface SyncQueueService {
  enqueue(op: { entity: string; id: Uuid; action: 'create' | 'update' | 'delete'; payload: unknown }): Promise<void>;
  pendingCount(): Promise<number>;
  flush(): Promise<{ succeeded: number; failed: number }>;
  onStatusChange(cb: (status: { online: boolean; pending: number }) => void): () => void;
}
