import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:translation_app/core/data/models/app_settings.dart';
import 'package:translation_app/core/data/models/exchange_rate_cache.dart';

part 'settings_state.freezed.dart';

/// Immutable state for the settings screen and global language/currency pair.
@freezed
abstract class SettingsState with _$SettingsState {
  const SettingsState._();

  const factory SettingsState({
    @Default(AppSettings()) AppSettings settings,
    ExchangeRateCache? exchangeRate,
    @Default(false) bool isLoading,
    @Default(false) bool isRefreshingRates,
    String? error,
  }) = _SettingsState;
}
